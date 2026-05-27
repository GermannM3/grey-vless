import threading
from typing import Callable, Optional

from .models import Server
from .paths import singbox_binary
from .ping import tcp_ping
from .proxy import SystemProxy
from .runner import SingBoxRunner
from .settings import AppSettings

LOCAL_PORT = 7890


class ConnectionManager:
    def __init__(self, settings: AppSettings):
        self.settings = settings
        self.runner = SingBoxRunner(singbox_binary(), LOCAL_PORT)
        self.system_proxy = SystemProxy(port=LOCAL_PORT)
        self.connected_server: Optional[Server] = None
        self._lock = threading.Lock()

    @property
    def is_connected(self) -> bool:
        return self.runner.is_running

    def connect(self, server: Server) -> None:
        with self._lock:
            self.runner.start(server, tun_mode=self.settings.tun_mode)
            if not self.settings.tun_mode:
                self.system_proxy.enable()
            self.connected_server = server

    def disconnect(self) -> None:
        with self._lock:
            self.runner.stop()
            if not self.settings.tun_mode:
                self.system_proxy.disable()
            self.connected_server = None

    def ping_all(self, servers: list[Server]) -> None:
        for server in servers:
            try:
                server.ping_ms = tcp_ping(server.host, server.port)
                server.ping_error = None
            except OSError:
                server.ping_ms = None
                server.ping_error = "нет связи"

    def best_server(self, servers: list[Server]) -> Optional[Server]:
        reachable = [s for s in servers if s.ping_ms is not None]
        if not reachable:
            return None
        return min(reachable, key=lambda s: s.ping_ms or 999999)

    def ping_and_connect_best(
        self,
        servers: list[Server],
        on_done: Callable[[Optional[Server], Optional[str]], None],
    ) -> None:
        def worker() -> None:
            try:
                self.ping_all(servers)
                server = self.best_server(servers)
                if server is None:
                    on_done(None, "Нет доступных серверов")
                    return
                self.connect(server)
                on_done(server, None)
            except Exception as exc:
                on_done(None, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def connect_async(
        self,
        server: Server,
        on_done: Callable[[Optional[str]], None],
    ) -> None:
        def worker() -> None:
            try:
                self.connect(server)
                on_done(None)
            except Exception as exc:
                on_done(str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def shutdown(self) -> None:
        self.disconnect()

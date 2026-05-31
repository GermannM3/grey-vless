import json
import os
import signal
import socket
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Optional

from .models import Server
from .singbox_config import LOCAL_PORT, build_config


class SingBoxRunner:
    def __init__(self, singbox_path: Path, local_port: int = LOCAL_PORT):
        self.singbox_path = singbox_path
        self.local_port = local_port
        self._process: Optional[subprocess.Popen] = None
        self._config_path: Optional[Path] = None
        self._log_path: Optional[Path] = None

    @property
    def is_running(self) -> bool:
        if self._process is None or self._process.poll() is not None:
            return False
        return self._port_open()

    def _port_open(self) -> bool:
        try:
            with socket.create_connection(("127.0.0.1", self.local_port), timeout=0.4):
                return True
        except OSError:
            return False

    def _read_log_tail(self, limit: int = 900) -> str:
        if not self._log_path or not self._log_path.exists():
            return ""
        content = self._log_path.read_text(encoding="utf-8", errors="ignore").strip()
        if not content:
            return ""
        return content[-limit:]

    def start(self, server: Server, tun_mode: bool = False) -> None:
        if self.is_running:
            self.stop()

        if not self.singbox_path.exists():
            raise FileNotFoundError(f"sing-box не найден: {self.singbox_path}")

        config = build_config(server, self.local_port, tun_mode=tun_mode)
        fd, path = tempfile.mkstemp(prefix="grey-vless-", suffix=".json")
        os.close(fd)
        self._config_path = Path(path)
        self._config_path.write_text(json.dumps(config, indent=2), encoding="utf-8")
        log_fd, log_path = tempfile.mkstemp(prefix="grey-vless-", suffix=".log")
        os.close(log_fd)
        self._log_path = Path(log_path)

        check = subprocess.run(
            [str(self.singbox_path), "check", "-c", str(self._config_path)],
            capture_output=True,
            text=True,
        )
        if check.returncode != 0:
            err = (check.stderr or check.stdout or "").strip()
            raise RuntimeError(f"Конфиг sing-box невалиден: {err[:600]}")

        log_handle = self._log_path.open("a", encoding="utf-8")
        self._process = subprocess.Popen(
            [str(self.singbox_path), "run", "-c", str(self._config_path)],
            stdout=log_handle,
            stderr=log_handle,
            preexec_fn=os.setsid,
        )
        log_handle.close()

        for _ in range(20):
            time.sleep(0.15)
            if self._process.poll() is not None:
                break
            if self._port_open():
                return

        if self._process.poll() is not None:
            details = self._read_log_tail()
            hint = ""
            if tun_mode and "operation not permitted" in details.lower():
                hint = "\nTUN нужны права: sudo setcap cap_net_admin,cap_net_bind_service+ep /opt/grey-vless/bin/sing-box"
            raise RuntimeError(
                f"sing-box не запустился.{hint}\n{details or 'Проверьте конфиг сервера.'}"
            )

        if not self._port_open():
            self.stop()
            raise RuntimeError(
                f"sing-box запущен, но порт 127.0.0.1:{self.local_port} не слушается.\n{self._read_log_tail()}"
            )

    def stop(self) -> None:
        if self._process and self._process.poll() is None:
            try:
                os.killpg(os.getpgid(self._process.pid), signal.SIGTERM)
                self._process.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(os.getpgid(self._process.pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass

        self._process = None

        if self._config_path and self._config_path.exists():
            self._config_path.unlink(missing_ok=True)
            self._config_path = None
        if self._log_path and self._log_path.exists():
            self._log_path.unlink(missing_ok=True)
            self._log_path = None

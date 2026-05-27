import json
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Optional

from .models import Server
from .singbox_config import build_config


class SingBoxRunner:
    def __init__(self, singbox_path: Path, local_port: int = 7890):
        self.singbox_path = singbox_path
        self.local_port = local_port
        self._process: Optional[subprocess.Popen] = None
        self._config_path: Optional[Path] = None
        self._log_path: Optional[Path] = None

    @property
    def is_running(self) -> bool:
        return self._process is not None and self._process.poll() is None

    def start(self, server: Server, tun_mode: bool = False) -> None:
        if self.is_running:
            self.stop()

        if not self.singbox_path.exists():
            raise FileNotFoundError(f"sing-box не найден: {self.singbox_path}")

        config = build_config(server, self.local_port, tun_mode=tun_mode)
        fd, path = tempfile.mkstemp(prefix="vless-app-", suffix=".json")
        os.close(fd)
        self._config_path = Path(path)
        self._config_path.write_text(json.dumps(config, indent=2), encoding="utf-8")
        log_fd, log_path = tempfile.mkstemp(prefix="vless-app-", suffix=".log")
        os.close(log_fd)
        self._log_path = Path(log_path)

        log_handle = self._log_path.open("a", encoding="utf-8")
        self._process = subprocess.Popen(
            [str(self.singbox_path), "run", "-c", str(self._config_path)],
            stdout=log_handle,
            stderr=log_handle,
            preexec_fn=os.setsid,
        )
        log_handle.close()
        time.sleep(0.8)

        if self._process.poll() is not None:
            details = ""
            if self._log_path and self._log_path.exists():
                content = self._log_path.read_text(encoding="utf-8", errors="ignore").strip()
                if content:
                    details = f"\nЛог sing-box:\n{content[-800:]}"
            raise RuntimeError(f"sing-box не запустился. Проверьте конфигурацию сервера.{details}")

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

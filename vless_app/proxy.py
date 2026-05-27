import subprocess


class SystemProxy:
    SCHEMA = "org.gnome.system.proxy"

    def __init__(self, host: str = "127.0.0.1", port: int = 7890):
        self.host = host
        self.port = port
        self._previous_mode: str | None = None

    def _run(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["gsettings", *args],
            check=False,
            capture_output=True,
            text=True,
        )

    def enable(self) -> None:
        result = subprocess.run(
            ["gsettings", "get", f"{self.SCHEMA}", "mode"],
            capture_output=True,
            text=True,
            check=False,
        )
        self._previous_mode = result.stdout.strip().strip("'")

        self._run("set", f"{self.SCHEMA}", "mode", "manual")
        for key in ("http", "https", "ftp", "socks"):
            self._run("set", f"{self.SCHEMA}.{key}", "host", self.host)
            self._run("set", f"{self.SCHEMA}.{key}", "port", str(self.port))
        self._run("set", f"{self.SCHEMA}.socks", "host", self.host)
        self._run("set", f"{self.SCHEMA}.socks", "port", str(self.port))
        verify = self._run("get", f"{self.SCHEMA}", "mode")
        mode = verify.stdout.strip().strip("'")
        if mode != "manual":
            reason = (verify.stderr or verify.stdout).strip()
            raise RuntimeError(
                "Не удалось включить системный прокси. "
                "Запустите приложение обычным пользователем (не через sudo). "
                f"Текущее значение mode: {mode or 'unknown'}. {reason}"
            )

    def disable(self) -> None:
        mode = self._previous_mode or "none"
        self._run("set", f"{self.SCHEMA}", "mode", mode)

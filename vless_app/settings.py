import json
from dataclasses import asdict, dataclass, field
from pathlib import Path


def _config_path() -> Path:
    base = Path.home() / ".config" / "grey-vless"
    base.mkdir(parents=True, exist_ok=True)
    return base / "settings.json"


@dataclass
class AppSettings:
    tun_mode: bool = False
    auto_connect: bool = False
    minimize_to_tray: bool = True
    subscription_url: str = ""
    subscription_name: str = "Подписка"
    servers: list[dict] = field(default_factory=list)
    selected_index: int | None = None

    def load(self) -> None:
        path = _config_path()
        if not path.exists():
            return
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return
        self.tun_mode = bool(data.get("tun_mode", False))
        self.auto_connect = bool(data.get("auto_connect", False))
        self.minimize_to_tray = bool(data.get("minimize_to_tray", True))
        self.subscription_url = str(data.get("subscription_url", ""))
        self.subscription_name = str(data.get("subscription_name", "Подписка"))
        self.servers = list(data.get("servers") or [])
        idx = data.get("selected_index")
        self.selected_index = int(idx) if idx is not None else None

    def save(self) -> None:
        path = _config_path()
        path.write_text(
            json.dumps(asdict(self), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

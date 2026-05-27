import os
from pathlib import Path

from .branding import INSTALL_DIR, PACKAGE_NAME


def app_root() -> Path:
    for key in ("GREY_VLESS_APP_ROOT", "VLESS_APP_ROOT"):
        env_root = os.environ.get(key)
        if env_root:
            return Path(env_root)
    return Path(__file__).resolve().parent.parent


def singbox_binary() -> Path:
    root = app_root()
    bundled = root / "bin" / "sing-box"
    if bundled.exists():
        return bundled
    for candidate in (
        Path(f"{INSTALL_DIR}/bin/sing-box"),
        Path("/opt/vless-vpn/bin/sing-box"),
        Path("/opt/nekoray/nekobox_core"),
    ):
        if candidate.exists():
            return candidate
    return bundled


def icon_path() -> Path:
    root = app_root()
    for candidate in (
        root / "share" / "icons" / f"{PACKAGE_NAME}.png",
        root / "data" / f"{PACKAGE_NAME}.png",
        Path(f"{INSTALL_DIR}/share/icons/{PACKAGE_NAME}.png"),
        Path("/opt/vless-vpn/share/icons/vless-vpn.png"),
    ):
        if candidate.exists():
            return candidate
    return root / "data" / f"{PACKAGE_NAME}.png"


def is_bundled() -> bool:
    return (app_root() / "lib" / "girepository-1.0").exists()

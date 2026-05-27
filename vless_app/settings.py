from dataclasses import dataclass


@dataclass
class AppSettings:
    tun_mode: bool = False
    auto_connect: bool = False
    minimize_to_tray: bool = True

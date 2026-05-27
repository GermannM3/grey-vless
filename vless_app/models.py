from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Server:
    name: str
    protocol: str
    host: str
    port: int
    raw_link: str
    ping_ms: Optional[int] = None
    ping_error: Optional[str] = None
    params: dict = field(default_factory=dict)

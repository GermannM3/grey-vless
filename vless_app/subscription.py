import base64
import re
import urllib.error
import urllib.request
from typing import List

from .parser import parse_link


def _decode_subscription_text(text: str) -> str:
    text = text.strip()
    if not text:
        return ""

    if "://" in text.split("\n", 1)[0]:
        return text

    try:
        padding = "=" * (-len(text) % 4)
        decoded = base64.b64decode(text + padding).decode("utf-8", errors="ignore")
        if "://" in decoded:
            return decoded
    except Exception:
        pass

    return text


def fetch_subscription(source: str) -> str:
    source = source.strip()
    if not source:
        raise ValueError("Пустая ссылка или текст")

    if re.match(r"^https?://", source, re.IGNORECASE):
        request = urllib.request.Request(
            source,
            headers={"User-Agent": "GreyVless/1.0"},
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                body = response.read().decode("utf-8", errors="ignore")
        except urllib.error.URLError as exc:
            raise RuntimeError(f"Не удалось загрузить подписку: {exc}") from exc
        return _decode_subscription_text(body)

    return _decode_subscription_text(source)


def parse_subscription(source: str) -> List:
    text = fetch_subscription(source)
    servers = []
    seen = set()

    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            server = parse_link(line)
        except ValueError:
            continue
        key = (server.protocol, server.host, server.port, server.raw_link)
        if key in seen:
            continue
        seen.add(key)
        servers.append(server)

    if not servers:
        raise ValueError("Серверы не найдены. Проверьте ссылку или формат.")

    return servers

import base64
import json
from urllib.parse import parse_qs, unquote, urlparse

from .models import Server


def _first(params: dict, key: str, default: str = "") -> str:
    value = params.get(key, [default])
    if not value:
        return default
    return value[0] if value[0] is not None else default


def _parse_shadowsocks(link: str) -> Server:
    parsed = urlparse(link)
    fragment = unquote(parsed.fragment or "Shadowsocks")

    if "@" in parsed.netloc:
        userinfo, hostport = parsed.netloc.rsplit("@", 1)
        if ":" in userinfo:
            method, password = userinfo.split(":", 1)
        else:
            decoded = base64.b64decode(userinfo + "=" * (-len(userinfo) % 4)).decode("utf-8", errors="ignore")
            method, password = decoded.split(":", 1)
        host, port_str = hostport.rsplit(":", 1)
    else:
        payload = parsed.netloc or parsed.path.lstrip("/")
        decoded = base64.b64decode(payload + "=" * (-len(payload) % 4)).decode("utf-8", errors="ignore")
        method_password, hostport = decoded.rsplit("@", 1)
        method, password = method_password.split(":", 1)
        host, port_str = hostport.rsplit(":", 1)

    return Server(
        name=fragment,
        protocol="shadowsocks",
        host=host,
        port=int(port_str),
        raw_link=link,
        params={
            "method": method,
            "password": password,
        },
    )


def _parse_vmess(link: str) -> Server:
    payload = link[len("vmess://") :]
    padding = "=" * (-len(payload) % 4)
    data = json.loads(base64.b64decode(payload + padding).decode("utf-8", errors="ignore"))

    return Server(
        name=data.get("ps") or data.get("remark") or "VMess",
        protocol="vmess",
        host=data.get("add") or data.get("host") or "",
        port=int(data.get("port") or 443),
        raw_link=link,
        params={
            "uuid": data.get("id", ""),
            "alter_id": int(data.get("aid") or 0),
            "security": data.get("scy") or "auto",
            "network": data.get("net") or "tcp",
            "host_header": data.get("host") or "",
            "path": data.get("path") or "",
            "tls": data.get("tls") or "",
            "sni": data.get("sni") or data.get("host") or "",
            "fp": data.get("fp") or "",
            "type": data.get("type") or "none",
            "serviceName": data.get("serviceName") or data.get("servicename") or "",
        },
    )


def _parse_uri_scheme(link: str, protocol: str) -> Server:
    parsed = urlparse(link)
    params = parse_qs(parsed.query)
    name = unquote(parsed.fragment or protocol.upper())

    if protocol == "trojan":
        password = parsed.username or ""
    else:
        password = parsed.username or ""

    return Server(
        name=name,
        protocol=protocol,
        host=parsed.hostname or "",
        port=int(parsed.port or 443),
        raw_link=link,
        params={
            "uuid" if protocol == "vless" else "password": password,
            "security": _first(params, "security"),
            "network": _first(params, "type", "tcp"),
            "flow": _first(params, "flow"),
            "path": _first(params, "path"),
            "host": _first(params, "host"),
            "sni": _first(params, "sni"),
            "fp": _first(params, "fp", "chrome"),
            "pbk": _first(params, "pbk"),
            "sid": _first(params, "sid"),
            "headerType": _first(params, "headerType"),
            "serviceName": _first(params, "serviceName"),
            "encryption": _first(params, "encryption", "none"),
        },
    )


def parse_link(link: str) -> Server:
    link = link.strip()
    lower = link.lower()

    if lower.startswith("vless://"):
        return _parse_uri_scheme(link, "vless")
    if lower.startswith("vmess://"):
        return _parse_vmess(link)
    if lower.startswith("trojan://"):
        return _parse_uri_scheme(link, "trojan")
    if lower.startswith("ss://"):
        return _parse_shadowsocks(link)

    raise ValueError(f"Неподдерживаемый формат: {link[:32]}...")

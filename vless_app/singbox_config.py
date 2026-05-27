from typing import Any, Dict

from .models import Server


def _transport(server: Server) -> Dict[str, Any] | None:
    network = server.params.get("network") or "tcp"
    if network in ("tcp", "none", ""):
        return None

    transport: Dict[str, Any] = {"type": network}

    if network == "ws":
        transport["path"] = server.params.get("path") or "/"
        host = server.params.get("host") or server.params.get("host_header")
        if host:
            transport["headers"] = {"Host": host}
    elif network == "grpc":
        transport["service_name"] = server.params.get("serviceName") or server.params.get("service_name") or ""
    elif network == "http":
        transport["path"] = server.params.get("path") or "/"
        host = server.params.get("host") or server.params.get("host_header")
        if host:
            transport["host"] = [host]

    return transport


def _tls(server: Server) -> Dict[str, Any] | None:
    security = (server.params.get("security") or server.params.get("tls") or "").lower()
    if security not in ("tls", "reality", "xtls"):
        return None

    tls: Dict[str, Any] = {
        "enabled": True,
        "server_name": server.params.get("sni") or server.host,
    }

    fp = server.params.get("fp")
    if fp:
        tls["utls"] = {"enabled": True, "fingerprint": fp}

    if security == "reality":
        tls["reality"] = {
            "enabled": True,
            "public_key": server.params.get("pbk") or "",
            "short_id": server.params.get("sid") or "",
        }

    return tls


def _vless_outbound(server: Server) -> Dict[str, Any]:
    outbound: Dict[str, Any] = {
        "type": "vless",
        "tag": "proxy",
        "server": server.host,
        "server_port": server.port,
        "uuid": server.params.get("uuid") or "",
    }

    flow = server.params.get("flow")
    if flow:
        outbound["flow"] = flow

    transport = _transport(server)
    if transport:
        outbound["transport"] = transport

    tls = _tls(server)
    if tls:
        outbound["tls"] = tls

    return outbound


def _vmess_outbound(server: Server) -> Dict[str, Any]:
    outbound: Dict[str, Any] = {
        "type": "vmess",
        "tag": "proxy",
        "server": server.host,
        "server_port": server.port,
        "uuid": server.params.get("uuid") or "",
        "security": server.params.get("security") or "auto",
        "alter_id": int(server.params.get("alter_id") or 0),
    }

    transport = _transport(server)
    if transport:
        outbound["transport"] = transport

    tls = _tls(server)
    if tls:
        outbound["tls"] = tls

    return outbound


def _trojan_outbound(server: Server) -> Dict[str, Any]:
    outbound: Dict[str, Any] = {
        "type": "trojan",
        "tag": "proxy",
        "server": server.host,
        "server_port": server.port,
        "password": server.params.get("password") or "",
    }

    transport = _transport(server)
    if transport:
        outbound["transport"] = transport

    tls = _tls(server) or {"enabled": True, "server_name": server.params.get("sni") or server.host}
    outbound["tls"] = tls
    return outbound


def _shadowsocks_outbound(server: Server) -> Dict[str, Any]:
    return {
        "type": "shadowsocks",
        "tag": "proxy",
        "server": server.host,
        "server_port": server.port,
        "method": server.params.get("method") or "aes-256-gcm",
        "password": server.params.get("password") or "",
    }


def build_config(server: Server, local_port: int = 7890, tun_mode: bool = False) -> Dict[str, Any]:
    builders = {
        "vless": _vless_outbound,
        "vmess": _vmess_outbound,
        "trojan": _trojan_outbound,
        "shadowsocks": _shadowsocks_outbound,
    }

    builder = builders.get(server.protocol)
    if not builder:
        raise ValueError(f"Протокол {server.protocol} пока не поддерживается")

    if tun_mode:
        inbounds = [
            {
                "type": "tun",
                "tag": "tun-in",
                "interface_name": "tun0",
                "address": ["172.19.0.1/30"],
                "auto_route": True,
                "strict_route": True,
                "stack": "system",
                "sniff": True,
            }
        ]
    else:
        inbounds = [
            {
                "type": "mixed",
                "tag": "mixed-in",
                "listen": "127.0.0.1",
                "listen_port": local_port,
            }
        ]

    return {
        "log": {"level": "warn"},
        "dns": {
            "servers": [
                {"tag": "google", "address": "8.8.8.8"},
                {"tag": "local", "address": "223.5.5.5", "detour": "direct"},
            ],
            "strategy": "prefer_ipv4",
        },
        "inbounds": inbounds,
        "outbounds": [
            builder(server),
            {"type": "direct", "tag": "direct"},
            {"type": "block", "tag": "block"},
        ],
        "route": {
            "auto_detect_interface": True,
            "final": "proxy",
        },
    }

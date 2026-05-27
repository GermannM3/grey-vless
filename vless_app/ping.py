import socket
import time


def tcp_ping(host: str, port: int, timeout: float = 3.0) -> int:
    start = time.perf_counter()
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect((host, port))
    finally:
        sock.close()
    elapsed = (time.perf_counter() - start) * 1000
    return int(elapsed)

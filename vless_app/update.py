"""Проверка обновлений через GitHub Releases."""
from __future__ import annotations

import json
import re
import subprocess
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from vless_app.branding import APP_VERSION, GITHUB_REPO, USER_AGENT

_API = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
_TAG_RE = re.compile(r"^v?(\d+\.\d+\.\d+)-build\.(\d+)$")
_PREFERRED_ASSETS = (
    "grey-vless_{semver}_amd64.deb",
    "Grey-vless-linux-x64.zip",
)


@dataclass(frozen=True)
class UpdateInfo:
    tag: str
    semver: str
    build: int
    download_url: str
    asset_name: str
    release_page: str


def _parse_version(semver: str, build: int) -> tuple[list[int], int]:
    return [int(x) for x in semver.split(".")], build


def _is_newer(current_semver: str, current_build: int, latest_semver: str, latest_build: int) -> bool:
    cur = _parse_version(current_semver, current_build)
    lat = _parse_version(latest_semver, latest_build)
    if cur[0] != lat[0]:
        return cur[0] < lat[0]
    return cur[1] < lat[1]


def _current_version() -> tuple[str, int]:
    if "+" in APP_VERSION:
        semver, build_part = APP_VERSION.split("+", 1)
        build = int(build_part) if build_part.isdigit() else 0
        return semver, build
    return APP_VERSION, 0


def check_for_update() -> UpdateInfo | None:
    req = urllib.request.Request(
        _API,
        headers={"Accept": "application/vnd.github+json", "User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    tag = str(data.get("tag_name", ""))
    m = _TAG_RE.match(tag)
    if not m:
        return None

    latest_semver, latest_build_s = m.group(1), m.group(2)
    latest_build = int(latest_build_s)
    current_semver, current_build = _current_version()

    if not _is_newer(current_semver, current_build, latest_semver, latest_build):
        return None

    assets = {str(a.get("name", "")): str(a.get("browser_download_url", "")) for a in data.get("assets") or []}
    download_url = ""
    asset_name = ""
    for pattern in _PREFERRED_ASSETS:
        candidate = pattern.format(semver=latest_semver)
        if candidate in assets and assets[candidate]:
            asset_name = candidate
            download_url = assets[candidate]
            break

    return UpdateInfo(
        tag=tag,
        semver=latest_semver,
        build=latest_build,
        download_url=download_url,
        asset_name=asset_name,
        release_page=f"https://github.com/{GITHUB_REPO}/releases/latest",
    )


def open_url(url: str) -> None:
    subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _download_file(url: str, dest: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=600) as resp, dest.open("wb") as out:
        while True:
            chunk = resp.read(1024 * 256)
            if not chunk:
                break
            out.write(chunk)


def _install_deb(path: Path) -> None:
    subprocess.Popen(["pkexec", "dpkg", "-i", str(path)])


def prompt_update(parent, info: UpdateInfo, on_done: Callable[[], None] | None = None) -> None:
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk

    secondary = "Скачать обновление с GitHub Releases?"
    if info.asset_name:
        secondary += f"\nФайл: {info.asset_name}"
    else:
        secondary += "\nГотовый .deb в релизе не найден — откроется страница загрузки."

    dialog = Gtk.MessageDialog(
        transient_for=parent,
        flags=0,
        message_type=Gtk.MessageType.INFO,
        buttons=Gtk.ButtonsType.NONE,
        text=f"Доступна версия {info.semver} (build {info.build})",
    )
    dialog.format_secondary_text(secondary)
    dialog.add_button("Позже", Gtk.ResponseType.CANCEL)
    dialog.add_button("Открыть релиз", Gtk.ResponseType.APPLY)
    if info.download_url:
        dialog.add_button("Скачать", Gtk.ResponseType.OK)
    response = dialog.run()
    dialog.destroy()

    if response == Gtk.ResponseType.OK and info.download_url:
        suffix = Path(info.asset_name).suffix or ".bin"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            dest = Path(tmp.name)
        try:
            _download_file(info.download_url, dest)
            if dest.suffix == ".deb":
                _install_deb(dest)
            else:
                open_url(info.release_page)
        except OSError as exc:
            err = Gtk.MessageDialog(
                transient_for=parent,
                flags=0,
                message_type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.OK,
                text="Не удалось скачать обновление",
            )
            err.format_secondary_text(str(exc))
            err.run()
            err.destroy()
    elif response == Gtk.ResponseType.APPLY:
        open_url(info.release_page)

    if on_done:
        on_done()

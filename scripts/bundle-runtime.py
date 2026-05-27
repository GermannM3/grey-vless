#!/usr/bin/env python3
"""Collect Python + GTK runtime for self-contained .deb package."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = ROOT / "build" / "runtime"

TYPELIBS = [
    "Gtk-3.0.typelib",
    "GLib-2.0.typelib",
    "GObject-2.0.typelib",
    "Gio-2.0.typelib",
    "Gdk-3.0.typelib",
    "GdkPixbuf-2.0.typelib",
    "Pango-1.0.typelib",
    "PangoCairo-1.0.typelib",
    "cairo-1.0.typelib",
    "Atk-1.0.typelib",
    "HarfBuzz-0.0.typelib",
    "freetype2-2.0.typelib",
    "fontconfig-2.0.typelib",
    "xlib-2.0.typelib",
    "xfixes-4.0.typelib",
    "xrandr-1.3.typelib",
    "xinerama-1.0.typelib",
    "Xi-2.0.typelib",
    "xft-2.0.typelib",
    "DBus-1.0.typelib",
    "libxml2-2.0.typelib",
    "Rsvg-2.0.typelib",
    "Polkit-1.0.typelib",
]

GI_REPO_DIRS = [
    Path("/usr/lib/x86_64-linux-gnu/girepository-1.0"),
    Path("/usr/lib/girepository-1.0"),
]


def ldd_paths(binary: Path) -> set[Path]:
    deps: set[Path] = set()
    try:
        output = subprocess.check_output(["ldd", str(binary)], text=True, errors="ignore")
    except (subprocess.CalledProcessError, FileNotFoundError):
        return deps
    for line in output.splitlines():
        if "=>" not in line:
            continue
        part = line.split("=>", 1)[1].strip().split()[0]
        if part.startswith("/"):
            deps.add(Path(part))
    return deps


def collect_recursive(seeds: list[Path]) -> set[Path]:
    collected: set[Path] = set()
    queue = [Path(s) for s in seeds if s.exists()]
    while queue:
        current = queue.pop()
        if current in collected:
            continue
        collected.add(current)
        for dep in ldd_paths(current):
            if dep not in collected:
                queue.append(dep)
    return collected


def copy_libs(libs: set[Path], dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for lib in sorted(libs):
        if not lib.is_file():
            continue
        target = dest / lib.name
        if target.exists():
            continue
        shutil.copy2(lib, target)


def copy_tree(src: Path, dest: Path) -> None:
    if not src.exists():
        raise FileNotFoundError(f"Missing runtime path: {src}")
    if src.is_dir():
        shutil.copytree(src, dest, dirs_exist_ok=True)
    else:
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)


def python_seeds() -> list[Path]:
    import gi  # noqa: WPS433

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk  # noqa: WPS433,F401

    gi_dir = Path(gi.__file__).parent
    seeds = [Path(sys.executable)]
    for so_name in gi_dir.glob("_gi.cpython-*.so"):
        seeds.append(so_name)
    for so_name in gi_dir.glob("_gi_cairo.cpython-*.so"):
        seeds.append(so_name)

    version = f"{sys.version_info.major}.{sys.version_info.minor}"
    for pattern in (
        f"/usr/lib/x86_64-linux-gnu/libpython{version}.so.1.0",
        f"/usr/lib/libpython{version}.so.1.0",
    ):
        candidate = Path(pattern)
        if candidate.exists():
            seeds.append(candidate)

    gtk_lib = Path("/usr/lib/x86_64-linux-gnu/libgtk-3.so.0")
    if gtk_lib.exists():
        seeds.append(gtk_lib)

    return [s for s in seeds if s.exists()]


def main() -> None:
    if BUNDLE.exists():
        shutil.rmtree(BUNDLE)

    lib_dir = BUNDLE / "lib"
    typelib_dir = lib_dir / "girepository-1.0"
    python_pkg = BUNDLE / "site-packages"
    dynload = lib_dir / "python3.12" / "lib-dynload"

    seeds = python_seeds()
    libs = collect_recursive(seeds)
    copy_libs(libs, lib_dir)

    copy_tree(Path("/usr/lib/python3/dist-packages/gi"), python_pkg / "gi")

    dynload_src = Path("/usr/lib/python3.12/lib-dynload")
    if dynload_src.exists():
        copy_tree(dynload_src, dynload)

    typelib_dir.mkdir(parents=True, exist_ok=True)
    for name in TYPELIBS:
        copied = False
        for repo in GI_REPO_DIRS:
            src = repo / name
            if src.exists():
                shutil.copy2(src, typelib_dir / name)
                copied = True
                break
        if not copied:
            print(f"Warning: typelib not found: {name}", file=sys.stderr)

    schemas_src = Path("/usr/share/glib-2.0/schemas")
    schemas_dest = BUNDLE / "share" / "glib-2.0" / "schemas"
    if schemas_src.exists():
        copy_tree(schemas_src, schemas_dest)

    pixbuf_root = BUNDLE / "lib" / "gdk-pixbuf-2.0"
    for pixbuf_lib in Path("/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0").glob("*/loaders"):
        copy_tree(pixbuf_lib, pixbuf_root / "loaders")
        break

    icons_dest = BUNDLE / "share" / "icons"
    icons_dest.mkdir(parents=True, exist_ok=True)
    icon_src = ROOT / "data" / "grey-vless.png"
    if icon_src.exists():
        shutil.copy2(icon_src, icons_dest / "grey-vless.png")

    python_bin = BUNDLE / "bin" / "python3"
    python_bin.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path(sys.executable), python_bin)

    print(f"Runtime bundled to {BUNDLE}")
    print(f"Libraries: {len(list(lib_dir.glob('*.so*')))}")


if __name__ == "__main__":
    main()

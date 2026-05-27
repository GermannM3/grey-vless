#!/usr/bin/env bash
# Сборка AppImage Grey vless — переносимый файл для любого Linux x86_64
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="Grey-vless"
VERSION="0.3.0"
ARCH="x86_64"
INSTALL_DIR="opt/grey-vless"
APPDIR="$ROOT/build/AppDir"
APPIMAGE_OUT="$ROOT/build/${NAME}-${VERSION}-${ARCH}.AppImage"
TOOLS_DIR="$ROOT/build/tools"

echo "==> Сборка runtime..."
python3 "$ROOT/scripts/bundle-runtime.py"

echo "==> Подготовка AppDir..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/${INSTALL_DIR}/app/vless_app"
mkdir -p "$APPDIR/${INSTALL_DIR}/bin"
mkdir -p "$APPDIR/${INSTALL_DIR}/share/icons"

cp -r "$ROOT/build/runtime/"* "$APPDIR/${INSTALL_DIR}/"
cp "$ROOT/vless_app/"*.py "$APPDIR/${INSTALL_DIR}/app/vless_app/"
cp "$ROOT/bin/sing-box" "$APPDIR/${INSTALL_DIR}/bin/sing-box"
chmod +x "$APPDIR/${INSTALL_DIR}/bin/sing-box"
cp "$ROOT/data/grey-vless.png" "$APPDIR/${INSTALL_DIR}/share/icons/grey-vless.png"
cp "$ROOT/data/grey-vless.png" "$APPDIR/grey-vless.png"
cp "$ROOT/data/grey-vless.desktop" "$APPDIR/grey-vless.desktop"

cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(dirname "$(readlink -f "${0}")")"
INSTALL_DIR="$HERE/opt/grey-vless"

export GREY_VLESS_APP_ROOT="$INSTALL_DIR"
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:${LD_LIBRARY_PATH:-}"
export GI_TYPELIB_PATH="$INSTALL_DIR/lib/girepository-1.0"
export PYTHONPATH="$INSTALL_DIR/site-packages:$INSTALL_DIR/app"
export GSETTINGS_SCHEMA_DIR="$INSTALL_DIR/share/glib-2.0/schemas"
export XDG_DATA_DIRS="$INSTALL_DIR/share:${XDG_DATA_DIRS:-/usr/share}"
export GDK_PIXBUF_MODULEDIR="$INSTALL_DIR/lib/gdk-pixbuf-2.0/loaders"

if [ -n "${APPIMAGE:-}" ] && [ -z "${DESKTOPINTEGRATION:-}" ]; then
  export APPIMAGE_SILENT_INSTALL=1
fi

exec "$INSTALL_DIR/bin/python3" -m vless_app "$@"
EOF
chmod +x "$APPDIR/AppRun"

ln -sf grey-vless.png "$APPDIR/.DirIcon"
chmod +x "$APPDIR/grey-vless.desktop"

mkdir -p "$TOOLS_DIR"
APPIMAGETOOL="$TOOLS_DIR/appimagetool-${ARCH}.AppImage"
if [ ! -x "$APPIMAGETOOL" ]; then
  echo "==> Загрузка appimagetool..."
  curl -fsSL "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${ARCH}.AppImage" \
    -o "$APPIMAGETOOL"
  chmod +x "$APPIMAGETOOL"
fi

echo "==> Сборка AppImage..."
ARCH="$ARCH" "$APPIMAGETOOL" "$APPDIR" "$APPIMAGE_OUT"

chmod +x "$APPIMAGE_OUT"
echo "Готово: $APPIMAGE_OUT"
echo "Запуск: chmod +x '$APPIMAGE_OUT' && '$APPIMAGE_OUT'"

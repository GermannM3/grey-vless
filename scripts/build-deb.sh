#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="grey-vless"
VERSION="0.4.3"
ARCH="amd64"
INSTALL_DIR="/opt/grey-vless"
PKG_DIR="$ROOT/build/deb/${NAME}_${VERSION}_${ARCH}"

echo "==> Сборка runtime..."
python3 "$ROOT/scripts/bundle-runtime.py"

echo "==> Подготовка .deb..."
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/usr/bin"
mkdir -p "$PKG_DIR/usr/share/applications"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor"
mkdir -p "$PKG_DIR${INSTALL_DIR}/app/vless_app"
mkdir -p "$PKG_DIR${INSTALL_DIR}/bin"
mkdir -p "$PKG_DIR${INSTALL_DIR}/share/icons"

cp -r "$ROOT/build/runtime/"* "$PKG_DIR${INSTALL_DIR}/"
cp "$ROOT/vless_app/"*.py "$PKG_DIR${INSTALL_DIR}/app/vless_app/"
cp "$ROOT/bin/sing-box" "$PKG_DIR${INSTALL_DIR}/bin/sing-box"
chmod +x "$PKG_DIR${INSTALL_DIR}/bin/sing-box"

for size in 64 128 256 512; do
  mkdir -p "$PKG_DIR/usr/share/icons/hicolor/${size}x${size}/apps"
  cp "$ROOT/data/icons/hicolor/${size}x${size}/apps/grey-vless.png" \
    "$PKG_DIR/usr/share/icons/hicolor/${size}x${size}/apps/grey-vless.png"
done
cp "$ROOT/data/grey-vless.png" "$PKG_DIR${INSTALL_DIR}/share/icons/grey-vless.png"
cp "$ROOT/data/grey-vless.desktop" "$PKG_DIR/usr/share/applications/grey-vless.desktop"

cat > "$PKG_DIR/usr/bin/grey-vless" <<EOF
#!/usr/bin/env bash
INSTALL_DIR="${INSTALL_DIR}"
export GREY_VLESS_APP_ROOT="\$INSTALL_DIR"
export LD_LIBRARY_PATH="\$INSTALL_DIR/lib:\${LD_LIBRARY_PATH:-}"
export GI_TYPELIB_PATH="\$INSTALL_DIR/lib/girepository-1.0"
export PYTHONPATH="\$INSTALL_DIR/site-packages:\$INSTALL_DIR/app"
export GSETTINGS_SCHEMA_DIR="\$INSTALL_DIR/share/glib-2.0/schemas"
export XDG_DATA_DIRS="\$INSTALL_DIR/share:/usr/share"
export GDK_PIXBUF_MODULEDIR="\$INSTALL_DIR/lib/gdk-pixbuf-2.0/loaders"
exec "\$INSTALL_DIR/bin/python3" -m vless_app "\$@"
EOF
chmod +x "$PKG_DIR/usr/bin/grey-vless"

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: grey-vless
Version: ${VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Maintainer: Grey vless <local@localhost>
Depends: libc6
Description: Grey vless — десктопный VPN-клиент (автономный)
 Вставьте ссылку на подписку, выберите сервер и подключитесь.
 Поддерживаются VLESS, VMess, Trojan, Shadowsocks.
 Все зависимости включены в пакет.
EOF

cat > "$PKG_DIR/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
SING_BOX="${INSTALL_DIR}/bin/sing-box"
if [ -x "\$SING_BOX" ]; then
  chmod +x "\$SING_BOX"
  if command -v setcap >/dev/null 2>&1; then
    setcap cap_net_admin,cap_net_bind_service+ep "\$SING_BOX" 2>/dev/null || true
  fi
fi
EOF
chmod 755 "$PKG_DIR/DEBIAN/postinst"

cat > "$PKG_DIR/DEBIAN/prerm" <<EOF
#!/bin/sh
set -e
pkill -f "${INSTALL_DIR}/bin/sing-box" 2>/dev/null || true
EOF
chmod 755 "$PKG_DIR/DEBIAN/prerm"

echo "==> Сборка пакета..."
dpkg-deb --root-owner-group --build "$PKG_DIR"
echo "Готово: ${PKG_DIR}.deb"

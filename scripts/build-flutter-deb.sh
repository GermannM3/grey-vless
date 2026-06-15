#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${1:-$ROOT/grey_vless/build/linux/x64/release/bundle}"
VERSION="$(grep '^version:' "$ROOT/grey_vless/pubspec.yaml" | awk '{print $2}' | cut -d+ -f1)"
ARCH="amd64"
INSTALL_DIR="/opt/grey-vless"
PKG_DIR="$ROOT/build/deb/grey-vless_${VERSION}_${ARCH}"

if [[ ! -d "$BUNDLE" ]]; then
  echo "Flutter bundle not found: $BUNDLE" >&2
  exit 1
fi

echo "==> Flutter .deb v${VERSION}..."
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN" "$PKG_DIR/usr/bin" "$PKG_DIR/usr/share/applications"
mkdir -p "$PKG_DIR${INSTALL_DIR}/flutter"

cp -a "$BUNDLE/." "$PKG_DIR${INSTALL_DIR}/flutter/"
chmod +x "$PKG_DIR${INSTALL_DIR}/flutter/grey_vless"

cp "$ROOT/data/grey-vless.desktop" "$PKG_DIR/usr/share/applications/grey-vless.desktop"
cp "$ROOT/data/grey-vless.png" "$PKG_DIR${INSTALL_DIR}/flutter/data/flutter_assets/assets/icons/grey-vless.png" 2>/dev/null || \
  cp "$ROOT/data/grey-vless.png" "$PKG_DIR/usr/share/icons/hicolor/256x256/apps/grey-vless.png" 2>/dev/null || true

cat > "$PKG_DIR/usr/bin/grey-vless" <<EOF
#!/usr/bin/env bash
exec "${INSTALL_DIR}/flutter/grey_vless" "\$@"
EOF
chmod +x "$PKG_DIR/usr/bin/grey-vless"

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: grey-vless
Version: ${VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Maintainer: Grey vless <local@localhost>
Depends: libgtk-3-0, libglib2.0-0
Description: Grey vless — Flutter VPN-клиент для Linux
 Тот же интерфейс, что на Android: подписки, Grey Sense, sing-box.
EOF

cat > "$PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
SING_BOX="/opt/grey-vless/flutter/data/flutter_assets/assets/bin/sing-box-linux-amd64"
if [ -f "$SING_BOX" ]; then
  chmod +x "$SING_BOX"
  if command -v setcap >/dev/null 2>&1; then
    setcap cap_net_admin,cap_net_bind_service+ep "$SING_BOX" 2>/dev/null || true
  fi
fi
EOF
chmod 755 "$PKG_DIR/DEBIAN/postinst"

dpkg-deb --root-owner-group --build "$PKG_DIR"
echo "Готово: ${PKG_DIR}.deb"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/data/grey-vless.png"
ASSETS="$ROOT/grey_vless/assets/icons/grey-vless.png"
WIN_ICO="$ROOT/grey_vless/windows/runner/resources/app_icon.ico"

mkdir -p "$(dirname "$ASSETS")" "$(dirname "$WIN_ICO")"
cp -f "$SRC" "$ASSETS"

if python3 -c "import PIL" 2>/dev/null; then
  python3 - "$SRC" "$WIN_ICO" <<'PY'
import sys
from PIL import Image

src, ico_out = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")
img.save(ico_out, format="ICO", sizes=[(s, s) for s in [256, 128, 64, 48, 32, 16]])
print("ICO:", ico_out)
PY
else
  echo "PIL недоступен — пропуск .ico (для macOS достаточно PNG + flutter_launcher_icons)"
  if [[ ! -f "$WIN_ICO" ]]; then
    echo "Предупреждение: $WIN_ICO не найден"
  fi
fi

echo "Icons prepared from $SRC"

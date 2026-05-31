#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/data/grey-vless.png"
ASSETS="$ROOT/grey_vless/assets/icons/grey-vless.png"
WIN_ICO="$ROOT/grey_vless/windows/runner/resources/app_icon.ico"

mkdir -p "$(dirname "$ASSETS")" "$(dirname "$WIN_ICO")"
cp -f "$SRC" "$ASSETS"

python3 - "$SRC" "$WIN_ICO" <<'PY'
import sys
from pathlib import Path
from PIL import Image

src, ico_out = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")
sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
img.save(ico_out, format="ICO", sizes=[(s, s) for s in [256, 128, 64, 48, 32, 16]])
print("ICO:", ico_out)
PY

echo "Icons prepared from $SRC"

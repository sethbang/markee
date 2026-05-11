#!/usr/bin/env bash
# Generate AppIcon.icns from Resources/AppIcon.svg using built-in macOS tooling.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Resources/AppIcon.svg"
OUT_ICNS="$ROOT/Resources/AppIcon.icns"
ICONSET="$ROOT/build/AppIcon.iconset"

if [ ! -f "$SRC" ]; then
    echo "build-icon: missing $SRC" >&2; exit 1
fi

# Skip if .icns is newer than the source SVG.
if [ -f "$OUT_ICNS" ] && [ "$OUT_ICNS" -nt "$SRC" ]; then
    echo "build-icon: AppIcon.icns is up to date."
    exit 0
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Required sizes (logical @ 1x and @ 2x). Pairs of "filename:pixel-size".
PAIRS=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)

for pair in "${PAIRS[@]}"; do
    name="${pair%%:*}"
    size="${pair##*:}"
    sips -s format png -z "$size" "$size" "$SRC" --out "$ICONSET/$name" >/dev/null
done

iconutil -c icns -o "$OUT_ICNS" "$ICONSET"
echo "build-icon: wrote $OUT_ICNS"

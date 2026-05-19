#!/usr/bin/env bash
# Generate .icns files from SVG sources using built-in macOS tooling.
# Builds the app icon and the Markdown document icon.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

build_icns() {
    local src="$1"
    local out_icns="$2"
    local iconset="$3"

    if [ ! -f "$src" ]; then
        echo "build-icon: missing $src" >&2; exit 1
    fi
    if [ -f "$out_icns" ] && [ "$out_icns" -nt "$src" ]; then
        echo "build-icon: $(basename "$out_icns") is up to date."
        return
    fi

    rm -rf "$iconset"
    mkdir -p "$iconset"
    for pair in "${PAIRS[@]}"; do
        local name="${pair%%:*}"
        local size="${pair##*:}"
        sips -s format png -z "$size" "$size" "$src" --out "$iconset/$name" >/dev/null
    done
    iconutil -c icns -o "$out_icns" "$iconset"
    echo "build-icon: wrote $out_icns"
}

build_icns "$ROOT/Resources/AppIcon.svg" "$ROOT/Resources/AppIcon.icns" "$ROOT/build/AppIcon.iconset"
build_icns "$ROOT/Resources/DocIcon.svg" "$ROOT/Resources/DocIcon.icns" "$ROOT/build/DocIcon.iconset"

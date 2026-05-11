#!/usr/bin/env bash
# Fetch vendored JS/CSS libraries into Resources/web/vendor/.
# Idempotent — skips files that already exist.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Resources/web/vendor"

mkdir -p "$VENDOR/markdown-it" "$VENDOR/highlight" "$VENDOR/katex/fonts" "$VENDOR/mermaid"

fetch() {
    local url="$1" out="$2"
    if [ -f "$out" ] && [ -s "$out" ]; then
        return 0
    fi
    echo "  $(basename "$out") ← $url"
    curl -fsSL "$url" -o "$out.tmp"
    mv "$out.tmp" "$out"
}

echo "Fetching markdown-it and plugins…"
fetch "https://cdn.jsdelivr.net/npm/markdown-it@14.1.0/dist/markdown-it.min.js" \
    "$VENDOR/markdown-it/markdown-it.min.js"
fetch "https://cdn.jsdelivr.net/npm/markdown-it-footnote@4.0.0/dist/markdown-it-footnote.min.js" \
    "$VENDOR/markdown-it/markdown-it-footnote.min.js"
fetch "https://cdn.jsdelivr.net/npm/markdown-it-deflist@3.0.0/dist/markdown-it-deflist.min.js" \
    "$VENDOR/markdown-it/markdown-it-deflist.min.js"
fetch "https://cdn.jsdelivr.net/npm/markdown-it-attrs@4.3.1/markdown-it-attrs.browser.js" \
    "$VENDOR/markdown-it/markdown-it-attrs.min.js"
fetch "https://cdn.jsdelivr.net/npm/markdown-it-task-lists@2.1.1/dist/markdown-it-task-lists.min.js" \
    "$VENDOR/markdown-it/markdown-it-task-lists.min.js"

echo "Fetching highlight.js…"
fetch "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.10.0/build/highlight.min.js" \
    "$VENDOR/highlight/highlight.min.js"
fetch "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.10.0/build/styles/github.min.css" \
    "$VENDOR/highlight/github.min.css"
fetch "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.10.0/build/styles/github-dark.min.css" \
    "$VENDOR/highlight/github-dark.min.css"

echo "Fetching KaTeX…"
KATEX_VER="0.16.11"
fetch "https://cdn.jsdelivr.net/npm/katex@${KATEX_VER}/dist/katex.min.css" \
    "$VENDOR/katex/katex.min.css"
fetch "https://cdn.jsdelivr.net/npm/katex@${KATEX_VER}/dist/katex.min.js" \
    "$VENDOR/katex/katex.min.js"
fetch "https://cdn.jsdelivr.net/npm/katex@${KATEX_VER}/dist/contrib/auto-render.min.js" \
    "$VENDOR/katex/auto-render.min.js"

# KaTeX fonts — the CSS references these via relative paths (../fonts/)
# Our scheme handler serves vendor/katex/fonts/ from markee-app://app/vendor/katex/fonts/
# katex.min.css has `url(fonts/...)` relative paths, so they need to live at
# vendor/katex/fonts/ relative to the CSS file.
KATEX_FONTS=(
    "KaTeX_AMS-Regular.woff2"
    "KaTeX_Caligraphic-Bold.woff2"
    "KaTeX_Caligraphic-Regular.woff2"
    "KaTeX_Fraktur-Bold.woff2"
    "KaTeX_Fraktur-Regular.woff2"
    "KaTeX_Main-Bold.woff2"
    "KaTeX_Main-BoldItalic.woff2"
    "KaTeX_Main-Italic.woff2"
    "KaTeX_Main-Regular.woff2"
    "KaTeX_Math-BoldItalic.woff2"
    "KaTeX_Math-Italic.woff2"
    "KaTeX_SansSerif-Bold.woff2"
    "KaTeX_SansSerif-Italic.woff2"
    "KaTeX_SansSerif-Regular.woff2"
    "KaTeX_Script-Regular.woff2"
    "KaTeX_Size1-Regular.woff2"
    "KaTeX_Size2-Regular.woff2"
    "KaTeX_Size3-Regular.woff2"
    "KaTeX_Size4-Regular.woff2"
    "KaTeX_Typewriter-Regular.woff2"
)
mkdir -p "$VENDOR/katex/fonts"
for f in "${KATEX_FONTS[@]}"; do
    fetch "https://cdn.jsdelivr.net/npm/katex@${KATEX_VER}/dist/fonts/${f}" \
        "$VENDOR/katex/fonts/${f}"
done

echo "Fetching Mermaid (UMD bundle)…"
# The ESM build splits into runtime-imported chunks that don't work behind
# a custom URL scheme. The UMD bundle is one self-contained file.
fetch "https://cdn.jsdelivr.net/npm/mermaid@11.4.0/dist/mermaid.min.js" \
    "$VENDOR/mermaid/mermaid.min.js"
# Remove any stale ESM artifacts from earlier fetches
rm -f "$VENDOR/mermaid/mermaid.esm.min.mjs"

echo "Done. Vendor tree:"
find "$VENDOR" -type f -not -name ".DS_Store" | sed "s|$ROOT/||" | sort

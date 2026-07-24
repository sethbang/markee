#!/usr/bin/env bash
# Fetch vendored JS/CSS libraries into Resources/web/vendor/.
# Idempotent — skips files that already exist.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Resources/web/vendor"

# Integrity manifest (pinned SHA-256 of every vendored file). A normal run
# verifies the fetched files against it and fails on mismatch; pass
# `--write-manifest` to regenerate it after a deliberate version bump (do that
# in the SAME diff as the URL change).
MANIFEST="$ROOT/scripts/vendor.sha256"
MODE="verify"
if [ "${1:-}" = "--write-manifest" ]; then MODE="write"; fi

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

# ---- integrity ----------------------------------------------------------
# Manifest paths are relative to the repo root so `shasum -c` resolves them.
cd "$ROOT"
# No spaces in vendored paths, so word-splitting `$FILES` is safe and intended.
FILES="$(find Resources/web/vendor -type f -not -name ".DS_Store" -not -name ".fetched" | sort)"

if [ "$MODE" = "write" ]; then
    # shellcheck disable=SC2086
    shasum -a 256 $FILES > "$MANIFEST"
    echo "Wrote manifest: scripts/vendor.sha256 ($(grep -c . "$MANIFEST") files)."
else
    if [ ! -f "$MANIFEST" ]; then
        echo "ERROR: $MANIFEST is missing — run: scripts/fetch-vendor.sh --write-manifest" >&2
        exit 1
    fi
    disk_count="$(printf '%s\n' "$FILES" | grep -c .)"
    manifest_count="$(grep -c . "$MANIFEST")"
    if [ "$disk_count" -ne "$manifest_count" ]; then
        echo "ERROR: $disk_count vendored files on disk vs $manifest_count in scripts/vendor.sha256." >&2
        echo "A vendored file was added or removed without updating the manifest." >&2
        echo "Re-run with --write-manifest in the same diff as the change." >&2
        exit 1
    fi
    if ! shasum -a 256 -c "$MANIFEST" >/dev/null; then
        echo "ERROR: a vendored file does not match scripts/vendor.sha256." >&2
        echo "A download was corrupted or tampered, or a library version changed" >&2
        echo "without updating the manifest (re-run with --write-manifest)." >&2
        exit 1
    fi
    echo "Vendor integrity verified against scripts/vendor.sha256 ($manifest_count files)."
fi

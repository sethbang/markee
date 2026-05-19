#!/usr/bin/env bash
# Sign Markee.app and its Quick Look extensions.
#
# Uses a Developer ID Application identity when one is available — taken from
# $CODESIGN_IDENTITY, else auto-detected from the keychain — and applies the
# Hardened Runtime plus a secure timestamp (both required for notarization).
# When no Developer ID identity is found it falls back to ad-hoc signing, so CI
# build-test and contributors without the certificate can still build.
#
# Usage: scripts/sign-app.sh [path/to/Markee.app]   (default: Markee.app)

set -euo pipefail

APP="${1:-Markee.app}"

if [ ! -d "$APP" ]; then
    echo "sign-app: no app bundle at '$APP'" >&2
    exit 1
fi

# Resolve the signing identity: explicit override ($CODESIGN_IDENTITY, a name
# or a SHA-1 hash), else the first Developer ID Application identity in the
# keychain. Auto-detection matches by SHA-1 hash (field 2) rather than name:
# a keychain may hold more than one cert with the same name, and codesign
# rejects an ambiguous name.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    # Match by SHA-1 hash (field 2), not name: a keychain may hold more than
    # one cert with the same name, and codesign rejects an ambiguous name.
    # A single awk (no grep) prints nothing and exits 0 on no match, so the
    # ad-hoc fallback below stays reachable under `set -euo pipefail`.
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/Developer ID Application/ { print $2; exit }')
fi

PREVIEW_APPEX="$APP/Contents/PlugIns/QuickLookPreview.appex"
THUMBNAIL_APPEX="$APP/Contents/PlugIns/QuickLookThumbnail.appex"

if [ -n "$IDENTITY" ]; then
    echo "sign-app: Developer ID signing as: $IDENTITY"
    SIGN_ARGS=(--force --options runtime --timestamp --sign "$IDENTITY")
else
    echo "sign-app: no Developer ID identity found — ad-hoc signing"
    SIGN_ARGS=(--force --sign -)
fi

# Sign inside-out: nested extensions first, then the app. `codesign --deep` is
# deprecated and seals nested code unreliably — sign each item explicitly.
#
# The two Quick Look extensions MUST be App-Sandboxed — pkd refuses to register
# an unsandboxed Quick Look extension. The app itself is NOT sandboxed (it
# watches and writes Markdown files at arbitrary paths).
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
EXT_ENTITLEMENTS="$SCRIPT_DIR/../Resources/QuickLookExtension.entitlements"
if [ ! -f "$EXT_ENTITLEMENTS" ]; then
    echo "sign-app: missing $EXT_ENTITLEMENTS" >&2
    exit 1
fi

for appex in "$PREVIEW_APPEX" "$THUMBNAIL_APPEX"; do
    if [ -d "$appex" ]; then
        echo "sign-app: signing $appex (sandboxed extension)"
        codesign "${SIGN_ARGS[@]}" --entitlements "$EXT_ENTITLEMENTS" "$appex"
    fi
done

if [ -d "$APP" ]; then
    echo "sign-app: signing $APP"
    codesign "${SIGN_ARGS[@]}" "$APP"
fi

codesign --verify --strict --verbose=2 "$APP"
echo "sign-app: done ($APP)"

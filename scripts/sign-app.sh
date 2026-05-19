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

# Resolve the signing identity: explicit override, else first Developer ID
# Application identity in the keychain search list.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" \
        | head -1 \
        | sed -E 's/.*"(.+)"$/\1/')
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
for item in "$PREVIEW_APPEX" "$THUMBNAIL_APPEX" "$APP"; do
    if [ -e "$item" ]; then
        echo "sign-app: signing $item"
        codesign "${SIGN_ARGS[@]}" "$item"
    fi
done

codesign --verify --strict --verbose=2 "$APP"
echo "sign-app: done ($APP)"

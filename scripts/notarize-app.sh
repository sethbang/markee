#!/usr/bin/env bash
# Notarize a Developer-ID-signed Markee.app and staple the ticket.
#
# Credentials (one of):
#   - NOTARY_KEYCHAIN_PROFILE: name of a profile stored via
#     `xcrun notarytool store-credentials` (local use).
#   - NOTARY_KEY_P8_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID: an App Store
#     Connect API key file and its identifiers (CI use).
#
# Usage: scripts/notarize-app.sh [path/to/Markee.app]   (default: Markee.app)

set -euo pipefail

APP="${1:-Markee.app}"

if [ ! -d "$APP" ]; then
    echo "notarize-app: no app bundle at '$APP'" >&2
    exit 1
fi

# Refuse an ad-hoc bundle — notarization needs a Developer ID signature.
if codesign -dvv "$APP" 2>&1 | grep -q "Signature=adhoc"; then
    echo "notarize-app: '$APP' is ad-hoc signed — run a Developer ID build first" >&2
    exit 1
fi

# Assemble notarytool credential arguments.
if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
    CRED_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [ -n "${NOTARY_KEY_P8_PATH:-}" ] \
  && [ -n "${NOTARY_KEY_ID:-}" ] \
  && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
    CRED_ARGS=(--key "$NOTARY_KEY_P8_PATH" \
               --key-id "$NOTARY_KEY_ID" \
               --issuer "$NOTARY_ISSUER_ID")
else
    echo "notarize-app: no credentials — set NOTARY_KEYCHAIN_PROFILE, or" >&2
    echo "              NOTARY_KEY_P8_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID" >&2
    exit 1
fi

ZIP="${APP%.app}.notarize.zip"
echo "notarize-app: zipping $APP -> $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "notarize-app: submitting to Apple (this can take a few minutes)..."
SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP" "${CRED_ARGS[@]}" --wait 2>&1) || true
echo "$SUBMIT_OUTPUT"
SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | awk -F': *' '/^ *id:/{print $2; exit}')

if ! echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo "notarize-app: notarization was not Accepted" >&2
    if [ -n "${SUBMISSION_ID:-}" ]; then
        echo "notarize-app: --- notarytool log ---" >&2
        xcrun notarytool log "$SUBMISSION_ID" "${CRED_ARGS[@]}" >&2 || true
    fi
    rm -f "$ZIP"
    exit 1
fi

rm -f "$ZIP"

echo "notarize-app: stapling ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"
echo "notarize-app: done — $APP is notarized and stapled"

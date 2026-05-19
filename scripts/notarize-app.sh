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

ZIP="${APP%.app}-notarize.zip"
trap 'rm -f "$ZIP"' EXIT  # clean the submission zip on any exit, incl. Ctrl-C

echo "notarize-app: zipping $APP -> $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "notarize-app: submitting to Apple (this can take a few minutes)..."
# Capture output and exit code without `set -e` aborting on a non-zero rc:
# success is decided by the reported status, not notarytool's exit code
# (its exit semantics for a rejected submission are not reliable).
set +e
SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP" "${CRED_ARGS[@]}" --wait 2>&1)
SUBMIT_RC=$?
set -e
echo "$SUBMIT_OUTPUT"
SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | awk -F': *' '/^ *id:/{print $2; exit}')

if ! echo "$SUBMIT_OUTPUT" | grep -qE '^[[:space:]]*status: Accepted[[:space:]]*$'; then
    if [ -n "$SUBMISSION_ID" ]; then
        echo "notarize-app: notarization was not Accepted — fetching the log" >&2
        xcrun notarytool log "$SUBMISSION_ID" "${CRED_ARGS[@]}" >&2 || true
    else
        echo "notarize-app: notarytool submit failed before a submission was created" >&2
        echo "notarize-app: (rc=$SUBMIT_RC) — check credentials and network" >&2
    fi
    exit 1
fi

echo "notarize-app: stapling ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

if ! spctl -a -vvv -t exec "$APP"; then
    echo "notarize-app: Gatekeeper assessment failed — see spctl output above" >&2
    exit 1
fi
echo "notarize-app: done — $APP is notarized and stapled"

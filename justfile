# Markee build & dev tasks. Run `just` (or `just --list`) to see every recipe.

app_name    := "Markee"
app_bundle  := app_name + ".app"
config      := "release"
bin         := ".build/release/" + app_name
preview_bin := ".build/release/MarkeeQuickLookPreview"
thumb_bin   := ".build/release/MarkeeQuickLookThumbnail"
installed   := "/Applications/" + app_bundle
bundle_id   := "com.markee.preview"
lsregister  := "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# List all recipes (runs on bare `just`).
default:
    @just --list

# Compile the Swift package (release config).
build:
    swift build -c {{config}}

# Regenerate the .icns app/document icons from the SVG sources.
icon:
    ./scripts/build-icon.sh

# Fetch pinned JS/CSS into Resources/web/vendor/ on first run; skip thereafter.
fetch-vendor:
    [ -f Resources/web/vendor/.fetched ] || { ./scripts/fetch-vendor.sh && touch Resources/web/vendor/.fetched; }

# Build the signed Markee.app bundle (vendor + binaries + Quick Look extensions).
app: fetch-vendor build icon
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf {{app_bundle}}
    mkdir -p {{app_bundle}}/Contents/MacOS
    mkdir -p {{app_bundle}}/Contents/Resources
    cp {{bin}} {{app_bundle}}/Contents/MacOS/{{app_name}}
    cp Resources/Info.plist {{app_bundle}}/Contents/Info.plist
    cp Resources/AppIcon.icns {{app_bundle}}/Contents/Resources/AppIcon.icns
    cp Resources/DocIcon.icns {{app_bundle}}/Contents/Resources/DocIcon.icns
    cp -R Resources/web {{app_bundle}}/Contents/Resources/
    cp -R Resources/cli {{app_bundle}}/Contents/Resources/
    cp "Resources/Support Markee.md" "{{app_bundle}}/Contents/Resources/Support Markee.md"
    cp LICENSE {{app_bundle}}/Contents/Resources/LICENSE
    cp THIRD-PARTY-NOTICES.md {{app_bundle}}/Contents/Resources/THIRD-PARTY-NOTICES.md
    # Quick Look extensions into Contents/PlugIns/
    mkdir -p {{app_bundle}}/Contents/PlugIns/QuickLookPreview.appex/Contents/MacOS
    mkdir -p {{app_bundle}}/Contents/PlugIns/QuickLookPreview.appex/Contents/Resources
    cp {{preview_bin}} {{app_bundle}}/Contents/PlugIns/QuickLookPreview.appex/Contents/MacOS/MarkeeQuickLookPreview
    cp Resources/QuickLookPreview-Info.plist {{app_bundle}}/Contents/PlugIns/QuickLookPreview.appex/Contents/Info.plist
    cp -R Resources/web {{app_bundle}}/Contents/PlugIns/QuickLookPreview.appex/Contents/Resources/
    mkdir -p {{app_bundle}}/Contents/PlugIns/QuickLookThumbnail.appex/Contents/MacOS
    mkdir -p {{app_bundle}}/Contents/PlugIns/QuickLookThumbnail.appex/Contents/Resources
    cp {{thumb_bin}} {{app_bundle}}/Contents/PlugIns/QuickLookThumbnail.appex/Contents/MacOS/MarkeeQuickLookThumbnail
    cp Resources/QuickLookThumbnail-Info.plist {{app_bundle}}/Contents/PlugIns/QuickLookThumbnail.appex/Contents/Info.plist
    cp -R Resources/web {{app_bundle}}/Contents/PlugIns/QuickLookThumbnail.appex/Contents/Resources/
    # Sign: Developer ID + Hardened Runtime when available, ad-hoc otherwise.
    ./scripts/sign-app.sh {{app_bundle}}
    echo "Built {{app_bundle}}"
    if [ -L "{{installed}}" ] || [ -d "{{installed}}" ]; then
        echo "Syncing to {{installed}}..."
        rm -rf "{{installed}}"
        cp -R {{app_bundle}} "{{installed}}"
        {{lsregister}} -f "{{installed}}"
    fi

# Install Markee.app to /Applications (quits a running instance first).
install: app
    #!/usr/bin/env bash
    set -euo pipefail
    osascript -e 'tell application "Markee" to quit' 2>/dev/null || true
    rm -rf "{{installed}}"
    cp -R {{app_bundle}} "{{installed}}"
    {{lsregister}} -f "{{installed}}"
    echo "Installed {{installed}}"

# Symlink the `markee` CLI launcher into /usr/local/bin.
install-cli: app
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -w /usr/local/bin ]; then
        ln -sf "$(pwd)/{{app_bundle}}/Contents/Resources/cli/markee" /usr/local/bin/markee
        echo "Installed /usr/local/bin/markee"
    else
        echo "Need write access to /usr/local/bin. Try: sudo just install-cli"
        exit 1
    fi

# Build and open Markee.app.
run: app
    open {{app_bundle}}

# Build, sign, notarize, and staple the bundle.
notarize: app
    ./scripts/notarize-app.sh {{app_bundle}}

# Run all tests (Swift + JS).
test: test-swift test-js

# Swift unit tests (XCTest).
test-swift:
    swift test

# JS pure-helper + render-snapshot + wiki-link tests.
test-js:
    node --test Tests/util.test.js Tests/render.test.js Tests/wikilink.test.js Tests/reflow.test.js

# Remove build products and the vendored JS libraries.
clean:
    swift package clean
    rm -rf .build {{app_bundle}} Resources/web/vendor

# --- Fresh-install lifecycle (un-licensed / licensing-pipeline testing) ---

# (private) Quit a running Markee instance.
_quit:
    @osascript -e 'tell application "Markee" to quit' 2>/dev/null || true

# (private) Wipe ALL persisted Markee state — the entire defaults domain.
_wipe:
    @defaults delete {{bundle_id}} 2>/dev/null || true

# Reset to a fresh, un-licensed install: wipe all state, relaunch fresh bits.
reset: _quit app _wipe
    @echo "Wiped {{bundle_id}}; relaunching fresh (quit Markee to return)…"
    ./{{app_bundle}}/Contents/MacOS/{{app_name}}

# Like reset, but force the supporter nudges on immediately (no grace period).
reset-nudges: _quit app _wipe
    @echo "Wiped {{bundle_id}}; relaunching with nudges forced on…"
    MARKEE_FORCE_NUDGES=1 ./{{app_bundle}}/Contents/MacOS/{{app_name}}

# Like reset-nudges, but point at the Polar sandbox (sources .env.local) for licensing tests.
reset-sandbox: _quit app _wipe
    #!/usr/bin/env bash
    set -euo pipefail
    set -a; [ -f .env.local ] && source .env.local; set +a
    echo "Wiped {{bundle_id}}; relaunching against Polar sandbox (${MARKEE_POLAR_BASE_URL:-<unset>})…"
    MARKEE_FORCE_NUDGES=1 ./{{app_bundle}}/Contents/MacOS/{{app_name}}

# Launch with the developer menu and forced supporter state (no Polar calls).
dev: _quit app
    @echo "Launching with Debug menu + forced nudges + forced supporter state…"
    MARKEE_DEV_TOOLS=1 MARKEE_FORCE_NUDGES=1 MARKEE_FORCE_SUPPORTER=1 ./{{app_bundle}}/Contents/MacOS/{{app_name}}

# Full from-scratch: remove installed + built app, rebuild, reinstall, wipe, relaunch.
clean-install: _quit
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{installed}}" {{app_bundle}}
    swift package clean
    just app
    cp -R {{app_bundle}} "{{installed}}"
    {{lsregister}} -f "{{installed}}"
    defaults delete {{bundle_id}} 2>/dev/null || true
    echo "Clean install complete; relaunching fresh…"
    open "{{installed}}"

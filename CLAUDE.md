# Markee — orientation for Claude Code

A native macOS app that watches a Markdown file on disk and re-renders a
preview every time it's saved. Editor-agnostic. Built with SwiftUI + WKWebView;
the actual rendering happens in JavaScript inside the WebView (markdown-it +
plugins, KaTeX, highlight.js, Mermaid). It also ships a Quick Look preview
extension, per-file Finder thumbnails, and a Markdown document icon, and is
distributed outside the App Store as a Developer-ID-signed, notarized `.app`.

## Run

```sh
make fetch-vendor   # one-time: downloads JS/CSS into Resources/web/vendor/ (gitignored)
make app            # builds Markee.app at the repo root
make run            # builds + opens
make test           # swift test + node --test Tests/util.test.js
make install        # builds and installs Markee.app to /Applications
make notarize       # builds, signs, notarizes, and staples (see "Signing & notarization")
```

`swift build` alone produces just the executables in `.build/`; `make app`
assembles the usable `.app` bundle — Info.plist, icons, `Resources/`, and the
two Quick Look extensions under `Contents/PlugIns/`.

## Layout

- `Sources/MarkeeKit/` — shared library used by the app and both extensions
  - `WebRenderer.swift` — headless WKWebView Markdown renderer
  - `SchemeHandlers.swift` — `markee-app://` (bundle resources) and
    `markee-doc://` (the document's directory, path-traversal sandboxed)
  - `FileReader.swift` — encoding-tolerant file reader
  - `Timeout.swift`, `ThumbnailLayout.swift` — async-timeout and thumbnail
    page-fit helpers
- `Sources/Markee/` — the SwiftUI app
  - `MarkeeApp.swift` — `@main`, `DocumentGroup`, menu commands, CLI installer
  - `MarkdownDocument.swift` — read-only `FileDocument` (no content stored;
    `PreviewView` reloads from disk)
  - `PreviewController.swift` — per-window controller owning the WKWebView +
    FileWatcher; routes JS messages, handles export-HTML and task-toggle
    write-back
  - `PreviewView.swift` — SwiftUI view: HSplitView (outline + WebView)
  - `FileWatcher.swift` — kqueue-backed (DispatchSource) with atomic-save
    reattach logic
- `Sources/MarkeeQuickLookPreview/` — Quick Look preview extension
  (`QLPreviewingController`) → `QuickLookPreview.appex`
- `Sources/MarkeeQuickLookThumbnail/` — Quick Look thumbnail extension
  (`QLThumbnailProvider`) → `QuickLookThumbnail.appex`
- `Resources/web/` — HTML/JS/CSS shipped into every bundle
  - `template.html` — loads vendor scripts, then `util.js`, then `app.js`
  - `app.js` — IIFE wrapping `render`, `scrollToHeading`, `exportStandalone`,
    the task-toggle click handler. Exposes `window.markee`.
  - `util.js` — pure helpers (`collectTaskLineNumbers`, `slugify`), UMD so Node
    can require them for tests
  - `theme.css` — built-in light/dark theme
  - `vendor/` — fetched libs; **gitignored**
- `Resources/Info.plist`, `Resources/QuickLookPreview-Info.plist`,
  `Resources/QuickLookThumbnail-Info.plist` — app and extension bundle plists
- `Resources/QuickLookExtension.entitlements` — App Sandbox entitlements for
  the extensions (see "Signing & notarization")
- `Resources/AppIcon.svg`, `Resources/DocIcon.svg` — icon sources; the `.icns`
  files are built and gitignored
- `Resources/cli/markee` — shell launcher (`open -b com.markee.preview`)
- `scripts/` — `fetch-vendor.sh` (pinned jsdelivr downloads), `build-icon.sh`
  (`sips` + `iconutil`), `sign-app.sh`, `notarize-app.sh`
- `Tests/MarkeeTests/`, `Tests/MarkeeKitTests/` — Swift unit tests;
  `Tests/util.test.js` — Node `--test` runner over `util.js`
- `.github/workflows/` — `ci.yml` (lint + build/test on push/PR) and
  `release.yml` (tag-triggered signed + notarized release)
- `fixtures/sample.md` — exercises every feature

## How the JS↔Swift bridge works

- Swift loads `markee-app://app/template.html` into the WebView at window open.
- After `app.js` finishes setup, it posts `{kind: "ready"}` via `webkit.messageHandlers.markee` → Swift flips `templateLoaded` and flushes any queued `render`.
- Every file change: Swift reads the file, serializes `{source, fileName, docBase}` to JSON, calls `evaluateJavaScript("window.markee.render(<json>);")`.
- JS replies with `{kind: "outline", items}` for the sidebar, `{kind: "error", message}` for renderer exceptions, `{kind: "taskToggle", line, checked}` for clicked checkboxes.
- Relative URLs in markdown (e.g. `![](pic.png)`) resolve via `<base href="markee-doc://doc/">`, which Swift's `DocSchemeHandler` maps to the document directory (path traversal blocked).

## Non-obvious invariants (don't break these)

- **FileWatcher.attach() must not call cancelInternal().** It would clobber the `changeDebounce` that `scheduleReattach()` schedules right before invoking `attach()`. Use `releaseSource()` (just the dispatch source). Caught by `test_atomicRenameFiresCallbackAfterReattach`.
- **`collectTaskLineNumbers` runs on the original source**, front matter and all, because Swift writes back to the file by absolute line index. Don't pass it the post-front-matter-stripped string.
- **Swift's `toggleTask` re-reads the file before writing** and bails if the target line no longer matches the `[ ]/[x]` regex. This is the only protection against clobbering concurrent edits in another editor. Keep it.
- **Line endings are preserved** in `toggleTask` by splitting on `"\n"`, leaving trailing `\r` inside each line, and joining on `"\n"`. Don't "normalize" them.
- **Mermaid uses the UMD bundle (`mermaid.min.js`), not the ESM split build.** The ESM entry imports a tree of separate chunk files that doesn't resolve cleanly under our custom URL scheme.
- **Renaming the app means updating four things in lockstep**: bundle id (`com.markee.preview`), URL schemes (`markee-app`, `markee-doc`), JS global (`window.markee`), and the `webkit.messageHandlers` name (`markee`).
- **The custom titlebar relies on `WindowAccessor` flipping `titlebarAppearsTransparent` / `titleVisibility` / `.fullSizeContentView` on the host `NSWindow`.** SwiftUI's `.toolbar` modifier reintroduces a toolbar area — don't add it back. The traffic-light gutter in `MarkeeTitlebar` is reserved by `leftGutter: 78` and mirrored on the right so the centered filename stays centered. Resizing the window narrowly enough may push the filename behind the toggle; this is acceptable.
- **`pickActiveHeading` (util.js) and the IntersectionObserver (app.js) are paired.** The observer uses `rootMargin: "0px 0px -80% 0px"` to fire when a heading enters the top 20% of the viewport; the helper picks the last heading whose top is ≤ 20% of viewport height. If you change one, change the other to match.
- **WKWebView does NOT render `::before` / `::after` pseudo-elements on `<input>`.** The custom task-list checkbox checkmark uses a `background-image: url("data:image/svg+xml;...")` instead. Do not try to switch back to `::after`.

## Conventions

- Default to **no comments**; annotate WHY only when non-obvious (invariants,
  workarounds, bug references).
- Build products are gitignored and must never be committed: `Markee.app`,
  `Resources/AppIcon.icns`, `Resources/DocIcon.icns`, `Resources/web/vendor/`.
- `.claude/` and `docs/superpowers/` are gitignored — intentionally local.

## Signing & notarization

Markee is distributed as a Developer-ID-signed, notarized app. Both the app and
its two Quick Look `.appex` extensions are signed with the **Developer ID
Application** certificate and the Hardened Runtime, then the bundle is notarized
by Apple and the ticket stapled. The app itself is **not** sandboxed — it watches and writes Markdown files at arbitrary paths. The two Quick Look `.appex` extensions, however, **are** sandboxed (`Resources/QuickLookExtension.entitlements`): `pkd` refuses to register an unsandboxed Quick Look extension. Their entitlements are `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-only` (to read the previewed file), and `com.apple.security.network.client` — the last is **load-bearing**: without it `WKWebView`'s helper processes crash inside the sandboxed extension and the renderer hangs forever (preview shows an endless spinner). `sign-app.sh` signs the extensions with those entitlements and the app without.

- `scripts/sign-app.sh` signs the bundle inside-out. With a Developer ID
  identity in the keychain it signs Developer ID + Hardened Runtime; with none
  it falls back to ad-hoc (so CI build-test and contributors still build).
- `scripts/notarize-app.sh` zips, submits to `notarytool`, and staples.
- `make app` signs; `make notarize` builds + signs + notarizes + staples.

**Local setup (one-time):**
- Install the "Developer ID Application" certificate in your login keychain
  (Xcode → Settings → Accounts → Manage Certificates, or the developer portal).
- Store the App Store Connect API key as a notarytool keychain profile:
  `xcrun notarytool store-credentials markee-notary --key <AuthKey.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>`
- Then `NOTARY_KEYCHAIN_PROFILE=markee-notary make notarize` produces a
  notarized, stapled bundle.

**CI:** `release.yml` (tag-triggered) imports the cert and notarizes
automatically. It needs five repo secrets: `MACOS_CERT_P12` (base64 of the
Developer ID `.p12`), `MACOS_CERT_PASSWORD`, `NOTARY_KEY_P8` (base64 of the API
key `.p8`), `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`. `ci.yml` (push/PR) stays
ad-hoc — signing secrets must never reach PR builds.

## Not yet built

- DMG installer / Homebrew cask
- In-app theme picker / custom CSS
- A print-tuned stylesheet (printing currently reuses the screen CSS)
- True MultiMarkdown citation / cross-reference support (GFM-ish via plugins today)

## Useful one-liners

```sh
# Quit any running instance before rebuilding
osascript -e 'tell application "Markee" to quit'

# Check the running process
pgrep -fl Markee.app/Contents/MacOS/Markee
```

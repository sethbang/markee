# Markee — orientation for Claude Code

A native macOS app that watches a Markdown file on disk and re-renders a
preview every time it's saved. Editor-agnostic. Built with SwiftUI + WKWebView;
the actual rendering happens in JavaScript inside the WebView (markdown-it +
plugins, KaTeX, highlight.js, Mermaid). It also ships a Quick Look preview
extension, per-file Finder thumbnails, and a Markdown document icon, and is
distributed outside the App Store as a Developer-ID-signed, notarized `.app`.

## Run

```sh
just fetch-vendor   # downloads JS/CSS into Resources/web/vendor/ (gitignored) + verifies the manifest
just app            # builds Markee.app at the repo root (never touches /Applications)
just run            # builds + opens
just reset          # wipe ALL local state + relaunch a fresh, un-licensed install
just reset-nudges   # like reset, but force the supporter nudges on immediately (no grace period)
just reset-sandbox  # like reset-nudges, but point at the Polar sandbox (sources .env.local) for licensing tests
just clean-install  # full from-scratch: remove + rebuild + reinstall + wipe + relaunch
just test           # swift test + node --test (util, render, wikilink, reflow .test.js)
just dev            # launch with the Debug menu (MARKEE_DEV_TOOLS=1) + forced nudge/supporter state
just install        # builds, quits Markee, replaces /Applications/Markee.app
just notarize       # builds, signs, notarizes, and staples (see "Signing & notarization")
```

Swift tests need full Xcode — the Command Line Tools have no XCTest, so if
`xcode-select -p` points at CommandLineTools, prefix with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (same for
`swiftlint`). Never run `just reset*`/`clean-install` casually: see the
Polar activation note under invariants.

`swift build` alone produces just the executables in `.build/`; `just app`
assembles the usable `.app` bundle — Info.plist, icons, `Resources/`, and the
two Quick Look extensions under `Contents/PlugIns/`.

## Layout

- `Sources/MarkeeKit/` — shared library used by the app and both extensions
  - `WebRenderer.swift` — headless WKWebView Markdown renderer (Quick Look:
    remote-load block list, template-pinned navigation, throwing `render`)
  - `WeakScriptMessageHandler.swift` — weak trampoline every `markee`
    message-handler registration goes through (avoids the retain cycle)
  - `SchemeHandlers.swift` — `markee-app://` (bundle resources) and
    `markee-doc://` (rooted at the workspace root; each document keeps its own
    `<base href>` so relative links still resolve — path traversal above the
    root blocked by `resolveSandboxed`)
  - `FileReader.swift` — encoding-tolerant reader (`readDecodedFile` returns
    the detected encoding + BOM so write-back is byte-compatible)
  - `Timeout.swift`, `ThumbnailLayout.swift` — async-timeout and thumbnail
    page-fit helpers
- `Sources/Markee/` — the SwiftUI app
  - `MarkeeApp.swift` — `@main`, `DocumentGroup`, menu commands, CLI installer
  - `MarkdownDocument.swift` — read-only `FileDocument` (no content stored;
    `PreviewView` reloads from disk)
  - `PreviewController.swift` — per-window controller owning the WKWebView +
    FileWatcher; routes JS messages, drives in-window navigation (back/forward)
    and the workspace search palette, and handles export-HTML/PDF, print, zoom,
    settings push, window pinning, open-in-editor, and task-toggle write-back
  - `PreviewView.swift` — SwiftUI view: titlebar + sidebar (outline/files) +
    WebView, plus the workspace search palette overlay
  - `WorkspaceModel.swift` / `NavigationHistory.swift` / `WorkspaceSearch.swift`
    — Phase 5 docs-navigation units: the workspace root + `.md` index + file
    tree (`ObservableObject`), the pure back/forward stack, and full-text
    search with a pure ranking function. `PreviewController` wires them together.
  - `FileWatcher.swift` — kqueue-backed (DispatchSource) with atomic-save
    reattach logic
  - `SupportNudgeState.swift` / `SupportController.swift` / `SupportViews.swift`
    / `LicenseActivation.swift` — optional Polar.sh supporter license: pure
    nudge-cadence logic, the `UserDefaults`-backed controller + key redemption,
    the SwiftUI surfaces (titlebar ♥ → `SupportDrawer` popover, menu, About
    credits), and the pure Polar wire format. Nothing is feature-gated; paying
    only silences the throttled nudges (a monthly support doc) and removes the
    heart. Activation hits Polar's public (unauthenticated) customer-portal
    endpoint, so no API key ships in the app. `SupportConfig` reads
    `MARKEE_POLAR_BASE_URL`/`MARKEE_POLAR_ORG_ID` from the environment to point
    a local build at the Polar sandbox for testing. **Dormant until go-live:**
    `SupportConfig.productionOrganizationID` is empty while the Polar org is in
    test mode, which hides the whole supporter surface (heart, menu items,
    monthly doc); restore it with the `/support` redirect and footer link at
    licensing go-live.
  - `UsageStats.swift` / `UsageTracker.swift` — local-only usage counters
    (documents previewed, re-renders watched, active days, boxes checked) shown
    in the support drawer. File paths are stored only as salted, truncated SHA-256
    hashes (salt kept in the same defaults domain — it prevents lookup tables,
    not local guessing); nothing here is ever transmitted.
  - `SettingsStore.swift` / `SettingsView.swift` — Preferences window (Settings
    scene, ⌘,): the `UserDefaults`-backed source of truth (theme override,
    accent, base font, custom-CSS path, update-check, default-float, editor),
    broadcasting `.settingsDidChange`; and the General/Appearance `TabView`.
  - `WindowPinState.swift` / `WindowPinController.swift` /
    `WindowPinCommands.swift` — window pinning: the pure state→AppKit mappings
    (float-on-top, all-spaces/follow-active, ghost-mode dimming), the
    controller applying them with hover/key tracking, and the Window-menu pin
    commands (Float on Top ⌥⌘P, Visible on All Spaces, Move to Active Space,
    Ghost Mode).
  - `MarkeeTitlebar.swift` / `WindowAccessor.swift` — the custom titlebar view
    (centered filename, sidebar toggle, back/forward chevrons, support heart,
    word-count pill) and the `NSWindow` accessor that flips the titlebar flags.
  - `TaskToggle.swift` — pure checkbox-line rewrite behind task write-back.
  - `DebugCommands.swift` — Debug menu (only with `MARKEE_DEV_TOOLS=1`, i.e.
    `just dev`): licensing-state controls such as Deactivate This Mac.
  - `PreviewController+Export.swift` — print, Export PDF, Export HTML.
  - `BridgeMessage.swift` — typed, pure parse of every `markee` bridge
    message; the trust check stays in `userContentController`.
  - `NavigationPolicy.swift` — pure main-frame/link navigation decisions
    (template-only main frame, link hand-off, safe-to-open file types).
  - `MarkeeWebView.swift` — `WKWebView` subclass extending the native
    right-click menu (Copy Markdown Source, Reveal in Finder).
  - `Updater.swift` — in-app updater (checks GitHub Releases, downloads,
    validates, swaps in place, relaunches); `EditorLauncher.swift` —
    open-in-editor binary resolution + per-editor line-jump argv.
  (This list is a curated overview, not an exhaustive file index.)
- `Sources/MarkeeQuickLookPreview/` — Quick Look preview extension
  (`QLPreviewingController`) → `QuickLookPreview.appex`
- `Sources/MarkeeQuickLookThumbnail/` — Quick Look thumbnail extension
  (`QLThumbnailProvider`) → `QuickLookThumbnail.appex`
- `Resources/web/` — HTML/JS/CSS shipped into every bundle
  - `template.html` — strict CSP, then vendor scripts, then `util.js`,
    `render-core.js`, `reflow.js`, then `app.js`
  - `app.js` — IIFE wrapping `render`, `scrollToHeading`, `exportStandalone`,
    `reflow`, `renderedText`, `setZoom`, `applySettings`, `find`/`clearFind`,
    `toast`, plus the task-toggle, `#fragment` and in-window `.md`-link
    navigation handlers. Exposes `window.markee`.
  - `util.js` — pure helpers (`slugify`, `pickActiveHeading`, find/selection
    and currency-mask helpers), UMD so Node can require them for tests
  - `render-core.js` — markdown-it pipeline construction (`createRenderer`,
    `splitFrontMatter`/`stripFrontMatter`, `escapeHtml`, the source-line
    `data-line` stamping); UMD so Node snapshot tests can require it
  - `reflow.js` — Copy Reflowed Markdown (⌥⌘C): unwraps soft-wrapped
    paragraphs using the same markdown-it parse; exposes `window.markeeReflow`
  - `theme.css` — built-in light/dark theme
  - `vendor/` — fetched libs; **gitignored**
- `Resources/Info.plist`, `Resources/QuickLookPreview-Info.plist`,
  `Resources/QuickLookThumbnail-Info.plist` — app and extension bundle plists
- `Resources/QuickLookExtension.entitlements` — App Sandbox entitlements for
  the extensions (see "Signing & notarization")
- `Resources/AppIcon.svg`, `Resources/DocIcon.svg` — icon sources; the `.icns`
  files are built and gitignored
- `Resources/cli/markee` — shell launcher (`open -b com.markee.preview`)
- `scripts/` — `fetch-vendor.sh` (pinned jsdelivr downloads, verified against
  `vendor.sha256`), `build-icon.sh` (`sips` + `iconutil`), `sign-app.sh`,
  `notarize-app.sh`
- `scripts/vendor.sha256` — SHA-256 manifest of every vendored file;
  `fetch-vendor.sh` fails on mismatch
- `Tests/MarkeeTests/`, `Tests/MarkeeKitTests/` — Swift unit tests;
  `Tests/{util,render,wikilink,reflow}.test.js` — Node `--test` suites
  (helpers, render snapshot + source lines + attrs allowlist, wiki-links,
  reflow); `Tests/snapshots/sample.html` is the render golden
- `.github/workflows/` — `ci.yml` (lint + build/test on push/PR) and
  `release.yml` (tag-triggered signed + notarized release)
- `fixtures/sample.md` — exercises most rendering features
- `site/` + `wrangler.toml` — the markee.sbang.dev landing page, deployed as
  Cloudflare Workers static assets (`_headers` carries its CSP/HSTS)

## How the JS↔Swift bridge works

- Swift loads `markee-app://app/template.html` into the WebView at window open.
- After `app.js` finishes setup, it posts `{kind: "ready"}` via `webkit.messageHandlers.markee` → Swift flips `templateLoaded` and flushes any queued `render`.
- Every file change: Swift reads the file, serializes `{source, fileName, docBase, wikiIndex, readOnly}` to JSON (plus `navigated` and `scrollTo` on cross-file navigation), calls `evaluateJavaScript("window.markee.render(<json>);")`.
- JS posts back `ready`, `outline` (sidebar items), `scrollSection` (active heading), `docStats` (word-count pill), `findResult`, `error` (banner), `copyText` (writes the pasteboard), `taskToggle` (checkbox write-back) and `navigate` (in-window/new-window `.md` navigation). The full list lives at the top of `app.js`.
- Relative URLs in markdown (e.g. `![](pic.png)`) resolve via a `<base href>` that `app.js` injects per render from the payload's `docBase` (`markee-doc://doc/<docDir-relative-to-workspace-root>/`, from `WorkspaceModel.docBase`). Swift's `DocSchemeHandler` is rooted at the workspace root and serves any file beneath it, with path traversal above the root blocked by `resolveSandboxed`.

## Non-obvious invariants (don't break these)

- **Rendered Markdown is untrusted; `template.html`'s CSP is the boundary.**
  `script-src markee-app:` only — never add `'unsafe-inline'`/`'unsafe-eval'`
  or `markee-doc:` to it (that re-enables `onerror=` handlers and workspace
  `.js`). `markdown-it-attrs` runs with an `allowedAttributes` allowlist; an
  unrestricted attrs plugin emits `on*` attributes regardless of `html: true`.
  `WebRendererTests.test_templateCSPBlocksDocumentScriptButRenders` covers both.
- **The main frame only ever holds `template.html`** (`NavigationPolicy`). Any
  other main-frame load would replace the preview and inherit the bridge.
  `#fragment` links resolve against `<base href>` (the doc's directory), so
  `app.js` scrolls them in place instead of letting them navigate.
- **The `markee` bridge only accepts the template's main frame**
  (`frameInfo.isMainFrame` + template request URL), and is registered through
  `WeakScriptMessageHandler` — registering the controller directly is a retain
  cycle that leaks every closed window.
- **Quick Look blocks all remote loads** with a `WKContentRuleList`
  (`WebRenderer.loadTemplate`, fails closed). Content-blocker regexes have no
  `|` alternation — one rule per scheme.
- **FileWatcher.attach() must not call cancelInternal().** It would clobber the `changeDebounce` that `scheduleReattach()` schedules right before invoking `attach()`. Use `releaseSource()` (just the dispatch source). Caught by `test_atomicRenameFiresCallbackAfterReattach`.
- **Task and heading source lines come from markdown-it's token maps**, stamped
  as `data-line` by `sourceLinePlugin` in `render-core.js` with
  `env.lineOffset` = the front-matter line count, so they index the ORIGINAL
  file. Never pair a separate line scan with the DOM by position — that drifted
  on blockquotes, fences in list items, HTML blocks and CRLF front matter and
  rewrote the wrong line. `splitFrontMatter` is the one front-matter definition
  (render, lines, reflow); `Tests/render.test.js` checks every stamped task line
  against the Swift regex.
- **Swift's `toggleTask` re-reads the file before writing** and bails if the target line no longer matches `TaskToggle`'s regex (which must accept every marker render-core stamps: bullets, `1.`/`1)`, `>` prefixes). This is the only protection against clobbering concurrent edits in another editor. Keep it. Every bail re-renders from disk so the clicked checkbox snaps back.
- **`toggleTask` writes back byte-compatibly**: through symlinks (to the resolved target), in the encoding and BOM `readDecodedFile` detected.
- **Line endings are preserved** in `TaskToggle` by splitting on `"\n"`, leaving trailing `\r` inside each line, and joining on `"\n"`. Don't "normalize" them.
- **`Resources/Support Markee.md` must contain no task checkboxes.** It's opened from the read-only app bundle; a `- [ ]`/`- [x]` would invite a task-toggle write-back that fails against the signed bundle. Keep the support-nudge copy checkbox-free.
- **Bumping a vendored library means regenerating the manifest in the same diff.** Change the URL/version in `scripts/fetch-vendor.sh`, run `just clean` (or `rm -rf Resources/web/vendor`) so the bumped file is actually re-downloaded rather than skipped (`fetch-vendor.sh` skips any existing non-empty output file), then `scripts/fetch-vendor.sh --write-manifest`, and commit the updated `scripts/vendor.sha256` alongside — otherwise the next fetch fails integrity verification.
- **Mermaid uses the UMD bundle (`mermaid.min.js`), not the ESM split build.** The ESM entry imports a tree of separate chunk files that doesn't resolve cleanly under our custom URL scheme. **Held on 11.x** (see `fetch-vendor.sh`): 12 bundles EPL-2.0 ELK, doubles the bundle and needs Safari 17.4+. Dependabot only manages GitHub Actions; vendored JS bumps are manual.
- **Renaming the app means updating four things in lockstep**: bundle id (`com.markee.preview`), URL schemes (`markee-app`, `markee-doc`), JS global (`window.markee`), and the `webkit.messageHandlers` name (`markee`).
- **The custom titlebar relies on `WindowAccessor` flipping `titlebarAppearsTransparent` / `titleVisibility` / `.fullSizeContentView` on the host `NSWindow`.** SwiftUI's `.toolbar` modifier reintroduces a toolbar area — don't add it back. The traffic-light gutter in `MarkeeTitlebar` is reserved by `leftGutter: 78` and mirrored on the right; the centered filename's symmetric inset (`titleInset`) is derived from the gutter plus the toggle and chevron widths, so adding a titlebar control means adding its width there. The filename truncates (middle) rather than drawing under the controls.
- **`pickActiveHeading` (util.js) and the IntersectionObserver (app.js) are paired.** The observer uses `rootMargin: "0px 0px -80% 0px"` to fire when a heading enters the top 20% of the viewport; the helper picks the last heading whose top is ≤ 20% of viewport height. If you change one, change the other to match.
- **WKWebView does NOT render `::before` / `::after` pseudo-elements on `<input>`.** The custom task-list checkbox checkmark uses a `background-image: url("data:image/svg+xml;...")` instead. Do not try to switch back to `::after`.
- **`markee-chrome` is the single contract for screen-only injected
  affordances.** Copy buttons, language badges, and heading anchors all carry
  it; `exportStandalone` strips it and `@media print` hides it. Anything
  injected into `#content` that must not appear in Export/Print/PDF must carry
  this class. DOM chrome is also gated on `!payload.readOnly` so it never
  renders in the Quick Look preview/thumbnail extensions.
- **The heading copy-link glyph is a CSS `::after`**, and `decorateHeadings`
  runs after the outline loop — so the link glyph never contaminates heading
  `textContent` or the outline.
- **Find is JS-owned** (`window.markee.find` / `clearFind`) using the CSS
  Custom Highlight API when available (Range-keyed — no DOM mutation, no
  Export/Print leak), falling back to `window.find`. Swift only drives it and
  reads `{kind:"findResult", current, total}` back. Do not reintroduce a
  `<mark>`-mutation engine or call `webView.find` directly.
- **The two `Highlight` objects are registered once and mutated in place**
  (per-range `add`/`delete` in `applyFindHighlights`). Replacing them wholesale
  under the same registry key makes WebKit repaint only the *incoming* ranges'
  text nodes, so a node that matched the old query but not the new one keeps
  its stale paint — typing "f" then "freeze" left stray "f"s highlighted in
  every text node without a "freeze" in it (inline markup splits a paragraph
  into many such nodes). Don't go back to `CSS.highlights.set(name, new
  Highlight(...))` per keystroke.
- **Currency dollars are masked before KaTeX's auto-render and restored
  after** (`maskCurrencyDollarsIn` in `app.js`, rule in `util.js`). Auto-render
  treats every `$` as an inline-math delimiter, so a paragraph with two amounts
  ("~$127k … ~$350M") was typeset as one math run. A `$` followed by an ASCII
  digit is money, not a delimiter; `$` next to another `$` is left alone so
  `$$…$$` still pairs. The restore runs in a `finally` — don't drop it, or a
  KaTeX throw leaves U+E000 sentinels in the DOM.
- **Task items are wrapped in an implicit `<label>`**
  (markdown-it-task-lists `label: true`), so *any* click inside the item
  activates the checkbox. A capture-phase click guard cancels that activation
  when the click ends a text selection (`shouldSuppressTaskToggle` in
  `util.js`). Without it, drag-selecting checklist text toggles the box, writes
  the file, re-renders, and collapses the selection — which also wipes find
  highlights via `clearFind()`.
- **Menu commands reach every window; only the key window acts.**
  `PreviewController.registerCommands` is the one table: key-window commands
  share a single `isKeyWindow` guard, while `.zoomDidChange` and
  `.settingsDidChange` are deliberate broadcasts every window applies. The
  observers are block-based, so their tokens are removed in `deinit` and
  they capture `self` weakly (the deallocation test catches a strong capture).
  Call into the page through `callJS` (JSON-encoded arguments), never by
  interpolating strings into `evaluateJavaScript`.
- **The word-count pill is SwiftUI, not DOM** — keep doc stats out of `#content`
  so they never reach Export/Print/Quick Look.
- **`render-core.js` owns markdown-it construction** and is loaded before
  `app.js`; it is also `require`d by `Tests/render.test.js`. Changing the
  pipeline means regenerating the snapshot:
  `UPDATE_SNAPSHOTS=1 node --test Tests/render.test.js`.
- **The `markee-doc://` sandbox is rooted at the workspace root, not the
  document's folder.** Each document keeps its own `<base href>`
  (`WorkspaceModel.docBase`) so relative images/links resolve correctly while
  `resolveSandboxed` still blocks escape above the root. Widening the root
  enlarges the in-app serving boundary — the nav policy makes no outbound
  request, and only `.md`/`.markdown` links retarget the window.
- **Navigation re-renders in place; it never reloads `template.html`.** Swift
  owns `NavigationHistory` (the authoritative back/forward stack behind the
  titlebar chevrons + `⌘[`/`⌘]`). `navigate(to:)` retargets `fileURL`, restarts
  the FileWatcher (fresh watcher, not a reattach), and re-renders.
- **Wiki-links resolve against `state.env.wikiIndex` ({stem → markee-doc url}),
  passed in the render payload.** With no index (Quick Look / `readOnly`) every
  `[[link]]` degrades to a non-navigating broken span. The rule lives in
  `render-core.js`. Its resolving (anchor) path is covered by the
  assertion-based `Tests/wikilink.test.js`; `render.test.js` passes no
  `wikiIndex`, so a resolving-path change leaves the snapshot green. The
  broken-span fallback IS in the render snapshot, so if that markup changes,
  regenerate it too (`UPDATE_SNAPSHOTS=1 node --test Tests/render.test.js`).
- **License keys are redeemed through Polar's `/activate` endpoint, not
  `/validate`.** The benefit caps activations at 3 devices, and Polar requires
  an `activation_id` on validate whenever a limit is set — so the activate
  response (which already carries `license_key.status`) is the single source of
  truth at key entry. `SupportController.redeem(key:)` is the UI entry point;
  `LicenseActivation` owns the wire format. There is no launch-time
  re-validation, deliberately: it would enforce nothing and break offline use.
- **Run Debug ▸ Deactivate This Mac BEFORE `just reset`.** `_wipe` deletes the
  whole defaults domain including `support.activationId`, which strands that
  activation on Polar's side and burns one of three slots until it's cleared in
  the customer portal.
- **Updates must pass `Updater.updateRequirement`** (Developer ID Application,
  team `N8427TN2XH`, bundle id `com.markee.preview`, strict nested-code check)
  before the swap helper runs. Changing the signing team or bundle id means
  updating that string in the same release — otherwise every installed copy
  refuses the update and falls back to the manual download page. Ad-hoc dev
  builds can't self-update by design.
- **No `polar_oat_` token may enter the app bundle.** The customer-portal
  endpoints are unauthenticated by design; only the organization UUID ships.

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
- `just app` signs; `just notarize` builds + signs + notarizes + staples.

**Local setup (one-time):**
- Install the "Developer ID Application" certificate in your login keychain
  (Xcode → Settings → Accounts → Manage Certificates, or the developer portal).
- Store the App Store Connect API key as a notarytool keychain profile:
  `xcrun notarytool store-credentials markee-notary --key <AuthKey.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>`
- Then `NOTARY_KEYCHAIN_PROFILE=markee-notary just notarize` produces a
  notarized, stapled bundle.

**CI:** `release.yml` (tag-triggered) imports the cert and notarizes
automatically. It needs five repo secrets: `MACOS_CERT_P12` (base64 of the
Developer ID `.p12`), `MACOS_CERT_PASSWORD`, `NOTARY_KEY_P8` (base64 of the API
key `.p8`), `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`. The job runs in the `release`
environment and refuses tags whose commit isn't on `main`; give that
environment required reviewers (and move the five secrets into it) so a pushed
tag alone can't sign and publish. `ci.yml` (push/PR) stays ad-hoc — signing
secrets must never reach PR builds. Actions are pinned by commit SHA (version
in a trailing comment); `.github/dependabot.yml` keeps them current.

## Not yet built

- DMG installer / Homebrew cask
- True MultiMarkdown citation / cross-reference support (GFM-ish via plugins today)

## Useful one-liners

```sh
# Quit any running instance before rebuilding
osascript -e 'tell application "Markee" to quit'

# Check the running process
pgrep -fl Markee.app/Contents/MacOS/Markee
```

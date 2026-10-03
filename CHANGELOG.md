# Changelog

All notable changes to Markee are documented here. Format roughly follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Optional Polar.sh supporter license** with a local-only usage-stats drawer.
  Nothing is feature-gated; supporting only silences the throttled nudges. A key
  is redeemed once through Polar's activation endpoint and covers up to 3 Macs;
  free a slot any time from the Polar customer portal. Built and tested, but
  dormant in 1.1.0 — no organization is configured, so the heart, the menu
  entries, and the monthly support doc stay hidden until go-live.
- **Developer Debug menu** (`MARKEE_DEV_TOOLS=1`) for exercising licensing
  state locally without contacting Polar.

### Security
- The preview page now has a strict Content-Security-Policy: document script
  (inline `<script>`, `on*=` handlers, `javascript:` URLs, workspace `.js`)
  never runs, and `{…}` attribute syntax is limited to an allowlist.
  Visible effects: `<iframe>` embeds (e.g. videos) no longer load, and remote
  images load only over `https:` (`http:` images are blocked).
- The native bridge only accepts messages from the preview's own main frame,
  and the main frame can no longer be navigated away from the preview.
- Quick Look previews and thumbnails block all remote loads.
- Updates must carry Markee's Developer ID signature before they're installed.
- Workspace root inference never widens to your home folder or above.
- Vendored JS is re-verified against its SHA-256 manifest on every build;
  CI actions are pinned by commit and releases require a commit on `main`.

### Fixed
- Clicking a task checkbox could rewrite the wrong line (blockquoted tasks,
  code in list items, HTML blocks, CRLF or `...` front matter, `1)` lists).
  Write-back now follows symlinks, keeps the file's encoding and BOM, and
  re-syncs the checkbox when it can't apply.
- Closed windows were never freed (WebView, file watcher and observers leaked).
- Legacy-encoded (Windows-1252/Latin-1) files no longer render as CJK mojibake.
- Exported HTML no longer gets dark code blocks, and keeps its math fonts.
- Open in Editor no longer freezes the UI on slow shell startup files.
- Footnote and in-page `#links` scroll instead of breaking the preview;
  links to images/PDFs in the workspace open in their default app.
- Many smaller fixes: search result races, slug collisions and non-ASCII
  heading anchors, Mermaid following the theme override, Find ignoring
  KaTeX's hidden MathML, outline lines with raw-HTML headings, `#`/`%` in
  workspace paths, deleted-file detection, WebContent crash recovery, the
  CLI opening multiple files, and the titlebar filename overlapping the
  back/forward buttons.

### Changed
- Terminal editors (`nvim`, `vim`, `hx`) are no longer auto-detected for
  Open in Editor — they can't run without a terminal.
- Markee registers as a Markdown *viewer*, and as only an alternate app for
  plain text; it no longer claims `.mmd` (Mermaid) files.
- `just app` no longer replaces `/Applications/Markee.app`; use `just install`.
- Updated bundled libraries: markdown-it 15.0.2 (includes fixes for
  quadratic-time parsing), markdown-it-deflist 4.0.0, markdown-it-attrs
  5.0.1, highlight.js 11.12.0, KaTeX 0.19.0 and Mermaid 11.17.2 (with
  DOMPurify 3.4.12). Mermaid stays on 11.x for now.
- Autolinks follow GitHub: `www.` addresses and `https://…` URLs link, but bare
  file names like `notes.md` or `setup.py` no longer turn into web links.

## [1.1.0] — 2026-07-24

### Added
- **Docs navigation** — click `.md` links to navigate in-window with
  back/forward history (⌘[ / ⌘]), a sidebar file tree, `[[wiki-links]]`
  resolved across the workspace, and a workspace-wide full-text search palette
  (⇧⌘O). *File ▸ Open Folder as Workspace…* sets the root explicitly.
- **Preferences window (⌘,)** — override the theme (System/Light/Dark), accent
  color, and base font size, and load a custom CSS file (Settings scene).
- **Window pinning** — Window-menu commands: Float on Top (⌥⌘P), Visible on All
  Spaces, Move to Active Space, and a Ghost Mode that dims the window until you
  hover or hold a modifier.
- **Rendering polish** — copy-code buttons and language badges on code blocks,
  heading anchor links, and a live word-count pill.
- **Copy Reflowed Markdown (⌥⌘C)** and **Copy as Rendered Text (⇧⌥⌘C)** —
  copy the source with soft-wrapped paragraphs unwrapped, or the rendered
  content as flowing plain text (also in the preview's right-click menu).
- **Export PDF… (⇧⌘E)** — write the rendered document straight to a PDF,
  alongside the existing Export Standalone HTML.
- **Commercial / Team license materials** (`COMMERCIAL.md`,
  `docs/commercial-agreement-template.md`).

### Changed
- **Print / Save as PDF** now uses a print-tuned `@media print` stylesheet
  (forced light palette, page-break avoidance for code/tables/diagrams, printed
  link URLs) for cleaner pagination.
- **Find in preview** is reimplemented as a JS-owned engine using the CSS Custom
  Highlight API — no DOM mutation, so highlights never leak into Export/Print.
- `fetch-vendor.sh` now verifies every downloaded library against a pinned
  SHA-256 manifest (`scripts/vendor.sha256`) and fails on mismatch.

### Removed
- The "Stay Visible in Full Screen" pinning option — unachievable for Markee's
  activating DocumentGroup windows.

### Fixed
- Mermaid and KaTeX render failures now surface in the in-app error banner
  instead of failing silently.

## [1.0.0] — 2026-05-19

The first publicly distributable release — Developer ID signed and notarized,
so Markee installs and opens without Gatekeeper warnings.

### Added
- **Quick Look preview** — press Space on a Markdown file in Finder to see it
  fully rendered instead of as raw source. A sandboxed Quick Look extension
  that reuses the app's renderer.
- **Per-file Finder thumbnails** — `.md` files show a thumbnail of their
  rendered content in Finder's icon views, falling back to the document icon.
- **Markdown document icon** — `.md` files now carry a branded Markee document
  icon in place of the generic plain-text page.
- **Developer ID signing & notarization** — the app and both Quick Look
  extensions are signed with a Developer ID certificate and notarized by Apple,
  so they install and open without Gatekeeper warnings. `make notarize` and the
  release workflow handle it end to end.

### Changed
- Mermaid now loads lazily — only documents that contain a diagram pay its
  ~2.5 MB parse cost, so cold-start render is faster for everything else.
- Bundle version bumped to `1.0.0` (CFBundleShortVersionString) / `6`
  (CFBundleVersion).

## [0.5.0] — 2026-05-18

### Added
- **Copy Markdown Source (⌘⇧C)** — copy the file's raw Markdown to the
  clipboard, read fresh from disk. In the File menu and the preview
  right-click menu.
- **Reveal in Finder (⌘⇧R)** — reveal the current file in Finder. In the
  File menu and the preview right-click menu.
- **In-app updates** — Markee checks GitHub Releases for a newer version on
  launch (at most once a day) and on demand via *Markee ▸ Check for
  Updates…*. When a newer release exists it downloads, validates, and
  installs it, then relaunches — clearing quarantine so there is no repeat
  Gatekeeper prompt. Falls back to opening the release page in the browser
  when it cannot replace itself in place.

### Changed
- Bundle version bumped to `0.5.0` (CFBundleShortVersionString) / `5`
  (CFBundleVersion).

### Fixed
- The custom title bar no longer disappears after the window loses and
  regains focus. AppKit resets `titlebarAppearsTransparent` during window
  reactivation; the window configuration is now re-applied via KVO
  whenever that happens.

## [0.4.0] — 2026-05-18

### Added
- **Zoom (⌘+ / ⌘= / ⌘- / ⌘0)** — resize the rendered preview. Zoom is
  reflow-based: text re-wraps and code blocks, images, KaTeX, and Mermaid
  output scale together. The level is one global preference, shared across
  all open windows and remembered across launches. ⌘+ and ⌘= both zoom in
  (the latter needs no Shift). Driven through a `window.markee.setZoom()`
  bridge call applying CSS `zoom`; native `WKWebView.pageZoom` is macOS 14+
  and the deployment target is macOS 13.
- **Find Next / Previous (⌘G / ⌘⇧G)** — step through find-bar matches with
  the standard macOS shortcuts, with matching Edit-menu items. ⌘G with no
  active query opens the find bar.
- **Reload (⌘R)** — manually re-read and re-render the file from disk; a
  fallback for the rare save the file watcher does not catch.

### Changed
- Bundle version bumped to `0.4.0` (CFBundleShortVersionString) / `4`
  (CFBundleVersion).

## [0.3.0] — 2026-05-15

### Added
- **Find in preview (⌘F)** — an in-app find bar. macOS `WKWebView` has no
  built-in find UI, so Markee ships its own: find-as-you-type, ↩ / chevrons
  to step through matches, wrap-around, a "Not found" indicator, and ⎋ to
  dismiss. Driven by `WKWebView.find(_:configuration:)`.
- **Print / Save as PDF (⌘P)** — opens the system print panel via
  `WKWebView.printOperation(with:)`; the panel's PDF menu covers
  print-to-PDF.

### Fixed
- **Export Standalone HTML (⌘E)** failed with *"JavaScript execution
  returned a result of an unsupported type."* `exportStandalone()` is async
  (it inlines images as data URIs), so it returns a Promise;
  `evaluateJavaScript` cannot await one. The bridge now uses
  `callAsyncJavaScript`, which resolves the Promise before returning to Swift.

### Changed
- CI builds on `macos-14` + `macos-15`; the retired `macos-13` hosted
  runner was queueing jobs indefinitely.
- Bundle version bumped to `0.3.0` (CFBundleShortVersionString) / `3`
  (CFBundleVersion).

## [0.2.0] — 2026-05-14

### Added
- **Open in Editor at Current Heading** — ⌥⌘E or right-click an outline row to
  jump to that heading's source line in your editor of choice. Auto-detects
  Cursor, VS Code, Zed, Sublime, TextMate, MacVim, and Helix; override with
  `defaults write com.markee.preview editor "<name>"`.
- Soft Modern UI/UX redesign:
  - Integrated window chrome (no system titlebar divider, custom 44pt gradient bar).
  - Spring-animated outline drawer (⌘⌥\ to toggle).
  - Live active-heading highlight in the outline, driven by an
    IntersectionObserver in the WebView.
  - New `theme.css` with `--surface` / `--accent` token palette,
    soft-modern typography, custom task-list checkboxes, faded `<hr>`, and a
    lede-paragraph treatment after H1.
  - Dark + light themes follow `prefers-color-scheme`.
- Article max-width widened from 740px → 1000px.
- `MIT` license, `THIRD-PARTY-NOTICES.md`, `SECURITY.md`, `CONTRIBUTING.md`,
  `CHANGELOG.md`, and a `docs/demo.md` showcase document.
- GitHub Actions CI workflow that builds and tests on every push and PR.

### Security
- **`BundleSchemeHandler` path-traversal hardening** — requests like
  `markee-app://app/../../Info.plist` no longer escape the bundle's
  `Resources/web/` directory.
- **`DocSchemeHandler` symlink-escape fix** — symlinks inside the document
  directory pointing at files outside (e.g. `~/.ssh/id_rsa`) are now rejected.
  Resolution moved from `standardizedFileURL` to `resolvingSymlinksInPath()`
  with a trailing-slash boundary so sibling directories with the root as a
  prefix (`/notes_secret` vs root `/notes`) cannot match.
- **External-link allowlist** — only `http`, `https`, and `mailto` schemes are
  handed to `NSWorkspace.shared.open`; `javascript:`, `file://`, custom
  app-handler schemes are blocked.
- **EditorLauncher input validation** — user-supplied editor names from
  `UserDefaults` are validated against `^[A-Za-z0-9._+-]+$` before being
  interpolated into the `zsh -ilc 'command -v <name>'` fallback, closing a
  self-targeted shell-injection vector.
- All `HTTPURLResponse(...)!` and `task.request.url!` force-unwraps in the
  scheme handlers replaced with `guard let` early-outs.

### Changed
- `Makefile` `app` target now depends on a `Resources/web/vendor/.fetched`
  sentinel — a fresh clone running `make app` automatically fetches vendored
  libraries instead of silently building a broken bundle.
- `LICENSE` and `THIRD-PARTY-NOTICES.md` are now copied into
  `Markee.app/Contents/Resources/` at build time so the obligations travel
  with the binary.
- Bundle version bumped to `0.2.0` (CFBundleShortVersionString) / `2`
  (CFBundleVersion).

### Fixed
- `fixtures/sample.md` references to the old "Macdown" name updated to
  "Markee" + smoke-test stragglers removed.

## [0.1.0] — initial release

### Added
- Watch + re-render a Markdown file on every save (kqueue-backed
  `FileWatcher` with atomic-save reattach).
- Markdown features: GitHub-flavored, footnotes, definition lists, attribute
  lists, task lists, YAML front matter.
- KaTeX math (inline and display), highlight.js syntax highlighting,
  Mermaid diagrams.
- Outline sidebar (⌘⌥\ to toggle).
- Interactive task-list checkboxes that write back to the source file.
- Export Standalone HTML with inlined CSS + images (⌘E).
- `markee` CLI launcher with menu installer.
- Custom app icon, 1000×800 default window, custom titlebar.
- 22 tests passing (18 JS + 4 Swift).

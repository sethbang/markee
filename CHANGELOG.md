# Changelog

All notable changes to Markee are documented here. Format roughly follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

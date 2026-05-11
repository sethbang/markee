# Markee — orientation for Claude Code

A native macOS app that watches a Markdown file on disk and re-renders a preview every time it's saved. Editor-agnostic. Built with SwiftUI + WKWebView; the actual rendering happens in JavaScript inside the WebView (markdown-it + plugins, KaTeX, highlight.js, Mermaid).

## Run

```sh
make fetch-vendor   # one-time: downloads JS/CSS into Resources/web/vendor/ (gitignored)
make app            # builds Markee.app at the repo root
make run            # builds + opens
make test           # swift test + node --test Tests/util.test.js (both green at last commit)
```

`swift build` alone produces just the executable in `.build/`; you need `make app` to get a usable `.app` bundle with Info.plist, AppIcon.icns, and Resources/.

## Layout

- `Sources/Markee/` — Swift app
  - `MarkeeApp.swift` — `@main`, `DocumentGroup`, menu commands, CLI installer
  - `MarkdownDocument.swift` — read-only `FileDocument` (no content stored; PreviewView reloads from disk)
  - `PreviewController.swift` — per-window controller owning the WKWebView + FileWatcher; routes JS messages, handles export-HTML and task-toggle write-back
  - `PreviewView.swift` — SwiftUI view: HSplitView (outline + WebView)
  - `FileWatcher.swift` — kqueue-backed (DispatchSource) with atomic-save reattach logic
  - `SchemeHandlers.swift` — `markee-app://` (bundle resources) and `markee-doc://` (current doc's directory, sandboxed)
- `Resources/web/` — HTML/JS/CSS shipped into the bundle
  - `template.html` — loads vendor scripts, then `util.js`, then `app.js`
  - `app.js` — IIFE wrapping `render`, `scrollToHeading`, `exportStandalone`, task-toggle click handler. Exposes `window.markee`.
  - `util.js` — pure helpers (`collectTaskLineNumbers`, `slugify`), UMD so Node can require them for tests
  - `theme.css` — built-in light/dark theme
  - `vendor/` — fetched libs; **gitignored**
- `Resources/cli/markee` — shell launcher (`open -b com.markee.preview`)
- `Resources/AppIcon.svg` — source; `Resources/AppIcon.icns` is built (gitignored)
- `scripts/build-icon.sh` — `sips` + `iconutil` → AppIcon.icns
- `scripts/fetch-vendor.sh` — pinned downloads from jsdelivr
- `Tests/MarkeeTests/` — Swift unit tests (`@testable import Markee`)
- `Tests/util.test.js` — Node `--test` runner over `util.js`
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

## Conventions in this repo

- Auto-mode-friendly: the user prefers action over questions for routine work.
- **No README/docs unless asked.** This file and `README.md` were both explicitly requested.
- **No git operations unless asked.** The user drives commits and PRs.
- Default to **no comments**; only annotate WHY when non-obvious (invariants, workarounds, bug references).
- Don't commit `Resources/AppIcon.icns` (built) or `Resources/web/vendor/` (fetched). Both are gitignored.
- `.claude/` is gitignored.

## What's done (v0.1)

Watch + rerender, atomic-save aware, scroll preservation, GFM + footnotes + deflists + attrs + task-lists + YAML front matter, KaTeX, highlight.js, Mermaid, outline sidebar (collapsed default, ⌘⌥\\), interactive task-list checkboxes write back to file, export standalone HTML (⌘E), find / print-as-PDF (free from WKWebView), CLI launcher with menu installer, custom app icon, default window 1000×800. 18 JS tests + 4 Swift tests passing.

## Not done

- Apple Developer ID signing / notarization (needed for distribution beyond your machine)
- DMG / Homebrew cask
- PreviewController test coverage: `toggleTask` drift bailout, line-ending preservation, export-HTML write
- Print stylesheet (uses screen CSS; usually fine, breaks near page boundaries can be ugly)
- App icon cache invalidation guidance (if the Dock shows a stale icon: `killall Dock`)
- Theme picker / custom CSS — deferred from v1
- True MultiMarkdown citation/cross-ref support — deferred; we ship GFM-ish via plugins

## Useful one-liners

```sh
# Find anywhere the old name 'macdown' or 'Macdown' still lurks
grep -rln "macdown\|Macdown" --exclude-dir=.build --exclude-dir=.git --exclude-dir=vendor

# Quit any running instance before rebuilding
osascript -e 'tell application "Markee" to quit'

# Check the running process
pgrep -fl Markee.app/Contents/MacOS/Markee
```

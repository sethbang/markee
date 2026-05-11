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
- **The custom titlebar relies on `WindowAccessor` flipping `titlebarAppearsTransparent` / `titleVisibility` / `.fullSizeContentView` on the host `NSWindow`.** SwiftUI's `.toolbar` modifier reintroduces a toolbar area — don't add it back. The traffic-light gutter in `MarkeeTitlebar` is reserved by `leftGutter: 78` and mirrored on the right so the centered filename stays centered. Resizing the window narrowly enough may push the filename behind the toggle; this is acceptable.
- **`pickActiveHeading` (util.js) and the IntersectionObserver (app.js) are paired.** The observer uses `rootMargin: "0px 0px -80% 0px"` to fire when a heading enters the top 20% of the viewport; the helper picks the last heading whose top is ≤ 20% of viewport height. If you change one, change the other to match.
- **WKWebView does NOT render `::before` / `::after` pseudo-elements on `<input>`.** The custom task-list checkbox checkmark uses a `background-image: url("data:image/svg+xml;...")` instead. Do not try to switch back to `::after`.

## Conventions in this repo

- Auto-mode-friendly: the user prefers action over questions for routine work.
- **No README/docs unless asked.** This file and `README.md` were both explicitly requested.
- **No git operations unless asked.** The user drives commits and PRs.
- Default to **no comments**; only annotate WHY when non-obvious (invariants, workarounds, bug references).
- Don't commit `Resources/AppIcon.icns` (built) or `Resources/web/vendor/` (fetched). Both are gitignored.
- `.claude/` is gitignored.

## What's done (v0.1)

Watch + rerender, atomic-save aware, scroll preservation, GFM + footnotes + deflists + attrs + task-lists + YAML front matter, KaTeX, highlight.js, Mermaid, outline sidebar (collapsed default, ⌘⌥\\), interactive task-list checkboxes write back to file, export standalone HTML (⌘E), find / print-as-PDF (free from WKWebView), CLI launcher with menu installer, custom app icon, default window 1000×800. 18 JS tests + 4 Swift tests passing.

## What's done (v0.2 — Soft Modern UI/UX pass)

Visual identity redesign. Integrated window chrome (no system titlebar divider, custom 44pt gradient bar, traffic lights kept). Outline sidebar redesigned with H1/H2/H3 indent + live active-section highlight (driven by `currentHeadingID` published from JS IntersectionObserver). Full `theme.css` rewrite with new token palette (`--surface`, `--accent`, etc.), Soft Modern typography, custom task-list checkboxes, faded `<hr>`, lede paragraph after H1. Dark + light themes, system-following via `prefers-color-scheme`. See `docs/superpowers/specs/2026-05-11-ui-ux-redesign-design.md`.

## Not done

- Apple Developer ID signing / notarization (needed for distribution beyond your machine) — see "Known issues blocking public release" below
- DMG / Homebrew cask
- PreviewController test coverage: `toggleTask` drift bailout, line-ending preservation, export-HTML write
- Print stylesheet (uses screen CSS; usually fine, breaks near page boundaries can be ugly)
- App icon cache invalidation guidance (if the Dock shows a stale icon: `killall Dock`)
- In-app theme picker / custom CSS — still deferred (system appearance toggle is sufficient for v0.2)
- True MultiMarkdown citation/cross-ref support — deferred; we ship GFM-ish via plugins

## Known issues blocking public release

### 1. Open With picker grays out Markee; not in "Recommended Applications"

**Symptom.** Right-click .md → Open With → Other… shows Markee grayed out under "Recommended Applications" *and* under "All Applications". The bundle is registered, the binding is correct, and `open -Ra Markee` works — but the picker UI refuses to let users select it.

**Why.** macOS (Sonoma+) gates the Open With picker on a Gatekeeper assessment (`spctl -a`). Ad-hoc signed apps fail this assessment. Self-signed certs — even trusted system-wide via `security add-trusted-cert -p codeSign` — *also* fail, because `spctl -a` specifically requires Apple's CA chain (Developer ID Application or notarized). There is no purely-local workaround. Note also: every file in the bundle carries `com.apple.provenance` xattr that `xattr -cr` cannot remove on Sonoma+; this is kernel-managed and Apple intends for it to stay.

**Why .md files still open with Markee anyway.** The actual LaunchServices binding (the user's "always open with" choice stored in `~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist`) does *not* gate on Gatekeeper. So once a binding is set — by any means — files open with Markee on double-click. The picker UI just refuses to be the path that sets the binding.

**Workaround we used during development.** Get Info → Open with → "Other…" → switch dropdown to "All Applications" → navigate to /Applications/Markee.app → it's grayed but still clickable in the file dialog → click Open → Change All. Once. Then it sticks.

**Real fix for public release.** Either:
- Enroll in the Apple Developer Program ($99/yr), get a Developer ID Application cert, codesign with that, notarize. After notarization, `spctl -a` passes and the picker enables Markee normally.
- Or: ship a tiny first-run helper that writes the LSHandler entries directly to the user's `launchservices.secure.plist` and runs `lsregister`. Avoids the picker entirely but doesn't help discoverability for users who didn't go through the helper.

**Do NOT.** Don't switch to a self-signed cert — counterintuitively this makes the picker *worse* than ad-hoc, because Apple's heuristic treats "signed by random untrusted CA" as more suspicious than "no claim of identity." (We tried this in the May 2026 debugging session and confirmed it; reverted.)

### 2. File → Open dialog quits the app

**Symptom.** Launch Markee, File → Open, select a .md file, click Open. The app quits silently. No crash log written. Drag-onto-Dock-icon works fine for the same file.

**Status.** Not yet root-caused — needs a live `log stream --predicate 'process == "Markee"' --info --debug` run while reproducing. Suspect either:
- `applicationShouldTerminateAfterLastWindowClosed = true` firing during the dialog→new-window transition when SwiftUI's `DocumentGroup` briefly has zero windows.
- Something in `PreviewController.init` taking a path that crashes when invoked via the SwiftUI Open dialog vs. the dock-drop path. Both should funnel through `MarkdownDocument(configuration:)` → `PreviewView(fileURL:)` → `PreviewContent` → `PreviewController(fileURL:)`, so this would be surprising — but it's the only behavioral difference.

Reproduce + capture logs before public release.

### 3. Bundle installation path

`make app` now syncs the built bundle to `/Applications/Markee.app` automatically *if that path already exists* (as a real directory; symlinks were tried and rejected by Finder's picker — symlinked .app bundles in /Applications are *also* grayed out in the picker, regardless of signature). First-time setup: `make install`.

Do **not** symlink /Applications/Markee.app → repo path. Finder's "Other…" picker won't let users select symlinked apps even in "All Applications" mode (we confirmed this in the May 2026 session).

## Useful one-liners

```sh
# Find anywhere the old name 'macdown' or 'Macdown' still lurks
grep -rln "macdown\|Macdown" --exclude-dir=.build --exclude-dir=.git --exclude-dir=vendor

# Quit any running instance before rebuilding
osascript -e 'tell application "Markee" to quit'

# Check the running process
pgrep -fl Markee.app/Contents/MacOS/Markee
```

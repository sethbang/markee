# Markee

A macOS Markdown preview app that watches a file on disk and re-renders every time you save. Editor-agnostic — keep using whatever editor you already love, and let Markee handle the preview.

## Features

- Live re-render on save, with scroll position preserved
- Works with editors that do atomic saves (Vim, VSCode, Sublime, JetBrains, …)
- GitHub-flavored Markdown plus footnotes, definition lists, attribute lists, task lists, YAML front matter
- KaTeX math (inline `$…$` and display `$$…$$`)
- Syntax highlighting via highlight.js
- Mermaid diagrams
- **Interactive task-list checkboxes that write back to the source file**
- Outline sidebar (⌘⌥\\ to toggle)
- Export Standalone HTML with inlined CSS + images (⌘E)
- ⌘F find in preview, ⌘P print or save as PDF
- One window per file, "Open Recent", drag onto Dock, etc.
- CLI launcher: `markee path/to/notes.md`

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon
- Swift 5.9+ (ships with Xcode 15 / the Command Line Tools)
- Node ≥ 18 (only needed to run the JS test suite)

## Build

```sh
make fetch-vendor   # one-time: pinned downloads of markdown-it, KaTeX, highlight.js, Mermaid
make app            # builds Markee.app at the repo root
make run            # build + open
```

The `.app` is ad-hoc codesigned, which is fine for personal use. Drop it into `/Applications` if you want it permanently installed.

## Use

Any of these will open a file:

- Drag a `.md` onto the Markee dock icon
- File ▸ Open… (⌘O)
- `open Markee.app yourfile.md`
- After installing the CLI (File ▸ Install Command Line Tool…): `markee yourfile.md`

Then edit the file in your editor. Save. The preview updates.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘O | Open file |
| ⌘W | Close window |
| ⌘⌥\\ | Toggle outline sidebar |
| ⌘E | Export standalone HTML |
| ⌘F | Find in preview |
| ⌘P | Print / save as PDF |

## Develop

```sh
make test         # swift test + node --test
make test-swift   # FileWatcher tests
make test-js      # util.js tests (collectTaskLineNumbers, slugify)
make clean        # nuke .build and Markee.app
```

### Project layout

```
Sources/Markee/        Swift app (SwiftUI DocumentGroup + WKWebView)
Resources/web/         HTML/JS/CSS shipped into the bundle
  template.html        Loads vendor + util + app
  app.js               Renderer glue, scroll preservation, message bridge
  util.js              Pure helpers (importable by Node tests)
  theme.css            Light/dark theme
  vendor/              Fetched at build time, not committed
Resources/cli/markee   Shell launcher
Resources/AppIcon.svg  Source for the app icon
scripts/               build-icon.sh, fetch-vendor.sh
Tests/                 Swift + JS tests
fixtures/sample.md     Exercises every feature
```

### How it works (briefly)

The Swift side is a thin host: a `DocumentGroup`, a per-window `PreviewController`, a `FileWatcher` (kqueue with atomic-save reattach), and two custom URL scheme handlers — `markee-app://` for bundle assets and `markee-doc://` for the current document's directory (sandboxed to prevent path traversal). All Markdown rendering happens in JavaScript inside the WebView; Swift just streams the file's source into `window.markee.render({…})` after every change.

## Status

- v0.1, working.
- 18 JS tests + 4 Swift tests, all green.
- Not yet signed with a Developer ID, not yet notarized — fine on your own machine, but you can't hand the `.app` to a friend until it is.

## License

TBD.

## Credits

Built on the shoulders of [markdown-it](https://github.com/markdown-it/markdown-it), [KaTeX](https://katex.org), [highlight.js](https://highlightjs.org), and [Mermaid](https://mermaid.js.org). The macOS-app shell is plain SwiftUI + WKWebView.

# Security

## Threat model

Markee is a local Markdown viewer. It renders the source file you point it at,
including any raw HTML embedded in the Markdown — `markdown-it` is configured
with `html: true` so documents can use `<details>`, `<kbd>`, `<img width>` and
the like. Raw HTML is untrusted, so the preview page is locked down instead of
the HTML being stripped.

## What a malicious `.md` can and can't do

The preview runs in a WKWebView whose page (`template.html`) carries a strict
Content-Security-Policy:

- **No document script runs.** Scripts load only from the app bundle
  (`markee-app://`); inline `<script>`, `on*=` event handlers, `javascript:`
  URLs and `.js` files inside the workspace are all refused. The
  `markdown-it-attrs` `{…}` syntax is limited to an allowlist (`id`, `class`,
  `data-*`, `width`, `height`, `lang`, `title`, `dir`), so it can't add
  event handlers either.
- **No frames, plugins or forms** (`frame-src`/`object-src`/`form-action`
  `'none'`), and `fetch`/XHR may only reach the bundle and the workspace.
- **Remote content is limited to `https:` images and media** in the app — so a
  document *can* act as a tracking pixel and reveal your IP when opened. Quick
  Look (Finder previews and thumbnails) additionally blocks every remote load
  with a content-blocking rule list, since it renders files with no user action.

The native bridge (`webkit.messageHandlers.markee`) only accepts messages from
the template's own main frame. Its messages are `ready`, `outline`,
`scrollSection`, `docStats`, `findResult` and `error` (UI state), `copyText`
(writes the clipboard; used by code-block copy buttons and heading links),
`taskToggle` (rewrites one `[ ]`/`[x]` checkbox in the open file) and
`navigate` (opens another Markdown file inside the workspace). Because document
script can't run, a document can only trigger these through Markee's own UI —
i.e. by you clicking a checkbox, copy button or link.

The main frame never leaves `template.html`: every document change is an
in-place re-render, and the navigation policy cancels any other main-frame
load. Clicked links are handed off — `http`/`https`/`mailto` to your browser,
non-Markdown workspace files (images, PDFs, plain text) to their default app,
anything else (scripts, `.command`, app bundles) revealed in Finder rather than
opened. Other schemes are blocked.

The serving boundary is the **workspace root**, inferred from the file you
open: the enclosing git repository if there is one, otherwise the nearest parent
folder holding more than one Markdown file, otherwise the file's own folder.
Inference never climbs to your home folder, anything above it, or `/` — a
dotfiles repo at `~` doesn't make your whole home folder the workspace — and a
root that *is* one of those (a file saved directly in `~`) is indexed one level
deep only.
*File ▸ Open Folder as Workspace…* sets it explicitly. Images and links can
reference any file under that root via `markee-doc://doc/...`; nothing outside
it is served (path traversal, percent-encoded `..` and symlink escapes are
blocked).

The remaining write path is the task checkbox: clicking one rewrites that
single line of the open file, after re-reading it and confirming the line is
still a task item.

## Reporting a vulnerability

Open a private security advisory on GitHub
([Security tab → Report a vulnerability](https://github.com/sethbang/markee/security/advisories/new)),
or email howdy@sbang.dev — please don't open a public issue for
security-sensitive reports.

I'll aim to respond within a week.

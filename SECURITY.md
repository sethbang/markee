# Security

## Threat model

Markee is a local Markdown viewer. It renders the source file you point it at,
including any raw HTML embedded in the Markdown — `markdown-it` is configured
with `html: true` so the source can contain `<script>`, `<iframe>`, etc.

**Don't open `.md` files from sources you don't trust.** Treat opening a
Markdown file with Markee the same way you'd treat opening an HTML file in a
browser: the contents can execute code in Markee's WebView context.

## What a malicious `.md` can and can't do

A script inside a rendered `.md` runs inside Markee's WKWebView. Markee loads no
remote resources of its own, but the WebView is **not** network-sandboxed and the
app itself is not sandboxed — so treat a rendered Markdown file as capable of
running code, reading nearby files, and reaching the network. It talks to the
host app through the `window.markee` bridge.

The boundary that matters is the **workspace root**, inferred from the file you
open: the enclosing git repository if there is one, otherwise the nearest parent
folder holding more than one Markdown file, otherwise the file's own folder.
*File ▸ Open Folder as Workspace…* sets it explicitly. Opening a file deep inside
a git repository therefore exposes the **whole repository** to the renderer.

It **can**:
- Call `webkit.messageHandlers.markee.postMessage({...})` to send `taskToggle`
  (writes a checkbox back to disk on the line you specify), `error` (shows a
  banner), or `outline` (replaces the sidebar contents).
- Read any file **inside the workspace root** — which may be an entire git
  repository, including sibling documents open under the same root — via
  `markee-doc://doc/...`.
- Make outbound network requests (e.g. `fetch`, a beacon, an `<img>`). Markee
  applies no Content-Security-Policy or content-blocking rules, so a malicious
  script could exfiltrate file contents it has read. (Top-level link clicks are
  separate: only `http`/`https`/`mailto` links are handed off to your browser;
  other schemes are blocked.)

It **cannot**:
- Read files **outside the workspace root** (the `markee-doc://` handler is
  sandboxed to that root; symlink escapes and path traversal are blocked).
- Replace the rendered view by navigating the main frame to another document
  (`.md` links are intercepted for in-window navigation; the scheme handler
  refuses to load Markdown into the main frame).
- Persist anything beyond the workspace files it can already write via the
  task-checkbox toggle — no arbitrary disk writes, no preferences.
- Escape the WebView process sandbox itself.

## Reporting a vulnerability

Open a private security advisory on GitHub
([Security tab → Report a vulnerability](https://github.com/sethbang/markee/security/advisories/new)),
or email howdy@sbang.dev — please don't open a public issue for
security-sensitive reports.

I'll aim to respond within a week.

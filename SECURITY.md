# Security

## Threat model

Markee is a local Markdown viewer. It renders the source file you point it at,
including any raw HTML embedded in the Markdown — `markdown-it` is configured
with `html: true` so the source can contain `<script>`, `<iframe>`, etc.

**Don't open `.md` files from sources you don't trust.** Treat opening a
Markdown file with Markee the same way you'd treat opening an HTML file in a
browser: the contents can execute code in Markee's WebView context.

## What a malicious `.md` can and can't do

A script inside a rendered `.md` runs inside Markee's WKWebView with no
network access, no file system access beyond the document directory, and
talks to the host app only through the `window.markee` bridge.

It **can**:
- Call `webkit.messageHandlers.markee.postMessage({...})` to send `taskToggle`
  (writes a checkbox back to disk on the line you specify), `error` (shows a
  banner), or `outline` (replaces the sidebar contents).
- Read any file inside the document's directory via `markee-doc://doc/...`.

It **cannot**:
- Make network requests (no remote resources are loaded).
- Read files outside the document directory (custom URL scheme handlers are
  sandboxed; symlink escapes are blocked; path traversal is blocked).
- Read other documents you have open.
- Persist anything beyond the file you opened.
- Escape the WebView sandbox.

## Reporting a vulnerability

Open a private security advisory on GitHub
([Security tab → Report a vulnerability](https://github.com/)),
or email howdy@sbang.dev — please don't open a public issue for
security-sensitive reports.

I'll aim to respond within a week.

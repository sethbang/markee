# Live-Reload Pipeline — Design Spec

A short internal-style design doc covering how Markee re-renders a file the
moment it's saved. This is the document used to demo the outline sidebar
with a realistic-feeling table of contents.

## Goals

The pipeline should:

- Re-render on every save without noticeable latency.
- Preserve scroll position across re-renders.
- Survive atomic-save patterns used by Vim, IntelliJ, and VS Code.
- Stay editor-agnostic.

## Non-goals

- Real-time keystroke streaming. Save is the natural commit boundary.
- Diff-based rendering. Full re-render is fast enough for any practical
  document size and dramatically simpler.

## Architecture

### File watcher

`FileWatcher` wraps a kqueue `DispatchSource`. When the inode under the
watched path changes — including the atomic-rename pattern — it schedules a
reattach to the new inode.

### Render bridge

The Swift host serializes `{source, fileName, docBase}` to JSON and calls
`window.markee.render(...)` inside the WebView. The renderer posts an
`{kind: "outline"}` reply back so SwiftUI can repopulate the sidebar.

### Outline tracker

An IntersectionObserver inside the WebView tracks which heading is
currently in the top 20% of the viewport and posts a `scrollSection`
message. SwiftUI publishes the active heading id; the sidebar binds to it
to draw the active-row indicator.

## Edge cases

### Atomic-save races

If the file is mid-rename when we read it, we get `EBUSY`. Retry once with
a 25 ms delay before surfacing an error banner.

### Front matter

YAML front matter is stripped before parsing, but heading source-line
numbers are offset by the stripped line count so editor-jump still lands
on the right line.

## Testing

- `FileWatcherTests` covers atomic save, in-place write, delete-then-recreate.
- `PreviewControllerTests` covers the bridge message kinds.
- `Tests/util.test.js` covers the pure helpers under Node.

## Open questions

- Should we expose a manual "re-render now" command? Probably not — saves
  are cheap and the watcher is reliable enough that explicit triggers feel
  redundant.

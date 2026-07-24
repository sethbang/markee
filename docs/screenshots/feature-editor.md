# v0.3 Roadmap

The next minor — what's in, what's deferred. This document is used to demo
the "open at heading in editor" right-click on the outline sidebar.

## In scope

### Notarization

Enroll in the Apple Developer Program, codesign with the Developer ID
Application cert, notarize. After this, the Open With picker stops
graying Markee out and the unsigned-app first-launch warning goes away.

### Homebrew cask

`brew install --cask markee` once notarization is done. Tap lives at
`sethbang/homebrew-markee`.

### DMG installer

Background image with drag-to-Applications arrow, automated via
`create-dmg`. Tag-triggered, attached to the GitHub Release.

## Shipped since

### Theme picker

Shipped — a Preferences window (⌘,) adds a System / Light / Dark override,
accent color, base font size, and a custom-CSS file.

### Print stylesheet

Shipped — a print-tuned `@media print` stylesheet now drives Print (⌘P) and
PDF export, with page-break handling for code, tables, KaTeX, and Mermaid.

## Process

PRs land on `feature/v0.3-*` branches. Merge to `main` only after a clean
CI run on the macOS matrix. Tag `v0.3.0` once notarization is verified
end-to-end with a clean download → quarantine → launch on a second Mac.

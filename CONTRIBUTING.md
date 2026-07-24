# Contributing to Markee

Markee is a small personal project. Issues, bug reports, and focused PRs are
all welcome. For anything larger than a small fix, please open an issue first
so we can talk through the approach before you spend time on it.

## Build + test

```sh
just fetch-vendor   # one-time
just app            # builds Markee.app at the repo root
just test           # Swift + JS tests
```

`just clean` resets everything (including the vendored JS libraries). Run `just` to list every recipe.

## Code style

- Match the existing patterns in `Sources/Markee/`.
- Default to **no comments**. Add one only when the *why* is non-obvious — a
  hidden constraint, a subtle invariant, a workaround for a specific bug.
  Don't explain *what* well-named code already says.
- Read `CLAUDE.md`'s "Non-obvious invariants" section before touching the
  `FileWatcher`, task-list write-back, or the scheme handlers — there are a
  few load-bearing behaviors that look incidental but aren't.
- Keep the editor-agnostic identity intact. Markee is a *viewer*; editing
  affordances should stay limited (the task-list checkboxes are the ceiling).

## Before opening a PR

- `just test` is green (Swift + JS).
- `just app` builds cleanly.
- SwiftLint passes: `swiftlint lint --strict Sources Tests` — CI runs this as a
  blocking gate (`--strict` makes warnings errors); install with
  `brew install swiftlint`.
- For UI changes, include a screenshot or short video.
- For invariant-adjacent changes, mention which invariant you touched and why
  it's still safe.

## Releases (maintainer notes)

- Bump `CFBundleShortVersionString` in `Resources/Info.plist` (and the two
  Quick Look extension plists).
- Update `CHANGELOG.md` — promote `[Unreleased]` to a `## [X.Y.Z] — <date>`
  section. The release workflow extracts the matching section as the release
  notes by an exact `## [VERSION]` match.
- Tag the commit and push the tag (`git tag vX.Y.Z && git push origin vX.Y.Z`).
  Pushing a `v*` tag triggers `.github/workflows/release.yml`, which lints,
  tests, Developer-ID-signs, notarizes, staples, zips, and publishes the GitHub
  Release automatically. The tag must equal `CFBundleShortVersionString` in
  `Resources/Info.plist` or the workflow fails. Don't build or publish by hand.

# Contributing to Markee

Markee is a small personal project. Issues, bug reports, and focused PRs are
all welcome. For anything larger than a small fix, please open an issue first
so we can talk through the approach before you spend time on it.

## Build + test

```sh
make fetch-vendor   # one-time
make app            # builds Markee.app at the repo root
make test           # Swift + JS tests
```

`make clean` resets everything (including the vendored JS libraries).

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

- `make test` is green (Swift + JS).
- `make app` builds cleanly.
- For UI changes, include a screenshot or short video.
- For invariant-adjacent changes, mention which invariant you touched and why
  it's still safe.

## Releases (maintainer notes)

- Bump `CFBundleShortVersionString` in `Resources/Info.plist`.
- Update `CHANGELOG.md`.
- Tag the commit (`git tag v0.X.Y`).
- Create a GitHub Release with the `.app` bundled as a zipped artifact.

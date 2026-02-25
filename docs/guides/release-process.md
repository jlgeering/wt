# Release Process Runbook

This runbook defines how to cut and publish a `wt` release on GitHub.

First release recommendation: `v0.1.0` (matches current `build.zig.zon`).

## Versioning rules

- Use Semantic Versioning with tag format `vX.Y.Z`.
- Keep embedded app version as `X.Y.Z` (no leading `v`).
- Pre-1.0 (`0.y.z`) policy:
  - Patch (`z`): bug fixes and low-risk internal changes with no intended behavior change.
  - Minor (`y`): any user-visible behavior/output/flag change, including breaking changes.

## Prerequisites

- GitHub CLI authenticated (`mise x -- gh auth status`).
- Clean working tree on `main`.
- CI/checks pass locally:
  - `mise install`
  - `mise run check`
  - `mise run build:all`

## Release checklist (`vX.Y.Z`)

1. Confirm version and changelog:
   - Decide target version (`X.Y.Z`) for the first public release.
   - `build.zig.zon` has `.version = "X.Y.Z"`.
   - `CHANGELOG.md` includes an `X.Y.Z` section with release notes.
2. Ensure release notes are finalized (use changelog content as source of truth).
3. Create and push annotated tag:

```bash
VERSION=0.1.0 # replace if first-release version decision differs

git checkout main
git pull --ff-only github main
git tag -a "v$VERSION" -m "wt v$VERSION"
git push github "v$VERSION"
```

4. Create GitHub release (first pass can be notes-only until release automation lands):

```bash
VERSION=0.1.0 # replace if first-release version decision differs

mise x -- gh release create "v$VERSION" \
  --verify-tag \
  --title "wt v$VERSION" \
  --notes-file CHANGELOG.md
```

5. Verify the release page:
   - Tag is `vX.Y.Z`.
   - Release notes render correctly.
   - Marked as latest (default behavior for first stable release).

## Artifact publishing (when pipeline is ready)

`wt-2fw` tracks the release artifact pipeline. When implemented, release should also:

- Build macOS (`aarch64`, `x86_64`), Linux (`aarch64`, `x86_64`), Windows (`x86_64`).
- Pass `-Dapp_version=X.Y.Z` to release builds.
- Upload archives and `SHA256SUMS` to the GitHub release.
- Verify `wt --version` from artifacts reports `wt X.Y.Z (<sha>)`.

## Do nots

- Do not retag or mutate an existing published version.
- If a release needs correction, publish the next version (for example `v0.1.1`).

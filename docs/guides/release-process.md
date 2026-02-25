# Release Process Runbook

This is the canonical process for publishing `wt` releases.

## Release contract

- Version format: `X.Y.Z` (SemVer)
- Tag format: `vX.Y.Z`
- Canonical release notes source: matching section in `CHANGELOG.md`
- Required GitHub release assets:
  - `wt-vX.Y.Z-darwin-arm64.tar.gz`
  - `wt-vX.Y.Z-darwin-amd64.tar.gz`
  - `wt-vX.Y.Z-linux-arm64.tar.gz`
  - `wt-vX.Y.Z-linux-amd64.tar.gz`
  - `wt-vX.Y.Z-windows-amd64.zip`
  - `SHA256SUMS`

This contract is chosen so users can install via `mise` `github:jlgeering/wt` without custom matching rules.

## Prerequisites

- On `main` with a clean working tree
- `CHANGELOG.md` includes `## [X.Y.Z] - YYYY-MM-DD`
- `build.zig.zon` and `build.zig` fallback version both set to `X.Y.Z`
- GitHub CLI authenticated: `mise x -- gh auth status`
- Local validation passes:
  - `mise run check`
  - `mise run build:all`

## Canonical command

```bash
mise run release -- <X.Y.Z>
```

Example:

```bash
mise run release -- 0.1.1
```

## What the release script does

`scripts/release.sh` performs the full flow:

1. Validates release preconditions:
   - clean git tree on `main`
   - semver input
   - no existing `vX.Y.Z` tag (local or remote)
   - version consistency across files
   - changelog section exists for `X.Y.Z`
2. Runs preflight checks (`mise run check`).
3. Builds all target binaries with `-Dapp_version=X.Y.Z`.
4. Packages artifacts with stable names and generates `SHA256SUMS`.
5. Pushes `main`, creates/pushes annotated tag `vX.Y.Z`.
6. Creates a **draft** GitHub release with changelog-derived notes and assets.
7. Verifies draft state, asset count, and notes body.
8. Publishes (`--draft=false`) and marks as latest.
9. Verifies `vX.Y.Z` is the latest GitHub release.

## Draft verification checklist

Before publish, verify the draft release has:

- Correct tag (`vX.Y.Z`)
- Exactly six required assets (5 archives + `SHA256SUMS`)
- Non-empty changelog-derived notes

After publish, verify:

- Release is not draft/prerelease
- Latest release endpoint resolves to `vX.Y.Z`

## Do nots

- Do not retag or mutate an existing published version.
- If a release needs correction, publish the next patch version (for example `v0.1.2`).

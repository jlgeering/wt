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

## Canonical command

```bash
mise run release -- <X.Y.Z>
```

Example:

```bash
mise run release -- 0.1.1
```

## What the mise release pipeline does

`mise run release -- <X.Y.Z>` orchestrates an internal task DAG and a Zig helper (`src/tools/release.zig`):

1. `release` exports `RELEASE_VERSION=<X.Y.Z>` and runs the internal release DAG.
2. `release:validate` validates git/version/changelog preconditions and writes notes to `dist/release/vX.Y.Z/notes.md`.
3. `release:build:*` cross-builds all target binaries with `-Dapp_version=X.Y.Z` into `dist/release/vX.Y.Z/build/<target>`.
4. `release:package` verifies host artifact version, packages archives, writes `SHA256SUMS`, and verifies checksums.
5. `release:git` pushes `main` and pushes annotated tag `vX.Y.Z`.
6. `release:gh:create-draft` creates a draft GitHub release with notes and required assets.
7. `release:gh:verify-draft` verifies draft state, asset count, and notes body.
8. `release:gh:publish` publishes and marks latest.
9. `release:gh:verify-latest` verifies latest release tag and prints release URL.

## Staging layout

Release artifacts are built in deterministic paths:

- `dist/release/vX.Y.Z/build/<target>/...`
- `dist/release/vX.Y.Z/dist/...`
- `dist/release/vX.Y.Z/notes.md`

## Inspecting the pipeline

Use these commands to inspect the internal DAG without publishing:

```bash
mise tasks deps release:pipeline
RELEASE_VERSION=<X.Y.Z> mise run -n release:pipeline
```

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

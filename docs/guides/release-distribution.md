# Release Distribution Policy

This document explains release-channel policy. For the exact execution steps, use the canonical runbook:

- `docs/guides/release-process.md`

## Primary distribution channel

Current primary channel is GitHub Releases with prebuilt binaries.

Supported targets:

- macOS: `arm64`, `amd64`
- Linux: `arm64`, `amd64`
- Windows: `amd64`

## Why GitHub Releases first

- Single source for versioned binaries and checksums
- Works across all supported target platforms
- Compatible with `mise` installs via `github:jlgeering/wt`
- Provides stable artifact URLs for downstream package managers

## Versioning and release cadence

- Tag format: `vX.Y.Z`
- Embedded app version: `X.Y.Z` (`-Dapp_version=X.Y.Z`)
- Never mutate an existing published tag/release
- Ship a new patch version for corrections

Pre-1.0 policy (`0.y.z`):

- Patch (`z`): bug fixes and low-risk internal changes with no intended behavior change
- Minor (`y`): user-visible behavior/output/flag changes

## Release notes policy

- `CHANGELOG.md` is the authoritative source for release notes
- Each `vX.Y.Z` release must have matching `## [X.Y.Z]` changelog section

## Integrity policy

For current releases, publish `SHA256SUMS` alongside archives and verify checksums before publish.

## Future channels

- Homebrew tap/formula is planned after GitHub release artifacts remain stable across multiple versions.

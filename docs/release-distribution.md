# Release and Distribution Findings (2026-02-23)

## Current state in this repo

- Cross-platform release builds already exist via `mise` tasks:
  - macOS: `aarch64`, `x86_64`
  - Linux: `aarch64`, `x86_64`
  - Windows: `x86_64`
- Binary version is embedded at build time via Zig option `-Dapp_version`; default fallback is `0.1.0`.
- `wt --version` prints embedded version + git SHA, so release builds should always set `-Dapp_version=<semver>`.

## Recommended rollout order

1. GitHub Releases (first)
2. Homebrew tap/formula (second, after release artifacts are stable)

Created beads:

- `wt-2fw` (P1): Set up GitHub Releases distribution pipeline
- `wt-3rp` (P2): Add Homebrew tap formula for wt

## Why GitHub Releases first

- Lowest maintenance path to distribute signed/versioned binaries.
- Works for all supported OS/arch targets immediately.
- Provides stable URLs and checksums that Homebrew can consume later.
- Keeps packaging policy in one place before adding downstream channels.

## Other options considered

- WinGet: good Windows UX, but higher ongoing manifest/update overhead.
- Scoop: easier than WinGet, still additional maintenance channel.
- Chocolatey: broader Windows ecosystem, more packaging/review overhead.

## Bash script vs `mise` task

Question: why a bash script instead of only `mise` tasks with dependencies?

Recommended approach is hybrid:

- Keep reusable compile units in `mise` tasks (already done: `build:mac`, `build:linux`, `build:windows`).
- Put release orchestration in `scripts/release.sh`:
  - validate clean git/tag/version state
  - call build steps
  - package archives with stable names
  - generate checksums
  - publish via `gh release`
- Expose one ergonomic entrypoint via `mise run release` that calls the script.

Rationale:

- `mise.toml` is great for straightforward task composition, but release flows typically need branching, loops, error traps, and richer validation.
- A script is easier to test locally and in CI, easier to review, and avoids packing complex shell logic into TOML multiline strings.
- The wrapper `mise run release` still keeps toolchain policy and developer UX consistent.

## Versioning strategy (how and when to create versions)

This project should use Semantic Versioning (`MAJOR.MINOR.PATCH`) and keep a human-focused changelog.

### Tag and version format

- Git tag format: `vX.Y.Z` (for example `v0.4.2`)
- Embedded app version: `X.Y.Z` passed as `-Dapp_version=X.Y.Z`
- Rule: never republish or mutate an existing tag/version; publish a new one instead

### Pre-1.0 policy (`0.y.z`)

While `wt` is pre-1.0, API/behavior may still change. Use this practical rule:

- `0.y.z` patch (`z`): bug fixes, docs-only, low-risk internal refactors, no intentional behavior change
- `0.y+1.0` minor (`y`): any user-visible behavior/CLI/output change, new command/flag, or breaking change

This keeps intent clear without overusing patch versions for behavior shifts before stability.

### Post-1.0 policy (`>=1.0.0`)

- Patch (`x.y.Z`): backward-compatible bug fixes only
- Minor (`x.Y.0`): backward-compatible feature additions/deprecations
- Major (`X.0.0`): breaking changes

### When to cut a release

- Patch release: when 1+ user-facing bug fixes are merged and validated
- Minor release: when a coherent feature set is complete, or any pre-1.0 behavior change lands
- Release candidate (optional): tag `vX.Y.Z-rc.N` when changes are broad/risky and early testers are available

### Suggested cadence and gates

- Prefer release-on-merge-window over strict calendar cadence
- Before tagging:
  - `mise run test` passes
  - cross-build artifacts succeed for target matrix
  - changelog entry exists for the version
  - `wt --version` from artifacts reports expected `X.Y.Z`

### Changelog policy

- Maintain `CHANGELOG.md` with sections per release version and release date
- Group entries under: `Added`, `Changed`, `Fixed`, `Deprecated`, `Removed`, `Security` (when applicable)
- Every release tag must have a matching changelog section

## Source references

- GitHub Releases docs: <https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases>
- GitHub CLI release create: <https://cli.github.com/manual/gh_release_create>
- Semantic Versioning 2.0.0: <https://semver.org/spec/v2.0.0.html>
- Keep a Changelog 1.1.0: <https://keepachangelog.com/en/1.1.0>
- Homebrew tap/formula docs:
  - <https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap>
  - <https://docs.brew.sh/Formula-Cookbook>
- WinGet docs: <https://learn.microsoft.com/en-us/windows/package-manager/winget/>
- Scoop manifests: <https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests>
- Chocolatey package creation: <https://docs.chocolatey.org/en-us/create/create-packages/>

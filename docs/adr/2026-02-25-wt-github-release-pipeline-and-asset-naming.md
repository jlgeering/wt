# ADR: Tag-Driven GitHub Release Pipeline and Canonical Asset Names

- Status: Superseded
- Date: 2026-02-25
- Decision Makers: wt maintainers
- Superseded By: `2026-02-28-wt-defer-github-release-workflow-until-ci-hardening.md`

## Context

`wt` had cross-platform build tasks, but release publishing was still manual. This made artifact naming, checksum publication, and release-note structure prone to drift.

Downstream distribution tasks (for example Homebrew formula automation) need stable URLs and deterministic filenames.

## Decision

1. Add a tag-driven GitHub Actions workflow at `.github/workflows/release.yml` triggered by `v*.*.*`.
2. Build and package the supported release targets:
   - Linux: `x86_64`, `aarch64`
   - macOS: `x86_64`, `aarch64`
   - Windows: `x86_64`
3. Publish assets with canonical names:
   - `wt_<version>_linux_x86_64.tar.gz`
   - `wt_<version>_linux_arm64.tar.gz`
   - `wt_<version>_macos_x86_64.tar.gz`
   - `wt_<version>_macos_arm64.tar.gz`
   - `wt_<version>_windows_x86_64.zip`
   - `SHA256SUMS`
4. Require release builds to embed app version via `-Dapp_version=<X.Y.Z>`.
5. Add a release notes template at `.github/release-notes-template.md` and document verification steps in the release runbook.

## Consequences

- Release publication becomes consistent, reproducible, and easier to audit.
- Homebrew/tap automation can rely on stable artifact names and checksums.
- Releases now depend on GitHub Actions and `GITHUB_TOKEN` release permissions.
- This decision was later deferred in favor of a mise-only release path until CI hardening.

# ADR: Release Publishing Contract (Notes + Artifacts)

- Status: Accepted
- Date: 2026-02-25
- Decision Makers: wt maintainers

## Context

`v0.1.0` established the first public GitHub release, but it exposed two release quality gaps:

1. release notes were not curated from a canonical source
2. no binary assets were attached to the release

The project also needs direct compatibility with `mise` installs using `github:jlgeering/wt`.

## Decision

Adopt the following release contract for all stable releases:

1. Canonical release process lives in `docs/guides/release-process.md`.
2. Canonical release notes source is `CHANGELOG.md` section `## [X.Y.Z]`.
3. Release command is `mise run release -- <X.Y.Z>` via `scripts/release.sh`.
4. Every release publishes exactly these assets:
   - `wt-vX.Y.Z-darwin-arm64.tar.gz`
   - `wt-vX.Y.Z-darwin-amd64.tar.gz`
   - `wt-vX.Y.Z-linux-arm64.tar.gz`
   - `wt-vX.Y.Z-linux-amd64.tar.gz`
   - `wt-vX.Y.Z-windows-amd64.zip`
   - `SHA256SUMS`
5. Releases are created as draft, verified, then published and marked latest.
6. For now, integrity uses SHA256 checksums only (no signing/attestations required).

## Consequences

Benefits:

- predictable public release quality (notes + assets)
- platform-complete binary distribution
- compatibility with `mise` GitHub installs without custom matching
- single canonical runbook for humans and agents

Costs and risks:

- release script maintenance overhead
- stricter preconditions can block release until docs/version metadata are aligned
- signing/attestation remains a future improvement

## References

- `docs/guides/release-process.md`
- `docs/guides/release-distribution.md`
- <https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases>
- <https://cli.github.com/manual/gh_release_create>
- <https://mise.jdx.dev/dev-tools/backends/github.html>

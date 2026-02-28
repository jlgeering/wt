# ADR: Defer GitHub Release Workflow Until CI Hardening

- Status: Accepted
- Date: 2026-02-28
- Decision Makers: wt maintainers

## Context

`wt` has a canonical release process driven by `mise run release -- <X.Y.Z>` with policy checks and publish steps enforced by the mise task graph and Zig helper.

The repository also had a separate tag-driven GitHub Actions workflow (`.github/workflows/release.yml`) plus a workflow-specific notes template (`.github/release-notes-template.md`).

Keeping both paths increases maintenance overhead and can drift policy enforcement while CI and GitHub automation conventions are still being hardened.

## Decision

1. Remove the tag-driven GitHub release workflow for now.
2. Remove workflow-only template artifacts tied to that workflow.
3. Keep the mise-native release pipeline as the sole canonical release path until CI/GitHub hardening work is complete.
4. Revisit and reintroduce GitHub workflow automation later under a dedicated CI/GitHub effort.

## Consequences

Benefits:

- one release path reduces ambiguity and policy drift
- lower maintenance burden while CI conventions are still evolving
- release checks remain enforced in one place (`mise` + `src/tools/release.zig`)

Costs and risks:

- no tag-triggered automated release publication in GitHub Actions for now
- maintainers must run the release command intentionally from a prepared local environment
- GitHub workflow reintroduction remains tracked future work

## References

- `docs/guides/release-process.md`
- `docs/adr/2026-02-25-wt-github-release-pipeline-and-asset-naming.md`
- `docs/adr/2026-02-25-wt-mise-release-task-graph.md`

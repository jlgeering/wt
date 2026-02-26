# ADR: Use a Mise-Native Release Task Graph with Zig Helper

- Status: Accepted
- Date: 2026-02-25
- Decision Makers: wt maintainers

## Context

Release automation was implemented as a monolithic Bash script (`scripts/release.sh`) invoked by `mise run release`.

That implementation worked, but it had two maintainability problems:

1. release orchestration lived outside the project task graph
2. shell-heavy logic increased complexity for validation, packaging, and portability

We still need the same release contract (command, notes source, artifacts, draft/publish checks), but with `mise` as the canonical orchestration layer.

## Decision

Adopt a mise-native release pipeline with hidden internal tasks and a Zig helper:

1. Keep maintainer entrypoint `mise run release -- <X.Y.Z>`.
2. Replace script orchestration with a task DAG (`release:validate`, `release:build:*`, `release:package`, `release:git`, `release:gh:*`).
3. Move heavy release logic into `src/tools/release.zig` subcommands:
   - `validate`
   - `extract-notes`
   - `verify-host`
   - `package`
   - `verify-checksums`
4. Keep GitHub release API interactions on `gh` via `mise x -- gh ...`.
5. Use deterministic staging paths under `dist/release/vX.Y.Z/...`.
6. Remove `scripts/release.sh`.

This ADR supersedes the script-specific implementation detail in `2026-02-25-wt-release-publishing-contract.md` (Decision item 3) while preserving the same public release contract.

## Consequences

Benefits:

- release flow is first-class in `mise` dependency orchestration
- less Bash-specific logic in the critical path
- reusable/testable release behavior in Zig code
- deterministic staging paths aid reproducibility and debugging

Costs and risks:

- more `mise` task definitions to maintain
- helper code must stay aligned with release policy and docs
- release now depends on both Zig helper behavior and task-graph wiring

## References

- `docs/guides/release-process.md`
- `docs/adr/2026-02-25-wt-release-publishing-contract.md`
- `src/tools/release.zig`

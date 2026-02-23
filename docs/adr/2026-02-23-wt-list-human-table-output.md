# ADR: `wt list` Human Table Output

- Status: Superseded
- Date: 2026-02-23
- Decision Makers: wt maintainers

## Context

Superseded by `2026-02-23-wt-list-status-model-base-upstream.md`.

`wt list` now has a stable machine contract via `--porcelain`.
That enables improving default human output without risking script breakage.

The prior human format was readable but dense and less scannable across many worktrees.

## Decision

Default `wt list` output used a table-like layout with explicit columns:

1. `CUR` marker (`*` for current worktree)
2. `BRANCH`
3. `STATUS`
4. `PATH`

Status used compact tokens:

- `clean`
- `M:<n>` and/or `U:<n>` (no literal `dirty` prefix in human rows)
- optional divergence suffixes `\u2191<n>` and `\u2193<n>`
- `unknown` when git status inspection fails

## Consequences

This ADR is retained for history only; current behavior is defined in `2026-02-23-wt-list-status-model-base-upstream.md`.

- Human output is easier to scan in terminals and picker previews.
- Script users should rely on `wt list --porcelain` for stability.
- Future UI tweaks to human formatting remain possible without changing machine contracts.

## References

- `/Users/jlg/src/wt/src/commands/list.zig`
- `/Users/jlg/src/wt/docs/adr/2026-02-23-wt-list-porcelain-mode.md`

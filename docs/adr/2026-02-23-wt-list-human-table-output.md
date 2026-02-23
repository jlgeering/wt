# ADR: `wt list` Human Table Output

- Status: Proposed
- Date: 2026-02-23
- Decision Makers: wt maintainers

## Context

`wt list` now has a stable machine contract via `--porcelain`.
That enables improving default human output without risking script breakage.

The prior human format was readable but dense and less scannable across many worktrees.

## Decision

Default `wt list` output uses a table-like layout with explicit columns:

1. `CUR` marker (`*` for current worktree)
2. `BRANCH`
3. `STATUS`
4. `PATH`

Status uses compact tokens:

- `clean`
- `dirty M:<n> U:<n>`
- optional divergence suffixes `^<ahead>` and `v<behind>`
- `unknown` when git status inspection fails

## Consequences

- Human output is easier to scan in terminals and picker previews.
- Script users should rely on `wt list --porcelain` for stability.
- Future UI tweaks to human formatting remain possible without changing machine contracts.

## References

- `/Users/jlg/src/wt/src/commands/list.zig`
- `/Users/jlg/src/wt/docs/adr/2026-02-23-wt-list-porcelain-mode.md`

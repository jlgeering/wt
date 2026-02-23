# ADR: `wt list` Shows Branch Divergence

- Status: Proposed
- Date: 2026-02-23
- Decision Makers: wt maintainers

## Context

`wt list` currently reports worktree cleanliness (clean vs modified/untracked), but does not show branch divergence from upstream.  
That makes it harder to scan which worktrees have local-only commits that still need to be pushed, or branches that are behind remote.

We want this signal in default output without making status text noisy.

## Decision

For each worktree in `wt list`:

1. Keep existing cleanliness summary (`clean` or `<n> modified, <m> untracked`).
2. Read branch divergence from `git status --porcelain --branch`.
3. Append divergence only when meaningful, using compact arrow counters:
   - append `^<n>` when ahead > 0
   - append `v<m>` when behind > 0
4. Do not add extra text for synced or no-upstream branches.

Examples:

- `(clean, ^2)`
- `(1 modified, 3 untracked, v1)`
- `(clean, ^2 v1)`
- `(clean)` for synced/no-upstream/detached branches.

## Consequences

- `wt list` is more useful for daily branch hygiene and push/pull decisions.
- Output remains compact because zero-value divergence is omitted.
- Divergence reflects local Git metadata and may be stale until users fetch.

## References

- `/Users/jlg/src/wt/src/commands/list.zig`
- `/Users/jlg/src/wt/src/lib/git.zig`

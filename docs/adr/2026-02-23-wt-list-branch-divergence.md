# ADR: `wt list` Shows Branch Divergence

- Status: Superseded
- Date: 2026-02-23
- Decision Makers: wt maintainers

## Context

Superseded by `2026-02-23-wt-list-status-model-base-upstream.md`.

`wt list` currently reports worktree cleanliness (clean vs modified/untracked), but does not show branch divergence from upstream.  
That makes it harder to scan which worktrees have local-only commits that still need to be pushed, or branches that are behind remote.

We want this signal in default output without making status text noisy.

## Decision

This ADR described upstream-only divergence in the prior status model.

For each worktree in `wt list`:

1. Keep existing cleanliness summary (`clean` or compact change tokens such as `M:<n> U:<n>`).
2. Read branch divergence from `git status --porcelain --branch`.
3. Append divergence only when meaningful, using compact arrow counters:
   - append `\u2191<n>` when ahead > 0
   - append `\u2193<n>` when behind > 0
4. Do not add extra text for synced or no-upstream branches.

Examples:

- `clean \u21912`
- `M:1 U:3 \u21931`
- `clean \u21912 \u21931`
- `clean` for synced/no-upstream/detached branches.

## Consequences

This ADR is retained for history only; current behavior is defined in `2026-02-23-wt-list-status-model-base-upstream.md`.

- `wt list` is more useful for daily branch hygiene and push/pull decisions.
- Output remains compact because zero-value divergence is omitted.
- Divergence reflects local Git metadata and may be stale until users fetch.

## References

- `/Users/jlg/src/wt/src/commands/list.zig`
- `/Users/jlg/src/wt/src/lib/git.zig`

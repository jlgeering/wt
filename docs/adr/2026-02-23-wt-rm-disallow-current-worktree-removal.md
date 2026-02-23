# ADR: `wt rm` Disallow Removing the Current Worktree

- Status: Proposed
- Date: 2026-02-23
- Decision Makers: wt maintainers

## Context

`wt rm` could remove the same worktree that the user was currently inside. Git allows the removal, but the shell then points at a deleted directory. This leads to confusing post-command behavior and follow-on failures.

The issue appears in multiple flows:

- `wt rm <branch>` when `<branch>` matches the current secondary worktree
- `wt rm` interactive selection when the current secondary worktree is listed as a candidate
- single-candidate confirmation when the only candidate is the current secondary worktree

## Decision

1. Detect the current checkout path via `git rev-parse --show-toplevel`.
2. Refuse branch-targeted removal when it resolves to the current worktree.
3. In no-arg interactive mode, exclude the current secondary worktree from removable candidates.
4. When exclusion leaves no removable candidates, stop with a warning that explains why and how to proceed.
5. Keep main-checkout behavior unchanged: from main, all secondary worktrees remain eligible.

## Consequences

- Users are protected from ending up in a deleted current directory.
- Interactive picker behavior becomes clearer and safer with explicit messaging.
- `wt rm` now has a small amount of extra branching around current-worktree detection and candidate filtering.

## References

- `docs/adr/2026-02-20-wt-rm-interactive-picker.md`
- `docs/adr/2026-02-20-wt-rm-single-candidate-and-cancel-keys.md`

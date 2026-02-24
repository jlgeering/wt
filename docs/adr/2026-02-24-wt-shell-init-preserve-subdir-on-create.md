# ADR: Preserve Relative Subdirectory On `wt new|add` Shell Auto-CD

- Status: Accepted
- Date: 2026-02-24
- Decision Makers: wt maintainers

## Context

Shell integration currently auto-enters the new worktree after `wt new` and `wt add`, but it always lands at the worktree root.

When users run creation commands from nested directories, this resets context and requires extra manual navigation to return to the same location within the newly created checkout.

## Decision

1. For shell integration `wt new|add` paths, capture the current repo-relative path using `git rev-parse --show-prefix`.
2. After successful creation, prefer entering `<new-worktree>/<relative-subdir>` when it exists.
3. If that subdirectory does not exist in the new worktree, print a short note and fall back to the new worktree root.
4. Keep command-line interface, porcelain output contract, and no-arg picker behavior unchanged.

## Consequences

- Creation flow preserves user context across worktrees when directory structure matches.
- Branches with moved/deleted paths still succeed predictably via root fallback.
- The shell wrapper gains a small amount of path-selection logic but remains backward-compatible.

# ADR: Clarify Shell Entered-Worktree Message Layout

- Status: Accepted
- Date: 2026-02-24
- Decision Makers: wt maintainers

## Context

Shell integration currently reports the final `cd` target as `Entered worktree: <path>`.

When subdirectory-preserving navigation is active, that path may be `<worktree-root>/<subdir>`, which makes it harder to quickly identify the actual selected worktree root.

## Decision

1. Replace the single-line entered message with a compact summary block after successful shell navigation.
2. Print a leading blank line before the block for readability during interactive use.
3. Report worktree root and subdirectory separately:
   - `Entered worktree: <worktree-root>`
   - `Subdirectory: <relative-subdir>` only when entered below root
4. Use distinct ANSI colors for worktree and subdirectory values when stdout is a TTY, and plain text otherwise.
5. Apply this output format consistently to both no-arg `wt` picker jumps and `wt new|add` auto-enter paths.

## Consequences

- Shell output no longer conflates worktree identity with current subdirectory.
- Interactive feedback becomes easier to scan while preserving non-TTY compatibility.
- Wrapper logic adds a small shared formatting helper per shell function.

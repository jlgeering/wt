# ADR: `wt shell-init` No-Argument Worktree Picker

- Status: Proposed
- Date: 2026-02-23
- Decision Makers: wt maintainers

## Context

The shell integration currently intercepts `wt new` so the active shell can `cd` into newly created worktrees. Running `wt` with no arguments still invokes the binary directly, which does not provide the "jump to worktree" interaction users expect in day-to-day navigation.

We need a no-argument behavior that is:

- interactive and quick in TTY sessions
- consistent with existing picker policy used by `wt rm` (`auto` prefers `fzf`, fallback to built-in)
- safe to cancel without side effects

## Decision

When using shell integration (`wt shell-init zsh|bash`):

1. Running `wt` with no arguments opens a worktree picker.
2. Picker backend uses `fzf` when available on `PATH`.
3. If `fzf` is unavailable, shell integration falls back to a built-in numbered prompt.
4. On selection, the wrapper changes directory to the selected worktree and prints `Entered worktree: <path>`.
5. Cancellation is a no-op and returns success.
6. If there is only one worktree entry, picker flow is skipped and the wrapper reports there is nothing to pick.
7. Existing `wt new` interception behavior remains unchanged.

## Consequences

- Navigation between worktrees becomes one command (`wt`) in integrated shells.
- Users get fuzzy search automatically when `fzf` is installed, without making it a hard dependency.
- The shell wrapper grows in complexity due to interactive picker logic in both zsh and bash templates.

## References

- `/Users/jlg/src/wt/src/commands/shell_init.zig`
- `/Users/jlg/src/wt/src/commands/rm.zig`

# ADR: `wt rm` Interactive Picker and Backend Policy

- Status: Proposed
- Date: 2026-02-20
- Decision Makers: wt maintainers

## Context

`wt init` now has a polished interactive flow, but `wt rm` without a branch only printed a plain list and required users to compose an external picker manually. This created UX inconsistency and extra friction for a common command where users typically want to select one entry quickly.

We needed to decide:

- whether no-arg `wt rm` should be interactive by default
- whether to depend on an external picker (`fzf`/`gum`) or provide a built-in fallback
- how cancellation should behave
- what happens in non-interactive contexts

## Decision

1. `wt rm` without a branch is interactive by default when running in a TTY.
2. Picker backend policy is hybrid:
   - default `--picker auto` uses `fzf` if present on `PATH`
   - otherwise it falls back to a built-in interactive picker
3. `gum` is out of scope for this iteration.
4. Add explicit controls:
   - `--picker auto|builtin|fzf`
   - `--no-interactive`
5. Cancellation in picker mode (`Esc`, `q`, cancel from `fzf`) is treated as a no-op and exits successfully.
6. `wt rm` without a branch is not supported in non-interactive sessions:
   - command exits with guidance to use `wt list` or pass a branch explicitly.
7. Picker rows include safety context before selection:
   - dirty counts (modified/untracked)
   - `local-commits` marker when branch-backed and ahead of main checkout
   - detached worktrees are selectable and removable by path

## Consequences

- `wt rm` matches `wt init` interaction quality and reduces selection friction.
- Users do not need extra setup for baseline functionality; built-in picker is always available.
- Users with `fzf` installed get fuzzy search automatically.
- Command behavior is clearer: `wt list` is for listing, `wt rm` is for removal.
- Additional implementation complexity is introduced for backend resolution and interactive terminal input handling.

## References

- NO_COLOR convention: https://no-color.org/

# ADR: Internal Picker Command and Shared Picker Formatting

- Status: Accepted
- Date: 2026-02-23
- Decision Makers: wt maintainers

## Context

No-argument shell integration (`wt` after `wt shell-init`) embedded picker selection and formatting logic directly in shell templates. That approach duplicated behavior and made alignment fragile:

- shell `awk` formatting counted bytes rather than visible terminal width in some environments
- picker headers and rows were maintained separately in multiple places
- `wt rm` had its own independent header/row spacing with drift risk

We need one implementation path for picker behavior and one source of truth for column rendering.

## Decision

1. Add internal command `wt __pick-worktree` that performs interactive worktree selection and prints only the selected path on stdout.
2. Keep shell wrappers thin: for no-arg `wt`, call `wt __pick-worktree`, then `cd` to the returned path.
3. Introduce shared picker formatting helpers in Zig and reuse them for:
   - no-arg worktree picker
   - `wt rm` FZF picker rows/header
4. Use FZF `--header-lines=1` with header injected in input so header and row rendering follow the same transform path.
5. Use FZF `--accept-nth 1` for stable selected identifier parsing.

## Consequences

- Column alignment is deterministic and no longer split between shell and Zig logic.
- Shell templates are smaller and easier to maintain.
- Picker behavior stays consistent with existing backend policy (`auto` prefers `fzf`, fallback builtin).
- We introduce an internal command surface (`__pick-worktree`) that should remain undocumented for now.

## References

- `/Users/jlg/src/wt/src/commands/pick_worktree.zig`
- `/Users/jlg/src/wt/src/lib/picker_format.zig`
- `/Users/jlg/src/wt/src/commands/rm.zig`
- `/Users/jlg/src/wt/src/commands/shell_init.zig`

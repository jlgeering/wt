# ADR: Add `wt add` Alias For `wt new`

- Status: Accepted
- Date: 2026-02-23
- Decision Makers: wt maintainers

## Context

Existing team workflows and mise tasks commonly use an `add` verb for worktree creation (`wt:add`).  
In the WT Zig CLI, creation currently lives under `wt new`, which is functional but inconsistent with those workflows.

This mismatch creates avoidable friction when switching from project-local task wrappers to the native `wt` binary.

## Decision

1. Add a first-class `wt add` subcommand as an alias of `wt new`.
2. Keep argument and output behavior identical:
   - `wt add [--porcelain] <branch> [base]`
3. Keep shell integration parity:
   - wrappers that auto-`cd` on creation must treat both `new` and `add` the same.
4. Keep `wt new` as-is for backward compatibility and documentation continuity.

## Consequences

- Users can choose whichever verb is more intuitive (`new` or `add`) without behavior drift.
- Existing scripts using `wt new` remain valid.
- Shell-init wrapper behavior remains consistent across both creation verbs.

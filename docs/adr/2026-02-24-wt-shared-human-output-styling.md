# ADR: Shared Human Output Styling for CLI Commands

- Status: Proposed
- Date: 2026-02-24
- Decision Makers: wt maintainers

## Context

Command output styling was inconsistent across `wt` commands. Some paths used colored, structured output while others used plain `std.debug.print` lines. This made interactive usage feel uneven and reduced scanability, especially during `wt new`, `wt rm`, and picker/setup flows.

At the same time, machine-readable output contracts (`--porcelain` and internal stdout contracts) must remain stable.

## Decision

Introduce a shared output helper (`src/lib/ui.zig`) with:

- consistent level labels (`Info`, `Success`, `Warning`, `Error`)
- TTY + `NO_COLOR` aware color behavior
- shared ANSI constants for command renderers

Refactor human-facing command logs to use the shared helper while preserving:

- existing porcelain schemas and field counts
- stdout-only machine outputs (for example, `wt new --porcelain`)

## Consequences

Benefits:

- consistent message structure across commands
- improved visual scanability in interactive sessions
- reduced duplicated color/label logic

Costs and risks:

- human text changed (scripts scraping human output may need updates)
- more shared coupling on `ui.zig`

Mitigations:

- porcelain behavior remains unchanged and is validated in tests/smoke checks

## References

- `src/lib/ui.zig`
- `src/commands/new.zig`
- `src/commands/rm.zig`
- `src/commands/pick_worktree.zig`
- `src/lib/setup.zig`

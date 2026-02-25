# ADR: Add `wt ls` Alias For `wt list`

- Status: Accepted
- Date: 2026-02-25
- Decision Makers: wt maintainers

## Context

`wt list` is a high-frequency command in interactive workflows.
Some users prefer short uppercase verbs for rapid shell usage.

## Decision

1. Add `ls` as an alias of `list`.
2. Keep behavior identical between `wt list` and `wt ls`.
3. Include the alias in shell-init completion output and alias-aware tests.
4. Keep `list` as the canonical command name in usage/help output.

## Consequences

- Users can run `wt ls` as a shorthand for worktree listing.
- Existing scripts and docs that use `wt list` remain valid.
- Completion remains consistent with parser-supported aliases.

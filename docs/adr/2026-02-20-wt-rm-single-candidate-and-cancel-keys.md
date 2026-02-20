# ADR: `wt rm` Single-Candidate Confirmation and Cancel Key Policy

- Status: Proposed
- Date: 2026-02-20
- Decision Makers: wt maintainers

## Context

`wt rm` no-arg interactive mode now supports both picker workflows and cancellation keys. Two UX refinements were requested:

- keep fast cancellation via `Esc`/Ctrl-C, but keep prompt copy concise
- avoid showing a picker when there is only one removable worktree

These are user-facing behavior choices that affect discoverability, safety, and consistency in future interactive screens.

## Decision

1. Keep `Esc` and Ctrl-C as valid cancel actions in interactive `wt rm` flows.
2. Use concise prompt copy (`q` to quit) while preserving hidden `Esc`/Ctrl-C support.
3. When exactly one secondary worktree exists, bypass picker/FZF and show a direct confirmation prompt.
4. A declined or canceled confirmation remains a no-op with successful command exit.

## Consequences

- Faster path for the common single-target case.
- Cleaner prompt text with unchanged power-user escape hatches.
- Slight increase in interaction branching and test surface.
- Establishes a pattern for future interactive commands: concise documented keys plus permissive hidden cancel keys.

## References

- `docs/adr/2026-02-20-wt-rm-interactive-picker.md`

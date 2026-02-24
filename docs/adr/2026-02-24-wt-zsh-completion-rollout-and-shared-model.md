# ADR: zsh Completion Rollout and Shared CLI Completion Model

- Status: Accepted
- Date: 2026-02-24
- Decision Makers: wt maintainers

## Context

`wt` already provides shell integration wrappers for `zsh` and `bash` through `wt shell-init <shell>`.
We want completion support, but each shell has a different completion mechanism and different integration requirements.

We also want to avoid duplicating command-surface metadata across future shell-specific completion implementations.

## Decision

1. Roll out completion in phases, starting with `zsh` only.
2. Deliver zsh completion through existing `wt shell-init zsh` output, with no extra install step.
3. Introduce a shared CLI completion model in source that records:
   - user-visible completion commands and aliases
   - positional kinds for completion behavior
   - shell enum values used by completion
4. Keep the initial completion UX intentionally minimal:
   - suggest subcommands and aliases
   - suggest positional values for `new|add`, `rm`, and `shell-init`
   - do not suggest flags
5. Keep internal commands hidden from completion (`__pick-worktree` is excluded).
6. Defer bash/fish completion implementation to follow-up work that reuses the shared model.

## Consequences

- Users on zsh get completion with no additional setup beyond existing shell-init usage.
- Completion remains focused and low-noise by excluding flags.
- The shared model reduces drift and rework when adding additional shell renderers later.
- We accept temporary asymmetry: zsh gets completion first, while bash/fish wait for later phases.

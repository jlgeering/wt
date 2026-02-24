# ADR: Fish Shell Support and Completion via `shell-init`

- Status: Accepted
- Date: 2026-02-24
- Decision Makers: wt maintainers

## Context

`wt shell-init` supported `zsh` and `bash`, with completion only in `zsh`.
Fish users had no first-class wrapper for no-arg picker navigation or automatic `cd` after `wt new|add`.
We also wanted fish completion to reuse the shared CLI completion model introduced for zsh.

## Decision

1. Add `fish` as a supported `wt shell-init <shell>` target.
2. Emit a fish wrapper function that preserves existing shell-wrapper behavior:
   - no-arg `wt` routes through `wt __pick-worktree` and `cd`s into the selection
   - `wt new|add` routes through `--porcelain` and `cd`s into the created worktree
   - both flows preserve repo-relative subdirectory when present
3. Register fish completion from `shell-init fish` output:
   - subcommands and aliases from shared `cli_surface` metadata
   - positional suggestions for `new|add`, `rm`, and `shell-init`
4. Keep completion scope intentionally minimal (no flag suggestions).
5. Keep bash behavior unchanged (wrapper only, no completion) in this phase.

## Consequences

- Fish users now get parity for navigation workflows with shell integration.
- Fish gets low-noise completion aligned with zsh’s positional-only approach.
- Shared completion metadata continues to reduce command-surface drift across shell renderers.
- Completion remains asymmetric across shells (`zsh` + `fish`, not `bash`).

## References

- `docs/adr/2026-02-24-wt-zsh-completion-rollout-and-shared-model.md`
- `src/commands/shell_init.zig`
- `src/lib/cli_surface.zig`

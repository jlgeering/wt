# ADR: Nushell Shell-Init Support and Completion

- Status: Accepted
- Date: 2026-02-24
- Decision Makers: wt maintainers

## Context

`wt shell-init` already supported `zsh` and `bash` wrappers for no-arg picker navigation and `new|add` auto-directory changes.

A tracked follow-up requested first-class Nushell support. We needed to decide the canonical shell key (`nu` vs `nushell`), preserve existing wrapper behavior expectations, and define completion scope without adding noisy flag suggestions.

## Decision

1. Add Nushell support to `wt shell-init` with canonical key `nu`.
2. Accept `nushell` as a compatibility alias for invocation, while documenting `nu` as the primary key.
3. Emit a Nushell wrapper that mirrors existing shell behavior:
   - no-arg `wt` opens the worktree picker and changes directory on selection
   - `wt new|add` runs porcelain mode, changes directory on success, and preserves repo-relative subdirectory when possible
   - all other invocations pass through to the underlying `wt` binary
4. Ship minimal Nushell completion in the shell-init output:
   - suggest subcommands and aliases
   - suggest positional values for `new|add`, `rm`, and `shell-init`
   - do not suggest flags
5. Keep shell-name completion model shared through `cli_surface` so zsh and Nushell stay aligned.

## Consequences

- Nushell users get parity with existing shell wrapper workflows and do not need a separate completion installer.
- The command surface now has three documented shell targets (`zsh`, `bash`, `nu`) plus one accepted alias (`nushell`).
- Completion remains intentionally low-noise and focused on common positional flows.

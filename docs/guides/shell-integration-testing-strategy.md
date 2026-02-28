# Shell Integration Testing Strategy

This guide documents the baseline `wt shell-init` test strategy used in this repo.

Scope covers generated wrappers for `zsh`, `bash`, `fish`, and `nu` (`nushell` alias), with runtime integration currently exercised for `zsh`, `bash`, and `nu`.

## Contract To Validate

1. `wt new|add` wrapper flow:
   - calls `__new`
   - preserves repo-relative subdirectory when present
   - falls back to worktree root when subdirectory is missing
2. Bare `wt` flow:
   - interactive sessions run picker flow
   - non-interactive sessions pass through to the real binary
3. Wrapper pass-through:
   - non-intercepted commands invoke the real `wt`
4. Stream/status behavior:
   - shell-specific stderr handling remains visible to users
   - exit/status semantics are preserved for wrapped and pass-through paths

## Current Automated Coverage

### 1) Unit-level template assertions

File: `src/commands/shell_init.zig`

- Verifies emitted snippets contain required wrapper branches and completion definitions.
- Locks shell-specific adapter details (including Nushell picker stderr/TTY handling).

### 2) Real-shell non-PTY integration tests

File: `test/integration_shell_init.zig`

- Runtime parity for `zsh`/`bash`/`nu` `new|add` auto-`cd` behavior.
- Non-interactive bare `wt` pass-through checks for `zsh`/`bash`/`nu`:
  - no picker invocation
  - unchanged working directory
  - passthrough status visibility

### 3) PTY integration for interactive picker

File: `test/integration_shell_init.zig`

- PTY cancel-path coverage for bare `wt` picker across `zsh`/`bash`/`nu`.
- Confirms interactive picker prompt remains reachable and cancellation is non-destructive.

## Validation Commands

1. `mise run format`
2. `mise run test`

Optional manual spot checks:

1. Source shell-init in your shell startup file.
2. Verify `wt new <branch>` changes into the created worktree.
3. Verify bare `wt` opens picker in interactive terminal.
4. Verify bare `wt` in a non-interactive shell script behaves like plain binary invocation.

## Known Gaps / Follow-ups

1. Fish runtime parity is not yet covered by real-shell integration tests.
2. Additional explicit failure-path assertions for `new|add` stderr/no-`cd` invariants can be expanded further.

These are tracked as follow-up work, while current baseline already guards the interactive-only no-arg policy and cross-shell wrapper contract.

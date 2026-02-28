# Shell Integration Testing Strategy

This guide documents the current `wt shell-init` test baseline and optional coverage.

Scope covers generated wrappers for `zsh`, `bash`, `fish`, and `nu` (`nushell` alias), with real-shell runtime coverage for all four shells.

## Contract To Validate

1. `wt new|add` wrapper flow:
   - calls `__new`
   - preserves repo-relative subdirectory when present
   - falls back to worktree root when subdirectory is missing
   - on failure or empty/missing path output, keeps cwd unchanged and surfaces stderr
2. Bare `wt` flow:
   - interactive sessions run picker flow
   - non-interactive sessions pass through to the real binary
3. Wrapper pass-through:
   - non-intercepted commands invoke the real `wt`
4. Stream/status behavior:
   - shell-specific stderr handling remains visible to users
   - exit/status semantics are preserved for wrapped and pass-through paths

## Baseline Automated Coverage

### 1) Template contract assertions

Files: `src/commands/shell_init.zig`, `test/integration_shell_init.zig`

- Verifies generated snippets for `zsh`/`bash`/`fish`/`nu` contain shared wrapper markers and subdir-preservation logic.
- Asserts shell-specific details, including Nushell `err> /dev/tty` picker handling and `nushell` alias parity.

### 2) Real-shell runtime parity (non-PTY)

File: `test/integration_shell_init.zig`

- `zsh`/`bash`/`fish`/`nu` parity for `new|add` auto-`cd` behavior.
- `zsh`/`bash`/`fish`/`nu` failure-path checks for `new|add`:
  - stderr is surfaced
  - no false "Entered worktree" output
  - cwd remains unchanged when output is empty/missing
- `zsh`/`bash`/`fish`/`nu` non-interactive bare `wt` pass-through checks:
  - no picker invocation
  - unchanged working directory
  - passthrough status visibility
- Nushell-specific pass-through check confirms `$env.LAST_EXIT_CODE` parity.

### 3) Interactive PTY coverage

File: `test/integration_shell_init.zig`

- PTY cancel-path coverage for bare `wt` picker across `zsh`/`bash`/`nu`.
- Confirms picker prompt visibility and non-destructive cancellation (cwd unchanged).

## Optional / Environment-Dependent Coverage

These tests are in the baseline suite but may skip based on host setup:

1. Runtime shell tests skip per shell if that shell binary is not installed.
2. PTY coverage skips when `script` is unavailable.
3. Fish PTY picker cancel coverage is temporarily disabled pending PTY watchdog/harness hardening (`wt-2eq`).

## Validation Commands

1. `mise run test`
2. `mise x -- zig build test-integration`

Optional local checks:

1. `mise run lint`
2. Source shell-init in your shell startup file and verify:
   - `wt new <branch>` changes into created worktree (or root fallback)
   - bare `wt` opens picker in an interactive terminal
   - bare `wt` in non-interactive execution behaves like plain binary invocation

## Remaining Gaps / Next Beads

1. Nushell PTY fallback runtime branch (`err> /dev/tty` failure) is only template-asserted today, not runtime-asserted. Follow-up: `wt-3v5`.

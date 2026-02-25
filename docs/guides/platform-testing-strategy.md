# Platform-Specific Testing Strategy

This guide documents practical ways to test platform-conditional behavior in `wt` across macOS, Linux, and Windows.

Scope:
- compile-time OS branches (for example `comptime builtin.os.tag` checks)
- runtime behavior differences (filesystem/process/shell behavior)
- interactive terminal logic (TTY vs non-TTY, single-key vs line input)

## Current Platform-Conditional Surface

Notable areas in this repo:

1. `src/commands/init.zig`
   - `tryReadSingleKey` uses POSIX `termios` on non-Windows.
   - Windows branch returns `null` and falls back to line-input prompts.
2. `src/commands/rm.zig`
   - same single-key vs line-input split as `init`.
3. `src/lib/setup.zig`
   - `cowCopy` chooses `cp` flags by OS:
     - macOS: `cp -cR`
     - Linux: `cp -R --reflink=auto`
     - fallback: `cp -R`

These paths need both compile validation and native runtime validation.

## Candidate Coverage Matrix

| Layer | Local | CI | Purpose |
| --- | --- | --- | --- |
| Cross-target compile checks | `mise run build:all` | Ubuntu job runs `mise run build:all` | Proves all target branches compile (`aarch64/x86_64` macOS + Linux, `x86_64` Windows). |
| Native unit+integration tests (Linux) | `mise run test` | `ubuntu-latest` job runs `mise run test` | Baseline runtime behavior in primary dev/CI environment. |
| Native unit+integration tests (macOS) | `mise run test` on macOS host | `macos-latest` job runs `mise run test` | Catches macOS-specific process and filesystem differences. |
| Native unit+integration tests (Windows) | `mise run test` on Windows host | `windows-latest` job runs `mise run test` (or staged smoke subset first) | Validates Windows runtime branches and path/process behavior. |
| Release artifact smoke | `mise run build:all`, run packaged binary on host OS | Run per-OS smoke command after packaging | Confirms shipped binaries start and run core commands. |

## Compile Checks vs Runtime Checks

### Compile Checks (cross-target)

Use cross-target builds to guard compile-time branches:

```bash
mise run build:all
```

This catches:
- unavailable APIs/types for a target
- target-specific compile errors in `switch (builtin.os.tag)` paths
- packaging regressions in release targets

It does not catch runtime behavior (TTY semantics, process exit handling, filesystem oddities).

### Runtime Checks (native OS)

Run tests on each target OS host:

```bash
mise run test
```

This catches:
- real process/shell behavior differences
- filesystem behavior and path handling differences
- interactive fallbacks triggered by non-TTY/TTY behavior

## Practical Options For OS-Conditional + Interactive Logic

### Option 1: Expand pure-function unit tests (lowest cost)

Keep factoring prompt decisions/parsers into pure helpers and test directly.

Best for:
- key parsing
- mode selection
- cancel/confirm decisions

Limits:
- does not validate terminal mode transitions or real subprocess behavior.

### Option 2: Native non-interactive integration tests (recommended baseline)

Run command flows with piped stdin/stdout and explicit flags to avoid flaky interactive timing.

Best for:
- success/failure command flows
- fallback line-input paths
- filesystem/process effects

Limits:
- does not validate raw-mode keypress UX.

### Option 3: PTY harness tests for raw-mode paths (targeted use)

Use a PTY-capable harness (for example `script`, `expect`, or a Zig/Python PTY helper) to validate single-key flows where needed.

Best for:
- `init`/`rm` single-key behavior on POSIX
- escape/cancel and immediate key responses

Limits:
- highest complexity/flakiness
- not available in the same way on all runners

### Option 4: Windows-focused behavior checks

On Windows, prioritize tests that confirm:
- line-input fallback behavior is used
- no POSIX-only assumptions leak into runtime paths
- path and process behavior match expectations

Start with non-interactive tests and add targeted interactive coverage only if concrete bugs appear.

## Tradeoffs and Limitations

1. Cross-compiling is cheap and broad, but compile-only.
2. Native runtime CI is higher confidence, but slower and costlier.
3. PTY coverage gives realistic terminal confidence, but is maintenance-heavy.
4. Windows CI often reveals quoting/path edge cases late; staged rollout reduces disruption.

## Recommended Path

1. Add/keep compile matrix check on every PR:
   - `mise run build:all`
2. Add native runtime test jobs:
   - Linux + macOS first (`mise run test`)
   - Windows runtime test next (start smoke-level if full suite is unstable)
3. Keep interactive logic mostly in unit + non-interactive integration tests.
4. Add PTY tests only for high-risk paths or regressions that other layers cannot catch.

This gives broad platform safety early while keeping maintenance cost controlled.

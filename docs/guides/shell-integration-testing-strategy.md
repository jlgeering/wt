# Shell Integration Testing Strategy

This guide documents practical ways to test `wt shell-init` behavior in both automated and local workflows.

Scope: shell wrapper behavior for `zsh` and `bash` (with notes for extending to `fish` and `nu`).

## Behaviors To Validate

Core behavior to verify:

1. `wt new|add` wrapper captures machine output (`wt __new`) correctly.
2. Wrapper changes directory (`cd`) only when the returned path exists.
3. Wrapper preserves error streams so users still see failures and warnings.
4. No-arg `wt` path (picker workflow) remains functional.
5. Non-intercepted subcommands pass through unchanged.

## Candidate Approaches

### 1) Unit-level string assertions (already in place)

What it checks:

- Generated shell-init snippets contain expected branches/functions/commands.
- Completion snippets include expected command and flag candidates.

Current status:

- This repo already has many string-level tests in `src/commands/shell_init.zig`.

Pros:

- Fast and stable.
- Easy to maintain.
- Good for regressions in emitted template text.

Cons:

- Does not execute in a real shell.
- Cannot validate actual `cd` side effects or stream-routing behavior.

### 2) Integration tests using real shell processes (recommended next)

What it checks:

- End-to-end wrapper execution in real `zsh`/`bash` processes.
- `pwd` changes after `wt new` through the wrapper.
- `stderr` and `stdout` behavior under success/failure paths.

How to structure:

1. Create temp repo fixture (similar to existing integration tests).
2. Emit shell-init script into a temporary file:
   - `wt shell-init zsh > /tmp/wt.zsh`
   - `wt shell-init bash > /tmp/wt.bash`
3. Run shell with `-c` to source script and execute assertions:
   - start in repo root
   - run wrapper call (`wt new feat-x`)
   - print `pwd` and compare to expected worktree path
4. Capture shell `stdout`, `stderr`, and exit code from parent test process.

Pros:

- High confidence in real runtime behavior.
- Catches wrapper execution bugs that unit tests cannot.

Cons:

- Requires target shells installed in CI/runtime.
- Slightly slower and more environment-dependent than unit tests.

### 3) PTY/interaction harness for picker-heavy behavior (optional)

What it checks:

- Interactive flows that depend on TTY behavior (for example picker cancellation keys).

Pros:

- Closest to real user terminal behavior.

Cons:

- Most complex and flaky option.
- Highest maintenance burden.
- Not needed for initial parity checks.

## Stream-Routing Validation

For `wt new|add` wrapper behavior, include explicit checks:

1. Success path:
   - `stdout` should not include unrelated noise from wrapper internals.
   - `pwd` should move to the new worktree path.
2. Failure path:
   - force a command failure (for example invalid base ref).
   - verify user-facing error appears on `stderr`.
   - verify working directory remains unchanged.

## Local Workflow

For local manual verification before merge:

1. `mise run build`
2. In a temp repo, source shell-init snippet for target shell.
3. Run:
   - `wt new <branch>` and confirm directory handoff.
   - failing `wt new <branch> <bad-base>` and confirm stderr + no `cd`.
   - `wt` no-arg flow and cancel path behavior.

## CI Workflow

Recommended phased rollout:

1. Keep current unit tests as baseline.
2. Add non-interactive real-shell integration tests for `zsh` and `bash`.
3. Gate shell-specific tests so missing shell binaries skip with clear message.
4. Add optional PTY coverage only where non-PTY tests cannot cover behavior.

## Reliability Risks And Mitigations

Risk: shell binary differences across runners.
Mitigation: pin test shell versions where feasible; skip with explicit diagnostics if unavailable.

Risk: brittle assertions against full output text.
Mitigation: assert key invariants (`pwd`, exit code, presence of key stderr markers) instead of full output equality.

Risk: filesystem race or temp-path assumptions.
Mitigation: use per-test temp dirs and absolute-path checks.

## Recommended Path

Recommended strategy for this repo:

1. Continue unit string tests in `shell_init.zig`.
2. Implement real-shell integration tests for `zsh` and `bash` as the primary new coverage.
3. Defer PTY harness work until a concrete bug requires it.

This balances confidence and maintenance cost, and directly supports follow-up implementation bead `wt-1od`.

# ADR: Capture Help Smoke-Test Output During `zig build test`

- Status: Accepted
- Date: 2026-02-24
- Decision Makers: wt maintainers

## Context

`zig build test` included smoke checks that executed:

- `wt --help`
- `wt list --help`
- `wt rm --help`
- `wt shell-init --help`
- `wt __pick-worktree --help`

These checks used inherited stdio, so successful runs printed full help text into normal test output. That made `mise run test` hard to scan even when everything passed.

## Decision

1. Keep help smoke checks in `build.zig`, but run them in check mode (`Run.addCheck`) instead of inherited stdio.
2. Assert on key usage text in stdout, require empty stderr, and require exit code 0.
3. Keep integration behavior assertions unchanged, but run setup actions in quiet mode inside integration tests to avoid non-essential progress lines.

## Consequences

- `mise run test` stays concise on success.
- Help-output regressions still fail tests with explicit checks.
- Failing smoke checks still show diagnostic output, but successful runs remain quiet.

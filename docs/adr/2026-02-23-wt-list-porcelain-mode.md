# ADR: `wt list` Porcelain Mode

- Status: Proposed
- Date: 2026-02-23
- Decision Makers: wt maintainers

## Context

`wt list` default output is human-oriented and now includes concise status summaries.
That format is intentionally readable, but brittle for shell scripting and editor integrations.

`wt new` already has a porcelain mode, and shell wrappers increasingly depend on stable machine output.

## Decision

Add `wt list --porcelain` with one tab-separated row per worktree:

`current<TAB>branch<TAB>path<TAB>status<TAB>modified<TAB>untracked<TAB>ahead<TAB>behind<TAB>has_upstream`

Field semantics:

1. `current`: `1` if this is the caller's current working tree, else `0`
2. `branch`: branch name or `(detached)`
3. `path`: absolute worktree path
4. `status`: `clean`, `dirty`, or `unknown`
5. `modified`: modified/staged entry count
6. `untracked`: untracked entry count
7. `ahead`: commits ahead of upstream
8. `behind`: commits behind upstream
9. `has_upstream`: `1` when upstream is configured, else `0`

## Consequences

- Scripts can consume `wt list` without parsing aligned human text.
- Shell integrations can display richer status while staying robust.
- The porcelain schema becomes a compatibility contract that should remain stable.

## References

- `/Users/jlg/src/wt/src/commands/list.zig`
- `/Users/jlg/src/wt/src/commands/shell_init.zig`

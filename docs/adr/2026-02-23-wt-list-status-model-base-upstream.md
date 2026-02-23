# ADR: `wt list` Status Model Splits `WT`, `BASE`, and `UPSTREAM`

- Status: Accepted
- Date: 2026-02-23
- Decision Makers: wt maintainers

## Context

`wt list` previously compressed multiple concepts into one `STATUS` field:

- working-tree dirtiness
- divergence from upstream

At the same time, `wt rm` surfaced "unmerged" wording that overlapped conceptually with "untracked" token shorthand (`U`) and caused ambiguity in human output.

Users need a scan-friendly view that distinguishes:

1. file dirtiness
2. branch divergence vs main worktree branch
3. branch divergence vs upstream

## Decision

### Human output

Default `wt list` output now uses explicit columns:

1. `CUR`
2. `BRANCH`
3. `WT`
4. `BASE`
5. `UPSTREAM`
6. `PATH`

Column semantics:

- `WT`: `clean`, `dirty`, or `unknown`
- `BASE`: branch divergence against the main worktree branch
  - `=`, `\u2191<n>`, `\u2193<n>`, `\u2191<n>\u2193<n>`, `-`, or `unknown`
- `UPSTREAM`: branch divergence against configured upstream
  - `=`, `\u2191<n>`, `\u2193<n>`, `\u2191<n>\u2193<n>`, `-`, or `unknown`

`BASE` appears before `UPSTREAM` to prioritize local workflow decisions first.

### `wt rm` wording

`wt rm` picker and confirmation language now uses:

- `clean` / `dirty`
- optional `local-commits`

No commit count is shown for local commits in the human summary.

### Porcelain schema

`wt list --porcelain` remains tab-separated but uses a richer schema:

`current<TAB>branch<TAB>path<TAB>wt<TAB>tracked_changes<TAB>untracked<TAB>base_ref<TAB>base_ahead<TAB>base_behind<TAB>has_upstream<TAB>upstream_ahead<TAB>upstream_behind`

Field semantics:

1. `current`: `1` if this is the caller's current worktree, else `0`
2. `branch`: branch name or `(detached)`
3. `path`: absolute worktree path
4. `wt`: `clean`, `dirty`, or `unknown`
5. `tracked_changes`: tracked status-entry count (modified/deleted/renamed/etc)
6. `untracked`: untracked entry count
7. `base_ref`: main worktree branch name, or `-` when unavailable
8. `base_ahead`: commits ahead of `base_ref`, `-1` when unavailable/unknown
9. `base_behind`: commits behind `base_ref`, `-1` when unavailable/unknown
10. `has_upstream`: `1` when upstream is configured, else `0`
11. `upstream_ahead`: commits ahead of upstream, `-1` when unavailable/unknown
12. `upstream_behind`: commits behind upstream, `-1` when unavailable/unknown

## Consequences

- Human output is less ambiguous and easier to scan.
- Local and remote divergence are clearly separated.
- Existing porcelain consumers must update for the new field layout.
- Shell integration can render richer picker columns without parsing overloaded status strings.

## References

- `/Users/jlg/src/wt/src/commands/list.zig`
- `/Users/jlg/src/wt/src/commands/rm.zig`
- `/Users/jlg/src/wt/src/commands/shell_init.zig`
- `/Users/jlg/src/wt/README.md`

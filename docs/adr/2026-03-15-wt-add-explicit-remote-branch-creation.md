# ADR: `wt add` Uses Explicit Remote Qualification For Remote Branch Creation

- Status: Accepted
- Date: 2026-03-15
- Decision Makers: wt maintainers

## Context

`wt new|add` already supports two local workflows:

- reuse an existing local branch in a new worktree
- create a new local branch from a base ref and create a worktree for it

We also want `wt` to support creating a worktree from an existing remote branch.

The main UX question is how much branch resolution `wt` should infer automatically. In repositories with multiple remotes, auto-resolving bare names like `foo` against `origin/foo` or `upstream/foo` adds ambiguity and makes it harder to explain when upstream tracking is configured.

At the same time, `wt list` now exposes explicit upstream divergence, so remote-based creation benefits from predictable tracking setup.

## Decision

1. Remote-branch creation requires explicit remote qualification: `wt add <remote>/<branch>`.
2. Bare branch names never trigger remote lookup.
3. When `<remote>` matches a configured Git remote, `wt add <remote>/<branch>`:
   - creates a local branch named `<branch>` from `<remote>/<branch>`
   - configures the local branch to track `<remote>/<branch>`
   - creates the worktree for local branch `<branch>`
4. `BASE` remains valid only for bare branch-name creation; remote-qualified creation rejects `BASE`.
5. If the derived local branch already exists during remote-qualified creation, the command fails instead of mutating that branch's upstream configuration.

## Consequences

- Multi-remote repositories get deterministic behavior with no guessing.
- `wt add foo` keeps its existing local/new-branch semantics.
- Remote-based worktrees immediately report meaningful upstream status in `wt list`.
- Users must type the remote name when they want remote-branch behavior.
- Local branch names that intentionally start with a configured remote name are treated as remote-qualified input by this command.

## References

- `README.md`
- `docs/specs/command-reference.md`
- `docs/adr/2026-02-23-wt-list-status-model-base-upstream.md`
- `src/commands/new.zig`

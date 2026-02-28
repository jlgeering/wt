# ADR: `wt init` Symlinks Local Mise And Claude Settings By Default

- Status: Accepted
- Date: 2026-02-28
- Decision Makers: wt maintainers

## Context

`wt init` previously recommended `copy.paths` entries for:

- `mise.local.toml` (and related variants)
- `.claude/settings.local.json`

That default created duplicated local configuration across worktrees. Changes made in one worktree would not propagate unless copied again, leading to drift and extra maintenance.

## Decision

1. Change built-in `wt init` path recommendations for local mise variants to `symlink.paths`.
2. Change built-in `wt init` path recommendations for `.claude/settings.local.json` to `symlink.paths`.
3. Keep existing setup execution behavior unchanged: `copy.paths` still performs CoW-aware copies and `symlink.paths` still creates links.
4. Keep command recommendation behavior unchanged (`mise trust` detection and gating).

## Consequences

- New `.wt.toml` recommendations now keep these local settings shared across all worktrees by default.
- Existing repos that already have copy entries keep their current behavior until users run `wt init` and apply the proposed changes.
- Setup flow behavior is now aligned across root and invocation-subdir recommendation scopes for these paths.

## References

- `src/lib/init_rules.zig`
- `src/lib/init_planner.zig`
- `docs/specs/init-and-config.md`

# ADR: `wt init` Recommends Elixir `deps` And `_build` CoW Copy Paths

- Status: Accepted
- Date: 2026-02-28
- Decision Makers: wt maintainers

## Context

`wt new` already supports copy-on-write-friendly copy behavior for configured `[copy].paths` values.

Elixir worktrees commonly benefit from reusing dependency and build directories:

- `deps`
- `_build`

Without explicit `wt init` recommendations, users must remember to add these paths manually even when an Elixir project is clearly present.

## Decision

1. Detect Elixir project roots in `wt init` using `mix.exs`.
2. When `mix.exs` is found at repo root or a discovered subproject root, recommend:
   - `<prefix>/deps`
   - `<prefix>/_build`
3. Keep existing detection-scope behavior unchanged:
   - repo-wide, CWD-invariant detection
   - bounded subproject scanning (default depth 2 unless internally overridden)
4. Keep setup execution semantics unchanged:
   - recommendations feed `[copy].paths`
   - copy behavior remains CoW-aware where available on each platform

## Consequences

- Elixir repositories get useful default setup entries with no manual config authoring.
- Nested Elixir subprojects inherit the same default recommendation behavior when within scan scope.
- Deeply nested or hidden subproject roots remain excluded under existing scan-depth and hidden-root rules.

## References

- `src/lib/init_rules.zig`
- `src/lib/init_planner.zig`
- `docs/specs/init-and-config.md`
- `docs/adr/2026-02-28-wt-init-repo-wide-cwd-invariant-subproject-scan.md`

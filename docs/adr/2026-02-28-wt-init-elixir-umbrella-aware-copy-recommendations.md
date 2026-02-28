# ADR: `wt init` Suppresses Elixir Copy Recommendations For Umbrella Child Apps

- Status: Accepted
- Date: 2026-02-28
- Decision Makers: wt maintainers

## Context

`wt init` now recommends Elixir CoW copy targets (`deps`, `_build`) when `mix.exs` is detected.

In umbrella projects, child apps under `apps/*` typically share umbrella-root `deps` and `_build` locations configured by the umbrella root `mix.exs` (via `apps_path`). Recommending per-child `apps/*/deps` and `apps/*/_build` can be incorrect and noisy.

## Decision

1. Keep recommending Elixir `deps` and `_build` for every detected `mix.exs` root by default.
2. Add umbrella-aware suppression:
   - if a detected `mix.exs` prefix is a child app directly under `*/apps/*`
   - and the parent mix project is an umbrella root (`apps_path` present in parent `mix.exs`)
   - then do not emit child-level `deps`/`_build` recommendations for that prefix.
3. Preserve all other detection behavior:
   - non-umbrella nested mix projects continue to receive per-prefix `deps`/`_build` recommendations
   - scan depth and hidden-root rules remain unchanged

## Consequences

- `wt init` output is more accurate for umbrella layouts by avoiding redundant child-app copy recommendations.
- Root umbrella recommendations still include `deps` and `_build`.
- Non-umbrella monorepo layouts are unaffected.

## References

- `src/lib/init_planner.zig`
- `src/lib/init_rules.zig`
- `docs/specs/init-and-config.md`
- `docs/adr/2026-02-28-wt-init-elixir-cow-copy-paths.md`

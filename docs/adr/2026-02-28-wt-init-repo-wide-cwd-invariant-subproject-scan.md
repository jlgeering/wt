# ADR: `wt init` Repo-Wide, CWD-Invariant Detection With Bounded Subproject Scan

- Status: Accepted
- Date: 2026-02-28
- Decision Makers: wt maintainers

## Context

`wt init` recommendation detection previously depended on invocation context (`repo root + invocation subdir`).

- Running `wt init` from different directories in the same repo could produce different proposals.
- Nested subprojects (for example `piazza/*`) were easy to miss when running from repo root.
- The behavior was surprising for a repo-wide config file (`.wt.toml`) and required manual fixes.

## Decision

1. Make `wt init` detection repo-wide and cwd-invariant by default.
2. Replace invocation-driven default scope with repo-root + discovered subprojects.
3. Discover subprojects with a bounded scan (default depth: 2).
4. Respect `.gitignore`/standard Git excludes during discovery.
5. Skip hidden subproject roots during recursive prefix discovery.
6. For command recommendations detected in subprojects, emit repo-relative prefixed commands (for example `cd apps/api && mise trust`).
7. Keep trust gating behavior: only recommend `mise trust` for scopes already trusted.

## Consequences

- Running `wt init` from repo root or any nested folder yields the same recommendation set.
- Detection covers the repo root and common nested project layouts without unbounded recursion.
- `.wt.toml` proposals better match multi-project repos and reduce manual command/path edits.
- The scan depth is currently an internal default (2); CLI override may be added later.

## Supersedes

- `2026-02-28-wt-init-shared-root-subdir-detection-scope.md` (default detection strategy)

## References

- `src/lib/init_rules.zig`
- `src/lib/init_planner.zig`
- `docs/specs/init-and-config.md`

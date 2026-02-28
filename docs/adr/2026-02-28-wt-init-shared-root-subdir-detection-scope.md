# ADR: Shared Repo-Root/Subdir Detection Scope For `wt init`

- Status: Accepted
- Date: 2026-02-28
- Decision Makers: wt maintainers

## Context

`wt init` recommendations were derived from detection rules, but scope handling was not explicit across all detector types.

- path recommendations were effectively repo-root centric
- subfolder context handling was not modeled as a shared rule concern
- command recommendation gating (`mise trust`) needed the same scope semantics as file/path detectors

This made root vs subfolder behavior harder to reason about and extend consistently.

## Decision

1. Introduce a shared detection-scope model in init rules (`repo_root`, `invocation_subdir`, `repo_root_and_invocation_subdir`).
2. Default built-in path and command rules to `repo_root_and_invocation_subdir`.
3. Pass invocation subdirectory context from `wt init` via `git rev-parse --show-prefix`.
4. Evaluate all detection-driven setup recommendations (copy/symlink/run) through the same scoped planner flow.

## Consequences

- Root and subfolder invocation contexts now follow one consistent detection model.
- Running `wt init` from a nested directory can propose repo-relative subfolder paths when matching files exist.
- Existing root recommendations remain intact due dual-scope default.
- Future recommendation rules can opt into precise scope behavior without one-off detector logic.

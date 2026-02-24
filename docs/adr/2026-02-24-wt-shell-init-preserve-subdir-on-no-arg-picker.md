# ADR: Preserve Relative Subdirectory On No-Arg `wt` Picker Jumps

- Status: Accepted
- Date: 2026-02-24
- Decision Makers: wt maintainers

## Context

Shell integration no-argument `wt` currently jumps to the selected worktree root.

After introducing subdirectory preservation for `wt new|add`, no-arg picker jumps remained inconsistent and still required manual navigation when switching between worktrees from nested paths.

## Decision

1. For no-arg shell-integration picker flows, capture the current repo-relative path using `git rev-parse --show-prefix`.
2. After selecting a worktree path, prefer entering `<selected-worktree>/<relative-subdir>` when it exists.
3. If that subdirectory does not exist in the selected worktree, print a short note and fall back to the selected worktree root.
4. Keep picker source, no-arg interaction model, and other subcommand behavior unchanged.

## Consequences

- No-arg `wt` navigation now preserves subdirectory context, matching `wt new|add` behavior.
- Missing-path cases remain predictable with root fallback.
- Shell wrapper gains additional path-selection logic but keeps backward-compatible invocation semantics.

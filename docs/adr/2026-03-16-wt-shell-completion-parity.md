# ADR: Shell Completion Parity Policy

- Status: Accepted
- Date: 2026-03-16
- Decision Makers: wt maintainers

## Context

`wt shell-init` emits shell integration for `zsh`, `bash`, `fish`, and `nu`, including
tab completion. Today that completion support is uneven:

- Bash has broader coverage for flags and some flag values.
- zsh, fish, and nushell focus on subcommands and selected positionals.
- the docs describe some of that asymmetry as intentional
- completion behavior for partial-token matching, aliases, ordering, and exclusion rules is
  not specified as a user-facing contract

That leaves two problems:

1. user-visible completion behavior can drift by shell without a clear policy boundary
2. specs and tests do not define the expected parity level for supported shells

This is a policy decision, not just an implementation cleanup. Shell completion is part of the
interactive CLI surface, and supported shells should not silently diverge unless there is a
documented reason.

## Decision

Adopt a **parity-by-default completion policy** for all supported shells.

### 1. Completion is a user-facing contract

Completion behavior for supported shells is part of the public `wt` interface. It belongs in the
specs, not only in generated shell scripts or guide prose.

### 2. Supported shells should expose the same completion surface

For `zsh`, `bash`, `fish`, and `nu`, `wt shell-init` should provide the same completion categories
for public commands unless a shell-specific exception is documented.

The shared completion surface includes:

- public subcommands and their aliases
- command positionals backed by dynamic candidate sources
- root flags and command flags
- flag-value completions where `wt` defines a constrained value set
- prefix filtering for partial tokens
- exclusion and deduplication rules for dynamic candidates

### 3. Shell-specific exceptions must be explicit

An exception is allowed only when:

1. the shell cannot safely or reasonably express the shared behavior,
2. the exception is documented in the spec and shell guide, and
3. at least one test covers the exception path.

Absent an explicit exception, completion differences across supported shells are bugs.

### 4. Specs drive the test matrix

Completion tests should be derived from the documented contract, including parity scenarios for:

- subcommands and aliases
- positional completion candidates
- partial-token matching
- flags and flag values
- dynamic exclusion rules such as omitting the current worktree branch from `rm` and `switch`

## Consequences

- Positive:
  - supported shells converge on one documented interactive UX
  - completion regressions become easier to identify and review
  - docs stop treating shell skew as the default maintenance model
- Costs:
  - more shell-init implementation work in zsh, fish, and nushell
  - new completion-focused tests are required beyond script-shape assertions
  - specs must be kept in sync as commands and flags evolve

## Options Considered

1. Keep Bash richer and document lighter support elsewhere.
   - Pros: lowest short-term effort.
   - Cons: preserves drift as policy; weak user expectations.
2. Parity-by-default across supported shells (chosen).
   - Pros: clearer UX contract, cleaner docs, better long-term maintainability.
   - Cons: requires adapter work and broader tests.
3. Immediate generator/DSL rewrite for completions.
   - Pros: strongest long-term unification story.
   - Cons: too much architecture change for the current gap.

## References

- `docs/specs/command-reference.md`
- `docs/guides/shell-integration.md`
- `docs/adr/2026-02-28-wt-shell-init-cross-shell-robustness-model.md`
- `src/commands/shell_init.zig`
- `src/lib/cli_surface.zig`
- `test/integration_shell_init.zig`

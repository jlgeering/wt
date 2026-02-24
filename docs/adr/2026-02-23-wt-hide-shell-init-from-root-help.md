# ADR: Hide `wt shell-init` From Root Help

- Status: Accepted
- Date: 2026-02-23
- Decision Makers: wt maintainers

## Context

`wt shell-init` is a compatibility/bootstrap command used to emit shell wrapper
functions. It is useful when explicitly configuring shell integration, but it is
not part of the primary day-to-day worktree workflow.

Listing it in `wt --help` adds noise to the top-level command list and competes
with the core task-oriented commands (`list`, `new`, `rm`, `init`).

## Decision

1. Keep `wt shell-init` supported as a hidden compatibility command.
2. Remove it from the root command registry so it no longer appears in
   `wt --help`.
3. Preserve direct invocation behavior (`wt shell-init <shell>`) by handling it
   before root command parsing.

## Consequences

- `wt --help` is more focused on primary workflows.
- Existing shell integration snippets that call `wt shell-init zsh|bash` keep
  working.
- `wt shell-init --help` remains available via its dedicated parser path.

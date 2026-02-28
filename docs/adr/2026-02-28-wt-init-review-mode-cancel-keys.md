# ADR: `wt init` Review-Mode Cancel Keys

- Status: Accepted
- Date: 2026-02-28
- Decision Makers: wt maintainers

## Context

`wt init` supported `Esc`/Ctrl-C cancellation on top-level decision screens, but review-mode per-change yes/no prompts did not treat these keys as cancel actions.

In practice, users entering review mode could get trapped in the prompt loop when trying to abort with `Esc`/Ctrl-C.

## Decision

1. Extend review-mode yes/no prompt parsing to treat `Esc` and Ctrl-C as explicit cancel decisions.
2. On cancel during review mode, exit immediately with `No changes written.` and skip config writes.
3. Add parser tests covering single-key and line-input cancel handling for review-mode yes/no prompts.

## Consequences

- `wt init` now has consistent cancellation semantics across top-level and review-mode prompts.
- Users can reliably abort interactive review without forcing terminal recovery.

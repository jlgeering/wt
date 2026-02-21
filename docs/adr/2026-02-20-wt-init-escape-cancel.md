# ADR: `wt init` Escape-Key Cancel Behavior

- Status: Proposed
- Date: 2026-02-20
- Decision Makers: wt maintainers

## Context

`wt init` already supports single-key input in interactive prompts. Users requested explicit support for `Esc` cancellation on top-level decision screens so they can back out immediately without stepping through follow-up menus.

## Decision

1. Keep the existing default semantics for Enter/y/n prompts.
2. Treat `Esc` and Ctrl-C as immediate quit on:
   - `Apply changes? [Y/n]`
   - `Choose next step` (`e`/`q`) screen
3. Quitting from either path exits without writing config changes.
4. Keep review-mode per-item prompts unchanged in this iteration.

## Consequences

- Faster, lower-friction cancellation for `wt init`.
- Better consistency with other interactive command cancel behavior.
- Slightly more decision-branch logic, covered by unit tests.

## References

- `docs/adr/2026-02-20-wt-init-interaction-model.md`
- `docs/adr/2026-02-20-wt-rm-single-candidate-and-cancel-keys.md`

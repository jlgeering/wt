# ADR: `wt init` Interaction Model

- Status: Accepted
- Date: 2026-02-20
- Decision Makers: wt maintainers

## Context

`wt init` had prompt friction and ambiguous branching:

- users had to confirm too many items
- option semantics were unclear (`n` vs review)
- menu choices were not self-explanatory
- `n` required Enter due canonical line input

We also needed anti-pattern output to be useful without noisy always-on text.

## Decision

1. Use a proposal-first flow:
   - discover recommended additions/removals
   - show one summary
   - ask for one top-level decision
2. Keep the top prompt simple:
   - `Apply changes? [Y/n]`
3. If declined, show explicit action menu:
   - `[e] Edit proposed changes one by one`
   - `[q] Quit without writing`
4. Review mode keeps changes by default and allows per-item override.
5. Enable single-key input for menu prompts and review yes/no prompts (no Enter required), with line-input fallback.
6. Keep anti-pattern messaging conditional:
   - warn only when anti-patterns are detected
   - otherwise remain silent
7. Use color only when appropriate:
   - auto-enable on TTY
   - disable with `NO_COLOR`

## Consequences

- Lower interaction cost in the common path.
- Clearer action semantics and fewer accidental choices.
- Slightly more terminal handling complexity due raw-mode key reads on POSIX.
- Windows and non-TTY behavior safely falls back to line-based prompts.

## References

- CLIG: https://clig.dev/
- USWDS modal/button clarity guidance: https://designsystem.digital.gov/components/modal/
- Canonical vs non-canonical terminal mode: https://www.gnu.org/software/libc/manual/html_node/Canonical-or-Not.html
- NO_COLOR convention: https://no-color.org/


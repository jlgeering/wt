# ADR: Replace `--porcelain` Flags With Internal Machine Commands

- Status: Accepted
- Date: 2026-02-24
- Decision Makers: wt maintainers

## Context

`wt` used `--porcelain` flags on public commands (`wt list` and `wt new|add`) for machine-readable output. In practice, those machine modes are consumed by `wt shell-init` wrappers, not intended as public user-facing interfaces.

Keeping machine contracts on public commands blurs UX boundaries, adds parser/handler branching to user commands, and makes completions/help more confusing.

## Decision

1. Remove `--porcelain` from public command surfaces.
2. Introduce internal machine commands:
   - `wt __list` for tab-separated listing rows
   - `wt __new <branch> [base]` for stdout path output
3. Keep `wt list` and `wt new|add` human-oriented only.
4. Update shell-init wrappers and completions to use `__list` / `__new`.
5. Treat `__*` commands as internal contracts for first-party wrappers.

## Consequences

- Public CLI help and completion are cleaner.
- Machine behavior remains available for wrappers without exposing `--porcelain` in user commands.
- Existing direct `--porcelain` callers break and must switch to internal commands.
- Internal command contracts now need integration-test coverage because wrappers depend on them.

## References

- /Users/jlg/src/wt/docs/specs/command-reference.md
- /Users/jlg/src/wt/docs/guides/shell-integration.md
- /Users/jlg/src/wt/docs/adr/2026-02-20-wt-new-output-modes.md
- /Users/jlg/src/wt/docs/adr/2026-02-23-wt-list-porcelain-mode.md

# Agent Usage Guidance (`AGENTS.md` / `CLAUDE.md`)

Keep agent instructions about `wt` short and stable. Do not duplicate command details, flags, or workflows in agent policy files.

Recommended pattern:

- Tell agents to use `wt` for worktree operations.
- Tell agents to discover current usage at runtime via `--help`.
- Prefer `mise x -- wt ...` in repos that enforce mise-managed tooling.
- Keep only durable policy in `AGENTS.md`/`CLAUDE.md`; let CLI help text be the source of truth as `wt` evolves.

For reusable prompt templates and pause/resume workflow phrasing, see:

- [`agent-workflow-prompts.md`](agent-workflow-prompts.md)

Example snippet to place in `AGENTS.md` or `CLAUDE.md`:

```md
## Worktrees

Use `wt` for worktree management.

- Discover commands with `mise x -- wt --help`.
```

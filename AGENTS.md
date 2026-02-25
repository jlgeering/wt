# AGENTS.md

## Issue Tracking

Use `br` for tracking work.

Terminology:
- `bead`, `task`, and `issue` mean the same thing in this repo.
- You may also see `ticket` or `work item` used with the same meaning.

Always run direct `br` commands through mise so agents use the mise-managed toolchain instead of global/system binaries:

- `mise x -- br ready`
- `mise x -- br list --status=open`
- `mise x -- br show <id>`
- `mise x -- br create --title="..." --description="..." --type=task --priority=2`
- `mise x -- br update <id> --claim`
- `mise x -- br close <id> --reason="Completed"`
- `mise x -- br sync --flush-only`

## Tooling Policy

We use mise for tool versions, task execution, and environment setup.

- Use `mise run <task>` for repo tasks.
- Use `mise x -- <tool> ...` for direct tool invocations.
- Do not rely on globally installed tools when a mise-managed equivalent exists.

## ADRs

Propose a new ADR in `docs/adr` for meaningful user-facing behavior/default changes, cross-platform tradeoffs, or policy decisions.

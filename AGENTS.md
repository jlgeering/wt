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

## Workflow Conventions

Use this default delivery loop unless the user asks otherwise:

1. Pick the next ready bead (`mise x -- br ready`).
2. Claim it (`mise x -- br update <id> --claim`).
3. Implement and validate changes.
4. Update the bead status/details as needed.
5. Close it when done (`mise x -- br close <id> --reason="Completed"`).
6. Sync tracker state (`mise x -- br sync --flush-only`).
7. Commit immediately for that bead (one commit per finished bead).
8. Repeat with the next ready bead.

When a completed bead uncovers new scoped work, create follow-up beads before moving on.

For long sessions, keep progress resumable:

- Keep one active bead at a time.
- After each completed bead: close, sync, commit, then move to next.
- If pausing mid-bead, checkpoint progress in the bead notes with:
  - what is done
  - what remains
  - exact next command/step
  - validation status
  - files touched
  - current branch and latest commit SHA

When starting a new session:

1. Check in-progress beads (`mise x -- br list --status=in_progress`).
2. Open the active bead (`mise x -- br show <id>`).
3. Resume from checkpoint notes before doing new work.

### Shorthand: "wrap it up"

If the user says "wrap it up", interpret it as:

1. Update the current bead (status/notes).
2. Create any necessary follow-up beads.
3. Export/flush tracker updates (`mise x -- br sync --flush-only`).
4. Commit the completed work.
5. If working on a non-`main` branch, rebase on `main` when appropriate and safe.

### Shorthand: "checkpoint"

If the user says "checkpoint", interpret it as:

1. Update current bead notes with a resume-ready handoff.
2. Sync/export tracker updates.
3. Report the exact next step for the next session.

### Shorthand: "resume"

If the user says "resume", interpret it as:

1. Find the active in-progress bead.
2. Read checkpoint notes and last commit context.
3. Continue from the documented next step.

## Tooling Policy

We use mise for tool versions, task execution, and environment setup.

- Use `mise run <task>` for repo tasks.
- Use `mise x -- <tool> ...` for direct tool invocations.
- Do not rely on globally installed tools when a mise-managed equivalent exists.

## ADRs

Propose a new ADR in `docs/adr` for meaningful user-facing behavior/default changes, cross-platform tradeoffs, or policy decisions.

## Release Process

Canonical release process: `docs/guides/release-process.md`.

# AGENTS.md

## What This Repo Is

`wt` is an experimental Zig CLI for managing Git worktrees. It helps users create, list, remove, and initialize worktrees with consistent naming and optional setup automation.

Treat `AGENTS.md` as bootstrap and policy, not as the canonical source for CLI details. Command flags, output contracts, and evolving behavior belong in the CLI help and specs.

## Start Here

When entering this repo cold, read these first:

1. [`README.md`](README.md) for quick usage, contributor workflow, and local development commands.
2. [`docs/specs/command-reference.md`](docs/specs/command-reference.md) for normative command behavior and output contracts.
3. [`docs/specs/init-and-config.md`](docs/specs/init-and-config.md) for `wt init` and config semantics.
4. [`docs/README.md`](docs/README.md) for the documentation map.
5. [`mise.toml`](mise.toml) for the source of truth on local tasks and tool versions.

For live command discovery, prefer `mise x -- wt --help` or `wt <command> --help` instead of copying command details into policy docs.

## Repo Map

- `src/commands/`: CLI command entrypoints
- `src/lib/`: shared worktree, git, config, formatting, shell-init, and UI logic
- `src/tools/`: internal maintainer tooling
- `test/`: integration tests, fixtures, and helpers
- `docs/specs/`: normative behavior and contract docs
- `docs/guides/`: contributor and maintainer runbooks
- `docs/adr/`: architecture and policy decisions
- `plans/`: active planning artifacts
- `archive/`: completed or superseded plans and explorations

## Working Norms

- Use `mise` for toolchain and task execution.
- Prefer `mise run build`, `mise run test`, `mise run lint`, or `mise run check` for validation.
- Prefer `mise x -- <tool> ...` for direct tool use when the repo manages that tool with `mise`.
- Follow existing Zig patterns before introducing new structure.
- Propose an ADR in `docs/adr` for meaningful user-facing default changes, policy decisions, or cross-platform tradeoffs.

## Docs Contract

Keep this file short and stable.

- `AGENTS.md`: bootstrap, repo-specific policy, and durable working conventions
- CLI help: current command surface and flags
- `docs/specs/`: normative behavior and output semantics
- `docs/guides/`: operational workflows and maintenance instructions

If a detail is likely to drift as the CLI evolves, do not duplicate it here.

## Work Tracking

Tracked work in this repo uses `br`. Run `br` through `mise x -- br ...`, not a global binary.

Default loop for tracked work:

1. Pick the next ready bead.
2. Claim it.
3. Implement and validate changes.
4. Update the bead status or notes as needed.
5. Close it when done.
6. Sync tracker state.
7. Commit immediately for that bead.

Keep one active bead at a time. If you pause mid-bead, leave resume-ready notes with what is done, what remains, files touched, validation status, the exact next step, and the current branch and commit.

Session shorthands:

- `resume`: find the active in-progress bead, read its notes, and continue from the documented next step.
- `checkpoint`: update the current bead with a resume-ready handoff, sync tracker state, and report the next step.
- `wrap it up`: update the current bead, create follow-up beads if needed, sync tracker state, commit finished work, and rebase on `main` when appropriate and safe.

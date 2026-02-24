# wt

`wt` is a Git worktree manager written in Zig.

It helps you create, list, and remove worktrees with consistent naming and optional per-repo setup automation.

## Disclaimer

`wt` is a vibe-coded project and remains experimental. It is actively used, but rough edges and breaking behavior changes are expected.

## Prerequisites

- `git` on `PATH`
- [`mise`](https://mise.jdx.dev/) on `PATH`

`mise` installs and pins Zig from `mise.toml`.

## Install (Recommended)

```bash
git clone <repo-url> wt
cd wt
mise install
mise run install
wt --help
```

Ensure `~/.local/bin` is on your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Quick Start

```bash
wt list
wt new demo-branch
wt rm demo-branch
```

## Shell Support

- `zsh`: primary shell, regularly tested (recommended)
- `bash`: supported, but less frequently tested
- other shells: may work, but are not regularly tested

## Shell Integration

Example (`zsh`):

```bash
if command -v wt >/dev/null 2>&1; then
  eval "$(wt shell-init zsh)"
fi
```

## Core Commands

```bash
wt list [--porcelain]
wt new|add [--porcelain] <branch> [base]
wt rm [branch] [-f|--force] [--picker auto|builtin|fzf] [--no-interactive]
wt init
wt --version
wt shell-init <shell>
```

## Worktree Naming

- Main repo path: `/path/to/repo`
- New worktree path for branch `feat-x`: `/path/to/repo--feat-x`
- Branch names with `/` are percent-encoded to keep paths flat: `feat/auth` -> `/path/to/repo--feat%2Fauth`

## Contributor Workflow

Use `mise` tasks for local development:

```bash
mise install
mise x -- zig version
mise run build
mise run test
mise run lint
mise run format
mise run check
mise run run -- --help
mise run build:release
mise run build:all
mise run clean
```

## Documentation

- Canonical docs index: `docs/README.md`
- Specs (normative behavior/contracts): `docs/specs/README.md`
- Guides (how-to/runbooks): `docs/guides/README.md`
- Decisions (ADRs): `docs/adr/README.md`
- Shell integration and troubleshooting: `docs/guides/shell-integration.md`, `docs/guides/troubleshooting.md`
- Release/distribution findings: `docs/guides/release-distribution.md`

## For Agents

Agent-specific policy lives in `AGENTS.md`.

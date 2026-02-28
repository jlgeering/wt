# wt

`wt` is a Git worktree manager written in Zig.

It helps you create, list, and remove worktrees with consistent naming and optional per-repo setup automation.

## Disclaimer

`wt` is a vibe-coded project and remains experimental. It is actively used, but rough edges and breaking behavior changes are expected.

## Prerequisites

- `git` on `PATH`
- [`mise`](https://mise.jdx.dev/) on `PATH`

## Install (Recommended)

```bash
mise use -g github:jlgeering/wt@latest
wt --version
```

## Install (Project-Local Pin)

```bash
mise use github:jlgeering/wt@latest
mise install
wt --version
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
- `fish`: supported, but less frequently tested
- `nu` (`nushell` accepted by `shell-init`): supported
- other shells: may work, but are not regularly tested

## Shell Integration

Examples:

```bash
if command -v wt >/dev/null 2>&1; then
  eval "$(wt shell-init zsh)"
fi
```

```fish
if type -q wt
  wt shell-init fish | source
end
```

Example (`nushell`):

```nu
if (which wt | is-not-empty) {
  wt shell-init nu | save -f ~/.config/nushell/wt.nu
  source ~/.config/nushell/wt.nu
}
```

## Core Commands

```bash
wt list|ls
wt new|add <branch> [base]
wt rm [branch] [-f|--force] [--picker auto|builtin|fzf] [--no-interactive]
wt init
wt --version
wt shell-init <shell>
```

Supported shell targets for `shell-init`: `zsh`, `bash`, `fish`, and `nu` (alias: `nushell`).

Detailed command contracts and output schemas:
- `docs/specs/command-reference.md`
- `docs/specs/init-and-config.md`

## Worktree Naming

- Main repo path: `/path/to/repo`
- New worktree path for branch `feat-x`: `/path/to/repo--feat-x`
- Branch names with `/` are percent-encoded to keep paths flat: `feat/auth` -> `/path/to/repo--feat%2Fauth`

## Development Install (From Source)

Use this path if you are contributing to `wt` itself:

```bash
git clone <repo-url> wt
cd wt
mise install
mise run install
wt --version
```

## Contributor Workflow

Use `mise` tasks for common local development actions:

```bash
mise install
mise run build
mise run test
mise run lint
mise run format
mise run check
mise run build:release
mise run build:all
mise run clean
```

For interactive shell usage, run Zig directly:

```bash
zig version
zig build run -- --help
```

Run a filtered subset of tests while preserving `build.zig` module wiring:

```bash
zig build test -- --test-filter "integration: PTY no-arg shell-init picker cancel works"
zig build test -Dtest_filter="release tool: semver validation"
```

## Documentation

- Canonical docs index: `docs/README.md`
- Specs (normative behavior/contracts): `docs/specs/README.md`
- Guides (how-to/runbooks): `docs/guides/README.md`
- Decisions (ADRs): `docs/adr/README.md`
- Shell integration and troubleshooting: `docs/guides/shell-integration.md`, `docs/guides/troubleshooting.md`
- Maintainer release runbook: `docs/guides/release-process.md`
- Release/distribution findings: `docs/guides/release-distribution.md`
- Agent workflows and prompts: `docs/guides/agent-workflow-prompts.md`

## For Agents

- Agent-specific policy and conventions: `AGENTS.md`
- Prompt cookbook for long sessions and restart handoffs: `docs/guides/agent-workflow-prompts.md`

## License

Licensed under the Apache License, Version 2.0. See `LICENSE`.

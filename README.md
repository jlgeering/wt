# wt

`wt` is a Git worktree manager written in Zig.

It helps you create, list, and remove worktrees with consistent naming and optional per-repo setup automation.

## Disclaimer

`wt` is a vibe-coded project and remains experimental. It is actively used, but rough edges and breaking behavior changes are expected.

## Worktree Naming

- Main repo path: `/path/to/repo`
- New worktree path for branch `feat-x`: `/path/to/repo--feat-x`
- Branch names with `/` are percent-encoded to keep paths flat:
  - `feat/auth` -> `/path/to/repo--feat%2Fauth`

## Prerequisites

- `git` on `PATH`
- Zig `0.15.x` (`build.zig.zon` sets `minimum_zig_version = "0.15.0"`)

## Install From Source

```bash
git clone <repo-url> wt
cd wt
zig build -Doptimize=ReleaseSafe
mkdir -p ~/.local/bin
cp zig-out/bin/wt ~/.local/bin/wt
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

## Development Workflow

`mise` is optional for install-from-source users, but recommended for contributors because it pins the toolchain:

```bash
mise install
mise exec -- zig version
```

Expected Zig version: `0.15.x` (for example, `0.15.2`).

Common tasks:

```bash
mise run build
mise run test
mise run install
mise run run -- --help
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

Detailed command contracts and output schemas:
- `docs/specs/command-reference.md`
- `docs/specs/init-and-config.md`

## Shell Integration

Example (`zsh`):

```bash
if command -v wt >/dev/null 2>&1; then
  eval "$(wt shell-init zsh)"
fi
```

This zsh integration also registers minimal completion for commands and positionals (branch/base/shell), with no flag suggestions.

Full setup and behavior:
- `docs/guides/shell-integration.md`
- `docs/guides/troubleshooting.md`

Note: `wt shell-init bash` also enables Bash tab completion for `wt`.

## Documentation Map

- Active work-in-progress plans: `plans/README.md`
- Canonical docs index: `docs/README.md`
- Specs (normative behavior/contracts): `docs/specs/README.md`
- Guides (how-to/runbooks): `docs/guides/README.md`
- Decisions (ADRs): `docs/adr/README.md`
- Archived completed/superseded plans: `archive/plans/README.md`
- Archived explorations/prototypes: `archive/explorations/README.md`

## Agent Policy

Keep `AGENTS.md`/`CLAUDE.md` concise and durable:

- Use `wt` for worktree operations.
- Discover current usage via `mise x -- wt --help`.
- Keep command specifics in docs/specs, not in agent policy files.

## Testing

```bash
zig build test
```

Or:

```bash
mise run test
```

## Release Distribution Planning

Release/distribution findings: `docs/guides/release-distribution.md`.

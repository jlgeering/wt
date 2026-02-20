# wt

## wt overview

`wt` is a Git worktree manager written in Zig. It helps you create, list, and remove worktrees with consistent naming and optional per-repo setup automation.

Worktree naming convention:

- Main repo path: `/path/to/repo`
- New worktree path for branch `feat-x`: `/path/to/repo--feat-x`
- Branch names with `/` are percent-encoded to keep paths flat:
  - Branch `feat/auth` -> `/path/to/repo--feat%2Fauth`

## Prerequisites

- `git` must be installed and available on `PATH`.
- `zig` `0.14.x` is required (`build.zig.zon` sets `minimum_zig_version = "0.14.0"`).
- Zig `0.15.x` is not compatible with this repo and fails with build API errors (for example, `no field named 'root_source_file'`).

## Installation from source

Clone, build, and install to `~/.local/bin`:

```bash
git clone <repo-url> wt
cd wt
zig build -Doptimize=ReleaseSafe
mkdir -p ~/.local/bin
cp zig-out/bin/wt ~/.local/bin/wt
wt --help
```

Make sure `~/.local/bin` is on your `PATH`. For zsh, add this to `~/.zshrc` if needed:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Build and development workflow

`mise` is optional for users installing from source, but recommended for contributors because it pins a compatible Zig toolchain.

```bash
mise install
mise exec -- zig version
```

Expected version is `0.14.x` (for example, `0.14.1`).

Common project tasks:

```bash
mise run build
mise run test
mise run install
mise run run -- --help
```

## Shell integration (zsh)

Add the integration function to your `~/.zshrc`:

```bash
eval "$(wt shell-init zsh)"
```

Reload your shell:

```bash
source ~/.zshrc
```

Behavior:

- The wrapper intercepts `wt new ...`.
- It captures `wt new` stdout (the created worktree path).
- If `wt new` exits successfully and the output is an existing directory, it runs `cd "$output"`.
- All other subcommands are passed through unchanged via `command wt "$@"`.

Quick verification:

```bash
wt new demo-branch
pwd
```

After `wt new demo-branch`, `pwd` should show the new worktree directory.

## Core command usage

```bash
wt list
wt new <branch> [base]
wt rm [branch] [-f|--force] [--picker auto|builtin|fzf] [--no-interactive]
wt --version
wt shell-init <shell>
```

Supported shells for `shell-init` are `zsh` and `bash`. This README documents zsh integration as the primary workflow.

### `wt rm` interaction model

- `wt rm <branch>` removes the named worktree (existing behavior).
- `wt rm` (no branch) opens an interactive picker in a TTY:
  - when exactly one secondary worktree exists, `wt` shows a direct confirmation prompt instead of a picker
  - default backend is `--picker auto` (`fzf` when available, otherwise built-in picker)
  - explicit backends: `--picker builtin` or `--picker fzf`
  - canceling picker selection exits successfully without removing anything
- non-interactive sessions (`pipe`, CI, or `--no-interactive`) require a branch argument:
  - use `wt list` to inspect worktrees
  - then remove with `wt rm <branch>`

## .wt.toml setup config

`wt` looks for `.wt.toml` in the main repo root. If the file is missing, `wt new` still works (setup is skipped).

Example:

```toml
[copy]
paths = ["deps", ".claude/settings.local.json"]

[symlink]
paths = ["mise.local.toml"]

[run]
commands = ["mise trust"]
```

Setup semantics:

- `[copy].paths`: copy paths from main repo to the new worktree (copy-on-write where available).
- `[symlink].paths`: create symlinks in the new worktree pointing back to files in the main repo.
- `[run].commands`: run shell commands in the new worktree after creation.
- Missing source paths are skipped with warnings.
- Existing destination paths are skipped with warnings.
- Failed run commands warn and continue to the next command.

## Troubleshooting

- Build fails with `root_source_file`/build API errors:
  - You are likely using Zig `0.15.x`. Switch to Zig `0.14.x`.
- `wt: command not found` after install:
  - Ensure `~/.local/bin` is on your `PATH`, then restart your shell.
- zsh integration does not change directory after `wt new`:
  - Run `type wt` and confirm `wt` is a shell function.
  - Re-run `source ~/.zshrc`.
  - Confirm your function includes `eval "$(wt shell-init zsh)"`.
- `wt rm --picker fzf` fails with picker unavailable:
  - Install `fzf`, or run `wt rm --picker builtin`.

## Testing

Run tests:

```bash
zig build test
```

Or with `mise`:

```bash
mise run test
```

Optional smoke test in a Git repo:

```bash
wt list
wt new test-branch
wt rm test-branch
```

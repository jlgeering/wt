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

Make sure `~/.local/bin` is on your `PATH`. For zsh or bash, add this to your startup file (`~/.zshrc` or `~/.bashrc`) if needed:

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

## Agent docs best practices (`AGENTS.md` / `CLAUDE.md`)

Keep agent instructions about `wt` short and stable. Do not duplicate command details, flags, or workflows in agent policy files.

Recommended pattern:

- Tell agents to use `wt` for worktree operations.
- Tell agents to discover current usage at runtime via `--help`.
- Prefer `mise x -- wt ...` in repos that enforce mise-managed tooling.
- Keep only durable policy in `AGENTS.md`/`CLAUDE.md`; let CLI help text be the source of truth as `wt` evolves.

Example snippet to place in `AGENTS.md` or `CLAUDE.md`:

```md
## Worktrees

Use `wt` for worktree management.

- Discover commands with `mise x -- wt --help`.
- Before running a subcommand, check `mise x -- wt <subcommand> --help`.
- Do not hardcode `wt` flags or flows here; rely on CLI help so instructions stay current.
```

## Shell integration (zsh and bash)

### zsh

Add the integration function to your `~/.zshrc`:

```bash
if command -v wt >/dev/null 2>&1; then
  eval "$(wt shell-init zsh)"
fi
```

Reload your shell:

```bash
source ~/.zshrc
```

### bash

Add the integration function to your `~/.bashrc`:

```bash
if command -v wt >/dev/null 2>&1; then
  eval "$(wt shell-init bash)"
fi
```

Reload your shell:

```bash
source ~/.bashrc
```

Behavior:

- Running `wt` with no arguments opens a worktree picker and changes directory to the selected worktree.
- Picker backend for no-arg `wt` mirrors `wt rm --picker auto`: use `fzf` when available, otherwise use a built-in numbered prompt.
- When only one worktree exists, no picker is shown; the wrapper prints a notice and returns without changing directories.
- The wrapper intercepts `wt new ...` and `wt add ...`.
- It calls `wt <new|add> --porcelain ...` and captures stdout (the created worktree path).
- If `wt new`/`wt add` exits successfully and the output is an existing directory, it runs `cd "$output"`.
- After changing directories, it prints `Entered worktree: <path>`.
- All other subcommands are passed through unchanged via `command wt "$@"`.

Notes:

- The wrapper function is intentionally named `wt`, the same as the binary.
- Inside the function, `command wt` bypasses the function and invokes the real binary.

Quick verification:

```bash
wt new demo-branch
pwd
wt
pwd
```

After `wt new demo-branch`, `pwd` should show the new worktree directory.

## Core command usage

```bash
wt list
wt new|add [--porcelain] <branch> [base]  # add is an alias of new
wt rm [branch] [-f|--force] [--picker auto|builtin|fzf] [--no-interactive]
wt init
wt --version
wt shell-init <shell>
```

Supported shells for `shell-init` are `zsh` and `bash`. This README includes setup steps for both shells.

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

`wt new` output modes:

- Default mode (human): prints status messages to stderr and does not print the raw path on stdout.
- `--porcelain` mode (machine): prints exactly the worktree path to stdout.

## Guided config bootstrap (`wt init`)

`wt init` creates `.wt.toml` if missing and can be run repeatedly to upgrade an existing config with current recommendations.

Behavior:

- Scans the repo for common local files and builds a full proposal for `copy`, `symlink`, and `run` entries.
- Keeps already-matching recommendations automatically on re-runs.
- Includes anti-pattern cleanup removals in the proposal.
- Shows anti-pattern warnings only when anti-patterns are actually detected.
- Shows one change summary and prompts `Apply changes? [Y/n]` (`Enter` applies all).
- If you answer `n`, a follow-up offers explicit actions:
  `e` to edit proposals one by one, or `q` to quit without writing.
- `Esc` or Ctrl-C on the top-level decision screens quits without writing.
- In review mode, each proposed change defaults to keep (`Enter` or `y`), and `n` skips.
- Uses color when stdout is a TTY; set `NO_COLOR=1` to disable.
- If `.wt.toml` already exists, writes a timestamped backup before updating.

Built-in recommendation patterns currently include:

- `mise.local.toml`, `.mise.local.toml`, and other `mise*local*.toml` variants
- `.claude/settings.local.json`
- `.env.local` and `.env.*.local`
- `.vscode/settings.local.json`
- `.envrc` (symlink recommendation)

Built-in command recommendations currently include:

- `mise trust` (when mise config is detected and the current repo directory is already trusted)
- `direnv allow` (when `.envrc` is detected)

Built-in anti-pattern checks include:

- paths present in both `[copy].paths` and `[symlink].paths`
- discouraged copy targets: `.git`, `.beads`, `node_modules`, `.zig-cache`, `zig-out`
- destructive run commands such as `rm -rf` and `git reset --hard`

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
- zsh/bash integration does not change directory after `wt new`:
  - Run `type wt` and confirm `wt` is a shell function.
  - Re-run `source ~/.zshrc` (zsh) or `source ~/.bashrc` (bash).
  - Confirm your startup file includes the guarded `if command -v wt ...; then eval "$(wt shell-init <shell>)"; fi` snippet.
- `wt rm --picker fzf` fails with picker unavailable:
  - Install `fzf`, or run `wt rm --picker builtin`.
- Unsure whether function or binary is running:
  - Run `type wt`.
  - If it says `wt is a function`, the wrapper is active.
  - If it says `wt is /.../wt`, you are calling the binary directly.

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

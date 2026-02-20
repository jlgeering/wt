# wt

## wt overview

`wt` is a Git worktree manager written in Zig. It helps you create, list, and remove worktrees with consistent naming and optional per-repo setup automation.

Worktree naming convention:

- Main repo path: `/path/to/repo`
- New worktree path for branch `feat-x`: `/path/to/repo--feat-x`

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
wt rm [branch] [-f|--force]
wt init
wt --version
wt shell-init <shell>
```

Supported shells for `shell-init` are `zsh` and `bash`. This README documents zsh integration as the primary workflow.

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
- zsh integration does not change directory after `wt new`:
  - Run `type wt` and confirm `wt` is a shell function.
  - Re-run `source ~/.zshrc`.
  - Confirm your function includes `eval "$(wt shell-init zsh)"`.

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

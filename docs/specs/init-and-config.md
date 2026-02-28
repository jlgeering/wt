# Guided Config Bootstrap (`wt init`)

`wt init` creates `.wt.toml` if missing and can be run repeatedly to upgrade an existing config with current recommendations.

## Behavior

- Scans both the repo root and the current repo-relative subdirectory (when invoked below root) for common local files, then builds a full proposal for `copy`, `symlink`, and `run` entries.
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

- `mise trust` (when mise config is detected in active detection scope and at least one matching scope is already trusted)
- `direnv allow` (when `.envrc` is detected)

Built-in anti-pattern checks include:

- paths present in both `[copy].paths` and `[symlink].paths`
- discouraged copy targets: `.git`, `.beads`, `node_modules`, `.zig-cache`, `zig-out`
- destructive run commands such as `rm -rf` and `git reset --hard`

## `.wt.toml` setup config

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

- `[copy].paths`: copy paths from main repo to the new worktree.
- macOS uses `cp -cR` and Linux uses `cp -R --reflink=auto` to preserve CoW/reflink behavior where available.
- Windows uses native filesystem copy APIs (no `cp` dependency).
- `[symlink].paths`: create symlinks in the new worktree pointing back to files in the main repo.
- On Windows, symlink creation can be unavailable without Developer Mode/elevated privileges; when it fails, setup logs `symlink failed for <path>` and continues.
- `[run].commands`: run shell commands in the new worktree after creation.
- Command runner is platform-specific: `sh -c` on non-Windows, `cmd.exe /C` on Windows.
- Run command strings must be valid for the host shell (`sh` syntax on Unix-like systems, `cmd.exe` syntax on Windows).
- Missing source paths are skipped with `skip copy ...: source doesn't exist` or `skip symlink ...: source doesn't exist`.
- Existing destination paths are skipped with `skip copy ...: already exists` or `skip symlink ...: already exists`.
- Failed run commands warn and continue to the next command.

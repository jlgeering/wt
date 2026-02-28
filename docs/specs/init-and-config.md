# Guided Config Bootstrap (`wt init`)

`wt init` creates `.wt.toml` if missing and can be run repeatedly to upgrade an existing config with current recommendations.

## Behavior

- Scans from the repo root with a bounded subproject discovery pass, then builds one repo-wide proposal for `copy`, `symlink`, and `run` entries regardless of the current working directory.
- Default subproject scan depth is 2 levels below repo root (configurable internally; no CLI flag yet).
- Subproject discovery respects `.gitignore`/standard Git excludes and skips hidden subproject roots.
- Within discovered roots, local setup files can still be detected even when those specific files are ignored (for example `**/.claude/settings.local.json`).
- Keeps already-matching recommendations automatically on re-runs.
- Includes anti-pattern cleanup removals in the proposal.
- Shows anti-pattern warnings only when anti-patterns are actually detected.
- Shows one change summary and prompts `Apply changes? [Y/n]` (`Enter` applies all).
- If you answer `n`, a follow-up offers explicit actions:
  `e` to edit proposals one by one, or `q` to quit without writing.
- `Esc` or Ctrl-C on top-level decision screens and review-mode yes/no prompts quits without writing.
- In review mode, each proposed change defaults to keep (`Enter` or `y`), and `n` skips.
- Uses color when stdout is a TTY; set `NO_COLOR=1` to disable.
- If `.wt.toml` already exists, writes a timestamped backup before updating.

Built-in recommendation patterns currently include:

- symlink recommendations:
  - `mise.local.toml`, `.mise.local.toml`, and other `mise*local*.toml` variants
  - `.claude/settings.local.json`
  - `.envrc`
- copy recommendations:
  - `.env.local` and `.env.*.local`
  - `.vscode/settings.local.json`
  - `deps` and `_build` when `mix.exs` is detected at repo root or discovered subproject roots

Built-in command recommendations currently include:

- `mise trust` (when mise config is detected in active detection scope and matching scope is already trusted)
- `direnv allow` (when `.envrc` is detected)
- For subproject-scoped command recommendations, `wt init` writes repo-root-relative prefixed commands such as `cd apps/api && mise trust`.

Built-in anti-pattern checks include:

- paths present in both `[copy].paths` and `[symlink].paths`
- discouraged copy targets: `.git`, `.beads`, `node_modules`, `.zig-cache`, `zig-out`
- destructive run commands such as `rm -rf` and `git reset --hard`

## `.wt.toml` setup config

`wt` looks for `.wt.toml` in the main repo root. If the file is missing, `wt new` still works (setup is skipped).

Example:

```toml
[copy]
paths = ["deps"]

[symlink]
paths = [".claude/settings.local.json", "mise.local.toml"]

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

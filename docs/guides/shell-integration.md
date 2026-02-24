# Shell Integration (zsh and bash)

## zsh

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

## bash

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

## Behavior

- Running `wt` with no arguments opens a worktree picker.
- Before picker selection, it captures the current repo-relative subdirectory via `git rev-parse --show-prefix`.
- After selection:
  - it prefers `cd "<selected-worktree>/<relative-subdir>"` when that path exists.
  - if the subdirectory is missing in the selected worktree, it prints a note and falls back to `cd "<selected-worktree>"`.
  - after changing directories, it prints a short summary block with a blank leading line:
    - `Entered worktree: <worktree-root>`
    - optional `Subdirectory: <relative-subdir>`
- Picker rows include branch, status, and path.
- Picker backend for no-arg `wt` mirrors `wt rm --picker auto`: use `fzf` when available, otherwise use a built-in numbered prompt.
- When only one worktree exists, no picker is shown; the wrapper prints a notice and returns without changing directories.
- The wrapper intercepts `wt new ...` and `wt add ...`.
- It calls `wt <new|add> --porcelain ...` and captures stdout (the created worktree path).
- Before creation, it captures the current repo-relative subdirectory via `git rev-parse --show-prefix`.
- If `wt new`/`wt add` exits successfully and the output is an existing directory:
  - it prefers `cd "$output/<relative-subdir>"` when that path exists.
  - if the subdirectory is missing in the new worktree, it prints a note and falls back to `cd "$output"`.
- After changing directories, it prints the same summary block (`Entered worktree` and optional `Subdirectory`).
- All other subcommands are passed through unchanged via `command wt "$@"`.

## Notes

- The wrapper function is intentionally named `wt`, the same as the binary.
- Inside the function, `command wt` bypasses the function and invokes the real binary.

## Quick verification

```bash
mkdir -p demo/subdir
cd demo/subdir
wt new demo-branch
pwd
wt
pwd
```

After `wt new demo-branch`, `pwd` should show the same relative subdirectory in the new worktree when present; otherwise it should show the new worktree root.  
After running bare `wt` from that subdirectory and selecting another worktree, it should preserve the same relative subdirectory when present, otherwise land at that selected worktree root.

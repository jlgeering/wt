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

- Running `wt` with no arguments opens a worktree picker and changes directory to the selected worktree.
- Picker rows include branch, status, and path.
- Picker backend for no-arg `wt` mirrors `wt rm --picker auto`: use `fzf` when available, otherwise use a built-in numbered prompt.
- When only one worktree exists, no picker is shown; the wrapper prints a notice and returns without changing directories.
- The wrapper intercepts `wt new ...` and `wt add ...`.
- It calls `wt <new|add> --porcelain ...` and captures stdout (the created worktree path).
- If `wt new`/`wt add` exits successfully and the output is an existing directory, it runs `cd "$output"`.
- After changing directories, it prints `Entered worktree: <path>`.
- All other subcommands are passed through unchanged via `command wt "$@"`.

## Notes

- The wrapper function is intentionally named `wt`, the same as the binary.
- Inside the function, `command wt` bypasses the function and invokes the real binary.

## Quick verification

```bash
wt new demo-branch
pwd
wt
pwd
```

After `wt new demo-branch`, `pwd` should show the new worktree directory.

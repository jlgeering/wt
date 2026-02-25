# Shell Integration (zsh, bash, fish, and nushell)

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

When loaded via `wt shell-init zsh`, `wt` also registers zsh completion for:

- subcommands (`list`, `new`, `add`, `rm`, `init`, `shell-init`)
- positionals:
  - `wt new|add <branch> [base]`: git refs
  - `wt rm [branch]`: branch names from `wt __list` (excluding current worktree branch)
  - `wt shell-init <shell>`: `zsh`, `bash`, `fish`

Completion intentionally does not suggest flags.

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

## fish

Add the integration function to your `~/.config/fish/config.fish`:

```fish
if type -q wt
  wt shell-init fish | source
end
```

Reload your shell:

```fish
source ~/.config/fish/config.fish
```

When loaded via `wt shell-init fish`, `wt` also registers fish completion for:

- subcommands (`list`, `new`, `add`, `rm`, `init`, `shell-init`)
- positionals:
  - `wt new|add <branch> [base]`: git refs
  - `wt rm [branch]`: branch names from `wt __list` (excluding current worktree branch)
  - `wt shell-init <shell>`: `zsh`, `bash`, `fish`

Completion intentionally does not suggest flags.

## nushell

Generate and source the integration script from your Nushell config:

```nu
if (which wt | is-not-empty) {
  wt shell-init nu | save -f ~/.config/nushell/wt.nu
  source ~/.config/nushell/wt.nu
}
```

The `nu` integration provides:

- the same no-arg picker and `new|add` auto-`cd` behavior as zsh/bash.
- completion for subcommands and key positionals (`new|add`, `rm`, `shell-init`).
- shell aliases accepted by `shell-init`: `zsh`, `bash`, `fish`, `nu` (`nushell` is also accepted).

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
- It calls `wt __new ...` and captures stdout (the created worktree path).
- Before creation, it captures the current repo-relative subdirectory via `git rev-parse --show-prefix`.
- If `wt new`/`wt add` exits successfully and the output is an existing directory:
  - it prefers `cd "$output/<relative-subdir>"` when that path exists.
  - if the subdirectory is missing in the new worktree, it prints a note and falls back to `cd "$output"`.
- After changing directories, it prints the same summary block (`Entered worktree` and optional `Subdirectory`).
- All other subcommands are passed through unchanged to the `wt` binary (`command wt` in zsh/bash, `command wt` in fish, `^wt` in nushell).

## Notes

- The wrapper function is intentionally named `wt`, the same as the binary.
- Inside the wrapper, shell-specific bypass forms (`command wt` for zsh/bash/fish, `^wt` for nushell) invoke the real binary.
- Bash integration also installs tab completion for `wt` (subcommands, common flags, `rm --picker` values, and `shell-init` shell names).

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

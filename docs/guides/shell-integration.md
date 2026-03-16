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

- subcommands (`list`, `ls`, `new`, `add`, `rm`, `switch`, `init`, `shell-init`)
- positionals:
  - `wt new|add <branch> [base]`: git refs
  - `wt rm [branch]`: branch names from `wt __list` (excluding current worktree branch)
  - `wt switch <branch>`: branch names from `wt __list` (excluding current worktree branch)
- `wt shell-init <shell>`: `zsh`, `bash`, `fish`, `nu`, `nushell`

For the normative completion contract, including parity expectations across supported shells, see
`docs/specs/command-reference.md`.

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

- subcommands (`list`, `ls`, `new`, `add`, `rm`, `switch`, `init`, `shell-init`)
- positionals:
  - `wt new|add <branch> [base]`: git refs
  - `wt rm [branch]`: branch names from `wt __list` (excluding current worktree branch)
  - `wt switch <branch>`: branch names from `wt __list` (excluding current worktree branch)
- `wt shell-init <shell>`: `zsh`, `bash`, `fish`, `nu`, `nushell`

For the normative completion contract, including parity expectations across supported shells, see
`docs/specs/command-reference.md`.

## nushell

Generate and source the integration script from your Nushell config:

```nu
if (which wt | is-not-empty) {
  wt shell-init nu | save -f ~/.config/nushell/wt.nu
  source ~/.config/nushell/wt.nu
}
```

The `nu` integration provides:

- the same interactive no-arg picker and `new|add` auto-`cd` behavior as zsh/bash.
- completion for subcommands and key positionals (`new|add`, `rm`, `switch`, `shell-init`).
- shell aliases accepted by `shell-init`: `zsh`, `bash`, `fish`, `nu` (`nushell` is also accepted).
- interactive no-arg picker stderr handling that prefers `err> /dev/tty`, with fallback to captured stderr if that redirection fails.

For the normative completion contract, including parity expectations across supported shells, see
`docs/specs/command-reference.md`.

## Behavior

- Running `wt` with no arguments opens a worktree picker in interactive sessions.
- In non-interactive sessions, bare `wt` passes through to the real binary (no wrapper picker flow).
- In Nushell interactive sessions, the no-arg picker first runs `^wt __pick-worktree err> /dev/tty | complete` so picker stderr remains visible while stdout stays parseable.
- If Nushell `err> /dev/tty` redirection fails, it falls back to `^wt __pick-worktree | complete`, reprints captured stderr, and preserves the picker exit code in `$env.LAST_EXIT_CODE`.
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
- The wrapper also intercepts `wt switch <branch>`.
- It calls `wt __switch <branch>` and captures stdout (the target worktree path).
- Before switching, it captures the current repo-relative subdirectory via `git rev-parse --show-prefix`.
- If `wt switch` exits successfully and the output is an existing directory:
  - it prefers `cd "$output/<relative-subdir>"` when that path exists.
  - if the subdirectory is missing in the target worktree, it prints a note and falls back to `cd "$output"`.
- If `wt __switch` exits non-zero or prints no usable directory, the wrapper preserves the current working directory and propagates the exit status.
- `wt switch --help` and non-standard switch invocations pass through to the real binary unchanged.
- All other subcommands are passed through unchanged to the `wt` binary (`command wt` in zsh/bash, `command wt` in fish, `^wt` in nushell).

## Notes

- The wrapper function is intentionally named `wt`, the same as the binary.
- Inside the wrapper, shell-specific bypass forms (`command wt` for zsh/bash/fish, `^wt` for nushell) invoke the real binary.
- Completion setup details live in this guide; completion behavior contracts live in `docs/specs/command-reference.md`.

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

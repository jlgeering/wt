# ADR: Add Bash Completion to `wt shell-init bash`

- Status: Accepted
- Date: 2026-02-24
- Decision Makers: wt maintainers

## Context

`wt shell-init bash` currently defines a Bash wrapper function for navigation behavior, but it does not register tab completion.

Without completion, Bash users must manually discover subcommands and flags, and they do not get guided values for options like `--picker`.

## Decision

1. Extend the emitted Bash shell-init snippet with a completion function bound via `complete -F ... wt`.
2. Complete root subcommands and common flags.
3. Complete command-specific flags and values:
   - `rm --picker`: `auto`, `builtin`, `fzf`
   - `shell-init`: `bash`, `zsh`
4. For `wt rm`, suggest removable worktree branches by reading `wt list --porcelain`.
5. Keep completion support scoped to Bash shell-init output; zsh behavior is unchanged.

## Consequences

- Bash UX improves with discoverable command/flag/value completion.
- Completion behavior stays coupled to shell-init, so users get it automatically when they enable Bash integration.
- Shell-init output becomes larger and now contains additional completion-specific logic to maintain.

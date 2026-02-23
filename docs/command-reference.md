# Command Reference

## Core command usage

```bash
wt list [--porcelain]
wt new|add [--porcelain] <branch> [base]  # add is an alias of new
wt rm [branch] [-f|--force] [--picker auto|builtin|fzf] [--no-interactive]
wt init
wt --version
wt shell-init <shell>
```

Supported shells for `shell-init` are `zsh` and `bash`.

Use `wt <command> --help` for command details.

## `wt rm` interaction model

- `wt rm <branch>` removes the named worktree (existing behavior).
- `wt rm` (no branch) opens an interactive picker in a TTY:
  - when exactly one secondary worktree exists, `wt` shows a direct confirmation prompt instead of a picker
  - default backend is `--picker auto` (`fzf` when available, otherwise built-in picker)
  - explicit backends: `--picker builtin` or `--picker fzf`
  - canceling picker selection exits successfully without removing anything
- non-interactive sessions (`pipe`, CI, or `--no-interactive`) require a branch argument:
  - use `wt list` to inspect worktrees
  - then remove with `wt rm <branch>`

## `wt new` output modes

- Default mode (human): prints status messages to stderr and does not print the raw path on stdout.
- `--porcelain` mode (machine): prints exactly the worktree path to stdout.

## `wt list` output modes

- Default mode (human): one worktree per line with readability-focused status summary.
- `--porcelain` mode (machine): tab-separated fields per line:
  `current\tbranch\tpath\tstatus\tmodified\tuntracked\tahead\tbehind\thas_upstream`

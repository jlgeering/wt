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

Supported shells for `shell-init` are `zsh`, `bash`, and `fish`.

Use `wt <command> --help` for command details.

## Completion via shell-init

When users load `wt shell-init bash` (via `eval`), `wt` registers Bash completion for subcommands, command-specific flags/values, and relevant positional values.

When users load `wt shell-init zsh` (via `eval`) or `wt shell-init fish` (via `source`), `wt` registers completion for:

- subcommands (`list`, `new`, `add`, `rm`, `init`, `shell-init`)
- positional arguments for `new|add`, `rm`, and `shell-init`

zsh/fish completion intentionally does not suggest flags.

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

- Default mode (human): table with explicit columns:
  `CUR BRANCH WT BASE UPSTREAM PATH`
- `--porcelain` mode (machine): tab-separated fields per line:
  `current\tbranch\tpath\twt\ttracked_changes\tuntracked\tbase_ref\tbase_ahead\tbase_behind\thas_upstream\tupstream_ahead\tupstream_behind`

Column semantics (human):

- `WT`: `clean`, `dirty`, or `unknown`.
- `BASE`: divergence of this worktree branch vs main worktree branch:
  - `=` in sync
  - `↑<n>` ahead of main
  - `↓<n>` behind main
  - `↑<n>↓<n>` diverged both ways
  - `-` unavailable (for example detached or no base branch)
  - `unknown` when divergence inspection fails
- `UPSTREAM`: divergence of this worktree branch vs configured upstream, using the same symbols as `BASE` (`=` / arrows / `-` / `unknown`).

Example (`wt list` human output row with divergences):

```text
*   feat-x               dirty    ↑2      ↓1      /Users/jlg/src/wt--feat-x
```

Porcelain field semantics:

- `wt`: `clean`, `dirty`, or `unknown`.
- `tracked_changes`: tracked status-entry count (modified/deleted/renamed/etc).
- `untracked`: untracked entry count.
- `base_ref`: main worktree branch name, or `-` when unavailable.
- `base_ahead` / `base_behind`: commit counts vs `base_ref`; `-1` means unavailable/unknown.
- `has_upstream`: `1` when upstream is configured, else `0`.
- `upstream_ahead` / `upstream_behind`: commit counts vs upstream; `-1` means unavailable/unknown.

Related picker semantics:

- `wt rm` picker rows show `clean`/`dirty` and optional `local-commits` (no count).
- shell integration (`wt` with no args after `wt shell-init`) consumes `wt list --porcelain` and displays `WT`, `BASE`, and `UPSTREAM` columns.

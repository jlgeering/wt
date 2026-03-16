# Command Reference

## Core command usage

```bash
wt list|ls  # ls is an alias of list
wt new|add <branch> [base]  # add is an alias of new
wt rm [branch] [-f|--force] [--picker auto|builtin|fzf] [--no-interactive]
wt switch <branch>
wt init
wt --version
wt shell-init <shell>
```

For `wt new|add`, `<branch>` accepts either:

- a local branch name (existing or new)
- an explicit remote-qualified branch name in the form `<remote>/<branch>`

Supported shells for `shell-init` are `zsh`, `bash`, `fish`, `nu`, `nushell`.
When using `wt shell-init bash`, the emitted shell code also registers a Bash completion function for `wt`.

Use `wt <command> --help` for command details.

Internal commands reserved for shell wrappers:

```bash
wt __list
wt __new <branch> [base]
wt __switch <branch>
wt __pick-worktree
wt __complete-local-branches
wt __complete-refs
wt __complete-worktree-branches
```

## Completion via shell-init

When users load `wt shell-init`, completion is part of the supported interactive surface for `zsh`,
`bash`, `fish`, and `nu`.

Parity rule:

- supported shells should expose the same completion behavior unless a shell-specific exception is
  explicitly documented
- differences that are not documented exceptions are bugs

Completion surface required for supported shells:

- subcommands (`list`, `ls`, `new`, `add`, `rm`, `switch`, `init`, `shell-init`)
- aliases complete anywhere the canonical command name completes
- root flags: `--help`, `-h`, `--version`, `-V`
- command flags for public commands
- constrained flag values where applicable
- dynamic positional candidates for `new|add`, `rm`, `switch`, and `shell-init`
- prefix filtering for partial tokens, including dynamic candidates

Dynamic candidate contracts:

- `wt new|add <branch>`: local branch names
- `wt new|add <branch> <base>`: branch and remote refs
- `wt rm [branch]`: worktree branch names from existing named worktrees, excluding the current
  worktree branch and excluding detached entries
- `wt switch <branch>`: same candidate set as `wt rm [branch]`
- `wt shell-init <shell>`: `zsh`, `bash`, `fish`, `nu`, `nushell`

Dynamic completion invariants:

- candidates are deduplicated before presentation
- partial-token completion filters candidates by the typed prefix rather than requiring a fresh
  positional token
- internal `__*` commands are never suggested by public completion

Constrained flag-value completions:

- `wt rm --picker`: `auto`, `builtin`, `fzf`

Guide-level setup docs may describe how to install shell integration, but this section is the
normative completion contract.

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

## `wt new` output contracts

- Public command `wt new|add` (human): prints status messages to stderr and does not print the raw path on stdout.
- Internal command `wt __new <branch> [base]` (machine): prints exactly the worktree path to stdout.

## `wt new|add` branch resolution

- Bare branch names never trigger remote lookup.
- `wt new|add foo`:
  - uses existing local branch `foo` when present
  - otherwise creates a new local branch `foo` from `[base]` or `HEAD`
- `wt new|add <remote>/<branch>`:
  - is treated as a remote-branch workflow only when `<remote>` matches a configured Git remote
  - creates a local branch named `<branch>` from `<remote>/<branch>`
  - configures the local branch to track `<remote>/<branch>`
  - creates the worktree for the local branch name `<branch>`
- `BASE` is only valid for bare branch-name creation; remote-qualified creation rejects `BASE`

Error cases:

- remote-qualified creation fails when `<remote>/<branch>` does not exist as a remote-tracking ref
- remote-qualified creation fails when the derived local branch already exists
- existing worktree/path collision behavior is unchanged

## `wt switch` output contracts

- Public command `wt switch <branch>` (human): prints the matching worktree path to stdout on success; prints an error to stderr and exits non-zero when no matching worktree exists.
- Internal command `wt __switch <branch>` (machine): prints the matching worktree path to stdout on success; suppresses error messages and exits non-zero when no matching worktree exists. Used by shell wrappers.
- `wt switch` intentionally prints the path in human mode, unlike `wt new`, because lookup has no side effects to narrate and the stdout path enables direct composition such as `cd $(wt switch foo)`.
- Detached-HEAD worktrees never satisfy `wt switch <branch>` because lookup only matches named branch checkouts.
- "No worktree found" means no existing worktree reports the requested branch in `git worktree list --porcelain`; `wt switch` does not create a worktree as fallback.

## `wt list` output contracts

- Public command `wt list` (human): table with explicit columns:
  `CUR BRANCH WT BASE UPSTREAM PATH`
- Internal command `wt __list` (machine): tab-separated fields per line:
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

Machine field semantics:

- `wt`: `clean`, `dirty`, or `unknown`.
- `tracked_changes`: tracked status-entry count (modified/deleted/renamed/etc).
- `untracked`: untracked entry count.
- `base_ref`: main worktree branch name, or `-` when unavailable.
- `base_ahead` / `base_behind`: commit counts vs `base_ref`; `-1` means unavailable/unknown.
- `has_upstream`: `1` when upstream is configured, else `0`.
- `upstream_ahead` / `upstream_behind`: commit counts vs upstream; `-1` means unavailable/unknown.

Related picker semantics:

- `wt rm` picker rows show `clean`/`dirty` and optional `local-commits` (no count).
- shell integration (`wt` with no args after `wt shell-init`) consumes `wt __list` and displays `WT`, `BASE`, and `UPSTREAM` columns.

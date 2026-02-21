# wt -- Git Worktree Manager CLI

A composable CLI tool for managing git worktrees, written in Zig.

## Commands (v0.1)

### `wt list`
List all worktrees with status info (dirty/clean, ahead/behind). Current worktree marked with `*`. Output example:

```
  main           /Users/jl/src/myapp            (clean)
  feat-auth      /Users/jl/src/myapp--feat-auth  (3 modified)
* fix-bug        /Users/jl/src/myapp--fix-bug    (clean, 2 ahead)
```

### `wt new [--porcelain] <branch> [base-ref]`
Create worktree at `{repo}--{branch}` as sibling directory. If worktree already exists, skip creation. Run `.wt.toml` setup (CoW copies, symlinks, run commands). Default base-ref: HEAD.

- default mode: human-oriented status output, no raw path on stdout
- `--porcelain`: machine mode, print only the path to stdout

### `wt rm [branch]`
Remove a worktree. Without arg: list worktrees with safety status for external picker (fzf/gum). With arg: check for uncommitted changes and unmerged commits. Prompt before unsafe removal. Auto-delete branch if fully merged. `--force` to skip safety checks.

### `wt shell-init <shell>`
Output a shell function that wraps `wt new` and `wt rm` to `cd` into the result. The wrapper calls `wt new --porcelain` so it can capture only the path and then print a concise success line. Usage: `eval "$(wt shell-init zsh)"` in `.zshrc`. Supports zsh (primary), bash, fish (future).

## Config File

`.wt.toml` in repo root, checked into git. Optional -- tool works without it.

```toml
[copy]
paths = ["deps", "_build"]

[symlink]
paths = ["mise.local.toml", ".claude/settings.local.json"]

[run]
commands = ["mise trust", "mix deps.get"]
```

- **copy**: CoW copy (`cp -cR` macOS, `cp --reflink=auto` Linux, regular copy Windows). Source doesn't exist: skip with warning.
- **symlink**: Symlink back to main worktree. Target exists: skip with warning.
- **run**: Shell commands executed in order in the new worktree directory. Failed command: warn, continue remaining.

## Architecture

```
CLI Layer (yazap)  -->  Command Fns  -->  Core Lib  -->  std lib
```

### Project Layout

```
src/
  main.zig              # Entry point, yazap setup
  commands/
    list.zig
    new.zig
    rm.zig
    shell_init.zig
  lib/
    git.zig              # Run git commands, parse porcelain output
    config.zig           # Parse .wt.toml via zig-config
    worktree.zig         # Path conventions, worktree discovery
    setup.zig            # CoW copy, symlink, run post-setup commands
build.zig                # Build config, dependencies (yazap, zig-config)
.wt.toml                 # Dogfooding
```

### Dependencies

- **yazap**: Subcommand routing, arg parsing, help generation
- **zig-config**: TOML parsing for `.wt.toml`
- **Zig std lib**: Process execution, filesystem, I/O

### Key Conventions

- default mode: stderr for human-readable status/errors
- porcelain mode: stdout for machine-readable data (path output), stderr only for warnings/errors
- All git interaction via `std.process.Child.run()` with `--porcelain` where available
- Worktree naming: `{repo}--{branch}` as sibling directory, not configurable
- Zig version pinned via mise

## Testing Strategy

### Unit Tests (Zig `test` blocks)

- `config.zig`: Parse valid/invalid TOML, missing file, empty sections
- `worktree.zig`: Path computation, naming convention logic
- `git.zig`: Parse `git worktree list --porcelain` output from fixtures

### Integration Tests (`test/`)

- Create real git repos in tmp dirs (`std.testing.tmpDir`)
- Full `wt new` / `wt list` / `wt rm` flows
- Verify CoW copy, symlinks, run commands
- Verify safety checks (dirty worktree, unmerged branch)

### Test Helpers

- `test/helpers.zig`: Create throwaway git repos, commit files, create branches

Run all: `zig build test`

## Error Handling

| Situation | Behavior |
|---|---|
| `git` not on PATH | Error message, exit 1 |
| `.wt.toml` parse error | Report line/column, exit 1 |
| Branch already in another worktree | Error naming which worktree |
| `wt rm` dirty worktree | Show changed files, prompt confirmation |
| `wt rm` unmerged commits | Warn, require `--force` |
| CoW copy source missing | Skip with warning (non-fatal) |
| Symlink target exists | Skip with warning (non-fatal) |
| Run command fails | Warn, continue remaining commands |
| Not in a git repo | Error, exit 1 |

## Future Work (not in v0.1)

- `wt switch` -- cd to existing worktree (with optional fzf piping)
- `wt claude` -- launch Claude Code in a worktree
- Tmux integration (open worktree in new pane/window)
- Built-in fuzzy picker (libvaxis/ZigZag)
- bash/fish shell-init support

## ADRs

### ADR-1: Shell out to git instead of libgit2

Git CLI is stable, well-tested, and avoids a massive C dependency. Porcelain output (`--porcelain`) is designed for machine parsing. Every successful worktree tool in the ecosystem does this.

### ADR-2: mode-based output contract (`wt new` human default + `--porcelain`)

Default command use optimizes readability, while `--porcelain` keeps script integration stable and explicit. Matches Unix conventions without forcing machine output into interactive runs.

### ADR-3: yazap over zig-clap

zig-clap has limited subcommand support. yazap is modeled after Rust's clap with full nested subcommand routing and auto-generated help.

### ADR-4: .wt.toml per-repo only (no global config)

YAGNI. Global config adds layering complexity. Per-repo config is the primary use case and can be version-controlled. Straightforward to add global config later if needed.

### ADR-5: {repo}--{branch} sibling naming, not configurable

Simple, predictable, proven in existing workflow. Avoids template parsing complexity. Can be made configurable later without breaking changes.

### ADR-6: CoW copy strategy by platform

`cp -cR` (macOS APFS) and `cp --reflink=auto` (Linux btrfs/xfs) avoid duplicating large build artifacts. Falls back to regular copy transparently. No Zig API for reflinks, so we shell out to `cp`.

### ADR-7: Zig as implementation language

Experimental/learning goal. Cross-compiles to all targets trivially, tiny static binaries, built-in test framework. Accepted trade-off: pre-1.0 stdlib churn. Pin to specific Zig version via mise.

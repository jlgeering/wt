# ADR: `wt new` Output Modes

- Status: Accepted
- Date: 2026-02-20
- Decision Makers: wt maintainers

## Context

`wt new` previously emitted both:

- human status text to stderr
- raw worktree path to stdout

That made scripting possible, but interactive use showed what looked like duplicate output. It also created confusion when shell integration was not installed, because users saw both status output and the path payload.

We need a contract that is explicit for scripts, clear for humans, and compatible with same-name shell wrappers that call `command wt`.

## Decision

1. `wt new` default mode is human-oriented:
   - print status/progress for people
   - do not print a raw path payload on stdout
2. `wt new --porcelain` is machine-oriented:
   - print exactly one newline-terminated path on stdout
   - suppress non-error chatter; stderr is for warnings/errors only
3. `wt shell-init` wrappers call `wt new --porcelain` internally, then:
   - `cd` into the resulting path
   - print one concise success line
4. Keep the wrapper function name `wt` and keep passthrough via `command wt`.
5. Adopt this as a breaking behavior change in v0.x now (no transition window).

## Consequences

- Interactive output is cleaner and less confusing without the wrapper.
- Scripts and wrappers must opt into `--porcelain` explicitly, making machine contracts discoverable.
- Existing scripts that parse `wt new` stdout without `--porcelain` will break and must be updated.
- Same-name wrapper behavior remains standard shell practice, but docs must explain `type wt` and `command wt`.

## References

- CLIG output guidance: https://clig.dev/
- Git porcelain conventions: https://git-scm.com/docs/git-status
- Bash `command` builtin: https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html
- zsh precommand modifiers (`command`): https://zsh.sourceforge.io/Doc/Release/Shell-Grammar.html

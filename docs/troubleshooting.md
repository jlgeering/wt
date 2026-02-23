# Troubleshooting

- Build fails with `root_source_file`/build API errors:
  - You are likely using Zig `0.15.x`. Switch to Zig `0.14.x`.
- `wt: command not found` after install:
  - Ensure `~/.local/bin` is on your `PATH`, then restart your shell.
- zsh/bash integration does not change directory after `wt new`:
  - Run `type wt` and confirm `wt` is a shell function.
  - Re-run `source ~/.zshrc` (zsh) or `source ~/.bashrc` (bash).
  - Confirm your startup file includes the guarded `if command -v wt ...; then eval "$(wt shell-init <shell>)"; fi` snippet.
- `wt rm --picker fzf` fails with picker unavailable:
  - Install `fzf`, or run `wt rm --picker builtin`.
- Unsure whether function or binary is running:
  - Run `type wt`.
  - If it says `wt is a function`, the wrapper is active.
  - If it says `wt is /.../wt`, you are calling the binary directly.

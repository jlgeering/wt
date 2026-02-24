# Troubleshooting

- Build fails with `root_source_file`/build API errors:
  - You are likely using an older Zig release. Switch to Zig `0.15.x`.
- `wt: command not found` after install:
  - Ensure `~/.local/bin` is on your `PATH`, then restart your shell.
- zsh/bash/fish integration does not change directory after `wt new`:
  - Run `type wt` and confirm `wt` is a shell function.
  - Re-run `source ~/.zshrc` (zsh), `source ~/.bashrc` (bash), or `source ~/.config/fish/config.fish` (fish).
  - Confirm your startup file includes the correct shell-init snippet (`eval "$(wt shell-init zsh|bash)"` or `wt shell-init fish | source`).
- `wt rm --picker fzf` fails with picker unavailable:
  - Install `fzf`, or run `wt rm --picker builtin`.
- Unsure whether function or binary is running:
  - Run `type wt`.
  - If it says `wt is a function`, the wrapper is active.
  - If it says `wt is /.../wt`, you are calling the binary directly.

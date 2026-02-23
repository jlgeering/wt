const std = @import("std");

const zsh_init =
    \\# wt shell integration
    \\# Add to .zshrc: eval "$(wt shell-init zsh)"
    \\
    \\wt() {
    \\    if [ "$#" -gt 0 ] && [ "${1#-}" != "$1" ]; then
    \\        command wt "$@"
    \\        return $?
    \\    fi
    \\
    \\    if [ "$#" -eq 0 ]; then
    \\        local worktrees
    \\        worktrees=$(command wt list --porcelain 2>/dev/null)
    \\        local list_exit=$?
    \\        if [ $list_exit -ne 0 ] || [ -z "$worktrees" ]; then
    \\            command wt "$@"
    \\            return $?
    \\        fi
    \\
    \\        local count
    \\        count=$(printf '%s\n' "$worktrees" | awk 'END { print NR }')
    \\        if [ -z "$count" ] || [ "$count" -eq 0 ]; then
    \\            return 0
    \\        fi
    \\        if [ "$count" -eq 1 ]; then
    \\            local only_branch
    \\            local only_path
    \\            only_branch=$(printf '%s\n' "$worktrees" | cut -f2)
    \\            only_path=$(printf '%s\n' "$worktrees" | cut -f3)
    \\            echo "Only one worktree is available: ${only_branch} (${only_path}). Staying in the current directory."
    \\            return 0
    \\        fi
    \\
    \\        local picker_rows
    \\        picker_rows=$(printf '%s\n' "$worktrees" | awk -F '\t' '
    \\            NF < 9 { next }
    \\            {
    \\                branch = $2
    \\                path = $3
    \\                state = $4
    \\                modified = $5 + 0
    \\                untracked = $6 + 0
    \\                ahead = $7 + 0
    \\                behind = $8 + 0
    \\
    \\                summary = state
    \\                if (state == "dirty") {
    \\                    summary = ""
    \\                    if (modified > 0) {
    \\                        summary = sprintf("M:%d", modified)
    \\                    }
    \\                    if (untracked > 0) {
    \\                        if (length(summary) > 0) {
    \\                            summary = sprintf("%s U:%d", summary, untracked)
    \\                        } else {
    \\                            summary = sprintf("U:%d", untracked)
    \\                        }
    \\                    }
    \\                    if (length(summary) == 0) {
    \\                        summary = "changes"
    \\                    }
    \\                }
    \\                if (ahead > 0) {
    \\                    summary = sprintf("%s ^%d", summary, ahead)
    \\                }
    \\                if (behind > 0) {
    \\                    summary = sprintf("%s v%d", summary, behind)
    \\                }
    \\
    \\                printf "%s\t%-20s  %-20s  %s\n", path, branch, summary, path
    \\            }
    \\        ')
    \\
    \\        local selected_path=""
    \\        if command -v fzf >/dev/null 2>&1; then
    \\            selected_path=$(printf '%s\n' "$picker_rows" | fzf --no-color --prompt "Worktree > " --height 40% --reverse --no-multi --delimiter $'\t' --with-nth 2 --header "BRANCH                STATUS               PATH" | cut -f1)
    \\        else
    \\            echo "Choose a worktree:"
    \\            printf '%s\n' "$picker_rows" | awk -F '\t' '{ printf "  [%d] %s\n", NR, $2 }'
    \\            while true; do
    \\                printf "Select worktree [1-%s], q to quit: " "$count"
    \\                local selection
    \\                IFS= read -r selection || return 0
    \\                case "$selection" in
    \\                    q|Q|quit|Quit|QUIT|cancel|Cancel|CANCEL)
    \\                        return 0
    \\                        ;;
    \\                    ''|*[!0-9]*)
    \\                        echo "Invalid selection. Enter a number or q."
    \\                        continue
    \\                        ;;
    \\                esac
    \\
    \\                if [ "$selection" -lt 1 ] || [ "$selection" -gt "$count" ]; then
    \\                    echo "Selection out of range (1-$count)."
    \\                    continue
    \\                fi
    \\
    \\                selected_path=$(printf '%s\n' "$picker_rows" | sed -n "${selection}p" | cut -f1)
    \\                break
    \\            done
    \\        fi
    \\
    \\        if [ -z "$selected_path" ]; then
    \\            return 0
    \\        fi
    \\        if [ ! -d "$selected_path" ]; then
    \\            echo "Error: selected worktree no longer exists: $selected_path" >&2
    \\            return 1
    \\        fi
    \\        cd "$selected_path" || return 1
    \\        echo "Entered worktree: $selected_path"
    \\        return 0
    \\    fi
    \\
    \\    case "$1" in
    \\        new|add)
    \\            local output
    \\            output=$(command wt "$1" --porcelain "${@:2}" 2>/dev/tty)
    \\            local exit_code=$?
    \\            if [ $exit_code -eq 0 ] && [ -n "$output" ] && [ -d "$output" ]; then
    \\                cd "$output"
    \\                echo "Entered worktree: $output"
    \\            fi
    \\            return $exit_code
    \\            ;;
    \\        *)
    \\            command wt "$@"
    \\            ;;
    \\    esac
    \\}
;

const bash_init =
    \\# wt shell integration
    \\# Add to .bashrc: eval "$(wt shell-init bash)"
    \\
    \\wt() {
    \\    if [ "$#" -gt 0 ] && [ "${1#-}" != "$1" ]; then
    \\        command wt "$@"
    \\        return $?
    \\    fi
    \\
    \\    if [ "$#" -eq 0 ]; then
    \\        local worktrees
    \\        worktrees=$(command wt list --porcelain 2>/dev/null)
    \\        local list_exit=$?
    \\        if [ $list_exit -ne 0 ] || [ -z "$worktrees" ]; then
    \\            command wt "$@"
    \\            return $?
    \\        fi
    \\
    \\        local count
    \\        count=$(printf '%s\n' "$worktrees" | awk 'END { print NR }')
    \\        if [ -z "$count" ] || [ "$count" -eq 0 ]; then
    \\            return 0
    \\        fi
    \\        if [ "$count" -eq 1 ]; then
    \\            local only_branch
    \\            local only_path
    \\            only_branch=$(printf '%s\n' "$worktrees" | cut -f2)
    \\            only_path=$(printf '%s\n' "$worktrees" | cut -f3)
    \\            echo "Only one worktree is available: ${only_branch} (${only_path}). Staying in the current directory."
    \\            return 0
    \\        fi
    \\
    \\        local picker_rows
    \\        picker_rows=$(printf '%s\n' "$worktrees" | awk -F '\t' '
    \\            NF < 9 { next }
    \\            {
    \\                branch = $2
    \\                path = $3
    \\                state = $4
    \\                modified = $5 + 0
    \\                untracked = $6 + 0
    \\                ahead = $7 + 0
    \\                behind = $8 + 0
    \\
    \\                summary = state
    \\                if (state == "dirty") {
    \\                    summary = ""
    \\                    if (modified > 0) {
    \\                        summary = sprintf("M:%d", modified)
    \\                    }
    \\                    if (untracked > 0) {
    \\                        if (length(summary) > 0) {
    \\                            summary = sprintf("%s U:%d", summary, untracked)
    \\                        } else {
    \\                            summary = sprintf("U:%d", untracked)
    \\                        }
    \\                    }
    \\                    if (length(summary) == 0) {
    \\                        summary = "changes"
    \\                    }
    \\                }
    \\                if (ahead > 0) {
    \\                    summary = sprintf("%s ^%d", summary, ahead)
    \\                }
    \\                if (behind > 0) {
    \\                    summary = sprintf("%s v%d", summary, behind)
    \\                }
    \\
    \\                printf "%s\t%-20s  %-20s  %s\n", path, branch, summary, path
    \\            }
    \\        ')
    \\
    \\        local selected_path=""
    \\        if command -v fzf >/dev/null 2>&1; then
    \\            selected_path=$(printf '%s\n' "$picker_rows" | fzf --no-color --prompt "Worktree > " --height 40% --reverse --no-multi --delimiter $'\t' --with-nth 2 --header "BRANCH                STATUS               PATH" | cut -f1)
    \\        else
    \\            echo "Choose a worktree:"
    \\            printf '%s\n' "$picker_rows" | awk -F '\t' '{ printf "  [%d] %s\n", NR, $2 }'
    \\            while true; do
    \\                printf "Select worktree [1-%s], q to quit: " "$count"
    \\                local selection
    \\                IFS= read -r selection || return 0
    \\                case "$selection" in
    \\                    q|Q|quit|Quit|QUIT|cancel|Cancel|CANCEL)
    \\                        return 0
    \\                        ;;
    \\                    ''|*[!0-9]*)
    \\                        echo "Invalid selection. Enter a number or q."
    \\                        continue
    \\                        ;;
    \\                esac
    \\
    \\                if [ "$selection" -lt 1 ] || [ "$selection" -gt "$count" ]; then
    \\                    echo "Selection out of range (1-$count)."
    \\                    continue
    \\                fi
    \\
    \\                selected_path=$(printf '%s\n' "$picker_rows" | sed -n "${selection}p" | cut -f1)
    \\                break
    \\            done
    \\        fi
    \\
    \\        if [ -z "$selected_path" ]; then
    \\            return 0
    \\        fi
    \\        if [ ! -d "$selected_path" ]; then
    \\            echo "Error: selected worktree no longer exists: $selected_path" >&2
    \\            return 1
    \\        fi
    \\        cd "$selected_path" || return 1
    \\        echo "Entered worktree: $selected_path"
    \\        return 0
    \\    fi
    \\
    \\    case "$1" in
    \\        new|add)
    \\            local output
    \\            output=$(command wt "$1" --porcelain "${@:2}" 2>/dev/tty)
    \\            local exit_code=$?
    \\            if [ $exit_code -eq 0 ] && [ -n "$output" ] && [ -d "$output" ]; then
    \\                cd "$output"
    \\                echo "Entered worktree: $output"
    \\            fi
    \\            return $exit_code
    \\            ;;
    \\        *)
    \\            command wt "$@"
    \\            ;;
    \\    esac
    \\}
;

pub fn run(shell: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    if (std.mem.eql(u8, shell, "zsh")) {
        try stdout.print("{s}\n", .{zsh_init});
    } else if (std.mem.eql(u8, shell, "bash")) {
        try stdout.print("{s}\n", .{bash_init});
    } else {
        std.debug.print("Unsupported shell: {s}. Supported: zsh, bash\n", .{shell});
        std.process.exit(1);
    }
}

test "zsh init contains function definition" {
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "wt()") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "${1#-}") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "new|add") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "\"$1\" --porcelain") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "wt list --porcelain") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "command -v fzf") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "--no-color") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "Only one worktree is available:") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "Select worktree [1-") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "cd \"$output\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "Entered worktree: $output") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "Entered worktree: $selected_path") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "command wt") != null);
}

test "bash init contains function definition" {
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "wt()") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "${1#-}") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "new|add") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "\"$1\" --porcelain") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "wt list --porcelain") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "command -v fzf") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "--no-color") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "Only one worktree is available:") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "Entered worktree: $output") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "Entered worktree: $selected_path") != null);
}

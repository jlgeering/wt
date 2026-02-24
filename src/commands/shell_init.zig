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
    \\        local selected_path
    \\        selected_path=$(command wt __pick-worktree)
    \\        local pick_exit=$?
    \\        if [ $pick_exit -ne 0 ]; then
    \\            return $pick_exit
    \\        fi
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
    \\        local selected_path
    \\        selected_path=$(command wt __pick-worktree)
    \\        local pick_exit=$?
    \\        if [ $pick_exit -ne 0 ]; then
    \\            return $pick_exit
    \\        fi
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
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "wt __pick-worktree") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "awk -F") == null);
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
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "wt __pick-worktree") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "awk -F") == null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "Entered worktree: $output") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "Entered worktree: $selected_path") != null);
}

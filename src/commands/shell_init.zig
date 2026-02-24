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
    \\    __wt_report_location() {
    \\        local worktree_root="$1"
    \\        local target_dir="$2"
    \\        local entered_subdir=""
    \\        if [ "$target_dir" != "$worktree_root" ]; then
    \\            entered_subdir="${target_dir#$worktree_root/}"
    \\        fi
    \\
    \\        if [ -t 1 ]; then
    \\            local c_reset=$'\033[0m'
    \\            local c_label=$'\033[2m'
    \\            local c_worktree=$'\033[36m'
    \\            local c_subdir=$'\033[33m'
    \\            printf "\n${c_label}Entered worktree:${c_reset} ${c_worktree}%s${c_reset}\n" "$worktree_root"
    \\            if [ -n "$entered_subdir" ]; then
    \\                printf "${c_label}Subdirectory:${c_reset} ${c_subdir}%s${c_reset}\n" "$entered_subdir"
    \\            fi
    \\        else
    \\            printf "\nEntered worktree: %s\n" "$worktree_root"
    \\            if [ -n "$entered_subdir" ]; then
    \\                printf "Subdirectory: %s\n" "$entered_subdir"
    \\            fi
    \\        fi
    \\    }
    \\
    \\    if [ "$#" -eq 0 ]; then
    \\        local relative_subdir
    \\        relative_subdir=$(command git rev-parse --show-prefix 2>/dev/null || true)
    \\        relative_subdir="${relative_subdir%/}"
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
    \\        local target_dir="$selected_path"
    \\        if [ -n "$relative_subdir" ]; then
    \\            local candidate_dir="$selected_path/$relative_subdir"
    \\            if [ -d "$candidate_dir" ]; then
    \\                target_dir="$candidate_dir"
    \\            else
    \\                echo "Subdirectory missing in selected worktree, using root: $selected_path"
    \\            fi
    \\        fi
    \\        cd "$target_dir" || return 1
    \\        __wt_report_location "$selected_path" "$target_dir"
    \\        return 0
    \\    fi
    \\
    \\    case "$1" in
    \\        new|add)
    \\            local arg
    \\            for arg in "${@:2}"; do
    \\                if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
    \\                    command wt "$@"
    \\                    return $?
    \\                fi
    \\            done
    \\
    \\            local relative_subdir
    \\            relative_subdir=$(command git rev-parse --show-prefix 2>/dev/null || true)
    \\            relative_subdir="${relative_subdir%/}"
    \\            local output
    \\            output=$(command wt "$1" --porcelain "${@:2}" 2>/dev/tty)
    \\            local exit_code=$?
    \\            if [ $exit_code -eq 0 ] && [ -n "$output" ] && [ -d "$output" ]; then
    \\                local target_dir="$output"
    \\                if [ -n "$relative_subdir" ]; then
    \\                    local candidate_dir="$output/$relative_subdir"
    \\                    if [ -d "$candidate_dir" ]; then
    \\                        target_dir="$candidate_dir"
    \\                    else
    \\                        echo "Subdirectory missing in new worktree, using root: $output"
    \\                    fi
    \\                fi
    \\                cd "$target_dir" || return 1
    \\                __wt_report_location "$output" "$target_dir"
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
    \\    __wt_report_location() {
    \\        local worktree_root="$1"
    \\        local target_dir="$2"
    \\        local entered_subdir=""
    \\        if [ "$target_dir" != "$worktree_root" ]; then
    \\            entered_subdir="${target_dir#$worktree_root/}"
    \\        fi
    \\
    \\        if [ -t 1 ]; then
    \\            local c_reset=$'\033[0m'
    \\            local c_label=$'\033[2m'
    \\            local c_worktree=$'\033[36m'
    \\            local c_subdir=$'\033[33m'
    \\            printf "\n${c_label}Entered worktree:${c_reset} ${c_worktree}%s${c_reset}\n" "$worktree_root"
    \\            if [ -n "$entered_subdir" ]; then
    \\                printf "${c_label}Subdirectory:${c_reset} ${c_subdir}%s${c_reset}\n" "$entered_subdir"
    \\            fi
    \\        else
    \\            printf "\nEntered worktree: %s\n" "$worktree_root"
    \\            if [ -n "$entered_subdir" ]; then
    \\                printf "Subdirectory: %s\n" "$entered_subdir"
    \\            fi
    \\        fi
    \\    }
    \\
    \\    if [ "$#" -eq 0 ]; then
    \\        local relative_subdir
    \\        relative_subdir=$(command git rev-parse --show-prefix 2>/dev/null || true)
    \\        relative_subdir="${relative_subdir%/}"
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
    \\        local target_dir="$selected_path"
    \\        if [ -n "$relative_subdir" ]; then
    \\            local candidate_dir="$selected_path/$relative_subdir"
    \\            if [ -d "$candidate_dir" ]; then
    \\                target_dir="$candidate_dir"
    \\            else
    \\                echo "Subdirectory missing in selected worktree, using root: $selected_path"
    \\            fi
    \\        fi
    \\        cd "$target_dir" || return 1
    \\        __wt_report_location "$selected_path" "$target_dir"
    \\        return 0
    \\    fi
    \\
    \\    case "$1" in
    \\        new|add)
    \\            local arg
    \\            for arg in "${@:2}"; do
    \\                if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
    \\                    command wt "$@"
    \\                    return $?
    \\                fi
    \\            done
    \\
    \\            local relative_subdir
    \\            relative_subdir=$(command git rev-parse --show-prefix 2>/dev/null || true)
    \\            relative_subdir="${relative_subdir%/}"
    \\            local output
    \\            output=$(command wt "$1" --porcelain "${@:2}" 2>/dev/tty)
    \\            local exit_code=$?
    \\            if [ $exit_code -eq 0 ] && [ -n "$output" ] && [ -d "$output" ]; then
    \\                local target_dir="$output"
    \\                if [ -n "$relative_subdir" ]; then
    \\                    local candidate_dir="$output/$relative_subdir"
    \\                    if [ -d "$candidate_dir" ]; then
    \\                        target_dir="$candidate_dir"
    \\                    else
    \\                        echo "Subdirectory missing in new worktree, using root: $output"
    \\                    fi
    \\                fi
    \\                cd "$target_dir" || return 1
    \\                __wt_report_location "$output" "$target_dir"
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
    const stdout = std.fs.File.stdout().deprecatedWriter();

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
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "for arg in \"${@:2}\"; do") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "[ \"$arg\" = \"--help\" ]") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "\"$1\" --porcelain") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "wt __pick-worktree") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "__wt_report_location()") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "printf \"\\nEntered worktree: %s\\n\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "printf \"Subdirectory: %s\\n\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "__wt_report_location \"$selected_path\" \"$target_dir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "__wt_report_location \"$output\" \"$target_dir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "awk -F") == null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "git rev-parse --show-prefix") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "candidate_dir=\"$selected_path/$relative_subdir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "Subdirectory missing in selected worktree, using root: $selected_path") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "candidate_dir=\"$output/$relative_subdir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "Subdirectory missing in new worktree, using root: $output") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "cd \"$target_dir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "command wt") != null);
}

test "bash init contains function definition" {
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "wt()") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "${1#-}") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "new|add") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "for arg in \"${@:2}\"; do") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "[ \"$arg\" = \"--help\" ]") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "\"$1\" --porcelain") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "wt __pick-worktree") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "__wt_report_location()") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "printf \"\\nEntered worktree: %s\\n\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "printf \"Subdirectory: %s\\n\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "__wt_report_location \"$selected_path\" \"$target_dir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "__wt_report_location \"$output\" \"$target_dir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "awk -F") == null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "git rev-parse --show-prefix") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "candidate_dir=\"$selected_path/$relative_subdir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "Subdirectory missing in selected worktree, using root: $selected_path") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "candidate_dir=\"$output/$relative_subdir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "Subdirectory missing in new worktree, using root: $output") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "cd \"$target_dir\"") != null);
}

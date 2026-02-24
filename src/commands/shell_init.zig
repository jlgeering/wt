const std = @import("std");
const ui = @import("../lib/ui.zig");
const cli_surface = @import("../lib/cli_surface.zig");

fn buildZshCommandChoices() []const u8 {
    comptime var out: []const u8 = "";
    inline for (cli_surface.completion_commands) |command| {
        out = out ++ "        '" ++ command.name ++ ":" ++ command.description ++ "'\n";
        inline for (command.aliases) |alias| {
            out = out ++ "        '" ++ alias ++ ":Alias for " ++ command.name ++ "'\n";
        }
    }
    return out;
}

fn buildShellNameChoices() []const u8 {
    comptime var out: []const u8 = "";
    inline for (cli_surface.shell_names, 0..) |shell_name, idx| {
        if (idx != 0) out = out ++ " ";
        out = out ++ shell_name;
    }
    return out;
}

const zsh_command_choices = buildZshCommandChoices();
const shell_name_choices = buildShellNameChoices();

const zsh_init =
    \\# wt shell integration
    \\# Add to .zshrc: eval "$(wt shell-init zsh)"
    \\
    \\__wt_complete_local_branches() {
    \\    local branch
    \\    local -a branches
    \\    typeset -A seen
    \\    while IFS= read -r branch; do
    \\        if [ -z "$branch" ]; then
    \\            continue
    \\        fi
    \\        if [ -z "${seen[$branch]}" ]; then
    \\            seen[$branch]=1
    \\            branches+=("$branch")
    \\        fi
    \\    done < <(command git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
    \\    if [ "${#branches[@]}" -gt 0 ]; then
    \\        compadd -- "${branches[@]}"
    \\    fi
    \\}
    \\
    \\__wt_complete_refs() {
    \\    local ref
    \\    local -a refs
    \\    typeset -A seen
    \\    while IFS= read -r ref; do
    \\        if [ -z "$ref" ]; then
    \\            continue
    \\        fi
    \\        if [ -z "${seen[$ref]}" ]; then
    \\            seen[$ref]=1
    \\            refs+=("$ref")
    \\        fi
    \\    done < <(command git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)
    \\    if [ "${#refs[@]}" -gt 0 ]; then
    \\        compadd -- "${refs[@]}"
    \\    fi
    \\}
    \\
    \\__wt_complete_rm_branches() {
    \\    local current branch
    \\    local -a branches
    \\    typeset -A seen
    \\    while IFS=$'\t' read -r current branch _; do
    \\        if [ -z "$branch" ] || [ "$branch" = "(detached)" ] || [ "$branch" = "-" ]; then
    \\            continue
    \\        fi
    \\        if [ "$current" = "1" ]; then
    \\            continue
    \\        fi
    \\        if [ -z "${seen[$branch]}" ]; then
    \\            seen[$branch]=1
    \\            branches+=("$branch")
    \\        fi
    \\    done < <(command wt list --porcelain 2>/dev/null)
    \\    if [ "${#branches[@]}" -gt 0 ]; then
    \\        compadd -- "${branches[@]}"
    \\    fi
    \\}
    \\
    \\_wt() {
    \\    local cmd="$words[2]"
    \\    local -a commands
    \\    commands=(
++ zsh_command_choices ++
    \\    )
    \\
    \\    if [ "$CURRENT" -eq 2 ]; then
    \\        _describe -t commands "wt command" commands
    \\        return 0
    \\    fi
    \\
    \\    if [ "$CURRENT" -lt 3 ]; then
    \\        return 0
    \\    fi
    \\
    \\    case "$cmd" in
    \\        new|add)
    \\            if [ "$CURRENT" -eq 3 ]; then
    \\                __wt_complete_local_branches
    \\            elif [ "$CURRENT" -eq 4 ]; then
    \\                __wt_complete_refs
    \\            fi
    \\            ;;
    \\        rm)
    \\            if [ "$CURRENT" -eq 3 ]; then
    \\                __wt_complete_rm_branches
    \\            fi
    \\            ;;
    \\        shell-init)
    \\            if [ "$CURRENT" -eq 3 ]; then
    \\
++ "                compadd -- " ++ shell_name_choices ++ "\n" ++
    \\            fi
    \\            ;;
    \\    esac
    \\
    \\    return 0
    \\}
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
    \\
    \\compdef _wt wt
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
    const stderr = std.fs.File.stderr().deprecatedWriter();
    const use_color = ui.shouldUseColor(std.fs.File.stderr());

    if (std.mem.eql(u8, shell, "zsh")) {
        try stdout.print("{s}\n", .{zsh_init});
    } else if (std.mem.eql(u8, shell, "bash")) {
        try stdout.print("{s}\n", .{bash_init});
    } else {
        try ui.printLevel(stderr, use_color, .err, "unsupported shell: {s}. Supported: zsh, bash", .{shell});
        std.process.exit(1);
    }
}

test "zsh init contains function definition" {
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "__wt_complete_local_branches()") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "__wt_complete_refs()") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "__wt_complete_rm_branches()") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "_wt()") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "compdef _wt wt") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'list:List worktrees'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'new:Create a new worktree'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'add:Alias for new'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'rm:Remove a worktree'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'init:Create or upgrade .wt.toml'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'shell-init:Output shell integration function'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "command wt list --porcelain") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "compadd -- zsh bash") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "if [ \"$CURRENT\" -eq 3 ]; then") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "elif [ \"$CURRENT\" -eq 4 ]; then") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "__wt_complete_local_branches") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "_arguments") == null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "--picker") == null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "--force") == null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "--no-interactive") == null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "--version") == null);
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

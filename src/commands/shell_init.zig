const std = @import("std");
const ui = @import("../lib/ui.zig");

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
    \\
    \\__wt_complete_worktree_branches() {
    \\    local current branch _rest
    \\    command wt list --porcelain 2>/dev/null | while IFS=$'\t' read -r current branch _rest; do
    \\        if [ "$current" = "1" ]; then
    \\            continue
    \\        fi
    \\        if [ -n "$branch" ] && [ "$branch" != "-" ]; then
    \\            printf '%s\n' "$branch"
    \\        fi
    \\    done
    \\}
    \\
    \\_wt_bash_completion() {
    \\    local cur prev cmd
    \\    COMPREPLY=()
    \\    cur="${COMP_WORDS[COMP_CWORD]}"
    \\    prev=""
    \\    if [ "$COMP_CWORD" -gt 0 ]; then
    \\        prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\    fi
    \\    cmd=""
    \\    if [ "${#COMP_WORDS[@]}" -gt 1 ]; then
    \\        cmd="${COMP_WORDS[1]}"
    \\    fi
    \\
    \\    if [ "$COMP_CWORD" -eq 1 ]; then
    \\        COMPREPLY=($(compgen -W "list new add rm init shell-init --help -h --version -V" -- "$cur"))
    \\        return 0
    \\    fi
    \\
    \\    case "$cmd" in
    \\        list)
    \\            COMPREPLY=($(compgen -W "--help -h --porcelain" -- "$cur"))
    \\            return 0
    \\            ;;
    \\        new|add)
    \\            if [[ "$cur" == -* ]]; then
    \\                COMPREPLY=($(compgen -W "--help -h --porcelain" -- "$cur"))
    \\                return 0
    \\            fi
    \\            if [ "$COMP_CWORD" -eq 3 ]; then
    \\                local refs
    \\                refs=$(command git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)
    \\                COMPREPLY=($(compgen -W "$refs" -- "$cur"))
    \\            fi
    \\            return 0
    \\            ;;
    \\        rm)
    \\            if [ "$prev" = "--picker" ]; then
    \\                COMPREPLY=($(compgen -W "auto builtin fzf" -- "$cur"))
    \\                return 0
    \\            fi
    \\            if [[ "$cur" == -* ]]; then
    \\                COMPREPLY=($(compgen -W "--help -h --force -f --picker --no-interactive" -- "$cur"))
    \\                return 0
    \\            fi
    \\            local branches
    \\            branches=$(__wt_complete_worktree_branches)
    \\            COMPREPLY=($(compgen -W "$branches" -- "$cur"))
    \\            return 0
    \\            ;;
    \\        init)
    \\            COMPREPLY=($(compgen -W "--help -h" -- "$cur"))
    \\            return 0
    \\            ;;
    \\        shell-init)
    \\            if [[ "$cur" == -* ]]; then
    \\                COMPREPLY=($(compgen -W "--help -h" -- "$cur"))
    \\            else
    \\                COMPREPLY=($(compgen -W "bash zsh" -- "$cur"))
    \\            fi
    \\            return 0
    \\            ;;
    \\        *)
    \\            if [[ "$cur" == -* ]]; then
    \\                COMPREPLY=($(compgen -W "--help -h --version -V" -- "$cur"))
    \\            fi
    \\            return 0
    \\            ;;
    \\    esac
    \\}
    \\
    \\complete -F _wt_bash_completion wt
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
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "__wt_complete_worktree_branches()") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "command wt list --porcelain") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "_wt_bash_completion()") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "compgen -W \"list new add rm init shell-init --help -h --version -V\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "compgen -W \"auto builtin fzf\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "compgen -W \"bash zsh\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "complete -F _wt_bash_completion wt") != null);
}

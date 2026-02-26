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

fn buildFishCommandCompletions() []const u8 {
    comptime var out: []const u8 = "";
    inline for (cli_surface.completion_commands) |command| {
        out = out ++ "complete -f -c wt -n \"__fish_use_subcommand\" -a \"" ++ command.name ++ "\" -d \"" ++ command.description ++ "\"\n";
        inline for (command.aliases) |alias| {
            out = out ++ "complete -f -c wt -n \"__fish_use_subcommand\" -a \"" ++ alias ++ "\" -d \"Alias for " ++ command.name ++ "\"\n";
        }
    }
    return out;
}

fn buildNuCommandChoices() []const u8 {
    comptime var out: []const u8 = "";
    inline for (cli_surface.completion_commands) |command| {
        out = out ++ "        { value: \"" ++ command.name ++ "\", description: \"" ++ command.description ++ "\" }\n";
        inline for (command.aliases) |alias| {
            out = out ++ "        { value: \"" ++ alias ++ "\", description: \"Alias for " ++ command.name ++ "\" }\n";
        }
    }
    return out;
}

fn buildNuShellNameChoices() []const u8 {
    comptime var out: []const u8 = "";
    inline for (cli_surface.shell_names, 0..) |shell_name, idx| {
        if (idx != 0) out = out ++ " ";
        out = out ++ "\"" ++ shell_name ++ "\"";
    }
    return out;
}

const zsh_command_choices = buildZshCommandChoices();
const shell_name_choices = buildShellNameChoices();
const fish_command_completions = buildFishCommandCompletions();
const nu_command_choices = buildNuCommandChoices();
const nu_shell_name_choices = buildNuShellNameChoices();

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
    \\    done < <(command wt __list 2>/dev/null)
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
    \\            output=$(command wt "__new" "${@:2}")
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
    \\            output=$(command wt "__new" "${@:2}")
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
    \\    command wt __list 2>/dev/null | while IFS=$'\t' read -r current branch _rest; do
    \\        if [ "$current" = "1" ]; then
    \\            continue
    \\        fi
    \\        if [ -n "$branch" ] && [ "$branch" != "(detached)" ] && [ "$branch" != "-" ]; then
    \\            printf '%s\n' "$branch"
    \\        fi
    \\    done
    \\}
    \\
    \\__wt_complete_local_branches() {
    \\    command git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
    \\}
    \\
    \\__wt_complete_refs() {
    \\    command git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
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
    \\        COMPREPLY=($(compgen -W "list ls new add rm init shell-init --help -h --version -V" -- "$cur"))
    \\        return 0
    \\    fi
    \\
    \\    case "$cmd" in
    \\        list)
    \\            COMPREPLY=($(compgen -W "--help -h" -- "$cur"))
    \\            return 0
    \\            ;;
    \\        new|add)
    \\            if [[ "$cur" == -* ]]; then
    \\                COMPREPLY=($(compgen -W "--help -h" -- "$cur"))
    \\                return 0
    \\            fi
    \\            local positional_count=0
    \\            local i word
    \\            for ((i=2; i<COMP_CWORD; i++)); do
    \\                word="${COMP_WORDS[i]}"
    \\                if [[ "$word" == -* ]]; then
    \\                    continue
    \\                fi
    \\                positional_count=$((positional_count + 1))
    \\            done
    \\            if [ "$positional_count" -eq 0 ]; then
    \\                local branches
    \\                branches=$(__wt_complete_local_branches)
    \\                COMPREPLY=($(compgen -W "$branches" -- "$cur"))
    \\                return 0
    \\            fi
    \\            if [ "$positional_count" -eq 1 ]; then
    \\                local refs
    \\                refs=$(__wt_complete_refs)
    \\                COMPREPLY=($(compgen -W "$refs" -- "$cur"))
    \\                return 0
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
++ "                COMPREPLY=($(compgen -W \"" ++ shell_name_choices ++ "\" -- \"$cur\"))\n" ++
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

const fish_init =
    \\# wt shell integration
    \\# Add to config.fish: wt shell-init fish | source
    \\
    \\function __wt_complete_local_branches
    \\    command git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | sort -u
    \\end
    \\
    \\function __wt_complete_refs
    \\    command git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null | sort -u
    \\end
    \\
    \\function __wt_complete_rm_branches
    \\    command wt __list 2>/dev/null | while read -l current branch _
    \\        if test -z "$branch"; or test "$branch" = "(detached)"; or test "$branch" = "-"
    \\            continue
    \\        end
    \\        if test "$current" = "1"
    \\            continue
    \\        end
    \\        echo "$branch"
    \\    end | sort -u
    \\end
    \\
    \\complete -e -c wt
    \\complete -f -c wt
++ "\n" ++ fish_command_completions ++
    \\complete -f -c wt -n "__fish_seen_subcommand_from new add; and test (count (commandline -opc)) -eq 2" -a "(__wt_complete_local_branches)"
    \\complete -f -c wt -n "__fish_seen_subcommand_from new add; and test (count (commandline -opc)) -eq 3" -a "(__wt_complete_refs)"
    \\complete -f -c wt -n "__fish_seen_subcommand_from rm; and test (count (commandline -opc)) -eq 2" -a "(__wt_complete_rm_branches)"
++ "\ncomplete -f -c wt -n \"__fish_seen_subcommand_from shell-init; and test (count (commandline -opc)) -eq 2\" -a \"" ++ shell_name_choices ++ "\"\n" ++
    \\
    \\function wt --wraps wt --description 'wt shell integration'
    \\    if test (count $argv) -gt 0
    \\        set -l first "$argv[1]"
    \\        if string match -qr '^-' -- "$first"
    \\            command wt $argv
    \\            return $status
    \\        end
    \\    end
    \\
    \\    function __wt_report_location --argument-names worktree_root target_dir
    \\        set -l entered_subdir ""
    \\        if test "$target_dir" != "$worktree_root"
    \\            set entered_subdir (string replace -- "$worktree_root/" "" "$target_dir")
    \\        end
    \\
    \\        if isatty stdout
    \\            set -l c_reset (set_color normal)
    \\            set -l c_label (set_color brblack)
    \\            set -l c_worktree (set_color cyan)
    \\            set -l c_subdir (set_color yellow)
    \\            printf "\n%sEntered worktree:%s %s%s%s\n" "$c_label" "$c_reset" "$c_worktree" "$worktree_root" "$c_reset"
    \\            if test -n "$entered_subdir"
    \\                printf "%sSubdirectory:%s %s%s%s\n" "$c_label" "$c_reset" "$c_subdir" "$entered_subdir" "$c_reset"
    \\            end
    \\        else
    \\            printf "\nEntered worktree: %s\n" "$worktree_root"
    \\            if test -n "$entered_subdir"
    \\                printf "Subdirectory: %s\n" "$entered_subdir"
    \\            end
    \\        end
    \\    end
    \\
    \\    if test (count $argv) -eq 0
    \\        set -l relative_subdir (command git rev-parse --show-prefix 2>/dev/null)
    \\        set relative_subdir (string trim -c / -- "$relative_subdir")
    \\        set -l selected_path (command wt __pick-worktree)
    \\        set -l pick_exit $status
    \\        if test $pick_exit -ne 0
    \\            return $pick_exit
    \\        end
    \\        if test -z "$selected_path"
    \\            return 0
    \\        end
    \\        if not test -d "$selected_path"
    \\            echo "Error: selected worktree no longer exists: $selected_path" >&2
    \\            return 1
    \\        end
    \\        set -l target_dir "$selected_path"
    \\        if test -n "$relative_subdir"
    \\            set -l candidate_dir "$selected_path/$relative_subdir"
    \\            if test -d "$candidate_dir"
    \\                set target_dir "$candidate_dir"
    \\            else
    \\                echo "Subdirectory missing in selected worktree, using root: $selected_path"
    \\            end
    \\        end
    \\        cd "$target_dir"; or return 1
    \\        __wt_report_location "$selected_path" "$target_dir"
    \\        return 0
    \\    end
    \\
    \\    switch "$argv[1]"
    \\        case new add
    \\            for arg in $argv[2..-1]
    \\                if test "$arg" = "-h"; or test "$arg" = "--help"
    \\                    command wt $argv
    \\                    return $status
    \\                end
    \\            end
    \\
    \\            set -l relative_subdir (command git rev-parse --show-prefix 2>/dev/null)
    \\            set relative_subdir (string trim -c / -- "$relative_subdir")
    \\            set -l output (command wt __new $argv[2..-1])
    \\            set -l exit_code $status
    \\            if test $exit_code -eq 0; and test -n "$output"; and test -d "$output"
    \\                set -l target_dir "$output"
    \\                if test -n "$relative_subdir"
    \\                    set -l candidate_dir "$output/$relative_subdir"
    \\                    if test -d "$candidate_dir"
    \\                        set target_dir "$candidate_dir"
    \\                    else
    \\                        echo "Subdirectory missing in new worktree, using root: $output"
    \\                    end
    \\                end
    \\                cd "$target_dir"; or return 1
    \\                __wt_report_location "$output" "$target_dir"
    \\            end
    \\            return $exit_code
    \\        case '*'
    \\            command wt $argv
    \\            return $status
    \\    end
    \\end
;

const nu_init =
    \\# wt shell integration
    \\# Add to config.nu:
    \\# wt shell-init nu | save -f ~/.config/nushell/wt.nu
    \\# source ~/.config/nushell/wt.nu
    \\
    \\def "nu-complete wt commands" [] {
    \\    [
++ nu_command_choices ++
    \\    ]
    \\}
    \\
    \\def "__wt_complete_local_branches" [] {
    \\    let refs = (^git for-each-ref --format='%(refname:short)' refs/heads err> /dev/null | complete)
    \\    if $refs.exit_code != 0 {
    \\        return []
    \\    }
    \\    $refs.stdout
    \\    | lines
    \\    | each {|it| $it | str trim}
    \\    | where {|it| $it != ""}
    \\    | uniq
    \\}
    \\
    \\def "__wt_complete_refs" [] {
    \\    let refs = (^git for-each-ref --format='%(refname:short)' refs/heads refs/remotes err> /dev/null | complete)
    \\    if $refs.exit_code != 0 {
    \\        return []
    \\    }
    \\    $refs.stdout
    \\    | lines
    \\    | each {|it| $it | str trim}
    \\    | where {|it| $it != ""}
    \\    | uniq
    \\}
    \\
    \\def "__wt_complete_rm_branches" [] {
    \\    let listing = (^wt __list err> /dev/null | complete)
    \\    if $listing.exit_code != 0 {
    \\        return []
    \\    }
    \\    $listing.stdout
    \\    | lines
    \\    | each {|line| $line | split row "\t"}
    \\    | where {|cols| ($cols | length) >= 2}
    \\    | each {|cols| { current: ($cols | get 0), branch: ($cols | get 1) }}
    \\    | where {|row| $row.current != "1" and $row.branch != "(detached)" and $row.branch != "-"}
    \\    | get branch
    \\    | uniq
    \\}
    \\
    \\def "__wt_complete_shell_names" [] {
    \\    [
++ nu_shell_name_choices ++
    \\    ]
    \\}
    \\
    \\def "nu-complete wt" [spans: list<string>] {
    \\    let total = ($spans | length)
    \\    if $total <= 2 {
    \\        return (nu-complete wt commands)
    \\    }
    \\
    \\    let cmd = ($spans | get 1)
    \\    match $cmd {
    \\        "new" | "add" => {
    \\            let positional = ($spans | skip 2 | where {|arg| not ($arg | str starts-with "-")})
    \\            if ($positional | length) <= 1 {
    \\                return (__wt_complete_local_branches)
    \\            }
    \\            if ($positional | length) == 2 {
    \\                return (__wt_complete_refs)
    \\            }
    \\            return []
    \\        }
    \\        "rm" => {
    \\            let positional = ($spans | skip 2 | where {|arg| not ($arg | str starts-with "-")})
    \\            if ($positional | length) <= 1 {
    \\                return (__wt_complete_rm_branches)
    \\            }
    \\            return []
    \\        }
    \\        "shell-init" => {
    \\            let positional = ($spans | skip 2 | where {|arg| not ($arg | str starts-with "-")})
    \\            if ($positional | length) <= 1 {
    \\                return (__wt_complete_shell_names)
    \\            }
    \\            return []
    \\        }
    \\        _ => {
    \\            return []
    \\        }
    \\    }
    \\}
    \\
    \\def "__wt_print_stderr" [result: record] {
    \\    if ("stderr" in ($result | columns)) and (not ($result.stderr | is-empty)) {
    \\        print --stderr --raw --no-newline $result.stderr
    \\    }
    \\}
    \\
    \\def "__wt_relative_subdir" [] {
    \\    let relative = (^git rev-parse --show-prefix err> /dev/null | complete)
    \\    if $relative.exit_code != 0 {
    \\        return ""
    \\    }
    \\    $relative.stdout | str trim | str trim --right --char '/'
    \\}
    \\
    \\def "__wt_report_location" [worktree_root: string, target_dir: string] {
    \\    let entered_subdir = if $target_dir == $worktree_root {
    \\        ""
    \\    } else {
    \\        let root_prefix = $"($worktree_root)/"
    \\        if ($target_dir | str starts-with $root_prefix) {
    \\            let prefix_len = ($root_prefix | str length)
    \\            $target_dir | str substring ($prefix_len)..
    \\        } else {
    \\            $target_dir
    \\        }
    \\    }
    \\
    \\    print ""
    \\    print $"Entered worktree: ($worktree_root)"
    \\    if $entered_subdir != "" {
    \\        print $"Subdirectory: ($entered_subdir)"
    \\    }
    \\}
    \\
    \\@complete 'nu-complete wt'
    \\def --env --wrapped wt [...args] {
    \\    if ($args | is-empty) {
    \\        let relative_subdir = (__wt_relative_subdir)
    \\        let picked = (^wt __pick-worktree | complete)
    \\        __wt_print_stderr $picked
    \\        $env.LAST_EXIT_CODE = $picked.exit_code
    \\        if $picked.exit_code != 0 {
    \\            return
    \\        }
    \\
    \\        let selected_path = ($picked.stdout | str trim)
    \\        if $selected_path == "" {
    \\            return
    \\        }
    \\        if not ($selected_path | path exists) {
    \\            print --stderr $"Error: selected worktree no longer exists: ($selected_path)"
    \\            $env.LAST_EXIT_CODE = 1
    \\            return
    \\        }
    \\
    \\        let target_dir = if $relative_subdir == "" {
    \\            $selected_path
    \\        } else {
    \\            let candidate_dir = ($selected_path | path join $relative_subdir)
    \\            if ($candidate_dir | path exists) {
    \\                $candidate_dir
    \\            } else {
    \\                print $"Subdirectory missing in selected worktree, using root: ($selected_path)"
    \\                $selected_path
    \\            }
    \\        }
    \\
    \\        cd $target_dir
    \\        __wt_report_location $selected_path $target_dir
    \\        $env.LAST_EXIT_CODE = 0
    \\        return
    \\    }
    \\
    \\    let cmd = ($args | first)
    \\    if ($cmd | str starts-with "-") {
    \\        ^wt ...$args
    \\        return
    \\    }
    \\
    \\    match $cmd {
    \\        "new" | "add" => {
    \\            let passthrough = ($args | skip 1)
    \\            if ($passthrough | any {|arg| $arg == "-h" or $arg == "--help"}) {
    \\                ^wt ...$args
    \\                return
    \\            }
    \\
    \\            let relative_subdir = (__wt_relative_subdir)
    \\            let created = (^wt __new ...$passthrough | complete)
    \\            __wt_print_stderr $created
    \\            $env.LAST_EXIT_CODE = $created.exit_code
    \\            if $created.exit_code != 0 {
    \\                return
    \\            }
    \\
    \\            let output = ($created.stdout | str trim)
    \\            if $output != "" and ($output | path exists) {
    \\                let target_dir = if $relative_subdir == "" {
    \\                    $output
    \\                } else {
    \\                    let candidate_dir = ($output | path join $relative_subdir)
    \\                    if ($candidate_dir | path exists) {
    \\                        $candidate_dir
    \\                    } else {
    \\                        print $"Subdirectory missing in new worktree, using root: ($output)"
    \\                        $output
    \\                    }
    \\                }
    \\                cd $target_dir
    \\                __wt_report_location $output $target_dir
    \\            }
    \\            return
    \\        }
    \\        _ => {
    \\            ^wt ...$args
    \\        }
    \\    }
    \\}
;

pub fn run(shell: []const u8) !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();
    const use_color = ui.shouldUseColor(std.fs.File.stderr());

    if (scriptForShell(shell)) |script| {
        try stdout.print("{s}\n", .{script});
    } else {
        try ui.printLevel(stderr, use_color, .err, "unsupported shell: {s}. Supported: zsh, bash, fish, nu", .{shell});
        std.process.exit(1);
    }
}

pub fn scriptForShell(shell: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, shell, "zsh")) return zsh_init;
    if (std.mem.eql(u8, shell, "bash")) return bash_init;
    if (std.mem.eql(u8, shell, "fish")) return fish_init;
    if (std.mem.eql(u8, shell, "nu") or std.mem.eql(u8, shell, "nushell")) return nu_init;
    return null;
}

test "zsh init contains function definition" {
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "__wt_complete_local_branches()") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "__wt_complete_refs()") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "__wt_complete_rm_branches()") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "_wt()") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "compdef _wt wt") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'list:List worktrees'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'ls:Alias for list'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'new:Create a new worktree'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'add:Alias for new'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'rm:Remove a worktree'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'init:Create or upgrade .wt.toml'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "'shell-init:Output shell integration function'") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "command wt __list") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "compadd -- zsh bash fish nu nushell") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "command wt \"__new\" \"${@:2}\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "2>/dev/tty") == null);
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
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "command wt \"__new\" \"${@:2}\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "2>/dev/tty") == null);
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
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "__wt_complete_local_branches()") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "__wt_complete_refs()") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "command wt __list") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "_wt_bash_completion()") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "for ((i=2; i<COMP_CWORD; i++)); do") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "branches=$(__wt_complete_local_branches)") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "refs=$(__wt_complete_refs)") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "compgen -W \"list ls new add rm init shell-init --help -h --version -V\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "--porcelain") == null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "compgen -W \"auto builtin fzf\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "compgen -W \"zsh bash fish nu nushell\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "[ \"$branch\" != \"(detached)\" ]") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "complete -F _wt_bash_completion wt") != null);
}

test "fish init contains function definition and completion" {
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "function __wt_complete_local_branches") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "function __wt_complete_refs") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "function __wt_complete_rm_branches") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "complete -e -c wt") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "complete -f -c wt\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "complete -f -c wt -n \"__fish_use_subcommand\" -a \"list\" -d \"List worktrees\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "complete -f -c wt -n \"__fish_use_subcommand\" -a \"ls\" -d \"Alias for list\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "complete -f -c wt -n \"__fish_use_subcommand\" -a \"add\" -d \"Alias for new\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "complete -f -c wt -n \"__fish_seen_subcommand_from new add; and test (count (commandline -opc)) -eq 2\" -a \"(__wt_complete_local_branches)\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "complete -f -c wt -n \"__fish_seen_subcommand_from shell-init; and test (count (commandline -opc)) -eq 2\" -a \"zsh bash fish nu nushell\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "function wt --wraps wt --description 'wt shell integration'") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "string match -qr '^-' -- \"$first\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "command wt __pick-worktree") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "__wt_report_location \"$selected_path\" \"$target_dir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "__wt_report_location \"$output\" \"$target_dir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "git rev-parse --show-prefix") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "2>/dev/tty") == null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "candidate_dir=\"$selected_path/$relative_subdir\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "set -l candidate_dir \"$selected_path/$relative_subdir\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "Subdirectory missing in selected worktree, using root: $selected_path") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "Subdirectory missing in new worktree, using root: $output") != null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "--picker") == null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "--force") == null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "--no-interactive") == null);
    try std.testing.expect(std.mem.indexOf(u8, fish_init, "--version") == null);
}

test "nu init contains wrapper and completion definitions" {
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "@complete 'nu-complete wt'") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "def --env --wrapped wt [...args]") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "def \"nu-complete wt\" [spans: list<string>]") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "def \"nu-complete wt commands\" []") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "{ value: \"ls\", description: \"Alias for list\" }") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "{ value: \"new\", description: \"Create a new worktree\" }") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "{ value: \"add\", description: \"Alias for new\" }") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "def \"__wt_complete_local_branches\" []") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "^git for-each-ref --format='%(refname:short)' refs/heads err> /dev/null") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "^git for-each-ref --format='%(refname:short)' refs/heads refs/remotes err> /dev/null") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "def \"__wt_complete_rm_branches\" []") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "^wt __list err> /dev/null") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "def \"__wt_complete_shell_names\" []") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "\"zsh\" \"bash\" \"fish\" \"nu\" \"nushell\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "^wt __pick-worktree | complete") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "^wt __new ...$passthrough | complete") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "__wt_report_location $selected_path $target_dir") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "__wt_report_location $output $target_dir") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "Subdirectory missing in selected worktree, using root: ($selected_path)") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "Subdirectory missing in new worktree, using root: ($output)") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_init, "$env.LAST_EXIT_CODE = $created.exit_code") != null);
}

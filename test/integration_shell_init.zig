const std = @import("std");

const helpers = @import("helpers.zig");
const shell_init = @import("wt_root").cmd_shell_init;

const ScriptFlavor = enum {
    bsd,
    util_linux,
};

const ShellRuntime = struct {
    name: []const u8,
    bin: []const u8,
};

const runtime_shells = [_]ShellRuntime{
    .{ .name = "zsh", .bin = "zsh" },
    .{ .name = "bash", .bin = "bash" },
    .{ .name = "fish", .bin = "fish" },
    .{ .name = "nu", .bin = "nu" },
};

const pty_runtime_shells = [_]ShellRuntime{
    .{ .name = "zsh", .bin = "zsh" },
    .{ .name = "bash", .bin = "bash" },
    // TODO(wt-2eq): Re-enable fish PTY picker-cancel coverage after harness watchdog work.
    .{ .name = "nu", .bin = "nu" },
};

const EnvOverride = struct {
    key: []const u8,
    value: []const u8,
};

const stub_wt_script =
    \\#!/usr/bin/env bash
    \\set -eu
    \\cmd="${1:-}"
    \\if [ -n "${WT_STUB_LOG:-}" ]; then
    \\  printf '%s\n' "$*" >> "$WT_STUB_LOG"
    \\fi
    \\case "$cmd" in
    \\  __pick-worktree)
    \\    if [ -n "${WT_STUB_PICK_STDERR:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_PICK_STDERR" >&2
    \\    fi
    \\    if [ -n "${WT_STUB_PICK_PATH:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_PICK_PATH"
    \\    fi
    \\    if [ -n "${WT_STUB_PICK_EXIT:-}" ]; then
    \\      exit "$WT_STUB_PICK_EXIT"
    \\    fi
    \\    ;;
    \\  __new)
    \\    shift || true
    \\    if [ -n "${WT_STUB_NEW_STDERR:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_NEW_STDERR" >&2
    \\    fi
    \\    if [ -n "${WT_STUB_NEW_PATH:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_NEW_PATH"
    \\    fi
    \\    if [ -n "${WT_STUB_NEW_EXIT:-}" ]; then
    \\      exit "$WT_STUB_NEW_EXIT"
    \\    fi
    \\    ;;
    \\  __switch)
    \\    shift || true
    \\    if [ -n "${WT_STUB_SWITCH_STDERR:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_SWITCH_STDERR" >&2
    \\    fi
    \\    if [ -n "${WT_STUB_SWITCH_PATH:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_SWITCH_PATH"
    \\    fi
    \\    if [ -n "${WT_STUB_SWITCH_EXIT:-}" ]; then
    \\      exit "$WT_STUB_SWITCH_EXIT"
    \\    fi
    \\    ;;
    \\  __complete-local-branches)
    \\    if [ -n "${WT_STUB_COMPLETE_LOCAL_BRANCHES:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_COMPLETE_LOCAL_BRANCHES"
    \\    fi
    \\    ;;
    \\  __complete-branch-targets)
    \\    shift || true
    \\    current="${1:-}"
    \\    if [ -n "$current" ] && [ "${current#origin/}" != "$current" ]; then
    \\      if [ -n "${WT_STUB_COMPLETE_BRANCH_TARGETS_REMOTE:-}" ]; then
    \\        printf '%s\n' "$WT_STUB_COMPLETE_BRANCH_TARGETS_REMOTE"
    \\      fi
    \\    elif [ -n "${WT_STUB_COMPLETE_BRANCH_TARGETS_ROOT:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_COMPLETE_BRANCH_TARGETS_ROOT"
    \\    fi
    \\    ;;
    \\  __complete-refs)
    \\    if [ -n "${WT_STUB_COMPLETE_REFS:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_COMPLETE_REFS"
    \\    fi
    \\    ;;
    \\  __complete-worktree-branches)
    \\    if [ -n "${WT_STUB_COMPLETE_WORKTREE_BRANCHES:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_COMPLETE_WORKTREE_BRANCHES"
    \\    fi
    \\    ;;
    \\  *)
    \\    if [ -n "${WT_STUB_DEFAULT_STDERR:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_DEFAULT_STDERR" >&2
    \\    fi
    \\    if [ -n "${WT_STUB_DEFAULT_EXIT:-}" ]; then
    \\      exit "$WT_STUB_DEFAULT_EXIT"
    \\    fi
    \\    ;;
    \\esac
;

fn requireScript(shell: []const u8) ![]const u8 {
    return shell_init.scriptForShell(shell) orelse return error.MissingShellScript;
}

fn commandSucceeds(allocator: std.mem.Allocator, argv: []const []const u8) bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return false,
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn shellExists(allocator: std.mem.Allocator, shell_bin: []const u8) bool {
    return commandSucceeds(allocator, &.{ shell_bin, "-c", "exit 0" });
}

fn detectScriptFlavor(allocator: std.mem.Allocator) ?ScriptFlavor {
    if (commandSucceeds(allocator, &.{ "script", "-q", "/dev/null", "true" })) return .bsd;
    if (commandSucceeds(allocator, &.{ "script", "-q", "-c", "true", "/dev/null" })) return .util_linux;
    return null;
}

fn resolveWtBinaryPath(allocator: std.mem.Allocator) !?[]u8 {
    const path = std.process.getEnvVarOwned(allocator, "WT_TEST_WT_BIN") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    errdefer allocator.free(path);

    std.fs.cwd().access(path, .{}) catch {
        allocator.free(path);
        return null;
    };

    return path;
}

fn writeExecutableFile(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !void {
    try helpers.writeFile(path, content);
    const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", path });
    allocator.free(chmod_stdout);
}

fn preparePtyShimBin(
    allocator: std.mem.Allocator,
    shim_bin_dir: []const u8,
    wt_bin_path: []const u8,
) !void {
    const shim_wt_path = try std.fs.path.join(allocator, &.{ shim_bin_dir, "wt" });
    defer allocator.free(shim_wt_path);
    const wt_wrapper = try std.fmt.allocPrint(
        allocator,
        "#!/bin/sh\nexec \"{s}\" \"$@\"\n",
        .{wt_bin_path},
    );
    defer allocator.free(wt_wrapper);
    try writeExecutableFile(allocator, shim_wt_path, wt_wrapper);

    const shim_fzf_path = try std.fs.path.join(allocator, &.{ shim_bin_dir, "fzf" });
    defer allocator.free(shim_fzf_path);
    try writeExecutableFile(allocator, shim_fzf_path, "#!/bin/sh\nexit 1\n");
}

fn runPtyShellNoArgScenario(
    allocator: std.mem.Allocator,
    shell: ShellRuntime,
    init_script_path: []const u8,
    cwd: []const u8,
    shim_bin_dir: []const u8,
    script_flavor: ScriptFlavor,
    stdin_input: []const u8,
) !std.process.Child.RunResult {
    const shell_program = try buildShellProgram(allocator, shell, init_script_path, "");
    defer allocator.free(shell_program);

    return runPtyShellProgramWithEnv(
        allocator,
        shell,
        shell_program,
        cwd,
        shim_bin_dir,
        script_flavor,
        stdin_input,
        &.{},
    );
}

fn runPtyShellProgramWithEnv(
    allocator: std.mem.Allocator,
    shell: ShellRuntime,
    shell_program: []const u8,
    cwd: []const u8,
    shim_bin_dir: []const u8,
    script_flavor: ScriptFlavor,
    stdin_input: []const u8,
    env_overrides: []const EnvOverride,
) !std.process.Child.RunResult {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const existing_path = env_map.get("PATH") orelse "";
    const full_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ shim_bin_dir, existing_path });
    defer allocator.free(full_path);
    try env_map.put("PATH", full_path);
    for (env_overrides) |entry| {
        try env_map.put(entry.key, entry.value);
    }

    const scenario_name = try std.fmt.allocPrint(allocator, "{s}.pty.scenario", .{shell.name});
    defer allocator.free(scenario_name);
    const scenario_path = try std.fs.path.join(allocator, &.{ shim_bin_dir, scenario_name });
    defer allocator.free(scenario_path);
    try helpers.writeFile(scenario_path, shell_program);

    var child = blk: {
        switch (script_flavor) {
            .bsd => {
                const c = std.process.Child.init(
                    &.{ "script", "-q", "/dev/null", shell.bin, scenario_path },
                    allocator,
                );
                break :blk c;
            },
            .util_linux => {
                const script_command = try std.fmt.allocPrint(allocator, "{s} {s}", .{ shell.bin, scenario_path });
                defer allocator.free(script_command);
                const c = std.process.Child.init(
                    &.{ "script", "-q", "-c", script_command, "/dev/null" },
                    allocator,
                );
                break :blk c;
            },
        }
    };

    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.cwd = cwd;
    child.env_map = &env_map;

    try child.spawn();
    {
        try child.stdin.?.deprecatedWriter().writeAll(stdin_input);
        child.stdin.?.close();
        child.stdin = null;
    }

    var stdout_buf = std.ArrayListUnmanaged(u8){};
    errdefer stdout_buf.deinit(allocator);
    var stderr_buf = std.ArrayListUnmanaged(u8){};
    errdefer stderr_buf.deinit(allocator);

    try child.collectOutput(allocator, &stdout_buf, &stderr_buf, 1024 * 1024);
    const term = try child.wait();

    return .{
        .term = term,
        .stdout = try stdout_buf.toOwnedSlice(allocator),
        .stderr = try stderr_buf.toOwnedSlice(allocator),
    };
}

fn runShellScenario(
    allocator: std.mem.Allocator,
    shell: ShellRuntime,
    init_script_path: []const u8,
    cwd: []const u8,
    stub_bin_dir: []const u8,
    invocation: []const u8,
    pick_path: ?[]const u8,
    new_path: ?[]const u8,
    log_path: []const u8,
) !std.process.Child.RunResult {
    return runShellScenarioWithEnv(
        allocator,
        shell,
        init_script_path,
        cwd,
        stub_bin_dir,
        invocation,
        pick_path,
        new_path,
        log_path,
        &.{},
    );
}

fn runShellScenarioWithEnv(
    allocator: std.mem.Allocator,
    shell: ShellRuntime,
    init_script_path: []const u8,
    cwd: []const u8,
    stub_bin_dir: []const u8,
    invocation: []const u8,
    pick_path: ?[]const u8,
    new_path: ?[]const u8,
    log_path: []const u8,
    env_overrides: []const EnvOverride,
) !std.process.Child.RunResult {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const existing_path = env_map.get("PATH") orelse "";
    const full_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ stub_bin_dir, existing_path });
    defer allocator.free(full_path);

    try env_map.put("PATH", full_path);
    try env_map.put("WT_STUB_LOG", log_path);
    if (pick_path) |value| try env_map.put("WT_STUB_PICK_PATH", value);
    if (new_path) |value| try env_map.put("WT_STUB_NEW_PATH", value);
    for (env_overrides) |entry| {
        try env_map.put(entry.key, entry.value);
    }

    const shell_program = try buildShellProgram(allocator, shell, init_script_path, invocation);
    defer allocator.free(shell_program);

    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ shell.bin, "-c", shell_program },
        .cwd = cwd,
        .env_map = &env_map,
        .max_output_bytes = 1024 * 1024,
    });
}

fn buildShellProgram(
    allocator: std.mem.Allocator,
    shell: ShellRuntime,
    init_script_path: []const u8,
    invocation: []const u8,
) ![]u8 {
    if (std.mem.eql(u8, shell.name, "nu")) {
        if (invocation.len == 0) {
            return std.fmt.allocPrint(
                allocator,
                "source \"{s}\"\nwt\nprint ('PWD=' + $env.PWD)\n",
                .{init_script_path},
            );
        }
        return std.fmt.allocPrint(
            allocator,
            "source \"{s}\"\nwt {s}\nprint ('PWD=' + $env.PWD)\n",
            .{ init_script_path, invocation },
        );
    }

    const prefix = if (std.mem.eql(u8, shell.name, "zsh")) "compdef() { :; }\n" else "";
    if (invocation.len == 0) {
        return std.fmt.allocPrint(
            allocator,
            "{s}source \"{s}\"\nwt\nprintf 'PWD=%s\\n' \"$PWD\"\n",
            .{ prefix, init_script_path },
        );
    }
    return std.fmt.allocPrint(
        allocator,
        "{s}source \"{s}\"\nwt {s}\nprintf 'PWD=%s\\n' \"$PWD\"\n",
        .{ prefix, init_script_path, invocation },
    );
}

fn buildNoArgStatusProgram(
    allocator: std.mem.Allocator,
    shell: ShellRuntime,
    init_script_path: []const u8,
) ![]u8 {
    if (std.mem.eql(u8, shell.name, "nu")) {
        return std.fmt.allocPrint(
            allocator,
            "source \"{s}\"\ntry {{ wt }} catch {{ }}\nprint ('WT_STATUS=' + ($env.LAST_EXIT_CODE | into string))\nprint ('PWD=' + $env.PWD)\n",
            .{init_script_path},
        );
    }
    if (std.mem.eql(u8, shell.name, "fish")) {
        return std.fmt.allocPrint(
            allocator,
            "source \"{s}\"\nwt\nset wt_status $status\nprintf 'WT_STATUS=%s\\n' \"$wt_status\"\nprintf 'PWD=%s\\n' \"$PWD\"\n",
            .{init_script_path},
        );
    }

    const prefix = if (std.mem.eql(u8, shell.name, "zsh")) "compdef() { :; }\n" else "";
    return std.fmt.allocPrint(
        allocator,
        "{s}source \"{s}\"\nwt\nwt_status=$?\nprintf 'WT_STATUS=%s\\n' \"$wt_status\"\nprintf 'PWD=%s\\n' \"$PWD\"\n",
        .{ prefix, init_script_path },
    );
}

fn buildInvocationStatusProgram(
    allocator: std.mem.Allocator,
    shell: ShellRuntime,
    init_script_path: []const u8,
    invocation: []const u8,
) ![]u8 {
    if (std.mem.eql(u8, shell.name, "nu")) {
        return std.fmt.allocPrint(
            allocator,
            "source \"{s}\"\ntry {{ wt {s} }} catch {{ }}\nprint ('WT_STATUS=' + ($env.LAST_EXIT_CODE | into string))\nprint ('PWD=' + $env.PWD)\n",
            .{ init_script_path, invocation },
        );
    }
    if (std.mem.eql(u8, shell.name, "fish")) {
        return std.fmt.allocPrint(
            allocator,
            "source \"{s}\"\nwt {s}\nset wt_status $status\nprintf 'WT_STATUS=%s\\n' \"$wt_status\"\nprintf 'PWD=%s\\n' \"$PWD\"\n",
            .{ init_script_path, invocation },
        );
    }

    const prefix = if (std.mem.eql(u8, shell.name, "zsh")) "compdef() { :; }\n" else "";
    return std.fmt.allocPrint(
        allocator,
        "{s}source \"{s}\"\nwt {s}\nwt_status=$?\nprintf 'WT_STATUS=%s\\n' \"$wt_status\"\nprintf 'PWD=%s\\n' \"$PWD\"\n",
        .{ prefix, init_script_path, invocation },
    );
}

fn buildCompletionProgram(
    allocator: std.mem.Allocator,
    shell: ShellRuntime,
    init_script_path: []const u8,
    query: []const u8,
) ![]u8 {
    if (std.mem.eql(u8, shell.name, "zsh")) {
        return std.fmt.allocPrint(
            allocator,
            "autoload -Uz compinit\ncompinit\nsource \"{s}\"\ncompadd() {{ shift; print -rl -- \"$@\"; }}\n_describe() {{ shift 2; print -rl -- \"$@\"; }}\nwords=({s})\nCURRENT=$#words\n_wt\n",
            .{ init_script_path, query },
        );
    }

    if (std.mem.eql(u8, shell.name, "bash")) {
        return std.fmt.allocPrint(
            allocator,
            "source \"{s}\"\nCOMP_WORDS=({s})\nCOMP_CWORD=$((${{#COMP_WORDS[@]}} - 1))\n_wt_bash_completion\nprintf '%s\\n' \"${{COMPREPLY[@]}}\"\n",
            .{ init_script_path, query },
        );
    }

    if (std.mem.eql(u8, shell.name, "fish")) {
        return std.fmt.allocPrint(
            allocator,
            "source \"{s}\"\ncomplete -C \"{s}\"\n",
            .{ init_script_path, query },
        );
    }

    return std.fmt.allocPrint(
        allocator,
        "source \"{s}\"\nnu-complete wt [{s}] | each {{|it| if (($it | describe) =~ 'record') {{ $it.value }} else {{ $it }} }} | to text\n",
        .{ init_script_path, query },
    );
}

fn buildZshCompletionTraceProgram(
    allocator: std.mem.Allocator,
    init_script_path: []const u8,
    query: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "autoload -Uz compinit\ncompinit\nsource \"{s}\"\ncompadd() {{ for arg in \"$@\"; do print -r -- \"ARG<$arg>\"; done }}\n_describe() {{ shift 2; for arg in \"$@\"; do print -r -- \"ARG<$arg>\"; done }}\nwords=({s})\nCURRENT=$#words\n_wt\n",
        .{ init_script_path, query },
    );
}

fn buildBashCompletionTraceProgram(
    allocator: std.mem.Allocator,
    init_script_path: []const u8,
    query: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "source \"{s}\"\ncompopt() {{ printf 'COMPOPT<%s %s>\\n' \"$1\" \"$2\"; }}\nCOMP_WORDS=({s})\nCOMP_CWORD=$((${{#COMP_WORDS[@]}} - 1))\n_wt_bash_completion\nprintf '%s\\n' \"${{COMPREPLY[@]}}\"\n",
        .{ init_script_path, query },
    );
}

fn runCompletionScenarioWithEnv(
    allocator: std.mem.Allocator,
    shell: ShellRuntime,
    init_script_path: []const u8,
    cwd: []const u8,
    stub_bin_dir: []const u8,
    query: []const u8,
    env_overrides: []const EnvOverride,
) !std.process.Child.RunResult {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const existing_path = env_map.get("PATH") orelse "";
    const full_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ stub_bin_dir, existing_path });
    defer allocator.free(full_path);

    try env_map.put("PATH", full_path);
    for (env_overrides) |entry| {
        try env_map.put(entry.key, entry.value);
    }

    const shell_program = try buildCompletionProgram(allocator, shell, init_script_path, query);
    defer allocator.free(shell_program);

    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ shell.bin, "-c", shell_program },
        .cwd = cwd,
        .env_map = &env_map,
        .max_output_bytes = 1024 * 1024,
    });
}

fn runZshCompletionTraceScenarioWithEnv(
    allocator: std.mem.Allocator,
    init_script_path: []const u8,
    cwd: []const u8,
    stub_bin_dir: []const u8,
    query: []const u8,
    env_overrides: []const EnvOverride,
) !std.process.Child.RunResult {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const existing_path = env_map.get("PATH") orelse "";
    const full_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ stub_bin_dir, existing_path });
    defer allocator.free(full_path);

    try env_map.put("PATH", full_path);
    for (env_overrides) |entry| {
        try env_map.put(entry.key, entry.value);
    }

    const shell_program = try buildZshCompletionTraceProgram(allocator, init_script_path, query);
    defer allocator.free(shell_program);

    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zsh", "-c", shell_program },
        .cwd = cwd,
        .env_map = &env_map,
        .max_output_bytes = 1024 * 1024,
    });
}

fn runBashCompletionTraceScenarioWithEnv(
    allocator: std.mem.Allocator,
    init_script_path: []const u8,
    cwd: []const u8,
    stub_bin_dir: []const u8,
    query: []const u8,
    env_overrides: []const EnvOverride,
) !std.process.Child.RunResult {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const existing_path = env_map.get("PATH") orelse "";
    const full_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ stub_bin_dir, existing_path });
    defer allocator.free(full_path);

    try env_map.put("PATH", full_path);
    for (env_overrides) |entry| {
        try env_map.put(entry.key, entry.value);
    }

    const shell_program = try buildBashCompletionTraceProgram(allocator, init_script_path, query);
    defer allocator.free(shell_program);

    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "bash", "-c", shell_program },
        .cwd = cwd,
        .env_map = &env_map,
        .max_output_bytes = 1024 * 1024,
    });
}

fn expectOutputContainsLine(output: []const u8, expected: []const u8) !void {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        var parts = std.mem.splitScalar(u8, trimmed, '\t');
        const candidate = parts.first();
        if (std.mem.eql(u8, candidate, expected)) return;
    }
    return error.ExpectedLineMissing;
}

fn expectOutputLacksLine(output: []const u8, unexpected: []const u8) !void {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        var parts = std.mem.splitScalar(u8, trimmed, '\t');
        const candidate = parts.first();
        if (std.mem.eql(u8, candidate, unexpected)) {
            return error.UnexpectedLinePresent;
        }
    }
}

fn runStatusShellScenarioWithEnv(
    allocator: std.mem.Allocator,
    shell: ShellRuntime,
    init_script_path: []const u8,
    cwd: []const u8,
    stub_bin_dir: []const u8,
    invocation: []const u8,
    log_path: []const u8,
    env_overrides: []const EnvOverride,
) !std.process.Child.RunResult {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const existing_path = env_map.get("PATH") orelse "";
    const full_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ stub_bin_dir, existing_path });
    defer allocator.free(full_path);

    try env_map.put("PATH", full_path);
    try env_map.put("WT_STUB_LOG", log_path);
    for (env_overrides) |entry| {
        try env_map.put(entry.key, entry.value);
    }

    const shell_program = try buildInvocationStatusProgram(allocator, shell, init_script_path, invocation);
    defer allocator.free(shell_program);

    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ shell.bin, "-c", shell_program },
        .cwd = cwd,
        .env_map = &env_map,
        .max_output_bytes = 1024 * 1024,
    });
}

fn expectExitCode(result: std.process.Child.RunResult, expected_code: u8) !void {
    switch (result.term) {
        .Exited => |code| try std.testing.expectEqual(expected_code, code),
        else => return error.UnexpectedTerm,
    }
}

test "integration: shell-init snippets carry shared parity markers across zsh/bash/fish/nu" {
    inline for ([_][]const u8{ "zsh", "bash", "fish", "nu" }) |shell| {
        const script = try requireScript(shell);
        try std.testing.expect(std.mem.indexOf(u8, script, "__pick-worktree") != null);
        try std.testing.expect(std.mem.indexOf(u8, script, "__new") != null);
        try std.testing.expect(std.mem.indexOf(u8, script, "git rev-parse --show-prefix") != null);
        try std.testing.expect(std.mem.indexOf(u8, script, "Subdirectory missing in selected worktree, using root") != null);
        try std.testing.expect(std.mem.indexOf(u8, script, "Subdirectory missing in new worktree, using root") != null);
        try std.testing.expect(std.mem.indexOf(u8, script, "Entered worktree") != null);
    }
    const nu_script = try requireScript("nu");
    try std.testing.expect(std.mem.indexOf(u8, nu_script, "^wt __pick-worktree err> /dev/tty | complete") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_script, "^wt __pick-worktree | complete") != null);
    try std.testing.expect(std.mem.indexOf(u8, nu_script, "$env.LAST_EXIT_CODE = $picked.exit_code") != null);

    try std.testing.expectEqualStrings(nu_script, try requireScript("nushell"));
}

test "integration: zsh/bash/fish/nu wrapper runtime parity for new/add flows" {
    const allocator = std.testing.allocator;
    const rel_subdir = "sub/inner";

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const stub_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(stub_bin_dir);
    try std.fs.cwd().makePath(stub_bin_dir);

    const stub_wt_path = try std.fs.path.join(allocator, &.{ stub_bin_dir, "wt" });
    defer allocator.free(stub_wt_path);
    try helpers.writeFile(stub_wt_path, stub_wt_script);
    {
        const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", stub_wt_path });
        allocator.free(chmod_stdout);
    }

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const repo_subdir = try std.fs.path.join(allocator, &.{ repo_path, rel_subdir });
    defer allocator.free(repo_subdir);
    try std.fs.cwd().makePath(repo_subdir);

    const new_with_subdir = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, new_with_subdir);
        allocator.free(new_with_subdir);
    }
    const new_subdir = try std.fs.path.join(allocator, &.{ new_with_subdir, rel_subdir });
    defer allocator.free(new_subdir);
    try std.fs.cwd().makePath(new_subdir);

    const new_root_only = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, new_root_only);
        allocator.free(new_root_only);
    }

    var ran_any_shell = false;

    for (runtime_shells) |shell| {
        if (!shellExists(allocator, shell.bin)) {
            std.debug.print("SKIP {s} runtime parity test: shell not installed\n", .{shell.name});
            continue;
        }

        ran_any_shell = true;

        const init_script = try requireScript(shell.name);
        const init_script_name = try std.fmt.allocPrint(allocator, "{s}.init", .{shell.name});
        defer allocator.free(init_script_name);
        const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, init_script_name });
        defer allocator.free(init_script_path);
        try helpers.writeFile(init_script_path, init_script);

        const new_log_name = try std.fmt.allocPrint(allocator, "{s}.new.log", .{shell.name});
        defer allocator.free(new_log_name);
        const log_new = try std.fs.path.join(allocator, &.{ temp_root, new_log_name });
        defer allocator.free(log_new);
        try helpers.writeFile(log_new, "");
        const new_preserve = try runShellScenario(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "new feat-shell-parity",
            null,
            new_with_subdir,
            log_new,
        );
        defer allocator.free(new_preserve.stdout);
        defer allocator.free(new_preserve.stderr);
        try expectExitCode(new_preserve, 0);

        const expected_new_preserve_pwd = try std.fs.path.join(allocator, &.{ new_with_subdir, rel_subdir });
        defer allocator.free(expected_new_preserve_pwd);
        const new_report = try std.fmt.allocPrint(allocator, "Entered worktree: {s}", .{new_with_subdir});
        defer allocator.free(new_report);
        const subdir_report = try std.fmt.allocPrint(allocator, "Subdirectory: {s}", .{rel_subdir});
        defer allocator.free(subdir_report);
        const new_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{expected_new_preserve_pwd});
        defer allocator.free(new_pwd_marker);
        try std.testing.expect(std.mem.indexOf(u8, new_preserve.stdout, new_report) != null);
        try std.testing.expect(std.mem.indexOf(u8, new_preserve.stdout, subdir_report) != null);
        try std.testing.expect(std.mem.indexOf(u8, new_preserve.stdout, new_pwd_marker) != null);
        const new_log = try helpers.readFileAlloc(allocator, log_new);
        defer allocator.free(new_log);
        try std.testing.expect(std.mem.indexOf(u8, new_log, "__new feat-shell-parity") != null);

        const add_log_name = try std.fmt.allocPrint(allocator, "{s}.add.log", .{shell.name});
        defer allocator.free(add_log_name);
        const log_add = try std.fs.path.join(allocator, &.{ temp_root, add_log_name });
        defer allocator.free(log_add);
        try helpers.writeFile(log_add, "");
        const add_fallback = try runShellScenario(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "add feat-shell-alias",
            null,
            new_root_only,
            log_add,
        );
        defer allocator.free(add_fallback.stdout);
        defer allocator.free(add_fallback.stderr);
        try expectExitCode(add_fallback, 0);

        const fallback_new_msg = try std.fmt.allocPrint(
            allocator,
            "Subdirectory missing in new worktree, using root: {s}",
            .{new_root_only},
        );
        defer allocator.free(fallback_new_msg);
        const new_root_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{new_root_only});
        defer allocator.free(new_root_pwd_marker);
        try std.testing.expect(std.mem.indexOf(u8, add_fallback.stdout, fallback_new_msg) != null);
        try std.testing.expect(std.mem.indexOf(u8, add_fallback.stdout, new_root_pwd_marker) != null);
        const add_log = try helpers.readFileAlloc(allocator, log_add);
        defer allocator.free(add_log);
        try std.testing.expect(std.mem.indexOf(u8, add_log, "__new feat-shell-alias") != null);
    }

    if (!ran_any_shell) {
        std.debug.print("SKIP runtime parity checks: zsh/bash/fish/nu not installed\n", .{});
    }
}

test "integration: wrapper failure paths keep cwd and surface __new stderr for zsh/bash/fish/nu" {
    const allocator = std.testing.allocator;
    const rel_subdir = "sub/inner";
    const failure_stderr = "simulated __new failure";

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const stub_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(stub_bin_dir);
    try std.fs.cwd().makePath(stub_bin_dir);

    const stub_wt_path = try std.fs.path.join(allocator, &.{ stub_bin_dir, "wt" });
    defer allocator.free(stub_wt_path);
    try helpers.writeFile(stub_wt_path, stub_wt_script);
    {
        const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", stub_wt_path });
        allocator.free(chmod_stdout);
    }

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const repo_subdir = try std.fs.path.join(allocator, &.{ repo_path, rel_subdir });
    defer allocator.free(repo_subdir);
    try std.fs.cwd().makePath(repo_subdir);

    const missing_new_path = try std.fs.path.join(allocator, &.{ temp_root, "missing-new-path" });
    defer allocator.free(missing_new_path);

    var ran_any_shell = false;

    for (runtime_shells) |shell| {
        if (!shellExists(allocator, shell.bin)) {
            std.debug.print("SKIP {s} wrapper failure-path test: shell not installed\n", .{shell.name});
            continue;
        }

        ran_any_shell = true;

        const init_script = try requireScript(shell.name);
        const init_script_name = try std.fmt.allocPrint(allocator, "{s}.failure.init", .{shell.name});
        defer allocator.free(init_script_name);
        const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, init_script_name });
        defer allocator.free(init_script_path);
        try helpers.writeFile(init_script_path, init_script);

        const unchanged_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{repo_subdir});
        defer allocator.free(unchanged_pwd_marker);

        const fail_log_name = try std.fmt.allocPrint(allocator, "{s}.new.fail.log", .{shell.name});
        defer allocator.free(fail_log_name);
        const fail_log_path = try std.fs.path.join(allocator, &.{ temp_root, fail_log_name });
        defer allocator.free(fail_log_path);
        try helpers.writeFile(fail_log_path, "");

        const failed_new = try runShellScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "new feat-failing-wrapper",
            null,
            null,
            fail_log_path,
            &.{
                .{ .key = "WT_STUB_NEW_STDERR", .value = failure_stderr },
                .{ .key = "WT_STUB_NEW_EXIT", .value = "17" },
            },
        );
        defer allocator.free(failed_new.stdout);
        defer allocator.free(failed_new.stderr);
        try expectExitCode(failed_new, 0);

        const failed_output = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ failed_new.stdout, failed_new.stderr });
        defer allocator.free(failed_output);
        try std.testing.expect(std.mem.indexOf(u8, failed_output, failure_stderr) != null);
        try std.testing.expect(std.mem.indexOf(u8, failed_new.stdout, unchanged_pwd_marker) != null);
        try std.testing.expect(std.mem.indexOf(u8, failed_new.stdout, "Entered worktree:") == null);

        const fail_log = try helpers.readFileAlloc(allocator, fail_log_path);
        defer allocator.free(fail_log);
        try std.testing.expect(std.mem.indexOf(u8, fail_log, "__new feat-failing-wrapper") != null);

        const empty_log_name = try std.fmt.allocPrint(allocator, "{s}.new.empty.log", .{shell.name});
        defer allocator.free(empty_log_name);
        const empty_log_path = try std.fs.path.join(allocator, &.{ temp_root, empty_log_name });
        defer allocator.free(empty_log_path);
        try helpers.writeFile(empty_log_path, "");

        const empty_new = try runShellScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "new feat-empty-output",
            null,
            null,
            empty_log_path,
            &.{},
        );
        defer allocator.free(empty_new.stdout);
        defer allocator.free(empty_new.stderr);
        try expectExitCode(empty_new, 0);
        try std.testing.expect(std.mem.indexOf(u8, empty_new.stdout, unchanged_pwd_marker) != null);
        try std.testing.expect(std.mem.indexOf(u8, empty_new.stdout, "Entered worktree:") == null);

        const empty_log = try helpers.readFileAlloc(allocator, empty_log_path);
        defer allocator.free(empty_log);
        try std.testing.expect(std.mem.indexOf(u8, empty_log, "__new feat-empty-output") != null);

        const missing_log_name = try std.fmt.allocPrint(allocator, "{s}.new.missing.log", .{shell.name});
        defer allocator.free(missing_log_name);
        const missing_log_path = try std.fs.path.join(allocator, &.{ temp_root, missing_log_name });
        defer allocator.free(missing_log_path);
        try helpers.writeFile(missing_log_path, "");

        const missing_new = try runShellScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "add feat-missing-output",
            null,
            missing_new_path,
            missing_log_path,
            &.{},
        );
        defer allocator.free(missing_new.stdout);
        defer allocator.free(missing_new.stderr);
        try expectExitCode(missing_new, 0);
        try std.testing.expect(std.mem.indexOf(u8, missing_new.stdout, unchanged_pwd_marker) != null);
        try std.testing.expect(std.mem.indexOf(u8, missing_new.stdout, "Entered worktree:") == null);

        const missing_log = try helpers.readFileAlloc(allocator, missing_log_path);
        defer allocator.free(missing_log);
        try std.testing.expect(std.mem.indexOf(u8, missing_log, "__new feat-missing-output") != null);
    }

    if (!ran_any_shell) {
        std.debug.print("SKIP wrapper failure-path test: zsh/bash/fish/nu not installed\n", .{});
    }
}

test "integration: zsh/bash/fish/nu wrapper runtime parity for switch flow" {
    const allocator = std.testing.allocator;
    const rel_subdir = "sub/inner";

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const stub_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(stub_bin_dir);
    try std.fs.cwd().makePath(stub_bin_dir);

    const stub_wt_path = try std.fs.path.join(allocator, &.{ stub_bin_dir, "wt" });
    defer allocator.free(stub_wt_path);
    try helpers.writeFile(stub_wt_path, stub_wt_script);
    {
        const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", stub_wt_path });
        allocator.free(chmod_stdout);
    }

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const repo_subdir = try std.fs.path.join(allocator, &.{ repo_path, rel_subdir });
    defer allocator.free(repo_subdir);
    try std.fs.cwd().makePath(repo_subdir);

    const switch_with_subdir = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, switch_with_subdir);
        allocator.free(switch_with_subdir);
    }
    const switched_subdir = try std.fs.path.join(allocator, &.{ switch_with_subdir, rel_subdir });
    defer allocator.free(switched_subdir);
    try std.fs.cwd().makePath(switched_subdir);

    const switch_root_only = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, switch_root_only);
        allocator.free(switch_root_only);
    }

    var ran_any_shell = false;

    for (runtime_shells) |shell| {
        if (!shellExists(allocator, shell.bin)) {
            std.debug.print("SKIP {s} switch runtime parity test: shell not installed\n", .{shell.name});
            continue;
        }

        ran_any_shell = true;

        const init_script = try requireScript(shell.name);
        const init_script_name = try std.fmt.allocPrint(allocator, "{s}.switch.init", .{shell.name});
        defer allocator.free(init_script_name);
        const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, init_script_name });
        defer allocator.free(init_script_path);
        try helpers.writeFile(init_script_path, init_script);

        const preserved_log_name = try std.fmt.allocPrint(allocator, "{s}.switch.preserve.log", .{shell.name});
        defer allocator.free(preserved_log_name);
        const preserved_log_path = try std.fs.path.join(allocator, &.{ temp_root, preserved_log_name });
        defer allocator.free(preserved_log_path);
        try helpers.writeFile(preserved_log_path, "");

        const preserved_switch = try runStatusShellScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "switch feat-switch-preserve",
            preserved_log_path,
            &.{.{ .key = "WT_STUB_SWITCH_PATH", .value = switch_with_subdir }},
        );
        defer allocator.free(preserved_switch.stdout);
        defer allocator.free(preserved_switch.stderr);
        try expectExitCode(preserved_switch, 0);

        const preserved_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{switched_subdir});
        defer allocator.free(preserved_pwd_marker);
        const preserved_report = try std.fmt.allocPrint(allocator, "Entered worktree: {s}", .{switch_with_subdir});
        defer allocator.free(preserved_report);
        const subdir_report = try std.fmt.allocPrint(allocator, "Subdirectory: {s}", .{rel_subdir});
        defer allocator.free(subdir_report);
        try std.testing.expect(std.mem.indexOf(u8, preserved_switch.stdout, "WT_STATUS=0") != null);
        try std.testing.expect(std.mem.indexOf(u8, preserved_switch.stdout, preserved_report) != null);
        try std.testing.expect(std.mem.indexOf(u8, preserved_switch.stdout, subdir_report) != null);
        try std.testing.expect(std.mem.indexOf(u8, preserved_switch.stdout, preserved_pwd_marker) != null);
        const preserved_log = try helpers.readFileAlloc(allocator, preserved_log_path);
        defer allocator.free(preserved_log);
        try std.testing.expect(std.mem.indexOf(u8, preserved_log, "__switch feat-switch-preserve") != null);

        const fallback_log_name = try std.fmt.allocPrint(allocator, "{s}.switch.fallback.log", .{shell.name});
        defer allocator.free(fallback_log_name);
        const fallback_log_path = try std.fs.path.join(allocator, &.{ temp_root, fallback_log_name });
        defer allocator.free(fallback_log_path);
        try helpers.writeFile(fallback_log_path, "");

        const fallback_switch = try runStatusShellScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "switch feat-switch-fallback",
            fallback_log_path,
            &.{.{ .key = "WT_STUB_SWITCH_PATH", .value = switch_root_only }},
        );
        defer allocator.free(fallback_switch.stdout);
        defer allocator.free(fallback_switch.stderr);
        try expectExitCode(fallback_switch, 0);

        const fallback_msg = try std.fmt.allocPrint(
            allocator,
            "Subdirectory missing in target worktree, using root: {s}",
            .{switch_root_only},
        );
        defer allocator.free(fallback_msg);
        const fallback_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{switch_root_only});
        defer allocator.free(fallback_pwd_marker);
        try std.testing.expect(std.mem.indexOf(u8, fallback_switch.stdout, "WT_STATUS=0") != null);
        try std.testing.expect(std.mem.indexOf(u8, fallback_switch.stdout, fallback_msg) != null);
        try std.testing.expect(std.mem.indexOf(u8, fallback_switch.stdout, fallback_pwd_marker) != null);
        const fallback_log = try helpers.readFileAlloc(allocator, fallback_log_path);
        defer allocator.free(fallback_log);
        try std.testing.expect(std.mem.indexOf(u8, fallback_log, "__switch feat-switch-fallback") != null);
    }

    if (!ran_any_shell) {
        std.debug.print("SKIP switch runtime parity checks: zsh/bash/fish/nu not installed\n", .{});
    }
}

test "integration: switch wrapper failure paths keep cwd and surface __switch stderr for zsh/bash/fish/nu" {
    const allocator = std.testing.allocator;
    const rel_subdir = "sub/inner";
    const failure_stderr = "simulated __switch failure";

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const stub_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(stub_bin_dir);
    try std.fs.cwd().makePath(stub_bin_dir);

    const stub_wt_path = try std.fs.path.join(allocator, &.{ stub_bin_dir, "wt" });
    defer allocator.free(stub_wt_path);
    try helpers.writeFile(stub_wt_path, stub_wt_script);
    {
        const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", stub_wt_path });
        allocator.free(chmod_stdout);
    }

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const repo_subdir = try std.fs.path.join(allocator, &.{ repo_path, rel_subdir });
    defer allocator.free(repo_subdir);
    try std.fs.cwd().makePath(repo_subdir);

    var ran_any_shell = false;

    for (runtime_shells) |shell| {
        if (!shellExists(allocator, shell.bin)) {
            std.debug.print("SKIP {s} switch failure-path test: shell not installed\n", .{shell.name});
            continue;
        }

        ran_any_shell = true;

        const init_script = try requireScript(shell.name);
        const init_script_name = try std.fmt.allocPrint(allocator, "{s}.switch.failure.init", .{shell.name});
        defer allocator.free(init_script_name);
        const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, init_script_name });
        defer allocator.free(init_script_path);
        try helpers.writeFile(init_script_path, init_script);

        const unchanged_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{repo_subdir});
        defer allocator.free(unchanged_pwd_marker);

        const fail_log_name = try std.fmt.allocPrint(allocator, "{s}.switch.fail.log", .{shell.name});
        defer allocator.free(fail_log_name);
        const fail_log_path = try std.fs.path.join(allocator, &.{ temp_root, fail_log_name });
        defer allocator.free(fail_log_path);
        try helpers.writeFile(fail_log_path, "");

        const failed_switch = try runStatusShellScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "switch feat-failing-switch",
            fail_log_path,
            &.{
                .{ .key = "WT_STUB_SWITCH_STDERR", .value = failure_stderr },
                .{ .key = "WT_STUB_SWITCH_EXIT", .value = "19" },
            },
        );
        defer allocator.free(failed_switch.stdout);
        defer allocator.free(failed_switch.stderr);
        try expectExitCode(failed_switch, 0);

        const failed_output = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ failed_switch.stdout, failed_switch.stderr });
        defer allocator.free(failed_output);
        try std.testing.expect(std.mem.indexOf(u8, failed_switch.stdout, "WT_STATUS=19") != null);
        try std.testing.expect(std.mem.indexOf(u8, failed_output, failure_stderr) != null);
        try std.testing.expect(std.mem.indexOf(u8, failed_switch.stdout, unchanged_pwd_marker) != null);
        try std.testing.expect(std.mem.indexOf(u8, failed_switch.stdout, "Entered worktree:") == null);
        const fail_log = try helpers.readFileAlloc(allocator, fail_log_path);
        defer allocator.free(fail_log);
        try std.testing.expect(std.mem.indexOf(u8, fail_log, "__switch feat-failing-switch") != null);

        const empty_log_name = try std.fmt.allocPrint(allocator, "{s}.switch.empty.log", .{shell.name});
        defer allocator.free(empty_log_name);
        const empty_log_path = try std.fs.path.join(allocator, &.{ temp_root, empty_log_name });
        defer allocator.free(empty_log_path);
        try helpers.writeFile(empty_log_path, "");

        const empty_switch = try runStatusShellScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "switch feat-empty-switch",
            empty_log_path,
            &.{},
        );
        defer allocator.free(empty_switch.stdout);
        defer allocator.free(empty_switch.stderr);
        try expectExitCode(empty_switch, 0);
        try std.testing.expect(std.mem.indexOf(u8, empty_switch.stdout, "WT_STATUS=0") != null);
        try std.testing.expect(std.mem.indexOf(u8, empty_switch.stdout, unchanged_pwd_marker) != null);
        try std.testing.expect(std.mem.indexOf(u8, empty_switch.stdout, "Entered worktree:") == null);
        const empty_log = try helpers.readFileAlloc(allocator, empty_log_path);
        defer allocator.free(empty_log);
        try std.testing.expect(std.mem.indexOf(u8, empty_log, "__switch feat-empty-switch") != null);
    }

    if (!ran_any_shell) {
        std.debug.print("SKIP switch failure-path test: zsh/bash/fish/nu not installed\n", .{});
    }
}

test "integration: switch help passthrough preserves cwd for zsh/bash/fish/nu" {
    const allocator = std.testing.allocator;
    const rel_subdir = "sub/inner";

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const stub_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(stub_bin_dir);
    try std.fs.cwd().makePath(stub_bin_dir);

    const stub_wt_path = try std.fs.path.join(allocator, &.{ stub_bin_dir, "wt" });
    defer allocator.free(stub_wt_path);
    try helpers.writeFile(stub_wt_path, stub_wt_script);
    {
        const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", stub_wt_path });
        allocator.free(chmod_stdout);
    }

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const repo_subdir = try std.fs.path.join(allocator, &.{ repo_path, rel_subdir });
    defer allocator.free(repo_subdir);
    try std.fs.cwd().makePath(repo_subdir);

    var ran_any_shell = false;

    for (runtime_shells) |shell| {
        if (!shellExists(allocator, shell.bin)) {
            std.debug.print("SKIP {s} switch help passthrough test: shell not installed\n", .{shell.name});
            continue;
        }

        ran_any_shell = true;

        const init_script = try requireScript(shell.name);
        const init_script_name = try std.fmt.allocPrint(allocator, "{s}.switch.help.init", .{shell.name});
        defer allocator.free(init_script_name);
        const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, init_script_name });
        defer allocator.free(init_script_path);
        try helpers.writeFile(init_script_path, init_script);

        const help_log_name = try std.fmt.allocPrint(allocator, "{s}.switch.help.log", .{shell.name});
        defer allocator.free(help_log_name);
        const help_log_path = try std.fs.path.join(allocator, &.{ temp_root, help_log_name });
        defer allocator.free(help_log_path);
        try helpers.writeFile(help_log_path, "");

        const help_result = try runStatusShellScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "switch --help",
            help_log_path,
            &.{},
        );
        defer allocator.free(help_result.stdout);
        defer allocator.free(help_result.stderr);
        try expectExitCode(help_result, 0);

        const unchanged_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{repo_subdir});
        defer allocator.free(unchanged_pwd_marker);
        try std.testing.expect(std.mem.indexOf(u8, help_result.stdout, "WT_STATUS=0") != null);
        try std.testing.expect(std.mem.indexOf(u8, help_result.stdout, unchanged_pwd_marker) != null);
        try std.testing.expect(std.mem.indexOf(u8, help_result.stdout, "Entered worktree:") == null);

        const help_log = try helpers.readFileAlloc(allocator, help_log_path);
        defer allocator.free(help_log);
        try std.testing.expect(std.mem.indexOf(u8, help_log, "switch --help") != null);
    }

    if (!ran_any_shell) {
        std.debug.print("SKIP switch help passthrough test: zsh/bash/fish/nu not installed\n", .{});
    }
}

test "integration: non-interactive bare wt passes through without picker for zsh/bash/fish/nu" {
    const allocator = std.testing.allocator;
    const rel_subdir = "sub/inner";
    const passthrough_error = "passthrough from stub";
    const passthrough_exit = "23";

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const stub_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(stub_bin_dir);
    try std.fs.cwd().makePath(stub_bin_dir);

    const stub_wt_path = try std.fs.path.join(allocator, &.{ stub_bin_dir, "wt" });
    defer allocator.free(stub_wt_path);
    try helpers.writeFile(stub_wt_path, stub_wt_script);
    {
        const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", stub_wt_path });
        allocator.free(chmod_stdout);
    }

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }
    const repo_subdir = try std.fs.path.join(allocator, &.{ repo_path, rel_subdir });
    defer allocator.free(repo_subdir);
    try std.fs.cwd().makePath(repo_subdir);

    var ran_any_shell = false;

    for (runtime_shells) |shell| {
        if (!shellExists(allocator, shell.bin)) {
            std.debug.print("SKIP {s} non-interactive pass-through test: shell not installed\n", .{shell.name});
            continue;
        }

        ran_any_shell = true;

        const init_script = try requireScript(shell.name);
        const init_script_name = try std.fmt.allocPrint(allocator, "{s}.noarg.pass.init", .{shell.name});
        defer allocator.free(init_script_name);
        const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, init_script_name });
        defer allocator.free(init_script_path);
        try helpers.writeFile(init_script_path, init_script);

        const log_name = try std.fmt.allocPrint(allocator, "{s}.noarg.pass.log", .{shell.name});
        defer allocator.free(log_name);
        const log_path = try std.fs.path.join(allocator, &.{ temp_root, log_name });
        defer allocator.free(log_path);
        try helpers.writeFile(log_path, "");

        var env_map = try std.process.getEnvMap(allocator);
        defer env_map.deinit();

        const existing_path = env_map.get("PATH") orelse "";
        const full_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ stub_bin_dir, existing_path });
        defer allocator.free(full_path);

        try env_map.put("PATH", full_path);
        try env_map.put("WT_STUB_LOG", log_path);
        try env_map.put("WT_STUB_DEFAULT_STDERR", passthrough_error);
        try env_map.put("WT_STUB_DEFAULT_EXIT", passthrough_exit);

        const shell_program = try buildNoArgStatusProgram(allocator, shell, init_script_path);
        defer allocator.free(shell_program);

        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ shell.bin, "-c", shell_program },
            .cwd = repo_subdir,
            .env_map = &env_map,
            .max_output_bytes = 1024 * 1024,
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try expectExitCode(result, 0);

        const status_marker = try std.fmt.allocPrint(allocator, "WT_STATUS={s}", .{passthrough_exit});
        defer allocator.free(status_marker);
        const pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{repo_subdir});
        defer allocator.free(pwd_marker);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, status_marker) != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, pwd_marker) != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Entered worktree:") == null);

        const combined_output = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ result.stdout, result.stderr });
        defer allocator.free(combined_output);
        try std.testing.expect(std.mem.indexOf(u8, combined_output, passthrough_error) != null);

        const log_data = try helpers.readFileAlloc(allocator, log_path);
        defer allocator.free(log_data);
        try std.testing.expect(std.mem.indexOf(u8, log_data, "__pick-worktree") == null);
    }

    if (!ran_any_shell) {
        std.debug.print("SKIP non-interactive pass-through test: zsh/bash/fish/nu not installed\n", .{});
    }
}

test "integration: PTY no-arg shell-init picker cancel works for zsh/bash/nu" {
    const allocator = std.testing.allocator;
    const rel_subdir = "sub/inner";
    const cancel_input = "q\n";
    const test_branch = "feat-pty-picker";

    const wt_bin_path = (try resolveWtBinaryPath(allocator)) orelse {
        std.debug.print("SKIP PTY picker test: WT_TEST_WT_BIN is missing or unresolved\n", .{});
        return;
    };
    defer allocator.free(wt_bin_path);

    const script_flavor = detectScriptFlavor(allocator) orelse {
        std.debug.print("SKIP PTY picker test: `script` command not available\n", .{});
        return;
    };

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const shim_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(shim_bin_dir);
    try std.fs.cwd().makePath(shim_bin_dir);
    try preparePtyShimBin(allocator, shim_bin_dir, wt_bin_path);

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const repo_subdir = try std.fs.path.join(allocator, &.{ repo_path, rel_subdir });
    defer allocator.free(repo_subdir);
    try std.fs.cwd().makePath(repo_subdir);

    const secondary_path = try std.fs.path.join(allocator, &.{ temp_root, "repo--feat-pty-picker" });
    defer allocator.free(secondary_path);
    {
        const add_worktree_output = try helpers.runChecked(
            allocator,
            repo_path,
            &.{ "git", "worktree", "add", "-b", test_branch, secondary_path },
        );
        allocator.free(add_worktree_output);
    }

    var ran_any_shell = false;

    for (pty_runtime_shells) |shell| {
        if (!shellExists(allocator, shell.bin)) {
            std.debug.print("SKIP {s} PTY picker test: shell not installed\n", .{shell.name});
            continue;
        }

        ran_any_shell = true;

        const init_script = try requireScript(shell.name);
        const init_script_name = try std.fmt.allocPrint(allocator, "{s}.pty.init", .{shell.name});
        defer allocator.free(init_script_name);
        const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, init_script_name });
        defer allocator.free(init_script_path);
        try helpers.writeFile(init_script_path, init_script);

        const result = try runPtyShellNoArgScenario(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            shim_bin_dir,
            script_flavor,
            cancel_input,
        );
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try expectExitCode(result, 0);

        const combined_output = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ result.stdout, result.stderr });
        defer allocator.free(combined_output);
        const unchanged_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{repo_subdir});
        defer allocator.free(unchanged_pwd_marker);

        try std.testing.expect(std.mem.indexOf(u8, combined_output, "Choose a worktree:") != null);
        try std.testing.expect(std.mem.indexOf(u8, combined_output, "Select worktree [1-") != null);
        try std.testing.expect(std.mem.indexOf(u8, combined_output, test_branch) != null);
        try std.testing.expect(std.mem.indexOf(u8, combined_output, unchanged_pwd_marker) != null);
    }

    if (!ran_any_shell) {
        std.debug.print("SKIP PTY picker test: zsh/bash/nu not installed\n", .{});
    }
}

test "integration: nushell PTY no-arg picker fallback preserves stderr, status, and cwd" {
    const allocator = std.testing.allocator;
    const rel_subdir = "sub/inner";
    const picker_stderr = "picker stderr from fallback";
    const picker_exit_code = "130";

    if (!shellExists(allocator, "nu")) {
        std.debug.print("SKIP nu PTY fallback test: shell not installed\n", .{});
        return;
    }

    const script_flavor = detectScriptFlavor(allocator) orelse {
        std.debug.print("SKIP nu PTY fallback test: `script` command not available\n", .{});
        return;
    };

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const stub_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(stub_bin_dir);
    try std.fs.cwd().makePath(stub_bin_dir);

    const stub_wt_path = try std.fs.path.join(allocator, &.{ stub_bin_dir, "wt" });
    defer allocator.free(stub_wt_path);
    try helpers.writeFile(stub_wt_path, stub_wt_script);
    {
        const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", stub_wt_path });
        allocator.free(chmod_stdout);
    }

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const repo_subdir = try std.fs.path.join(allocator, &.{ repo_path, rel_subdir });
    defer allocator.free(repo_subdir);
    try std.fs.cwd().makePath(repo_subdir);

    const init_script = try requireScript("nu");
    const fallback_tty_path = "/dev/wt-missing-tty-for-test";
    const fallback_source = "^wt __pick-worktree err> /dev/tty | complete";
    const forced_fallback_source = try std.fmt.allocPrint(
        allocator,
        "^wt __pick-worktree err> {s} | complete",
        .{fallback_tty_path},
    );
    defer allocator.free(forced_fallback_source);
    const forced_init_script = try std.mem.replaceOwned(
        u8,
        allocator,
        init_script,
        fallback_source,
        forced_fallback_source,
    );
    defer allocator.free(forced_init_script);
    try std.testing.expect(std.mem.indexOf(u8, forced_init_script, forced_fallback_source) != null);
    try std.testing.expect(std.mem.indexOf(u8, forced_init_script, fallback_source) == null);

    const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, "nu.pty.fallback.init" });
    defer allocator.free(init_script_path);
    try helpers.writeFile(init_script_path, forced_init_script);

    const log_path = try std.fs.path.join(allocator, &.{ temp_root, "nu.pty.fallback.log" });
    defer allocator.free(log_path);
    try helpers.writeFile(log_path, "");

    const shell: ShellRuntime = .{ .name = "nu", .bin = "nu" };
    const shell_program = try buildNoArgStatusProgram(allocator, shell, init_script_path);
    defer allocator.free(shell_program);
    const result = try runPtyShellProgramWithEnv(
        allocator,
        shell,
        shell_program,
        repo_subdir,
        stub_bin_dir,
        script_flavor,
        "",
        &.{
            .{ .key = "WT_STUB_LOG", .value = log_path },
            .{ .key = "WT_STUB_PICK_STDERR", .value = picker_stderr },
            .{ .key = "WT_STUB_PICK_EXIT", .value = picker_exit_code },
        },
    );
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try expectExitCode(result, 0);

    const status_marker = try std.fmt.allocPrint(allocator, "WT_STATUS={s}", .{picker_exit_code});
    defer allocator.free(status_marker);
    const unchanged_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{repo_subdir});
    defer allocator.free(unchanged_pwd_marker);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, status_marker) != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, unchanged_pwd_marker) != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Entered worktree:") == null);

    const combined_output = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined_output);
    try std.testing.expect(std.mem.indexOf(u8, combined_output, picker_stderr) != null);

    const log_data = try helpers.readFileAlloc(allocator, log_path);
    defer allocator.free(log_data);
    try std.testing.expect(std.mem.indexOf(u8, log_data, "__pick-worktree") != null);
}

test "integration: nushell non-interactive bare wt passthrough preserves LAST_EXIT_CODE and cwd" {
    const allocator = std.testing.allocator;
    const rel_subdir = "sub/inner";

    if (!shellExists(allocator, "nu")) {
        std.debug.print("SKIP nu non-interactive pass-through test: shell not installed\n", .{});
        return;
    }

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const stub_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(stub_bin_dir);
    try std.fs.cwd().makePath(stub_bin_dir);

    const stub_wt_path = try std.fs.path.join(allocator, &.{ stub_bin_dir, "wt" });
    defer allocator.free(stub_wt_path);
    try helpers.writeFile(stub_wt_path, stub_wt_script);
    {
        const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", stub_wt_path });
        allocator.free(chmod_stdout);
    }

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }
    const repo_subdir = try std.fs.path.join(allocator, &.{ repo_path, rel_subdir });
    defer allocator.free(repo_subdir);
    try std.fs.cwd().makePath(repo_subdir);

    const init_script = try requireScript("nu");
    const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, "nu.noarg.pass.init" });
    defer allocator.free(init_script_path);
    try helpers.writeFile(init_script_path, init_script);

    const passthrough_error = "passthrough from stub";
    const passthrough_exit_code = "23";

    const log_path = try std.fs.path.join(allocator, &.{ temp_root, "nu.noarg.pass.log" });
    defer allocator.free(log_path);
    try helpers.writeFile(log_path, "");

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const existing_path = env_map.get("PATH") orelse "";
    const full_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ stub_bin_dir, existing_path });
    defer allocator.free(full_path);

    try env_map.put("PATH", full_path);
    try env_map.put("WT_STUB_LOG", log_path);
    try env_map.put("WT_STUB_DEFAULT_STDERR", passthrough_error);
    try env_map.put("WT_STUB_DEFAULT_EXIT", passthrough_exit_code);

    const shell_program = try std.fmt.allocPrint(
        allocator,
        "source \"{s}\"\ntry {{ wt }} catch {{ }}\nprint ('LAST_EXIT_CODE=' + ($env.LAST_EXIT_CODE | into string))\nprint ('PWD=' + $env.PWD)\n",
        .{init_script_path},
    );
    defer allocator.free(shell_program);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "nu", "-c", shell_program },
        .cwd = repo_subdir,
        .env_map = &env_map,
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try expectExitCode(result, 0);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "LAST_EXIT_CODE=23") != null);
    const unchanged_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{repo_subdir});
    defer allocator.free(unchanged_pwd_marker);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, unchanged_pwd_marker) != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Entered worktree:") == null);

    const combined_output = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined_output);
    try std.testing.expect(std.mem.indexOf(u8, combined_output, passthrough_error) != null);

    const log_data = try helpers.readFileAlloc(allocator, log_path);
    defer allocator.free(log_data);
    try std.testing.expect(std.mem.indexOf(u8, log_data, "__pick-worktree") == null);
}

// This test checks the candidate sets each shell adapter returns.
// It intentionally does not verify shell-specific insertion behavior such as
// whether selecting `github/` appends a trailing space.
test "integration: shell completion parity covers candidate text for partial branches flags and aliases" {
    const allocator = std.testing.allocator;

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const stub_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(stub_bin_dir);
    try std.fs.cwd().makePath(stub_bin_dir);

    const stub_wt_path = try std.fs.path.join(allocator, &.{ stub_bin_dir, "wt" });
    defer allocator.free(stub_wt_path);
    try helpers.writeFile(stub_wt_path, stub_wt_script);
    {
        const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", stub_wt_path });
        allocator.free(chmod_stdout);
    }

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const completion_env = [_]EnvOverride{
        .{ .key = "WT_STUB_COMPLETE_WORKTREE_BRANCHES", .value = "somename\nsomething-else" },
        .{ .key = "WT_STUB_COMPLETE_LOCAL_BRANCHES", .value = "feature-a\nfeature-b" },
        .{ .key = "WT_STUB_COMPLETE_BRANCH_TARGETS_ROOT", .value = "feature-a\nfeature-b\ngithub/\norigin/\nupstream/" },
        .{ .key = "WT_STUB_COMPLETE_BRANCH_TARGETS_REMOTE", .value = "origin/feature/remote-one\norigin/feature/remote-two" },
        .{ .key = "WT_STUB_COMPLETE_REFS", .value = "origin/main\nupstream/topic" },
    };

    var ran_any_shell = false;

    for (runtime_shells) |shell| {
        if (!shellExists(allocator, shell.bin)) {
            std.debug.print("SKIP {s} completion parity test: shell not installed\n", .{shell.name});
            continue;
        }

        ran_any_shell = true;
        const shell_filters_candidates = std.mem.eql(u8, shell.name, "bash") or std.mem.eql(u8, shell.name, "fish");

        const init_script = try requireScript(shell.name);
        const init_script_name = try std.fmt.allocPrint(allocator, "{s}.completion.init", .{shell.name});
        defer allocator.free(init_script_name);
        const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, init_script_name });
        defer allocator.free(init_script_path);
        try helpers.writeFile(init_script_path, init_script);

        const switch_result = try runCompletionScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_path,
            stub_bin_dir,
            "wt switch somen",
            &completion_env,
        );
        defer allocator.free(switch_result.stdout);
        defer allocator.free(switch_result.stderr);
        try expectExitCode(switch_result, 0);
        try expectOutputContainsLine(switch_result.stdout, "somename");
        if (shell_filters_candidates) {
            try expectOutputLacksLine(switch_result.stdout, "something-else");
        }

        const rm_result = try runCompletionScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_path,
            stub_bin_dir,
            "wt rm somen",
            &completion_env,
        );
        defer allocator.free(rm_result.stdout);
        defer allocator.free(rm_result.stderr);
        try expectExitCode(rm_result, 0);
        try expectOutputContainsLine(rm_result.stdout, "somename");
        if (shell_filters_candidates) {
            try expectOutputLacksLine(rm_result.stdout, "something-else");
        }

        const new_branch_target_result = try runCompletionScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_path,
            stub_bin_dir,
            "wt add or",
            &completion_env,
        );
        defer allocator.free(new_branch_target_result.stdout);
        defer allocator.free(new_branch_target_result.stderr);
        try expectExitCode(new_branch_target_result, 0);
        try expectOutputContainsLine(new_branch_target_result.stdout, "origin/");
        if (shell_filters_candidates) {
            try expectOutputLacksLine(new_branch_target_result.stdout, "upstream/");
            try expectOutputLacksLine(new_branch_target_result.stdout, "feature-a");
        }

        const github_branch_target_result = try runCompletionScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_path,
            stub_bin_dir,
            "wt add gith",
            &completion_env,
        );
        defer allocator.free(github_branch_target_result.stdout);
        defer allocator.free(github_branch_target_result.stderr);
        try expectExitCode(github_branch_target_result, 0);
        try expectOutputContainsLine(github_branch_target_result.stdout, "github/");
        if (shell_filters_candidates) {
            try expectOutputLacksLine(github_branch_target_result.stdout, "origin/");
        }

        const remote_branch_target_result = try runCompletionScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_path,
            stub_bin_dir,
            "wt add origin/fe",
            &completion_env,
        );
        defer allocator.free(remote_branch_target_result.stdout);
        defer allocator.free(remote_branch_target_result.stderr);
        try expectExitCode(remote_branch_target_result, 0);
        try expectOutputContainsLine(remote_branch_target_result.stdout, "origin/feature/remote-one");
        try expectOutputLacksLine(remote_branch_target_result.stdout, "upstream/");

        const root_flag_result = try runCompletionScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_path,
            stub_bin_dir,
            "wt --v",
            &completion_env,
        );
        defer allocator.free(root_flag_result.stdout);
        defer allocator.free(root_flag_result.stderr);
        try expectExitCode(root_flag_result, 0);
        try expectOutputContainsLine(root_flag_result.stdout, "--version");
        if (shell_filters_candidates) {
            try expectOutputLacksLine(root_flag_result.stdout, "--help");
        }

        const rm_flag_result = try runCompletionScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_path,
            stub_bin_dir,
            "wt rm --",
            &completion_env,
        );
        defer allocator.free(rm_flag_result.stdout);
        defer allocator.free(rm_flag_result.stderr);
        try expectExitCode(rm_flag_result, 0);
        try expectOutputContainsLine(rm_flag_result.stdout, "--picker");
        try expectOutputContainsLine(rm_flag_result.stdout, "--force");

        const rm_force_flag_result = try runCompletionScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_path,
            stub_bin_dir,
            "wt rm --f",
            &completion_env,
        );
        defer allocator.free(rm_force_flag_result.stdout);
        defer allocator.free(rm_force_flag_result.stderr);
        try expectExitCode(rm_force_flag_result, 0);
        try expectOutputContainsLine(rm_force_flag_result.stdout, "--force");
        if (shell_filters_candidates) {
            try expectOutputLacksLine(rm_force_flag_result.stdout, "--picker");
        }

        const picker_value_result = try runCompletionScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_path,
            stub_bin_dir,
            "wt rm --picker b",
            &completion_env,
        );
        defer allocator.free(picker_value_result.stdout);
        defer allocator.free(picker_value_result.stderr);
        try expectExitCode(picker_value_result, 0);
        try expectOutputContainsLine(picker_value_result.stdout, "builtin");
        if (shell_filters_candidates) {
            try expectOutputLacksLine(picker_value_result.stdout, "auto");
        }

        const alias_result = try runCompletionScenarioWithEnv(
            allocator,
            shell,
            init_script_path,
            repo_path,
            stub_bin_dir,
            "wt ls --",
            &completion_env,
        );
        defer allocator.free(alias_result.stdout);
        defer allocator.free(alias_result.stderr);
        try expectExitCode(alias_result, 0);
        try expectOutputContainsLine(alias_result.stdout, "--help");
    }

    if (!ran_any_shell) {
        std.debug.print("SKIP completion parity test: zsh/bash/fish/nu not installed\n", .{});
    }
}

// This is narrower than the cross-shell parity test above: it verifies zsh's
// insertion behavior by tracing the exact compadd arguments used for a remote
// prefix candidate.
test "integration: zsh remote branch target completion suppresses trailing space for remote prefixes" {
    const allocator = std.testing.allocator;

    if (!shellExists(allocator, "zsh")) {
        std.debug.print("SKIP zsh completion suffix test: zsh not installed\n", .{});
        return;
    }

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const stub_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(stub_bin_dir);
    try std.fs.cwd().makePath(stub_bin_dir);

    const stub_wt_path = try std.fs.path.join(allocator, &.{ stub_bin_dir, "wt" });
    defer allocator.free(stub_wt_path);
    try helpers.writeFile(stub_wt_path, stub_wt_script);
    const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", stub_wt_path });
    defer allocator.free(chmod_stdout);

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const init_script = try requireScript("zsh");
    const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, "zsh.trace.init" });
    defer allocator.free(init_script_path);
    try helpers.writeFile(init_script_path, init_script);

    const completion_env = [_]EnvOverride{
        .{ .key = "WT_STUB_COMPLETE_BRANCH_TARGETS_ROOT", .value = "github/\nfeature-a" },
    };

    const result = try runZshCompletionTraceScenarioWithEnv(
        allocator,
        init_script_path,
        repo_path,
        stub_bin_dir,
        "wt add gith",
        &completion_env,
    );
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExitCode(result, 0);
    try expectOutputContainsLine(result.stdout, "ARG<-S>");
    try expectOutputContainsLine(result.stdout, "ARG<>");
    try expectOutputContainsLine(result.stdout, "ARG<-->");
    try expectOutputContainsLine(result.stdout, "ARG<github/>");
}

// This is narrower than the cross-shell parity test above: it verifies bash's
// insertion behavior by tracing the compopt call that keeps readline from
// appending a trailing space after a remote prefix candidate.
test "integration: bash remote branch target completion requests nospace for remote prefixes" {
    const allocator = std.testing.allocator;

    if (!shellExists(allocator, "bash")) {
        std.debug.print("SKIP bash completion suffix test: bash not installed\n", .{});
        return;
    }

    const temp_root = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_root);
        allocator.free(temp_root);
    }

    const stub_bin_dir = try std.fs.path.join(allocator, &.{ temp_root, "bin" });
    defer allocator.free(stub_bin_dir);
    try std.fs.cwd().makePath(stub_bin_dir);

    const stub_wt_path = try std.fs.path.join(allocator, &.{ stub_bin_dir, "wt" });
    defer allocator.free(stub_wt_path);
    try helpers.writeFile(stub_wt_path, stub_wt_script);
    const chmod_stdout = try helpers.runChecked(allocator, null, &.{ "chmod", "+x", stub_wt_path });
    defer allocator.free(chmod_stdout);

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const init_script = try requireScript("bash");
    const init_script_path = try std.fs.path.join(allocator, &.{ temp_root, "bash.trace.init" });
    defer allocator.free(init_script_path);
    try helpers.writeFile(init_script_path, init_script);

    const completion_env = [_]EnvOverride{
        .{ .key = "WT_STUB_COMPLETE_BRANCH_TARGETS_ROOT", .value = "github/\nfeature-a" },
    };

    const result = try runBashCompletionTraceScenarioWithEnv(
        allocator,
        init_script_path,
        repo_path,
        stub_bin_dir,
        "wt add gith",
        &completion_env,
    );
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExitCode(result, 0);
    try expectOutputContainsLine(result.stdout, "COMPOPT<-o nospace>");
    try expectOutputContainsLine(result.stdout, "github/");
}

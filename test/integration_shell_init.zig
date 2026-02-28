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
    .{ .name = "nu", .bin = "nu" },
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
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const existing_path = env_map.get("PATH") orelse "";
    const full_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ shim_bin_dir, existing_path });
    defer allocator.free(full_path);
    try env_map.put("PATH", full_path);

    const shell_program = try buildShellProgram(allocator, shell, init_script_path, "");
    defer allocator.free(shell_program);

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
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const existing_path = env_map.get("PATH") orelse "";
    const full_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ stub_bin_dir, existing_path });
    defer allocator.free(full_path);

    try env_map.put("PATH", full_path);
    try env_map.put("WT_STUB_LOG", log_path);
    if (pick_path) |value| try env_map.put("WT_STUB_PICK_PATH", value);
    if (new_path) |value| try env_map.put("WT_STUB_NEW_PATH", value);

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

    const prefix = if (std.mem.eql(u8, shell.name, "zsh")) "compdef() { :; }\n" else "";
    return std.fmt.allocPrint(
        allocator,
        "{s}source \"{s}\"\nwt\nwt_status=$?\nprintf 'WT_STATUS=%s\\n' \"$wt_status\"\nprintf 'PWD=%s\\n' \"$PWD\"\n",
        .{ prefix, init_script_path },
    );
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

test "integration: zsh/bash/nu wrapper runtime parity for new/add flows" {
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
        std.debug.print("SKIP runtime parity checks: zsh/bash/nu not installed\n", .{});
    }
}

test "integration: non-interactive bare wt passes through without picker for zsh/bash/nu" {
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
        std.debug.print("SKIP non-interactive pass-through test: zsh/bash/nu not installed\n", .{});
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

    for (runtime_shells) |shell| {
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

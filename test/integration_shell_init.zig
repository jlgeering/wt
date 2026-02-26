const std = @import("std");

const helpers = @import("helpers.zig");
const shell_init = @import("wt_root").cmd_shell_init;

const ShellRuntime = struct {
    name: []const u8,
    bin: []const u8,
};

const runtime_shells = [_]ShellRuntime{
    .{ .name = "zsh", .bin = "zsh" },
    .{ .name = "bash", .bin = "bash" },
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
    \\    if [ -n "${WT_STUB_PICK_PATH:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_PICK_PATH"
    \\    fi
    \\    ;;
    \\  __new)
    \\    shift || true
    \\    if [ -n "${WT_STUB_NEW_PATH:-}" ]; then
    \\      printf '%s\n' "$WT_STUB_NEW_PATH"
    \\    fi
    \\    ;;
    \\  *)
    \\    ;;
    \\esac
;

fn requireScript(shell: []const u8) ![]const u8 {
    return shell_init.scriptForShell(shell) orelse return error.MissingShellScript;
}

fn shellExists(allocator: std.mem.Allocator, shell_bin: []const u8) bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ shell_bin, "-c", "exit 0" },
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

    const prefix = if (std.mem.eql(u8, shell.name, "zsh")) "compdef() { :; }\n" else "";
    const shell_program = try std.fmt.allocPrint(
        allocator,
        "{s}source \"{s}\"\nwt {s}\nprintf 'PWD=%s\\n' \"$PWD\"\n",
        .{ prefix, init_script_path, invocation },
    );
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
    try std.testing.expectEqualStrings(try requireScript("nu"), try requireScript("nushell"));
}

test "integration: zsh/bash wrapper runtime parity for picker and new/add flows" {
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

    const selected_with_subdir = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, selected_with_subdir);
        allocator.free(selected_with_subdir);
    }
    const selected_subdir = try std.fs.path.join(allocator, &.{ selected_with_subdir, rel_subdir });
    defer allocator.free(selected_subdir);
    try std.fs.cwd().makePath(selected_subdir);

    const selected_root_only = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, selected_root_only);
        allocator.free(selected_root_only);
    }

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

        const noarg_preserve_log_name = try std.fmt.allocPrint(allocator, "{s}.noarg-preserve.log", .{shell.name});
        defer allocator.free(noarg_preserve_log_name);
        const log_noarg_preserve = try std.fs.path.join(allocator, &.{ temp_root, noarg_preserve_log_name });
        defer allocator.free(log_noarg_preserve);
        try helpers.writeFile(log_noarg_preserve, "");
        const noarg_preserve = try runShellScenario(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "",
            selected_with_subdir,
            null,
            log_noarg_preserve,
        );
        defer allocator.free(noarg_preserve.stdout);
        defer allocator.free(noarg_preserve.stderr);
        try expectExitCode(noarg_preserve, 0);

        const expected_selected_preserve_pwd = try std.fs.path.join(allocator, &.{ selected_with_subdir, rel_subdir });
        defer allocator.free(expected_selected_preserve_pwd);
        const selected_report = try std.fmt.allocPrint(allocator, "Entered worktree: {s}", .{selected_with_subdir});
        defer allocator.free(selected_report);
        const subdir_report = try std.fmt.allocPrint(allocator, "Subdirectory: {s}", .{rel_subdir});
        defer allocator.free(subdir_report);
        const selected_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{expected_selected_preserve_pwd});
        defer allocator.free(selected_pwd_marker);
        try std.testing.expect(std.mem.indexOf(u8, noarg_preserve.stdout, selected_report) != null);
        try std.testing.expect(std.mem.indexOf(u8, noarg_preserve.stdout, subdir_report) != null);
        try std.testing.expect(std.mem.indexOf(u8, noarg_preserve.stdout, selected_pwd_marker) != null);
        const noarg_log = try helpers.readFileAlloc(allocator, log_noarg_preserve);
        defer allocator.free(noarg_log);
        try std.testing.expect(std.mem.indexOf(u8, noarg_log, "__pick-worktree") != null);

        const noarg_fallback_log_name = try std.fmt.allocPrint(allocator, "{s}.noarg-fallback.log", .{shell.name});
        defer allocator.free(noarg_fallback_log_name);
        const log_noarg_fallback = try std.fs.path.join(allocator, &.{ temp_root, noarg_fallback_log_name });
        defer allocator.free(log_noarg_fallback);
        try helpers.writeFile(log_noarg_fallback, "");
        const noarg_fallback = try runShellScenario(
            allocator,
            shell,
            init_script_path,
            repo_subdir,
            stub_bin_dir,
            "",
            selected_root_only,
            null,
            log_noarg_fallback,
        );
        defer allocator.free(noarg_fallback.stdout);
        defer allocator.free(noarg_fallback.stderr);
        try expectExitCode(noarg_fallback, 0);

        const fallback_selected_msg = try std.fmt.allocPrint(
            allocator,
            "Subdirectory missing in selected worktree, using root: {s}",
            .{selected_root_only},
        );
        defer allocator.free(fallback_selected_msg);
        const selected_root_pwd_marker = try std.fmt.allocPrint(allocator, "PWD={s}", .{selected_root_only});
        defer allocator.free(selected_root_pwd_marker);
        try std.testing.expect(std.mem.indexOf(u8, noarg_fallback.stdout, fallback_selected_msg) != null);
        try std.testing.expect(std.mem.indexOf(u8, noarg_fallback.stdout, selected_root_pwd_marker) != null);

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
        std.debug.print("SKIP runtime parity checks: zsh/bash not installed\n", .{});
    }
}

const std = @import("std");
const builtin = @import("builtin");

const wt_lib = @import("wt_lib");
const git = wt_lib.git;
const config = wt_lib.config;
const setup = wt_lib.setup;
const worktree = wt_lib.worktree;
const helpers = @import("helpers.zig");

fn expectBranchExists(repo_path: []const u8, branch: []const u8) !void {
    const allocator = std.testing.allocator;
    const out = try git.runGit(allocator, repo_path, &.{ "rev-parse", "--verify", branch });
    allocator.free(out);
}

fn expectBranchMissing(repo_path: []const u8, branch: []const u8) !void {
    const allocator = std.testing.allocator;
    if (git.runGit(allocator, repo_path, &.{ "rev-parse", "--verify", branch })) |out| {
        allocator.free(out);
        return error.BranchShouldNotExist;
    } else |err| {
        try std.testing.expectEqual(error.GitCommandFailed, err);
    }
}

fn expectUpstream(repo_path: []const u8, branch: []const u8, expected_upstream: []const u8) !void {
    const allocator = std.testing.allocator;
    const upstream_ref = try std.fmt.allocPrint(allocator, "{s}@{{upstream}}", .{branch});
    defer allocator.free(upstream_ref);

    const out = try git.runGit(
        allocator,
        repo_path,
        &.{ "rev-parse", "--abbrev-ref", "--symbolic-full-name", upstream_ref },
    );
    defer allocator.free(out);

    try std.testing.expectEqualStrings(expected_upstream, std.mem.trim(u8, out, " \t\r\n"));
}

const CliResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,

    fn deinit(self: CliResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

fn runWt(allocator: std.mem.Allocator, wt_bin: []const u8, cwd: []const u8, argv: []const []const u8) !CliResult {
    var full_argv = std.array_list.Managed([]const u8).init(allocator);
    defer full_argv.deinit();

    try full_argv.append(wt_bin);
    try full_argv.appendSlice(argv);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = full_argv.items,
        .cwd = cwd,
    });

    const exit_code = switch (result.term) {
        .Exited => |code| code,
        else => return error.UnexpectedTermination,
    };

    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = exit_code,
    };
}

fn createBareRemoteRepo(allocator: std.mem.Allocator) ![]u8 {
    const remote_path = try helpers.createTempDir(allocator);
    errdefer {
        helpers.cleanupPath(allocator, remote_path);
        allocator.free(remote_path);
    }

    const init_remote_output = try helpers.runChecked(allocator, null, &.{ "git", "init", "--bare", remote_path });
    allocator.free(init_remote_output);
    return remote_path;
}

fn addRemote(repo_path: []const u8, remote_name: []const u8, remote_path: []const u8) !void {
    const allocator = std.testing.allocator;
    const add_remote_output = try helpers.runChecked(
        allocator,
        repo_path,
        &.{ "git", "remote", "add", remote_name, remote_path },
    );
    allocator.free(add_remote_output);
}

fn createRemoteOnlyBranch(repo_path: []const u8, remote_name: []const u8, branch: []const u8) !void {
    const allocator = std.testing.allocator;

    const create_branch_output = try helpers.runChecked(
        allocator,
        repo_path,
        &.{ "git", "checkout", "-b", branch },
    );
    allocator.free(create_branch_output);

    const push_output = try helpers.runChecked(
        allocator,
        repo_path,
        &.{ "git", "push", "-u", remote_name, branch },
    );
    allocator.free(push_output);

    const return_main_output = try helpers.runChecked(allocator, repo_path, &.{ "git", "checkout", "-" });
    allocator.free(return_main_output);

    const delete_local_branch_output = try helpers.runChecked(
        allocator,
        repo_path,
        &.{ "git", "branch", "-D", branch },
    );
    allocator.free(delete_local_branch_output);
}

test "integration: setup actions run against a real worktree" {
    const allocator = std.testing.allocator;
    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const wt_path = try worktree.computeWorktreePath(allocator, repo_path, "feat-setup-int");
    defer {
        helpers.cleanupPath(allocator, wt_path);
        allocator.free(wt_path);
    }

    const copy_source = try std.fs.path.join(allocator, &.{ repo_path, "copy-me.txt" });
    defer allocator.free(copy_source);
    try helpers.writeFile(copy_source, "copy payload\n");

    const link_source = try std.fs.path.join(allocator, &.{ repo_path, "link-me.txt" });
    defer allocator.free(link_source);
    try helpers.writeFile(link_source, "link payload\n");

    const run_cmd = switch (builtin.os.tag) {
        .windows => "echo setup-ran>setup.log",
        else => "printf setup-ran > setup.log",
    };
    const config_body = try std.fmt.allocPrint(allocator,
        \\[copy]
        \\paths = ["copy-me.txt"]
        \\
        \\[symlink]
        \\paths = ["link-me.txt"]
        \\
        \\[run]
        \\commands = ["{s}"]
        \\
    , .{run_cmd});
    defer allocator.free(config_body);

    const config_path = try std.fs.path.join(allocator, &.{ repo_path, ".wt.toml" });
    defer allocator.free(config_path);
    try helpers.writeFile(config_path, config_body);

    const add_output = try git.runGit(
        allocator,
        repo_path,
        &.{ "worktree", "add", "-b", "feat-setup-int", wt_path },
    );
    allocator.free(add_output);

    var cfg = try config.loadConfigFile(allocator, repo_path);
    defer cfg.deinit();

    try setup.runAllSetup(allocator, cfg.value, repo_path, wt_path, .silent);

    try std.fs.cwd().access(wt_path, .{});
    try expectBranchExists(repo_path, "feat-setup-int");

    const copied_path = try std.fs.path.join(allocator, &.{ wt_path, "copy-me.txt" });
    defer allocator.free(copied_path);
    const copied_content = try helpers.readFileAlloc(allocator, copied_path);
    defer allocator.free(copied_content);
    try std.testing.expectEqualStrings("copy payload\n", copied_content);

    const linked_path = try std.fs.path.join(allocator, &.{ wt_path, "link-me.txt" });
    defer allocator.free(linked_path);
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (builtin.os.tag == .windows) {
        if (std.fs.cwd().readLink(linked_path, &link_buf)) |target| {
            try std.testing.expectEqualStrings(link_source, target);
        } else |err| switch (err) {
            // Windows may not permit symlink creation without extra privileges.
            error.FileNotFound => {},
            else => return err,
        }
    } else {
        const target = try std.fs.cwd().readLink(linked_path, &link_buf);
        try std.testing.expectEqualStrings(link_source, target);
    }

    const setup_log_path = try std.fs.path.join(allocator, &.{ wt_path, "setup.log" });
    defer allocator.free(setup_log_path);
    const setup_log = try helpers.readFileAlloc(allocator, setup_log_path);
    defer allocator.free(setup_log);
    const setup_log_trimmed = std.mem.trim(u8, setup_log, " \t\r\n");
    try std.testing.expectEqualStrings("setup-ran", setup_log_trimmed);
}

test "integration: remove a clean worktree and delete branch" {
    const allocator = std.testing.allocator;
    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const wt_path = try worktree.computeWorktreePath(allocator, repo_path, "feat-rm-int");
    defer {
        helpers.cleanupPath(allocator, wt_path);
        allocator.free(wt_path);
    }

    const add_output = try git.runGit(
        allocator,
        repo_path,
        &.{ "worktree", "add", "-b", "feat-rm-int", wt_path },
    );
    allocator.free(add_output);

    try expectBranchExists(repo_path, "feat-rm-int");

    const remove_output = try git.runGit(allocator, repo_path, &.{ "worktree", "remove", wt_path });
    allocator.free(remove_output);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(wt_path, .{}));

    const delete_branch_output = try git.runGit(
        allocator,
        repo_path,
        &.{ "branch", "-d", "feat-rm-int" },
    );
    allocator.free(delete_branch_output);
    try expectBranchMissing(repo_path, "feat-rm-int");
}

test "integration: wt add creates local tracked branch from explicit remote branch" {
    const allocator = std.testing.allocator;
    const wt_bin = std.process.getEnvVarOwned(allocator, "WT_TEST_WT_BIN") catch return error.MissingWtTestBinary;
    defer allocator.free(wt_bin);

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const remote_path = try createBareRemoteRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, remote_path);
        allocator.free(remote_path);
    }

    try addRemote(repo_path, "origin", remote_path);
    try createRemoteOnlyBranch(repo_path, "origin", "feature/remote-add");

    const wt_path = try worktree.computeWorktreePath(allocator, repo_path, "feature/remote-add");
    defer {
        helpers.cleanupPath(allocator, wt_path);
        allocator.free(wt_path);
    }

    const result = try runWt(allocator, wt_bin, repo_path, &.{ "add", "origin/feature/remote-add" });
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.fs.cwd().access(wt_path, .{});
    try expectBranchExists(repo_path, "feature/remote-add");
    try expectUpstream(repo_path, "feature/remote-add", "origin/feature/remote-add");
}

test "integration: wt add rejects base when branch is remote-qualified" {
    const allocator = std.testing.allocator;
    const wt_bin = std.process.getEnvVarOwned(allocator, "WT_TEST_WT_BIN") catch return error.MissingWtTestBinary;
    defer allocator.free(wt_bin);

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const remote_path = try createBareRemoteRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, remote_path);
        allocator.free(remote_path);
    }

    try addRemote(repo_path, "origin", remote_path);
    try createRemoteOnlyBranch(repo_path, "origin", "feature/base-reject");

    const result = try runWt(allocator, wt_bin, repo_path, &.{ "add", "origin/feature/base-reject", "main" });
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "base ref is not supported") != null);
    try expectBranchMissing(repo_path, "feature/base-reject");
}

test "integration: wt add rejects remote-qualified creation when local branch already exists" {
    const allocator = std.testing.allocator;
    const wt_bin = std.process.getEnvVarOwned(allocator, "WT_TEST_WT_BIN") catch return error.MissingWtTestBinary;
    defer allocator.free(wt_bin);

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const remote_path = try createBareRemoteRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, remote_path);
        allocator.free(remote_path);
    }

    try addRemote(repo_path, "origin", remote_path);
    try createRemoteOnlyBranch(repo_path, "origin", "feature/local-conflict");

    const local_branch_output = try helpers.runChecked(
        allocator,
        repo_path,
        &.{ "git", "branch", "feature/local-conflict" },
    );
    allocator.free(local_branch_output);

    const result = try runWt(allocator, wt_bin, repo_path, &.{ "add", "origin/feature/local-conflict" });
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "local branch already exists") != null);
}

test "integration: wt add rejects remote-qualified creation when remote branch is missing" {
    const allocator = std.testing.allocator;
    const wt_bin = std.process.getEnvVarOwned(allocator, "WT_TEST_WT_BIN") catch return error.MissingWtTestBinary;
    defer allocator.free(wt_bin);

    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const remote_path = try createBareRemoteRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, remote_path);
        allocator.free(remote_path);
    }

    try addRemote(repo_path, "origin", remote_path);

    const result = try runWt(allocator, wt_bin, repo_path, &.{ "add", "origin/feature/missing" });
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "remote branch not found") != null);
    try expectBranchMissing(repo_path, "feature/missing");
}

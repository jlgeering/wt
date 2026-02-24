const std = @import("std");

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

    const config_path = try std.fs.path.join(allocator, &.{ repo_path, ".wt.toml" });
    defer allocator.free(config_path);
    try helpers.writeFile(config_path,
        \\[copy]
        \\paths = ["copy-me.txt"]
        \\
        \\[symlink]
        \\paths = ["link-me.txt"]
        \\
        \\[run]
        \\commands = ["printf setup-ran > setup.log"]
        \\
    );

    const add_output = try git.runGit(
        allocator,
        repo_path,
        &.{ "worktree", "add", "-b", "feat-setup-int", wt_path },
    );
    allocator.free(add_output);

    var cfg = try config.loadConfigFile(allocator, repo_path);
    defer cfg.deinit();

    try setup.runAllSetup(allocator, cfg.value, repo_path, wt_path, .quiet);

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
    const target = try std.fs.cwd().readLink(linked_path, &link_buf);
    try std.testing.expectEqualStrings(link_source, target);

    const setup_log_path = try std.fs.path.join(allocator, &.{ wt_path, "setup.log" });
    defer allocator.free(setup_log_path);
    const setup_log = try helpers.readFileAlloc(allocator, setup_log_path);
    defer allocator.free(setup_log);
    try std.testing.expectEqualStrings("setup-ran", setup_log);
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

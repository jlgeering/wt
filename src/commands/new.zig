const std = @import("std");
const git = @import("../lib/git.zig");
const worktree = @import("../lib/worktree.zig");
const config = @import("../lib/config.zig");
const setup = @import("../lib/setup.zig");
const ui = @import("../lib/ui.zig");

const OutputMode = enum {
    human,
    machine,
};

const RemoteBranchTarget = struct {
    qualified_ref: []const u8,
    remote: []const u8,
    branch: []const u8,
};

const BranchTarget = union(enum) {
    local: []const u8,
    remote: RemoteBranchTarget,
};

fn isRegisteredWorktreePath(worktrees: []const git.WorktreeInfo, path: []const u8) bool {
    for (worktrees) |wt| {
        if (std.mem.eql(u8, wt.path, path)) return true;
    }
    return false;
}

fn parseBranchTarget(branch_arg: []const u8, remotes_output: []const u8) BranchTarget {
    const slash_index = std.mem.indexOfScalar(u8, branch_arg, '/') orelse {
        return .{ .local = branch_arg };
    };

    const remote = branch_arg[0..slash_index];
    const remote_branch = branch_arg[slash_index + 1 ..];
    if (remote.len == 0 or remote_branch.len == 0) {
        return .{ .local = branch_arg };
    }

    var lines = std.mem.splitScalar(u8, remotes_output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, remote)) {
            return .{
                .remote = .{
                    .qualified_ref = branch_arg,
                    .remote = remote,
                    .branch = remote_branch,
                },
            };
        }
    }

    return .{ .local = branch_arg };
}

fn targetBranchName(target: BranchTarget) []const u8 {
    return switch (target) {
        .local => |branch| branch,
        .remote => |remote_target| remote_target.branch,
    };
}

fn localBranchExists(allocator: std.mem.Allocator, branch: []const u8) bool {
    const branch_ref = std.fmt.allocPrint(allocator, "refs/heads/{s}", .{branch}) catch return false;
    defer allocator.free(branch_ref);

    const output = git.runGit(allocator, null, &.{ "rev-parse", "--verify", branch_ref }) catch {
        return false;
    };
    allocator.free(output);
    return true;
}

fn remoteBranchExists(allocator: std.mem.Allocator, remote_qualified_branch: []const u8) bool {
    const remote_ref = std.fmt.allocPrint(allocator, "refs/remotes/{s}", .{remote_qualified_branch}) catch return false;
    defer allocator.free(remote_ref);

    const output = git.runGit(allocator, null, &.{ "rev-parse", "--verify", remote_ref }) catch {
        return false;
    };
    allocator.free(output);
    return true;
}

fn ensureBranchNotCheckedOut(
    stderr: anytype,
    use_color: bool,
    worktrees: []const git.WorktreeInfo,
    branch: []const u8,
) !void {
    for (worktrees) |wt| {
        if (wt.branch) |b| {
            if (std.mem.eql(u8, b, branch)) {
                try ui.printLevel(
                    stderr,
                    use_color,
                    .err,
                    "branch '{s}' is already checked out in {s}",
                    .{ branch, wt.path },
                );
                std.process.exit(1);
            }
        }
    }
}

fn runWithMode(allocator: std.mem.Allocator, branch_arg: []const u8, base_arg: ?[]const u8, mode: OutputMode) !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();
    const use_color = ui.shouldUseColor(std.fs.File.stderr());
    const is_machine = mode == .machine;

    const remotes_output = git.runGit(allocator, null, &.{"remote"}) catch {
        try ui.printLevel(stderr, use_color, .err, "failed to inspect configured remotes", .{});
        std.process.exit(1);
    };
    defer allocator.free(remotes_output);

    const branch_target = parseBranchTarget(branch_arg, remotes_output);
    const branch = targetBranchName(branch_target);

    switch (branch_target) {
        .remote => {
            if (base_arg != null) {
                try ui.printLevel(
                    stderr,
                    use_color,
                    .err,
                    "base ref is not supported when creating from a remote branch",
                    .{},
                );
                std.process.exit(1);
            }
        },
        .local => {},
    }

    const base = base_arg orelse "HEAD";

    // Find main worktree (first in list)
    const wt_output = git.runGit(allocator, null, &.{ "worktree", "list", "--porcelain" }) catch {
        try ui.printLevel(stderr, use_color, .err, "not a git repository or git not found", .{});
        std.process.exit(1);
    };
    defer allocator.free(wt_output);

    const worktrees = try git.parseWorktreeList(allocator, wt_output);
    defer allocator.free(worktrees);

    if (worktrees.len == 0) {
        try ui.printLevel(stderr, use_color, .err, "no worktrees found", .{});
        std.process.exit(1);
    }

    const main_path = worktrees[0].path;
    const wt_path = try worktree.computeWorktreePath(allocator, main_path, branch);
    defer allocator.free(wt_path);

    // Check if worktree already exists
    if (std.fs.cwd().access(wt_path, .{})) |_| {
        if (!isRegisteredWorktreePath(worktrees, wt_path)) {
            try ui.printLevel(stderr, use_color, .err, "path collision at {s}: exists but is not a git worktree", .{wt_path});
            try ui.printLevel(stderr, use_color, .info, "remove or rename the path, then run `wt new` again", .{});
            std.process.exit(1);
        }

        if (!is_machine) {
            try ui.printLevel(stderr, use_color, .warn, "worktree already exists at {s}", .{wt_path});
        }
        if (is_machine) {
            try stdout.print("{s}\n", .{wt_path});
        }
        return;
    } else |_| {}

    switch (branch_target) {
        .local => {
            const branch_exists = localBranchExists(allocator, branch);

            if (branch_exists) {
                try ensureBranchNotCheckedOut(stderr, use_color, worktrees, branch);

                if (!is_machine) {
                    try ui.printLevel(stderr, use_color, .info, "using existing branch '{s}'", .{branch});
                }
                const add_result = git.runGit(allocator, null, &.{ "worktree", "add", wt_path, branch }) catch {
                    try ui.printLevel(stderr, use_color, .err, "failed to create worktree", .{});
                    std.process.exit(1);
                };
                allocator.free(add_result);
            } else {
                const add_result = git.runGit(allocator, null, &.{ "worktree", "add", "-b", branch, wt_path, base }) catch {
                    try ui.printLevel(stderr, use_color, .err, "failed to create worktree", .{});
                    std.process.exit(1);
                };
                allocator.free(add_result);
            }
        },
        .remote => |remote_target| {
            if (localBranchExists(allocator, branch)) {
                try ui.printLevel(stderr, use_color, .err, "local branch already exists: {s}", .{branch});
                std.process.exit(1);
            }
            if (!remoteBranchExists(allocator, remote_target.qualified_ref)) {
                try ui.printLevel(
                    stderr,
                    use_color,
                    .err,
                    "remote branch not found: {s}",
                    .{remote_target.qualified_ref},
                );
                std.process.exit(1);
            }

            if (!is_machine) {
                try ui.printLevel(
                    stderr,
                    use_color,
                    .info,
                    "creating branch '{s}' from {s}/{s} with upstream tracking",
                    .{ branch, remote_target.remote, remote_target.branch },
                );
            }

            const add_result = git.runGit(
                allocator,
                null,
                &.{ "worktree", "add", "-b", branch, wt_path, remote_target.qualified_ref },
            ) catch {
                try ui.printLevel(stderr, use_color, .err, "failed to create worktree", .{});
                std.process.exit(1);
            };
            allocator.free(add_result);

            const upstream_arg = try std.fmt.allocPrint(
                allocator,
                "--set-upstream-to={s}",
                .{remote_target.qualified_ref},
            );
            defer allocator.free(upstream_arg);

            const upstream_result = git.runGit(allocator, wt_path, &.{ "branch", upstream_arg, branch }) catch {
                try ui.printLevel(stderr, use_color, .err, "failed to configure upstream tracking", .{});
                std.process.exit(1);
            };
            allocator.free(upstream_result);
        },
    }

    if (!is_machine) {
        try ui.printLevel(stderr, use_color, .success, "created worktree at {s}", .{wt_path});
    }

    // Load config and run setup
    var cfg = try config.loadConfigFile(allocator, main_path);
    defer cfg.deinit();

    const log_mode: setup.LogMode = if (is_machine) .machine else .human;
    try setup.runAllSetup(allocator, cfg.value, main_path, wt_path, log_mode);

    if (is_machine) {
        try stdout.print("{s}\n", .{wt_path});
    }
}

pub fn runHuman(allocator: std.mem.Allocator, branch: []const u8, base: ?[]const u8) !void {
    try runWithMode(allocator, branch, base, .human);
}

pub fn runMachine(allocator: std.mem.Allocator, branch: []const u8, base: ?[]const u8) !void {
    try runWithMode(allocator, branch, base, .machine);
}

test "isRegisteredWorktreePath returns true only for listed worktrees" {
    const worktrees = [_]git.WorktreeInfo{
        .{ .path = "/tmp/repo", .head = "abc", .branch = "main", .is_bare = false },
        .{ .path = "/tmp/repo--feat", .head = "def", .branch = "feat", .is_bare = false },
    };

    try std.testing.expect(isRegisteredWorktreePath(&worktrees, "/tmp/repo--feat"));
    try std.testing.expect(!isRegisteredWorktreePath(&worktrees, "/tmp/repo--other"));
}

test "parseBranchTarget keeps plain branch local" {
    const target = parseBranchTarget("feat-x", "origin\nupstream\n");

    switch (target) {
        .local => |branch| try std.testing.expectEqualStrings("feat-x", branch),
        .remote => return error.UnexpectedRemoteTarget,
    }
}

test "parseBranchTarget keeps slash branch local when remote is absent" {
    const target = parseBranchTarget("feature/foo", "origin\nupstream\n");

    switch (target) {
        .local => |branch| try std.testing.expectEqualStrings("feature/foo", branch),
        .remote => return error.UnexpectedRemoteTarget,
    }
}

test "parseBranchTarget resolves configured remote branch" {
    const target = parseBranchTarget("origin/feature/foo", "origin\nupstream\n");

    switch (target) {
        .local => return error.ExpectedRemoteTarget,
        .remote => |remote_target| {
            try std.testing.expectEqualStrings("origin/feature/foo", remote_target.qualified_ref);
            try std.testing.expectEqualStrings("origin", remote_target.remote);
            try std.testing.expectEqualStrings("feature/foo", remote_target.branch);
        },
    }
}

test "parseBranchTarget treats configured remote prefix as remote-qualified input" {
    const target = parseBranchTarget("origin/foo", "origin\nupstream\n");

    switch (target) {
        .local => return error.ExpectedRemoteTarget,
        .remote => |remote_target| {
            try std.testing.expectEqualStrings("origin/foo", remote_target.qualified_ref);
            try std.testing.expectEqualStrings("origin", remote_target.remote);
            try std.testing.expectEqualStrings("foo", remote_target.branch);
        },
    }
}

test "parseBranchTarget keeps empty branch argument local" {
    const target = parseBranchTarget("", "origin\nupstream\n");

    switch (target) {
        .local => |branch| try std.testing.expectEqualStrings("", branch),
        .remote => return error.UnexpectedRemoteTarget,
    }
}

test "parseBranchTarget keeps leading-slash input local" {
    const target = parseBranchTarget("/foo", "origin\nupstream\n");

    switch (target) {
        .local => |branch| try std.testing.expectEqualStrings("/foo", branch),
        .remote => return error.UnexpectedRemoteTarget,
    }
}

test "parseBranchTarget keeps trailing-slash input local" {
    const target = parseBranchTarget("foo/", "origin\nupstream\n");

    switch (target) {
        .local => |branch| try std.testing.expectEqualStrings("foo/", branch),
        .remote => return error.UnexpectedRemoteTarget,
    }
}

test "parseBranchTarget keeps slash branch local when remotes output is empty" {
    const target = parseBranchTarget("origin/feature/foo", "");

    switch (target) {
        .local => |branch| try std.testing.expectEqualStrings("origin/feature/foo", branch),
        .remote => return error.UnexpectedRemoteTarget,
    }
}

const std = @import("std");
const git = @import("../lib/git.zig");
const ui = @import("../lib/ui.zig");

const OutputMode = enum {
    human,
    machine,
};

fn findWorktreeByBranch(worktrees: []const git.WorktreeInfo, branch: []const u8) ?[]const u8 {
    for (worktrees) |wt| {
        if (wt.branch) |b| {
            if (std.mem.eql(u8, b, branch)) return wt.path;
        }
    }
    return null;
}

fn runWithMode(allocator: std.mem.Allocator, branch: []const u8, mode: OutputMode) !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();
    const use_color = ui.shouldUseColor(std.fs.File.stderr());
    const is_machine = mode == .machine;

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

    if (findWorktreeByBranch(worktrees, branch)) |path| {
        try stdout.print("{s}\n", .{path});
    } else {
        if (!is_machine) {
            try ui.printLevel(stderr, use_color, .err, "no worktree for branch '{s}'", .{branch});
        }
        std.process.exit(1);
    }
}

pub fn runHuman(allocator: std.mem.Allocator, branch: []const u8) !void {
    try runWithMode(allocator, branch, .human);
}

pub fn runMachine(allocator: std.mem.Allocator, branch: []const u8) !void {
    try runWithMode(allocator, branch, .machine);
}

test "findWorktreeByBranch returns path for matching branch" {
    const worktrees = [_]git.WorktreeInfo{
        .{ .path = "/repo", .head = "abc", .branch = "main", .is_bare = false },
        .{ .path = "/repo--feat", .head = "def", .branch = "feat", .is_bare = false },
    };
    const result = findWorktreeByBranch(&worktrees, "feat");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("/repo--feat", result.?);
}

test "findWorktreeByBranch returns null for unknown branch" {
    const worktrees = [_]git.WorktreeInfo{
        .{ .path = "/repo", .head = "abc", .branch = "main", .is_bare = false },
    };
    const result = findWorktreeByBranch(&worktrees, "missing");
    try std.testing.expect(result == null);
}

test "findWorktreeByBranch returns null for detached HEAD worktree" {
    const worktrees = [_]git.WorktreeInfo{
        .{ .path = "/repo", .head = "abc", .branch = null, .is_bare = false },
    };
    const result = findWorktreeByBranch(&worktrees, "main");
    try std.testing.expect(result == null);
}

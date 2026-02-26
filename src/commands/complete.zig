const std = @import("std");
const git = @import("../lib/git.zig");

fn writeUniqueLinesFromOutput(
    allocator: std.mem.Allocator,
    output: []const u8,
    writer: anytype,
) !void {
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (seen.contains(line)) continue;
        try seen.put(line, {});
        try writer.print("{s}\n", .{line});
    }
}

fn writeRmBranchCandidates(
    allocator: std.mem.Allocator,
    worktrees: []const git.WorktreeInfo,
    current_root: ?[]const u8,
    writer: anytype,
) !void {
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    for (worktrees) |wt| {
        const branch = wt.branch orelse continue;
        if (current_root) |root| {
            if (std.mem.eql(u8, wt.path, root)) continue;
        }
        if (seen.contains(branch)) continue;
        try seen.put(branch, {});
        try writer.print("{s}\n", .{branch});
    }
}

pub fn runLocalBranches(allocator: std.mem.Allocator) !void {
    const output = git.runGit(
        allocator,
        null,
        &.{ "for-each-ref", "--format=%(refname:short)", "refs/heads" },
    ) catch return;
    defer allocator.free(output);

    const stdout = std.fs.File.stdout().deprecatedWriter();
    try writeUniqueLinesFromOutput(allocator, output, stdout);
}

pub fn runRefs(allocator: std.mem.Allocator) !void {
    const output = git.runGit(
        allocator,
        null,
        &.{ "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes" },
    ) catch return;
    defer allocator.free(output);

    const stdout = std.fs.File.stdout().deprecatedWriter();
    try writeUniqueLinesFromOutput(allocator, output, stdout);
}

pub fn runRmBranches(allocator: std.mem.Allocator) !void {
    const list_output = git.runGit(
        allocator,
        null,
        &.{ "worktree", "list", "--porcelain" },
    ) catch return;
    defer allocator.free(list_output);

    const worktrees = git.parseWorktreeList(allocator, list_output) catch return;
    defer allocator.free(worktrees);

    var current_root: ?[]u8 = null;
    defer if (current_root) |path| allocator.free(path);
    if (git.runGit(allocator, null, &.{ "rev-parse", "--show-toplevel" })) |output| {
        defer allocator.free(output);
        const trimmed = std.mem.trim(u8, output, " \t\r\n");
        if (trimmed.len > 0) {
            current_root = try allocator.dupe(u8, trimmed);
        }
    } else |_| {}

    const stdout = std.fs.File.stdout().deprecatedWriter();
    try writeRmBranchCandidates(allocator, worktrees, current_root, stdout);
}

test "writeUniqueLinesFromOutput deduplicates and drops blanks" {
    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();

    try writeUniqueLinesFromOutput(
        std.testing.allocator,
        "main\nfeat\nmain\n\nfeature-two\n",
        out.writer(),
    );

    try std.testing.expectEqualStrings("main\nfeat\nfeature-two\n", out.items);
}

test "writeRmBranchCandidates excludes current and detached entries" {
    const worktrees = [_]git.WorktreeInfo{
        .{ .path = "/repo", .head = "a", .branch = "main", .is_bare = false },
        .{ .path = "/repo--feat", .head = "b", .branch = "feat", .is_bare = false },
        .{ .path = "/repo--detached", .head = "c", .branch = null, .is_bare = false },
        .{ .path = "/repo--feat-dupe", .head = "d", .branch = "feat", .is_bare = false },
        .{ .path = "/repo--topic", .head = "e", .branch = "topic", .is_bare = false },
    };

    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();

    try writeRmBranchCandidates(
        std.testing.allocator,
        &worktrees,
        "/repo",
        out.writer(),
    );

    try std.testing.expectEqualStrings("feat\ntopic\n", out.items);
}

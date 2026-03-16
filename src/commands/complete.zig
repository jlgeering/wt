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

fn writeUniqueLinesWithSuffixFromOutput(
    allocator: std.mem.Allocator,
    output: []const u8,
    suffix: []const u8,
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
        try writer.print("{s}{s}\n", .{ line, suffix });
    }
}

fn writeWorktreeBranchCandidates(
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

fn writeUniqueRemoteBranchLinesFromOutput(
    allocator: std.mem.Allocator,
    output: []const u8,
    remote_name: []const u8,
    writer: anytype,
) !void {
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    const head_ref = try std.fmt.allocPrint(allocator, "{s}/HEAD", .{remote_name});
    defer allocator.free(head_ref);

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, head_ref)) continue;
        if (seen.contains(line)) continue;
        try seen.put(line, {});
        try writer.print("{s}\n", .{line});
    }
}

fn findRemoteNamePrefix(current: []const u8, remotes_output: []const u8) ?[]const u8 {
    const slash_index = std.mem.indexOfScalar(u8, current, '/') orelse return null;
    const remote_name = current[0..slash_index];
    if (remote_name.len == 0) return null;

    var lines = std.mem.splitScalar(u8, remotes_output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, remote_name)) return remote_name;
    }

    return null;
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

pub fn runBranchTargets(allocator: std.mem.Allocator, current: ?[]const u8) !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();

    const remotes_output = git.runGit(allocator, null, &.{"remote"}) catch return;
    defer allocator.free(remotes_output);

    if (current) |partial| {
        if (findRemoteNamePrefix(partial, remotes_output)) |remote_name| {
            const remote_ref = try std.fmt.allocPrint(allocator, "refs/remotes/{s}", .{remote_name});
            defer allocator.free(remote_ref);

            const remote_output = git.runGit(
                allocator,
                null,
                &.{ "for-each-ref", "--format=%(refname:short)", remote_ref },
            ) catch return;
            defer allocator.free(remote_output);

            try writeUniqueRemoteBranchLinesFromOutput(allocator, remote_output, remote_name, stdout);
            return;
        }
    }

    const local_output = git.runGit(
        allocator,
        null,
        &.{ "for-each-ref", "--format=%(refname:short)", "refs/heads" },
    ) catch return;
    defer allocator.free(local_output);

    try writeUniqueLinesFromOutput(allocator, local_output, stdout);
    try writeUniqueLinesWithSuffixFromOutput(allocator, remotes_output, "/", stdout);
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

pub fn runWorktreeBranches(allocator: std.mem.Allocator) !void {
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
    if (git.repoRoot(allocator, null)) |root| {
        current_root = root;
    } else |_| {}

    const stdout = std.fs.File.stdout().deprecatedWriter();
    try writeWorktreeBranchCandidates(allocator, worktrees, current_root, stdout);
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

test "writeUniqueLinesWithSuffixFromOutput appends suffix once" {
    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();

    try writeUniqueLinesWithSuffixFromOutput(
        std.testing.allocator,
        "origin\nupstream\norigin\n",
        "/",
        out.writer(),
    );

    try std.testing.expectEqualStrings("origin/\nupstream/\n", out.items);
}

test "writeUniqueRemoteBranchLinesFromOutput skips symbolic head refs" {
    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();

    try writeUniqueRemoteBranchLinesFromOutput(
        std.testing.allocator,
        "origin/HEAD\norigin/feature/one\norigin/feature/one\norigin/feature/two\n",
        "origin",
        out.writer(),
    );

    try std.testing.expectEqualStrings("origin/feature/one\norigin/feature/two\n", out.items);
}

test "findRemoteNamePrefix only matches configured remotes" {
    try std.testing.expectEqualStrings(
        "origin",
        findRemoteNamePrefix("origin/feat", "origin\nupstream\n").?,
    );
    try std.testing.expect(findRemoteNamePrefix("feature/foo", "origin\nupstream\n") == null);
    try std.testing.expect(findRemoteNamePrefix("/feat", "origin\nupstream\n") == null);
}

test "writeWorktreeBranchCandidates excludes current and detached entries" {
    const worktrees = [_]git.WorktreeInfo{
        .{ .path = "/repo", .head = "a", .branch = "main", .is_bare = false },
        .{ .path = "/repo--feat", .head = "b", .branch = "feat", .is_bare = false },
        .{ .path = "/repo--detached", .head = "c", .branch = null, .is_bare = false },
        .{ .path = "/repo--feat-dupe", .head = "d", .branch = "feat", .is_bare = false },
        .{ .path = "/repo--topic", .head = "e", .branch = "topic", .is_bare = false },
    };

    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();

    try writeWorktreeBranchCandidates(
        std.testing.allocator,
        &worktrees,
        "/repo",
        out.writer(),
    );

    try std.testing.expectEqualStrings("feat\ntopic\n", out.items);
}

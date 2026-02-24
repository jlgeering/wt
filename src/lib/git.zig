const std = @import("std");

pub const WorktreeInfo = struct {
    path: []const u8,
    head: []const u8,
    branch: ?[]const u8, // null for detached HEAD
    is_bare: bool,
};

pub const WorktreeStatus = struct {
    modified: usize,
    untracked: usize,
};

pub const BranchDivergence = struct {
    has_upstream: bool,
    ahead: usize,
    behind: usize,
};

/// Parse integer output from git commands like `rev-list --count`.
pub fn parseCountOutput(output: []const u8) !usize {
    const trimmed = std.mem.trim(u8, output, " \t\r\n");
    if (trimmed.len == 0) return 0;
    return std.fmt.parseInt(usize, trimmed, 10);
}

/// Parse output of `git worktree list --porcelain` into WorktreeInfo structs.
/// Returned slice is owned by caller. Strings point into the input buffer.
pub fn parseWorktreeList(allocator: std.mem.Allocator, output: []const u8) ![]WorktreeInfo {
    var worktrees = std.array_list.Managed(WorktreeInfo).init(allocator);
    defer worktrees.deinit();

    var current: WorktreeInfo = .{ .path = "", .head = "", .branch = null, .is_bare = false };
    var in_entry = false;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) {
            if (in_entry) {
                try worktrees.append(current);
                current = .{ .path = "", .head = "", .branch = null, .is_bare = false };
                in_entry = false;
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "worktree ")) {
            current.path = line["worktree ".len..];
            in_entry = true;
        } else if (std.mem.startsWith(u8, line, "HEAD ")) {
            current.head = line["HEAD ".len..];
        } else if (std.mem.startsWith(u8, line, "branch refs/heads/")) {
            current.branch = line["branch refs/heads/".len..];
        } else if (std.mem.eql(u8, line, "bare")) {
            current.is_bare = true;
        }
    }

    // Handle last entry if no trailing newline
    if (in_entry) {
        try worktrees.append(current);
    }

    return worktrees.toOwnedSlice();
}

/// Parse output of `git status --porcelain` into counts.
pub fn parseStatusPorcelain(output: []const u8) WorktreeStatus {
    var modified: usize = 0;
    var untracked: usize = 0;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len < 2) continue;
        if (line[0] == '#' and line[1] == '#') continue;
        if (line[0] == '?' and line[1] == '?') {
            untracked += 1;
        } else {
            modified += 1;
        }
    }

    return .{ .modified = modified, .untracked = untracked };
}

/// Parse branch divergence from `git status --porcelain --branch` first header line.
pub fn parseBranchDivergence(output: []const u8) BranchDivergence {
    var result: BranchDivergence = .{
        .has_upstream = false,
        .ahead = 0,
        .behind = 0,
    };

    var lines = std.mem.splitScalar(u8, output, '\n');
    const first_line = lines.next() orelse return result;
    if (!std.mem.startsWith(u8, first_line, "## ")) return result;

    const header = first_line[3..];
    result.has_upstream = std.mem.indexOf(u8, header, "...") != null;

    const bracket_open = std.mem.indexOfScalar(u8, header, '[') orelse return result;
    const bracket_close = std.mem.indexOfScalarPos(u8, header, bracket_open + 1, ']') orelse return result;
    const details = std.mem.trim(u8, header[bracket_open + 1 .. bracket_close], " ");

    var parts = std.mem.splitScalar(u8, details, ',');
    while (parts.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " ");
        if (std.mem.startsWith(u8, part, "ahead ")) {
            result.ahead = std.fmt.parseInt(usize, part["ahead ".len..], 10) catch result.ahead;
        } else if (std.mem.startsWith(u8, part, "behind ")) {
            result.behind = std.fmt.parseInt(usize, part["behind ".len..], 10) catch result.behind;
        }
    }

    return result;
}

/// Count commits reachable from `branch_ref` but not from `base_ref`.
pub fn countUnmergedCommits(
    allocator: std.mem.Allocator,
    cwd: ?[]const u8,
    base_ref: []const u8,
    branch_ref: []const u8,
) !usize {
    const range = try std.fmt.allocPrint(allocator, "{s}..{s}", .{ base_ref, branch_ref });
    defer allocator.free(range);

    const output = try runGit(allocator, cwd, &.{ "rev-list", "--count", range });
    defer allocator.free(output);

    return parseCountOutput(output);
}

/// Run a git command and return stdout. Caller owns returned memory.
pub fn runGit(allocator: std.mem.Allocator, cwd: ?[]const u8, args: []const []const u8) ![]u8 {
    var argv = std.array_list.Managed([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append("git");
    try argv.appendSlice(args);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
        .cwd = cwd,
    }) catch {
        return error.GitNotFound;
    };
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                allocator.free(result.stdout);
                return error.GitCommandFailed;
            }
            return result.stdout;
        },
        else => {
            allocator.free(result.stdout);
            return error.GitCommandFailed;
        },
    }
}

// --- Tests ---

test "parseWorktreeList parses two worktrees" {
    const input =
        \\worktree /Users/jl/src/myapp
        \\HEAD abc123def456789012345678901234567890abcd
        \\branch refs/heads/main
        \\
        \\worktree /Users/jl/src/myapp--feat
        \\HEAD def456abc123789012345678901234567890abcd
        \\branch refs/heads/feat
        \\
    ;

    const result = try parseWorktreeList(std.testing.allocator, input);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("/Users/jl/src/myapp", result[0].path);
    try std.testing.expectEqualStrings("main", result[0].branch.?);
    try std.testing.expectEqualStrings("/Users/jl/src/myapp--feat", result[1].path);
    try std.testing.expectEqualStrings("feat", result[1].branch.?);
}

test "parseWorktreeList handles detached HEAD" {
    const input =
        \\worktree /Users/jl/src/myapp--detached
        \\HEAD abc123def456789012345678901234567890abcd
        \\detached
        \\
    ;

    const result = try parseWorktreeList(std.testing.allocator, input);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(result[0].branch == null);
}

test "parseWorktreeList handles bare worktree" {
    const input =
        \\worktree /Users/jl/src/myapp.git
        \\HEAD abc123def456789012345678901234567890abcd
        \\bare
        \\
    ;

    const result = try parseWorktreeList(std.testing.allocator, input);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(result[0].is_bare);
}

test "parseStatusPorcelain counts modified and untracked" {
    const input =
        \\ M src/main.zig
        \\?? new_file.txt
        \\MM src/lib.zig
    ;

    const status = parseStatusPorcelain(input);
    try std.testing.expectEqual(@as(usize, 2), status.modified);
    try std.testing.expectEqual(@as(usize, 1), status.untracked);
}

test "parseStatusPorcelain handles empty output" {
    const status = parseStatusPorcelain("");
    try std.testing.expectEqual(@as(usize, 0), status.modified);
    try std.testing.expectEqual(@as(usize, 0), status.untracked);
}

test "parseStatusPorcelain ignores --branch header line" {
    const input =
        \\## main...origin/main [ahead 2]
        \\ M src/main.zig
        \\?? new_file.txt
    ;

    const status = parseStatusPorcelain(input);
    try std.testing.expectEqual(@as(usize, 1), status.modified);
    try std.testing.expectEqual(@as(usize, 1), status.untracked);
}

test "parseBranchDivergence parses ahead and behind counters" {
    const input = "## feat-x...origin/feat-x [ahead 3, behind 1]\n";
    const divergence = parseBranchDivergence(input);
    try std.testing.expect(divergence.has_upstream);
    try std.testing.expectEqual(@as(usize, 3), divergence.ahead);
    try std.testing.expectEqual(@as(usize, 1), divergence.behind);
}

test "parseBranchDivergence handles synced branch with upstream" {
    const input = "## main...origin/main\n";
    const divergence = parseBranchDivergence(input);
    try std.testing.expect(divergence.has_upstream);
    try std.testing.expectEqual(@as(usize, 0), divergence.ahead);
    try std.testing.expectEqual(@as(usize, 0), divergence.behind);
}

test "parseBranchDivergence handles branch without upstream" {
    const input = "## feat-local\n";
    const divergence = parseBranchDivergence(input);
    try std.testing.expect(!divergence.has_upstream);
    try std.testing.expectEqual(@as(usize, 0), divergence.ahead);
    try std.testing.expectEqual(@as(usize, 0), divergence.behind);
}

test "parseCountOutput parses newline-terminated number" {
    const count = try parseCountOutput("12\n");
    try std.testing.expectEqual(@as(usize, 12), count);
}

test "parseCountOutput treats empty output as zero" {
    const count = try parseCountOutput(" \n");
    try std.testing.expectEqual(@as(usize, 0), count);
}

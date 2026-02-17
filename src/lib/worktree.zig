const std = @import("std");

/// Compute the worktree path for a branch: {main_path}--{branch}
pub fn computeWorktreePath(allocator: std.mem.Allocator, main_path: []const u8, branch: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}--{s}", .{ main_path, branch });
}

/// Extract branch name from worktree path.
/// Returns null if path doesn't match the {repo}--{branch} pattern.
pub fn extractBranchFromPath(main_path: []const u8, wt_path: []const u8) ?[]const u8 {
    const prefix_len = main_path.len + "--".len;
    if (wt_path.len <= prefix_len) return null;
    if (!std.mem.startsWith(u8, wt_path, main_path)) return null;
    if (!std.mem.startsWith(u8, wt_path[main_path.len..], "--")) return null;
    return wt_path[prefix_len..];
}

/// Get the repository name from the main worktree path (last path component).
pub fn repoName(main_path: []const u8) []const u8 {
    return std.fs.path.basename(main_path);
}

// --- Tests ---

test "computeWorktreePath creates sibling with branch suffix" {
    const result = try computeWorktreePath(
        std.testing.allocator,
        "/Users/jl/src/myapp",
        "feat-auth",
    );
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("/Users/jl/src/myapp--feat-auth", result);
}

test "extractBranchFromPath returns branch name" {
    const branch = extractBranchFromPath(
        "/Users/jl/src/myapp",
        "/Users/jl/src/myapp--feat-auth",
    );
    try std.testing.expectEqualStrings("feat-auth", branch.?);
}

test "extractBranchFromPath returns null for main worktree" {
    const branch = extractBranchFromPath(
        "/Users/jl/src/myapp",
        "/Users/jl/src/myapp",
    );
    try std.testing.expect(branch == null);
}

test "extractBranchFromPath returns null for unrelated path" {
    const branch = extractBranchFromPath(
        "/Users/jl/src/myapp",
        "/Users/jl/src/other",
    );
    try std.testing.expect(branch == null);
}

test "repoName returns last path component" {
    try std.testing.expectEqualStrings("myapp", repoName("/Users/jl/src/myapp"));
    try std.testing.expectEqualStrings("wt", repoName("/Users/jl/src/wt"));
}

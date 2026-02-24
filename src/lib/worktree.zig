const std = @import("std");

/// Compute the worktree path for a branch: {main_path}--{branch}
pub fn computeWorktreePath(allocator: std.mem.Allocator, main_path: []const u8, branch: []const u8) ![]u8 {
    var path = std.array_list.Managed(u8).init(allocator);
    errdefer path.deinit();

    try path.appendSlice(main_path);
    try path.appendSlice("--");

    const hex = "0123456789ABCDEF";
    for (branch) |byte| {
        const is_safe =
            std.ascii.isAlphanumeric(byte) or
            byte == '-' or
            byte == '_' or
            byte == '.';

        if (is_safe) {
            try path.append(byte);
        } else {
            try path.append('%');
            try path.append(hex[byte >> 4]);
            try path.append(hex[byte & 0x0F]);
        }
    }

    return path.toOwnedSlice();
}

/// Extract encoded branch suffix from worktree path.
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

test "computeWorktreePath percent-encodes slash in branch names" {
    const result = try computeWorktreePath(
        std.testing.allocator,
        "/Users/jl/src/myapp",
        "feat/auth",
    );
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("/Users/jl/src/myapp--feat%2Fauth", result);
}

test "computeWorktreePath avoids collisions for encoded-like branch names" {
    const slash_branch = try computeWorktreePath(
        std.testing.allocator,
        "/Users/jl/src/myapp",
        "feat/auth",
    );
    defer std.testing.allocator.free(slash_branch);

    const encoded_literal_branch = try computeWorktreePath(
        std.testing.allocator,
        "/Users/jl/src/myapp",
        "feat%2Fauth",
    );
    defer std.testing.allocator.free(encoded_literal_branch);

    try std.testing.expectEqualStrings("/Users/jl/src/myapp--feat%2Fauth", slash_branch);
    try std.testing.expectEqualStrings("/Users/jl/src/myapp--feat%252Fauth", encoded_literal_branch);
    try std.testing.expect(!std.mem.eql(u8, slash_branch, encoded_literal_branch));
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

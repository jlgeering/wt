const std = @import("std");

const wt_lib = @import("wt_lib");
const git = wt_lib.git;
const worktree = wt_lib.worktree;
const helpers = @import("helpers.zig");

test "integration: parse list output from real git repo" {
    const allocator = std.testing.allocator;
    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const wt_path = try worktree.computeWorktreePath(allocator, repo_path, "feat-list-int");
    defer {
        helpers.cleanupPath(allocator, wt_path);
        allocator.free(wt_path);
    }

    const add_output = try git.runGit(
        allocator,
        repo_path,
        &.{ "worktree", "add", "-b", "feat-list-int", wt_path },
    );
    allocator.free(add_output);

    const list_output = try git.runGit(allocator, repo_path, &.{ "worktree", "list", "--porcelain" });
    defer allocator.free(list_output);

    const parsed = try git.parseWorktreeList(allocator, list_output);
    defer allocator.free(parsed);

    try std.testing.expectEqual(@as(usize, 2), parsed.len);

    var found_main = false;
    var found_feature = false;
    for (parsed) |entry| {
        if (std.mem.eql(u8, entry.path, repo_path)) found_main = true;
        if (std.mem.eql(u8, entry.path, wt_path)) {
            found_feature = true;
            try std.testing.expect(entry.branch != null);
            try std.testing.expectEqualStrings("feat-list-int", entry.branch.?);
        }
    }

    try std.testing.expect(found_main);
    try std.testing.expect(found_feature);
}

test "integration: count unmerged commits for feature branch" {
    const allocator = std.testing.allocator;
    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const wt_path = try worktree.computeWorktreePath(allocator, repo_path, "feat-unmerged-int");
    defer {
        helpers.cleanupPath(allocator, wt_path);
        allocator.free(wt_path);
    }

    const add_output = try git.runGit(
        allocator,
        repo_path,
        &.{ "worktree", "add", "-b", "feat-unmerged-int", wt_path },
    );
    allocator.free(add_output);

    const feature_file = try std.fs.path.join(allocator, &.{ wt_path, "feature.txt" });
    defer allocator.free(feature_file);
    try helpers.writeFile(feature_file, "feature\n");

    const add_feature_output = try git.runGit(allocator, wt_path, &.{ "add", "feature.txt" });
    allocator.free(add_feature_output);
    const commit_output = try git.runGit(allocator, wt_path, &.{ "commit", "-m", "feature commit" });
    allocator.free(commit_output);

    const unmerged_before_merge = try git.countUnmergedCommits(
        allocator,
        repo_path,
        "HEAD",
        "feat-unmerged-int",
    );
    try std.testing.expectEqual(@as(usize, 1), unmerged_before_merge);

    const merge_output = try git.runGit(allocator, repo_path, &.{ "merge", "--ff-only", "feat-unmerged-int" });
    allocator.free(merge_output);

    const unmerged_after_merge = try git.countUnmergedCommits(
        allocator,
        repo_path,
        "HEAD",
        "feat-unmerged-int",
    );
    try std.testing.expectEqual(@as(usize, 0), unmerged_after_merge);
}

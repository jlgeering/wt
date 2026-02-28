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

test "integration: patch-equivalent local commits are excluded from non-equivalent local commit counts" {
    const allocator = std.testing.allocator;
    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const wt_path = try worktree.computeWorktreePath(allocator, repo_path, "feat-cherry-equivalent-int");
    defer {
        helpers.cleanupPath(allocator, wt_path);
        allocator.free(wt_path);
    }

    const add_output = try git.runGit(
        allocator,
        repo_path,
        &.{ "worktree", "add", "-b", "feat-cherry-equivalent-int", wt_path },
    );
    allocator.free(add_output);

    const feature_file = try std.fs.path.join(allocator, &.{ wt_path, "feature.txt" });
    defer allocator.free(feature_file);
    try helpers.writeFile(feature_file, "feature\n");

    const add_feature_output = try git.runGit(allocator, wt_path, &.{ "add", "feature.txt" });
    allocator.free(add_feature_output);
    const feature_commit_output = try git.runGit(allocator, wt_path, &.{ "commit", "-m", "feature commit" });
    allocator.free(feature_commit_output);

    const main_file = try std.fs.path.join(allocator, &.{ repo_path, "main.txt" });
    defer allocator.free(main_file);
    try helpers.writeFile(main_file, "main\n");

    const add_main_output = try git.runGit(allocator, repo_path, &.{ "add", "main.txt" });
    allocator.free(add_main_output);
    const main_commit_output = try git.runGit(allocator, repo_path, &.{ "commit", "-m", "main commit" });
    allocator.free(main_commit_output);

    const feature_sha_output = try git.runGit(allocator, wt_path, &.{ "rev-parse", "HEAD" });
    defer allocator.free(feature_sha_output);
    const feature_sha = std.mem.trim(u8, feature_sha_output, " \t\r\n");

    const cherry_pick_output = try git.runGit(allocator, repo_path, &.{ "cherry-pick", feature_sha });
    allocator.free(cherry_pick_output);

    const graph_local_commits = try git.countUnmergedCommits(
        allocator,
        repo_path,
        "HEAD",
        "feat-cherry-equivalent-int",
    );
    try std.testing.expectEqual(@as(usize, 1), graph_local_commits);

    const non_equivalent_local_commits = try git.countNonEquivalentLocalCommits(
        allocator,
        repo_path,
        "HEAD",
        "feat-cherry-equivalent-int",
    );
    try std.testing.expectEqual(@as(usize, 0), non_equivalent_local_commits);
}

test "integration: merge-only local history remains detectable as non-equivalent local commits" {
    const allocator = std.testing.allocator;
    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const wt_path = try worktree.computeWorktreePath(allocator, repo_path, "feat-merge-only-int");
    defer {
        helpers.cleanupPath(allocator, wt_path);
        allocator.free(wt_path);
    }

    const add_output = try git.runGit(
        allocator,
        repo_path,
        &.{ "worktree", "add", "-b", "feat-merge-only-int", wt_path },
    );
    allocator.free(add_output);

    const main_file = try std.fs.path.join(allocator, &.{ repo_path, "main.txt" });
    defer allocator.free(main_file);
    try helpers.writeFile(main_file, "main\n");

    const add_main_output = try git.runGit(allocator, repo_path, &.{ "add", "main.txt" });
    allocator.free(add_main_output);
    const main_commit_output = try git.runGit(allocator, repo_path, &.{ "commit", "-m", "main commit" });
    allocator.free(main_commit_output);

    const default_branch_output = try git.runGit(allocator, repo_path, &.{ "rev-parse", "--abbrev-ref", "HEAD" });
    defer allocator.free(default_branch_output);
    const default_branch = std.mem.trim(u8, default_branch_output, " \t\r\n");

    const merge_output = try git.runGit(
        allocator,
        wt_path,
        &.{ "merge", "--no-ff", "-m", "merge default branch", default_branch },
    );
    allocator.free(merge_output);

    const graph_local_commits = try git.countUnmergedCommits(
        allocator,
        repo_path,
        "HEAD",
        "feat-merge-only-int",
    );
    try std.testing.expectEqual(@as(usize, 1), graph_local_commits);

    const non_equivalent_local_commits = try git.countNonEquivalentLocalCommits(
        allocator,
        repo_path,
        "HEAD",
        "feat-merge-only-int",
    );
    try std.testing.expectEqual(@as(usize, 1), non_equivalent_local_commits);
}

test "integration: ahead and behind counts diverge after commits on both branches" {
    const allocator = std.testing.allocator;
    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const wt_path = try worktree.computeWorktreePath(allocator, repo_path, "feat-diverge-int");
    defer {
        helpers.cleanupPath(allocator, wt_path);
        allocator.free(wt_path);
    }

    const add_output = try git.runGit(
        allocator,
        repo_path,
        &.{ "worktree", "add", "-b", "feat-diverge-int", wt_path },
    );
    allocator.free(add_output);

    const feature_file = try std.fs.path.join(allocator, &.{ wt_path, "feature.txt" });
    defer allocator.free(feature_file);
    try helpers.writeFile(feature_file, "feature\n");

    const add_feature_output = try git.runGit(allocator, wt_path, &.{ "add", "feature.txt" });
    allocator.free(add_feature_output);
    const feature_commit_output = try git.runGit(allocator, wt_path, &.{ "commit", "-m", "feature commit" });
    allocator.free(feature_commit_output);

    const main_file = try std.fs.path.join(allocator, &.{ repo_path, "main.txt" });
    defer allocator.free(main_file);
    try helpers.writeFile(main_file, "main\n");

    const add_main_output = try git.runGit(allocator, repo_path, &.{ "add", "main.txt" });
    allocator.free(add_main_output);
    const main_commit_output = try git.runGit(allocator, repo_path, &.{ "commit", "-m", "main commit" });
    allocator.free(main_commit_output);

    const default_branch_output = try git.runGit(allocator, repo_path, &.{ "rev-parse", "--abbrev-ref", "HEAD" });
    defer allocator.free(default_branch_output);
    const default_branch = std.mem.trim(u8, default_branch_output, " \t\r\n");

    const ahead = try git.countUnmergedCommits(
        allocator,
        repo_path,
        default_branch,
        "feat-diverge-int",
    );
    const behind = try git.countUnmergedCommits(
        allocator,
        repo_path,
        "feat-diverge-int",
        default_branch,
    );

    try std.testing.expectEqual(@as(usize, 1), ahead);
    try std.testing.expectEqual(@as(usize, 1), behind);
}

test "integration: dirty worktree remove requires force" {
    const allocator = std.testing.allocator;
    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const wt_path = try worktree.computeWorktreePath(allocator, repo_path, "feat-dirty-rm-int");
    defer {
        helpers.cleanupPath(allocator, wt_path);
        allocator.free(wt_path);
    }

    const add_output = try git.runGit(
        allocator,
        repo_path,
        &.{ "worktree", "add", "-b", "feat-dirty-rm-int", wt_path },
    );
    allocator.free(add_output);

    const dirty_file = try std.fs.path.join(allocator, &.{ wt_path, "dirty.txt" });
    defer allocator.free(dirty_file);
    try helpers.writeFile(dirty_file, "dirty\n");

    try std.testing.expectError(
        error.GitCommandFailed,
        git.runGit(allocator, repo_path, &.{ "worktree", "remove", wt_path }),
    );

    const force_remove_output = try git.runGit(allocator, repo_path, &.{ "worktree", "remove", "--force", wt_path });
    allocator.free(force_remove_output);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(wt_path, .{}));
}

test "integration: detached worktree unique commit is detectable" {
    const allocator = std.testing.allocator;
    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    const wt_path = try worktree.computeWorktreePath(allocator, repo_path, "detached-int");
    defer {
        helpers.cleanupPath(allocator, wt_path);
        allocator.free(wt_path);
    }

    const add_output = try git.runGit(
        allocator,
        repo_path,
        &.{ "worktree", "add", "--detach", wt_path, "HEAD" },
    );
    allocator.free(add_output);

    const detached_file = try std.fs.path.join(allocator, &.{ wt_path, "detached.txt" });
    defer allocator.free(detached_file);
    try helpers.writeFile(detached_file, "detached\n");

    const add_detached_output = try git.runGit(allocator, wt_path, &.{ "add", "detached.txt" });
    allocator.free(add_detached_output);
    const detached_commit_output = try git.runGit(allocator, wt_path, &.{ "commit", "-m", "detached commit" });
    allocator.free(detached_commit_output);

    const detached_head_output = try git.runGit(allocator, wt_path, &.{ "rev-parse", "HEAD" });
    defer allocator.free(detached_head_output);
    const detached_head = std.mem.trim(u8, detached_head_output, " \t\r\n");

    const unique_commits = try git.countUnmergedCommits(
        allocator,
        repo_path,
        "HEAD",
        detached_head,
    );

    try std.testing.expectEqual(@as(usize, 1), unique_commits);
}

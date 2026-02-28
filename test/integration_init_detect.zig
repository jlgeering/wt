const std = @import("std");

const wt_lib = @import("wt_lib");
const init_planner = wt_lib.init_planner;
const helpers = @import("helpers.zig");

fn hasRecommendation(
    recs: []const init_planner.Recommendation,
    section: init_planner.Section,
    value: []const u8,
) bool {
    for (recs) |rec| {
        if (rec.section == section and std.mem.eql(u8, rec.value, value)) return true;
    }
    return false;
}

test "integration: fixture detects ignored local files in discovered subprojects" {
    const allocator = std.testing.allocator;
    const repo_path = try helpers.createTestRepo(allocator);
    defer {
        helpers.cleanupPath(allocator, repo_path);
        allocator.free(repo_path);
    }

    try helpers.copyFixtureTree(
        allocator,
        "test/fixtures/init_detect_ignored_locals",
        repo_path,
    );

    const git_visible = try helpers.runChecked(
        allocator,
        repo_path,
        &.{ "git", "ls-files", "--cached", "--others", "--exclude-standard" },
    );
    defer allocator.free(git_visible);

    try std.testing.expect(std.mem.indexOf(u8, git_visible, "apps/api/README.md") != null);
    try std.testing.expect(std.mem.indexOf(u8, git_visible, "apps/api/mise.local.toml") == null);
    try std.testing.expect(std.mem.indexOf(u8, git_visible, "apps/api/.claude/settings.local.json") == null);

    const recs = try init_planner.discoverRecommendationsWithOptions(allocator, repo_path, .{
        .assume_repo_mise_trusted = true,
    });
    defer init_planner.freeRecommendations(allocator, recs);

    try std.testing.expect(hasRecommendation(recs, .symlink, "apps/api/mise.local.toml"));
    try std.testing.expect(hasRecommendation(recs, .symlink, "apps/api/.claude/settings.local.json"));
    try std.testing.expect(hasRecommendation(recs, .run, "cd apps/api && mise trust"));
}

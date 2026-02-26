const std = @import("std");

const helpers = @import("helpers.zig");
const release_tool = @import("release_tool");

test "release tool: semver validation" {
    try std.testing.expect(release_tool.isValidSemver("0.1.2"));
    try std.testing.expect(release_tool.isValidSemver("10.20.30"));

    try std.testing.expect(!release_tool.isValidSemver("0.1"));
    try std.testing.expect(!release_tool.isValidSemver("0.1.2.3"));
    try std.testing.expect(!release_tool.isValidSemver("v0.1.2"));
    try std.testing.expect(!release_tool.isValidSemver("0.1.x"));
}

test "release tool: extract changelog section" {
    const allocator = std.testing.allocator;

    const changelog =
        \\## [0.2.0] - 2026-02-25
        \\- Added feature
        \\
        \\## [0.1.9] - 2026-02-24
        \\- Previous notes
        \\
    ;

    const notes = try release_tool.extractChangelogSectionAlloc(allocator, changelog, "0.2.0");
    defer allocator.free(notes);

    try std.testing.expectEqualStrings(
        "## [0.2.0] - 2026-02-25\n- Added feature\n\n",
        notes,
    );
}

test "release tool: extract changelog section missing" {
    const allocator = std.testing.allocator;

    const changelog =
        \\## [0.1.0] - 2026-02-24
        \\- Notes
        \\
    ;

    try std.testing.expectError(
        error.ReleaseToolFailed,
        release_tool.extractChangelogSectionAlloc(allocator, changelog, "0.2.0"),
    );
}

test "release tool: version parsing from build files" {
    const allocator = std.testing.allocator;

    const zon_content =
        \\.{
        \\    .name = "wt",
        \\    .version = "0.3.4",
        \\}
    ;

    const build_content =
        \\const app_version = b.option([]const u8, "app_version", "Application version string") orelse "0.3.4";
    ;

    const zon_version = try release_tool.extractZonVersionAlloc(allocator, zon_content);
    defer allocator.free(zon_version);
    try std.testing.expectEqualStrings("0.3.4", zon_version);

    const fallback_version = try release_tool.extractBuildFallbackVersionAlloc(allocator, build_content);
    defer allocator.free(fallback_version);
    try std.testing.expectEqualStrings("0.3.4", fallback_version);
}

test "release tool: checksum verification passes" {
    const allocator = std.testing.allocator;

    const temp_dir = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_dir);
        allocator.free(temp_dir);
    }

    const file_a = try std.fs.path.join(allocator, &.{ temp_dir, "a.txt" });
    defer allocator.free(file_a);
    const file_b = try std.fs.path.join(allocator, &.{ temp_dir, "b.txt" });
    defer allocator.free(file_b);

    try helpers.writeFile(file_a, "alpha\n");
    try helpers.writeFile(file_b, "beta\n");

    const hash_a = try release_tool.sha256FileHexAlloc(allocator, file_a);
    defer allocator.free(hash_a);
    const hash_b = try release_tool.sha256FileHexAlloc(allocator, file_b);
    defer allocator.free(hash_b);

    const sums = try std.fmt.allocPrint(allocator, "{s}  a.txt\n{s}  b.txt\n", .{ hash_a, hash_b });
    defer allocator.free(sums);

    try release_tool.verifySha256SumsContent(allocator, temp_dir, sums);
}

test "release tool: checksum verification fails on mismatch" {
    const allocator = std.testing.allocator;

    const temp_dir = try helpers.createTempDir(allocator);
    defer {
        helpers.cleanupPath(allocator, temp_dir);
        allocator.free(temp_dir);
    }

    const file_a = try std.fs.path.join(allocator, &.{ temp_dir, "a.txt" });
    defer allocator.free(file_a);
    try helpers.writeFile(file_a, "alpha\n");

    const sums = "0000000000000000000000000000000000000000000000000000000000000000  a.txt\n";

    try std.testing.expectError(
        error.ReleaseToolFailed,
        release_tool.verifySha256SumsContent(allocator, temp_dir, sums),
    );
}

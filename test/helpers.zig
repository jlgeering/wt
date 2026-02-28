const std = @import("std");

pub fn runChecked(
    allocator: std.mem.Allocator,
    cwd: ?[]const u8,
    argv: []const []const u8,
) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd,
    });
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code == 0) return result.stdout;
            allocator.free(result.stdout);
            return error.CommandFailed;
        },
        else => {
            allocator.free(result.stdout);
            return error.CommandFailed;
        },
    }
}

pub fn createTempDir(allocator: std.mem.Allocator) ![]u8 {
    const stdout = try runChecked(allocator, null, &.{ "mktemp", "-d" });
    defer allocator.free(stdout);

    const trimmed = std.mem.trimRight(u8, stdout, "\r\n");
    return std.fs.cwd().realpathAlloc(allocator, trimmed);
}

pub fn createTestRepo(allocator: std.mem.Allocator) ![]u8 {
    const repo_path = try createTempDir(allocator);
    errdefer cleanupPath(allocator, repo_path);
    errdefer allocator.free(repo_path);

    {
        const stdout = try runChecked(allocator, repo_path, &.{ "git", "init" });
        allocator.free(stdout);
    }
    {
        const stdout = try runChecked(
            allocator,
            repo_path,
            &.{ "git", "config", "user.email", "test@example.com" },
        );
        allocator.free(stdout);
    }
    {
        const stdout = try runChecked(
            allocator,
            repo_path,
            &.{ "git", "config", "user.name", "WT Test" },
        );
        allocator.free(stdout);
    }
    {
        const excludes_path = try std.fs.path.join(allocator, &.{ repo_path, ".gitignore-global-empty" });
        defer allocator.free(excludes_path);
        try writeFile(excludes_path, "");
        const stdout = try runChecked(
            allocator,
            repo_path,
            &.{ "git", "config", "--local", "core.excludesfile", excludes_path },
        );
        allocator.free(stdout);
    }
    {
        const stdout = try runChecked(
            allocator,
            repo_path,
            &.{ "git", "commit", "--allow-empty", "-m", "initial" },
        );
        allocator.free(stdout);
    }

    return repo_path;
}

pub fn cleanupPath(allocator: std.mem.Allocator, path: []const u8) void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "rm", "-rf", path },
    }) catch return;
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}

pub fn writeFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

pub fn readFileAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
}

pub fn copyFixtureTree(
    allocator: std.mem.Allocator,
    fixture_relative_path: []const u8,
    destination_path: []const u8,
) !void {
    const fixture_root = try std.fs.cwd().realpathAlloc(allocator, fixture_relative_path);
    defer allocator.free(fixture_root);

    try copyDirRecursive(allocator, fixture_root, destination_path);
}

fn copyDirRecursive(
    allocator: std.mem.Allocator,
    source_dir_path: []const u8,
    destination_dir_path: []const u8,
) !void {
    try std.fs.cwd().makePath(destination_dir_path);

    var source_dir = try std.fs.cwd().openDir(source_dir_path, .{ .iterate = true });
    defer source_dir.close();

    var iter = source_dir.iterate();
    while (try iter.next()) |entry| {
        const source_path = try std.fs.path.join(allocator, &.{ source_dir_path, entry.name });
        defer allocator.free(source_path);
        const destination_path = try std.fs.path.join(allocator, &.{ destination_dir_path, entry.name });
        defer allocator.free(destination_path);

        switch (entry.kind) {
            .directory => try copyDirRecursive(allocator, source_path, destination_path),
            .file => {
                const content = try std.fs.cwd().readFileAlloc(allocator, source_path, 16 * 1024 * 1024);
                defer allocator.free(content);
                try writeFile(destination_path, content);
            },
            .sym_link => {
                var link_buf: [std.fs.max_path_bytes]u8 = undefined;
                const link_target = try std.fs.cwd().readLink(source_path, &link_buf);
                try std.fs.cwd().symLink(link_target, destination_path, .{});
            },
            else => {},
        }
    }
}

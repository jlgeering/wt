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

const std = @import("std");
const builtin = @import("builtin");
const config_mod = @import("config.zig");
const ui = @import("ui.zig");

pub const LogMode = enum {
    human,
    quiet,
};

const PathValidationIssue = enum {
    empty,
    absolute,
    traversal,
};

fn logMessage(level: ui.Level, comptime fmt: []const u8, args: anytype) void {
    const stderr_file = std.fs.File.stderr();
    const stderr = stderr_file.deprecatedWriter();
    const use_color = ui.shouldUseColor(stderr_file);
    ui.printLevel(stderr, use_color, level, fmt, args) catch {};
}

fn isPathSeparator(char: u8) bool {
    return char == '/' or char == '\\';
}

fn hasWindowsDrivePrefix(path: []const u8) bool {
    return path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':';
}

fn hasParentTraversalSegment(path: []const u8) bool {
    var start: usize = 0;
    while (start <= path.len) {
        var end = start;
        while (end < path.len and !isPathSeparator(path[end])) : (end += 1) {}

        if (std.mem.eql(u8, path[start..end], "..")) return true;

        if (end == path.len) break;
        start = end + 1;
    }
    return false;
}

fn detectUnsafeRelPath(rel_path: []const u8) ?PathValidationIssue {
    const trimmed = std.mem.trim(u8, rel_path, " \t\r\n");
    if (trimmed.len == 0) return .empty;
    if (std.fs.path.isAbsolute(trimmed) or hasWindowsDrivePrefix(trimmed)) return .absolute;
    if (hasParentTraversalSegment(trimmed)) return .traversal;
    return null;
}

fn pathIssueLabel(issue: PathValidationIssue) []const u8 {
    return switch (issue) {
        .empty => "empty path",
        .absolute => "absolute path",
        .traversal => "parent traversal",
    };
}

/// Copy a path from source to target using copy-on-write where available.
/// Shells out to `cp` for CoW support. Skips if source missing or target exists.
pub fn cowCopy(
    allocator: std.mem.Allocator,
    source_root: []const u8,
    target_root: []const u8,
    rel_path: []const u8,
    mode: LogMode,
) !void {
    if (detectUnsafeRelPath(rel_path)) |issue| {
        logMessage(.warn, "skip copy {s}: invalid setup path ({s})", .{ rel_path, pathIssueLabel(issue) });
        return;
    }

    const source = try std.fs.path.join(allocator, &.{ source_root, rel_path });
    defer allocator.free(source);
    const target = try std.fs.path.join(allocator, &.{ target_root, rel_path });
    defer allocator.free(target);

    // Check source exists
    std.fs.cwd().access(source, .{}) catch {
        if (mode == .human) {
            logMessage(.info, "skip copy {s}: source doesn't exist", .{rel_path});
        }
        return;
    };

    // Check target doesn't already exist
    if (std.fs.cwd().access(target, .{})) |_| {
        if (mode == .human) {
            logMessage(.info, "skip copy {s}: already exists", .{rel_path});
        }
        return;
    } else |_| {}

    // Ensure parent directory exists
    if (std.fs.path.dirname(target)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }

    // Platform-specific CoW copy
    const cp_args: []const []const u8 = switch (builtin.os.tag) {
        .macos => &.{ "cp", "-cR", source, target },
        .linux => &.{ "cp", "-R", "--reflink=auto", source, target },
        else => &.{ "cp", "-R", source, target },
    };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = cp_args,
    }) catch {
        logMessage(.warn, "copy failed for {s}", .{rel_path});
        return;
    };
    allocator.free(result.stdout);
    allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                logMessage(.warn, "copy failed for {s}", .{rel_path});
                return;
            }
        },
        else => {
            logMessage(.warn, "copy failed for {s}", .{rel_path});
            return;
        },
    }

    if (mode == .human) {
        logMessage(.success, "copied (CoW) {s}", .{rel_path});
    }
}

/// Create a symlink from target_root/rel_path -> source_root/rel_path.
/// Skips if target already exists.
pub fn createSymlink(
    allocator: std.mem.Allocator,
    source_root: []const u8,
    target_root: []const u8,
    rel_path: []const u8,
    mode: LogMode,
) !void {
    if (detectUnsafeRelPath(rel_path)) |issue| {
        logMessage(.warn, "skip symlink {s}: invalid setup path ({s})", .{ rel_path, pathIssueLabel(issue) });
        return;
    }

    const source = try std.fs.path.join(allocator, &.{ source_root, rel_path });
    defer allocator.free(source);
    const target = try std.fs.path.join(allocator, &.{ target_root, rel_path });
    defer allocator.free(target);

    // Check source exists
    std.fs.cwd().access(source, .{}) catch {
        if (mode == .human) {
            logMessage(.info, "skip symlink {s}: source doesn't exist", .{rel_path});
        }
        return;
    };

    // Check target doesn't already exist
    if (std.fs.cwd().access(target, .{})) |_| {
        if (mode == .human) {
            logMessage(.info, "skip symlink {s}: already exists", .{rel_path});
        }
        return;
    } else |_| {}

    // Ensure parent directory exists
    if (std.fs.path.dirname(target)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }

    std.fs.symLinkAbsolute(source, target, .{}) catch {
        logMessage(.warn, "symlink failed for {s}", .{rel_path});
        return;
    };

    if (mode == .human) {
        logMessage(.success, "symlinked {s}", .{rel_path});
    }
}

/// Run post-setup commands in the given working directory.
/// Warns on failure but continues to next command.
pub fn runSetupCommands(
    allocator: std.mem.Allocator,
    cwd: []const u8,
    commands: []const []const u8,
    mode: LogMode,
) !void {
    for (commands) |cmd| {
        if (mode == .human) {
            logMessage(.info, "running: {s}", .{cmd});
        }

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "sh", "-c", cmd },
            .cwd = cwd,
        }) catch {
            logMessage(.warn, "failed to run '{s}'", .{cmd});
            continue;
        };
        allocator.free(result.stdout);
        allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code != 0) {
                    logMessage(.warn, "'{s}' exited with code {d}", .{ cmd, code });
                }
            },
            else => {
                logMessage(.warn, "'{s}' terminated abnormally", .{cmd});
            },
        }
    }
}

/// Run all setup operations from a Config on a new worktree.
pub fn runAllSetup(
    allocator: std.mem.Allocator,
    cfg: config_mod.Config,
    main_path: []const u8,
    worktree_path: []const u8,
    mode: LogMode,
) !void {
    for (cfg.copyPaths()) |path| {
        try cowCopy(allocator, main_path, worktree_path, path, mode);
    }

    for (cfg.symlinkPaths()) |path| {
        try createSymlink(allocator, main_path, worktree_path, path, mode);
    }

    try runSetupCommands(allocator, worktree_path, cfg.runCommands(), mode);
}

// Setup operations are filesystem-heavy; tested via integration tests.
test "placeholder" {}

test "detectUnsafeRelPath accepts normal relative paths" {
    try std.testing.expect(detectUnsafeRelPath(".env") == null);
    try std.testing.expect(detectUnsafeRelPath("config/app.toml") == null);
    try std.testing.expect(detectUnsafeRelPath("nested\\path\\file.txt") == null);
}

test "detectUnsafeRelPath rejects empty and traversal paths" {
    try std.testing.expectEqual(PathValidationIssue.empty, detectUnsafeRelPath(" \t\n").?);
    try std.testing.expectEqual(PathValidationIssue.traversal, detectUnsafeRelPath("../secret").?);
    try std.testing.expectEqual(PathValidationIssue.traversal, detectUnsafeRelPath("safe/../../secret").?);
    try std.testing.expectEqual(PathValidationIssue.traversal, detectUnsafeRelPath("safe\\..\\secret").?);
}

test "detectUnsafeRelPath rejects absolute paths" {
    const absolute_sample = if (builtin.os.tag == .windows) "C:\\tmp\\file" else "/tmp/file";
    try std.testing.expectEqual(PathValidationIssue.absolute, detectUnsafeRelPath(absolute_sample).?);
    try std.testing.expectEqual(PathValidationIssue.absolute, detectUnsafeRelPath("D:\\data").?);
}

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

fn copyPathPortable(allocator: std.mem.Allocator, source: []const u8, target: []const u8) !void {
    var source_dir = std.fs.cwd().openDir(source, .{ .iterate = true }) catch |err| switch (err) {
        error.NotDir => {
            if (std.fs.path.dirname(target)) |parent| {
                try std.fs.cwd().makePath(parent);
            }
            try std.fs.cwd().copyFile(source, std.fs.cwd(), target, .{});
            return;
        },
        else => return err,
    };
    defer source_dir.close();

    try std.fs.cwd().makePath(target);

    var walker = try source_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const entry_target = try std.fs.path.join(allocator, &.{ target, entry.path });
        defer allocator.free(entry_target);

        if (std.fs.path.dirname(entry_target)) |parent| {
            try std.fs.cwd().makePath(parent);
        }

        switch (entry.kind) {
            .directory => try std.fs.cwd().makePath(entry_target),
            .file => try source_dir.copyFile(entry.path, std.fs.cwd(), entry_target, .{}),
            .sym_link => {
                var link_target_buf: [std.fs.max_path_bytes]u8 = undefined;
                const link_target = try source_dir.readLink(entry.path, &link_target_buf);
                try std.fs.cwd().symLink(link_target, entry_target, .{});
            },
            else => return error.UnsupportedSetupCopyEntryKind,
        }
    }
}

/// Copy a path from source to target using copy-on-write where available.
/// Uses native filesystem APIs on Windows. Skips if source missing or target exists.
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

    const used_cow = switch (builtin.os.tag) {
        .windows => false,
        else => true,
    };

    if (builtin.os.tag == .windows) {
        copyPathPortable(allocator, source, target) catch {
            logMessage(.warn, "copy failed for {s}", .{rel_path});
            return;
        };
    } else {
        // Platform-specific CoW copy.
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
    }

    if (mode == .human) {
        if (used_cow) {
            logMessage(.success, "copied (CoW) {s}", .{rel_path});
        } else {
            logMessage(.success, "copied {s}", .{rel_path});
        }
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

test "copyPathPortable copies single file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "source.txt",
        .data = "portable copy payload\n",
    });

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const source = try std.fs.path.join(std.testing.allocator, &.{ root, "source.txt" });
    defer std.testing.allocator.free(source);
    const target = try std.fs.path.join(std.testing.allocator, &.{ root, "nested", "target.txt" });
    defer std.testing.allocator.free(target);

    try copyPathPortable(std.testing.allocator, source, target);

    const copied = try std.fs.cwd().readFileAlloc(std.testing.allocator, target, 1024);
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings("portable copy payload\n", copied);
}

test "copyPathPortable copies directory tree" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("source/subdir/beta");
    try tmp.dir.writeFile(.{
        .sub_path = "source/subdir/alpha.txt",
        .data = "alpha\n",
    });
    try tmp.dir.writeFile(.{
        .sub_path = "source/subdir/beta/gamma.txt",
        .data = "gamma\n",
    });

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const source = try std.fs.path.join(std.testing.allocator, &.{ root, "source" });
    defer std.testing.allocator.free(source);
    const target = try std.fs.path.join(std.testing.allocator, &.{ root, "copied" });
    defer std.testing.allocator.free(target);

    try copyPathPortable(std.testing.allocator, source, target);

    const alpha = try std.fs.path.join(std.testing.allocator, &.{ target, "subdir", "alpha.txt" });
    defer std.testing.allocator.free(alpha);
    const gamma = try std.fs.path.join(std.testing.allocator, &.{ target, "subdir", "beta", "gamma.txt" });
    defer std.testing.allocator.free(gamma);

    const alpha_data = try std.fs.cwd().readFileAlloc(std.testing.allocator, alpha, 1024);
    defer std.testing.allocator.free(alpha_data);
    try std.testing.expectEqualStrings("alpha\n", alpha_data);

    const gamma_data = try std.fs.cwd().readFileAlloc(std.testing.allocator, gamma, 1024);
    defer std.testing.allocator.free(gamma_data);
    try std.testing.expectEqualStrings("gamma\n", gamma_data);
}

const std = @import("std");
const builtin = @import("builtin");
const config_mod = @import("config.zig");
const ui = @import("ui.zig");

pub const LogMode = enum {
    human,
    machine,
    silent,
};

const SetupShell = struct {
    program: []const u8,
    command_flag: []const u8,
};

const PathValidationIssue = enum {
    empty,
    absolute,
    traversal,
};

fn shouldEmitLog(mode: LogMode, level: ui.Level) bool {
    return switch (mode) {
        .human => true,
        .machine => switch (level) {
            .warn, .err => true,
            else => false,
        },
        .silent => false,
    };
}

fn logMessage(mode: LogMode, level: ui.Level, comptime fmt: []const u8, args: anytype) void {
    if (!shouldEmitLog(mode, level)) return;

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

fn setupShellForOs(os_tag: std.Target.Os.Tag) SetupShell {
    return switch (os_tag) {
        .windows => .{ .program = "cmd.exe", .command_flag = "/C" },
        else => .{ .program = "sh", .command_flag = "-c" },
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
        logMessage(mode, .warn, "skip copy {s}: invalid setup path ({s})", .{ rel_path, pathIssueLabel(issue) });
        return;
    }

    const source = try std.fs.path.join(allocator, &.{ source_root, rel_path });
    defer allocator.free(source);
    const target = try std.fs.path.join(allocator, &.{ target_root, rel_path });
    defer allocator.free(target);

    // Check source exists
    std.fs.cwd().access(source, .{}) catch {
        if (mode == .human) {
            logMessage(mode, .info, "skip copy {s}: source doesn't exist", .{rel_path});
        }
        return;
    };

    // Check target doesn't already exist
    if (std.fs.cwd().access(target, .{})) |_| {
        if (mode == .human) {
            logMessage(mode, .info, "skip copy {s}: already exists", .{rel_path});
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
            logMessage(mode, .warn, "copy failed for {s}", .{rel_path});
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
            logMessage(mode, .warn, "copy failed for {s}", .{rel_path});
            return;
        };
        allocator.free(result.stdout);
        allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code != 0) {
                    logMessage(mode, .warn, "copy failed for {s}", .{rel_path});
                    return;
                }
            },
            else => {
                logMessage(mode, .warn, "copy failed for {s}", .{rel_path});
                return;
            },
        }
    }

    if (mode == .human) {
        if (used_cow) {
            logMessage(mode, .success, "copied (CoW) {s}", .{rel_path});
        } else {
            logMessage(mode, .success, "copied {s}", .{rel_path});
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
        logMessage(mode, .warn, "skip symlink {s}: invalid setup path ({s})", .{ rel_path, pathIssueLabel(issue) });
        return;
    }

    const source = try std.fs.path.join(allocator, &.{ source_root, rel_path });
    defer allocator.free(source);
    const target = try std.fs.path.join(allocator, &.{ target_root, rel_path });
    defer allocator.free(target);

    // Check source exists
    std.fs.cwd().access(source, .{}) catch {
        if (mode == .human) {
            logMessage(mode, .info, "skip symlink {s}: source doesn't exist", .{rel_path});
        }
        return;
    };

    // Check target doesn't already exist
    if (std.fs.cwd().access(target, .{})) |_| {
        if (mode == .human) {
            logMessage(mode, .info, "skip symlink {s}: already exists", .{rel_path});
        }
        return;
    } else |_| {}

    // Ensure parent directory exists
    if (std.fs.path.dirname(target)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }

    std.fs.symLinkAbsolute(source, target, .{}) catch {
        logMessage(mode, .warn, "symlink failed for {s}", .{rel_path});
        return;
    };

    if (mode == .human) {
        logMessage(mode, .success, "symlinked {s}", .{rel_path});
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
    const shell = setupShellForOs(builtin.os.tag);

    for (commands) |cmd| {
        if (mode == .human) {
            logMessage(mode, .info, "running: {s}", .{cmd});
        }

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ shell.program, shell.command_flag, cmd },
            .cwd = cwd,
        }) catch {
            logMessage(mode, .warn, "failed to run '{s}'", .{cmd});
            continue;
        };
        allocator.free(result.stdout);
        allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code != 0) {
                    logMessage(mode, .warn, "'{s}' exited with code {d}", .{ cmd, code });
                }
            },
            else => {
                logMessage(mode, .warn, "'{s}' terminated abnormally", .{cmd});
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

test "setupShellForOs picks shell command for each platform" {
    const windows_shell = setupShellForOs(.windows);
    try std.testing.expectEqualStrings("cmd.exe", windows_shell.program);
    try std.testing.expectEqualStrings("/C", windows_shell.command_flag);

    const linux_shell = setupShellForOs(.linux);
    try std.testing.expectEqualStrings("sh", linux_shell.program);
    try std.testing.expectEqualStrings("-c", linux_shell.command_flag);
}

test "shouldEmitLog enforces mode visibility policy" {
    try std.testing.expect(shouldEmitLog(.human, .info));
    try std.testing.expect(shouldEmitLog(.human, .success));
    try std.testing.expect(shouldEmitLog(.human, .warn));
    try std.testing.expect(shouldEmitLog(.human, .err));

    try std.testing.expect(!shouldEmitLog(.machine, .info));
    try std.testing.expect(!shouldEmitLog(.machine, .success));
    try std.testing.expect(shouldEmitLog(.machine, .warn));
    try std.testing.expect(shouldEmitLog(.machine, .err));

    try std.testing.expect(!shouldEmitLog(.silent, .info));
    try std.testing.expect(!shouldEmitLog(.silent, .success));
    try std.testing.expect(!shouldEmitLog(.silent, .warn));
    try std.testing.expect(!shouldEmitLog(.silent, .err));
}

test "runSetupCommands continues after command failure" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(cwd);

    const commands: []const []const u8 = switch (builtin.os.tag) {
        .windows => &.{ "exit /b 1", "echo after-failure>marker.txt" },
        else => &.{ "false", "printf after-failure > marker.txt" },
    };

    try runSetupCommands(std.testing.allocator, cwd, commands, .silent);

    const marker_path = try std.fs.path.join(std.testing.allocator, &.{ cwd, "marker.txt" });
    defer std.testing.allocator.free(marker_path);

    const marker_content = try std.fs.cwd().readFileAlloc(std.testing.allocator, marker_path, 1024);
    defer std.testing.allocator.free(marker_content);
    const marker_trimmed = std.mem.trim(u8, marker_content, " \t\r\n");
    try std.testing.expectEqualStrings("after-failure", marker_trimmed);
}

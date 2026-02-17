const std = @import("std");
const builtin = @import("builtin");
const config_mod = @import("config.zig");

/// Copy a path from source to target using copy-on-write where available.
/// Shells out to `cp` for CoW support. Skips if source missing or target exists.
pub fn cowCopy(allocator: std.mem.Allocator, source_root: []const u8, target_root: []const u8, rel_path: []const u8) !void {
    const source = try std.fs.path.join(allocator, &.{ source_root, rel_path });
    defer allocator.free(source);
    const target = try std.fs.path.join(allocator, &.{ target_root, rel_path });
    defer allocator.free(target);

    // Check source exists
    std.fs.cwd().access(source, .{}) catch {
        std.debug.print("  skip copy {s}: source doesn't exist\n", .{rel_path});
        return;
    };

    // Check target doesn't already exist
    if (std.fs.cwd().access(target, .{})) |_| {
        std.debug.print("  skip copy {s}: already exists\n", .{rel_path});
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
        std.debug.print("  WARN: copy failed for {s}\n", .{rel_path});
        return;
    };
    allocator.free(result.stdout);
    allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("  WARN: copy failed for {s}\n", .{rel_path});
                return;
            }
        },
        else => {
            std.debug.print("  WARN: copy failed for {s}\n", .{rel_path});
            return;
        },
    }

    std.debug.print("  copied (CoW) {s}\n", .{rel_path});
}

/// Create a symlink from target_root/rel_path -> source_root/rel_path.
/// Skips if target already exists.
pub fn createSymlink(allocator: std.mem.Allocator, source_root: []const u8, target_root: []const u8, rel_path: []const u8) !void {
    const source = try std.fs.path.join(allocator, &.{ source_root, rel_path });
    defer allocator.free(source);
    const target = try std.fs.path.join(allocator, &.{ target_root, rel_path });
    defer allocator.free(target);

    // Check source exists
    std.fs.cwd().access(source, .{}) catch {
        std.debug.print("  skip symlink {s}: source doesn't exist\n", .{rel_path});
        return;
    };

    // Check target doesn't already exist
    if (std.fs.cwd().access(target, .{})) |_| {
        std.debug.print("  skip symlink {s}: already exists\n", .{rel_path});
        return;
    } else |_| {}

    // Ensure parent directory exists
    if (std.fs.path.dirname(target)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }

    std.fs.symLinkAbsolute(source, target, .{}) catch {
        std.debug.print("  WARN: symlink failed for {s}\n", .{rel_path});
        return;
    };

    std.debug.print("  symlinked {s}\n", .{rel_path});
}

/// Run post-setup commands in the given working directory.
/// Warns on failure but continues to next command.
pub fn runSetupCommands(allocator: std.mem.Allocator, cwd: []const u8, commands: []const []const u8) !void {
    for (commands) |cmd| {
        std.debug.print("  running: {s}\n", .{cmd});

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "sh", "-c", cmd },
            .cwd = cwd,
        }) catch {
            std.debug.print("  WARN: failed to run '{s}'\n", .{cmd});
            continue;
        };
        allocator.free(result.stdout);
        allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code != 0) {
                    std.debug.print("  WARN: '{s}' exited with code {d}\n", .{ cmd, code });
                }
            },
            else => {
                std.debug.print("  WARN: '{s}' terminated abnormally\n", .{cmd});
            },
        }
    }
}

/// Run all setup operations from a Config on a new worktree.
pub fn runAllSetup(allocator: std.mem.Allocator, cfg: config_mod.Config, main_path: []const u8, worktree_path: []const u8) !void {
    for (cfg.copyPaths()) |path| {
        try cowCopy(allocator, main_path, worktree_path, path);
    }

    for (cfg.symlinkPaths()) |path| {
        try createSymlink(allocator, main_path, worktree_path, path);
    }

    try runSetupCommands(allocator, worktree_path, cfg.runCommands());
}

// Setup operations are filesystem-heavy; tested via integration tests.
test "placeholder" {}

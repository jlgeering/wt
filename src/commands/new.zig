const std = @import("std");
const git = @import("../lib/git.zig");
const worktree = @import("../lib/worktree.zig");
const config = @import("../lib/config.zig");
const setup = @import("../lib/setup.zig");

fn shouldPrintPathToStdout(porcelain: bool) bool {
    return porcelain;
}

fn shouldPrintHumanStatus(porcelain: bool) bool {
    return !porcelain;
}

pub fn run(allocator: std.mem.Allocator, branch: []const u8, base: []const u8, porcelain: bool) !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();

    // Find main worktree (first in list)
    const wt_output = git.runGit(allocator, null, &.{ "worktree", "list", "--porcelain" }) catch {
        std.debug.print("Error: not a git repository or git not found\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(wt_output);

    const worktrees = try git.parseWorktreeList(allocator, wt_output);
    defer allocator.free(worktrees);

    if (worktrees.len == 0) {
        std.debug.print("Error: no worktrees found\n", .{});
        std.process.exit(1);
    }

    const main_path = worktrees[0].path;
    const wt_path = try worktree.computeWorktreePath(allocator, main_path, branch);
    defer allocator.free(wt_path);

    // Check if worktree already exists
    if (std.fs.cwd().access(wt_path, .{})) |_| {
        if (shouldPrintHumanStatus(porcelain)) {
            std.debug.print("Worktree already exists at {s}\n", .{wt_path});
        }
        if (shouldPrintPathToStdout(porcelain)) {
            try stdout.print("{s}\n", .{wt_path});
        }
        return;
    } else |_| {}

    // Check if branch already exists
    const branch_exists = if (git.runGit(allocator, null, &.{ "rev-parse", "--verify", branch })) |out| blk: {
        allocator.free(out);
        break :blk true;
    } else |_| false;

    if (branch_exists) {
        // Check branch isn't already used by another worktree
        for (worktrees) |wt| {
            if (wt.branch) |b| {
                if (std.mem.eql(u8, b, branch)) {
                    std.debug.print("Error: branch '{s}' already checked out in {s}\n", .{ branch, wt.path });
                    std.process.exit(1);
                }
            }
        }

        if (shouldPrintHumanStatus(porcelain)) {
            std.debug.print("Using existing branch '{s}'\n", .{branch});
        }
        const add_result = git.runGit(allocator, null, &.{ "worktree", "add", wt_path, branch }) catch {
            std.debug.print("Error creating worktree\n", .{});
            std.process.exit(1);
        };
        allocator.free(add_result);
    } else {
        const add_result = git.runGit(allocator, null, &.{ "worktree", "add", "-b", branch, wt_path, base }) catch {
            std.debug.print("Error creating worktree\n", .{});
            std.process.exit(1);
        };
        allocator.free(add_result);
    }

    if (shouldPrintHumanStatus(porcelain)) {
        std.debug.print("Created worktree at {s}\n", .{wt_path});
    }

    // Load config and run setup
    var cfg = try config.loadConfigFile(allocator, main_path);
    defer cfg.deinit();

    const log_mode: setup.LogMode = if (porcelain) .quiet else .human;
    try setup.runAllSetup(allocator, cfg.value, main_path, wt_path, log_mode);

    // Print path to stdout for machine mode.
    if (shouldPrintPathToStdout(porcelain)) {
        try stdout.print("{s}\n", .{wt_path});
    }
}

test "human mode emits status not machine path" {
    try std.testing.expect(shouldPrintHumanStatus(false));
    try std.testing.expect(!shouldPrintPathToStdout(false));
}

test "porcelain mode emits machine path not status" {
    try std.testing.expect(!shouldPrintHumanStatus(true));
    try std.testing.expect(shouldPrintPathToStdout(true));
}

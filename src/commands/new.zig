const std = @import("std");
const git = @import("../lib/git.zig");
const worktree = @import("../lib/worktree.zig");
const config = @import("../lib/config.zig");
const setup = @import("../lib/setup.zig");
const ui = @import("../lib/ui.zig");

const OutputMode = enum {
    human,
    machine,
};

fn isRegisteredWorktreePath(worktrees: []const git.WorktreeInfo, path: []const u8) bool {
    for (worktrees) |wt| {
        if (std.mem.eql(u8, wt.path, path)) return true;
    }
    return false;
}

fn runWithMode(allocator: std.mem.Allocator, branch: []const u8, base: []const u8, mode: OutputMode) !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();
    const use_color = ui.shouldUseColor(std.fs.File.stderr());
    const is_machine = mode == .machine;

    // Find main worktree (first in list)
    const wt_output = git.runGit(allocator, null, &.{ "worktree", "list", "--porcelain" }) catch {
        try ui.printLevel(stderr, use_color, .err, "not a git repository or git not found", .{});
        std.process.exit(1);
    };
    defer allocator.free(wt_output);

    const worktrees = try git.parseWorktreeList(allocator, wt_output);
    defer allocator.free(worktrees);

    if (worktrees.len == 0) {
        try ui.printLevel(stderr, use_color, .err, "no worktrees found", .{});
        std.process.exit(1);
    }

    const main_path = worktrees[0].path;
    const wt_path = try worktree.computeWorktreePath(allocator, main_path, branch);
    defer allocator.free(wt_path);

    // Check if worktree already exists
    if (std.fs.cwd().access(wt_path, .{})) |_| {
        if (!isRegisteredWorktreePath(worktrees, wt_path)) {
            try ui.printLevel(stderr, use_color, .err, "path collision at {s}: exists but is not a git worktree", .{wt_path});
            try ui.printLevel(stderr, use_color, .info, "remove or rename the path, then run `wt new` again", .{});
            std.process.exit(1);
        }

        if (!is_machine) {
            try ui.printLevel(stderr, use_color, .warn, "worktree already exists at {s}", .{wt_path});
        }
        if (is_machine) {
            try stdout.print("{s}\n", .{wt_path});
        }
        return;
    } else |_| {}

    // Check if local branch already exists (ignore tags/other refs with the same name).
    const branch_ref = try std.fmt.allocPrint(allocator, "refs/heads/{s}", .{branch});
    defer allocator.free(branch_ref);
    const branch_exists = if (git.runGit(allocator, null, &.{ "rev-parse", "--verify", branch_ref })) |out| blk: {
        allocator.free(out);
        break :blk true;
    } else |_| false;

    if (branch_exists) {
        // Check branch isn't already used by another worktree
        for (worktrees) |wt| {
            if (wt.branch) |b| {
                if (std.mem.eql(u8, b, branch)) {
                    try ui.printLevel(
                        stderr,
                        use_color,
                        .err,
                        "branch '{s}' is already checked out in {s}",
                        .{ branch, wt.path },
                    );
                    std.process.exit(1);
                }
            }
        }

        if (!is_machine) {
            try ui.printLevel(stderr, use_color, .info, "using existing branch '{s}'", .{branch});
        }
        const add_result = git.runGit(allocator, null, &.{ "worktree", "add", wt_path, branch }) catch {
            try ui.printLevel(stderr, use_color, .err, "failed to create worktree", .{});
            std.process.exit(1);
        };
        allocator.free(add_result);
    } else {
        const add_result = git.runGit(allocator, null, &.{ "worktree", "add", "-b", branch, wt_path, base }) catch {
            try ui.printLevel(stderr, use_color, .err, "failed to create worktree", .{});
            std.process.exit(1);
        };
        allocator.free(add_result);
    }

    if (!is_machine) {
        try ui.printLevel(stderr, use_color, .success, "created worktree at {s}", .{wt_path});
    }

    // Load config and run setup
    var cfg = try config.loadConfigFile(allocator, main_path);
    defer cfg.deinit();

    const log_mode: setup.LogMode = if (is_machine) .quiet else .human;
    try setup.runAllSetup(allocator, cfg.value, main_path, wt_path, log_mode);

    if (is_machine) {
        try stdout.print("{s}\n", .{wt_path});
    }
}

pub fn runHuman(allocator: std.mem.Allocator, branch: []const u8, base: []const u8) !void {
    try runWithMode(allocator, branch, base, .human);
}

pub fn runMachine(allocator: std.mem.Allocator, branch: []const u8, base: []const u8) !void {
    try runWithMode(allocator, branch, base, .machine);
}

test "isRegisteredWorktreePath returns true only for listed worktrees" {
    const worktrees = [_]git.WorktreeInfo{
        .{ .path = "/tmp/repo", .head = "abc", .branch = "main", .is_bare = false },
        .{ .path = "/tmp/repo--feat", .head = "def", .branch = "feat", .is_bare = false },
    };

    try std.testing.expect(isRegisteredWorktreePath(&worktrees, "/tmp/repo--feat"));
    try std.testing.expect(!isRegisteredWorktreePath(&worktrees, "/tmp/repo--other"));
}

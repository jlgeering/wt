const std = @import("std");
const git = @import("../lib/git.zig");

pub fn run(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    // Get current working directory
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    // Get worktree list
    const wt_output = git.runGit(allocator, null, &.{ "worktree", "list", "--porcelain" }) catch {
        std.debug.print("Error: not a git repository or git not found\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(wt_output);

    const worktrees = try git.parseWorktreeList(allocator, wt_output);
    defer allocator.free(worktrees);

    if (worktrees.len == 0) {
        std.debug.print("No worktrees found\n", .{});
        return;
    }

    for (worktrees) |wt| {
        const is_current = std.mem.eql(u8, cwd, wt.path);
        const marker: []const u8 = if (is_current) "*" else " ";
        const branch_name = wt.branch orelse "(detached)";

        // Get status for this worktree
        const status_output = git.runGit(allocator, wt.path, &.{ "status", "--porcelain" }) catch {
            try stdout.print("{s} {s:<20} {s}\n", .{ marker, branch_name, wt.path });
            continue;
        };
        defer allocator.free(status_output);

        const status = git.parseStatusPorcelain(status_output);

        if (status.modified == 0 and status.untracked == 0) {
            try stdout.print("{s} {s:<20} {s}  (clean)\n", .{ marker, branch_name, wt.path });
        } else {
            // Build status string
            var buf: [64]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buf);
            const w = fbs.writer();
            if (status.modified > 0) {
                w.print("{d} modified", .{status.modified}) catch {};
            }
            if (status.untracked > 0) {
                if (status.modified > 0) w.print(", ", .{}) catch {};
                w.print("{d} untracked", .{status.untracked}) catch {};
            }
            try stdout.print("{s} {s:<20} {s}  ({s})\n", .{ marker, branch_name, wt.path, fbs.getWritten() });
        }
    }
}

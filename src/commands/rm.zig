const std = @import("std");
const git = @import("../lib/git.zig");
const worktree = @import("../lib/worktree.zig");

pub fn run(allocator: std.mem.Allocator, branch_arg: ?[]const u8, force: bool) !void {
    const stdout = std.io.getStdOut().writer();

    // Get worktree list
    const wt_output = git.runGit(allocator, null, &.{ "worktree", "list", "--porcelain" }) catch {
        std.debug.print("Error: not a git repository or git not found\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(wt_output);

    const worktrees = try git.parseWorktreeList(allocator, wt_output);
    defer allocator.free(worktrees);

    if (worktrees.len < 2) {
        std.debug.print("No secondary worktrees to remove\n", .{});
        return;
    }

    const main_path = worktrees[0].path;

    const branch = branch_arg orelse {
        // No branch specified: list worktrees with safety status for picker
        for (worktrees[1..]) |wt| {
            const branch_name = wt.branch orelse "(detached)";

            const status_output = git.runGit(allocator, wt.path, &.{ "status", "--porcelain" }) catch {
                try stdout.print("{s}\t{s}\tunknown\n", .{ branch_name, wt.path });
                continue;
            };
            defer allocator.free(status_output);

            const status = git.parseStatusPorcelain(status_output);
            const safety: []const u8 = if (status.modified == 0 and status.untracked == 0) "safe" else "dirty";
            try stdout.print("{s}\t{s}\t{s}\n", .{ branch_name, wt.path, safety });
        }
        return;
    };

    // Find the worktree for this branch
    const wt_path = try worktree.computeWorktreePath(allocator, main_path, branch);
    defer allocator.free(wt_path);

    // Check it exists
    std.fs.cwd().access(wt_path, .{}) catch {
        std.debug.print("Error: worktree at {s} does not exist\n", .{wt_path});
        std.process.exit(1);
    };

    // Safety check: uncommitted changes
    if (!force) {
        const status_output = git.runGit(allocator, wt_path, &.{ "status", "--porcelain" }) catch {
            std.debug.print("Warning: could not check worktree status\n", .{});
            std.process.exit(1);
        };
        defer allocator.free(status_output);

        const status = git.parseStatusPorcelain(status_output);
        if (status.modified > 0 or status.untracked > 0) {
            std.debug.print("Error: worktree has {d} modified and {d} untracked files\n", .{ status.modified, status.untracked });
            std.debug.print("Use --force to remove anyway\n", .{});
            std.process.exit(1);
        }
    }

    // Remove worktree
    if (force) {
        const rm_result = git.runGit(allocator, null, &.{ "worktree", "remove", "--force", wt_path }) catch {
            std.debug.print("Error: could not remove worktree\n", .{});
            std.process.exit(1);
        };
        allocator.free(rm_result);
    } else {
        const rm_result = git.runGit(allocator, null, &.{ "worktree", "remove", wt_path }) catch {
            std.debug.print("Error: could not remove worktree\n", .{});
            std.process.exit(1);
        };
        allocator.free(rm_result);
    }

    std.debug.print("Removed worktree {s}\n", .{wt_path});

    // Try to delete branch if fully merged
    const del_result = git.runGit(allocator, main_path, &.{ "branch", "-d", branch }) catch {
        std.debug.print("Branch '{s}' kept (has unmerged commits)\n", .{branch});
        return;
    };
    allocator.free(del_result);

    std.debug.print("Deleted merged branch '{s}'\n", .{branch});
}

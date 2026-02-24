const std = @import("std");
const git = @import("../lib/git.zig");
const worktree_status = @import("../lib/worktree_status.zig");

fn writeHumanHeader(stdout: anytype) !void {
    try stdout.writeAll("CUR BRANCH                STATUS                  PATH\n");
    try stdout.writeAll("--- -------------------- ----------------------- ------------------------------\n");
}

fn writeHumanRow(stdout: anytype, row: worktree_status.WorktreeRow) !void {
    const marker: []const u8 = if (row.is_current) "*" else " ";
    var buf: [128]u8 = undefined;
    const summary = worktree_status.humanStatusSummary(row, &buf);
    try stdout.print("{s}   {s:<20} {s:<23} {s}\n", .{ marker, row.branch_name, summary, row.path });
}

fn writePorcelainRow(stdout: anytype, row: worktree_status.WorktreeRow) !void {
    const status = worktree_status.statusLabel(row);
    const current: usize = if (row.is_current) 1 else 0;
    const has_upstream: usize = if (row.has_upstream) 1 else 0;
    try stdout.print(
        "{d}\t{s}\t{s}\t{s}\t{d}\t{d}\t{d}\t{d}\t{d}\n",
        .{
            current,
            row.branch_name,
            row.path,
            status,
            row.modified,
            row.untracked,
            row.ahead,
            row.behind,
            has_upstream,
        },
    );
}

pub fn run(allocator: std.mem.Allocator, porcelain: bool) !void {
    const stdout = std.io.getStdOut().writer();

    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

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

    if (!porcelain) {
        try writeHumanHeader(stdout);
    }

    for (worktrees) |wt| {
        const row = worktree_status.inspectWorktree(allocator, cwd, wt);
        if (porcelain) {
            try writePorcelainRow(stdout, row);
        } else {
            try writeHumanRow(stdout, row);
        }
    }
}

test "writePorcelainRow uses tab-separated stable schema" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    const row: worktree_status.WorktreeRow = .{
        .is_current = true,
        .branch_name = "feat-x",
        .path = "/tmp/repo--feat-x",
        .status_known = true,
        .modified = 2,
        .untracked = 1,
        .has_upstream = true,
        .ahead = 3,
        .behind = 0,
    };
    try writePorcelainRow(fbs.writer(), row);

    try std.testing.expectEqualStrings(
        "1\tfeat-x\t/tmp/repo--feat-x\tdirty\t2\t1\t3\t0\t1\n",
        fbs.getWritten(),
    );
}

test "writeHumanRow includes clean and divergence markers" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    const row: worktree_status.WorktreeRow = .{
        .is_current = false,
        .branch_name = "main",
        .path = "/tmp/repo",
        .status_known = true,
        .modified = 0,
        .untracked = 0,
        .has_upstream = true,
        .ahead = 2,
        .behind = 1,
    };
    try writeHumanRow(fbs.writer(), row);

    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "clean") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "^2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "v1") != null);
}

test "writeHumanHeader prints table columns" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    try writeHumanHeader(fbs.writer());
    const out = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, out, "CUR BRANCH") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "STATUS") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "PATH") != null);
}

test "writeHumanRow omits literal dirty label" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    const row: worktree_status.WorktreeRow = .{
        .is_current = false,
        .branch_name = "feat-x",
        .path = "/tmp/repo--feat-x",
        .status_known = true,
        .modified = 2,
        .untracked = 1,
        .has_upstream = true,
        .ahead = 0,
        .behind = 1,
    };
    try writeHumanRow(fbs.writer(), row);

    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "dirty") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "M:2 U:1 v1") != null);
}

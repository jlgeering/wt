const std = @import("std");
const git = @import("../lib/git.zig");

const WorktreeRow = struct {
    is_current: bool,
    branch_name: []const u8,
    path: []const u8,
    status_known: bool,
    modified: usize,
    untracked: usize,
    has_upstream: bool,
    ahead: usize,
    behind: usize,
};

fn statusLabel(row: WorktreeRow) []const u8 {
    if (!row.status_known) return "unknown";
    return if (row.modified == 0 and row.untracked == 0) "clean" else "dirty";
}

fn humanStatusSummary(row: WorktreeRow, writer: anytype) void {
    if (!row.status_known) {
        writer.writeAll("unknown") catch {};
        return;
    }

    const base = statusLabel(row);
    if (std.mem.eql(u8, base, "clean")) {
        writer.writeAll("clean") catch {};
    } else {
        var wrote_change = false;
        if (row.modified > 0) {
            writer.print("M:{d}", .{row.modified}) catch {};
            wrote_change = true;
        }
        if (row.untracked > 0) {
            if (wrote_change) writer.writeAll(" ") catch {};
            writer.print("U:{d}", .{row.untracked}) catch {};
            wrote_change = true;
        }
        if (!wrote_change) {
            writer.writeAll("changes") catch {};
        }
    }

    if (row.has_upstream and (row.ahead > 0 or row.behind > 0)) {
        if (row.ahead > 0) {
            writer.print(" ^{d}", .{row.ahead}) catch {};
        }
        if (row.behind > 0) {
            writer.print(" v{d}", .{row.behind}) catch {};
        }
    }
}

fn writeHumanHeader(stdout: anytype) !void {
    try stdout.writeAll("CUR BRANCH                STATUS                  PATH\n");
    try stdout.writeAll("--- -------------------- ----------------------- ------------------------------\n");
}

fn writeHumanRow(stdout: anytype, row: WorktreeRow) !void {
    const marker: []const u8 = if (row.is_current) "*" else " ";
    var buf: [96]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();
    humanStatusSummary(row, w);

    try stdout.print("{s}   {s:<20} {s:<23} {s}\n", .{ marker, row.branch_name, fbs.getWritten(), row.path });
}

fn writePorcelainRow(stdout: anytype, row: WorktreeRow) !void {
    const status = statusLabel(row);
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

fn inspectWorktree(allocator: std.mem.Allocator, cwd: []const u8, wt: git.WorktreeInfo) WorktreeRow {
    const is_current = std.mem.eql(u8, cwd, wt.path);
    const branch_name = wt.branch orelse "(detached)";

    const status_output = git.runGit(allocator, wt.path, &.{ "status", "--porcelain", "--branch" }) catch {
        return .{
            .is_current = is_current,
            .branch_name = branch_name,
            .path = wt.path,
            .status_known = false,
            .modified = 0,
            .untracked = 0,
            .has_upstream = false,
            .ahead = 0,
            .behind = 0,
        };
    };
    defer allocator.free(status_output);

    const status = git.parseStatusPorcelain(status_output);
    const divergence = git.parseBranchDivergence(status_output);
    return .{
        .is_current = is_current,
        .branch_name = branch_name,
        .path = wt.path,
        .status_known = true,
        .modified = status.modified,
        .untracked = status.untracked,
        .has_upstream = divergence.has_upstream,
        .ahead = divergence.ahead,
        .behind = divergence.behind,
    };
}

pub fn run(allocator: std.mem.Allocator, porcelain: bool) !void {
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

    if (!porcelain) {
        try writeHumanHeader(stdout);
    }

    for (worktrees) |wt| {
        const row = inspectWorktree(allocator, cwd, wt);
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

    const row: WorktreeRow = .{
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

test "writeHumanRow includes clean and divergence arrows" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    const row: WorktreeRow = .{
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

    try std.testing.expectEqualStrings(
        "    main                 clean ^2 v1             /tmp/repo\n",
        fbs.getWritten(),
    );
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

    const row: WorktreeRow = .{
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

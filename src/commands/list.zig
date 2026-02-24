const std = @import("std");
const git = @import("../lib/git.zig");

const ansi_reset = "\x1b[0m";
const ansi_green = "\x1b[32m";
const ansi_yellow = "\x1b[33m";

const Divergence = struct {
    known: bool,
    available: bool,
    ahead: usize,
    behind: usize,
};

const WorktreeRow = struct {
    is_current: bool,
    branch_name: []const u8,
    path: []const u8,
    wt_known: bool,
    tracked_changes: usize,
    untracked: usize,
    base_ref: []const u8,
    base_divergence: Divergence,
    upstream_divergence: Divergence,
};

fn shouldUseColor() bool {
    return std.fs.File.stdout().isTty() and !std.process.hasEnvVarConstant("NO_COLOR");
}

fn wtStateLabel(row: WorktreeRow) []const u8 {
    if (!row.wt_known) return "unknown";
    return if (row.tracked_changes == 0 and row.untracked == 0) "clean" else "dirty";
}

fn writeDivergenceLabel(divergence: Divergence, writer: anytype) void {
    if (!divergence.known) {
        writer.writeAll("unknown") catch {};
        return;
    }
    if (!divergence.available) {
        writer.writeAll("-") catch {};
        return;
    }
    if (divergence.ahead == 0 and divergence.behind == 0) {
        writer.writeAll("=") catch {};
        return;
    }
    if (divergence.ahead > 0) {
        writer.print("\u{2191}{d}", .{divergence.ahead}) catch {};
    }
    if (divergence.behind > 0) {
        writer.print("\u{2193}{d}", .{divergence.behind}) catch {};
    }
}

fn divergenceLabel(divergence: Divergence, buffer: []u8) []const u8 {
    var fbs = std.io.fixedBufferStream(buffer);
    writeDivergenceLabel(divergence, fbs.writer());
    return fbs.getWritten();
}

fn divergenceCountOrMinusOne(divergence: Divergence, field: enum { ahead, behind }) i64 {
    if (!divergence.known or !divergence.available) return -1;
    const count = switch (field) {
        .ahead => divergence.ahead,
        .behind => divergence.behind,
    };
    return @as(i64, @intCast(count));
}

fn writeHumanHeader(stdout: anytype) !void {
    try stdout.writeAll("CUR BRANCH                WT       BASE      UPSTREAM  PATH\n");
    try stdout.writeAll("--- -------------------- -------- --------- --------- ------------------------------\n");
}

fn wtColor(row: WorktreeRow) []const u8 {
    if (!row.wt_known) return ansi_yellow;
    return if (row.tracked_changes == 0 and row.untracked == 0) ansi_green else ansi_yellow;
}

fn divergenceColor(divergence: Divergence) []const u8 {
    if (!divergence.known) return ansi_yellow;
    if (!divergence.available) return ansi_reset;
    return if (divergence.ahead == 0 and divergence.behind == 0) ansi_green else ansi_yellow;
}

fn writeHumanRow(stdout: anytype, row: WorktreeRow, use_color: bool) !void {
    const marker: []const u8 = if (row.is_current) "*" else " ";

    var wt_buf: [16]u8 = undefined;
    var base_buf: [32]u8 = undefined;
    var upstream_buf: [32]u8 = undefined;
    const wt = wtStateLabel(row);
    const base = divergenceLabel(row.base_divergence, &base_buf);
    const upstream = divergenceLabel(row.upstream_divergence, &upstream_buf);

    if (!use_color) {
        try stdout.print(
            "{s}   {s:<20} {s:<8} {s:<9} {s:<9} {s}\n",
            .{ marker, row.branch_name, wt, base, upstream, row.path },
        );
        return;
    }

    const wt_cell = std.fmt.bufPrint(&wt_buf, "{s:<8}", .{wt}) catch wt;
    var base_cell_buf: [48]u8 = undefined;
    const base_cell = std.fmt.bufPrint(&base_cell_buf, "{s:<9}", .{base}) catch base;
    var upstream_cell_buf: [48]u8 = undefined;
    const upstream_cell = std.fmt.bufPrint(&upstream_cell_buf, "{s:<9}", .{upstream}) catch upstream;

    try stdout.print("{s}   {s:<20} ", .{ marker, row.branch_name });
    try stdout.print("{s}{s}{s} ", .{ wtColor(row), wt_cell, ansi_reset });
    try stdout.print("{s}{s}{s} ", .{ divergenceColor(row.base_divergence), base_cell, ansi_reset });
    try stdout.print("{s}{s}{s} ", .{ divergenceColor(row.upstream_divergence), upstream_cell, ansi_reset });
    try stdout.print("{s}\n", .{row.path});
}

fn writePorcelainRow(stdout: anytype, row: WorktreeRow) !void {
    const current: usize = if (row.is_current) 1 else 0;
    const has_upstream: usize = if (row.upstream_divergence.known and row.upstream_divergence.available) 1 else 0;
    try stdout.print(
        "{d}\t{s}\t{s}\t{s}\t{d}\t{d}\t{s}\t{d}\t{d}\t{d}\t{d}\t{d}\n",
        .{
            current,
            row.branch_name,
            row.path,
            wtStateLabel(row),
            row.tracked_changes,
            row.untracked,
            row.base_ref,
            divergenceCountOrMinusOne(row.base_divergence, .ahead),
            divergenceCountOrMinusOne(row.base_divergence, .behind),
            has_upstream,
            divergenceCountOrMinusOne(row.upstream_divergence, .ahead),
            divergenceCountOrMinusOne(row.upstream_divergence, .behind),
        },
    );
}

fn inspectWorktree(
    allocator: std.mem.Allocator,
    cwd: []const u8,
    wt: git.WorktreeInfo,
    base_branch: ?[]const u8,
) WorktreeRow {
    const is_current = std.mem.eql(u8, cwd, wt.path);
    const branch_name = wt.branch orelse "(detached)";
    const base_ref = base_branch orelse "-";

    var wt_known = false;
    var tracked_changes: usize = 0;
    var untracked: usize = 0;
    var upstream_divergence: Divergence = .{
        .known = false,
        .available = false,
        .ahead = 0,
        .behind = 0,
    };

    const status_output = git.runGit(allocator, wt.path, &.{ "status", "--porcelain", "--branch" }) catch null;
    if (status_output) |output| {
        defer allocator.free(output);
        wt_known = true;
        const status = git.parseStatusPorcelain(output);
        tracked_changes = status.modified;
        untracked = status.untracked;

        const upstream = git.parseBranchDivergence(output);
        upstream_divergence = .{
            .known = true,
            .available = upstream.has_upstream,
            .ahead = upstream.ahead,
            .behind = upstream.behind,
        };
    }

    var base_divergence: Divergence = .{
        .known = true,
        .available = false,
        .ahead = 0,
        .behind = 0,
    };
    if (wt.branch) |branch| {
        if (base_branch) |base| {
            if (std.mem.eql(u8, branch, base)) {
                base_divergence.available = true;
            } else {
                var base_ok = true;
                var ahead: usize = 0;
                var behind: usize = 0;

                const ahead_result = git.countUnmergedCommits(allocator, wt.path, base, branch);
                if (ahead_result) |count| {
                    ahead = count;
                } else |_| {
                    base_ok = false;
                }

                const behind_result = git.countUnmergedCommits(allocator, wt.path, branch, base);
                if (behind_result) |count| {
                    behind = count;
                } else |_| {
                    base_ok = false;
                }

                if (base_ok) {
                    base_divergence = .{
                        .known = true,
                        .available = true,
                        .ahead = ahead,
                        .behind = behind,
                    };
                } else {
                    base_divergence = .{
                        .known = false,
                        .available = false,
                        .ahead = 0,
                        .behind = 0,
                    };
                }
            }
        }
    }

    return .{
        .is_current = is_current,
        .branch_name = branch_name,
        .path = wt.path,
        .wt_known = wt_known,
        .tracked_changes = tracked_changes,
        .untracked = untracked,
        .base_ref = base_ref,
        .base_divergence = base_divergence,
        .upstream_divergence = upstream_divergence,
    };
}

pub fn run(allocator: std.mem.Allocator, porcelain: bool) !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const use_color = shouldUseColor();

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

    const base_branch = worktrees[0].branch;

    if (!porcelain) {
        try writeHumanHeader(stdout);
    }

    for (worktrees) |wt| {
        const row = inspectWorktree(allocator, cwd, wt, base_branch);
        if (porcelain) {
            try writePorcelainRow(stdout, row);
        } else {
            try writeHumanRow(stdout, row, use_color);
        }
    }
}

test "writePorcelainRow uses tab-separated schema with base and upstream divergence" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    const row: WorktreeRow = .{
        .is_current = true,
        .branch_name = "feat-x",
        .path = "/tmp/repo--feat-x",
        .wt_known = true,
        .tracked_changes = 2,
        .untracked = 1,
        .base_ref = "main",
        .base_divergence = .{ .known = true, .available = true, .ahead = 4, .behind = 1 },
        .upstream_divergence = .{ .known = true, .available = true, .ahead = 3, .behind = 0 },
    };
    try writePorcelainRow(fbs.writer(), row);

    try std.testing.expectEqualStrings(
        "1\tfeat-x\t/tmp/repo--feat-x\tdirty\t2\t1\tmain\t4\t1\t1\t3\t0\n",
        fbs.getWritten(),
    );
}

test "writeHumanRow includes WT BASE and UPSTREAM columns" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    const row: WorktreeRow = .{
        .is_current = false,
        .branch_name = "main",
        .path = "/tmp/repo",
        .wt_known = true,
        .tracked_changes = 0,
        .untracked = 0,
        .base_ref = "main",
        .base_divergence = .{ .known = true, .available = true, .ahead = 0, .behind = 0 },
        .upstream_divergence = .{ .known = true, .available = true, .ahead = 2, .behind = 1 },
    };
    try writeHumanRow(fbs.writer(), row, false);

    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "clean") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "=") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\xE2\x86\x912\xE2\x86\x931") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "/tmp/repo") != null);
}

test "writeHumanHeader prints table columns" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    try writeHumanHeader(fbs.writer());
    const out = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, out, "CUR BRANCH") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "WT") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "BASE") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "UPSTREAM") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "PATH") != null);
}

test "writeHumanRow uses dirty label and unavailable divergence marker" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    const row: WorktreeRow = .{
        .is_current = false,
        .branch_name = "feat-x",
        .path = "/tmp/repo--feat-x",
        .wt_known = true,
        .tracked_changes = 2,
        .untracked = 1,
        .base_ref = "main",
        .base_divergence = .{ .known = true, .available = true, .ahead = 0, .behind = 1 },
        .upstream_divergence = .{ .known = true, .available = false, .ahead = 0, .behind = 0 },
    };
    try writeHumanRow(fbs.writer(), row, false);

    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "dirty") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\xE2\x86\x931") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, " - ") != null);
}

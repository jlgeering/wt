const std = @import("std");
const git = @import("git.zig");

pub const WorktreeRow = struct {
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

pub fn statusLabel(row: WorktreeRow) []const u8 {
    if (!row.status_known) return "unknown";
    return if (row.modified == 0 and row.untracked == 0) "clean" else "dirty";
}

fn writeStatusSummary(row: WorktreeRow, writer: anytype, use_unicode_arrows: bool) void {
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
            if (use_unicode_arrows) {
                writer.print(" ↑{d}", .{row.ahead}) catch {};
            } else {
                writer.print(" ^{d}", .{row.ahead}) catch {};
            }
        }
        if (row.behind > 0) {
            if (use_unicode_arrows) {
                writer.print(" ↓{d}", .{row.behind}) catch {};
            } else {
                writer.print(" v{d}", .{row.behind}) catch {};
            }
        }
    }
}

pub fn writeHumanStatusSummary(row: WorktreeRow, writer: anytype) void {
    writeStatusSummary(row, writer, false);
}

pub fn humanStatusSummary(row: WorktreeRow, buffer: []u8) []const u8 {
    var fbs = std.io.fixedBufferStream(buffer);
    writeStatusSummary(row, fbs.writer(), false);
    return fbs.getWritten();
}

pub fn pickerStatusSummary(row: WorktreeRow, buffer: []u8) []const u8 {
    var fbs = std.io.fixedBufferStream(buffer);
    writeStatusSummary(row, fbs.writer(), true);
    return fbs.getWritten();
}

pub fn inspectWorktree(allocator: std.mem.Allocator, cwd: []const u8, wt: git.WorktreeInfo) WorktreeRow {
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

test "humanStatusSummary uses ASCII markers for upstream divergence" {
    var buf: [96]u8 = undefined;
    const row: WorktreeRow = .{
        .is_current = false,
        .branch_name = "feat-x",
        .path = "/tmp/repo--feat-x",
        .status_known = true,
        .modified = 2,
        .untracked = 1,
        .has_upstream = true,
        .ahead = 3,
        .behind = 1,
    };

    const summary = humanStatusSummary(row, &buf);
    try std.testing.expect(std.mem.indexOf(u8, summary, "M:2") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "U:1") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "^3") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "v1") != null);
}

test "pickerStatusSummary uses Unicode arrows for upstream divergence" {
    var buf: [96]u8 = undefined;
    const row: WorktreeRow = .{
        .is_current = false,
        .branch_name = "feat-x",
        .path = "/tmp/repo--feat-x",
        .status_known = true,
        .modified = 1,
        .untracked = 0,
        .has_upstream = true,
        .ahead = 2,
        .behind = 1,
    };

    const summary = pickerStatusSummary(row, &buf);
    try std.testing.expect(std.mem.indexOf(u8, summary, "↑2") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "↓1") != null);
}

const std = @import("std");
const column_format = @import("column_format.zig");

const worktree_branch_width: usize = 20;
const worktree_status_width: usize = 20;
const rm_branch_width: usize = 20;
const rm_status_width: usize = 26;

pub fn visibleWidth(text: []const u8) usize {
    return column_format.visibleWidth(text);
}

fn writePadded(writer: anytype, text: []const u8, width: usize) !void {
    try column_format.writePadded(writer, text, width);
}

fn writeWorktreeColumns(writer: anytype, branch: []const u8, status: []const u8, path: []const u8) !void {
    try writePadded(writer, branch, worktree_branch_width);
    try writer.writeAll("  ");
    try writePadded(writer, status, worktree_status_width);
    try writer.writeAll("  ");
    try writer.writeAll(path);
}

fn writeRmColumns(writer: anytype, branch: []const u8, status: []const u8, path: []const u8) !void {
    try writePadded(writer, branch, rm_branch_width);
    try writer.writeAll("  ");
    try writePadded(writer, status, rm_status_width);
    try writer.writeAll("  ");
    try writer.writeAll(path);
}

pub fn writeWorktreeHeader(writer: anytype) !void {
    try writeWorktreeColumns(writer, "BRANCH", "STATUS", "PATH");
}

pub fn writeWorktreeRow(writer: anytype, branch: []const u8, status: []const u8, path: []const u8) !void {
    try writeWorktreeColumns(writer, branch, status, path);
}

pub fn writeRmHeader(writer: anytype) !void {
    try writeRmColumns(writer, "BRANCH", "STATUS", "PATH");
}

pub fn writeRmRow(writer: anytype, branch: []const u8, status: []const u8, path: []const u8) !void {
    try writeRmColumns(writer, branch, status, path);
}

test "worktree header and row share column starts" {
    var header_buf: [256]u8 = undefined;
    var header_fbs = std.io.fixedBufferStream(&header_buf);
    try writeWorktreeHeader(header_fbs.writer());
    const header = header_fbs.getWritten();

    var row_buf: [256]u8 = undefined;
    var row_fbs = std.io.fixedBufferStream(&row_buf);
    try writeWorktreeRow(row_fbs.writer(), "asdf1", "dirty, local-commits", "/tmp/repo--asdf1");
    const row = row_fbs.getWritten();

    try std.testing.expectEqual(columnStartWidth(header, "BRANCH"), columnStartWidth(row, "asdf1"));
    try std.testing.expectEqual(columnStartWidth(header, "STATUS"), columnStartWidth(row, "dirty"));
    try std.testing.expectEqual(columnStartWidth(header, "PATH"), columnStartWidth(row, "/tmp/repo--asdf1"));
}

test "rm header and row share column starts with arrow content" {
    var header_buf: [256]u8 = undefined;
    var header_fbs = std.io.fixedBufferStream(&header_buf);
    try writeRmHeader(header_fbs.writer());
    const header = header_fbs.getWritten();

    var row_buf: [256]u8 = undefined;
    var row_fbs = std.io.fixedBufferStream(&row_buf);
    try writeRmRow(row_fbs.writer(), "branch-a", "dirty, ↑1 ↓8", "/tmp/repo--branch-a");
    const row = row_fbs.getWritten();

    try std.testing.expectEqual(columnStartWidth(header, "BRANCH"), columnStartWidth(row, "branch-a"));
    try std.testing.expectEqual(columnStartWidth(header, "STATUS"), columnStartWidth(row, "dirty"));
    try std.testing.expectEqual(columnStartWidth(header, "PATH"), columnStartWidth(row, "/tmp/repo--branch-a"));
}

fn columnStartWidth(line: []const u8, token: []const u8) usize {
    const idx = std.mem.indexOf(u8, line, token) orelse unreachable;
    return visibleWidth(line[0..idx]);
}

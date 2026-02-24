const std = @import("std");

const ansi_escape: u8 = 0x1b;
const ansi_csi_start: u8 = '[';
const tab_width: usize = 4;

const worktree_branch_width: usize = 20;
const worktree_status_width: usize = 20;
const rm_branch_width: usize = 20;
const rm_status_width: usize = 26;

pub fn visibleWidth(text: []const u8) usize {
    var width: usize = 0;
    var i: usize = 0;

    while (i < text.len) {
        if (text[i] == ansi_escape and i + 1 < text.len and text[i + 1] == ansi_csi_start) {
            i += 2;
            while (i < text.len and !isAnsiTerminator(text[i])) : (i += 1) {}
            if (i < text.len) i += 1;
            continue;
        }

        const char_len = std.unicode.utf8ByteSequenceLength(text[i]) catch {
            width += 1;
            i += 1;
            continue;
        };

        if (i + char_len > text.len) {
            width += 1;
            break;
        }

        const cp = std.unicode.utf8Decode(text[i .. i + char_len]) catch {
            width += 1;
            i += 1;
            continue;
        };

        width += if (cp == '\t') tab_width else 1;
        i += char_len;
    }

    return width;
}

fn isAnsiTerminator(byte: u8) bool {
    return byte >= 0x40 and byte <= 0x7e;
}

fn writePadded(writer: anytype, text: []const u8, width: usize) !void {
    try writer.writeAll(text);
    const actual = visibleWidth(text);
    if (actual >= width) return;
    try writer.writeByteNTimes(' ', width - actual);
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

test "visibleWidth counts UTF-8 arrows by display cell" {
    try std.testing.expectEqual(@as(usize, 2), visibleWidth("↑2"));
    try std.testing.expectEqual(@as(usize, 5), visibleWidth("↑1 ↓8"));
}

test "visibleWidth ignores ANSI escape sequences" {
    const colored = "\x1b[33mM:1 U:2, ↑3\x1b[0m";
    try std.testing.expectEqual(@as(usize, 11), visibleWidth(colored));
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

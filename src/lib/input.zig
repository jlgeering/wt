const std = @import("std");
const builtin = @import("builtin");

pub const esc_key: u8 = 0x1b;
pub const ctrl_c_key: u8 = 0x03;

pub fn isCancelKey(key: u8) bool {
    return key == esc_key or key == ctrl_c_key;
}

pub fn isConfirmedResponse(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    return std.ascii.eqlIgnoreCase(trimmed, "y") or std.ascii.eqlIgnoreCase(trimmed, "yes");
}

pub fn isSingleKeySupported(stdin_file: std.fs.File) bool {
    if (comptime builtin.target.os.tag == .windows) {
        return false;
    } else {
        if (!stdin_file.isTty()) return false;
        _ = std.posix.tcgetattr(stdin_file.handle) catch return false;
        return true;
    }
}

pub fn tryReadSingleKey(stdin_file: std.fs.File) !?u8 {
    if (comptime builtin.target.os.tag == .windows) {
        return null;
    } else {
        if (!stdin_file.isTty()) return null;

        const original_termios = std.posix.tcgetattr(stdin_file.handle) catch return null;
        var raw_termios = original_termios;
        raw_termios.lflag.ICANON = false;
        raw_termios.lflag.ECHO = false;
        raw_termios.lflag.ISIG = false;
        raw_termios.cc[@intFromEnum(std.c.V.MIN)] = 1;
        raw_termios.cc[@intFromEnum(std.c.V.TIME)] = 0;
        std.posix.tcsetattr(stdin_file.handle, .NOW, raw_termios) catch return null;
        defer std.posix.tcsetattr(stdin_file.handle, .NOW, original_termios) catch {};

        var buf: [1]u8 = undefined;
        const read_len = std.posix.read(stdin_file.handle, &buf) catch return null;
        if (read_len == 0) return null;
        return buf[0];
    }
}

// --- Tests ---

test "isCancelKey recognizes escape and ctrl-c" {
    try std.testing.expect(isCancelKey(esc_key));
    try std.testing.expect(isCancelKey(ctrl_c_key));
    try std.testing.expect(!isCancelKey('q'));
    try std.testing.expect(!isCancelKey('n'));
}

test "isConfirmedResponse accepts y and yes" {
    try std.testing.expect(isConfirmedResponse("y"));
    try std.testing.expect(isConfirmedResponse("yes"));
    try std.testing.expect(isConfirmedResponse("YES"));
    try std.testing.expect(isConfirmedResponse(" Y "));
    try std.testing.expect(!isConfirmedResponse("n"));
    try std.testing.expect(!isConfirmedResponse("no"));
    try std.testing.expect(!isConfirmedResponse(""));
}

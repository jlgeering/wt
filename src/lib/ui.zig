const std = @import("std");

pub const ansi = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
};

pub const Level = enum {
    info,
    success,
    warn,
    err,
};

pub fn shouldUseColor(file: std.fs.File) bool {
    return file.isTty() and !std.process.hasEnvVarConstant("NO_COLOR");
}

pub fn printLevel(
    writer: anytype,
    use_color: bool,
    level: Level,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const label = levelLabel(level);
    if (use_color) {
        try writer.print("{s}{s}{s}{s} ", .{
            ansi.bold,
            levelColor(level),
            label,
            ansi.reset,
        });
    } else {
        try writer.print("{s} ", .{label});
    }

    try writer.print(fmt, args);
    if (!std.mem.endsWith(u8, fmt, "\n")) {
        try writer.writeByte('\n');
    }
}

fn levelLabel(level: Level) []const u8 {
    return switch (level) {
        .info => "Info:",
        .success => "Success:",
        .warn => "Warning:",
        .err => "Error:",
    };
}

fn levelColor(level: Level) []const u8 {
    return switch (level) {
        .info => ansi.cyan,
        .success => ansi.green,
        .warn => ansi.yellow,
        .err => ansi.red,
    };
}

test "printLevel includes level labels in plain mode" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    try printLevel(fbs.writer(), false, .warn, "hello {s}", .{"world"});
    try std.testing.expectEqualStrings("Warning: hello world\n", fbs.getWritten());
}

test "printLevel includes ansi in color mode" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);
    try printLevel(fbs.writer(), true, .success, "done", .{});
    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, ansi.green) != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Success:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "done\n") != null);
}

const std = @import("std");

pub const PickerMode = enum {
    auto,
    builtin,
    fzf,
};

pub const CommandDetector = *const fn (std.mem.Allocator, []const u8) bool;

pub fn parsePickerMode(raw: []const u8) !PickerMode {
    const value = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(value, "auto")) return .auto;
    if (std.ascii.eqlIgnoreCase(value, "builtin")) return .builtin;
    if (std.ascii.eqlIgnoreCase(value, "fzf")) return .fzf;
    return error.InvalidPickerMode;
}

pub fn commandExists(allocator: std.mem.Allocator, name: []const u8) bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ name, "--version" },
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

pub fn resolvePickerMode(
    allocator: std.mem.Allocator,
    requested: PickerMode,
    detector: CommandDetector,
) !PickerMode {
    return switch (requested) {
        .builtin => .builtin,
        .fzf => if (detector(allocator, "fzf")) .fzf else error.FzfUnavailable,
        .auto => if (detector(allocator, "fzf")) .fzf else .builtin,
    };
}

pub fn isFzfCancelTerm(term: std.process.Child.Term) bool {
    return switch (term) {
        .Exited => |code| code == 130,
        .Signal => |signal| signal == 2,
        else => false,
    };
}

// --- Tests ---

fn detectorAlwaysTrue(_: std.mem.Allocator, _: []const u8) bool {
    return true;
}

fn detectorAlwaysFalse(_: std.mem.Allocator, _: []const u8) bool {
    return false;
}

test "parsePickerMode accepts known values" {
    try std.testing.expectEqual(PickerMode.auto, try parsePickerMode("auto"));
    try std.testing.expectEqual(PickerMode.builtin, try parsePickerMode("builtin"));
    try std.testing.expectEqual(PickerMode.fzf, try parsePickerMode("fzf"));
    try std.testing.expectEqual(PickerMode.auto, try parsePickerMode(" AUTO "));
}

test "parsePickerMode rejects invalid values" {
    try std.testing.expectError(error.InvalidPickerMode, parsePickerMode("gum"));
}

test "resolvePickerMode auto prefers fzf when available" {
    const resolved = try resolvePickerMode(std.testing.allocator, .auto, detectorAlwaysTrue);
    try std.testing.expectEqual(PickerMode.fzf, resolved);
}

test "resolvePickerMode auto falls back to builtin when fzf unavailable" {
    const resolved = try resolvePickerMode(std.testing.allocator, .auto, detectorAlwaysFalse);
    try std.testing.expectEqual(PickerMode.builtin, resolved);
}

test "resolvePickerMode explicit fzf fails when unavailable" {
    try std.testing.expectError(
        error.FzfUnavailable,
        resolvePickerMode(std.testing.allocator, .fzf, detectorAlwaysFalse),
    );
}

test "isFzfCancelTerm recognizes cancel exit" {
    try std.testing.expect(isFzfCancelTerm(.{ .Exited = 130 }));
    try std.testing.expect(isFzfCancelTerm(.{ .Signal = 2 }));
    try std.testing.expect(!isFzfCancelTerm(.{ .Exited = 1 }));
}

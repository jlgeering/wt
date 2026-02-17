const std = @import("std");
const toml = @import("toml");

const CopySection = struct {
    paths: []const []const u8 = &.{},
};

const SymlinkSection = struct {
    paths: []const []const u8 = &.{},
};

const RunSection = struct {
    commands: []const []const u8 = &.{},
};

pub const Config = struct {
    copy: ?*CopySection = null,
    symlink: ?*SymlinkSection = null,
    run: ?*RunSection = null,

    pub fn copyPaths(self: Config) []const []const u8 {
        return if (self.copy) |c| c.paths else &.{};
    }

    pub fn symlinkPaths(self: Config) []const []const u8 {
        return if (self.symlink) |s| s.paths else &.{};
    }

    pub fn runCommands(self: Config) []const []const u8 {
        return if (self.run) |r| r.commands else &.{};
    }
};

pub const ParsedConfig = toml.Parsed(Config);

/// Parse a TOML config string into a Config.
pub fn parseConfigString(allocator: std.mem.Allocator, input: []const u8) !ParsedConfig {
    var parser = toml.Parser(Config).init(allocator);
    defer parser.deinit();
    return try parser.parseString(input);
}

/// Load config from .wt.toml in the given directory. Returns empty config if file missing.
pub fn loadConfigFile(allocator: std.mem.Allocator, dir_path: []const u8) !ParsedConfig {
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, ".wt.toml" });
    defer allocator.free(config_path);

    const content = std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            // Return empty config — parse an empty string
            var parser = toml.Parser(Config).init(allocator);
            defer parser.deinit();
            return try parser.parseString("");
        },
        else => return err,
    };
    defer allocator.free(content);

    return parseConfigString(allocator, content);
}

// --- Tests ---

test "parseConfigString parses full config" {
    const input =
        \\[copy]
        \\paths = ["deps", "_build"]
        \\
        \\[symlink]
        \\paths = ["mise.local.toml"]
        \\
        \\[run]
        \\commands = ["mise trust", "mix deps.get"]
    ;

    var result = try parseConfigString(std.testing.allocator, input);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.value.copyPaths().len);
    try std.testing.expectEqualStrings("deps", result.value.copyPaths()[0]);
    try std.testing.expectEqualStrings("_build", result.value.copyPaths()[1]);

    try std.testing.expectEqual(@as(usize, 1), result.value.symlinkPaths().len);
    try std.testing.expectEqualStrings("mise.local.toml", result.value.symlinkPaths()[0]);

    try std.testing.expectEqual(@as(usize, 2), result.value.runCommands().len);
    try std.testing.expectEqualStrings("mise trust", result.value.runCommands()[0]);
}

test "parseConfigString handles empty string" {
    var result = try parseConfigString(std.testing.allocator, "");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.value.copyPaths().len);
    try std.testing.expectEqual(@as(usize, 0), result.value.symlinkPaths().len);
    try std.testing.expectEqual(@as(usize, 0), result.value.runCommands().len);
}

test "parseConfigString handles partial config" {
    const input =
        \\[copy]
        \\paths = ["deps"]
    ;

    var result = try parseConfigString(std.testing.allocator, input);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.value.copyPaths().len);
    try std.testing.expectEqual(@as(usize, 0), result.value.symlinkPaths().len);
    try std.testing.expectEqual(@as(usize, 0), result.value.runCommands().len);
}

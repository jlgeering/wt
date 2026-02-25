const std = @import("std");

pub const PositionalKind = enum {
    git_ref,
    rm_branch,
    shell_name,
};

pub const PositionalSpec = struct {
    name: []const u8,
    kind: PositionalKind,
};

pub const CommandSpec = struct {
    name: []const u8,
    description: []const u8,
    aliases: []const []const u8 = &.{},
    positionals: []const PositionalSpec = &.{},
};

pub const completion_commands = [_]CommandSpec{
    .{
        .name = "list",
        .description = "List worktrees",
        .aliases = &.{"ls"},
    },
    .{
        .name = "new",
        .description = "Create a new worktree",
        .aliases = &.{"add"},
        .positionals = &.{
            .{ .name = "BRANCH", .kind = .git_ref },
            .{ .name = "BASE", .kind = .git_ref },
        },
    },
    .{
        .name = "rm",
        .description = "Remove a worktree",
        .positionals = &.{
            .{ .name = "BRANCH", .kind = .rm_branch },
        },
    },
    .{
        .name = "init",
        .description = "Create or upgrade .wt.toml",
    },
    .{
        .name = "shell-init",
        .description = "Output shell integration function",
        .positionals = &.{
            .{ .name = "SHELL", .kind = .shell_name },
        },
    },
};

pub const shell_names = [_][]const u8{
    "zsh",
    "bash",
    "fish",
    "nu",
};

pub fn commandForName(name: []const u8) ?*const CommandSpec {
    inline for (&completion_commands) |*command| {
        if (std.mem.eql(u8, command.name, name)) return command;
        for (command.aliases) |alias| {
            if (std.mem.eql(u8, alias, name)) return command;
        }
    }
    return null;
}

test "commandForName resolves aliases" {
    const new_cmd = commandForName("new");
    try std.testing.expect(new_cmd != null);
    try std.testing.expectEqualStrings("new", new_cmd.?.name);

    const list_alias = commandForName("ls");
    try std.testing.expect(list_alias != null);
    try std.testing.expectEqualStrings("list", list_alias.?.name);

    const add_alias = commandForName("add");
    try std.testing.expect(add_alias != null);
    try std.testing.expectEqualStrings("new", add_alias.?.name);
}

test "shell-init command positional uses shell_name kind" {
    const shell_init_cmd = commandForName("shell-init");
    try std.testing.expect(shell_init_cmd != null);
    try std.testing.expect(shell_init_cmd.?.positionals.len == 1);
    try std.testing.expect(shell_init_cmd.?.positionals[0].kind == .shell_name);
}

test "shell names include fish" {
    try std.testing.expectEqual(@as(usize, 4), shell_names.len);
    try std.testing.expectEqualStrings("zsh", shell_names[0]);
    try std.testing.expectEqualStrings("bash", shell_names[1]);
    try std.testing.expectEqualStrings("fish", shell_names[2]);
    try std.testing.expectEqualStrings("nu", shell_names[3]);
}

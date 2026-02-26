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
    "nushell",
};

fn buildDocCompletionCommandList() []const u8 {
    comptime var out: []const u8 = "";
    comptime var first = true;
    inline for (completion_commands) |command| {
        if (!first) out = out ++ ", ";
        out = out ++ "`" ++ command.name ++ "`";
        first = false;
        inline for (command.aliases) |alias| {
            out = out ++ ", `" ++ alias ++ "`";
        }
    }
    return out;
}

fn buildDocShellNameList() []const u8 {
    comptime var out: []const u8 = "";
    inline for (shell_names, 0..) |shell_name, idx| {
        if (idx != 0) out = out ++ ", ";
        out = out ++ "`" ++ shell_name ++ "`";
    }
    return out;
}

const doc_completion_command_list = buildDocCompletionCommandList();
const doc_shell_name_list = buildDocShellNameList();
const doc_subcommands_clause = "subcommands (" ++ doc_completion_command_list ++ ")";

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
    try std.testing.expectEqual(@as(usize, 5), shell_names.len);
    try std.testing.expectEqualStrings("zsh", shell_names[0]);
    try std.testing.expectEqualStrings("bash", shell_names[1]);
    try std.testing.expectEqualStrings("fish", shell_names[2]);
    try std.testing.expectEqualStrings("nu", shell_names[3]);
    try std.testing.expectEqualStrings("nushell", shell_names[4]);
}

test "shell docs include generated shell-name list from metadata" {
    const allocator = std.testing.allocator;
    const guide_doc = try std.fs.cwd().readFileAlloc(
        allocator,
        "docs/guides/shell-integration.md",
        1024 * 1024,
    );
    defer allocator.free(guide_doc);
    const command_ref_doc = try std.fs.cwd().readFileAlloc(
        allocator,
        "docs/specs/command-reference.md",
        1024 * 1024,
    );
    defer allocator.free(command_ref_doc);

    try std.testing.expect(std.mem.indexOf(u8, guide_doc, doc_shell_name_list) != null);
    try std.testing.expect(std.mem.indexOf(u8, command_ref_doc, doc_shell_name_list) != null);
}

test "shell docs include generated completion subcommand list from metadata" {
    const allocator = std.testing.allocator;
    const guide_doc = try std.fs.cwd().readFileAlloc(
        allocator,
        "docs/guides/shell-integration.md",
        1024 * 1024,
    );
    defer allocator.free(guide_doc);
    const command_ref_doc = try std.fs.cwd().readFileAlloc(
        allocator,
        "docs/specs/command-reference.md",
        1024 * 1024,
    );
    defer allocator.free(command_ref_doc);

    try std.testing.expect(std.mem.indexOf(u8, guide_doc, doc_subcommands_clause) != null);
    try std.testing.expect(std.mem.indexOf(u8, command_ref_doc, doc_subcommands_clause) != null);
}

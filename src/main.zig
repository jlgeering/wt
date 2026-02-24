const std = @import("std");
const zli = @import("zli");
const build_options = @import("build_options");

const list_cmd = @import("commands/list.zig");
const new_cmd = @import("commands/new.zig");
const rm_cmd = @import("commands/rm.zig");
const pick_worktree_cmd = @import("commands/pick_worktree.zig");
const shell_init_cmd = @import("commands/shell_init.zig");
const init_cmd = @import("commands/init.zig");

const root_description = "Git worktree manager";

const root_help_text =
    root_description ++
    "\n\n" ++
    "Usage: wt [OPTIONS] [COMMAND]\n\n" ++
    "Commands:\n" ++
    "    list                                          List worktrees (WT, BASE, UPSTREAM); use --porcelain for machine output\n" ++
    "    new                                           Create a new worktree (alias: add)\n" ++
    "    rm                                            Remove a worktree (picker status: clean|dirty plus optional local-commits)\n" ++
    "    init                                          Create or upgrade .wt.toml with guided recommendations\n\n" ++
    "Options:\n" ++
    "    -V, --version                                 Print version and exit\n" ++
    "    -h, --help                                    Print this help and exit\n\n" ++
    "Use `wt <command> --help` for command details.\n";

fn shouldPrintCustomRootHelp(allocator: std.mem.Allocator) !bool {
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    if (argv.len <= 1) {
        return true;
    }

    return std.mem.eql(u8, argv[1], "--help") or std.mem.eql(u8, argv[1], "-h");
}

fn printRootHelp() !void {
    try std.io.getStdOut().writer().writeAll(root_help_text);
}

fn buildRootCommand(allocator: std.mem.Allocator) !*zli.Command {
    const root = try zli.Command.init(allocator, .{
        .name = "wt",
        .description = "Git worktree manager",
        .help = root_description,
    }, runRoot);

    try root.addFlag(.{
        .name = "version",
        .shortcut = "V",
        .description = "Print version and exit",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    try root.addCommands(&.{
        try buildListCommand(allocator),
        try buildNewCommand(allocator),
        try buildRmCommand(allocator),
        try buildInitCommand(allocator),
        try buildShellInitCommand(allocator),
        try buildPickWorktreeCommand(allocator),
    });

    return root;
}

fn buildListCommand(allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(allocator, .{
        .name = "list",
        .description = "List worktrees (WT, BASE, UPSTREAM); use --porcelain for machine output",
    }, runList);

    try cmd.addFlag(.{
        .name = "porcelain",
        .description = "Print machine-readable output only",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });
    return cmd;
}

fn buildNewCommand(allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(allocator, .{
        .name = "new",
        .description = "Create a new worktree (alias: add)",
        .aliases = &.{"add"},
    }, runNew);

    try cmd.addFlag(.{
        .name = "porcelain",
        .description = "Print machine-readable output only",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });
    try cmd.addPositionalArg(.{
        .name = "BRANCH",
        .description = "Branch name",
        .required = false,
    });
    try cmd.addPositionalArg(.{
        .name = "BASE",
        .description = "Base ref (default: HEAD)",
        .required = false,
    });
    return cmd;
}

fn buildRmCommand(allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(allocator, .{
        .name = "rm",
        .description = "Remove a worktree (picker status: clean|dirty plus optional local-commits)",
    }, runRm);

    try cmd.addPositionalArg(.{
        .name = "BRANCH",
        .description = "Branch name (omit to use interactive picker)",
        .required = false,
    });
    try cmd.addFlag(.{
        .name = "force",
        .shortcut = "f",
        .description = "Force removal without safety confirmation (dirty/local-commits)",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });
    try cmd.addFlag(.{
        .name = "picker",
        .description = "Picker backend for interactive mode (auto|builtin|fzf)",
        .type = .String,
        .default_value = .{ .String = "auto" },
    });
    try cmd.addFlag(.{
        .name = "no-interactive",
        .description = "Disable interactive picker when BRANCH is omitted",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });
    return cmd;
}

fn buildInitCommand(allocator: std.mem.Allocator) !*zli.Command {
    return zli.Command.init(allocator, .{
        .name = "init",
        .description = "Create or upgrade .wt.toml with guided recommendations",
    }, runInit);
}

fn buildShellInitCommand(allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(allocator, .{
        .name = "shell-init",
        .description = "Output shell integration function",
        .section_title = "Internal",
    }, runShellInit);

    try cmd.addPositionalArg(.{
        .name = "SHELL",
        .description = "Shell name: zsh, bash",
        .required = false,
    });
    return cmd;
}

fn buildPickWorktreeCommand(allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(allocator, .{
        .name = "__pick-worktree",
        .description = "Internal: interactive worktree picker",
        .section_title = "Internal",
    }, runPickWorktree);

    try cmd.addFlag(.{
        .name = "picker",
        .description = "Picker backend for interactive mode (auto|builtin|fzf)",
        .type = .String,
        .default_value = .{ .String = "auto" },
    });
    return cmd;
}

fn runRoot(ctx: zli.CommandContext) !void {
    if (ctx.flag("version", bool)) {
        try std.io.getStdOut().writer().print("wt {s} ({s})\n", .{ build_options.version, build_options.git_sha });
        return;
    }

    try printRootHelp();
}

fn runList(ctx: zli.CommandContext) !void {
    try list_cmd.run(ctx.allocator, ctx.flag("porcelain", bool));
}

fn runNew(ctx: zli.CommandContext) !void {
    const branch = ctx.getArg("BRANCH") orelse {
        std.debug.print("Error: branch name required\n", .{});
        std.process.exit(1);
    };
    const base = ctx.getArg("BASE") orelse "HEAD";

    try new_cmd.run(ctx.allocator, branch, base, ctx.flag("porcelain", bool));
}

fn runRm(ctx: zli.CommandContext) !void {
    const picker_raw = ctx.flag("picker", []const u8);
    const picker_mode = rm_cmd.parsePickerMode(picker_raw) catch {
        std.debug.print("Error: invalid picker '{s}'. Expected auto, builtin, or fzf\n", .{picker_raw});
        std.process.exit(1);
    };

    try rm_cmd.run(ctx.allocator, .{
        .branch_arg = ctx.getArg("BRANCH"),
        .force = ctx.flag("force", bool),
        .picker_mode = picker_mode,
        .no_interactive = ctx.flag("no-interactive", bool),
    });
}

fn runInit(ctx: zli.CommandContext) !void {
    try init_cmd.run(ctx.allocator);
}

fn runShellInit(ctx: zli.CommandContext) !void {
    const shell = ctx.getArg("SHELL") orelse {
        std.debug.print("Error: shell name required (zsh, bash)\n", .{});
        std.process.exit(1);
    };

    try shell_init_cmd.run(shell);
}

fn runPickWorktree(ctx: zli.CommandContext) !void {
    const picker_raw = ctx.flag("picker", []const u8);
    const picker_mode = pick_worktree_cmd.parsePickerMode(picker_raw) catch {
        std.debug.print("Error: invalid picker '{s}'. Expected auto, builtin, or fzf\n", .{picker_raw});
        std.process.exit(1);
    };

    try pick_worktree_cmd.run(ctx.allocator, picker_mode);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (try shouldPrintCustomRootHelp(allocator)) {
        try printRootHelp();
        return;
    }

    const root = try buildRootCommand(allocator);
    defer root.deinit();

    try root.execute(.{});
}

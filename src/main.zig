const std = @import("std");
const zli = @import("zli");
const build_options = @import("build_options");

const list_cmd = @import("commands/list.zig");
const new_cmd = @import("commands/new.zig");
const rm_cmd = @import("commands/rm.zig");
const pick_worktree_cmd = @import("commands/pick_worktree.zig");
const shell_init_cmd = @import("commands/shell_init.zig");
const init_cmd = @import("commands/init.zig");
const ui = @import("lib/ui.zig");

const root_description = "Git worktree manager";

const root_help_text =
    root_description ++
    "\n\n" ++
    "Usage: wt [OPTIONS] [COMMAND]\n\n" ++
    "Commands:\n" ++
    "    list                                          List worktrees (WT, BASE, UPSTREAM)\n" ++
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
    try std.fs.File.stdout().deprecatedWriter().writeAll(root_help_text);
}

fn buildRootCommand(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const root = try zli.Command.init(writer, reader, allocator, .{
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
        try buildListCommand(writer, reader, allocator),
        try buildNewCommand(writer, reader, allocator),
        try buildInternalListCommand(writer, reader, allocator),
        try buildInternalNewCommand(writer, reader, allocator),
        try buildRmCommand(writer, reader, allocator),
        try buildInitCommand(writer, reader, allocator),
        try buildShellInitCommand(writer, reader, allocator),
        try buildPickWorktreeCommand(writer, reader, allocator),
    });

    return root;
}

fn buildListCommand(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "list",
        .description = "List worktrees (WT, BASE, UPSTREAM)",
    }, runList);

    return cmd;
}

fn buildNewCommand(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "new",
        .description = "Create a new worktree (alias: add)",
        .aliases = &.{"add"},
    }, runNew);

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

fn buildInternalListCommand(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    return zli.Command.init(writer, reader, allocator, .{
        .name = "__list",
        .description = "Internal: machine-readable worktree list",
        .section_title = "Internal",
    }, runInternalList);
}

fn buildInternalNewCommand(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "__new",
        .description = "Internal: machine-readable worktree create",
        .section_title = "Internal",
    }, runInternalNew);

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

fn buildRmCommand(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
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

fn buildInitCommand(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    return zli.Command.init(writer, reader, allocator, .{
        .name = "init",
        .description = "Create or upgrade .wt.toml with guided recommendations",
    }, runInit);
}

fn buildShellInitCommand(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "shell-init",
        .description = "Output shell integration function",
        .section_title = "Internal",
    }, runShellInit);

    try cmd.addPositionalArg(.{
        .name = "SHELL",
        .description = "Shell name: zsh, bash, fish, nu",
        .required = false,
    });
    return cmd;
}

fn buildPickWorktreeCommand(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
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
        try std.fs.File.stdout().deprecatedWriter().print("wt {s} ({s})\n", .{ build_options.version, build_options.git_sha });
        return;
    }

    try printRootHelp();
}

fn runList(ctx: zli.CommandContext) !void {
    try list_cmd.runHuman(ctx.allocator);
}

fn runInternalList(ctx: zli.CommandContext) !void {
    try list_cmd.runMachine(ctx.allocator);
}

fn runNew(ctx: zli.CommandContext) !void {
    const branch = ctx.getArg("BRANCH") orelse {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        const use_color = ui.shouldUseColor(std.fs.File.stderr());
        try ui.printLevel(stderr, use_color, .err, "branch name required", .{});
        std.process.exit(1);
    };
    const base = ctx.getArg("BASE") orelse "HEAD";

    try new_cmd.runHuman(ctx.allocator, branch, base);
}

fn runInternalNew(ctx: zli.CommandContext) !void {
    const branch = ctx.getArg("BRANCH") orelse {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        const use_color = ui.shouldUseColor(std.fs.File.stderr());
        try ui.printLevel(stderr, use_color, .err, "branch name required", .{});
        std.process.exit(1);
    };
    const base = ctx.getArg("BASE") orelse "HEAD";

    try new_cmd.runMachine(ctx.allocator, branch, base);
}

fn runRm(ctx: zli.CommandContext) !void {
    const picker_raw = ctx.flag("picker", []const u8);
    const picker_mode = rm_cmd.parsePickerMode(picker_raw) catch {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        const use_color = ui.shouldUseColor(std.fs.File.stderr());
        try ui.printLevel(stderr, use_color, .err, "invalid picker '{s}'. Expected auto, builtin, or fzf", .{picker_raw});
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
        const stderr = std.fs.File.stderr().deprecatedWriter();
        const use_color = ui.shouldUseColor(std.fs.File.stderr());
        try ui.printLevel(stderr, use_color, .err, "shell name required (zsh, bash, fish, nu)", .{});
        std.process.exit(1);
    };

    try shell_init_cmd.run(shell);
}

fn runPickWorktree(ctx: zli.CommandContext) !void {
    const picker_raw = ctx.flag("picker", []const u8);
    const picker_mode = pick_worktree_cmd.parsePickerMode(picker_raw) catch {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        const use_color = ui.shouldUseColor(std.fs.File.stderr());
        try ui.printLevel(stderr, use_color, .err, "invalid picker '{s}'. Expected auto, builtin, or fzf", .{picker_raw});
        std.process.exit(1);
    };

    try pick_worktree_cmd.run(ctx.allocator, picker_mode);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
    const stdout = &stdout_writer.interface;
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().readerStreaming(&stdin_buffer);
    const stdin = &stdin_reader.interface;

    if (try shouldPrintCustomRootHelp(allocator)) {
        try printRootHelp();
        return;
    }

    const root = try buildRootCommand(stdout, stdin, allocator);
    defer root.deinit();

    try root.execute(.{});
}

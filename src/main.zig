const std = @import("std");
const yazap = @import("yazap");
const build_options = @import("build_options");

const list_cmd = @import("commands/list.zig");
const new_cmd = @import("commands/new.zig");
const rm_cmd = @import("commands/rm.zig");
const pick_worktree_cmd = @import("commands/pick_worktree.zig");
const shell_init_cmd = @import("commands/shell_init.zig");
const init_cmd = @import("commands/init.zig");

const App = yazap.App;
const Arg = yazap.Arg;

const root_description =
    "Git worktree manager\n" ++
    "\n" ++
    "Quick start:\n" ++
    "  wt list\n" ++
    "  wt new <branch> [base]\n" ++
    "  wt rm [branch]\n" ++
    "  wt init\n" ++
    "\n" ++
    "Use `wt <command> --help` for command details.";

fn normalizeArgvForAliases(
    allocator: std.mem.Allocator,
    argv: []const [:0]u8,
) ![][:0]const u8 {
    var normalized = try allocator.alloc([:0]const u8, argv.len);
    for (argv, 0..) |arg, idx| {
        normalized[idx] = arg;
    }

    if (normalized.len > 1 and std.mem.eql(u8, normalized[1], "add")) {
        normalized[1] = "new";
    }

    return normalized;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.init(allocator, "wt", root_description);
    defer app.deinit();

    var wt = app.rootCommand();
    wt.setProperty(.help_on_empty_args);
    try wt.addArg(Arg.booleanOption("version", 'V', "Print version and exit"));

    var cmd_list = app.createCommand("list", "List all worktrees");
    try cmd_list.addArg(Arg.booleanOption("porcelain", null, "Print machine-readable output only"));
    try wt.addSubcommand(cmd_list);

    var cmd_new = app.createCommand("new", "Create a new worktree (alias: add)");
    try cmd_new.addArg(Arg.booleanOption("porcelain", null, "Print machine-readable output only"));
    try cmd_new.addArg(Arg.positional("BRANCH", "Branch name", null));
    try cmd_new.addArg(Arg.positional("BASE", "Base ref (default: HEAD)", null));
    try wt.addSubcommand(cmd_new);

    var cmd_rm = app.createCommand("rm", "Remove a worktree");
    try cmd_rm.addArg(Arg.positional("BRANCH", "Branch name (omit to use interactive picker)", null));
    try cmd_rm.addArg(Arg.booleanOption("force", 'f', "Force removal without safety confirmation (dirty/unmerged)"));
    try cmd_rm.addArg(Arg.singleValueOption("picker", null, "Picker backend for interactive mode: auto|builtin|fzf"));
    try cmd_rm.addArg(Arg.booleanOption("no-interactive", null, "Disable interactive picker when BRANCH is omitted"));
    try wt.addSubcommand(cmd_rm);

    var cmd_shell_init = app.createCommand("shell-init", "Output shell integration function");
    try cmd_shell_init.addArg(Arg.positional("SHELL", "Shell name: zsh, bash", null));
    try wt.addSubcommand(cmd_shell_init);

    var cmd_pick_worktree = app.createCommand("__pick-worktree", "Internal: interactive worktree picker");
    try cmd_pick_worktree.addArg(Arg.singleValueOption(
        "picker",
        null,
        "Picker backend for interactive mode (auto|builtin|fzf)",
    ));
    try wt.addSubcommand(cmd_pick_worktree);

    try wt.addSubcommand(app.createCommand("init", "Create or upgrade .wt.toml with guided recommendations"));

    app.process_args = try std.process.argsAlloc(allocator);
    const parse_argv = try normalizeArgvForAliases(allocator, app.process_args.?);
    defer allocator.free(parse_argv);

    const matches = try app.parseFrom(parse_argv[1..]);
    if (matches.containsArg("version")) {
        std.debug.print("wt {s} ({s})\n", .{ build_options.version, build_options.git_sha });
        return;
    }

    if (matches.subcommandMatches("list")) |list_matches| {
        const porcelain = list_matches.containsArg("porcelain");
        try list_cmd.run(allocator, porcelain);
    } else if (matches.subcommandMatches("new")) |new_matches| {
        const branch = new_matches.getSingleValue("BRANCH") orelse {
            std.debug.print("Error: branch name required\n", .{});
            std.process.exit(1);
        };
        const base = new_matches.getSingleValue("BASE") orelse "HEAD";
        const porcelain = new_matches.containsArg("porcelain");
        try new_cmd.run(allocator, branch, base, porcelain);
    } else if (matches.subcommandMatches("rm")) |rm_matches| {
        const picker_raw = rm_matches.getSingleValue("picker") orelse "auto";
        const picker_mode = rm_cmd.parsePickerMode(picker_raw) catch {
            std.debug.print("Error: invalid picker '{s}'. Expected auto, builtin, or fzf\n", .{picker_raw});
            std.process.exit(1);
        };

        try rm_cmd.run(allocator, .{
            .branch_arg = rm_matches.getSingleValue("BRANCH"),
            .force = rm_matches.containsArg("force"),
            .picker_mode = picker_mode,
            .no_interactive = rm_matches.containsArg("no-interactive"),
        });
    } else if (matches.subcommandMatches("shell-init")) |si_matches| {
        const shell = si_matches.getSingleValue("SHELL") orelse {
            std.debug.print("Error: shell name required (zsh, bash)\n", .{});
            std.process.exit(1);
        };
        try shell_init_cmd.run(shell);
    } else if (matches.subcommandMatches("__pick-worktree")) |pick_matches| {
        const picker_raw = pick_matches.getSingleValue("picker") orelse "auto";
        const picker_mode = pick_worktree_cmd.parsePickerMode(picker_raw) catch {
            std.debug.print("Error: invalid picker '{s}'. Expected auto, builtin, or fzf\n", .{picker_raw});
            std.process.exit(1);
        };
        try pick_worktree_cmd.run(allocator, picker_mode);
    } else if (matches.subcommandMatches("init")) |_| {
        try init_cmd.run(allocator);
    }
}

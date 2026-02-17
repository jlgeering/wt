const std = @import("std");
const yazap = @import("yazap");

const list_cmd = @import("commands/list.zig");
const new_cmd = @import("commands/new.zig");

const App = yazap.App;
const Arg = yazap.Arg;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.init(allocator, "wt", "Git worktree manager");
    defer app.deinit();

    var wt = app.rootCommand();
    wt.setProperty(.help_on_empty_args);

    try wt.addSubcommand(app.createCommand("list", "List all worktrees"));

    var cmd_new = app.createCommand("new", "Create a new worktree");
    try cmd_new.addArg(Arg.positional("BRANCH", "Branch name", null));
    try cmd_new.addArg(Arg.positional("BASE", "Base ref (default: HEAD)", null));
    try wt.addSubcommand(cmd_new);

    const matches = try app.parseProcess();

    if (matches.subcommandMatches("list")) |_| {
        try list_cmd.run(allocator);
    } else if (matches.subcommandMatches("new")) |new_matches| {
        const branch = new_matches.getSingleValue("BRANCH") orelse {
            std.debug.print("Error: branch name required\n", .{});
            std.process.exit(1);
        };
        const base = new_matches.getSingleValue("BASE") orelse "HEAD";
        try new_cmd.run(allocator, branch, base);
    }
}

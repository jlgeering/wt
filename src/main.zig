const std = @import("std");
const yazap = @import("yazap");

const App = yazap.App;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.init(allocator, "wt", "Git worktree manager");
    defer app.deinit();

    var wt = app.rootCommand();
    wt.setProperty(.help_on_empty_args);

    try wt.addSubcommand(app.createCommand("list", "List all worktrees"));

    const matches = try app.parseProcess();

    if (matches.subcommandMatches("list")) |_| {
        std.debug.print("wt list: not yet implemented\n", .{});
    }
}

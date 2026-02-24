const std = @import("std");
const git = @import("../lib/git.zig");
const picker_format = @import("../lib/picker_format.zig");
const worktree_status = @import("../lib/worktree_status.zig");
const ui = @import("../lib/ui.zig");

pub const PickerMode = enum {
    auto,
    builtin,
    fzf,
};

pub fn parsePickerMode(raw: []const u8) !PickerMode {
    const value = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(value, "auto")) return .auto;
    if (std.ascii.eqlIgnoreCase(value, "builtin")) return .builtin;
    if (std.ascii.eqlIgnoreCase(value, "fzf")) return .fzf;
    return error.InvalidPickerMode;
}

fn commandExists(allocator: std.mem.Allocator, name: []const u8) bool {
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

fn resolvePickerMode(allocator: std.mem.Allocator, requested: PickerMode) !PickerMode {
    return switch (requested) {
        .builtin => .builtin,
        .fzf => if (commandExists(allocator, "fzf")) .fzf else error.FzfUnavailable,
        .auto => if (commandExists(allocator, "fzf")) .fzf else .builtin,
    };
}

fn isInteractiveSession() bool {
    return std.fs.File.stdin().isTty() and std.fs.File.stderr().isTty();
}

fn isFzfCancelTerm(term: std.process.Child.Term) bool {
    return switch (term) {
        .Exited => |code| code == 130,
        .Signal => |signal| signal == 2,
        else => false,
    };
}

fn buildRows(
    allocator: std.mem.Allocator,
    cwd: []const u8,
    worktrees: []const git.WorktreeInfo,
) ![]worktree_status.WorktreeRow {
    var rows = try allocator.alloc(worktree_status.WorktreeRow, worktrees.len);
    for (worktrees, 0..) |wt, idx| {
        rows[idx] = worktree_status.inspectWorktree(allocator, cwd, wt);
    }
    return rows;
}

fn isCancelResponse(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    return std.ascii.eqlIgnoreCase(trimmed, "q") or
        std.ascii.eqlIgnoreCase(trimmed, "quit") or
        std.ascii.eqlIgnoreCase(trimmed, "cancel");
}

fn selectViaBuiltin(
    stderr: anytype,
    stdin_file: std.fs.File,
    rows: []const worktree_status.WorktreeRow,
    use_color: bool,
) !?usize {
    if (use_color) {
        try stderr.print("\n{s}{s}{s}\n", .{ ui.ansi.bold, "Choose a worktree:", ui.ansi.reset });
    } else {
        try stderr.writeAll("\nChoose a worktree:\n");
    }

    for (rows, 0..) |row, idx| {
        var raw_summary_buf: [128]u8 = undefined;
        const raw_summary = worktree_status.pickerStatusSummary(row, &raw_summary_buf);
        var summary_buf: [192]u8 = undefined;
        const summary = if (use_color) blk: {
            const summary_color: []const u8 = if (!row.status_known)
                ui.ansi.yellow
            else if (row.modified == 0 and row.untracked == 0 and row.ahead == 0 and row.behind == 0)
                ui.ansi.green
            else
                ui.ansi.yellow;
            break :blk std.fmt.bufPrint(&summary_buf, "{s}{s}{s}", .{
                summary_color,
                raw_summary,
                ui.ansi.reset,
            }) catch raw_summary;
        } else raw_summary;
        var branch_buf: [128]u8 = undefined;
        const branch_name = if (use_color and row.is_current) blk: {
            break :blk std.fmt.bufPrint(&branch_buf, "{s}{s}{s}", .{
                ui.ansi.bold,
                row.branch_name,
                ui.ansi.reset,
            }) catch row.branch_name;
        } else row.branch_name;

        var display_buf: [768]u8 = undefined;
        var display_fbs = std.io.fixedBufferStream(&display_buf);
        try picker_format.writeWorktreeRow(display_fbs.writer(), branch_name, summary, row.path);
        try stderr.print("  [{d}] {s}\n", .{ idx + 1, display_fbs.getWritten() });
    }

    var response_buf: [64]u8 = undefined;
    while (true) {
        try stderr.print("Select worktree [1-{d}], q to quit: ", .{rows.len});
        const response = try stdin_file.deprecatedReader().readUntilDelimiterOrEof(&response_buf, '\n');
        if (response == null) return null;

        const trimmed = std.mem.trim(u8, response.?, " \t\r\n");
        if (trimmed.len == 0) {
            try stderr.writeAll("Please enter a number or q.\n");
            continue;
        }
        if (isCancelResponse(trimmed)) return null;

        const selected = std.fmt.parseInt(usize, trimmed, 10) catch {
            try stderr.writeAll("Invalid selection. Enter a number or q.\n");
            continue;
        };

        if (selected < 1 or selected > rows.len) {
            try stderr.print("Selection out of range (1-{d}).\n", .{rows.len});
            continue;
        }

        return selected - 1;
    }
}

fn selectViaFzf(
    allocator: std.mem.Allocator,
    rows: []const worktree_status.WorktreeRow,
    use_color: bool,
) !?usize {
    const fzf_args: []const []const u8 = if (use_color)
        &.{
            "fzf",
            "--prompt",
            "Worktree > ",
            "--height",
            "40%",
            "--reverse",
            "--no-multi",
            "--delimiter",
            "\t",
            "--with-nth",
            "2",
            "--accept-nth",
            "1",
            "--header-lines",
            "1",
            "--tabstop",
            "4",
            "--ansi",
        }
    else
        &.{
            "fzf",
            "--no-color",
            "--prompt",
            "Worktree > ",
            "--height",
            "40%",
            "--reverse",
            "--no-multi",
            "--delimiter",
            "\t",
            "--with-nth",
            "2",
            "--accept-nth",
            "1",
            "--header-lines",
            "1",
            "--tabstop",
            "4",
        };

    var child = std.process.Child.init(fzf_args, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    errdefer {
        _ = child.kill() catch {};
    }

    {
        var input = child.stdin.?.deprecatedWriter();

        var header_buf: [256]u8 = undefined;
        var header_fbs = std.io.fixedBufferStream(&header_buf);
        try picker_format.writeWorktreeHeader(header_fbs.writer());
        try input.print("0\t{s}\n", .{header_fbs.getWritten()});

        for (rows, 0..) |row, idx| {
            var raw_summary_buf: [128]u8 = undefined;
            const raw_summary = worktree_status.pickerStatusSummary(row, &raw_summary_buf);
            var summary_buf: [192]u8 = undefined;
            const summary = if (use_color) blk: {
                const summary_color: []const u8 = if (!row.status_known)
                    ui.ansi.yellow
                else if (row.modified == 0 and row.untracked == 0 and row.ahead == 0 and row.behind == 0)
                    ui.ansi.green
                else
                    ui.ansi.yellow;
                break :blk std.fmt.bufPrint(&summary_buf, "{s}{s}{s}", .{
                    summary_color,
                    raw_summary,
                    ui.ansi.reset,
                }) catch raw_summary;
            } else raw_summary;
            var branch_buf: [128]u8 = undefined;
            const branch_name = if (use_color and row.is_current) blk: {
                break :blk std.fmt.bufPrint(&branch_buf, "{s}{s}{s}", .{
                    ui.ansi.bold,
                    row.branch_name,
                    ui.ansi.reset,
                }) catch row.branch_name;
            } else row.branch_name;

            var display_buf: [768]u8 = undefined;
            var display_fbs = std.io.fixedBufferStream(&display_buf);
            try picker_format.writeWorktreeRow(display_fbs.writer(), branch_name, summary, row.path);
            try input.print("{d}\t{s}\n", .{ idx + 1, display_fbs.getWritten() });
        }
    }

    child.stdin.?.close();
    child.stdin = null;

    var stdout_buf = std.ArrayListUnmanaged(u8){};
    defer stdout_buf.deinit(allocator);
    var stderr_buf = std.ArrayListUnmanaged(u8){};
    defer stderr_buf.deinit(allocator);

    try child.collectOutput(allocator, &stdout_buf, &stderr_buf, 1024 * 1024);
    const term = try child.wait();

    if (isFzfCancelTerm(term)) return null;

    switch (term) {
        .Exited => |code| if (code != 0) return error.FzfFailed,
        else => return error.FzfFailed,
    }

    const selected_raw = std.mem.trim(u8, stdout_buf.items, " \t\r\n");
    if (selected_raw.len == 0) return null;

    const selected = std.fmt.parseInt(usize, selected_raw, 10) catch return error.FzfInvalidSelection;
    if (selected < 1 or selected > rows.len) return error.FzfInvalidSelection;
    return selected - 1;
}

pub fn run(allocator: std.mem.Allocator, requested_picker: PickerMode) !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();
    const use_color = ui.shouldUseColor(std.fs.File.stderr());

    if (!isInteractiveSession()) {
        try ui.printLevel(stderr, use_color, .err, "__pick-worktree requires an interactive terminal", .{});
        std.process.exit(1);
    }

    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    const wt_output = git.runGit(allocator, null, &.{ "worktree", "list", "--porcelain" }) catch {
        try ui.printLevel(stderr, use_color, .err, "not a git repository or git not found", .{});
        std.process.exit(1);
    };
    defer allocator.free(wt_output);

    const worktrees = try git.parseWorktreeList(allocator, wt_output);
    defer allocator.free(worktrees);

    if (worktrees.len == 0) return;

    if (worktrees.len == 1) {
        try ui.printLevel(
            stderr,
            use_color,
            .info,
            "only one worktree is available: {s} ({s}). Staying in the current directory.",
            .{ worktrees[0].branch orelse "(detached)", worktrees[0].path },
        );
        return;
    }

    const rows = try buildRows(allocator, cwd, worktrees);
    defer allocator.free(rows);

    const resolved_mode = resolvePickerMode(allocator, requested_picker) catch |err| {
        switch (err) {
            error.FzfUnavailable => {
                try ui.printLevel(stderr, use_color, .err, "picker 'fzf' was requested but fzf is not available on PATH", .{});
                try ui.printLevel(stderr, use_color, .info, "install fzf or use `--picker builtin`", .{});
                std.process.exit(1);
            },
            else => return err,
        }
    };

    const selected = switch (resolved_mode) {
        .builtin => try selectViaBuiltin(stderr, std.fs.File.stdin(), rows, use_color),
        .fzf => selectViaFzf(allocator, rows, use_color) catch |err| switch (err) {
            error.FzfFailed => {
                try ui.printLevel(stderr, use_color, .err, "fzf failed while selecting a worktree", .{});
                std.process.exit(1);
            },
            error.FzfInvalidSelection => {
                try ui.printLevel(stderr, use_color, .err, "failed to parse fzf selection", .{});
                std.process.exit(1);
            },
            else => return err,
        },
        .auto => unreachable,
    };

    if (selected == null) return;
    try stdout.print("{s}\n", .{rows[selected.?].path});
}

test "parsePickerMode accepts known values" {
    try std.testing.expectEqual(PickerMode.auto, try parsePickerMode("auto"));
    try std.testing.expectEqual(PickerMode.builtin, try parsePickerMode("builtin"));
    try std.testing.expectEqual(PickerMode.fzf, try parsePickerMode("fzf"));
}

test "parsePickerMode rejects unknown value" {
    try std.testing.expectError(error.InvalidPickerMode, parsePickerMode("gum"));
}

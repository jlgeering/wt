const std = @import("std");
const builtin = @import("builtin");
const git = @import("../lib/git.zig");

pub const PickerMode = enum {
    auto,
    builtin,
    fzf,
};

pub const RmOptions = struct {
    branch_arg: ?[]const u8 = null,
    force: bool = false,
    picker_mode: PickerMode = .auto,
    no_interactive: bool = false,
};

const RemovalCandidate = struct {
    path: []const u8,
    branch: ?[]const u8,
    modified: usize,
    untracked: usize,
    unmerged: ?usize,
    safe: bool,
};

const BranchDeleteAction = enum {
    delete,
    skip_detached,
};

const ansi_reset = "\x1b[0m";
const ansi_bold = "\x1b[1m";
const ansi_green = "\x1b[32m";
const ansi_yellow = "\x1b[33m";

const esc_key: u8 = 0x1b;
const ctrl_c_key: u8 = 0x03;

const CommandDetector = *const fn (std.mem.Allocator, []const u8) bool;

pub fn parsePickerMode(raw: []const u8) !PickerMode {
    const value = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(value, "auto")) return .auto;
    if (std.ascii.eqlIgnoreCase(value, "builtin")) return .builtin;
    if (std.ascii.eqlIgnoreCase(value, "fzf")) return .fzf;
    return error.InvalidPickerMode;
}
fn findWorktreeByBranch(worktrees: []const git.WorktreeInfo, branch: []const u8) ?git.WorktreeInfo {
    for (worktrees, 0..) |wt, idx| {
        // Never target the main worktree.
        if (idx == 0) continue;

        const wt_branch = wt.branch orelse continue;
        if (std.mem.eql(u8, wt_branch, branch)) return wt;
    }
    return null;
}

const SecondarySplit = struct {
    removable: []git.WorktreeInfo,
    current_secondary: ?git.WorktreeInfo,
};

fn detectCurrentWorktreePath(allocator: std.mem.Allocator) ![]u8 {
    const output = try git.runGit(allocator, null, &.{ "rev-parse", "--show-toplevel" });
    defer allocator.free(output);

    const trimmed = std.mem.trim(u8, output, " \t\r\n");
    if (trimmed.len == 0) return error.GitCommandFailed;
    return allocator.dupe(u8, trimmed);
}

fn isCurrentWorktree(path: []const u8, current_worktree_path: []const u8) bool {
    return std.mem.eql(u8, path, current_worktree_path);
}

fn splitSecondaryWorktrees(
    allocator: std.mem.Allocator,
    secondary_worktrees: []const git.WorktreeInfo,
    current_worktree_path: []const u8,
) !SecondarySplit {
    var removable = std.ArrayList(git.WorktreeInfo).init(allocator);
    errdefer removable.deinit();

    var current_secondary: ?git.WorktreeInfo = null;
    for (secondary_worktrees) |wt| {
        if (isCurrentWorktree(wt.path, current_worktree_path)) {
            current_secondary = wt;
            continue;
        }
        try removable.append(wt);
    }

    return .{
        .removable = try removable.toOwnedSlice(),
        .current_secondary = current_secondary,
    };
}

fn isConfirmedResponse(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    return std.ascii.eqlIgnoreCase(trimmed, "y") or std.ascii.eqlIgnoreCase(trimmed, "yes");
}

fn isCancelKey(key: u8) bool {
    return key == esc_key or key == ctrl_c_key;
}

fn isCancelResponse(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 1 and isCancelKey(trimmed[0])) return true;
    return std.ascii.eqlIgnoreCase(trimmed, "q") or
        std.ascii.eqlIgnoreCase(trimmed, "quit") or
        std.ascii.eqlIgnoreCase(trimmed, "cancel");
}

fn shouldUseColor() bool {
    return std.io.getStdOut().isTty() and !std.process.hasEnvVarConstant("NO_COLOR");
}

fn branchDeleteAction(candidate: RemovalCandidate) BranchDeleteAction {
    if (candidate.branch == null) return .skip_detached;
    return .delete;
}

fn isInteractiveSession() bool {
    return std.io.getStdIn().isTty() and std.io.getStdOut().isTty();
}

fn isSingleKeySupported(stdin_file: std.fs.File) bool {
    if (builtin.os.tag == .windows) return false;
    if (!stdin_file.isTty()) return false;
    _ = std.posix.tcgetattr(stdin_file.handle) catch return false;
    return true;
}

fn tryReadSingleKey(stdin_file: std.fs.File) !?u8 {
    if (!isSingleKeySupported(stdin_file)) return null;

    const original_termios = std.posix.tcgetattr(stdin_file.handle) catch return null;
    var raw_termios = original_termios;
    raw_termios.lflag.ICANON = false;
    raw_termios.lflag.ECHO = false;
    raw_termios.lflag.ISIG = false;
    raw_termios.cc[@intFromEnum(std.c.V.MIN)] = 1;
    raw_termios.cc[@intFromEnum(std.c.V.TIME)] = 0;
    std.posix.tcsetattr(stdin_file.handle, .NOW, raw_termios) catch return null;
    defer std.posix.tcsetattr(stdin_file.handle, .NOW, original_termios) catch {};

    var buf: [1]u8 = undefined;
    const read_len = std.posix.read(stdin_file.handle, &buf) catch return null;
    if (read_len == 0) return null;
    return buf[0];
}

fn formatCandidateSummary(buffer: []u8, candidate: RemovalCandidate) []const u8 {
    var fbs = std.io.fixedBufferStream(buffer);
    const w = fbs.writer();

    const is_dirty = candidate.modified > 0 or candidate.untracked > 0;
    if (!is_dirty) {
        w.writeAll("clean") catch unreachable;
    } else {
        w.writeAll("dirty") catch unreachable;
        if (candidate.modified > 0) {
            w.print(": {d} modified", .{candidate.modified}) catch unreachable;
        }
        if (candidate.untracked > 0) {
            if (candidate.modified > 0) {
                w.writeAll(", ") catch unreachable;
            } else {
                w.writeAll(": ") catch unreachable;
            }
            w.print("{d} untracked", .{candidate.untracked}) catch unreachable;
        }
    }

    if (candidate.unmerged) |count| {
        if (count > 0) {
            w.print(", {d} unmerged", .{count}) catch unreachable;
        }
    }

    return fbs.getWritten();
}

fn printCandidateRow(
    stdout: anytype,
    use_color: bool,
    idx: usize,
    candidate: RemovalCandidate,
) !void {
    const branch_name = candidate.branch orelse "(detached)";

    var summary_buf: [128]u8 = undefined;
    const summary = formatCandidateSummary(&summary_buf, candidate);

    if (!use_color) {
        try stdout.print("  [{d}] {s:<20} {s}  ({s})\n", .{ idx + 1, branch_name, candidate.path, summary });
        return;
    }

    const summary_color: []const u8 = if (candidate.safe) ansi_green else ansi_yellow;
    try stdout.print(
        "  [{d}] {s}{s}{s}  {s}  ({s}{s}{s})\n",
        .{ idx + 1, ansi_bold, branch_name, ansi_reset, candidate.path, summary_color, summary, ansi_reset },
    );
}

fn promptSelectionLineMode(
    stdout: anytype,
    stdin_file: std.fs.File,
    candidate_count: usize,
) !?usize {
    var response_buf: [128]u8 = undefined;

    while (true) {
        try stdout.print("Select worktree [1-{d}], q to quit: ", .{candidate_count});
        const response = try stdin_file.reader().readUntilDelimiterOrEof(&response_buf, '\n');
        if (response == null) return null;

        const trimmed = std.mem.trim(u8, response.?, " \t\r\n");
        if (trimmed.len == 0) {
            try stdout.writeAll("Please enter a number or q.\n");
            continue;
        }

        if (isCancelResponse(trimmed)) {
            return null;
        }

        const selected = std.fmt.parseInt(usize, trimmed, 10) catch {
            try stdout.writeAll("Invalid selection. Enter a number or q.\n");
            continue;
        };

        if (selected < 1 or selected > candidate_count) {
            try stdout.print("Selection out of range (1-{d}).\n", .{candidate_count});
            continue;
        }

        return selected - 1;
    }
}

fn promptSelectionRawMode(
    stdout: anytype,
    stdin_file: std.fs.File,
    candidate_count: usize,
) !?usize {
    while (true) {
        try stdout.print("Select worktree [1-{d}], q to quit: ", .{candidate_count});

        var digits: [16]u8 = undefined;
        var digit_len: usize = 0;

        while (true) {
            const key = (try tryReadSingleKey(stdin_file)) orelse return error.SingleKeyUnavailable;
            if (key == '\r' or key == '\n') {
                try stdout.writeAll("\n");
                if (digit_len == 0) {
                    try stdout.writeAll("Please enter a number or q.\n");
                    break;
                }

                const selected = std.fmt.parseInt(usize, digits[0..digit_len], 10) catch {
                    try stdout.writeAll("Invalid selection. Enter a number or q.\n");
                    break;
                };

                if (selected < 1 or selected > candidate_count) {
                    try stdout.print("Selection out of range (1-{d}).\n", .{candidate_count});
                    break;
                }

                return selected - 1;
            }

            if (isCancelKey(key)) {
                try stdout.writeAll("\n");
                return null;
            }

            if ((key == 'q' or key == 'Q') and digit_len == 0) {
                try stdout.print("{c}\n", .{key});
                return null;
            }

            if (key == 0x7f or key == 0x08) {
                if (digit_len > 0) {
                    digit_len -= 1;
                    try stdout.writeAll("\x08 \x08");
                }
                continue;
            }

            if (std.ascii.isDigit(key)) {
                if (digit_len < digits.len) {
                    digits[digit_len] = key;
                    digit_len += 1;
                    try stdout.print("{c}", .{key});
                }
                continue;
            }
        }
    }
}

fn selectViaBuiltin(
    stdout: anytype,
    stdin_file: std.fs.File,
    candidates: []const RemovalCandidate,
    use_color: bool,
) !?usize {
    try stdout.writeAll("Choose a worktree to remove:\n");
    for (candidates, 0..) |candidate, idx| {
        try printCandidateRow(stdout, use_color, idx, candidate);
    }

    if (isSingleKeySupported(stdin_file)) {
        return promptSelectionRawMode(stdout, stdin_file, candidates.len) catch |err| switch (err) {
            error.SingleKeyUnavailable => promptSelectionLineMode(stdout, stdin_file, candidates.len),
            else => err,
        };
    }

    return promptSelectionLineMode(stdout, stdin_file, candidates.len);
}
fn isFzfCancelTerm(term: std.process.Child.Term) bool {
    return switch (term) {
        .Exited => |code| code == 130,
        .Signal => |signal| signal == 2,
        else => false,
    };
}

fn selectViaFzf(
    allocator: std.mem.Allocator,
    candidates: []const RemovalCandidate,
    use_color: bool,
) !?usize {
    var child = std.process.Child.init(
        &.{
            "fzf",
            "--prompt",
            "Remove worktree > ",
            "--height",
            "40%",
            "--reverse",
            "--no-multi",
            "--delimiter",
            "\t",
            "--with-nth",
            "2",
            "--header",
            "BRANCH               STATUS                      PATH",
            "--tabstop",
            "4",
            "--ansi",
        },
        allocator,
    );
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    errdefer {
        _ = child.kill() catch {};
    }

    {
        var input = child.stdin.?.writer();
        for (candidates, 0..) |candidate, idx| {
            var summary_buf: [128]u8 = undefined;
            const summary = formatCandidateSummary(&summary_buf, candidate);
            const branch_name = candidate.branch orelse "(detached)";
            if (use_color) {
                const summary_color: []const u8 = if (candidate.safe) ansi_green else ansi_yellow;
                try input.print(
                    "{d}\t{s:<20}  {s}{s:<26}{s}  {s}\n",
                    .{ idx + 1, branch_name, summary_color, summary, ansi_reset, candidate.path },
                );
            } else {
                try input.print("{d}\t{s:<20}  {s:<26}  {s}\n", .{ idx + 1, branch_name, summary, candidate.path });
            }
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
        .Exited => |code| {
            if (code != 0) {
                return error.FzfFailed;
            }
        },
        else => return error.FzfFailed,
    }

    const selected_line = std.mem.trim(u8, stdout_buf.items, " \t\r\n");
    if (selected_line.len == 0) return null;

    const tab_idx = std.mem.indexOfScalar(u8, selected_line, '\t') orelse return error.FzfInvalidSelection;
    const index_raw = selected_line[0..tab_idx];
    const selected = std.fmt.parseInt(usize, index_raw, 10) catch return error.FzfInvalidSelection;
    if (selected < 1 or selected > candidates.len) return error.FzfInvalidSelection;

    return selected - 1;
}

fn printBlockedCurrentWorktreeMessage(
    stderr: anytype,
    use_color: bool,
    current_branch: []const u8,
    current_path: []const u8,
    main_path: []const u8,
) !void {
    if (use_color) {
        try stderr.print(
            "\n{s}{s}Warning:{s} cannot remove the current worktree\n",
            .{ ansi_bold, ansi_yellow, ansi_reset },
        );
        try stderr.print("  branch: {s}{s}{s}\n", .{ ansi_bold, current_branch, ansi_reset });
        try stderr.print("  path:   {s}\n", .{current_path});
    } else {
        try stderr.writeAll("\nWarning: cannot remove the current worktree\n");
        try stderr.print("  branch: {s}\n", .{current_branch});
        try stderr.print("  path:   {s}\n", .{current_path});
    }

    try stderr.writeAll("Removing it would leave this shell in a deleted directory.\n");
    try stderr.print("Switch to another checkout first (for example: cd {s}).\n\n", .{main_path});
}

fn printSkipCurrentWorktreeMessage(
    stderr: anytype,
    use_color: bool,
    current_branch: []const u8,
    current_path: []const u8,
) !void {
    if (use_color) {
        try stderr.print(
            "\n{s}{s}Warning:{s} excluding current worktree from removal candidates\n",
            .{ ansi_bold, ansi_yellow, ansi_reset },
        );
    } else {
        try stderr.writeAll("\nWarning: excluding current worktree from removal candidates\n");
    }

    try stderr.print("  branch: {s}\n", .{current_branch});
    try stderr.print("  path:   {s}\n", .{current_path});
    try stderr.writeAll("Remove it from another checkout if needed.\n\n");
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

fn resolvePickerMode(
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

fn inspectCandidate(
    allocator: std.mem.Allocator,
    main_path: []const u8,
    wt: git.WorktreeInfo,
) !RemovalCandidate {
    const status_output = try git.runGit(allocator, wt.path, &.{ "status", "--porcelain" });
    defer allocator.free(status_output);

    const status = git.parseStatusPorcelain(status_output);

    var unmerged: ?usize = null;
    if (wt.branch) |branch| {
        unmerged = try git.countUnmergedCommits(allocator, main_path, "HEAD", branch);
    }

    const has_dirty = status.modified > 0 or status.untracked > 0;
    const has_unmerged = if (unmerged) |count| count > 0 else false;

    return .{
        .path = wt.path,
        .branch = wt.branch,
        .modified = status.modified,
        .untracked = status.untracked,
        .unmerged = unmerged,
        .safe = !has_dirty and !has_unmerged,
    };
}

fn buildCandidates(
    allocator: std.mem.Allocator,
    main_path: []const u8,
    secondary_worktrees: []const git.WorktreeInfo,
) ![]RemovalCandidate {
    var candidates = std.ArrayList(RemovalCandidate).init(allocator);
    errdefer candidates.deinit();

    for (secondary_worktrees) |wt| {
        const candidate = try inspectCandidate(allocator, main_path, wt);
        try candidates.append(candidate);
    }

    return candidates.toOwnedSlice();
}

fn confirmUnsafeRemoval(
    stdout: anytype,
    stdin: anytype,
    target_name: []const u8,
    modified: usize,
    untracked: usize,
    unmerged_commits: ?usize,
) !bool {
    try stdout.print("Warning: unsafe worktree removal for '{s}'\n", .{target_name});
    if (modified > 0 or untracked > 0) {
        try stdout.print("- dirty worktree: {d} modified, {d} untracked\n", .{ modified, untracked });
    }
    if (unmerged_commits) |count| {
        if (count > 0) {
            try stdout.print("- branch has {d} unmerged commit(s) vs HEAD\n", .{count});
        }
    }
    try stdout.print("Remove anyway? [y/N]: ", .{});

    var response_buf: [16]u8 = undefined;
    const response = try stdin.readUntilDelimiterOrEof(&response_buf, '\n');
    if (response == null) return false;
    return isConfirmedResponse(response.?);
}

fn removeCandidate(
    allocator: std.mem.Allocator,
    candidate: RemovalCandidate,
    main_path: []const u8,
    force: bool,
) !void {
    const stdout = std.io.getStdOut().writer();

    std.fs.cwd().access(candidate.path, .{}) catch {
        std.debug.print("Error: worktree at {s} does not exist\n", .{candidate.path});
        std.process.exit(1);
    };

    if (!force and !candidate.safe) {
        if (!std.io.getStdIn().isTty()) {
            std.debug.print("Error: worktree removal is unsafe and requires confirmation\n", .{});
            std.debug.print("Use --force to remove anyway\n", .{});
            std.process.exit(1);
        }

        const target_name = candidate.branch orelse candidate.path;
        const confirmed = confirmUnsafeRemoval(
            stdout,
            std.io.getStdIn().reader(),
            target_name,
            candidate.modified,
            candidate.untracked,
            candidate.unmerged,
        ) catch {
            std.debug.print("Error: failed to read confirmation\n", .{});
            std.process.exit(1);
        };

        if (!confirmed) {
            std.debug.print("Aborted\n", .{});
            std.process.exit(1);
        }
    }

    if (force) {
        const rm_result = git.runGit(allocator, null, &.{ "worktree", "remove", "--force", candidate.path }) catch {
            std.debug.print("Error: could not remove worktree\n", .{});
            std.process.exit(1);
        };
        allocator.free(rm_result);
    } else {
        const rm_result = git.runGit(allocator, null, &.{ "worktree", "remove", candidate.path }) catch {
            std.debug.print("Error: could not remove worktree\n", .{});
            std.process.exit(1);
        };
        allocator.free(rm_result);
    }

    std.debug.print("Removed worktree {s}\n", .{candidate.path});

    switch (branchDeleteAction(candidate)) {
        .delete => {
            const branch = candidate.branch.?;
            const del_result = git.runGit(allocator, main_path, &.{ "branch", "-d", branch }) catch {
                std.debug.print("Branch '{s}' kept (has unmerged commits)\n", .{branch});
                return;
            };
            allocator.free(del_result);
            std.debug.print("Deleted merged branch '{s}'\n", .{branch});
        },
        .skip_detached => {
            std.debug.print("Detached worktree removed; no branch deleted\n", .{});
        },
    }
}

pub fn run(allocator: std.mem.Allocator, options: RmOptions) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    const use_color = shouldUseColor();

    const wt_output = git.runGit(allocator, null, &.{ "worktree", "list", "--porcelain" }) catch {
        std.debug.print("Error: not a git repository or git not found\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(wt_output);

    const worktrees = try git.parseWorktreeList(allocator, wt_output);
    defer allocator.free(worktrees);

    if (worktrees.len < 2) {
        std.debug.print("No secondary worktrees to remove\n", .{});
        return;
    }

    const current_worktree_path = detectCurrentWorktreePath(allocator) catch {
        std.debug.print("Error: could not determine current worktree path\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(current_worktree_path);

    const main_path = worktrees[0].path;

    if (options.branch_arg) |branch| {
        const wt_info = findWorktreeByBranch(worktrees, branch) orelse {
            std.debug.print("Error: no worktree found for branch '{s}'\n", .{branch});
            std.process.exit(1);
        };

        if (isCurrentWorktree(wt_info.path, current_worktree_path)) {
            const current_branch = wt_info.branch orelse "(detached)";
            try printBlockedCurrentWorktreeMessage(
                stderr,
                use_color,
                current_branch,
                wt_info.path,
                main_path,
            );
            std.process.exit(1);
        }

        const candidate = inspectCandidate(allocator, main_path, wt_info) catch {
            std.debug.print("Error: could not inspect worktree for branch '{s}'\n", .{branch});
            std.process.exit(1);
        };

        try removeCandidate(allocator, candidate, main_path, options.force);
        return;
    }

    const split = splitSecondaryWorktrees(allocator, worktrees[1..], current_worktree_path) catch {
        std.debug.print("Error: could not build worktree removal candidates\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(split.removable);

    if (split.removable.len == 0) {
        if (split.current_secondary) |current_secondary| {
            const current_branch = current_secondary.branch orelse "(detached)";
            try printBlockedCurrentWorktreeMessage(
                stderr,
                use_color,
                current_branch,
                current_secondary.path,
                main_path,
            );
            return;
        }

        std.debug.print("No secondary worktrees to remove\n", .{});
        return;
    }

    if (split.current_secondary) |current_secondary| {
        const current_branch = current_secondary.branch orelse "(detached)";
        try printSkipCurrentWorktreeMessage(
            stderr,
            use_color,
            current_branch,
            current_secondary.path,
        );
    }

    if (options.no_interactive or !isInteractiveSession()) {
        try stderr.writeAll("Error: wt rm without a branch requires an interactive terminal\n");
        try stderr.writeAll("Use `wt list` to inspect worktrees, or pass a branch to `wt rm <branch>`.\n");
        std.process.exit(1);
    }

    const candidates = buildCandidates(allocator, main_path, split.removable) catch {
        std.debug.print("Error: could not build worktree removal candidates\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(candidates);

    const resolved_mode = resolvePickerMode(allocator, options.picker_mode, commandExists) catch |err| {
        switch (err) {
            error.FzfUnavailable => {
                try stderr.writeAll("Error: picker 'fzf' was requested but fzf is not available on PATH\n");
                try stderr.writeAll("Install fzf or use `--picker builtin`.\n");
                std.process.exit(1);
            },
            else => return err,
        }
    };

    const selected_index = switch (resolved_mode) {
        .builtin => try selectViaBuiltin(stdout, std.io.getStdIn(), candidates, use_color),
        .fzf => selectViaFzf(allocator, candidates, use_color) catch |err| {
            switch (err) {
                error.FzfFailed => {
                    try stderr.writeAll("Error: fzf failed while selecting a worktree\n");
                    std.process.exit(1);
                },
                error.FzfInvalidSelection => {
                    try stderr.writeAll("Error: failed to parse fzf selection\n");
                    std.process.exit(1);
                },
                else => return err,
            }
        },
        .auto => unreachable,
    };

    if (selected_index == null) {
        try stderr.writeAll("Aborted (no worktree removed)\n");
        return;
    }

    try removeCandidate(allocator, candidates[selected_index.?], main_path, options.force);
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

fn detectorAlwaysTrue(_: std.mem.Allocator, _: []const u8) bool {
    return true;
}

fn detectorAlwaysFalse(_: std.mem.Allocator, _: []const u8) bool {
    return false;
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

test "branchDeleteAction skips detached worktrees" {
    const detached: RemovalCandidate = .{
        .path = "/tmp/repo--detached",
        .branch = null,
        .modified = 0,
        .untracked = 0,
        .unmerged = null,
        .safe = true,
    };

    const branched: RemovalCandidate = .{
        .path = "/tmp/repo--feat",
        .branch = "feat",
        .modified = 0,
        .untracked = 0,
        .unmerged = 0,
        .safe = true,
    };

    try std.testing.expectEqual(BranchDeleteAction.skip_detached, branchDeleteAction(detached));
    try std.testing.expectEqual(BranchDeleteAction.delete, branchDeleteAction(branched));
}

test "formatCandidateSummary includes dirty and unmerged details" {
    const candidate: RemovalCandidate = .{
        .path = "/tmp/repo--feat",
        .branch = "feat",
        .modified = 2,
        .untracked = 1,
        .unmerged = 3,
        .safe = false,
    };

    var buf: [128]u8 = undefined;
    const summary = formatCandidateSummary(&buf, candidate);
    try std.testing.expect(std.mem.indexOf(u8, summary, "dirty") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "2 modified") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "1 untracked") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "3 unmerged") != null);
}

test "cancel helpers recognize q and control keys" {
    try std.testing.expect(isCancelKey(esc_key));
    try std.testing.expect(isCancelKey(ctrl_c_key));
    try std.testing.expect(!isCancelKey('q'));

    try std.testing.expect(isCancelResponse("q"));
    try std.testing.expect(isCancelResponse("quit"));
    try std.testing.expect(isCancelResponse("cancel"));

    const esc_text = [_]u8{esc_key};
    const ctrl_c_text = [_]u8{ctrl_c_key};
    try std.testing.expect(isCancelResponse(&esc_text));
    try std.testing.expect(isCancelResponse(&ctrl_c_text));
}

test "findWorktreeByBranch matches branch regardless of path naming" {
    const worktrees = [_]git.WorktreeInfo{
        .{ .path = "/tmp/repo", .head = "a", .branch = "main", .is_bare = false },
        .{ .path = "/tmp/custom/location/feature-tree", .head = "b", .branch = "feat-x", .is_bare = false },
    };

    const found = findWorktreeByBranch(&worktrees, "feat-x");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("/tmp/custom/location/feature-tree", found.?.path);
}

test "findWorktreeByBranch skips main worktree" {
    const worktrees = [_]git.WorktreeInfo{
        .{ .path = "/tmp/repo", .head = "a", .branch = "main", .is_bare = false },
    };

    const found = findWorktreeByBranch(&worktrees, "main");
    try std.testing.expect(found == null);
}

test "splitSecondaryWorktrees excludes current secondary worktree" {
    const secondary = [_]git.WorktreeInfo{
        .{ .path = "/tmp/repo--feat-a", .head = "a", .branch = "feat-a", .is_bare = false },
        .{ .path = "/tmp/repo--feat-b", .head = "b", .branch = "feat-b", .is_bare = false },
    };

    const split = try splitSecondaryWorktrees(std.testing.allocator, &secondary, "/tmp/repo--feat-b");
    defer std.testing.allocator.free(split.removable);

    try std.testing.expectEqual(@as(usize, 1), split.removable.len);
    try std.testing.expectEqualStrings("/tmp/repo--feat-a", split.removable[0].path);
    try std.testing.expect(split.current_secondary != null);
    try std.testing.expectEqualStrings("/tmp/repo--feat-b", split.current_secondary.?.path);
}

test "splitSecondaryWorktrees keeps all secondaries when current is main" {
    const secondary = [_]git.WorktreeInfo{
        .{ .path = "/tmp/repo--feat-a", .head = "a", .branch = "feat-a", .is_bare = false },
        .{ .path = "/tmp/repo--feat-b", .head = "b", .branch = "feat-b", .is_bare = false },
    };

    const split = try splitSecondaryWorktrees(std.testing.allocator, &secondary, "/tmp/repo");
    defer std.testing.allocator.free(split.removable);

    try std.testing.expectEqual(@as(usize, 2), split.removable.len);
    try std.testing.expect(split.current_secondary == null);
}

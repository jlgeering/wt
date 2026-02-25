const std = @import("std");
const git = @import("../lib/git.zig");
const column_format = @import("../lib/column_format.zig");
const ui = @import("../lib/ui.zig");

const OutputMode = enum {
    human,
    machine,
};

const Divergence = struct {
    known: bool,
    available: bool,
    ahead: usize,
    behind: usize,
};

const WorktreeRow = struct {
    is_current: bool,
    branch_name: []const u8,
    path: []const u8,
    wt_known: bool,
    tracked_changes: usize,
    untracked: usize,
    base_ref: []const u8,
    base_divergence: Divergence,
    upstream_divergence: Divergence,
};

const marker_width: usize = 3;
const branch_width: usize = 20;
const wt_width: usize = 8;
const base_width: usize = 9;
const upstream_width: usize = 9;

fn shouldUseColor() bool {
    return ui.shouldUseColor(std.fs.File.stdout());
}

fn wtStateLabel(row: WorktreeRow) []const u8 {
    if (!row.wt_known) return "unknown";
    return if (row.tracked_changes == 0 and row.untracked == 0) "clean" else "dirty";
}

fn writeDivergenceLabel(divergence: Divergence, writer: anytype) void {
    if (!divergence.known) {
        writer.writeAll("unknown") catch {};
        return;
    }
    if (!divergence.available) {
        writer.writeAll("-") catch {};
        return;
    }
    if (divergence.ahead == 0 and divergence.behind == 0) {
        writer.writeAll("=") catch {};
        return;
    }
    if (divergence.ahead > 0) {
        writer.print("\u{2191}{d}", .{divergence.ahead}) catch {};
    }
    if (divergence.behind > 0) {
        writer.print("\u{2193}{d}", .{divergence.behind}) catch {};
    }
}

fn divergenceLabel(divergence: Divergence, buffer: []u8) []const u8 {
    var fbs = std.io.fixedBufferStream(buffer);
    writeDivergenceLabel(divergence, fbs.writer());
    return fbs.getWritten();
}

fn divergenceCountOrMinusOne(divergence: Divergence, field: enum { ahead, behind }) i64 {
    if (!divergence.known or !divergence.available) return -1;
    const count = switch (field) {
        .ahead => divergence.ahead,
        .behind => divergence.behind,
    };
    return @as(i64, @intCast(count));
}

fn writeHumanHeader(stdout: anytype) !void {
    try writeHumanColumns(stdout, "CUR", "BRANCH", "WT", "BASE", "UPSTREAM", "PATH");
    try stdout.writeByte('\n');
    try writeHumanColumns(
        stdout,
        "---",
        "--------------------",
        "--------",
        "---------",
        "---------",
        "------------------------------",
    );
    try stdout.writeByte('\n');
}

fn wtColor(row: WorktreeRow) []const u8 {
    if (!row.wt_known) return ui.ansi.yellow;
    return if (row.tracked_changes == 0 and row.untracked == 0) ui.ansi.green else ui.ansi.yellow;
}

fn divergenceColor(divergence: Divergence) []const u8 {
    if (!divergence.known) return ui.ansi.yellow;
    if (!divergence.available) return ui.ansi.reset;
    return if (divergence.ahead == 0 and divergence.behind == 0) ui.ansi.green else ui.ansi.yellow;
}

fn writeHumanRow(stdout: anytype, row: WorktreeRow, use_color: bool) !void {
    const marker: []const u8 = if (row.is_current) "*" else "";

    var base_buf: [32]u8 = undefined;
    var upstream_buf: [32]u8 = undefined;
    const wt = wtStateLabel(row);
    const base = divergenceLabel(row.base_divergence, &base_buf);
    const upstream = divergenceLabel(row.upstream_divergence, &upstream_buf);

    if (!use_color) {
        try writeHumanColumns(stdout, marker, row.branch_name, wt, base, upstream, row.path);
        try stdout.writeByte('\n');
        return;
    }

    var wt_buf: [64]u8 = undefined;
    const wt_colored = std.fmt.bufPrint(&wt_buf, "{s}{s}{s}", .{ wtColor(row), wt, ui.ansi.reset }) catch wt;
    var base_colored_buf: [80]u8 = undefined;
    const base_colored = std.fmt.bufPrint(&base_colored_buf, "{s}{s}{s}", .{
        divergenceColor(row.base_divergence),
        base,
        ui.ansi.reset,
    }) catch base;
    var upstream_colored_buf: [80]u8 = undefined;
    const upstream_colored = std.fmt.bufPrint(&upstream_colored_buf, "{s}{s}{s}", .{
        divergenceColor(row.upstream_divergence),
        upstream,
        ui.ansi.reset,
    }) catch upstream;

    try writeHumanColumns(
        stdout,
        marker,
        row.branch_name,
        wt_colored,
        base_colored,
        upstream_colored,
        row.path,
    );
    try stdout.writeByte('\n');
}

fn writeHumanColumns(
    writer: anytype,
    marker: []const u8,
    branch: []const u8,
    wt: []const u8,
    base: []const u8,
    upstream: []const u8,
    path: []const u8,
) !void {
    try column_format.writePadded(writer, marker, marker_width);
    try writer.writeAll(" ");
    try column_format.writePadded(writer, branch, branch_width);
    try writer.writeAll(" ");
    try column_format.writePadded(writer, wt, wt_width);
    try writer.writeAll(" ");
    try column_format.writePadded(writer, base, base_width);
    try writer.writeAll(" ");
    try column_format.writePadded(writer, upstream, upstream_width);
    try writer.writeAll(" ");
    try writer.writeAll(path);
}

fn writeMachineRow(stdout: anytype, row: WorktreeRow) !void {
    const current: usize = if (row.is_current) 1 else 0;
    const has_upstream: usize = if (row.upstream_divergence.known and row.upstream_divergence.available) 1 else 0;
    try stdout.print(
        "{d}\t{s}\t{s}\t{s}\t{d}\t{d}\t{s}\t{d}\t{d}\t{d}\t{d}\t{d}\n",
        .{
            current,
            row.branch_name,
            row.path,
            wtStateLabel(row),
            row.tracked_changes,
            row.untracked,
            row.base_ref,
            divergenceCountOrMinusOne(row.base_divergence, .ahead),
            divergenceCountOrMinusOne(row.base_divergence, .behind),
            has_upstream,
            divergenceCountOrMinusOne(row.upstream_divergence, .ahead),
            divergenceCountOrMinusOne(row.upstream_divergence, .behind),
        },
    );
}

fn resolveCurrentWorktreeRoot(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    const top_level_output = git.runGit(allocator, cwd, &.{ "rev-parse", "--show-toplevel" }) catch {
        return try allocator.dupe(u8, cwd);
    };
    defer allocator.free(top_level_output);

    const top_level = std.mem.trim(u8, top_level_output, " \t\r\n");
    if (top_level.len == 0) {
        return try allocator.dupe(u8, cwd);
    }

    return try allocator.dupe(u8, top_level);
}

fn inspectWorktree(
    allocator: std.mem.Allocator,
    current_worktree_root: []const u8,
    wt: git.WorktreeInfo,
    base_branch: ?[]const u8,
) WorktreeRow {
    const is_current = std.mem.eql(u8, current_worktree_root, wt.path);
    const branch_name = wt.branch orelse "(detached)";
    const base_ref = base_branch orelse "-";

    var wt_known = false;
    var tracked_changes: usize = 0;
    var untracked: usize = 0;
    var upstream_divergence: Divergence = .{
        .known = false,
        .available = false,
        .ahead = 0,
        .behind = 0,
    };

    const status_output = git.runGit(allocator, wt.path, &.{ "status", "--porcelain", "--branch" }) catch null;
    if (status_output) |output| {
        defer allocator.free(output);
        wt_known = true;
        const status = git.parseStatusPorcelain(output);
        tracked_changes = status.modified;
        untracked = status.untracked;

        const upstream = git.parseBranchDivergence(output);
        upstream_divergence = .{
            .known = true,
            .available = upstream.has_upstream,
            .ahead = upstream.ahead,
            .behind = upstream.behind,
        };
    }

    var base_divergence: Divergence = .{
        .known = true,
        .available = false,
        .ahead = 0,
        .behind = 0,
    };
    if (wt.branch) |branch| {
        if (base_branch) |base| {
            if (std.mem.eql(u8, branch, base)) {
                base_divergence.available = true;
            } else {
                var base_ok = true;
                var ahead: usize = 0;
                var behind: usize = 0;

                const ahead_result = git.countUnmergedCommits(allocator, wt.path, base, branch);
                if (ahead_result) |count| {
                    ahead = count;
                } else |_| {
                    base_ok = false;
                }

                const behind_result = git.countUnmergedCommits(allocator, wt.path, branch, base);
                if (behind_result) |count| {
                    behind = count;
                } else |_| {
                    base_ok = false;
                }

                if (base_ok) {
                    base_divergence = .{
                        .known = true,
                        .available = true,
                        .ahead = ahead,
                        .behind = behind,
                    };
                } else {
                    base_divergence = .{
                        .known = false,
                        .available = false,
                        .ahead = 0,
                        .behind = 0,
                    };
                }
            }
        }
    }

    return .{
        .is_current = is_current,
        .branch_name = branch_name,
        .path = wt.path,
        .wt_known = wt_known,
        .tracked_changes = tracked_changes,
        .untracked = untracked,
        .base_ref = base_ref,
        .base_divergence = base_divergence,
        .upstream_divergence = upstream_divergence,
    };
}

fn runWithMode(allocator: std.mem.Allocator, mode: OutputMode) !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();
    const use_stderr_color = ui.shouldUseColor(std.fs.File.stderr());
    const use_color = shouldUseColor();

    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    const current_worktree_root = try resolveCurrentWorktreeRoot(allocator, cwd);
    defer allocator.free(current_worktree_root);

    const wt_output = git.runGit(allocator, null, &.{ "worktree", "list", "--porcelain" }) catch {
        try ui.printLevel(stderr, use_stderr_color, .err, "not a git repository or git not found", .{});
        std.process.exit(1);
    };
    defer allocator.free(wt_output);

    const worktrees = try git.parseWorktreeList(allocator, wt_output);
    defer allocator.free(worktrees);

    if (worktrees.len == 0) {
        try ui.printLevel(stderr, use_stderr_color, .info, "no worktrees found", .{});
        return;
    }

    const base_branch = worktrees[0].branch;

    if (mode == .human) {
        try stdout.writeAll("\n");
        try writeHumanHeader(stdout);
    }

    for (worktrees) |wt| {
        const row = inspectWorktree(allocator, current_worktree_root, wt, base_branch);
        if (mode == .machine) {
            try writeMachineRow(stdout, row);
        } else {
            try writeHumanRow(stdout, row, use_color);
        }
    }
}

pub fn runHuman(allocator: std.mem.Allocator) !void {
    try runWithMode(allocator, .human);
}

pub fn runMachine(allocator: std.mem.Allocator) !void {
    try runWithMode(allocator, .machine);
}

test "writeMachineRow uses tab-separated schema with base and upstream divergence" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    const row: WorktreeRow = .{
        .is_current = true,
        .branch_name = "feat-x",
        .path = "/tmp/repo--feat-x",
        .wt_known = true,
        .tracked_changes = 2,
        .untracked = 1,
        .base_ref = "main",
        .base_divergence = .{ .known = true, .available = true, .ahead = 4, .behind = 1 },
        .upstream_divergence = .{ .known = true, .available = true, .ahead = 3, .behind = 0 },
    };
    try writeMachineRow(fbs.writer(), row);

    try std.testing.expectEqualStrings(
        "1\tfeat-x\t/tmp/repo--feat-x\tdirty\t2\t1\tmain\t4\t1\t1\t3\t0\n",
        fbs.getWritten(),
    );
}

test "writeHumanRow includes WT BASE and UPSTREAM columns" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    const row: WorktreeRow = .{
        .is_current = false,
        .branch_name = "main",
        .path = "/tmp/repo",
        .wt_known = true,
        .tracked_changes = 0,
        .untracked = 0,
        .base_ref = "main",
        .base_divergence = .{ .known = true, .available = true, .ahead = 0, .behind = 0 },
        .upstream_divergence = .{ .known = true, .available = true, .ahead = 2, .behind = 1 },
    };
    try writeHumanRow(fbs.writer(), row, false);

    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "clean") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "=") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\xE2\x86\x912\xE2\x86\x931") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "/tmp/repo") != null);
}

test "writeHumanHeader prints table columns" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    try writeHumanHeader(fbs.writer());
    const out = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, out, "CUR BRANCH") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "WT") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "BASE") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "UPSTREAM") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "PATH") != null);
}

test "writeHumanRow uses dirty label and unavailable divergence marker" {
    var out_buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out_buf);

    const row: WorktreeRow = .{
        .is_current = false,
        .branch_name = "feat-x",
        .path = "/tmp/repo--feat-x",
        .wt_known = true,
        .tracked_changes = 2,
        .untracked = 1,
        .base_ref = "main",
        .base_divergence = .{ .known = true, .available = true, .ahead = 0, .behind = 1 },
        .upstream_divergence = .{ .known = true, .available = false, .ahead = 0, .behind = 0 },
    };
    try writeHumanRow(fbs.writer(), row, false);

    const out = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, out, "dirty") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\xE2\x86\x931") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, " - ") != null);
}

test "writeHumanRow keeps PATH column aligned with unicode upstream" {
    var header_buf: [256]u8 = undefined;
    var header_fbs = std.io.fixedBufferStream(&header_buf);
    try writeHumanHeader(header_fbs.writer());
    const header = header_fbs.getWritten();

    var row_buf: [256]u8 = undefined;
    var row_fbs = std.io.fixedBufferStream(&row_buf);
    const row: WorktreeRow = .{
        .is_current = true,
        .branch_name = "main",
        .path = "/tmp/repo",
        .wt_known = true,
        .tracked_changes = 1,
        .untracked = 0,
        .base_ref = "main",
        .base_divergence = .{ .known = true, .available = true, .ahead = 0, .behind = 0 },
        .upstream_divergence = .{ .known = true, .available = true, .ahead = 12, .behind = 3 },
    };
    try writeHumanRow(row_fbs.writer(), row, false);
    const rendered_row = row_fbs.getWritten();

    try std.testing.expectEqual(columnStartWidth(header, "PATH"), columnStartWidth(rendered_row, "/tmp/repo"));
}

test "writeHumanRow keeps PATH column aligned with unicode upstream in color mode" {
    var header_buf: [256]u8 = undefined;
    var header_fbs = std.io.fixedBufferStream(&header_buf);
    try writeHumanHeader(header_fbs.writer());
    const header = header_fbs.getWritten();

    var row_buf: [512]u8 = undefined;
    var row_fbs = std.io.fixedBufferStream(&row_buf);
    const row: WorktreeRow = .{
        .is_current = true,
        .branch_name = "main",
        .path = "/tmp/repo",
        .wt_known = true,
        .tracked_changes = 1,
        .untracked = 0,
        .base_ref = "main",
        .base_divergence = .{ .known = true, .available = true, .ahead = 0, .behind = 0 },
        .upstream_divergence = .{ .known = true, .available = true, .ahead = 12, .behind = 3 },
    };
    try writeHumanRow(row_fbs.writer(), row, true);
    const rendered_row = row_fbs.getWritten();

    try std.testing.expectEqual(columnStartWidth(header, "PATH"), columnStartWidth(rendered_row, "/tmp/repo"));
}

fn columnStartWidth(line: []const u8, token: []const u8) usize {
    const idx = std.mem.indexOf(u8, line, token) orelse unreachable;
    return column_format.visibleWidth(line[0..idx]);
}

test "resolveCurrentWorktreeRoot falls back to cwd outside a git repo" {
    const root = try resolveCurrentWorktreeRoot(std.testing.allocator, "/");
    defer std.testing.allocator.free(root);

    try std.testing.expectEqualStrings("/", root);
}

test "resolveCurrentWorktreeRoot resolves repo root from nested directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    const init_output = try git.runGit(std.testing.allocator, repo_root, &.{ "init" });
    defer std.testing.allocator.free(init_output);

    try tmp.dir.makePath("nested/deep");
    const nested = try std.fs.path.join(std.testing.allocator, &.{ repo_root, "nested", "deep" });
    defer std.testing.allocator.free(nested);

    const resolved = try resolveCurrentWorktreeRoot(std.testing.allocator, nested);
    defer std.testing.allocator.free(resolved);

    try std.testing.expectEqualStrings(repo_root, resolved);
}

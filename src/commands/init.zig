const std = @import("std");
const git = @import("../lib/git.zig");
const config = @import("../lib/config.zig");
const init_planner = @import("../lib/init_planner.zig");

fn isConfirmedResponse(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    return std.ascii.eqlIgnoreCase(trimmed, "y") or std.ascii.eqlIgnoreCase(trimmed, "yes");
}

fn isNegativeResponse(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    return std.ascii.eqlIgnoreCase(trimmed, "n") or std.ascii.eqlIgnoreCase(trimmed, "no");
}

fn promptYesNo(
    stdout: anytype,
    stdin: anytype,
    question: []const u8,
    default_yes: bool,
) !bool {
    const suffix: []const u8 = if (default_yes) " [Y/n]: " else " [y/N]: ";

    while (true) {
        try stdout.print("{s}{s}", .{ question, suffix });

        var buf: [256]u8 = undefined;
        const response = try stdin.readUntilDelimiterOrEof(&buf, '\n');
        if (response == null) return default_yes;

        const trimmed = std.mem.trim(u8, response.?, " \t\r\n");
        if (trimmed.len == 0) return default_yes;
        if (isConfirmedResponse(trimmed)) return true;
        if (isNegativeResponse(trimmed)) return false;

        try stdout.writeAll("Please answer yes or no.\n");
    }
}

fn getRepoRoot(allocator: std.mem.Allocator) ![]u8 {
    const root_output = git.runGit(allocator, null, &.{ "rev-parse", "--show-toplevel" }) catch {
        return error.NotGitRepository;
    };
    defer allocator.free(root_output);

    const trimmed = std.mem.trim(u8, root_output, " \t\r\n");
    if (trimmed.len == 0) return error.NotGitRepository;

    return allocator.dupe(u8, trimmed);
}

fn writeFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

pub fn run(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    if (!std.io.getStdIn().isTty()) {
        std.debug.print("Error: wt init requires an interactive terminal\n", .{});
        std.process.exit(1);
    }

    const repo_root = getRepoRoot(allocator) catch {
        std.debug.print("Error: not a git repository or git not found\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(repo_root);

    const config_path = try std.fs.path.join(allocator, &.{ repo_root, ".wt.toml" });
    defer allocator.free(config_path);

    const config_exists = if (std.fs.cwd().access(config_path, .{})) |_| true else |_| false;

    var parsed = try config.loadConfigFile(allocator, repo_root);
    defer parsed.deinit();

    var editable = try init_planner.EditableConfig.fromConfig(allocator, parsed.value);
    defer editable.deinit();

    var baseline = try editable.clone(allocator);
    defer baseline.deinit();

    try stdout.print("Scanning repository: {s}\n", .{repo_root});
    try stdout.writeAll("Rules cover: mise local variants, .claude/settings.local.json, local .env files, .vscode/settings.local.json, and .envrc.\n\n");

    const recommendations = try init_planner.discoverRecommendations(allocator, repo_root);
    defer init_planner.freeRecommendations(allocator, recommendations);

    if (recommendations.len == 0) {
        try stdout.writeAll("No matching local files found from built-in rules.\n");
    }

    for (recommendations) |rec| {
        const currently_enabled = editable.contains(rec.section, rec.value);
        const question = if (currently_enabled)
            try std.fmt.allocPrint(allocator, "Keep {s}: {s} ({s})", .{ init_planner.sectionName(rec.section), rec.value, rec.reason })
        else
            try std.fmt.allocPrint(allocator, "Add {s}: {s} ({s})", .{ init_planner.sectionName(rec.section), rec.value, rec.reason });
        defer allocator.free(question);

        const desired = try promptYesNo(stdout, std.io.getStdIn().reader(), question, currently_enabled);

        if (desired and !currently_enabled) {
            _ = try editable.add(rec.section, rec.value);
        } else if (!desired and currently_enabled) {
            _ = editable.remove(rec.section, rec.value);
        }
    }

    const findings = try init_planner.detectAntiPatterns(allocator, &editable);
    defer init_planner.freeAntiPatterns(allocator, findings);

    if (findings.len > 0) {
        try stdout.writeAll("\nPotential anti-patterns detected:\n");
    }

    for (findings) |finding| {
        if (!editable.contains(finding.section, finding.value)) continue;

        const question = try std.fmt.allocPrint(
            allocator,
            "Remove from {s}: {s} ({s})",
            .{ init_planner.sectionName(finding.section), finding.value, finding.message },
        );
        defer allocator.free(question);

        const remove = try promptYesNo(stdout, std.io.getStdIn().reader(), question, true);
        if (remove) {
            _ = editable.remove(finding.section, finding.value);
        }
    }

    const changes = try init_planner.diffConfigs(allocator, &baseline, &editable);
    defer init_planner.freeChanges(allocator, changes);

    const needs_write = !config_exists or changes.len > 0;
    if (!needs_write) {
        try stdout.writeAll("\n.wt.toml is already aligned with current recommendations.\n");
        return;
    }

    try stdout.writeAll("\nPlanned config changes:\n");
    if (!config_exists) {
        try stdout.print("  + create {s}\n", .{config_path});
    }
    for (changes) |change| {
        const marker: []const u8 = switch (change.kind) {
            .add => "+",
            .remove => "-",
        };
        try stdout.print("  {s} {s}: {s}\n", .{ marker, init_planner.sectionName(change.section), change.value });
    }

    const apply = try promptYesNo(stdout, std.io.getStdIn().reader(), "Write .wt.toml now", true);
    if (!apply) {
        try stdout.writeAll("Aborted without writing changes.\n");
        return;
    }

    const new_content = try editable.renderToml(allocator);
    defer allocator.free(new_content);

    if (config_exists) {
        const existing_content = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
        defer allocator.free(existing_content);

        const backup_path = try std.fmt.allocPrint(allocator, "{s}.bak-{d}", .{ config_path, std.time.timestamp() });
        defer allocator.free(backup_path);

        try writeFile(backup_path, existing_content);
        try stdout.print("Backed up existing config to {s}\n", .{backup_path});
    }

    try writeFile(config_path, new_content);
    try stdout.print("Wrote {s}\n", .{config_path});

    try stdout.writeAll("\nCommon anti-pattern defaults:\n");
    try stdout.writeAll("- Avoid copying .git, .beads, node_modules, .zig-cache, zig-out\n");
    try stdout.writeAll("- Avoid destructive [run].commands like rm -rf or git reset --hard\n");
}

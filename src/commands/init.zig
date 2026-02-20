const std = @import("std");
const git = @import("../lib/git.zig");
const config = @import("../lib/config.zig");
const init_planner = @import("../lib/init_planner.zig");

const ApplyDecision = enum {
    apply_all,
    review,
    cancel,
};

const ansi_reset = "\x1b[0m";
const ansi_bold = "\x1b[1m";
const ansi_green = "\x1b[32m";
const ansi_yellow = "\x1b[33m";
const ansi_red = "\x1b[31m";

fn isConfirmedResponse(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    return std.ascii.eqlIgnoreCase(trimmed, "y") or std.ascii.eqlIgnoreCase(trimmed, "yes");
}

fn isEscapeResponse(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    return trimmed.len == 1 and trimmed[0] == 0x1b;
}

fn isNegativeResponse(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    return std.ascii.eqlIgnoreCase(trimmed, "n") or std.ascii.eqlIgnoreCase(trimmed, "no") or isEscapeResponse(trimmed);
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

fn promptApplyDecision(stdout: anytype, stdin: anytype) !ApplyDecision {
    while (true) {
        try stdout.writeAll("Apply changes? [Y/n/r]: ");

        var buf: [256]u8 = undefined;
        const response = try stdin.readUntilDelimiterOrEof(&buf, '\n');
        if (response == null) return .apply_all;

        const trimmed = std.mem.trim(u8, response.?, " \t\r\n");
        if (trimmed.len == 0) return .apply_all;
        if (isConfirmedResponse(trimmed)) return .apply_all;
        if (isNegativeResponse(trimmed)) return .cancel;
        if (std.ascii.eqlIgnoreCase(trimmed, "r") or std.ascii.eqlIgnoreCase(trimmed, "review")) return .review;

        try stdout.writeAll("Please answer yes, no, or review.\n");
    }
}

fn shouldUseColor() bool {
    return std.io.getStdOut().isTty() and !std.process.hasEnvVarConstant("NO_COLOR");
}

fn printHeading(stdout: anytype, use_color: bool, heading: []const u8) !void {
    if (use_color) {
        try stdout.print("\n{s}{s}{s}\n", .{ ansi_bold, heading, ansi_reset });
    } else {
        try stdout.print("\n{s}\n", .{heading});
    }
}

fn printStatus(stdout: anytype, use_color: bool, level: enum { ok, warn }, message: []const u8) !void {
    if (!use_color) {
        const plain_label: []const u8 = switch (level) {
            .ok => "OK:",
            .warn => "WARN:",
        };
        try stdout.print("{s} {s}\n", .{ plain_label, message });
        return;
    }

    const color = switch (level) {
        .ok => ansi_green,
        .warn => ansi_yellow,
    };
    const label: []const u8 = switch (level) {
        .ok => "OK:",
        .warn => "WARN:",
    };
    try stdout.print("{s}{s}{s} {s}\n", .{ color, label, ansi_reset, message });
}

fn revertChange(cfg: *init_planner.EditableConfig, change: init_planner.Change) !void {
    switch (change.kind) {
        .add => _ = cfg.remove(change.section, change.value),
        .remove => _ = try cfg.add(change.section, change.value),
    }
}

fn printChangesSummary(
    stdout: anytype,
    use_color: bool,
    heading: []const u8,
    config_path: []const u8,
    config_exists: bool,
    changes: []const init_planner.Change,
) !void {
    try printHeading(stdout, use_color, heading);
    if (!config_exists) {
        if (use_color) {
            try stdout.print("  {s}+{s} create {s}\n", .{ ansi_green, ansi_reset, config_path });
        } else {
            try stdout.print("  + create {s}\n", .{config_path});
        }
    }
    for (changes) |change| {
        const marker: []const u8 = switch (change.kind) {
            .add => "+",
            .remove => "-",
        };
        if (use_color) {
            const marker_color = switch (change.kind) {
                .add => ansi_green,
                .remove => ansi_red,
            };
            try stdout.print("  {s}{s}{s} {s}: {s}\n", .{ marker_color, marker, ansi_reset, init_planner.sectionName(change.section), change.value });
        } else {
            try stdout.print("  {s} {s}: {s}\n", .{ marker, init_planner.sectionName(change.section), change.value });
        }
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
    const use_color = shouldUseColor();

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

    try stdout.print("Repository: {s}\n", .{repo_root});

    const recommendations = try init_planner.discoverRecommendations(allocator, repo_root);
    defer init_planner.freeRecommendations(allocator, recommendations);

    for (recommendations) |rec| {
        if (!editable.contains(rec.section, rec.value)) {
            _ = try editable.add(rec.section, rec.value);
        }
    }

    const findings = try init_planner.detectAntiPatterns(allocator, &editable);
    defer init_planner.freeAntiPatterns(allocator, findings);

    var warned_anti_patterns: usize = 0;
    for (findings) |finding| {
        if (editable.contains(finding.section, finding.value)) {
            if (warned_anti_patterns == 0) {
                try printStatus(stdout, use_color, .warn, "Detected anti-patterns; proposing removals:");
            }
            warned_anti_patterns += 1;
            try stdout.print("  - {s}: {s} ({s})\n", .{ init_planner.sectionName(finding.section), finding.value, finding.message });
            _ = editable.remove(finding.section, finding.value);
        }
    }

    var changes = try init_planner.diffConfigs(allocator, &baseline, &editable);
    defer init_planner.freeChanges(allocator, changes);

    const needs_write = !config_exists or changes.len > 0;
    if (!needs_write) {
        try printStatus(stdout, use_color, .ok, "Everything is already ready. No changes needed.");
        return;
    }

    try printChangesSummary(stdout, use_color, "Proposed changes:", config_path, config_exists, changes);

    const decision = try promptApplyDecision(stdout, std.io.getStdIn().reader());
    switch (decision) {
        .cancel => {
            try stdout.writeAll("Aborted without writing changes.\n");
            return;
        },
        .apply_all => {},
        .review => {
            try stdout.writeAll("Review mode: Enter keeps, n skips.\n");
            for (changes) |change| {
                const marker: []const u8 = switch (change.kind) {
                    .add => "+",
                    .remove => "-",
                };
                {
                    const question = try std.fmt.allocPrint(
                        allocator,
                        "Apply {s} {s}: {s}",
                        .{ marker, init_planner.sectionName(change.section), change.value },
                    );
                    defer allocator.free(question);

                    const keep = try promptYesNo(stdout, std.io.getStdIn().reader(), question, true);
                    if (!keep) {
                        try revertChange(&editable, change);
                    }
                }
            }

            init_planner.freeChanges(allocator, changes);
            changes = try init_planner.diffConfigs(allocator, &baseline, &editable);

            if (config_exists and changes.len == 0) {
                try stdout.writeAll("No changes selected.\n");
                return;
            }

            try printChangesSummary(stdout, use_color, "Selected changes:", config_path, config_exists, changes);
        },
    }

    const final_needs_write = !config_exists or changes.len > 0;
    if (!final_needs_write) {
        try stdout.writeAll("No changes selected.\n");
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
    try printStatus(stdout, use_color, .ok, "Updated .wt.toml.");
}

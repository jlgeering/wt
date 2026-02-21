const std = @import("std");
const builtin = @import("builtin");
const git = @import("../lib/git.zig");
const config = @import("../lib/config.zig");
const init_planner = @import("../lib/init_planner.zig");

const ApplyDecision = enum {
    apply_all,
    decline,
};

const DeclineDecision = enum {
    review,
    quit,
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

fn isNegativeResponse(input: []const u8) bool {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    return std.ascii.eqlIgnoreCase(trimmed, "n") or std.ascii.eqlIgnoreCase(trimmed, "no");
}

// Keep one blank line between interactive "screens" so transitions are easier to scan.
fn printScreenBreak(stdout: anytype) !void {
    try stdout.writeAll("\n");
}

fn tryReadSingleKey(stdin_file: std.fs.File) !?u8 {
    if (builtin.os.tag == .windows) return null;
    if (!stdin_file.isTty()) return null;

    const original_termios = std.posix.tcgetattr(stdin_file.handle) catch return null;
    var raw_termios = original_termios;
    raw_termios.lflag.ICANON = false;
    raw_termios.lflag.ECHO = false;
    raw_termios.cc[@intFromEnum(std.c.V.MIN)] = 1;
    raw_termios.cc[@intFromEnum(std.c.V.TIME)] = 0;
    std.posix.tcsetattr(stdin_file.handle, .NOW, raw_termios) catch return null;
    defer std.posix.tcsetattr(stdin_file.handle, .NOW, original_termios) catch {};

    var buf: [1]u8 = undefined;
    const read_len = std.posix.read(stdin_file.handle, &buf) catch return null;
    if (read_len == 0) return null;
    return buf[0];
}

fn promptYesNo(
    stdout: anytype,
    stdin_file: std.fs.File,
    question: []const u8,
    default_yes: bool,
) !bool {
    const suffix: []const u8 = if (default_yes) " [Y/n]: " else " [y/N]: ";

    while (true) {
        try stdout.print("{s}{s}", .{ question, suffix });

        if (try tryReadSingleKey(stdin_file)) |key_raw| {
            const key = std.ascii.toLower(key_raw);
            if (key == '\r' or key == '\n') {
                try stdout.writeAll("\n");
                return default_yes;
            }
            if (key == 'y') {
                try stdout.writeAll("y\n");
                return true;
            }
            if (key == 'n') {
                try stdout.writeAll("n\n");
                return false;
            }
            try stdout.print("{c}\n", .{key_raw});
            try stdout.writeAll("Please answer y or n.\n");
            continue;
        }

        var buf: [256]u8 = undefined;
        const response = try stdin_file.reader().readUntilDelimiterOrEof(&buf, '\n');
        if (response == null) return default_yes;

        const trimmed = std.mem.trim(u8, response.?, " \t\r\n");
        if (trimmed.len == 0) return default_yes;
        if (isConfirmedResponse(trimmed)) return true;
        if (isNegativeResponse(trimmed)) return false;

        try stdout.writeAll("Please answer yes or no.\n");
    }
}

fn promptApplyDecision(stdout: anytype, stdin_file: std.fs.File) !ApplyDecision {
    while (true) {
        try stdout.writeAll("Apply changes? [Y/n]: ");

        if (try tryReadSingleKey(stdin_file)) |key_raw| {
            const key = std.ascii.toLower(key_raw);
            if (key == '\r' or key == '\n') {
                try stdout.writeAll("\n");
                return .apply_all;
            }
            if (key == 'y') {
                try stdout.writeAll("y\n");
                return .apply_all;
            }
            if (key == 'n') {
                try stdout.writeAll("n\n");
                return .decline;
            }
            try stdout.print("{c}\n", .{key_raw});
            try stdout.writeAll("Please answer y or n.\n");
            continue;
        }

        var buf: [256]u8 = undefined;
        const response = try stdin_file.reader().readUntilDelimiterOrEof(&buf, '\n');
        if (response == null) return .apply_all;

        const trimmed = std.mem.trim(u8, response.?, " \t\r\n");
        if (trimmed.len == 0) return .apply_all;
        if (isConfirmedResponse(trimmed)) return .apply_all;
        if (isNegativeResponse(trimmed)) return .decline;

        try stdout.writeAll("Please answer yes or no.\n");
    }
}

fn promptDeclineDecision(stdout: anytype, stdin_file: std.fs.File) !DeclineDecision {
    while (true) {
        try printScreenBreak(stdout);
        try stdout.writeAll("Choose next step:\n");
        try stdout.writeAll("  [e] Edit proposed changes one by one\n");
        try stdout.writeAll("  [q] Quit without writing\n");
        try stdout.writeAll("Choice [e/q]: ");

        if (try tryReadSingleKey(stdin_file)) |key_raw| {
            const key = std.ascii.toLower(key_raw);
            if (key == '\r' or key == '\n') {
                try stdout.writeAll("\n");
                return .review;
            }
            if (key == 'e' or key == 'r') {
                try stdout.writeAll("e\n");
                return .review;
            }
            if (key == 'q' or key == 'n') {
                try stdout.writeAll("q\n");
                return .quit;
            }
            try stdout.print("{c}\n", .{key_raw});
            try stdout.writeAll("Please answer e or q.\n");
            continue;
        }

        var buf: [256]u8 = undefined;
        const response = try stdin_file.reader().readUntilDelimiterOrEof(&buf, '\n');
        if (response == null) return .review;

        const trimmed = std.mem.trim(u8, response.?, " \t\r\n");
        if (trimmed.len == 0) return .review;
        if (std.ascii.eqlIgnoreCase(trimmed, "e") or std.ascii.eqlIgnoreCase(trimmed, "edit") or std.ascii.eqlIgnoreCase(trimmed, "r") or std.ascii.eqlIgnoreCase(trimmed, "review")) return .review;
        if (std.ascii.eqlIgnoreCase(trimmed, "q") or std.ascii.eqlIgnoreCase(trimmed, "quit") or std.ascii.eqlIgnoreCase(trimmed, "n") or std.ascii.eqlIgnoreCase(trimmed, "no")) return .quit;

        try stdout.writeAll("Please answer edit or quit.\n");
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
    const stdin_file = std.io.getStdIn();
    const stdout = std.io.getStdOut().writer();
    const use_color = shouldUseColor();

    if (!stdin_file.isTty()) {
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

    const decision = try promptApplyDecision(stdout, stdin_file);
    switch (decision) {
        .apply_all => {},
        .decline => {
            const decline = try promptDeclineDecision(stdout, stdin_file);
            switch (decline) {
                .quit => {
                    try printScreenBreak(stdout);
                    try stdout.writeAll("No changes written.\n");
                    return;
                },
                .review => {},
            }

            try printScreenBreak(stdout);
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

                    const keep = try promptYesNo(stdout, stdin_file, question, true);
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

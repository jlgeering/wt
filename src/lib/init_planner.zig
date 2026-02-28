const std = @import("std");
const config_mod = @import("config.zig");
const init_rules = @import("init_rules.zig");

pub const Section = init_rules.Section;

pub const Recommendation = struct {
    rule_id: []const u8,
    section: Section,
    value: []u8,
    prompt: []const u8,
    reason: []const u8,
};

pub const DiscoveryOptions = struct {
    // For tests and deterministic callers. Null means detect from `mise trust --show`.
    assume_repo_mise_trusted: ?bool = null,
    // Repo-relative invocation directory (empty means repo root).
    invocation_subdir: []const u8 = "",
};

const ScopePrefixes = struct {
    values: [2][]const u8 = .{ "", "" },
    len: usize = 0,

    fn append(self: *ScopePrefixes, prefix: []const u8) void {
        if (self.len == self.values.len) return;
        self.values[self.len] = prefix;
        self.len += 1;
    }

    fn slice(self: *const ScopePrefixes) []const []const u8 {
        return self.values[0..self.len];
    }
};

const DetectionContext = struct {
    repo_root: []const u8,
    invocation_subdir: []const u8,
    root_entries: []([]u8),
    subdir_entries: ?[]([]u8),

    fn init(
        allocator: std.mem.Allocator,
        repo_root: []const u8,
        invocation_subdir: []const u8,
    ) !DetectionContext {
        const root_entries = try readEntriesAtRelPath(allocator, repo_root, "");
        errdefer freeStringSlice(allocator, root_entries);

        var subdir_entries: ?[]([]u8) = null;
        if (invocation_subdir.len > 0) {
            subdir_entries = readEntriesAtRelPath(allocator, repo_root, invocation_subdir) catch |err| switch (err) {
                error.FileNotFound, error.NotDir => try allocator.alloc([]u8, 0),
                else => return err,
            };
        }
        errdefer if (subdir_entries) |entries| freeStringSlice(allocator, entries);

        return .{
            .repo_root = repo_root,
            .invocation_subdir = invocation_subdir,
            .root_entries = root_entries,
            .subdir_entries = subdir_entries,
        };
    }

    fn deinit(self: *DetectionContext, allocator: std.mem.Allocator) void {
        freeStringSlice(allocator, self.root_entries);
        if (self.subdir_entries) |entries| {
            freeStringSlice(allocator, entries);
        }
    }

    fn prefixesForScope(self: *const DetectionContext, scope: init_rules.DetectionScope) ScopePrefixes {
        var prefixes = ScopePrefixes{};
        switch (scope) {
            .repo_root => prefixes.append(""),
            .invocation_subdir => {
                if (self.invocation_subdir.len > 0) {
                    prefixes.append(self.invocation_subdir);
                } else {
                    prefixes.append("");
                }
            },
            .repo_root_and_invocation_subdir => {
                prefixes.append("");
                if (self.invocation_subdir.len > 0) {
                    prefixes.append(self.invocation_subdir);
                }
            },
        }
        return prefixes;
    }

    fn entriesForPrefix(self: *const DetectionContext, prefix: []const u8) []([]u8) {
        if (prefix.len == 0) return self.root_entries;
        if (self.subdir_entries != null and std.mem.eql(u8, prefix, self.invocation_subdir)) {
            return self.subdir_entries.?;
        }
        return &.{};
    }
};

pub const AntiPattern = struct {
    section: Section,
    value: []u8,
    message: []const u8,
};

pub const ChangeKind = enum {
    add,
    remove,
};

pub const Change = struct {
    kind: ChangeKind,
    section: Section,
    value: []u8,
};

pub const EditableConfig = struct {
    allocator: std.mem.Allocator,
    copy_paths: std.array_list.Managed([]u8),
    symlink_paths: std.array_list.Managed([]u8),
    run_commands: std.array_list.Managed([]u8),

    pub fn init(allocator: std.mem.Allocator) EditableConfig {
        return .{
            .allocator = allocator,
            .copy_paths = std.array_list.Managed([]u8).init(allocator),
            .symlink_paths = std.array_list.Managed([]u8).init(allocator),
            .run_commands = std.array_list.Managed([]u8).init(allocator),
        };
    }

    pub fn fromConfig(allocator: std.mem.Allocator, cfg: config_mod.Config) !EditableConfig {
        var editable = EditableConfig.init(allocator);
        errdefer editable.deinit();

        for (cfg.copyPaths()) |value| {
            _ = try editable.add(.copy, value);
        }
        for (cfg.symlinkPaths()) |value| {
            _ = try editable.add(.symlink, value);
        }
        for (cfg.runCommands()) |value| {
            _ = try editable.add(.run, value);
        }

        return editable;
    }

    pub fn clone(self: *const EditableConfig, allocator: std.mem.Allocator) !EditableConfig {
        var copy = EditableConfig.init(allocator);
        errdefer copy.deinit();

        for (self.copy_paths.items) |value| {
            _ = try copy.add(.copy, value);
        }
        for (self.symlink_paths.items) |value| {
            _ = try copy.add(.symlink, value);
        }
        for (self.run_commands.items) |value| {
            _ = try copy.add(.run, value);
        }

        return copy;
    }

    pub fn deinit(self: *EditableConfig) void {
        freeList(self.allocator, &self.copy_paths);
        freeList(self.allocator, &self.symlink_paths);
        freeList(self.allocator, &self.run_commands);
    }

    pub fn contains(self: *const EditableConfig, section: Section, value: []const u8) bool {
        const section_items = self.listConst(section);
        for (section_items.items) |existing| {
            if (std.mem.eql(u8, existing, value)) return true;
        }
        return false;
    }

    pub fn add(self: *EditableConfig, section: Section, value: []const u8) !bool {
        var section_items = self.list(section);
        for (section_items.items) |existing| {
            if (std.mem.eql(u8, existing, value)) return false;
        }

        const duped = try self.allocator.dupe(u8, value);
        try section_items.append(duped);
        return true;
    }

    pub fn remove(self: *EditableConfig, section: Section, value: []const u8) bool {
        var section_items = self.list(section);
        var i: usize = 0;
        while (i < section_items.items.len) : (i += 1) {
            if (std.mem.eql(u8, section_items.items[i], value)) {
                self.allocator.free(section_items.items[i]);
                _ = section_items.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn renderToml(self: *const EditableConfig, allocator: std.mem.Allocator) ![]u8 {
        const copy_sorted = try cloneSortedStrings(allocator, self.copy_paths.items);
        defer freeStringSlice(allocator, copy_sorted);

        const symlink_sorted = try cloneSortedStrings(allocator, self.symlink_paths.items);
        defer freeStringSlice(allocator, symlink_sorted);

        const run_sorted = try cloneSortedStrings(allocator, self.run_commands.items);
        defer freeStringSlice(allocator, run_sorted);

        var out = std.array_list.Managed(u8).init(allocator);
        errdefer out.deinit();

        const writer = out.writer();
        try writer.writeAll("# Generated by `wt init`\n");
        try writer.writeAll("# Edit this file to customize new-worktree setup.\n\n");

        try writer.writeAll("[copy]\n");
        try writeStringArray(writer, "paths", copy_sorted);
        try writer.writeAll("\n");

        try writer.writeAll("[symlink]\n");
        try writeStringArray(writer, "paths", symlink_sorted);
        try writer.writeAll("\n");

        try writer.writeAll("[run]\n");
        try writeStringArray(writer, "commands", run_sorted);

        return out.toOwnedSlice();
    }

    fn list(self: *EditableConfig, section: Section) *std.array_list.Managed([]u8) {
        return switch (section) {
            .copy => &self.copy_paths,
            .symlink => &self.symlink_paths,
            .run => &self.run_commands,
        };
    }

    fn listConst(self: *const EditableConfig, section: Section) *const std.array_list.Managed([]u8) {
        return switch (section) {
            .copy => &self.copy_paths,
            .symlink => &self.symlink_paths,
            .run => &self.run_commands,
        };
    }
};

pub fn discoverRecommendations(allocator: std.mem.Allocator, repo_root: []const u8) ![]Recommendation {
    return discoverRecommendationsWithOptions(allocator, repo_root, .{});
}

pub fn discoverRecommendationsWithOptions(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    options: DiscoveryOptions,
) ![]Recommendation {
    var recs = std.array_list.Managed(Recommendation).init(allocator);
    errdefer {
        for (recs.items) |rec| allocator.free(rec.value);
    }
    defer recs.deinit();

    const invocation_subdir = normalizeInvocationSubdir(options.invocation_subdir);
    var context = try DetectionContext.init(allocator, repo_root, invocation_subdir);
    defer context.deinit(allocator);

    var triggered_rule_ids = std.StringHashMap(void).init(allocator);
    defer triggered_rule_ids.deinit();

    for (init_rules.path_rules) |rule| {
        const matched = try discoverForPathRule(allocator, &context, rule, &recs);
        if (matched) {
            try triggered_rule_ids.put(rule.id, {});
        }
    }

    for (init_rules.command_rules) |rule| {
        const triggered_by_rules = isCommandRuleTriggeredByRules(&triggered_rule_ids, rule);
        const triggered_by_patterns = try isCommandRuleTriggeredByPatterns(allocator, &context, rule);
        if (!triggered_by_rules and !triggered_by_patterns) continue;

        if (rule.requires_repo_mise_trust) {
            if (!try isMiseTrustedForScope(allocator, &context, rule.detection_scope, options.assume_repo_mise_trusted)) continue;
        }

        _ = try addRecommendationIfMissing(allocator, &recs, .{
            .rule_id = rule.id,
            .section = rule.section,
            .value = rule.command,
            .prompt = rule.prompt,
            .reason = rule.reason,
        });
    }

    return recs.toOwnedSlice();
}

fn normalizeInvocationSubdir(raw_subdir: []const u8) []const u8 {
    const whitespace_trimmed = std.mem.trim(u8, raw_subdir, " \t\r\n");
    return std.mem.trim(u8, whitespace_trimmed, "/\\");
}

fn isCommandRuleTriggeredByRules(
    triggered_rule_ids: *const std.StringHashMap(void),
    rule: init_rules.CommandRule,
) bool {
    for (rule.trigger_rule_ids) |id| {
        if (triggered_rule_ids.contains(id)) return true;
    }
    return false;
}

fn isCommandRuleTriggeredByPatterns(
    allocator: std.mem.Allocator,
    context: *const DetectionContext,
    rule: init_rules.CommandRule,
) !bool {
    const prefixes = context.prefixesForScope(rule.detection_scope);
    for (prefixes.slice()) |prefix| {
        for (rule.trigger_patterns) |pattern| {
            switch (pattern.kind) {
                .exact => {
                    const rel_path = try joinRelPath(allocator, prefix, pattern.value);
                    defer allocator.free(rel_path);
                    if (pathExists(allocator, context.repo_root, rel_path)) return true;
                },
                .prefix, .glob => {
                    if (std.mem.indexOfScalar(u8, pattern.value, '/')) |_| {
                        // Prefix/glob matching is intentionally limited to one directory level.
                        continue;
                    }
                    const entries = context.entriesForPrefix(prefix);
                    for (entries) |entry_name| {
                        if (init_rules.matchesPattern(pattern, entry_name)) return true;
                    }
                },
            }
        }
    }
    return false;
}

fn isMiseTrustedForScope(
    allocator: std.mem.Allocator,
    context: *const DetectionContext,
    scope: init_rules.DetectionScope,
    assume_repo_mise_trusted: ?bool,
) !bool {
    if (assume_repo_mise_trusted) |trusted| return trusted;

    const prefixes = context.prefixesForScope(scope);
    for (prefixes.slice()) |prefix| {
        const cwd = try resolveScopeCwd(allocator, context.repo_root, prefix);
        defer allocator.free(cwd);
        if (detectMiseTrustInDir(allocator, cwd) catch false) return true;
    }

    return false;
}

fn resolveScopeCwd(allocator: std.mem.Allocator, repo_root: []const u8, prefix: []const u8) ![]u8 {
    if (prefix.len == 0) return allocator.dupe(u8, repo_root);
    return std.fs.path.join(allocator, &.{ repo_root, prefix });
}

fn detectMiseTrustInDir(allocator: std.mem.Allocator, cwd: []const u8) !bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "mise", "trust", "--show" },
        .cwd = cwd,
    }) catch {
        return error.MiseNotFound;
    };
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) return error.MiseCommandFailed;
        },
        else => return error.MiseCommandFailed,
    }

    return parseMiseTrustShowOutput(result.stdout) orelse false;
}

fn parseMiseTrustShowOutput(output: []const u8) ?bool {
    var lines = std.mem.splitScalar(u8, output, '\n');
    var last_non_empty: ?[]const u8 = null;
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \t\r\n").len > 0) {
            last_non_empty = line;
        }
    }

    const line = last_non_empty orelse return null;
    const separator_index = std.mem.lastIndexOf(u8, line, ":") orelse return null;
    const status = std.mem.trim(u8, line[separator_index + 1 ..], " \t\r\n");

    if (std.ascii.eqlIgnoreCase(status, "trusted")) return true;
    if (std.ascii.eqlIgnoreCase(status, "untrusted")) return false;
    if (std.ascii.eqlIgnoreCase(status, "ignored")) return false;
    return null;
}

pub fn detectAntiPatterns(allocator: std.mem.Allocator, cfg: *const EditableConfig) ![]AntiPattern {
    var findings = std.array_list.Managed(AntiPattern).init(allocator);
    errdefer {
        for (findings.items) |finding| allocator.free(finding.value);
    }
    defer findings.deinit();

    for (cfg.copy_paths.items) |copy_path| {
        if (cfg.contains(.symlink, copy_path)) {
            _ = try addAntiPatternIfMissing(allocator, &findings, .{
                .section = .copy,
                .value = copy_path,
                .message = "Path appears in both copy.paths and symlink.paths. Prefer one strategy.",
            });
        }
    }

    for (init_rules.path_anti_patterns) |rule| {
        const list = switch (rule.section) {
            .copy => cfg.copy_paths.items,
            .symlink => cfg.symlink_paths.items,
            .run => cfg.run_commands.items,
        };
        for (list) |value| {
            if (init_rules.matchesPattern(rule.pattern, value)) {
                _ = try addAntiPatternIfMissing(allocator, &findings, .{
                    .section = rule.section,
                    .value = value,
                    .message = rule.message,
                });
            }
        }
    }

    for (cfg.run_commands.items) |command| {
        for (init_rules.run_anti_patterns) |rule| {
            if (std.mem.indexOf(u8, command, rule.token) != null) {
                _ = try addAntiPatternIfMissing(allocator, &findings, .{
                    .section = .run,
                    .value = command,
                    .message = rule.message,
                });
            }
        }
    }

    return findings.toOwnedSlice();
}

pub fn diffConfigs(allocator: std.mem.Allocator, before: *const EditableConfig, after: *const EditableConfig) ![]Change {
    var changes = std.array_list.Managed(Change).init(allocator);
    errdefer {
        for (changes.items) |change| allocator.free(change.value);
    }
    defer changes.deinit();

    const sections = [_]Section{ .copy, .symlink, .run };

    for (sections) |section| {
        const after_list = after.listConst(section).items;
        for (after_list) |value| {
            if (!before.contains(section, value)) {
                try changes.append(.{
                    .kind = .add,
                    .section = section,
                    .value = try allocator.dupe(u8, value),
                });
            }
        }

        const before_list = before.listConst(section).items;
        for (before_list) |value| {
            if (!after.contains(section, value)) {
                try changes.append(.{
                    .kind = .remove,
                    .section = section,
                    .value = try allocator.dupe(u8, value),
                });
            }
        }
    }

    return changes.toOwnedSlice();
}

pub fn freeRecommendations(allocator: std.mem.Allocator, recs: []Recommendation) void {
    for (recs) |rec| allocator.free(rec.value);
    allocator.free(recs);
}

pub fn freeAntiPatterns(allocator: std.mem.Allocator, findings: []AntiPattern) void {
    for (findings) |finding| allocator.free(finding.value);
    allocator.free(findings);
}

pub fn freeChanges(allocator: std.mem.Allocator, changes: []Change) void {
    for (changes) |change| allocator.free(change.value);
    allocator.free(changes);
}

pub fn sectionName(section: Section) []const u8 {
    return switch (section) {
        .copy => "copy.paths",
        .symlink => "symlink.paths",
        .run => "run.commands",
    };
}

fn freeList(allocator: std.mem.Allocator, list: *std.array_list.Managed([]u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit();
}

fn readEntriesAtRelPath(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    rel_path: []const u8,
) ![]([]u8) {
    var entries = std.array_list.Managed([]u8).init(allocator);
    errdefer freeStringItems(allocator, entries.items);
    defer entries.deinit();

    const dir_path = if (rel_path.len == 0)
        try allocator.dupe(u8, repo_root)
    else
        try std.fs.path.join(allocator, &.{ repo_root, rel_path });
    defer allocator.free(dir_path);

    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        switch (entry.kind) {
            .file, .sym_link => try entries.append(try allocator.dupe(u8, entry.name)),
            else => {},
        }
    }

    return entries.toOwnedSlice();
}

fn discoverForPathRule(
    allocator: std.mem.Allocator,
    context: *const DetectionContext,
    rule: init_rules.PathRule,
    recs: *std.array_list.Managed(Recommendation),
) !bool {
    var matched = false;
    const prefixes = context.prefixesForScope(rule.detection_scope);

    for (prefixes.slice()) |prefix| {
        for (rule.patterns) |pattern| {
            switch (pattern.kind) {
                .exact => {
                    const rel_path = try joinRelPath(allocator, prefix, pattern.value);
                    defer allocator.free(rel_path);
                    if (pathExists(allocator, context.repo_root, rel_path)) {
                        matched = true;
                        _ = try addRecommendationIfMissing(allocator, recs, .{
                            .rule_id = rule.id,
                            .section = rule.section,
                            .value = rel_path,
                            .prompt = rule.prompt,
                            .reason = rule.reason,
                        });
                    }
                },
                .prefix, .glob => {
                    if (std.mem.indexOfScalar(u8, pattern.value, '/')) |_| {
                        // Prefix/glob matching is intentionally limited to one directory level.
                        continue;
                    }

                    const entries = context.entriesForPrefix(prefix);
                    for (entries) |entry_name| {
                        if (!init_rules.matchesPattern(pattern, entry_name)) continue;
                        matched = true;
                        const rel_path = try joinRelPath(allocator, prefix, entry_name);
                        defer allocator.free(rel_path);
                        _ = try addRecommendationIfMissing(allocator, recs, .{
                            .rule_id = rule.id,
                            .section = rule.section,
                            .value = rel_path,
                            .prompt = rule.prompt,
                            .reason = rule.reason,
                        });
                    }
                },
            }
        }
    }

    return matched;
}

fn joinRelPath(allocator: std.mem.Allocator, prefix: []const u8, leaf: []const u8) ![]u8 {
    if (prefix.len == 0) return allocator.dupe(u8, leaf);
    return std.fs.path.join(allocator, &.{ prefix, leaf });
}

fn pathExists(allocator: std.mem.Allocator, root: []const u8, rel_path: []const u8) bool {
    const path = std.fs.path.join(allocator, &.{ root, rel_path }) catch return false;
    defer allocator.free(path);

    if (std.fs.cwd().access(path, .{})) |_| {
        return true;
    } else |_| {
        return false;
    }
}

fn addRecommendationIfMissing(
    allocator: std.mem.Allocator,
    recs: *std.array_list.Managed(Recommendation),
    candidate: struct {
        rule_id: []const u8,
        section: Section,
        value: []const u8,
        prompt: []const u8,
        reason: []const u8,
    },
) !bool {
    for (recs.items) |existing| {
        if (existing.section == candidate.section and std.mem.eql(u8, existing.value, candidate.value)) {
            return false;
        }
    }

    try recs.append(.{
        .rule_id = candidate.rule_id,
        .section = candidate.section,
        .value = try allocator.dupe(u8, candidate.value),
        .prompt = candidate.prompt,
        .reason = candidate.reason,
    });
    return true;
}

fn addAntiPatternIfMissing(
    allocator: std.mem.Allocator,
    findings: *std.array_list.Managed(AntiPattern),
    candidate: AntiPattern,
) !bool {
    for (findings.items) |existing| {
        if (existing.section == candidate.section and
            std.mem.eql(u8, existing.value, candidate.value) and
            std.mem.eql(u8, existing.message, candidate.message))
        {
            return false;
        }
    }

    try findings.append(.{
        .section = candidate.section,
        .value = try allocator.dupe(u8, candidate.value),
        .message = candidate.message,
    });
    return true;
}

fn writeStringArray(writer: anytype, key: []const u8, items: []const []u8) !void {
    if (items.len == 0) {
        try writer.print("{s} = []\n", .{key});
        return;
    }

    try writer.print("{s} = [\n", .{key});
    for (items) |item| {
        try writer.writeAll("  ");
        try writeTomlString(writer, item);
        try writer.writeAll(",\n");
    }
    try writer.writeAll("]\n");
}

fn writeTomlString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

fn cloneSortedStrings(allocator: std.mem.Allocator, items: []const []u8) ![]([]u8) {
    var cloned = std.array_list.Managed([]u8).init(allocator);
    errdefer freeStringItems(allocator, cloned.items);
    defer cloned.deinit();

    for (items) |item| {
        try cloned.append(try allocator.dupe(u8, item));
    }

    insertionSortStrings(cloned.items);
    return cloned.toOwnedSlice();
}

fn insertionSortStrings(items: []([]u8)) void {
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        const current = items[i];
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, current, items[j - 1])) : (j -= 1) {
            items[j] = items[j - 1];
        }
        items[j] = current;
    }
}

fn freeStringSlice(allocator: std.mem.Allocator, items: []([]u8)) void {
    for (items) |item| allocator.free(item);
    allocator.free(items);
}

fn freeStringItems(allocator: std.mem.Allocator, items: []([]u8)) void {
    for (items) |item| allocator.free(item);
}

test "EditableConfig add remove and render" {
    var cfg = EditableConfig.init(std.testing.allocator);
    defer cfg.deinit();

    try std.testing.expect(try cfg.add(.copy, ".env.local"));
    try std.testing.expect(!try cfg.add(.copy, ".env.local"));
    try std.testing.expect(cfg.contains(.copy, ".env.local"));

    try std.testing.expect(try cfg.add(.run, "mise trust"));
    try std.testing.expect(cfg.remove(.run, "mise trust"));
    try std.testing.expect(!cfg.contains(.run, "mise trust"));

    const toml = try cfg.renderToml(std.testing.allocator);
    defer std.testing.allocator.free(toml);

    try std.testing.expect(std.mem.indexOf(u8, toml, "[copy]") != null);
    try std.testing.expect(std.mem.indexOf(u8, toml, ".env.local") != null);
    try std.testing.expect(std.mem.indexOf(u8, toml, "[run]") != null);
}

test "detectAntiPatterns flags copy-symlink conflicts and risky commands" {
    var cfg = EditableConfig.init(std.testing.allocator);
    defer cfg.deinit();

    _ = try cfg.add(.copy, "mise.local.toml");
    _ = try cfg.add(.symlink, "mise.local.toml");
    _ = try cfg.add(.run, "rm -rf build");

    const findings = try detectAntiPatterns(std.testing.allocator, &cfg);
    defer freeAntiPatterns(std.testing.allocator, findings);

    try std.testing.expect(findings.len >= 2);
}

test "diffConfigs reports added and removed values" {
    var before = EditableConfig.init(std.testing.allocator);
    defer before.deinit();
    _ = try before.add(.copy, "a");

    var after = EditableConfig.init(std.testing.allocator);
    defer after.deinit();
    _ = try after.add(.copy, "b");

    const changes = try diffConfigs(std.testing.allocator, &before, &after);
    defer freeChanges(std.testing.allocator, changes);

    try std.testing.expectEqual(@as(usize, 2), changes.len);
}

test "discoverRecommendations finds file and command suggestions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.makePath(".claude");
    try tmp.dir.writeFile(.{ .sub_path = ".claude/settings.local.json", .data = "{ }\n" });

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    var saw_symlink_mise = false;
    var saw_symlink_claude = false;
    var saw_mise_trust = false;

    for (recs) |rec| {
        if (rec.section == .symlink and std.mem.eql(u8, rec.value, "mise.local.toml")) saw_symlink_mise = true;
        if (rec.section == .symlink and std.mem.eql(u8, rec.value, ".claude/settings.local.json")) saw_symlink_claude = true;
        if (rec.section == .run and std.mem.eql(u8, rec.value, "mise trust")) saw_mise_trust = true;
    }

    try std.testing.expect(saw_symlink_mise);
    try std.testing.expect(saw_symlink_claude);
    try std.testing.expect(saw_mise_trust);
}

test "discoverRecommendations includes invocation subdir matches across setup types" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("apps/api/.claude");
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/.claude/settings.local.json", .data = "{ }\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/.envrc", .data = "use flake\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.toml", .data = "[tools]\nzig = \"0.15\"\n" });

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
        .invocation_subdir = "apps/api/",
    });
    defer freeRecommendations(std.testing.allocator, recs);

    var saw_subdir_symlink_mise = false;
    var saw_subdir_symlink_claude = false;
    var saw_subdir_symlink_envrc = false;
    var saw_mise_trust = false;
    var saw_direnv_allow = false;

    for (recs) |rec| {
        if (rec.section == .symlink and std.mem.eql(u8, rec.value, "apps/api/mise.local.toml")) saw_subdir_symlink_mise = true;
        if (rec.section == .symlink and std.mem.eql(u8, rec.value, "apps/api/.claude/settings.local.json")) saw_subdir_symlink_claude = true;
        if (rec.section == .symlink and std.mem.eql(u8, rec.value, "apps/api/.envrc")) saw_subdir_symlink_envrc = true;
        if (rec.section == .run and std.mem.eql(u8, rec.value, "mise trust")) saw_mise_trust = true;
        if (rec.section == .run and std.mem.eql(u8, rec.value, "direnv allow")) saw_direnv_allow = true;
    }

    try std.testing.expect(saw_subdir_symlink_mise);
    try std.testing.expect(saw_subdir_symlink_claude);
    try std.testing.expect(saw_subdir_symlink_envrc);
    try std.testing.expect(saw_mise_trust);
    try std.testing.expect(saw_direnv_allow);
}

test "discoverRecommendations ignores nested matches without invocation subdir context" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("apps/api/.claude");
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/.claude/settings.local.json", .data = "{ }\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/.envrc", .data = "use flake\n" });

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    for (recs) |rec| {
        try std.testing.expect(!std.mem.eql(u8, rec.value, "apps/api/mise.local.toml"));
        try std.testing.expect(!std.mem.eql(u8, rec.value, "apps/api/.claude/settings.local.json"));
        try std.testing.expect(!std.mem.eql(u8, rec.value, "apps/api/.envrc"));
    }
}

test "discoverRecommendations omits mise trust when repo is not trusted" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "mise.toml", .data = "[tools]\nzig = \"0.15\"\n" });

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = false,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    for (recs) |rec| {
        try std.testing.expect(!(rec.section == .run and std.mem.eql(u8, rec.value, "mise trust")));
    }
}

test "discoverRecommendations includes mise trust when mise.toml exists and repo is trusted" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "mise.toml", .data = "[tools]\nzig = \"0.15\"\n" });

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    var saw_mise_trust = false;
    for (recs) |rec| {
        if (rec.section == .run and std.mem.eql(u8, rec.value, "mise trust")) {
            saw_mise_trust = true;
        }
    }

    try std.testing.expect(saw_mise_trust);
}

test "parseMiseTrustShowOutput parses trusted and untrusted states" {
    try std.testing.expectEqual(@as(?bool, true), parseMiseTrustShowOutput(
        \\~/src: trusted
        \\~/src/wt: trusted
        \\
    ));
    try std.testing.expectEqual(@as(?bool, false), parseMiseTrustShowOutput(
        \\~/src: trusted
        \\~/src/wt: untrusted
        \\
    ));
    try std.testing.expectEqual(@as(?bool, null), parseMiseTrustShowOutput(
        \\no-separator-here
        \\
    ));
}

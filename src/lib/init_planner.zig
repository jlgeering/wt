const std = @import("std");
const config_mod = @import("config.zig");
const git = @import("git.zig");
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
    // Backward-compatible option retained for callers; defaults now ignore cwd.
    invocation_subdir: []const u8 = "",
    max_subproject_scan_depth: usize = default_max_subproject_scan_depth,
};

const default_max_subproject_scan_depth: usize = 2;

const DetectionContext = struct {
    repo_root: []const u8,
    invocation_subdir: []const u8,
    visible_paths: []([]u8),
    visible_path_set: std.StringHashMap(void),
    repo_root_and_subproject_prefixes: []([]u8),
    root_only_prefixes: [1][]const u8 = .{""},
    invocation_only_prefixes: [1][]const u8 = .{""},
    root_and_invocation_prefixes: [2][]const u8 = .{ "", "" },
    root_and_invocation_len: usize = 1,

    fn init(
        allocator: std.mem.Allocator,
        repo_root: []const u8,
        invocation_subdir: []const u8,
        max_subproject_scan_depth: usize,
    ) !DetectionContext {
        const visible_paths = try listVisibleRepoPaths(allocator, repo_root);
        errdefer freeStringSlice(allocator, visible_paths);
        insertionSortStrings(visible_paths);

        var visible_path_set = std.StringHashMap(void).init(allocator);
        errdefer visible_path_set.deinit();
        for (visible_paths) |path| {
            try visible_path_set.put(path, {});
        }

        const repo_root_and_subproject_prefixes = try collectRepoRootAndSubprojectPrefixes(
            allocator,
            visible_paths,
            max_subproject_scan_depth,
        );
        errdefer freeStringSlice(allocator, repo_root_and_subproject_prefixes);

        var context: DetectionContext = .{
            .repo_root = repo_root,
            .invocation_subdir = invocation_subdir,
            .visible_paths = visible_paths,
            .visible_path_set = visible_path_set,
            .repo_root_and_subproject_prefixes = repo_root_and_subproject_prefixes,
        };

        if (invocation_subdir.len > 0) {
            context.invocation_only_prefixes[0] = invocation_subdir;
            context.root_and_invocation_prefixes[1] = invocation_subdir;
            context.root_and_invocation_len = 2;
        }

        return context;
    }

    fn deinit(self: *DetectionContext, allocator: std.mem.Allocator) void {
        self.visible_path_set.deinit();
        freeStringSlice(allocator, self.visible_paths);
        freeStringSlice(allocator, self.repo_root_and_subproject_prefixes);
    }

    fn prefixesForScope(self: *const DetectionContext, scope: init_rules.DetectionScope) []const []const u8 {
        return switch (scope) {
            .repo_root => self.root_only_prefixes[0..],
            .invocation_subdir => if (self.invocation_subdir.len > 0)
                self.invocation_only_prefixes[0..]
            else
                self.root_only_prefixes[0..],
            .repo_root_and_invocation_subdir => self.root_and_invocation_prefixes[0..self.root_and_invocation_len],
            .repo_root_and_subprojects => self.repo_root_and_subproject_prefixes,
        };
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
    var context = try DetectionContext.init(
        allocator,
        repo_root,
        invocation_subdir,
        options.max_subproject_scan_depth,
    );
    defer context.deinit(allocator);

    var trust_cache = std.StringHashMap(bool).init(allocator);
    defer trust_cache.deinit();

    for (init_rules.path_rules) |rule| {
        _ = try discoverForPathRule(allocator, &context, rule, &recs);
    }

    for (init_rules.command_rules) |rule| {
        const matched_prefixes = try collectTriggeredPrefixesForCommandRule(allocator, &context, rule);
        defer allocator.free(matched_prefixes);

        for (matched_prefixes) |prefix| {
            if (rule.requires_repo_mise_trust) {
                if (!try isMiseTrustedForPrefix(
                    allocator,
                    &context,
                    prefix,
                    options.assume_repo_mise_trusted,
                    &trust_cache,
                )) continue;
            }

            const command = try commandForPrefix(allocator, prefix, rule.command);
            defer allocator.free(command);

            _ = try addRecommendationIfMissing(allocator, &recs, .{
                .rule_id = rule.id,
                .section = rule.section,
                .value = command,
                .prompt = rule.prompt,
                .reason = rule.reason,
            });
        }
    }

    return recs.toOwnedSlice();
}

fn normalizeInvocationSubdir(raw_subdir: []const u8) []const u8 {
    const whitespace_trimmed = std.mem.trim(u8, raw_subdir, " \t\r\n");
    return std.mem.trim(u8, whitespace_trimmed, "/\\");
}

fn collectTriggeredPrefixesForCommandRule(
    allocator: std.mem.Allocator,
    context: *const DetectionContext,
    rule: init_rules.CommandRule,
) ![]([]const u8) {
    var matched = std.array_list.Managed([]const u8).init(allocator);
    defer matched.deinit();

    const scope_prefixes = context.prefixesForScope(rule.detection_scope);
    for (scope_prefixes) |prefix| {
        if (!try isCommandRuleTriggeredAtPrefix(allocator, context, rule, prefix)) continue;
        if (containsPrefix(matched.items, prefix)) continue;
        try matched.append(prefix);
    }

    return matched.toOwnedSlice();
}

fn containsPrefix(prefixes: []const []const u8, candidate: []const u8) bool {
    for (prefixes) |prefix| {
        if (std.mem.eql(u8, prefix, candidate)) return true;
    }
    return false;
}

fn isCommandRuleTriggeredAtPrefix(
    allocator: std.mem.Allocator,
    context: *const DetectionContext,
    rule: init_rules.CommandRule,
    prefix: []const u8,
) !bool {
    for (rule.trigger_rule_ids) |id| {
        const path_rule = findPathRuleById(id) orelse continue;
        if (try pathRuleMatchesAtPrefix(allocator, context, path_rule, prefix)) return true;
    }

    for (rule.trigger_patterns) |pattern| {
        if (try patternMatchesAtPrefix(allocator, context, prefix, pattern)) return true;
    }

    return false;
}

fn findPathRuleById(id: []const u8) ?init_rules.PathRule {
    for (init_rules.path_rules) |rule| {
        if (std.mem.eql(u8, rule.id, id)) return rule;
    }
    return null;
}

fn pathRuleMatchesAtPrefix(
    allocator: std.mem.Allocator,
    context: *const DetectionContext,
    rule: init_rules.PathRule,
    prefix: []const u8,
) !bool {
    for (rule.patterns) |pattern| {
        if (try patternMatchesAtPrefix(allocator, context, prefix, pattern)) return true;
    }
    return false;
}

fn patternMatchesAtPrefix(
    allocator: std.mem.Allocator,
    context: *const DetectionContext,
    prefix: []const u8,
    pattern: init_rules.Pattern,
) !bool {
    return switch (pattern.kind) {
        .exact => blk: {
            const rel_path = try joinRelPath(allocator, prefix, pattern.value);
            defer allocator.free(rel_path);
            break :blk context.visible_path_set.contains(rel_path);
        },
        .prefix, .glob => blk: {
            if (std.mem.indexOfScalar(u8, pattern.value, '/')) |_| break :blk false;

            for (context.visible_paths) |visible_path| {
                const entry_name = directFileNameForPrefix(visible_path, prefix) orelse continue;
                if (init_rules.matchesPattern(pattern, entry_name)) break :blk true;
            }
            break :blk false;
        },
    };
}

fn isMiseTrustedForPrefix(
    allocator: std.mem.Allocator,
    context: *const DetectionContext,
    prefix: []const u8,
    assume_repo_mise_trusted: ?bool,
    trust_cache: *std.StringHashMap(bool),
) !bool {
    if (assume_repo_mise_trusted) |trusted| return trusted;
    if (trust_cache.get(prefix)) |trusted| return trusted;

    const cwd = try resolveScopeCwd(allocator, context.repo_root, prefix);
    defer allocator.free(cwd);
    const trusted = detectMiseTrustInDir(allocator, cwd) catch false;
    try trust_cache.put(prefix, trusted);
    return trusted;
}

fn resolveScopeCwd(allocator: std.mem.Allocator, repo_root: []const u8, prefix: []const u8) ![]u8 {
    if (prefix.len == 0) return allocator.dupe(u8, repo_root);
    return std.fs.path.join(allocator, &.{ repo_root, prefix });
}

fn commandForPrefix(allocator: std.mem.Allocator, prefix: []const u8, command: []const u8) ![]u8 {
    if (prefix.len == 0) return allocator.dupe(u8, command);
    return std.fmt.allocPrint(allocator, "cd {s} && {s}", .{ prefix, command });
}

fn directFileNameForPrefix(rel_path: []const u8, prefix: []const u8) ?[]const u8 {
    if (prefix.len == 0) {
        if (std.mem.indexOfScalar(u8, rel_path, '/') != null) return null;
        return rel_path;
    }

    if (!std.mem.startsWith(u8, rel_path, prefix)) return null;
    if (rel_path.len <= prefix.len + 1) return null;
    if (rel_path[prefix.len] != '/') return null;

    const suffix = rel_path[prefix.len + 1 ..];
    if (std.mem.indexOfScalar(u8, suffix, '/') != null) return null;
    return suffix;
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

fn listVisibleRepoPaths(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
) ![]([]u8) {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "git",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
        },
        .cwd = repo_root,
        .max_output_bytes = 64 * 1024 * 1024,
    }) catch {
        return error.GitCommandFailed;
    };
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);

    switch (result.term) {
        .Exited => |code| if (code != 0) return error.GitCommandFailed,
        else => return error.GitCommandFailed,
    }

    var paths = std.array_list.Managed([]u8).init(allocator);
    errdefer freeStringItems(allocator, paths.items);
    defer paths.deinit();

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;
        try paths.append(try allocator.dupe(u8, trimmed));
    }

    return paths.toOwnedSlice();
}

fn collectRepoRootAndSubprojectPrefixes(
    allocator: std.mem.Allocator,
    visible_paths: []const []u8,
    max_subproject_scan_depth: usize,
) ![]([]u8) {
    var prefixes = std.array_list.Managed([]u8).init(allocator);
    errdefer freeStringItems(allocator, prefixes.items);
    defer prefixes.deinit();

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    const root = try allocator.dupe(u8, "");
    errdefer allocator.free(root);
    try seen.put(root, {});
    try prefixes.append(root);

    if (max_subproject_scan_depth == 0) {
        return prefixes.toOwnedSlice();
    }

    for (visible_paths) |path| {
        var segment_start: usize = 0;
        var depth: usize = 0;

        while (std.mem.indexOfScalarPos(u8, path, segment_start, '/')) |slash_index| {
            const segment = path[segment_start..slash_index];
            depth += 1;
            if (depth > max_subproject_scan_depth) break;
            if (segment.len > 0 and segment[0] == '.') break;

            const prefix = path[0..slash_index];
            if (seen.contains(prefix)) {
                segment_start = slash_index + 1;
                continue;
            }

            const duped = try allocator.dupe(u8, prefix);
            errdefer allocator.free(duped);
            try seen.put(duped, {});
            try prefixes.append(duped);

            segment_start = slash_index + 1;
        }
    }

    insertionSortStrings(prefixes.items);
    return prefixes.toOwnedSlice();
}

fn discoverForPathRule(
    allocator: std.mem.Allocator,
    context: *const DetectionContext,
    rule: init_rules.PathRule,
    recs: *std.array_list.Managed(Recommendation),
) !bool {
    var matched = false;
    const prefixes = context.prefixesForScope(rule.detection_scope);

    for (prefixes) |prefix| {
        for (rule.patterns) |pattern| {
            switch (pattern.kind) {
                .exact => {
                    const rel_path = try joinRelPath(allocator, prefix, pattern.value);
                    defer allocator.free(rel_path);
                    if (pathExists(context, rel_path)) {
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

                    for (context.visible_paths) |visible_path| {
                        const entry_name = directFileNameForPrefix(visible_path, prefix) orelse continue;
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

fn pathExists(context: *const DetectionContext, rel_path: []const u8) bool {
    return context.visible_path_set.contains(rel_path);
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

fn initTmpGitRepo(tmp: *std.testing.TmpDir) ![]u8 {
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    errdefer std.testing.allocator.free(root);

    const init_out = try git.runGit(std.testing.allocator, root, &.{"init"});
    defer std.testing.allocator.free(init_out);

    try tmp.dir.writeFile(.{ .sub_path = ".gitignore-global-empty", .data = "" });
    const excludes_path = try std.fs.path.join(std.testing.allocator, &.{ root, ".gitignore-global-empty" });
    defer std.testing.allocator.free(excludes_path);

    const cfg_out = try git.runGit(
        std.testing.allocator,
        root,
        &.{ "config", "--local", "core.excludesfile", excludes_path },
    );
    defer std.testing.allocator.free(cfg_out);

    return root;
}

fn hasRecommendation(recs: []const Recommendation, section: Section, value: []const u8) bool {
    for (recs) |rec| {
        if (rec.section == section and std.mem.eql(u8, rec.value, value)) return true;
    }
    return false;
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

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.writeFile(.{ .sub_path = "mise.toml", .data = "[tools]\nzig = \"0.15\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.makePath(".claude");
    try tmp.dir.writeFile(.{ .sub_path = ".claude/settings.local.json", .data = "{ }\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(hasRecommendation(recs, .symlink, "mise.local.toml"));
    try std.testing.expect(hasRecommendation(recs, .symlink, ".claude/settings.local.json"));
    try std.testing.expect(hasRecommendation(recs, .run, "mise trust"));
}

test "discoverRecommendations includes subproject matches with per-subproject commands" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.makePath("apps/api/.claude");
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/.claude/settings.local.json", .data = "{ }\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/.envrc", .data = "use flake\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.toml", .data = "[tools]\nzig = \"0.15\"\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{ .assume_repo_mise_trusted = true });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(hasRecommendation(recs, .symlink, "apps/api/mise.local.toml"));
    try std.testing.expect(hasRecommendation(recs, .symlink, "apps/api/.claude/settings.local.json"));
    try std.testing.expect(hasRecommendation(recs, .symlink, "apps/api/.envrc"));
    try std.testing.expect(hasRecommendation(recs, .run, "cd apps/api && mise trust"));
    try std.testing.expect(hasRecommendation(recs, .run, "cd apps/api && direnv allow"));
}

test "discoverRecommendations is invariant to invocation subdir input" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.makePath("apps/api/.claude");
    try tmp.dir.writeFile(.{ .sub_path = "mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = "mise.toml", .data = "[tools]\nzig = \"0.15\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/.claude/settings.local.json", .data = "{ }\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/.envrc", .data = "use flake\n" });

    const root_recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, root_recs);

    const invoked_recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
        .invocation_subdir = "apps/api",
    });
    defer freeRecommendations(std.testing.allocator, invoked_recs);

    for (root_recs) |rec| {
        try std.testing.expect(hasRecommendation(invoked_recs, rec.section, rec.value));
    }
    for (invoked_recs) |rec| {
        try std.testing.expect(hasRecommendation(root_recs, rec.section, rec.value));
    }
}

test "discoverRecommendations limits subproject scan depth and skips hidden roots" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.makePath("apps/api/service/.claude");
    try tmp.dir.makePath(".hidden/tools/.claude");
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/service/mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/service/.claude/settings.local.json", .data = "{ }\n" });
    try tmp.dir.writeFile(.{ .sub_path = ".hidden/tools/mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = ".hidden/tools/.claude/settings.local.json", .data = "{ }\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
        .max_subproject_scan_depth = 2,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(hasRecommendation(recs, .symlink, "apps/api/mise.local.toml"));
    try std.testing.expect(!hasRecommendation(recs, .symlink, "apps/api/service/mise.local.toml"));
    try std.testing.expect(!hasRecommendation(recs, .symlink, "apps/api/service/.claude/settings.local.json"));
    try std.testing.expect(!hasRecommendation(recs, .symlink, ".hidden/tools/mise.local.toml"));
    try std.testing.expect(!hasRecommendation(recs, .symlink, ".hidden/tools/.claude/settings.local.json"));
}

test "discoverRecommendations respects gitignore when scanning subprojects" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.makePath("apps/api/.claude");
    try tmp.dir.writeFile(.{ .sub_path = ".gitignore", .data = "apps/\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/.claude/settings.local.json", .data = "{ }\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(!hasRecommendation(recs, .symlink, "apps/api/mise.local.toml"));
    try std.testing.expect(!hasRecommendation(recs, .symlink, "apps/api/.claude/settings.local.json"));
    try std.testing.expect(!hasRecommendation(recs, .run, "cd apps/api && mise trust"));
}

test "discoverRecommendations can expand depth when requested" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.makePath("apps/api/service/.claude");
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/service/mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/service/.claude/settings.local.json", .data = "{ }\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
        .max_subproject_scan_depth = 3,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(hasRecommendation(recs, .symlink, "apps/api/service/mise.local.toml"));
    try std.testing.expect(hasRecommendation(recs, .symlink, "apps/api/service/.claude/settings.local.json"));
}

test "discoverRecommendations omits mise trust when repo is not trusted" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.writeFile(.{ .sub_path = "mise.toml", .data = "[tools]\nzig = \"0.15\"\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = false,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(!hasRecommendation(recs, .run, "mise trust"));
}

test "discoverRecommendations includes mise trust when mise.toml exists and repo is trusted" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.writeFile(.{ .sub_path = "mise.toml", .data = "[tools]\nzig = \"0.15\"\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(hasRecommendation(recs, .run, "mise trust"));
}

test "discoverRecommendations includes subproject mise trust when trusted" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.makePath("apps/api");
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.toml", .data = "[tools]\nzig = \"0.15\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.local.toml", .data = "trust = true\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(hasRecommendation(recs, .run, "cd apps/api && mise trust"));
}

test "discoverRecommendations omits subproject mise trust when not trusted" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.makePath("apps/api");
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.toml", .data = "[tools]\nzig = \"0.15\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.local.toml", .data = "trust = true\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = false,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(!hasRecommendation(recs, .run, "cd apps/api && mise trust"));
}

test "discoverRecommendations preserves root command without cd prefix" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.writeFile(.{ .sub_path = ".envrc", .data = "use flake\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(hasRecommendation(recs, .run, "direnv allow"));
    try std.testing.expect(!hasRecommendation(recs, .run, "cd . && direnv allow"));
}

test "discoverRecommendations defaults to depth 2 for subproject scanning" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.makePath("a/b/c/.claude");
    try tmp.dir.writeFile(.{ .sub_path = "a/b/mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = "a/b/c/mise.local.toml", .data = "trust = true\n" });
    try tmp.dir.writeFile(.{ .sub_path = "a/b/c/.claude/settings.local.json", .data = "{ }\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(hasRecommendation(recs, .symlink, "a/b/mise.local.toml"));
    try std.testing.expect(!hasRecommendation(recs, .symlink, "a/b/c/mise.local.toml"));
    try std.testing.expect(!hasRecommendation(recs, .symlink, "a/b/c/.claude/settings.local.json"));
}

test "discoverRecommendations keeps hidden exact root targets" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.makePath(".claude");
    try tmp.dir.writeFile(.{ .sub_path = ".claude/settings.local.json", .data = "{ }\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    try std.testing.expect(hasRecommendation(recs, .symlink, ".claude/settings.local.json"));
}

test "discoverRecommendations omits duplicate command recommendations across triggers" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.writeFile(.{ .sub_path = "mise.toml", .data = "[tools]\nzig = \"0.15\"\n" });
    try tmp.dir.writeFile(.{ .sub_path = "mise.local.toml", .data = "trust = true\n" });

    const recs = try discoverRecommendationsWithOptions(std.testing.allocator, root, .{
        .assume_repo_mise_trusted = true,
    });
    defer freeRecommendations(std.testing.allocator, recs);

    var count: usize = 0;
    for (recs) |rec| {
        if (rec.section == .run and std.mem.eql(u8, rec.value, "mise trust")) {
            count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), count);
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

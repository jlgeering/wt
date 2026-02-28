const std = @import("std");

pub const Section = enum {
    copy,
    symlink,
    run,
};

pub const DetectionScope = enum {
    repo_root,
    invocation_subdir,
    repo_root_and_invocation_subdir,
    repo_root_and_subprojects,
};

pub const PatternKind = enum {
    exact,
    prefix,
    glob,
};

pub const Pattern = struct {
    kind: PatternKind,
    value: []const u8,
};

pub const PathRule = struct {
    id: []const u8,
    section: Section,
    detection_scope: DetectionScope = .repo_root_and_subprojects,
    prompt: []const u8,
    reason: []const u8,
    patterns: []const Pattern,
    // Optional recommendation leaf paths to emit when any pattern matches.
    // When empty, the matched path itself is recommended.
    recommendation_values: []const []const u8 = &.{},
};

pub const CommandRule = struct {
    id: []const u8,
    section: Section = .run,
    detection_scope: DetectionScope = .repo_root_and_subprojects,
    prompt: []const u8,
    reason: []const u8,
    command: []const u8,
    trigger_rule_ids: []const []const u8,
    trigger_patterns: []const Pattern = &.{},
    requires_repo_mise_trust: bool = false,
};

pub const AntiPatternPathRule = struct {
    section: Section,
    pattern: Pattern,
    message: []const u8,
};

pub const AntiPatternRunTokenRule = struct {
    token: []const u8,
    message: []const u8,
};

pub const path_rules = [_]PathRule{
    .{
        .id = "mise-local-file",
        .section = .symlink,
        .prompt = "Symlink local mise config from the main repo",
        .reason = "Keeping local mise variants shared across worktrees avoids configuration drift.",
        .patterns = &.{
            .{ .kind = .exact, .value = "mise.local.toml" },
            .{ .kind = .exact, .value = ".mise.local.toml" },
            .{ .kind = .glob, .value = "mise*local*.toml" },
            .{ .kind = .glob, .value = ".mise*local*.toml" },
        },
    },
    .{
        .id = "claude-local-settings",
        .section = .symlink,
        .prompt = "Symlink Claude local settings from the main repo",
        .reason = "Sharing Claude local settings keeps agent preferences and paths consistent across worktrees.",
        .patterns = &.{
            .{ .kind = .exact, .value = ".claude/settings.local.json" },
        },
    },
    .{
        .id = "env-local-files",
        .section = .copy,
        .prompt = "Copy local dotenv files",
        .reason = "Local dotenv files usually hold machine-local secrets or overrides.",
        .patterns = &.{
            .{ .kind = .exact, .value = ".env.local" },
            .{ .kind = .glob, .value = ".env.*.local" },
        },
    },
    .{
        .id = "vscode-local-settings",
        .section = .copy,
        .prompt = "Copy VS Code local settings",
        .reason = "Workspace-local editor settings are frequently machine specific.",
        .patterns = &.{
            .{ .kind = .exact, .value = ".vscode/settings.local.json" },
        },
    },
    .{
        .id = "elixir-cow-build-and-deps",
        .section = .copy,
        .prompt = "Copy Elixir deps and _build directories from the main repo",
        .reason = "Reusing Elixir dependency and build outputs speeds up worktree setup while preserving CoW behavior where available.",
        .patterns = &.{
            .{ .kind = .exact, .value = "mix.exs" },
        },
        .recommendation_values = &.{ "deps", "_build" },
    },
    .{
        .id = "direnv-envrc",
        .section = .symlink,
        .prompt = "Symlink .envrc from the main repo",
        .reason = "Sharing .envrc avoids divergence between worktrees and keeps activation logic consistent.",
        .patterns = &.{
            .{ .kind = .exact, .value = ".envrc" },
        },
    },
};

pub const command_rules = [_]CommandRule{
    .{
        .id = "mise-trust",
        .prompt = "Run mise trust after creating a worktree",
        .reason = "mise config files need trust in each new worktree.",
        .command = "mise trust",
        .trigger_rule_ids = &.{"mise-local-file"},
        .trigger_patterns = &.{
            .{ .kind = .exact, .value = "mise.toml" },
            .{ .kind = .exact, .value = ".mise.toml" },
        },
        .requires_repo_mise_trust = true,
    },
    .{
        .id = "direnv-allow",
        .prompt = "Run direnv allow after creating a worktree",
        .reason = "direnv needs per-directory allow approval.",
        .command = "direnv allow",
        .trigger_rule_ids = &.{"direnv-envrc"},
    },
};

pub const path_anti_patterns = [_]AntiPatternPathRule{
    .{ .section = .copy, .pattern = .{ .kind = .exact, .value = ".git" }, .message = "Never copy Git metadata into worktrees." },
    .{ .section = .copy, .pattern = .{ .kind = .prefix, .value = ".git/" }, .message = "Never copy Git metadata into worktrees." },
    .{ .section = .copy, .pattern = .{ .kind = .exact, .value = ".beads" }, .message = "Issue-tracker databases should not be copied per worktree." },
    .{ .section = .copy, .pattern = .{ .kind = .prefix, .value = ".beads/" }, .message = "Issue-tracker databases should not be copied per worktree." },
    .{ .section = .copy, .pattern = .{ .kind = .exact, .value = "node_modules" }, .message = "node_modules is large and should be rebuilt per worktree." },
    .{ .section = .copy, .pattern = .{ .kind = .prefix, .value = "node_modules/" }, .message = "node_modules is large and should be rebuilt per worktree." },
    .{ .section = .copy, .pattern = .{ .kind = .exact, .value = ".zig-cache" }, .message = "Build caches should not be copied into worktrees." },
    .{ .section = .copy, .pattern = .{ .kind = .prefix, .value = ".zig-cache/" }, .message = "Build caches should not be copied into worktrees." },
    .{ .section = .copy, .pattern = .{ .kind = .exact, .value = "zig-out" }, .message = "Build outputs should not be copied into worktrees." },
    .{ .section = .copy, .pattern = .{ .kind = .prefix, .value = "zig-out/" }, .message = "Build outputs should not be copied into worktrees." },
};

pub const run_anti_patterns = [_]AntiPatternRunTokenRule{
    .{ .token = "rm -rf", .message = "Avoid destructive remove commands in [run].commands." },
    .{ .token = "git reset --hard", .message = "Avoid destructive Git reset commands in [run].commands." },
};

pub fn matchesPattern(pattern: Pattern, candidate: []const u8) bool {
    return switch (pattern.kind) {
        .exact => std.mem.eql(u8, candidate, pattern.value),
        .prefix => std.mem.startsWith(u8, candidate, pattern.value),
        .glob => globMatch(pattern.value, candidate),
    };
}

fn globMatch(pattern: []const u8, text: []const u8) bool {
    var p: usize = 0;
    var t: usize = 0;
    var star_index: ?usize = null;
    var backtrack_t: usize = 0;

    while (t < text.len) {
        if (p < pattern.len and (pattern[p] == text[t])) {
            p += 1;
            t += 1;
        } else if (p < pattern.len and pattern[p] == '*') {
            star_index = p;
            p += 1;
            backtrack_t = t;
        } else if (star_index) |star| {
            p = star + 1;
            backtrack_t += 1;
            t = backtrack_t;
        } else {
            return false;
        }
    }

    while (p < pattern.len and pattern[p] == '*') {
        p += 1;
    }

    return p == pattern.len;
}

test "matchesPattern exact, prefix, and glob" {
    try std.testing.expect(matchesPattern(.{ .kind = .exact, .value = "mise.local.toml" }, "mise.local.toml"));
    try std.testing.expect(!matchesPattern(.{ .kind = .exact, .value = "mise.local.toml" }, ".mise.local.toml"));

    try std.testing.expect(matchesPattern(.{ .kind = .prefix, .value = ".git/" }, ".git/config"));
    try std.testing.expect(!matchesPattern(.{ .kind = .prefix, .value = ".git/" }, "git/config"));

    try std.testing.expect(matchesPattern(.{ .kind = .glob, .value = "mise*local*.toml" }, "mise.local.toml"));
    try std.testing.expect(matchesPattern(.{ .kind = .glob, .value = "mise*local*.toml" }, "mise.foo.local.bar.toml"));
    try std.testing.expect(!matchesPattern(.{ .kind = .glob, .value = "mise*local*.toml" }, "mise.toml"));
}

test "default setup strategy for mise and claude local files is symlink" {
    var saw_mise_rule = false;
    var saw_claude_rule = false;

    for (path_rules) |rule| {
        if (std.mem.eql(u8, rule.id, "mise-local-file")) {
            saw_mise_rule = true;
            try std.testing.expectEqual(Section.symlink, rule.section);
        }
        if (std.mem.eql(u8, rule.id, "claude-local-settings")) {
            saw_claude_rule = true;
            try std.testing.expectEqual(Section.symlink, rule.section);
        }
    }

    try std.testing.expect(saw_mise_rule);
    try std.testing.expect(saw_claude_rule);
}

test "elixir mix rule recommends deps and _build copy paths" {
    var saw_rule = false;

    for (path_rules) |rule| {
        if (!std.mem.eql(u8, rule.id, "elixir-cow-build-and-deps")) continue;
        saw_rule = true;
        try std.testing.expectEqual(Section.copy, rule.section);
        try std.testing.expectEqual(@as(usize, 1), rule.patterns.len);
        try std.testing.expectEqual(PatternKind.exact, rule.patterns[0].kind);
        try std.testing.expectEqualStrings("mix.exs", rule.patterns[0].value);
        try std.testing.expectEqual(@as(usize, 2), rule.recommendation_values.len);
        try std.testing.expectEqualStrings("deps", rule.recommendation_values[0]);
        try std.testing.expectEqualStrings("_build", rule.recommendation_values[1]);
    }

    try std.testing.expect(saw_rule);
}

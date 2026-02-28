const std = @import("std");
const git = @import("git.zig");

pub fn listVisibleRepoPaths(
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

    sortStrings(paths.items);
    return paths.toOwnedSlice();
}

pub fn collectRepoRootAndSubprojectPrefixes(
    allocator: std.mem.Allocator,
    visible_paths: []const []const u8,
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

    sortStrings(prefixes.items);
    return prefixes.toOwnedSlice();
}

pub fn listEntryNamesAtPrefix(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    prefix: []const u8,
) ![]([]u8) {
    var names = std.array_list.Managed([]u8).init(allocator);
    errdefer freeStringItems(allocator, names.items);
    defer names.deinit();

    const dir_path = if (prefix.len == 0)
        try allocator.dupe(u8, repo_root)
    else
        try std.fs.path.join(allocator, &.{ repo_root, prefix });
    defer allocator.free(dir_path);

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return try allocator.alloc([]u8, 0),
        else => return err,
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .file, .sym_link => try names.append(try allocator.dupe(u8, entry.name)),
            else => {},
        }
    }

    sortStrings(names.items);
    return names.toOwnedSlice();
}

pub fn pathExists(allocator: std.mem.Allocator, repo_root: []const u8, rel_path: []const u8) bool {
    const abs_path = std.fs.path.join(allocator, &.{ repo_root, rel_path }) catch return false;
    defer allocator.free(abs_path);

    if (std.fs.cwd().access(abs_path, .{})) |_| {
        return true;
    } else |_| {
        return false;
    }
}

pub fn freeStringSlice(allocator: std.mem.Allocator, items: []([]u8)) void {
    for (items) |item| allocator.free(item);
    allocator.free(items);
}

fn freeStringItems(allocator: std.mem.Allocator, items: []([]u8)) void {
    for (items) |item| allocator.free(item);
}

fn sortStrings(items: []([]u8)) void {
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

fn containsString(items: []const []const u8, value: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, value)) return true;
    }
    return false;
}

test "collectRepoRootAndSubprojectPrefixes respects depth and hidden roots" {
    const visible = [_][]const u8{
        "apps/api/README.md",
        "apps/api/service/mise.toml",
        ".hidden/tools/mise.toml",
        "a/b/c/file.txt",
    };

    const prefixes = try collectRepoRootAndSubprojectPrefixes(std.testing.allocator, &visible, 2);
    defer freeStringSlice(std.testing.allocator, prefixes);

    try std.testing.expect(containsString(prefixes, ""));
    try std.testing.expect(containsString(prefixes, "apps"));
    try std.testing.expect(containsString(prefixes, "apps/api"));
    try std.testing.expect(containsString(prefixes, "a"));
    try std.testing.expect(containsString(prefixes, "a/b"));
    try std.testing.expect(!containsString(prefixes, "apps/api/service"));
    try std.testing.expect(!containsString(prefixes, ".hidden"));
}

test "listEntryNamesAtPrefix returns direct file entries only" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("apps/api/subdir");
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.local.toml", .data = "x\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/.envrc", .data = "y\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/subdir/nested.txt", .data = "z\n" });

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const entries = try listEntryNamesAtPrefix(std.testing.allocator, root, "apps/api");
    defer freeStringSlice(std.testing.allocator, entries);

    try std.testing.expect(containsString(entries, "mise.local.toml"));
    try std.testing.expect(containsString(entries, ".envrc"));
    try std.testing.expect(!containsString(entries, "subdir"));
}

test "pathExists checks relative path in repo root" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("apps/api");
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.toml", .data = "x\n" });

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    try std.testing.expect(pathExists(std.testing.allocator, root, "apps/api/mise.toml"));
    try std.testing.expect(!pathExists(std.testing.allocator, root, "apps/api/missing.toml"));
}

test "listVisibleRepoPaths respects gitignore" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try initTmpGitRepo(&tmp);
    defer std.testing.allocator.free(root);

    try tmp.dir.makePath("apps/api");
    try tmp.dir.writeFile(.{ .sub_path = ".gitignore", .data = "apps/\n" });
    try tmp.dir.writeFile(.{ .sub_path = "README.md", .data = "root\n" });
    try tmp.dir.writeFile(.{ .sub_path = "apps/api/mise.local.toml", .data = "ignored\n" });

    const paths = try listVisibleRepoPaths(std.testing.allocator, root);
    defer freeStringSlice(std.testing.allocator, paths);

    try std.testing.expect(containsString(paths, "README.md"));
    try std.testing.expect(!containsString(paths, "apps/api/mise.local.toml"));
}

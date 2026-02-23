# wt CLI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a composable CLI tool for managing git worktrees, written in Zig.

**Architecture:** Layered — yazap handles CLI routing, command functions delegate to core lib modules (git.zig, worktree.zig, config.zig, setup.zig) which shell out to git and use std.fs. stdout for machine output, stderr for human messages.

**Tech Stack:** Zig 0.14.x, yazap v0.6.3 (arg parsing), sam701/zig-toml (TOML config parsing)

**Note:** The design doc references "zig-config" but the actual library is `sam701/zig-toml`. Use tag `last-zig-0.14.1` for Zig 0.14 compatibility.

---

### Task 1: Project Scaffolding

**Files:**
- Create: `mise.toml`
- Create: `build.zig.zon`
- Create: `build.zig`
- Create: `src/main.zig`
- Create: `.gitignore`

**Step 1: Create mise.toml**

```toml
[tools]
zig = "0.14"
```

**Step 2: Verify zig is available**

Run: `mise install && mise exec -- zig version`
Expected: `0.14.x` version output

**Step 3: Initialize build.zig.zon**

```zig
.{
    .name = "wt",
    .version = "0.1.0",
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

**Step 4: Fetch dependencies**

Run:
```bash
zig fetch --save git+https://github.com/prajwalch/yazap#v0.6.3
zig fetch --save "git+https://github.com/sam701/zig-toml#last-zig-0.14.1"
```

Verify `build.zig.zon` now has both dependencies with hashes.

**Step 5: Create build.zig**

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "wt",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const yazap_dep = b.dependency("yazap", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("yazap", yazap_dep.module("yazap"));

    const toml_dep = b.dependency("zig-toml", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("toml", toml_dep.module("toml"));

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run wt");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_tests.root_module.addImport("toml", toml_dep.module("toml"));

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
}
```

**Step 6: Create src/main.zig with basic yazap setup**

```zig
const std = @import("std");
const yazap = @import("yazap");

const App = yazap.App;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.init(allocator, "wt", "Git worktree manager");
    defer app.deinit();

    var wt = app.rootCommand();
    wt.setProperty(.help_on_empty_args);

    // Subcommands will be added in later tasks
    try wt.addSubcommand(app.createCommand("list", "List all worktrees"));

    const matches = try app.parseProcess();

    if (matches.subcommandMatches("list")) |_| {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("wt list: not yet implemented\n", .{});
    }
}
```

**Step 7: Create src/lib/root.zig**

```zig
pub const git = @import("git.zig");
pub const worktree = @import("worktree.zig");
pub const config = @import("config.zig");
pub const setup = @import("setup.zig");

test {
    _ = git;
    _ = worktree;
    _ = config;
    _ = setup;
}
```

Create placeholder files for the test runner:

`src/lib/git.zig`:
```zig
test "placeholder" {}
```

`src/lib/worktree.zig`:
```zig
test "placeholder" {}
```

`src/lib/config.zig`:
```zig
test "placeholder" {}
```

`src/lib/setup.zig`:
```zig
test "placeholder" {}
```

**Step 8: Create .gitignore**

```
zig-out/
.zig-cache/
zig-cache/
```

**Step 9: Verify build and help**

Run: `zig build`
Expected: Compiles without errors

Run: `zig build run -- --help`
Expected: Help output showing `list` subcommand

Run: `zig build test`
Expected: All placeholder tests pass

**Step 10: Commit**

```bash
git add mise.toml build.zig build.zig.zon src/ .gitignore
git commit -m "feat: project scaffolding with yazap and zig-toml"
```

---

### Task 2: Git Porcelain Parser

**Files:**
- Modify: `src/lib/git.zig`

**Context:** `git worktree list --porcelain` outputs blocks like:

```
worktree /Users/jl/src/myapp
HEAD abc123def456
branch refs/heads/main
<blank line>
worktree /Users/jl/src/myapp--feat
HEAD def456abc123
branch refs/heads/feat
<blank line>
```

`git status --porcelain` outputs lines like:
```
 M src/main.zig
?? new_file.txt
```

**Step 1: Write failing test for parseWorktreeList**

In `src/lib/git.zig`:

```zig
const std = @import("std");

pub const WorktreeInfo = struct {
    path: []const u8,
    head: []const u8,
    branch: ?[]const u8, // null for detached HEAD
    is_bare: bool,
};

pub fn parseWorktreeList(allocator: std.mem.Allocator, output: []const u8) ![]WorktreeInfo {
    _ = allocator;
    _ = output;
    return error.NotImplemented;
}

test "parseWorktreeList parses two worktrees" {
    const input =
        \\worktree /Users/jl/src/myapp
        \\HEAD abc123def456789012345678901234567890abcd
        \\branch refs/heads/main
        \\
        \\worktree /Users/jl/src/myapp--feat
        \\HEAD def456abc123789012345678901234567890abcd
        \\branch refs/heads/feat
        \\
    ;

    const result = try parseWorktreeList(std.testing.allocator, input);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("/Users/jl/src/myapp", result[0].path);
    try std.testing.expectEqualStrings("main", result[0].branch.?);
    try std.testing.expectEqualStrings("/Users/jl/src/myapp--feat", result[1].path);
    try std.testing.expectEqualStrings("feat", result[1].branch.?);
}
```

**Step 2: Run test to verify it fails**

Run: `zig build test`
Expected: FAIL with `error.NotImplemented`

**Step 3: Implement parseWorktreeList**

Replace the function body:

```zig
pub fn parseWorktreeList(allocator: std.mem.Allocator, output: []const u8) ![]WorktreeInfo {
    var worktrees = std.ArrayList(WorktreeInfo).init(allocator);
    defer worktrees.deinit();

    var current: WorktreeInfo = .{ .path = "", .head = "", .branch = null, .is_bare = false };
    var in_entry = false;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) {
            if (in_entry) {
                try worktrees.append(current);
                current = .{ .path = "", .head = "", .branch = null, .is_bare = false };
                in_entry = false;
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "worktree ")) {
            current.path = line["worktree ".len..];
            in_entry = true;
        } else if (std.mem.startsWith(u8, line, "HEAD ")) {
            current.head = line["HEAD ".len..];
        } else if (std.mem.startsWith(u8, line, "branch refs/heads/")) {
            current.branch = line["branch refs/heads/".len..];
        } else if (std.mem.eql(u8, line, "bare")) {
            current.is_bare = true;
        }
    }

    // Handle last entry if no trailing newline
    if (in_entry) {
        try worktrees.append(current);
    }

    return worktrees.toOwnedSlice();
}
```

**Step 4: Run test to verify it passes**

Run: `zig build test`
Expected: PASS

**Step 5: Add test for detached HEAD**

```zig
test "parseWorktreeList handles detached HEAD" {
    const input =
        \\worktree /Users/jl/src/myapp--detached
        \\HEAD abc123def456789012345678901234567890abcd
        \\detached
        \\
    ;

    const result = try parseWorktreeList(std.testing.allocator, input);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(result[0].branch == null);
}
```

**Step 6: Run test -- should pass (detached = no branch line)**

Run: `zig build test`
Expected: PASS

**Step 7: Add test for bare worktree**

```zig
test "parseWorktreeList handles bare worktree" {
    const input =
        \\worktree /Users/jl/src/myapp.git
        \\HEAD abc123def456789012345678901234567890abcd
        \\bare
        \\
    ;

    const result = try parseWorktreeList(std.testing.allocator, input);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(result[0].is_bare);
}
```

**Step 8: Run test**

Run: `zig build test`
Expected: PASS

**Step 9: Add parseStatusPorcelain for dirty file counting**

```zig
pub const WorktreeStatus = struct {
    modified: usize,
    untracked: usize,
};

pub fn parseStatusPorcelain(output: []const u8) WorktreeStatus {
    var modified: usize = 0;
    var untracked: usize = 0;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len < 2) continue;
        if (line[0] == '?' and line[1] == '?') {
            untracked += 1;
        } else {
            modified += 1;
        }
    }

    return .{ .modified = modified, .untracked = untracked };
}

test "parseStatusPorcelain counts modified and untracked" {
    const input =
        \\ M src/main.zig
        \\?? new_file.txt
        \\MM src/lib.zig
    ;

    const status = parseStatusPorcelain(input);
    try std.testing.expectEqual(@as(usize, 2), status.modified);
    try std.testing.expectEqual(@as(usize, 1), status.untracked);
}

test "parseStatusPorcelain handles empty output" {
    const status = parseStatusPorcelain("");
    try std.testing.expectEqual(@as(usize, 0), status.modified);
    try std.testing.expectEqual(@as(usize, 0), status.untracked);
}
```

**Step 10: Run tests**

Run: `zig build test`
Expected: PASS

**Step 11: Add runGit helper function**

```zig
pub const GitError = error{
    GitNotFound,
    NotAGitRepo,
    GitCommandFailed,
} || std.mem.Allocator.Error;

pub fn runGit(allocator: std.mem.Allocator, cwd: ?[]const u8, args: []const []const u8) ![]u8 {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append("git");
    try argv.appendSlice(args);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
        .cwd = cwd,
    }) catch {
        return error.GitNotFound;
    };
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                allocator.free(result.stdout);
                return error.GitCommandFailed;
            }
            return result.stdout;
        },
        else => {
            allocator.free(result.stdout);
            return error.GitCommandFailed;
        },
    }
}
```

Note: `runGit` is not unit-testable without a real git repo. It will be tested in integration tests (Task 6+).

**Step 12: Run all tests**

Run: `zig build test`
Expected: PASS

**Step 13: Commit**

```bash
git add src/lib/git.zig
git commit -m "feat: git porcelain output parser with status counting"
```

---

### Task 3: Worktree Path Logic

**Files:**
- Modify: `src/lib/worktree.zig`

**Step 1: Write failing test for computeWorktreePath**

```zig
const std = @import("std");

/// Compute the worktree path for a branch: {parent}/{repo}--{branch}
pub fn computeWorktreePath(allocator: std.mem.Allocator, main_path: []const u8, branch: []const u8) ![]u8 {
    _ = allocator;
    _ = main_path;
    _ = branch;
    return error.NotImplemented;
}

test "computeWorktreePath creates sibling with branch suffix" {
    const result = try computeWorktreePath(
        std.testing.allocator,
        "/Users/jl/src/myapp",
        "feat-auth",
    );
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("/Users/jl/src/myapp--feat-auth", result);
}
```

**Step 2: Run test to verify failure**

Run: `zig build test`
Expected: FAIL

**Step 3: Implement computeWorktreePath**

```zig
pub fn computeWorktreePath(allocator: std.mem.Allocator, main_path: []const u8, branch: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}--{s}", .{ main_path, branch });
}
```

**Step 4: Run test**

Run: `zig build test`
Expected: PASS

**Step 5: Add extractBranchFromPath**

```zig
/// Extract branch name from worktree path.
/// Returns null if path doesn't match the {repo}--{branch} pattern.
pub fn extractBranchFromPath(main_path: []const u8, wt_path: []const u8) ?[]const u8 {
    const prefix_len = main_path.len + "--".len;
    if (wt_path.len <= prefix_len) return null;
    if (!std.mem.startsWith(u8, wt_path, main_path)) return null;
    if (!std.mem.startsWith(u8, wt_path[main_path.len..], "--")) return null;
    return wt_path[prefix_len..];
}

test "extractBranchFromPath returns branch name" {
    const branch = extractBranchFromPath(
        "/Users/jl/src/myapp",
        "/Users/jl/src/myapp--feat-auth",
    );
    try std.testing.expectEqualStrings("feat-auth", branch.?);
}

test "extractBranchFromPath returns null for main worktree" {
    const branch = extractBranchFromPath(
        "/Users/jl/src/myapp",
        "/Users/jl/src/myapp",
    );
    try std.testing.expect(branch == null);
}

test "extractBranchFromPath returns null for unrelated path" {
    const branch = extractBranchFromPath(
        "/Users/jl/src/myapp",
        "/Users/jl/src/other",
    );
    try std.testing.expect(branch == null);
}
```

**Step 6: Run tests**

Run: `zig build test`
Expected: PASS

**Step 7: Add repoName helper**

```zig
/// Get the repository name from the main worktree path (last path component).
pub fn repoName(main_path: []const u8) []const u8 {
    return std.fs.path.basename(main_path);
}

test "repoName returns last path component" {
    try std.testing.expectEqualStrings("myapp", repoName("/Users/jl/src/myapp"));
    try std.testing.expectEqualStrings("wt", repoName("/Users/jl/src/wt"));
}
```

**Step 8: Run tests and commit**

Run: `zig build test`
Expected: PASS

```bash
git add src/lib/worktree.zig
git commit -m "feat: worktree path computation and branch extraction"
```

---

### Task 4: Config Parser

**Files:**
- Modify: `src/lib/config.zig`

**Step 1: Define Config struct and write failing test**

```zig
const std = @import("std");
const toml = @import("toml");

pub const CopyConfig = struct {
    paths: []const []const u8 = &.{},
};

pub const SymlinkConfig = struct {
    paths: []const []const u8 = &.{},
};

pub const RunConfig = struct {
    commands: []const []const u8 = &.{},
};

pub const Config = struct {
    copy: ?*CopyConfig = null,
    symlink: ?*SymlinkConfig = null,
    run: ?*RunConfig = null,

    pub fn copyPaths(self: Config) []const []const u8 {
        return if (self.copy) |c| c.paths else &.{};
    }

    pub fn symlinkPaths(self: Config) []const []const u8 {
        return if (self.symlink) |s| s.paths else &.{};
    }

    pub fn runCommands(self: Config) []const []const u8 {
        return if (self.run) |r| r.commands else &.{};
    }
};

pub const ParsedConfig = struct {
    arena: std.heap.ArenaAllocator,
    value: Config,

    pub fn deinit(self: *ParsedConfig) void {
        self.arena.deinit();
    }
};

pub fn parseConfigString(allocator: std.mem.Allocator, input: []const u8) !ParsedConfig {
    _ = allocator;
    _ = input;
    return error.NotImplemented;
}

test "parseConfigString parses full config" {
    const input =
        \\[copy]
        \\paths = ["deps", "_build"]
        \\
        \\[symlink]
        \\paths = ["mise.local.toml"]
        \\
        \\[run]
        \\commands = ["mise trust", "mix deps.get"]
    ;

    var result = try parseConfigString(std.testing.allocator, input);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.value.copyPaths().len);
    try std.testing.expectEqualStrings("deps", result.value.copyPaths()[0]);
    try std.testing.expectEqualStrings("_build", result.value.copyPaths()[1]);

    try std.testing.expectEqual(@as(usize, 1), result.value.symlinkPaths().len);
    try std.testing.expectEqualStrings("mise.local.toml", result.value.symlinkPaths()[0]);

    try std.testing.expectEqual(@as(usize, 2), result.value.runCommands().len);
    try std.testing.expectEqualStrings("mise trust", result.value.runCommands()[0]);
}
```

**Step 2: Run test to verify failure**

Run: `zig build test`
Expected: FAIL

**Step 3: Implement parseConfigString**

```zig
pub fn parseConfigString(allocator: std.mem.Allocator, input: []const u8) !ParsedConfig {
    var parser = toml.Parser(Config).init(allocator);
    defer parser.deinit();

    var result = try parser.parseString(input);
    return ParsedConfig{
        .arena = result.arena,
        .value = result.value,
    };
}
```

Note: The exact zig-toml API may differ slightly. The struct-based parsing maps TOML sections to struct fields automatically. Nested `[copy]` maps to the `copy` field, etc. Adjust based on what compiles.

**Step 4: Run test**

Run: `zig build test`
Expected: PASS

**Step 5: Test empty config**

```zig
test "parseConfigString handles empty string" {
    var result = try parseConfigString(std.testing.allocator, "");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.value.copyPaths().len);
    try std.testing.expectEqual(@as(usize, 0), result.value.symlinkPaths().len);
    try std.testing.expectEqual(@as(usize, 0), result.value.runCommands().len);
}
```

**Step 6: Test partial config (only copy section)**

```zig
test "parseConfigString handles partial config" {
    const input =
        \\[copy]
        \\paths = ["deps"]
    ;

    var result = try parseConfigString(std.testing.allocator, input);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.value.copyPaths().len);
    try std.testing.expectEqual(@as(usize, 0), result.value.symlinkPaths().len);
    try std.testing.expectEqual(@as(usize, 0), result.value.runCommands().len);
}
```

**Step 7: Add loadConfigFile that handles missing file**

```zig
pub fn loadConfigFile(allocator: std.mem.Allocator, dir_path: []const u8) !ParsedConfig {
    const config_path = try std.fs.path.join(allocator, &.{ dir_path, ".wt.toml" });
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            // Return empty config
            return ParsedConfig{
                .arena = std.heap.ArenaAllocator.init(allocator),
                .value = Config{},
            };
        },
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    return parseConfigString(allocator, content);
}
```

Note: `loadConfigFile` uses real filesystem, so it's tested in integration tests.

**Step 8: Run all tests and commit**

Run: `zig build test`
Expected: PASS

```bash
git add src/lib/config.zig
git commit -m "feat: TOML config parser for .wt.toml"
```

---

### Task 5: Setup Operations

**Files:**
- Modify: `src/lib/setup.zig`

**Step 1: Implement cowCopy**

```zig
const std = @import("std");
const builtin = @import("builtin");

pub const SetupError = error{
    CopyFailed,
    SymlinkFailed,
    CommandFailed,
} || std.mem.Allocator.Error;

/// Copy a path from source to target using copy-on-write where available.
/// Shells out to `cp` for CoW support. Skips if source missing or target exists.
pub fn cowCopy(allocator: std.mem.Allocator, source_root: []const u8, target_root: []const u8, rel_path: []const u8, stderr_writer: anytype) !void {
    const source = try std.fs.path.join(allocator, &.{ source_root, rel_path });
    defer allocator.free(source);
    const target = try std.fs.path.join(allocator, &.{ target_root, rel_path });
    defer allocator.free(target);

    // Check source exists
    std.fs.accessAbsolute(source, .{}) catch {
        try stderr_writer.print("Skipping {s}: source doesn't exist\n", .{rel_path});
        return;
    };

    // Check target doesn't already exist
    std.fs.accessAbsolute(target, .{}) catch |err| switch (err) {
        error.FileNotFound => {}, // Good, doesn't exist yet
        else => return err,
    };
    // If we get here without error, target exists
    if (std.fs.accessAbsolute(target, .{})) |_| {
        try stderr_writer.print("Skipping {s}: already exists\n", .{rel_path});
        return;
    } else |_| {}

    // Ensure parent directory exists
    if (std.fs.path.dirname(target)) |parent| {
        std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    // Platform-specific CoW copy
    const cp_args = switch (builtin.os.tag) {
        .macos => &[_][]const u8{ "cp", "-cR", source, target },
        .linux => &[_][]const u8{ "cp", "-R", "--reflink=auto", source, target },
        else => &[_][]const u8{ "cp", "-R", source, target },
    };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = cp_args,
    }) catch {
        return error.CopyFailed;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) return error.CopyFailed;
        },
        else => return error.CopyFailed,
    }

    try stderr_writer.print("Copied (CoW) {s}\n", .{rel_path});
}
```

**Step 2: Implement createSymlink**

```zig
/// Create a symlink from target_root/rel_path -> source_root/rel_path.
/// Skips if target already exists.
pub fn createSymlink(allocator: std.mem.Allocator, source_root: []const u8, target_root: []const u8, rel_path: []const u8, stderr_writer: anytype) !void {
    const source = try std.fs.path.join(allocator, &.{ source_root, rel_path });
    defer allocator.free(source);
    const target = try std.fs.path.join(allocator, &.{ target_root, rel_path });
    defer allocator.free(target);

    // Check source exists
    std.fs.accessAbsolute(source, .{}) catch {
        try stderr_writer.print("Skipping symlink {s}: source doesn't exist\n", .{rel_path});
        return;
    };

    // Check target doesn't already exist
    std.fs.accessAbsolute(target, .{}) catch |err| switch (err) {
        error.FileNotFound => {}, // Good
        else => return err,
    };
    if (std.fs.accessAbsolute(target, .{})) |_| {
        try stderr_writer.print("Skipping symlink {s}: already exists\n", .{rel_path});
        return;
    } else |_| {}

    // Ensure parent directory exists
    if (std.fs.path.dirname(target)) |parent| {
        std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    std.fs.symLinkAbsolute(source, target, .{}) catch {
        return error.SymlinkFailed;
    };

    try stderr_writer.print("Symlinked {s}\n", .{rel_path});
}
```

**Step 3: Implement runSetupCommands**

```zig
/// Run post-setup commands in the given working directory.
/// Warns on failure but continues to next command.
pub fn runSetupCommands(allocator: std.mem.Allocator, cwd: []const u8, commands: []const []const u8, stderr_writer: anytype) !void {
    for (commands) |cmd| {
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "sh", "-c", cmd },
            .cwd = cwd,
        }) catch |err| {
            try stderr_writer.print("Warning: failed to run '{s}': {any}\n", .{ cmd, err });
            continue;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code != 0) {
                    try stderr_writer.print("Warning: '{s}' exited with code {d}\n", .{ cmd, code });
                } else {
                    try stderr_writer.print("Ran: {s}\n", .{cmd});
                }
            },
            else => {
                try stderr_writer.print("Warning: '{s}' terminated abnormally\n", .{cmd});
            },
        }
    }
}
```

**Step 4: Add runAllSetup that ties everything together**

```zig
const config_mod = @import("config.zig");

/// Run all setup operations from a Config on a new worktree.
pub fn runAllSetup(allocator: std.mem.Allocator, cfg: config_mod.Config, main_path: []const u8, worktree_path: []const u8, stderr_writer: anytype) !void {
    // CoW copies
    for (cfg.copyPaths()) |path| {
        try cowCopy(allocator, main_path, worktree_path, path, stderr_writer);
    }

    // Symlinks
    for (cfg.symlinkPaths()) |path| {
        try createSymlink(allocator, main_path, worktree_path, path, stderr_writer);
    }

    // Run commands
    try runSetupCommands(allocator, worktree_path, cfg.runCommands(), stderr_writer);
}
```

**Step 5: Add import for config in setup.zig header**

Make sure setup.zig has the right imports. The `@import("config.zig")` works because both files are in the same `lib/` directory and config.zig is a module sibling.

**Step 6: Run tests (placeholder still passes)**

Run: `zig build test`
Expected: PASS (setup functions use real filesystem, tested in integration tests)

**Step 7: Commit**

```bash
git add src/lib/setup.zig
git commit -m "feat: setup operations - CoW copy, symlink, run commands"
```

---

### Task 6: List Command

**Files:**
- Create: `src/commands/list.zig`
- Modify: `src/main.zig`

**Step 1: Implement list command**

`src/commands/list.zig`:

```zig
const std = @import("std");
const git = @import("../lib/git.zig");

pub fn run(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Get current working directory to determine which worktree we're in
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    // Get worktree list
    const wt_output = git.runGit(allocator, null, &.{ "worktree", "list", "--porcelain" }) catch |err| {
        try stderr.print("Error: {any}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(wt_output);

    const worktrees = try git.parseWorktreeList(allocator, wt_output);
    defer allocator.free(worktrees);

    if (worktrees.len == 0) {
        try stderr.print("No worktrees found\n", .{});
        return;
    }

    // For each worktree, get status
    for (worktrees) |wt| {
        // Check if this is the current worktree
        const is_current = std.mem.startsWith(u8, cwd, wt.path);

        // Get status for this worktree
        const status_output = git.runGit(allocator, wt.path, &.{ "status", "--porcelain" }) catch {
            // If we can't get status, just show unknown
            const marker: []const u8 = if (is_current) "*" else " ";
            const branch_name = wt.branch orelse "(detached)";
            try stdout.print("{s} {s:<20} {s}\n", .{ marker, branch_name, wt.path });
            continue;
        };
        defer allocator.free(status_output);

        const status = git.parseStatusPorcelain(status_output);
        const marker: []const u8 = if (is_current) "*" else " ";
        const branch_name = wt.branch orelse "(detached)";

        if (status.modified == 0 and status.untracked == 0) {
            try stdout.print("{s} {s:<20} {s}  (clean)\n", .{ marker, branch_name, wt.path });
        } else {
            var buf: [64]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buf);
            const w = fbs.writer();

            if (status.modified > 0) {
                try w.print("{d} modified", .{status.modified});
            }
            if (status.untracked > 0) {
                if (status.modified > 0) try w.print(", ", .{});
                try w.print("{d} untracked", .{status.untracked});
            }

            try stdout.print("{s} {s:<20} {s}  ({s})\n", .{ marker, branch_name, wt.path, fbs.getWritten() });
        }
    }
}
```

**Step 2: Wire list into main.zig**

Update `src/main.zig`:

```zig
const std = @import("std");
const yazap = @import("yazap");
const list_cmd = @import("commands/list.zig");

const App = yazap.App;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.init(allocator, "wt", "Git worktree manager");
    defer app.deinit();

    var wt = app.rootCommand();
    wt.setProperty(.help_on_empty_args);

    try wt.addSubcommand(app.createCommand("list", "List all worktrees with status"));

    const matches = try app.parseProcess();

    if (matches.subcommandMatches("list")) |_| {
        try list_cmd.run(allocator);
    }
}
```

**Step 3: Build and manually test**

Run: `zig build`
Run: `zig build run -- list`
Expected: Shows at least the main worktree for the `wt` repo

**Step 4: Commit**

```bash
git add src/commands/list.zig src/main.zig
git commit -m "feat: wt list command shows worktrees with status"
```

---

### Task 7: New Command

**Files:**
- Create: `src/commands/new.zig`
- Modify: `src/main.zig`

**Step 1: Implement new command**

`src/commands/new.zig`:

```zig
const std = @import("std");
const git = @import("../lib/git.zig");
const worktree = @import("../lib/worktree.zig");
const config = @import("../lib/config.zig");
const setup = @import("../lib/setup.zig");

pub fn run(allocator: std.mem.Allocator, branch: []const u8, base: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Find main worktree
    const wt_output = try git.runGit(allocator, null, &.{ "worktree", "list", "--porcelain" });
    defer allocator.free(wt_output);

    const worktrees = try git.parseWorktreeList(allocator, wt_output);
    defer allocator.free(worktrees);

    if (worktrees.len == 0) {
        try stderr.print("Error: no worktrees found\n", .{});
        std.process.exit(1);
    }

    const main_path = worktrees[0].path;
    const wt_path = try worktree.computeWorktreePath(allocator, main_path, branch);
    defer allocator.free(wt_path);

    // Check if worktree already exists
    if (std.fs.accessAbsolute(wt_path, .{})) |_| {
        try stderr.print("Worktree already exists at {s}\n", .{wt_path});
        try stdout.print("{s}\n", .{wt_path});
        return;
    } else |_| {}

    // Check if branch already exists
    const branch_check = git.runGit(allocator, null, &.{ "rev-parse", "--verify", branch }) catch null;
    if (branch_check) |bc| allocator.free(bc);

    // Create worktree
    if (branch_check != null) {
        // Branch exists, check it's not already used by another worktree
        const wt_branches = try getWorktreeBranches(allocator, worktrees);
        defer allocator.free(wt_branches);

        for (wt_branches) |b| {
            if (std.mem.eql(u8, b, branch)) {
                try stderr.print("Error: branch '{s}' already used by another worktree\n", .{branch});
                std.process.exit(1);
            }
        }

        try stderr.print("Using existing branch '{s}'\n", .{branch});
        const add_result = git.runGit(allocator, null, &.{ "worktree", "add", wt_path, branch }) catch |err| {
            try stderr.print("Error creating worktree: {any}\n", .{err});
            std.process.exit(1);
        };
        allocator.free(add_result);
    } else {
        // Create new branch
        const add_result = git.runGit(allocator, null, &.{ "worktree", "add", "-b", branch, wt_path, base }) catch |err| {
            try stderr.print("Error creating worktree: {any}\n", .{err});
            std.process.exit(1);
        };
        allocator.free(add_result);
    }

    try stderr.print("Created worktree at {s}\n", .{wt_path});

    // Load config and run setup
    var cfg = try config.loadConfigFile(allocator, main_path);
    defer cfg.deinit();

    try setup.runAllSetup(allocator, cfg.value, main_path, wt_path, stderr);

    // Print path to stdout for scripting
    try stdout.print("{s}\n", .{wt_path});
}

fn getWorktreeBranches(allocator: std.mem.Allocator, worktrees: []const git.WorktreeInfo) ![]const []const u8 {
    var branches = std.ArrayList([]const u8).init(allocator);
    defer branches.deinit();

    for (worktrees) |wt| {
        if (wt.branch) |b| {
            try branches.append(b);
        }
    }

    return branches.toOwnedSlice();
}
```

**Step 2: Wire new command into main.zig**

Add to main.zig imports:

```zig
const new_cmd = @import("commands/new.zig");
```

Add subcommand definition (after list):

```zig
var cmd_new = app.createCommand("new", "Create a new worktree");
try cmd_new.addArg(yazap.Arg.positional("BRANCH", "Branch name", null));
try cmd_new.addArg(yazap.Arg.positional("BASE", "Base ref (default: HEAD)", null));
cmd_new.setProperty(.positional_arg_required);
try wt.addSubcommand(cmd_new);
```

Add match handler:

```zig
if (matches.subcommandMatches("new")) |new_matches| {
    const branch = new_matches.getSingleValue("BRANCH") orelse {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Error: branch name required\n", .{});
        std.process.exit(1);
    };
    const base = new_matches.getSingleValue("BASE") orelse "HEAD";
    try new_cmd.run(allocator, branch, base);
}
```

**Step 3: Build and manually test**

Run: `zig build`
Run: `zig build run -- new test-branch`
Expected: Creates worktree at `../wt--test-branch`, prints path

Clean up: `git worktree remove ../wt--test-branch && git branch -d test-branch`

**Step 4: Commit**

```bash
git add src/commands/new.zig src/main.zig
git commit -m "feat: wt new command creates worktrees with setup"
```

---

### Task 8: Rm Command

**Files:**
- Create: `src/commands/rm.zig`
- Modify: `src/main.zig`

**Step 1: Implement rm command**

`src/commands/rm.zig`:

```zig
const std = @import("std");
const git = @import("../lib/git.zig");
const worktree = @import("../lib/worktree.zig");

pub fn run(allocator: std.mem.Allocator, branch_arg: ?[]const u8, force: bool) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Get worktree list
    const wt_output = try git.runGit(allocator, null, &.{ "worktree", "list", "--porcelain" });
    defer allocator.free(wt_output);

    const worktrees = try git.parseWorktreeList(allocator, wt_output);
    defer allocator.free(worktrees);

    if (worktrees.len < 2) {
        try stderr.print("No secondary worktrees to remove\n", .{});
        return;
    }

    const main_path = worktrees[0].path;

    // Determine which branch to remove
    const branch = branch_arg orelse {
        // No branch specified: list worktrees for external picker
        for (worktrees[1..]) |wt| {
            const branch_name = wt.branch orelse "(detached)";

            // Check safety status
            const status_output = git.runGit(allocator, wt.path, &.{ "status", "--porcelain" }) catch {
                try stdout.print("{s}\t{s}\tunknown\n", .{ branch_name, wt.path });
                continue;
            };
            defer allocator.free(status_output);

            const status = git.parseStatusPorcelain(status_output);
            const safety: []const u8 = if (status.modified == 0 and status.untracked == 0) "safe" else "dirty";
            try stdout.print("{s}\t{s}\t{s}\n", .{ branch_name, wt.path, safety });
        }
        return;
    };

    // Find the worktree for this branch
    const wt_path = try worktree.computeWorktreePath(allocator, main_path, branch);
    defer allocator.free(wt_path);

    // Check it exists
    std.fs.accessAbsolute(wt_path, .{}) catch {
        try stderr.print("Error: worktree at {s} does not exist\n", .{wt_path});
        std.process.exit(1);
    };

    // Safety check: uncommitted changes
    if (!force) {
        const status_output = git.runGit(allocator, wt_path, &.{ "status", "--porcelain" }) catch |err| {
            try stderr.print("Warning: could not check status: {any}\n", .{err});
            // Continue anyway
            return;
        };
        defer allocator.free(status_output);

        const status = git.parseStatusPorcelain(status_output);
        if (status.modified > 0 or status.untracked > 0) {
            try stderr.print("Error: worktree has {d} modified and {d} untracked files\n", .{ status.modified, status.untracked });
            try stderr.print("Use --force to remove anyway\n", .{});
            std.process.exit(1);
        }
    }

    // Remove worktree
    const rm_result = git.runGit(allocator, null, &.{ "worktree", "remove", wt_path }) catch |err| {
        if (force) {
            // Try force remove
            const force_result = git.runGit(allocator, null, &.{ "worktree", "remove", "--force", wt_path }) catch |err2| {
                try stderr.print("Error: could not remove worktree: {any}\n", .{err2});
                std.process.exit(1);
            };
            allocator.free(force_result);
        } else {
            try stderr.print("Error: could not remove worktree: {any}\n", .{err});
            std.process.exit(1);
        }
        return;
    };
    allocator.free(rm_result);

    try stderr.print("Removed worktree {s}\n", .{wt_path});

    // Check if branch has unmerged commits; delete if fully merged
    const merge_check = git.runGit(allocator, main_path, &.{ "branch", "-d", branch }) catch {
        try stderr.print("Branch '{s}' kept (has unmerged commits or could not delete)\n", .{branch});
        return;
    };
    allocator.free(merge_check);

    try stderr.print("Deleted merged branch '{s}'\n", .{branch});
}
```

**Step 2: Wire rm into main.zig**

Add import:

```zig
const rm_cmd = @import("commands/rm.zig");
```

Add subcommand:

```zig
var cmd_rm = app.createCommand("rm", "Remove a worktree");
try cmd_rm.addArg(yazap.Arg.positional("BRANCH", "Branch name (omit for picker list)", null));
try cmd_rm.addArg(yazap.Arg.booleanOption("force", 'f', "Force removal even with uncommitted changes"));
try wt.addSubcommand(cmd_rm);
```

Add handler:

```zig
if (matches.subcommandMatches("rm")) |rm_matches| {
    const branch = rm_matches.getSingleValue("BRANCH");
    const force = rm_matches.containsArg("force");
    try rm_cmd.run(allocator, branch, force);
}
```

**Step 3: Build and manually test**

Run: `zig build`

Test picker mode: `zig build run -- rm`
Expected: Lists worktrees (if any) with safety status

Test with branch: Create a test worktree first, then remove it:
```bash
zig build run -- new test-rm
zig build run -- rm test-rm
```

**Step 4: Commit**

```bash
git add src/commands/rm.zig src/main.zig
git commit -m "feat: wt rm command with safety checks and branch cleanup"
```

---

### Task 9: Shell Init Command

**Files:**
- Create: `src/commands/shell_init.zig`
- Modify: `src/main.zig`

**Step 1: Implement shell init**

`src/commands/shell_init.zig`:

```zig
const std = @import("std");

const zsh_init =
    \\# wt shell integration
    \\# Add to .zshrc: eval "$(wt shell-init zsh)"
    \\
    \\wt() {
    \\    case "$1" in
    \\        new)
    \\            local output
    \\            output=$(command wt new "${@:2}" 2>/dev/tty)
    \\            local exit_code=$?
    \\            if [ $exit_code -eq 0 ] && [ -n "$output" ] && [ -d "$output" ]; then
    \\                cd "$output"
    \\            fi
    \\            return $exit_code
    \\            ;;
    \\        *)
    \\            command wt "$@"
    \\            ;;
    \\    esac
    \\}
;

const bash_init =
    \\# wt shell integration
    \\# Add to .bashrc: eval "$(wt shell-init bash)"
    \\
    \\wt() {
    \\    case "$1" in
    \\        new)
    \\            local output
    \\            output=$(command wt new "${@:2}" 2>/dev/tty)
    \\            local exit_code=$?
    \\            if [ $exit_code -eq 0 ] && [ -n "$output" ] && [ -d "$output" ]; then
    \\                cd "$output"
    \\            fi
    \\            return $exit_code
    \\            ;;
    \\        *)
    \\            command wt "$@"
    \\            ;;
    \\    esac
    \\}
;

pub fn run(shell: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    if (std.mem.eql(u8, shell, "zsh")) {
        try stdout.print("{s}\n", .{zsh_init});
    } else if (std.mem.eql(u8, shell, "bash")) {
        try stdout.print("{s}\n", .{bash_init});
    } else {
        try stderr.print("Unsupported shell: {s}. Supported: zsh, bash\n", .{shell});
        std.process.exit(1);
    }
}
```

**Step 2: Add test for shell init output**

```zig
test "zsh init contains function definition" {
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "wt()") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "cd \"$output\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_init, "command wt") != null);
}

test "bash init contains function definition" {
    try std.testing.expect(std.mem.indexOf(u8, bash_init, "wt()") != null);
}
```

**Step 3: Wire into main.zig**

Add import:

```zig
const shell_init_cmd = @import("commands/shell_init.zig");
```

Add subcommand:

```zig
var cmd_shell_init = app.createCommand("shell-init", "Output shell integration function");
try cmd_shell_init.addArg(yazap.Arg.positional("SHELL", "Shell name: zsh, bash", null));
cmd_shell_init.setProperty(.positional_arg_required);
try wt.addSubcommand(cmd_shell_init);
```

Add handler:

```zig
if (matches.subcommandMatches("shell-init")) |si_matches| {
    const shell = si_matches.getSingleValue("SHELL") orelse {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Error: shell name required (zsh, bash)\n", .{});
        std.process.exit(1);
    };
    try shell_init_cmd.run(shell);
}
```

**Step 4: Build and test**

Run: `zig build test`
Expected: PASS

Run: `zig build run -- shell-init zsh`
Expected: Outputs shell function

**Step 5: Commit**

```bash
git add src/commands/shell_init.zig src/main.zig
git commit -m "feat: wt shell-init for zsh and bash cd integration"
```

---

### Task 10: Integration Tests

**Files:**
- Create: `src/test_integration.zig`
- Modify: `build.zig` (add integration test step)

**Step 1: Add integration test build step**

In `build.zig`, after the unit test step, add:

```zig
// Integration tests
const integration_tests = b.addTest(.{
    .root_source_file = b.path("src/test_integration.zig"),
    .target = target,
    .optimize = optimize,
});
integration_tests.root_module.addImport("toml", toml_dep.module("toml"));

const run_integration_tests = b.addRunArtifact(integration_tests);
const integration_test_step = b.step("test-integration", "Run integration tests");
integration_test_step.dependOn(&run_integration_tests.step);
```

**Step 2: Create test helper for git repos**

`src/test_integration.zig`:

```zig
const std = @import("std");
const git_mod = @import("lib/git.zig");
const worktree_mod = @import("lib/worktree.zig");
const config_mod = @import("lib/config.zig");
const setup_mod = @import("lib/setup.zig");

/// Create a temporary git repo for testing.
/// Returns the absolute path (allocated, caller must free).
fn createTempGitRepo(allocator: std.mem.Allocator) ![]u8 {
    var tmp = std.testing.tmpDir(.{});
    // Note: we intentionally do NOT defer tmp.cleanup() here --
    // the caller is responsible for cleanup.

    // Get the absolute path
    const path = try tmp.dir.realpathAlloc(allocator, ".");

    // git init
    const init_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "init" },
        .cwd = path,
    });
    allocator.free(init_result.stdout);
    allocator.free(init_result.stderr);

    // Configure git user for commits
    const config1 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "config", "user.email", "test@test.com" },
        .cwd = path,
    });
    allocator.free(config1.stdout);
    allocator.free(config1.stderr);

    const config2 = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "config", "user.name", "Test" },
        .cwd = path,
    });
    allocator.free(config2.stdout);
    allocator.free(config2.stderr);

    // Create initial commit
    const touch = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "commit", "--allow-empty", "-m", "initial" },
        .cwd = path,
    });
    allocator.free(touch.stdout);
    allocator.free(touch.stderr);

    return path;
}

fn cleanupTempRepo(allocator: std.mem.Allocator, path: []const u8) void {
    // Remove all worktrees first, then delete the directory
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "rm", "-rf", path },
    }) catch return;
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}

test "integration: git worktree list in fresh repo" {
    const allocator = std.testing.allocator;
    const repo_path = try createTempGitRepo(allocator);
    defer {
        cleanupTempRepo(allocator, repo_path);
        allocator.free(repo_path);
    }

    const output = try git_mod.runGit(allocator, repo_path, &.{ "worktree", "list", "--porcelain" });
    defer allocator.free(output);

    const worktrees = try git_mod.parseWorktreeList(allocator, output);
    defer allocator.free(worktrees);

    try std.testing.expectEqual(@as(usize, 1), worktrees.len);
    try std.testing.expectEqualStrings(repo_path, worktrees[0].path);
}

test "integration: create and list worktree" {
    const allocator = std.testing.allocator;
    const repo_path = try createTempGitRepo(allocator);
    defer {
        // Clean up worktree dir too
        const wt_path = try worktree_mod.computeWorktreePath(allocator, repo_path, "test-branch");
        cleanupTempRepo(allocator, wt_path);
        allocator.free(wt_path);
        cleanupTempRepo(allocator, repo_path);
        allocator.free(repo_path);
    }

    // Create worktree
    const wt_path = try worktree_mod.computeWorktreePath(allocator, repo_path, "test-branch");
    defer allocator.free(wt_path);

    const add_result = try git_mod.runGit(allocator, repo_path, &.{ "worktree", "add", "-b", "test-branch", wt_path });
    allocator.free(add_result);

    // List worktrees
    const output = try git_mod.runGit(allocator, repo_path, &.{ "worktree", "list", "--porcelain" });
    defer allocator.free(output);

    const worktrees = try git_mod.parseWorktreeList(allocator, output);
    defer allocator.free(worktrees);

    try std.testing.expectEqual(@as(usize, 2), worktrees.len);
    try std.testing.expectEqualStrings("test-branch", worktrees[1].branch.?);
}

test "integration: config loading from file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Write a .wt.toml
    const file = try tmp.dir.createFile(".wt.toml", .{});
    try file.writeAll(
        \\[copy]
        \\paths = ["deps"]
        \\
        \\[symlink]
        \\paths = ["mise.local.toml"]
        \\
        \\[run]
        \\commands = ["echo setup done"]
    );
    file.close();

    const path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var cfg = try config_mod.loadConfigFile(allocator, path);
    defer cfg.deinit();

    try std.testing.expectEqual(@as(usize, 1), cfg.value.copyPaths().len);
    try std.testing.expectEqualStrings("deps", cfg.value.copyPaths()[0]);
    try std.testing.expectEqual(@as(usize, 1), cfg.value.symlinkPaths().len);
    try std.testing.expectEqual(@as(usize, 1), cfg.value.runCommands().len);
}

test "integration: config loading missing file returns empty" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(path);

    var cfg = try config_mod.loadConfigFile(allocator, path);
    defer cfg.deinit();

    try std.testing.expectEqual(@as(usize, 0), cfg.value.copyPaths().len);
    try std.testing.expectEqual(@as(usize, 0), cfg.value.symlinkPaths().len);
    try std.testing.expectEqual(@as(usize, 0), cfg.value.runCommands().len);
}
```

**Step 3: Run integration tests**

Run: `zig build test-integration`
Expected: All pass

**Step 4: Commit**

```bash
git add src/test_integration.zig build.zig
git commit -m "feat: integration tests for git, config, and worktree operations"
```

---

### Task 11: Dogfooding & Polish

**Files:**
- Create: `.wt.toml`
- Verify all commands work end-to-end

**Step 1: Create .wt.toml for this project**

```toml
[symlink]
paths = ["mise.local.toml"]

[run]
commands = ["mise install"]
```

**Step 2: End-to-end test**

```bash
# Build
zig build

# List
zig build run -- list

# Create a test worktree
zig build run -- new test-dogfood

# Verify it exists
ls ../wt--test-dogfood

# List again -- should show both
zig build run -- list

# Remove it
zig build run -- rm test-dogfood

# Verify it's gone
zig build run -- list

# Shell init
zig build run -- shell-init zsh

# Help
zig build run -- --help
```

**Step 3: Fix any issues found during dogfooding**

Address edge cases discovered during manual testing.

**Step 4: Commit**

```bash
git add .wt.toml
git commit -m "feat: add .wt.toml for dogfooding"
```

---

## Notes for Implementer

### Zig Version Compatibility

This plan targets **Zig 0.14.x**. If mise installs 0.15.x instead:
- `pub fn main() !void` becomes `pub fn main(init: std.process.Init) anyerror!void`
- Use `init.gpa` instead of creating a `GeneralPurposeAllocator`
- `std.io.getStdOut()` becomes `std.fs.File.stdout()`
- yazap tag becomes `0.7.0`, zig-toml uses `master` branch
- `app.parseProcess()` becomes `app.parseProcess(init.io, init.minimal.args)`

### yazap API Cautions

The yazap API may differ slightly from what's shown here. Key things to verify:
- `app.createCommand()` returns a `Command` value (not pointer)
- `Arg.positional()` third parameter is the index (pass `null` for auto)
- `app.parseProcess()` may or may not take parameters depending on version

### zig-toml Struct Mapping

The TOML-to-struct mapping requires `*Struct` (pointer) for nested tables. If the parser complains about the `Config` struct definition, try wrapping nested sections as pointers:
```zig
copy: ?*CopyConfig = null,
```
vs
```zig
copy: CopyConfig = .{},
```

Experiment to see what works with the actual library version.

### Testing Philosophy

- Unit tests (in each `.zig` file): Fast, no external dependencies, test parsing logic
- Integration tests (`test_integration.zig`): Create real git repos, test real filesystem operations
- Manual testing: Run the actual binary against this repo

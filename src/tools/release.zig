const builtin = @import("builtin");
const std = @import("std");

const Allocator = std.mem.Allocator;
const max_file_size: usize = 16 * 1024 * 1024;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) return usage();

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "validate")) {
        const version = try requiredFlag(args[2..], "--version");
        try validateRelease(allocator, version);
        return;
    }
    if (std.mem.eql(u8, cmd, "extract-notes")) {
        const version = try requiredFlag(args[2..], "--version");
        const out_path = try requiredFlag(args[2..], "--out");
        try extractNotesToFile(allocator, version, out_path);
        return;
    }
    if (std.mem.eql(u8, cmd, "verify-host")) {
        const version = try requiredFlag(args[2..], "--version");
        const build_root = try requiredFlag(args[2..], "--build-root");
        try verifyHostArtifact(allocator, version, build_root);
        return;
    }
    if (std.mem.eql(u8, cmd, "package")) {
        const version = try requiredFlag(args[2..], "--version");
        const build_root = try requiredFlag(args[2..], "--build-root");
        const dist_dir = try requiredFlag(args[2..], "--dist-dir");
        try packageArchives(allocator, version, build_root, dist_dir);
        return;
    }
    if (std.mem.eql(u8, cmd, "verify-checksums")) {
        const dist_dir = try requiredFlag(args[2..], "--dist-dir");
        try verifySha256SumsFile(allocator, dist_dir);
        return;
    }

    return usage();
}

fn usage() !void {
    std.debug.print(
        \\Usage:
        \\  release validate --version <X.Y.Z>
        \\  release extract-notes --version <X.Y.Z> --out <path>
        \\  release verify-host --version <X.Y.Z> --build-root <path>
        \\  release package --version <X.Y.Z> --build-root <path> --dist-dir <path>
        \\  release verify-checksums --dist-dir <path>
        \\
    , .{});
    return error.ReleaseToolFailed;
}

fn fail(comptime fmt: []const u8, args: anytype) error{ReleaseToolFailed} {
    if (!builtin.is_test) {
        std.debug.print("error: " ++ fmt ++ "\n", args);
    }
    return error.ReleaseToolFailed;
}

fn requiredFlag(args: []const []const u8, name: []const u8) ![]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], name)) {
            if (i + 1 >= args.len) return fail("missing value for {s}", .{name});
            return args[i + 1];
        }
    }
    return fail("missing required flag {s}", .{name});
}

fn runExitCode(allocator: Allocator, cwd: ?[]const u8, argv: []const []const u8) !u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return switch (result.term) {
        .Exited => |code| code,
        else => 1,
    };
}

fn runChecked(allocator: Allocator, cwd: ?[]const u8, argv: []const []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd,
    });
    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return switch (result.term) {
        .Exited => |code| if (code == 0) result.stdout else fail("command failed ({s})", .{argv[0]}),
        else => fail("command failed ({s})", .{argv[0]}),
    };
}

fn runNoCaptureChecked(allocator: Allocator, cwd: ?[]const u8, argv: []const []const u8) !void {
    const code = try runExitCode(allocator, cwd, argv);
    if (code != 0) return fail("command failed ({s})", .{argv[0]});
}

fn trimCopy(allocator: Allocator, value: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    return allocator.dupe(u8, trimmed);
}

fn gitRepoRoot(allocator: Allocator) ![]u8 {
    const out = try runChecked(allocator, null, &.{ "git", "rev-parse", "--show-toplevel" });
    defer allocator.free(out);
    return trimCopy(allocator, out);
}

pub fn isValidSemver(version: []const u8) bool {
    var it = std.mem.splitScalar(u8, version, '.');
    var count: usize = 0;
    while (it.next()) |part| {
        if (part.len == 0) return false;
        for (part) |ch| {
            if (!std.ascii.isDigit(ch)) return false;
        }
        count += 1;
    }
    return count == 3;
}

fn ensureSemver(version: []const u8) !void {
    if (!isValidSemver(version)) return fail("version must match X.Y.Z", .{});
}

pub fn extractZonVersionAlloc(allocator: Allocator, content: []const u8) ![]u8 {
    const marker = ".version = \"";
    const start = std.mem.indexOf(u8, content, marker) orelse return fail("build.zig.zon is missing .version", .{});
    const rest = content[start + marker.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return fail("build.zig.zon has malformed .version", .{});
    return allocator.dupe(u8, rest[0..end]);
}

pub fn extractBuildFallbackVersionAlloc(allocator: Allocator, content: []const u8) ![]u8 {
    const marker = "orelse \"";
    const start = std.mem.indexOf(u8, content, marker) orelse return fail("build.zig is missing fallback version", .{});
    const rest = content[start + marker.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return fail("build.zig has malformed fallback version", .{});
    return allocator.dupe(u8, rest[0..end]);
}

pub fn extractChangelogSectionAlloc(allocator: Allocator, changelog: []const u8, version: []const u8) ![]u8 {
    const heading = try std.fmt.allocPrint(allocator, "## [{s}]", .{version});
    defer allocator.free(heading);

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var capture = false;
    var lines = std.mem.splitScalar(u8, changelog, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (std.mem.startsWith(u8, line, "## [")) {
            if (capture) break;
            if (std.mem.startsWith(u8, line, heading)) capture = true;
        }

        if (capture) {
            try out.appendSlice(line);
            try out.append('\n');
        }
    }

    if (!capture) return fail("CHANGELOG.md is missing section for {s}", .{version});
    if (out.items.len == 0) return fail("release notes extracted from CHANGELOG.md are empty", .{});

    return out.toOwnedSlice();
}

fn extractNotesToFile(allocator: Allocator, version: []const u8, out_path: []const u8) !void {
    const repo_root = try gitRepoRoot(allocator);
    defer allocator.free(repo_root);

    const changelog_path = try std.fs.path.join(allocator, &.{ repo_root, "CHANGELOG.md" });
    defer allocator.free(changelog_path);

    const changelog = try std.fs.cwd().readFileAlloc(allocator, changelog_path, max_file_size);
    defer allocator.free(changelog);

    const notes = try extractChangelogSectionAlloc(allocator, changelog, version);
    defer allocator.free(notes);

    if (std.fs.path.dirname(out_path)) |parent| {
        try std.fs.cwd().makePath(parent);
    }

    const file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(notes);
}

fn validateRelease(allocator: Allocator, version: []const u8) !void {
    try ensureSemver(version);

    const tag = try std.fmt.allocPrint(allocator, "v{s}", .{version});
    defer allocator.free(tag);

    const repo_root = try gitRepoRoot(allocator);
    defer allocator.free(repo_root);

    const branch_raw = try runChecked(allocator, repo_root, &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" });
    defer allocator.free(branch_raw);
    const branch = std.mem.trim(u8, branch_raw, " \t\r\n");
    if (!std.mem.eql(u8, branch, "main")) return fail("must release from main (current: {s})", .{branch});

    if ((try runExitCode(allocator, repo_root, &.{ "git", "diff", "--quiet" })) != 0) {
        return fail("working tree must be clean", .{});
    }
    if ((try runExitCode(allocator, repo_root, &.{ "git", "diff", "--cached", "--quiet" })) != 0) {
        return fail("working tree must be clean", .{});
    }

    const untracked = try runChecked(allocator, repo_root, &.{ "git", "ls-files", "--others", "--exclude-standard" });
    defer allocator.free(untracked);
    if (std.mem.trim(u8, untracked, " \t\r\n").len != 0) {
        return fail("working tree has untracked files", .{});
    }

    if ((try runExitCode(allocator, repo_root, &.{ "git", "remote", "get-url", "github" })) != 0) {
        return fail("missing github remote", .{});
    }

    if ((try runExitCode(allocator, repo_root, &.{ "mise", "x", "--", "gh", "auth", "status" })) != 0) {
        return fail("gh authentication required (run: mise x -- gh auth login)", .{});
    }

    try runNoCaptureChecked(allocator, repo_root, &.{ "git", "fetch", "github", "main", "--tags" });

    if ((try runExitCode(allocator, repo_root, &.{ "git", "merge-base", "--is-ancestor", "github/main", "HEAD" })) != 0) {
        return fail("local main is behind github/main; pull or rebase first", .{});
    }

    const local_tag_ref = try std.fmt.allocPrint(allocator, "refs/tags/{s}", .{tag});
    defer allocator.free(local_tag_ref);
    if ((try runExitCode(allocator, repo_root, &.{ "git", "rev-parse", "-q", "--verify", local_tag_ref })) == 0) {
        return fail("local tag already exists: {s}", .{tag});
    }

    const remote_tag_ref = try std.fmt.allocPrint(allocator, "refs/tags/{s}", .{tag});
    defer allocator.free(remote_tag_ref);
    if ((try runExitCode(allocator, repo_root, &.{ "git", "ls-remote", "--exit-code", "--tags", "github", remote_tag_ref })) == 0) {
        return fail("remote tag already exists: {s}", .{tag});
    }

    const zon_path = try std.fs.path.join(allocator, &.{ repo_root, "build.zig.zon" });
    defer allocator.free(zon_path);
    const zon_content = try std.fs.cwd().readFileAlloc(allocator, zon_path, max_file_size);
    defer allocator.free(zon_content);
    const zon_version = try extractZonVersionAlloc(allocator, zon_content);
    defer allocator.free(zon_version);
    if (!std.mem.eql(u8, zon_version, version)) {
        return fail("build.zig.zon version ({s}) does not match requested version ({s})", .{ zon_version, version });
    }

    const build_path = try std.fs.path.join(allocator, &.{ repo_root, "build.zig" });
    defer allocator.free(build_path);
    const build_content = try std.fs.cwd().readFileAlloc(allocator, build_path, max_file_size);
    defer allocator.free(build_content);
    const fallback_version = try extractBuildFallbackVersionAlloc(allocator, build_content);
    defer allocator.free(fallback_version);
    if (!std.mem.eql(u8, fallback_version, version)) {
        return fail("build.zig fallback version ({s}) does not match requested version ({s})", .{ fallback_version, version });
    }
}

const TargetArchive = struct {
    build_dir: []const u8,
    output_suffix: []const u8,
    bin_name: []const u8,
    use_zip: bool,
};

fn appendArchive(allocator: Allocator, list: *std.array_list.Managed([]u8), name: []const u8) !void {
    try list.append(try allocator.dupe(u8, name));
}

fn cleanupStrings(allocator: Allocator, list: []const []u8) void {
    for (list) |item| allocator.free(item);
}

fn packageArchives(allocator: Allocator, version: []const u8, build_root: []const u8, dist_dir: []const u8) !void {
    try ensureSemver(version);
    try std.fs.cwd().makePath(dist_dir);

    const tag = try std.fmt.allocPrint(allocator, "v{s}", .{version});
    defer allocator.free(tag);

    const archives = [_]TargetArchive{
        .{ .build_dir = "aarch64-macos", .output_suffix = "darwin-arm64.tar.gz", .bin_name = "wt", .use_zip = false },
        .{ .build_dir = "x86_64-macos", .output_suffix = "darwin-amd64.tar.gz", .bin_name = "wt", .use_zip = false },
        .{ .build_dir = "aarch64-linux", .output_suffix = "linux-arm64.tar.gz", .bin_name = "wt", .use_zip = false },
        .{ .build_dir = "x86_64-linux", .output_suffix = "linux-amd64.tar.gz", .bin_name = "wt", .use_zip = false },
        .{ .build_dir = "x86_64-windows", .output_suffix = "windows-amd64.zip", .bin_name = "wt.exe", .use_zip = true },
    };

    var created = std.array_list.Managed([]u8).init(allocator);
    defer {
        cleanupStrings(allocator, created.items);
        created.deinit();
    }

    for (archives) |archive| {
        const output_name = try std.fmt.allocPrint(allocator, "wt-{s}-{s}", .{ tag, archive.output_suffix });
        defer allocator.free(output_name);

        const output_path = try std.fs.path.join(allocator, &.{ dist_dir, output_name });
        defer allocator.free(output_path);

        const bin_dir = try std.fs.path.join(allocator, &.{ build_root, archive.build_dir, "bin" });
        defer allocator.free(bin_dir);

        if (archive.use_zip) {
            try runNoCaptureChecked(allocator, bin_dir, &.{ "zip", "-q", output_path, archive.bin_name });
        } else {
            try runNoCaptureChecked(allocator, null, &.{ "tar", "-C", bin_dir, "-czf", output_path, archive.bin_name });
        }

        try appendArchive(allocator, &created, output_name);
    }

    const sums_path = try std.fs.path.join(allocator, &.{ dist_dir, "SHA256SUMS" });
    defer allocator.free(sums_path);

    const sums_file = try std.fs.cwd().createFile(sums_path, .{ .truncate = true });
    defer sums_file.close();

    for (created.items) |archive_name| {
        const file_path = try std.fs.path.join(allocator, &.{ dist_dir, archive_name });
        defer allocator.free(file_path);

        const hash = try sha256FileHexAlloc(allocator, file_path);
        defer allocator.free(hash);

        const line = try std.fmt.allocPrint(allocator, "{s}  {s}\n", .{ hash, archive_name });
        defer allocator.free(line);
        try sums_file.writeAll(line);
    }

    try verifySha256SumsFile(allocator, dist_dir);
}

pub fn sha256FileHexAlloc(allocator: Allocator, file_path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [16 * 1024]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    return allocator.dupe(u8, hex[0..]);
}

pub fn verifySha256SumsContent(allocator: Allocator, dist_dir: []const u8, sums_content: []const u8) !void {
    var lines = std.mem.splitScalar(u8, sums_content, '\n');
    var checked: usize = 0;

    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        if (line.len < 67) return fail("SHA256SUMS line is malformed", .{});
        const expected = line[0..64];
        if (line[64] != ' ' or line[65] != ' ') return fail("SHA256SUMS line is malformed", .{});
        const filename = line[66..];
        if (filename.len == 0) return fail("SHA256SUMS line is malformed", .{});

        for (expected) |ch| {
            if (!std.ascii.isHex(ch)) return fail("SHA256SUMS has non-hex digest", .{});
        }

        const file_path = try std.fs.path.join(allocator, &.{ dist_dir, filename });
        defer allocator.free(file_path);

        const actual = try sha256FileHexAlloc(allocator, file_path);
        defer allocator.free(actual);

        if (!std.ascii.eqlIgnoreCase(expected, actual)) {
            return fail("checksum mismatch for {s}", .{filename});
        }

        checked += 1;
    }

    if (checked == 0) return fail("SHA256SUMS has no entries", .{});
}

fn verifySha256SumsFile(allocator: Allocator, dist_dir: []const u8) !void {
    const sums_path = try std.fs.path.join(allocator, &.{ dist_dir, "SHA256SUMS" });
    defer allocator.free(sums_path);

    const content = try std.fs.cwd().readFileAlloc(allocator, sums_path, max_file_size);
    defer allocator.free(content);

    try verifySha256SumsContent(allocator, dist_dir, content);
}

fn verifyHostArtifact(allocator: Allocator, version: []const u8, build_root: []const u8) !void {
    const target_dir: ?[]const u8 = switch (builtin.os.tag) {
        .macos => switch (builtin.cpu.arch) {
            .aarch64 => "aarch64-macos",
            .x86_64 => "x86_64-macos",
            else => null,
        },
        .linux => switch (builtin.cpu.arch) {
            .aarch64 => "aarch64-linux",
            .x86_64 => "x86_64-linux",
            else => null,
        },
        else => null,
    };

    if (target_dir == null) return;

    const bin_path = try std.fs.path.join(allocator, &.{ build_root, target_dir.?, "bin", "wt" });
    defer allocator.free(bin_path);

    const output = try runChecked(allocator, null, &.{ bin_path, "--version" });
    defer allocator.free(output);

    const trimmed = std.mem.trim(u8, output, " \t\r\n");
    const prefix = try std.fmt.allocPrint(allocator, "wt {s} (", .{version});
    defer allocator.free(prefix);

    if (!std.mem.startsWith(u8, trimmed, prefix) or !std.mem.endsWith(u8, trimmed, ")")) {
        return fail("host artifact version check failed: {s}", .{trimmed});
    }
}

const std = @import("std");

fn resolveGitSha(b: *std.Build) []const u8 {
    var code: u8 = 0;
    const output = b.runAllowFail(&.{ "git", "rev-parse", "--short", "HEAD" }, &code, .Ignore) catch {
        return "unknown";
    };
    defer b.allocator.free(output);

    const trimmed = std.mem.trim(u8, output, " \t\r\n");
    if (trimmed.len == 0) return "unknown";

    return b.allocator.dupe(u8, trimmed) catch "unknown";
}

fn addHelpSmokeCheck(
    b: *std.Build,
    test_step: *std.Build.Step,
    exe: *std.Build.Step.Compile,
    args: []const []const u8,
    expected_usage: []const u8,
) void {
    const run_help = b.addRunArtifact(exe);
    run_help.addArgs(args);
    run_help.addCheck(.{ .expect_stdout_match = expected_usage });
    run_help.expectStdErrEqual("");
    run_help.expectExitCode(0);
    test_step.dependOn(&run_help.step);
}

fn appendCliTestFilters(
    out: [][]const u8,
    start_index: usize,
    args: []const []const u8,
) usize {
    var next_index = start_index;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--test-filter")) {
            if (i + 1 < args.len) {
                i += 1;
                const filter = args[i];
                if (filter.len != 0) {
                    out[next_index] = filter;
                    next_index += 1;
                }
            }
            continue;
        }

        const prefix = "--test-filter=";
        if (std.mem.startsWith(u8, arg, prefix)) {
            const filter = arg[prefix.len..];
            if (filter.len != 0) {
                out[next_index] = filter;
                next_index += 1;
            }
        }
    }

    return next_index;
}

fn countCliTestFilters(args: []const []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--test-filter")) {
            if (i + 1 < args.len) {
                i += 1;
                if (args[i].len != 0) count += 1;
            }
            continue;
        }

        const prefix = "--test-filter=";
        if (std.mem.startsWith(u8, arg, prefix) and arg.len > prefix.len) {
            count += 1;
        }
    }

    return count;
}

fn collectTestFilters(b: *std.Build) []const []const u8 {
    const option_filter = b.option([]const u8, "test_filter", "Only run tests whose names contain this text");
    const cli_args = b.args orelse &.{};

    const option_count: usize = if (option_filter != null) 1 else 0;
    const cli_count = countCliTestFilters(cli_args);
    const total_count = option_count + cli_count;
    if (total_count == 0) return &.{};

    const filters = b.allocator.alloc([]const u8, total_count) catch @panic("OOM");
    var next_index: usize = 0;
    if (option_filter) |filter| {
        filters[next_index] = filter;
        next_index += 1;
    }
    next_index = appendCliTestFilters(filters, next_index, cli_args);
    return filters[0..next_index];
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const app_version = b.option([]const u8, "app_version", "Application version string") orelse "0.3.0";
    const git_sha = resolveGitSha(b);
    const test_filters = collectTestFilters(b);

    // Dependencies
    const zli_dep = b.dependency("zli", .{ .target = target, .optimize = optimize });
    const toml_dep = b.dependency("toml", .{ .target = target, .optimize = optimize });
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", app_version);
    build_options.addOption([]const u8, "git_sha", git_sha);

    // Executable
    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "wt",
        .root_module = exe_module,
    });
    exe.root_module.addImport("zli", zli_dep.module("zli"));
    exe.root_module.addImport("toml", toml_dep.module("toml"));
    exe.root_module.addOptions("build_options", build_options);
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the wt CLI");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const installed_wt_path = b.getInstallPath(.bin, "wt");

    const lib_test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_test_module.addImport("toml", toml_dep.module("toml"));
    const lib_tests = b.addTest(.{
        .root_module = lib_test_module,
        .filters = test_filters,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit and integration tests");
    test_step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_lib_tests.step);

    // Smoke-test help rendering paths so regressions fail `zig build test`.
    addHelpSmokeCheck(b, test_step, exe, &.{"--help"}, "Usage: wt [OPTIONS] [COMMAND]");
    addHelpSmokeCheck(b, test_step, exe, &.{ "list", "--help" }, "Usage: wt list [options]");
    addHelpSmokeCheck(b, test_step, exe, &.{ "__list", "--help" }, "Usage: wt __list [options]");
    addHelpSmokeCheck(b, test_step, exe, &.{ "new", "--help" }, "Usage: wt new [options] [BRANCH] [BASE]");
    addHelpSmokeCheck(b, test_step, exe, &.{ "__new", "--help" }, "Usage: wt __new [options] [BRANCH] [BASE]");
    addHelpSmokeCheck(b, test_step, exe, &.{ "rm", "--help" }, "Usage: wt rm [options] [BRANCH]");
    addHelpSmokeCheck(b, test_step, exe, &.{ "shell-init", "--help" }, "Usage: wt shell-init [options] [SHELL]");
    addHelpSmokeCheck(b, test_step, exe, &.{ "__pick-worktree", "--help" }, "Usage: wt __pick-worktree [options]");

    const wt_lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    wt_lib_module.addImport("toml", toml_dep.module("toml"));

    const integration_lib_test_module = b.createModule(.{
        .root_source_file = b.path("test/integration_lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_lib_test_module.addImport("wt_lib", wt_lib_module);
    integration_lib_test_module.addImport("toml", toml_dep.module("toml"));
    const integration_lib_tests = b.addTest(.{
        .root_module = integration_lib_test_module,
        .filters = test_filters,
    });
    const run_integration_lib_tests = b.addRunArtifact(integration_lib_tests);
    test_step.dependOn(&run_integration_lib_tests.step);

    const integration_workflow_test_module = b.createModule(.{
        .root_source_file = b.path("test/integration_workflow.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_workflow_test_module.addImport("wt_lib", wt_lib_module);
    integration_workflow_test_module.addImport("toml", toml_dep.module("toml"));
    const integration_workflow_tests = b.addTest(.{
        .root_module = integration_workflow_test_module,
        .filters = test_filters,
    });
    const run_integration_workflow_tests = b.addRunArtifact(integration_workflow_tests);
    test_step.dependOn(&run_integration_workflow_tests.step);

    const integration_init_detect_test_module = b.createModule(.{
        .root_source_file = b.path("test/integration_init_detect.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_init_detect_test_module.addImport("wt_lib", wt_lib_module);
    const integration_init_detect_tests = b.addTest(.{
        .root_module = integration_init_detect_test_module,
        .filters = test_filters,
    });
    const run_integration_init_detect_tests = b.addRunArtifact(integration_init_detect_tests);
    test_step.dependOn(&run_integration_init_detect_tests.step);

    const integration_shell_init_test_module = b.createModule(.{
        .root_source_file = b.path("test/integration_shell_init.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_shell_init_test_module.addImport("wt_root", lib_test_module);
    const integration_shell_init_tests = b.addTest(.{
        .root_module = integration_shell_init_test_module,
        .filters = test_filters,
    });
    const run_integration_shell_init_tests = b.addRunArtifact(integration_shell_init_tests);
    run_integration_shell_init_tests.step.dependOn(b.getInstallStep());
    run_integration_shell_init_tests.setEnvironmentVariable("WT_TEST_WT_BIN", installed_wt_path);
    test_step.dependOn(&run_integration_shell_init_tests.step);

    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&run_integration_lib_tests.step);
    integration_step.dependOn(&run_integration_workflow_tests.step);
    integration_step.dependOn(&run_integration_init_detect_tests.step);
    integration_step.dependOn(&run_integration_shell_init_tests.step);

    const release_tool_test_module = b.createModule(.{
        .root_source_file = b.path("test/release_tool_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const release_tool_module = b.createModule(.{
        .root_source_file = b.path("src/tools/release.zig"),
        .target = target,
        .optimize = optimize,
    });
    release_tool_test_module.addImport("release_tool", release_tool_module);
    const release_tool_tests = b.addTest(.{
        .root_module = release_tool_test_module,
        .filters = test_filters,
    });
    const run_release_tool_tests = b.addRunArtifact(release_tool_tests);
    test_step.dependOn(&run_release_tool_tests.step);
}

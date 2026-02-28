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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const app_version = b.option([]const u8, "app_version", "Application version string") orelse "0.2.0";
    const git_sha = resolveGitSha(b);

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
    const lib_test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_test_module.addImport("toml", toml_dep.module("toml"));
    const lib_tests = b.addTest(.{
        .root_module = lib_test_module,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit and integration tests");
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
    });
    const run_integration_workflow_tests = b.addRunArtifact(integration_workflow_tests);
    test_step.dependOn(&run_integration_workflow_tests.step);

    const integration_shell_init_test_module = b.createModule(.{
        .root_source_file = b.path("test/integration_shell_init.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_shell_init_test_module.addImport("wt_root", lib_test_module);
    const integration_shell_init_tests = b.addTest(.{
        .root_module = integration_shell_init_test_module,
    });
    const run_integration_shell_init_tests = b.addRunArtifact(integration_shell_init_tests);
    test_step.dependOn(&run_integration_shell_init_tests.step);

    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&run_integration_lib_tests.step);
    integration_step.dependOn(&run_integration_workflow_tests.step);
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
    });
    const run_release_tool_tests = b.addRunArtifact(release_tool_tests);
    test_step.dependOn(&run_release_tool_tests.step);
}

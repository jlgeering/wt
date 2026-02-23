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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const app_version = b.option([]const u8, "app_version", "Application version string") orelse "0.1.0";
    const git_sha = resolveGitSha(b);

    // Dependencies
    const yazap_dep = b.dependency("yazap", .{});
    const toml_dep = b.dependency("toml", .{});
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", app_version);
    build_options.addOption([]const u8, "git_sha", git_sha);

    // Executable
    const exe = b.addExecutable(.{
        .name = "wt",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("yazap", yazap_dep.module("yazap"));
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
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_tests.root_module.addImport("toml", toml_dep.module("toml"));
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit and integration tests");
    test_step.dependOn(&run_lib_tests.step);

    // Smoke-test help rendering paths so regressions fail `zig build test`.
    const run_help_root = b.addRunArtifact(exe);
    run_help_root.addArg("--help");
    test_step.dependOn(&run_help_root.step);

    const run_help_list = b.addRunArtifact(exe);
    run_help_list.addArgs(&.{ "list", "--help" });
    test_step.dependOn(&run_help_list.step);

    const run_help_rm = b.addRunArtifact(exe);
    run_help_rm.addArgs(&.{ "rm", "--help" });
    test_step.dependOn(&run_help_rm.step);

    const integration_lib_tests = b.addTest(.{
        .root_source_file = b.path("test/integration_lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib/root.zig"),
    });
    lib_module.addImport("toml", toml_dep.module("toml"));
    integration_lib_tests.root_module.addImport("wt_lib", lib_module);
    integration_lib_tests.root_module.addImport("toml", toml_dep.module("toml"));
    const run_integration_lib_tests = b.addRunArtifact(integration_lib_tests);
    test_step.dependOn(&run_integration_lib_tests.step);

    const integration_workflow_tests = b.addTest(.{
        .root_source_file = b.path("test/integration_workflow.zig"),
        .target = target,
        .optimize = optimize,
    });
    const workflow_lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib/root.zig"),
    });
    workflow_lib_module.addImport("toml", toml_dep.module("toml"));
    integration_workflow_tests.root_module.addImport("wt_lib", workflow_lib_module);
    integration_workflow_tests.root_module.addImport("toml", toml_dep.module("toml"));
    const run_integration_workflow_tests = b.addRunArtifact(integration_workflow_tests);
    test_step.dependOn(&run_integration_workflow_tests.step);

    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&run_integration_lib_tests.step);
    integration_step.dependOn(&run_integration_workflow_tests.step);
}

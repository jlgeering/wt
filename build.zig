const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const yazap_dep = b.dependency("yazap", .{});
    const toml_dep = b.dependency("toml", .{});

    // Executable
    const exe = b.addExecutable(.{
        .name = "wt",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("yazap", yazap_dep.module("yazap"));
    exe.root_module.addImport("toml", toml_dep.module("toml"));
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the wt CLI");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
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

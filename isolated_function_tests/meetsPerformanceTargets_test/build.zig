const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Executable for main function
    const exe = b.addExecutable(.{
        .name = "test_meetsPerformanceTargets",
        .root_source_file = b.path("test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the test");
    run_step.dependOn(&run_cmd.step);

    // Test command
    const test_cmd = b.addTest(.{
        .root_source_file = b.path("test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_cmd.step);
}
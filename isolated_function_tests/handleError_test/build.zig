const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create executable for running the function
    const exe = b.addExecutable(.{
        .name = "handleError_test_runner",
        .root_source_file = b.path("test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the handleError test");
    run_step.dependOn(&run_cmd.step);

    // Create test executable
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
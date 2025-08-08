const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create executable for testing the function
    const exe = b.addExecutable(.{
        .name = "clearConflictingRestInfo_test",
        .root_source_file = b.path("test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Create run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the function test");
    run_step.dependOn(&run_cmd.step);

    // Create test step
    const test_exe = b.addTest(.{
        .root_source_file = b.path("test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_exe.step);
}
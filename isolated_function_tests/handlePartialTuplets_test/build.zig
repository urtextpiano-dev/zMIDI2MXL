const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Create executable
    const exe = b.addExecutable(.{
        .name = "handlePartialTuplets_test",
        .root_source_file = b.path("test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    
    // Create run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    const run_step = b.step("run", "Run the test");
    run_step.dependOn(&run_cmd.step);
    
    // Create test command
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
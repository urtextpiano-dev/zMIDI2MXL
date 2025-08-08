const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Create the main executable
    const exe = b.addExecutable(.{
        .name = "zmidi2mxl",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Add integration tests
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("test/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add the main module as a dependency to integration tests
    integration_tests.root_module.addImport("main", exe.root_module);

    const run_integration_tests = b.addRunArtifact(integration_tests);
    
    // Add educational integration tests (TASK-INT-004)
    const educational_integration_tests = b.addTest(.{
        .root_source_file = b.path("test/educational_integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add the main module as a dependency to educational integration tests
    educational_integration_tests.root_module.addImport("zmidi2mxl", exe.root_module);
    
    const run_educational_integration_tests = b.addRunArtifact(educational_integration_tests);

    // Add zip_writer tests
    const zip_writer_tests = b.addTest(.{
        .root_source_file = b.path("src/mxl/zip_writer.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const run_zip_writer_tests = b.addRunArtifact(zip_writer_tests);
    
    // Add rest_optimizer tests
    const rest_optimizer_tests = b.addTest(.{
        .root_source_file = b.path("src/timing/rest_optimizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const run_rest_optimizer_tests = b.addRunArtifact(rest_optimizer_tests);
    
    // Add dynamics_mapper tests
    const dynamics_mapper_tests = b.addTest(.{
        .root_source_file = b.path("src/interpreter/dynamics_mapper.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const run_dynamics_mapper_tests = b.addRunArtifact(dynamics_mapper_tests);
    
    // Add beam-tuplet coordination tests (TASK-INT-010)
    const beam_tuplet_coordination_tests = b.addTest(.{
        .root_source_file = b.path("test/beam_tuplet_coordination_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    beam_tuplet_coordination_tests.root_module.addImport("main", exe.root_module);
    
    const run_beam_tuplet_coordination_tests = b.addRunArtifact(beam_tuplet_coordination_tests);
    
    // Add mxl generator tests (TASK-INT-016)
    const mxl_generator_tests = b.addTest(.{
        .root_source_file = b.path("src/mxl/generator.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const run_mxl_generator_tests = b.addRunArtifact(mxl_generator_tests);
    
    // Add chord notation tests (TASK 3.1)
    const chord_notation_tests = b.addTest(.{
        .root_source_file = b.path("test/test_chord_notation.zig"),
        .target = target,
        .optimize = optimize,
    });
    chord_notation_tests.root_module.addImport("zmidi2mxl", exe.root_module);
    const run_chord_notation_tests = b.addRunArtifact(chord_notation_tests);
    
    // Add cross-track chord detector tests (TASK 3.1)
    const cross_track_chord_tests = b.addTest(.{
        .root_source_file = b.path("src/harmony/cross_track_chord_detector.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_cross_track_chord_tests = b.addRunArtifact(cross_track_chord_tests);
    
    // Add precision tracking validation tests (TASK-VL-005)
    const precision_tracking_tests = b.addTest(.{
        .root_source_file = b.path("test/test_precision_tracking.zig"),
        .target = target,
        .optimize = optimize,
    });
    precision_tracking_tests.root_module.addImport("zmidi2mxl", exe.root_module);
    const run_precision_tracking_tests = b.addRunArtifact(precision_tracking_tests);
    
    // Add regression prevention tests (TIMING-1.3)
    const regression_prevention_tests = b.addTest(.{
        .root_source_file = b.path("test/regression_prevention_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    regression_prevention_tests.root_module.addImport("zmidi2mxl", exe.root_module);
    const run_regression_prevention_tests = b.addRunArtifact(regression_prevention_tests);
    
    // Add chord regression prevention tests (CDR-1.4)
    const chord_regression_tests = b.addTest(.{
        .root_source_file = b.path("test/test_chord_regression_prevention.zig"),
        .target = target,
        .optimize = optimize,
    });
    chord_regression_tests.root_module.addImport("zmidi2mxl", exe.root_module);
    const run_chord_regression_tests = b.addRunArtifact(chord_regression_tests);
    
    // Add voice preservation tests (MVS-2.1)
    const voice_preservation_tests = b.addTest(.{
        .root_source_file = b.path("test/test_voice_preservation.zig"),
        .target = target,
        .optimize = optimize,
    });
    voice_preservation_tests.root_module.addImport("zmidi2mxl", exe.root_module);
    const run_voice_preservation_tests = b.addRunArtifact(voice_preservation_tests);
    
    // Add voice pipeline integration tests (MVS-2.1)
    const voice_pipeline_tests = b.addTest(.{
        .root_source_file = b.path("test/test_voice_pipeline_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    voice_pipeline_tests.root_module.addImport("zmidi2mxl", exe.root_module);
    const run_voice_pipeline_tests = b.addRunArtifact(voice_pipeline_tests);
    
    // Add MVS-2.2 voice data integrity tests
    const mvs_2_2_tests = b.addTest(.{
        .root_source_file = b.path("test/mvs_2_2_voice_data_integrity_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    mvs_2_2_tests.root_module.addImport("zmidi2mxl", exe.root_module);
    const run_mvs_2_2_tests = b.addRunArtifact(mvs_2_2_tests);
    
    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);
    test_step.dependOn(&run_educational_integration_tests.step);
    test_step.dependOn(&run_zip_writer_tests.step);
    test_step.dependOn(&run_rest_optimizer_tests.step);
    test_step.dependOn(&run_dynamics_mapper_tests.step);
    test_step.dependOn(&run_beam_tuplet_coordination_tests.step);
    test_step.dependOn(&run_mxl_generator_tests.step);
    test_step.dependOn(&run_chord_notation_tests.step);
    test_step.dependOn(&run_cross_track_chord_tests.step);
    test_step.dependOn(&run_precision_tracking_tests.step);
    test_step.dependOn(&run_regression_prevention_tests.step);
    test_step.dependOn(&run_chord_regression_tests.step);
    test_step.dependOn(&run_voice_preservation_tests.step);
    test_step.dependOn(&run_voice_pipeline_tests.step);
    test_step.dependOn(&run_mvs_2_2_tests.step);
    
    // Add separate educational integration test step for TASK-INT-004
    const educational_test_step = b.step("test-educational", "Run educational integration tests");
    educational_test_step.dependOn(&run_educational_integration_tests.step);
    
    // Add precision tracking validation step for TASK-VL-005
    const precision_test_step = b.step("test-precision", "Run precision tracking validation tests");
    precision_test_step.dependOn(&run_precision_tracking_tests.step);
    
    // Add regression prevention test step for TIMING-1.3
    const regression_test_step = b.step("test-regression", "Run regression prevention tests");
    regression_test_step.dependOn(&run_regression_prevention_tests.step);
    
    // Add chord regression prevention test step for CDR-1.4
    const chord_regression_test_step = b.step("test-chord-regression", "Run chord regression prevention tests");
    chord_regression_test_step.dependOn(&run_chord_regression_tests.step);
    
    // Add voice preservation test step for MVS-2.1 and MVS-2.2
    const voice_preservation_test_step = b.step("test-voice-preservation", "Run voice preservation tests");
    voice_preservation_test_step.dependOn(&run_voice_preservation_tests.step);
    voice_preservation_test_step.dependOn(&run_voice_pipeline_tests.step);
    voice_preservation_test_step.dependOn(&run_mvs_2_2_tests.step);
    
    // Add performance benchmarking step for educational features
    const benchmark_step = b.step("benchmark-educational", "Run educational performance benchmarks");
    benchmark_step.dependOn(&run_educational_integration_tests.step);
    
    // Add example programs
    const minimal_example = b.addExecutable(.{
        .name = "minimal_musicxml",
        .root_source_file = b.path("examples/minimal_musicxml.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const notes_example = b.addExecutable(.{
        .name = "musicxml_with_notes",
        .root_source_file = b.path("examples/musicxml_with_notes.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const create_mxl_example = b.addExecutable(.{
        .name = "create_mxl",
        .root_source_file = b.path("examples/create_mxl.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const simple_stem_example = b.addExecutable(.{
        .name = "simple_stem_demo",
        .root_source_file = b.path("examples/simple_stem_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const chord_test_example = b.addExecutable(.{
        .name = "test_chord_generation",
        .root_source_file = b.path("examples/test_chord_generation.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const voice_allocation_test = b.addExecutable(.{
        .name = "test_voice_allocation_verification",
        .root_source_file = b.path("examples/test_voice_allocation_verification.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const voice_algorithm_details = b.addExecutable(.{
        .name = "test_voice_algorithm_details",
        .root_source_file = b.path("examples/test_voice_algorithm_details.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Debug MIDI timing analysis (commented out - file missing)
    // const debug_midi_timing = b.addExecutable(.{
    //     .name = "debug_midi_timing",
    //     .root_source_file = b.path("debug_midi_timing.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // b.installArtifact(debug_midi_timing);
    
    // Add main module to examples so they can import it
    minimal_example.root_module.addImport("zmidi2mxl", exe.root_module);
    notes_example.root_module.addImport("zmidi2mxl", exe.root_module);
    create_mxl_example.root_module.addImport("zmidi2mxl", exe.root_module);
    simple_stem_example.root_module.addImport("zmidi2mxl", exe.root_module);
    chord_test_example.root_module.addImport("zmidi2mxl", exe.root_module);
    voice_allocation_test.root_module.addImport("zmidi2mxl", exe.root_module);
    voice_algorithm_details.root_module.addImport("zmidi2mxl", exe.root_module);
    
    // Create run commands for examples
    const run_minimal = b.addRunArtifact(minimal_example);
    const run_notes = b.addRunArtifact(notes_example);
    const run_create_mxl = b.addRunArtifact(create_mxl_example);
    const run_simple_stem = b.addRunArtifact(simple_stem_example);
    const run_chord_test = b.addRunArtifact(chord_test_example);
    const run_voice_test = b.addRunArtifact(voice_allocation_test);
    const run_voice_details = b.addRunArtifact(voice_algorithm_details);
    
    // Create steps for examples
    const examples_step = b.step("examples", "Build example programs");
    examples_step.dependOn(&minimal_example.step);
    examples_step.dependOn(&notes_example.step);
    examples_step.dependOn(&create_mxl_example.step);
    examples_step.dependOn(&simple_stem_example.step);
    examples_step.dependOn(&chord_test_example.step);
    examples_step.dependOn(&voice_allocation_test.step);
    examples_step.dependOn(&voice_algorithm_details.step);
    
    const run_minimal_step = b.step("run-minimal", "Run minimal MusicXML example");
    run_minimal_step.dependOn(&run_minimal.step);
    
    const run_notes_step = b.step("run-notes", "Run MusicXML with notes example");
    run_notes_step.dependOn(&run_notes.step);
    
    const run_create_mxl_step = b.step("run-create-mxl", "Run create MXL example");
    run_create_mxl_step.dependOn(&run_create_mxl.step);
    
    const run_simple_stem_step = b.step("run-simple-stem", "Run simple stem direction example");
    run_simple_stem_step.dependOn(&run_simple_stem.step);
    
    const run_voice_test_step = b.step("run-voice-test", "Run voice allocation verification test");
    run_voice_test_step.dependOn(&run_voice_test.step);
    
    const run_voice_details_step = b.step("run-voice-details", "Run voice algorithm details test");
    run_voice_details_step.dependOn(&run_voice_details.step);
    
    const run_chord_test_step = b.step("run-chord-test", "Run chord detection test example");
    run_chord_test_step.dependOn(&run_chord_test.step);
}
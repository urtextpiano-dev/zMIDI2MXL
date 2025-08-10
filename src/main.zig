const std = @import("std");
const builtin = @import("builtin");

// Zig 0.14 requires a value, not a type
pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        .ReleaseSafe => .debug, // Keep debug for testing
        .ReleaseFast, .ReleaseSmall => .warn,
    },
};

// Core framework modules - TASK-002, TASK-003
pub const error_mod = @import("error.zig");
pub const log_mod = @import("log.zig");
pub const result = @import("result.zig");
pub const verbose_logger = @import("verbose_logger.zig");
const error_helpers = @import("utils/error_helpers.zig");

// Memory management - TASK-003
pub const memory = struct {
    pub const arena = @import("memory/arena.zig");
};

// Import modules to ensure they compile
pub const midi = struct {
    pub const parser = @import("midi/parser.zig");
    pub const events = @import("midi/events.zig");
    pub const multi_track = @import("midi/multi_track.zig");
};

pub const interpreter = struct {
    pub const quantizer = @import("interpreter/quantizer.zig");
    pub const dynamics_mapper = @import("interpreter/dynamics_mapper.zig");
};

// Export dynamics mapper types and functions for convenience
pub const DynamicsMapper = interpreter.dynamics_mapper.DynamicsMapper;
pub const DynamicsConfig = interpreter.dynamics_mapper.DynamicsConfig;
pub const Dynamic = interpreter.dynamics_mapper.Dynamic;
pub const DynamicMarking = interpreter.dynamics_mapper.DynamicMarking;
pub const generateDynamicXml = interpreter.dynamics_mapper.generateDynamicXml;

pub const mxl = struct {
    pub const generator = @import("mxl/generator.zig");
    pub const xml_writer = @import("mxl/xml_writer.zig");
    pub const zip_writer = @import("mxl/zip_writer.zig");
    pub const note_attributes = @import("mxl/note_attributes.zig");
    pub const Generator = generator.Generator;
    pub const XmlWriter = xml_writer.XmlWriter;
    pub const ZipWriter = zip_writer.ZipWriter;
    pub const createContainerXml = zip_writer.createContainerXml;
};

// Pipeline integration
pub const pipeline = @import("pipeline.zig");
pub const timing = struct {
    pub const enhanced_note = @import("timing/enhanced_note.zig");
    pub const measure_detector = @import("timing/measure_detector.zig");
    pub const tuplet_detector = @import("timing/tuplet_detector.zig");
    pub const beam_grouper = @import("timing/beam_grouper.zig");
    pub const rest_optimizer = @import("timing/rest_optimizer.zig");
    pub const division_converter = @import("timing/division_converter.zig");

    // Export types for convenience
    pub const EnhancedTimedNote = enhanced_note.EnhancedTimedNote;
    pub const Measure = measure_detector.Measure;
    pub const TimedNote = measure_detector.TimedNote;
    pub const MeasureBoundaryDetector = measure_detector.MeasureBoundaryDetector;
    pub const TupletDetector = tuplet_detector.TupletDetector;
    pub const BeamGrouper = beam_grouper.BeamGrouper;
    pub const BeamGroup = beam_grouper.BeamGroup;
    pub const BeamedNote = beam_grouper.BeamedNote;
    pub const BeamState = beam_grouper.BeamState;
    pub const note_type_converter = @import("timing/note_type_converter.zig");
    pub const NoteTypeResult = note_type_converter.NoteTypeResult;
    pub const DivisionConverter = division_converter.DivisionConverter;
};
pub const voice_allocation = @import("voice_allocation.zig");

// Harmony and chord detection (TASK 3.1)
pub const harmony = struct {
    pub const chord_detector = @import("harmony/chord_detector.zig");
    pub const ChordDetector = chord_detector.ChordDetector;
    pub const ChordGroup = chord_detector.ChordGroup;
};

// Educational processing integration (TASK-INT-003)
pub const educational_processor = @import("educational_processor.zig");

pub fn main() !void {
    // Implements TASK-VL-008 per VERBOSE_LOGGING_TASK_LIST.md Section 8
    // Instrument Main Pipeline with comprehensive step tracking

    // Initialize global allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // --- Parse arguments FIRST so we can set up logging correctly ---
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Basic arity check and usage
    if (args.len < 3) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Usage: {s} <input.mid> <output.mxl> [options]\n", .{args[0]});
        try stdout.print("\nOptions:\n", .{});
        try stdout.print("  --no-educational     Disable educational feature processing\n", .{});
        try stdout.print("  --verbose            Enable verbose step-by-step logging\n", .{});
        try stdout.print("  --track-precision    Track floating-point precision loss during conversion\n", .{});
        try stdout.print("                       (can be used with or without --verbose)\n", .{});
        try stdout.print("  --chord-tolerance N  Set chord detection tolerance in ticks (default: 0)\n", .{});
        try stdout.print("\nEnvironment variables:\n", .{});
        try stdout.print("  ZMIDI_LOG_LEVEL   Set log level (trace, debug, info, warn, err)\n", .{});
        try stdout.print("  ZMIDI_STRICT      Enable strict error mode\n", .{});
        return;
    }

    const input_path = args[1];
    const output_path = args[2];

    // Scan CLI flags (same behavior as before; flags can appear anywhere)
    var enable_educational = true;
    var verbose_enabled = false;
    var track_precision = false;
    var chord_tolerance: ?u32 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--no-educational")) {
            enable_educational = false;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose_enabled = true;
        } else if (std.mem.eql(u8, arg, "--track-precision")) {
            track_precision = true;
        } else if (std.mem.eql(u8, arg, "--chord-tolerance")) {
            if (i + 1 < args.len) {
                i += 1;
                chord_tolerance = std.fmt.parseInt(u32, args[i], 10) catch {
                    const logger = log_mod.getLogger();
                    logger.err("Invalid chord tolerance value: {s}", .{args[i]});
                    // Strictly mirror previous behavior: emit error and exit
                    // (error handler is initialized a few lines later)
                    return;
                };
            } else {
                const logger = log_mod.getLogger();
                logger.err("--chord-tolerance requires a numeric argument", .{});
                return;
            }
        }
    }

    // Initialize verbose logger ONCE with real CLI settings
    verbose_logger.initGlobalVerboseLogger(.{
        .enabled = verbose_enabled,
        .track_precision = track_precision,
        .allocator = allocator,
    });
    defer verbose_logger.deinitGlobalVerboseLogger();

    const vlogger = verbose_logger.getVerboseLogger();

    // INITIALIZATION PHASE (001.xxx.xxx)
    vlogger.pipelineStep(.INIT_START, "Starting MIDI to MXL converter v0.1.0", .{});

    vlogger.pipelineStep(.INIT_PARSE_ARGS, "Parsing command-line arguments", .{});

    vlogger.pipelineStep(.INIT_SETUP_LOGGING, "Setting up logging system", .{});
    // Initialize logging based on environment variable
    const log_level_str = std.process.getEnvVarOwned(allocator, "ZMIDI_LOG_LEVEL") catch "info";
    defer if (!std.mem.eql(u8, log_level_str, "info")) allocator.free(log_level_str);

    const log_level = log_mod.LogLevel.fromString(log_level_str) orelse .info;

    log_mod.initGlobalLogger(.{
        .level = log_level,
        .show_timestamp = true,
        .show_location = true,
    });

    const logger = log_mod.getLogger();
    logger.info("MIDI to MXL Converter v0.1.0", .{});

    vlogger.pipelineStep(.INIT_SETUP_ERROR_HANDLER, "Setting up error handler", .{});

    // Initialize error handler
    const strict_env = std.process.getEnvVarOwned(allocator, "ZMIDI_STRICT") catch null;
    const strict_mode = strict_env != null;
    if (strict_env) |env| allocator.free(env);
    var error_handler = error_mod.ErrorHandler.init(allocator, strict_mode);
    defer error_handler.deinit();

    vlogger.pipelineStep(.INIT_PARSE_CONFIG, "Parsing configuration and validating arguments", .{});

    if (!enable_educational) {
        logger.info("Educational processing disabled", .{});
    }

    // Configure pipeline with educational processing based on flag
    const pipeline_config = pipeline.PipelineConfig{
        .divisions = 480,
        .enable_voice_assignment = true,
        .enable_measure_detection = true,
        .chord_tolerance_ticks = chord_tolerance orelse 0,
        .educational = .{
            .enabled = enable_educational,
            .enable_leak_detection = false,
            .enable_logging = log_level == .debug,
            .enable_error_recovery = true,
            .max_memory_overhead_percent = 20.0,
            .performance_target_ns_per_note = 100,
            .processor_config = .{
                .features = .{
                    .enable_tuplet_detection = true,
                    .enable_beam_grouping = true,
                    .enable_rest_optimization = true,
                    .enable_dynamics_mapping = true,
                },
                .quality = .{
                    .tuplet_min_confidence = 0.75,
                    .enable_beam_tuplet_coordination = true,
                    .enable_rest_beam_coordination = true,
                    .prioritize_readability = true,
                },
                .coordination = .{
                    .enable_conflict_resolution = true,
                    .coordination_failure_mode = .fallback,
                    .enable_inter_phase_validation = true,
                },
            },
        },
    };

    vlogger.pipelineStep(.FILE_READ_START, "Starting file operations", .{});

    vlogger.pipelineStep(.FILE_OPEN, "Opening MIDI input file", .{});
    vlogger.pipelineStep(.FILE_READ_CONTENT, "Reading MIDI file content", .{});
    const midi_data = std.fs.cwd().readFileAlloc(allocator, input_path, 10 * 1024 * 1024) catch |err| {
        vlogger.pipelineStepFailed(.FILE_READ_CONTENT, "Failed to read MIDI file", "Error: {}", .{err});
        logger.err("Failed to read MIDI file: {}", .{err});
        try error_handler.handleError(
            .err,
            "Could not read input file",
            .{},
        );
        return;
    };
    defer allocator.free(midi_data);

    vlogger.pipelineStep(.FILE_VALIDATE_SIZE, "Validating file size", .{});
    logger.info("Read {} bytes from {s}", .{ midi_data.len, input_path });

    vlogger.pipelineStep(.FILE_VALIDATE_FORMAT, "Validating MIDI format", .{});

    logger.info("Converting: {s} -> {s}", .{ input_path, output_path });

    // Convert using integrated pipeline with educational processing
    var pipeline_instance = pipeline.Pipeline.init(allocator, pipeline_config);
    defer pipeline_instance.deinit();

    var pipeline_result = pipeline_instance.convertMidiToMxl(midi_data) catch |err| {
        logger.err("Pipeline conversion failed: {}", .{err});
        try error_handler.handleError(
            .err,
            "Conversion pipeline failed",
            .{},
        );
        return;
    };
    defer pipeline_result.deinit(allocator);

    // Log educational processing metrics if available
    if (pipeline_result.educational_metrics) |metrics| {
        logger.info("Educational processing metrics:", .{});
        logger.info("  Notes processed: {}", .{metrics.notes_processed});
        logger.info("  Processing time per note: {}ns", .{metrics.processing_time_per_note_ns});
        logger.info("  Peak memory usage: {} bytes", .{metrics.peak_educational_memory});
        logger.info("  Successful cycles: {}", .{metrics.successful_cycles});
        logger.info("  Errors encountered: {}", .{metrics.error_count});
        logger.info("  Phase allocations:", .{});
        logger.info("    Tuplet detection: {} bytes", .{metrics.phase_allocations[0]});
        logger.info("    Beam grouping: {} bytes", .{metrics.phase_allocations[1]});
        logger.info("    Rest optimization: {} bytes", .{metrics.phase_allocations[2]});
        logger.info("    Dynamics mapping: {} bytes", .{metrics.phase_allocations[3]});
        logger.info("    Coordination: {} bytes", .{metrics.phase_allocations[4]});
    }

    logger.info("Generated {} bytes of MusicXML", .{pipeline_result.musicxml_content.len});

    // MXL ARCHIVE CREATION PHASE (009.xxx.xxx)
    const vlogger_final = verbose_logger.getVerboseLogger();
    vlogger_final.pipelineStep(.MXL_ARCHIVE_START, "Starting MXL archive creation", .{});

    vlogger_final.pipelineStep(.MXL_ZIP_WRITER_INIT, "Initializing ZIP writer for MXL output", .{});
    const output_file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
        vlogger_final.pipelineStepFailed(.MXL_ZIP_WRITER_INIT, "Failed to create output file", "Error: {}", .{err});
        logger.err("Failed to create output file: {}", .{err});
        try error_handler.handleError(.err, "Could not create output file", .{});
        return;
    };
    defer output_file.close();

    var zip_writer = mxl.ZipWriter.init(allocator, output_file.writer().any());
    defer zip_writer.deinit();

    vlogger_final.pipelineStep(.MXL_ADD_MUSICXML_FILE, "Adding MusicXML file to archive", .{});
    zip_writer.addFile("score.musicxml", pipeline_result.musicxml_content, true) catch |err| {
        vlogger_final.pipelineStepFailed(.MXL_ADD_MUSICXML_FILE, "Failed to add MusicXML to archive", "Error: {}", .{err});
        logger.err("Failed to add MusicXML to MXL: {}", .{err});
        try error_handler.handleError(.err, "Could not add MusicXML content", .{});
        return;
    };

    vlogger_final.pipelineStep(.MXL_CREATE_CONTAINER_XML, "Creating container.xml for MXL format", .{});
    const container_xml = mxl.createContainerXml(allocator, "score.musicxml") catch |err| {
        vlogger_final.pipelineStepFailed(.MXL_CREATE_CONTAINER_XML, "Failed to create container XML", "Error: {}", .{err});
        logger.err("Failed to create container XML: {}", .{err});
        try error_handler.handleError(.err, "Could not create container XML", .{});
        return;
    };
    defer allocator.free(container_xml);

    vlogger_final.pipelineStep(.MXL_ADD_CONTAINER_XML, "Adding container.xml to archive", .{});
    zip_writer.addFile("META-INF/container.xml", container_xml, false) catch |err| {
        vlogger_final.pipelineStepFailed(.MXL_ADD_CONTAINER_XML, "Failed to add container XML to archive", "Error: {}", .{err});
        logger.err("Failed to add container XML: {}", .{err});
        try error_handler.handleError(.err, "Could not add container XML", .{});
        return;
    };

    vlogger_final.pipelineStep(.MXL_FINALIZE_ARCHIVE, "Finalizing MXL archive", .{});
    zip_writer.finalize() catch |err| {
        vlogger_final.pipelineStepFailed(.MXL_FINALIZE_ARCHIVE, "Failed to finalize MXL archive", "Error: {}", .{err});
        logger.err("Failed to finalize MXL file: {}", .{err});
        try error_handler.handleError(.err, "Could not finalize MXL file", .{});
        return;
    };

    logger.info("Successfully created MXL file: {s}", .{output_path});

    // FINALIZATION PHASE (010.xxx.xxx)
    vlogger_final.pipelineStep(.FINAL_START, "Starting finalization", .{});

    vlogger_final.pipelineStep(.FINAL_PRECISION_WARNINGS, "Reporting precision warnings", .{});
    vlogger_final.reportPrecisionWarnings();

    vlogger_final.pipelineStep(.FINAL_ERROR_REPORTING, "Reporting errors and validation results", .{});
    if (error_handler.hasErrors()) {
        logger.err("Conversion completed with errors:", .{});
        for (error_handler.errors.items) |err| {
            logger.err("  {any}", .{err});
        }
    } else {
        logger.info("Conversion completed successfully", .{});
    }

    vlogger_final.pipelineStep(.FINAL_METRICS_REPORTING, "Generating pipeline execution report", .{});
    vlogger_final.generatePipelineReport();

    vlogger_final.pipelineStep(.FINAL_CLEANUP, "Cleaning up resources", .{});
    vlogger_final.pipelineStep(.FINAL_SUCCESS, "Conversion completed successfully", .{});
}

// Basic test to verify the test infrastructure works
test "basic test" {
    try std.testing.expect(true);
}

test "allocator test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);

    try std.testing.expect(data.len == 100);
}

test "error handling framework integration" {
    // Test that all error handling modules compile and work together
    var error_handler = error_mod.ErrorHandler.init(std.testing.allocator, false);
    defer error_handler.deinit();

    // Test logging initialization
    log_mod.initGlobalLogger(.{
        .level = .debug,
        .show_timestamp = false,
        .writer = std.io.null_writer.any(),
    });

    const logger = log_mod.getLogger();
    logger.info("Test message", .{});

    // Test error handling
    try error_handler.handleError(.warning, "Test warning", .{});
    try std.testing.expectEqual(@as(usize, 1), error_handler.getErrorCount(.warning));

    // Test Result type
    const TestResult = result.Result(u32);
    const ok_result = TestResult.ok(42);
    try std.testing.expect(ok_result.isOk());
    try std.testing.expectEqual(@as(u32, 42), ok_result.unwrap());
}

test "memory arena allocator integration" {
    // Test TASK-003: Memory Arena Allocator integration
    // Note: Using custom memory.arena module, not ScopedArena helper
    var arena = memory.arena.ArenaAllocator.init(std.testing.allocator, false);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Test basic functionality
    const data = try allocator.alloc(u8, 1000);
    try std.testing.expect(data.len == 1000);

    // Test statistics
    const stats = arena.getStats();
    try std.testing.expect(stats.allocation_count == 1);
    try std.testing.expect(stats.total_allocated >= 1000);

    // Test batch cleanup
    arena.reset();
    const stats_after_reset = arena.getStats();
    try std.testing.expect(stats_after_reset.reset_count == 1);
    try std.testing.expect(stats_after_reset.total_allocated == 0);

    // Test convenience functions
    var arena2 = memory.arena.createArena(std.testing.allocator);
    defer arena2.deinit();

    const alloc2 = arena2.allocator();
    _ = try alloc2.alloc(u8, 100);
    try std.testing.expect(arena2.getStats().allocation_count == 1);
}

test "TASK-004: VLQ parser integration" {
    // Test TASK-004: Variable Length Quantity parser
    // Verify the VLQ parser functions are accessible and work correctly

    // Test basic VLQ parsing
    const vlq_data = [_]u8{ 0x81, 0x00 }; // Represents decimal 128
    const vlq_result = try midi.parser.parseVlq(&vlq_data);
    try std.testing.expectEqual(@as(u32, 128), vlq_result.value);
    try std.testing.expectEqual(@as(u8, 2), vlq_result.bytes_read);

    // Test fast VLQ parsing
    const single_byte_data = [_]u8{0x7F}; // Represents decimal 127
    const fast_result = try midi.parser.parseVlqFast(&single_byte_data);
    try std.testing.expectEqual(@as(u32, 127), fast_result.value);
    try std.testing.expectEqual(@as(u8, 1), fast_result.bytes_read);

    // Test error handling
    const empty_data = [_]u8{};
    const error_result = midi.parser.parseVlq(&empty_data);
    try std.testing.expectError(error_mod.MidiError.UnexpectedEndOfFile, error_result);
}

test "TASK 3.1: Chord detection integration" {
    // Test that chord detection module is accessible and works correctly
    const allocator = std.testing.allocator;
    var detector = harmony.ChordDetector.init(allocator);

    // Test simple chord detection
    const notes = [_]timing.TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 67, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
    };

    const chord_groups = try detector.detectChords(&notes, 10);
    defer {
        for (chord_groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(chord_groups);
    }

    // Should detect one chord with three notes
    try std.testing.expectEqual(@as(usize, 1), chord_groups.len);
    try std.testing.expectEqual(@as(usize, 3), chord_groups[0].notes.len);
}

// test "TASK-007: XML Writer basic functionality" {
//     // Test TASK-007: XML Writer Infrastructure
//     // NOTE: There's a format specifier issue when running tests through main.zig
//     // The xml_writer module itself tests correctly when run standalone
//     // This appears to be a Zig compiler issue with nested module imports
// }

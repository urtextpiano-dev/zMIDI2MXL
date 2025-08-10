const std = @import("std");
const pipeline = @import("../src/pipeline.zig");
const test_utils = @import("../src/test_utils.zig");

// Test configuration
const TestConfig = struct {
    input_midi: []const u8,
    expected_notes: usize,
    expected_measures: usize,
    expected_parts: usize,
    min_voices: usize,
    max_voices: usize,
};

// Test cases for different MIDI files
const test_cases = [_]TestConfig{
    .{
        .input_midi = "Sweden_Minecraft.mid",
        .expected_notes = 271, // Based on our analysis
        .expected_measures = 65,
        .expected_parts = 2,
        .min_voices = 1,
        .max_voices = 8,
    },
};

test "MIDI to MusicXML conversion pipeline" {
    const allocator = test_utils.allocator;
    
    // Test each MIDI file
    for (test_cases) |test_case| {
        std.debug.print("\nTesting: {s}\n", .{test_case.input_midi});
        
        // Read MIDI file
        const midi_data = std.fs.cwd().readFileAlloc(
            allocator, 
            test_case.input_midi, 
            10 * 1024 * 1024
        ) catch |err| {
            std.debug.print("Skipping {s}: {}\n", .{test_case.input_midi, err});
            continue;
        };
        defer allocator.free(midi_data);
        
        // Configure pipeline
        const config = pipeline.PipelineConfig{
            .divisions = 480,
            .enable_voice_assignment = true,
            .enable_measure_detection = true,
            .chord_tolerance_ticks = 0,
            .educational = .{
                .enabled = true,
                .enable_leak_detection = false,
                .enable_logging = false,
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
        
        // Run conversion
        var pipeline_instance = pipeline.Pipeline.init(allocator, config);
        defer pipeline_instance.deinit();
        
        var result = try pipeline_instance.convertMidiToMxl(midi_data);
        defer result.deinit(allocator);
        
        // Validate output
        try test_utils.expect(result.musicxml_content.len > 0);
        
        // Parse and validate MusicXML structure
        const validation = try validateMusicXML(allocator, result.musicxml_content);
        defer validation.deinit(allocator);
        
        // Check basic metrics
        std.debug.print("  Notes: {} (expected: {})\n", .{
            validation.note_count, 
            test_case.expected_notes
        });
        std.debug.print("  Measures: {} (expected: {})\n", .{
            validation.measure_count, 
            test_case.expected_measures
        });
        std.debug.print("  Parts: {} (expected: {})\n", .{
            validation.part_count, 
            test_case.expected_parts
        });
        std.debug.print("  Voices: {}\n", .{validation.voice_count});
        
        // Allow some tolerance in note count (±5%)
        const note_tolerance = @as(f32, @floatFromInt(test_case.expected_notes)) * 0.05;
        const note_diff = @abs(@as(i32, @intCast(validation.note_count)) - 
                              @as(i32, @intCast(test_case.expected_notes)));
        try test_utils.expect(@as(f32, @floatFromInt(note_diff)) <= note_tolerance);
        
        // Check voice range
        try test_utils.expect(validation.voice_count >= test_case.min_voices);
        try test_utils.expect(validation.voice_count <= test_case.max_voices);
        
        // Verify educational metrics if available
        if (result.educational_metrics) |metrics| {
            std.debug.print("  Educational processing:\n", .{});
            std.debug.print("    Notes processed: {}\n", .{metrics.notes_processed});
            std.debug.print("    Time per note: {}ns\n", .{metrics.processing_time_per_note_ns});
            
            // Performance should be reasonable
            try test_utils.expect(metrics.processing_time_per_note_ns < 10000); // <10μs per note
        }
    }
}

// MusicXML validation structure
const MusicXMLValidation = struct {
    note_count: usize,
    measure_count: usize,
    part_count: usize,
    voice_count: usize,
    has_time_signature: bool,
    has_key_signature: bool,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *MusicXMLValidation, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Cleanup if needed
    }
};

// Simple MusicXML parser for validation
fn validateMusicXML(allocator: std.mem.Allocator, xml_content: []const u8) !MusicXMLValidation {
    _ = allocator;
    
    var validation = MusicXMLValidation{
        .note_count = 0,
        .measure_count = 0,
        .part_count = 0,
        .voice_count = 0,
        .has_time_signature = false,
        .has_key_signature = false,
        .allocator = allocator,
    };
    
    // Count basic elements (simple string search for now)
    var note_iter = std.mem.tokenize(u8, xml_content, "<note>");
    while (note_iter.next()) |_| {
        validation.note_count += 1;
    }
    
    var measure_iter = std.mem.tokenize(u8, xml_content, "<measure ");
    while (measure_iter.next()) |_| {
        validation.measure_count += 1;
    }
    
    var part_iter = std.mem.tokenize(u8, xml_content, "<part id=");
    while (part_iter.next()) |_| {
        validation.part_count += 1;
    }
    
    // Check for voices
    var voices = std.AutoHashMap(u32, void).init(allocator);
    defer voices.deinit();
    
    var voice_iter = std.mem.tokenize(u8, xml_content, "<voice>");
    while (voice_iter.next()) |voice_tag| {
        // Extract voice number (simple approach)
        if (voice_tag.len > 0) {
            const voice_num = std.fmt.parseInt(u32, voice_tag[0..1], 10) catch continue;
            try voices.put(voice_num, {});
        }
    }
    validation.voice_count = voices.count();
    
    // Check for time and key signatures
    validation.has_time_signature = std.mem.indexOf(u8, xml_content, "<time>") != null;
    validation.has_key_signature = std.mem.indexOf(u8, xml_content, "<key>") != null;
    
    return validation;
}

test "Chord detection accuracy" {
    const allocator = test_utils.allocator;
    
    // Create a simple test case with known chords
    const test_midi = [_]u8{
        // MIDI header
        'M', 'T', 'h', 'd', 0, 0, 0, 6, // Header chunk
        0, 0, // Format 0
        0, 1, // 1 track
        0, 0x60, // 96 ticks per quarter note
        
        // Track header
        'M', 'T', 'r', 'k', 0, 0, 0, 28, // Track chunk, 28 bytes
        
        // C major chord (C-E-G)
        0, 0x90, 60, 100, // Note on C4
        0, 0x90, 64, 100, // Note on E4  
        0, 0x90, 67, 100, // Note on G4
        
        // Release chord after quarter note
        96, 0x80, 60, 0, // Note off C4
        0, 0x80, 64, 0,  // Note off E4
        0, 0x80, 67, 0,  // Note off G4
        
        // End of track
        0, 0xFF, 0x2F, 0,
    };
    
    const config = pipeline.PipelineConfig{
        .divisions = 480,
        .enable_voice_assignment = true,
        .enable_measure_detection = true,
        .chord_tolerance_ticks = 0, // Exact timing for chords
        .educational = .{
            .enabled = false,
            .enable_leak_detection = false,
            .enable_logging = false,
            .enable_error_recovery = true,
            .max_memory_overhead_percent = 20.0,
            .performance_target_ns_per_note = 100,
            .processor_config = .{
                .features = .{
                    .enable_tuplet_detection = false,
                    .enable_beam_grouping = false,
                    .enable_rest_optimization = false,
                    .enable_dynamics_mapping = false,
                },
                .quality = .{
                    .tuplet_min_confidence = 0.75,
                    .enable_beam_tuplet_coordination = false,
                    .enable_rest_beam_coordination = false,
                    .prioritize_readability = true,
                },
                .coordination = .{
                    .enable_conflict_resolution = false,
                    .coordination_failure_mode = .fallback,
                    .enable_inter_phase_validation = false,
                },
            },
        },
    };
    
    var pipeline_instance = pipeline.Pipeline.init(allocator, config);
    defer pipeline_instance.deinit();
    
    var result = try pipeline_instance.convertMidiToMxl(&test_midi);
    defer result.deinit(allocator);
    
    // Check that chord was detected
    const has_chord = std.mem.indexOf(u8, result.musicxml_content, "<chord/>") != null;
    try test_utils.expect(has_chord);
    
    std.debug.print("Chord detection test: PASSED\n", .{});
}
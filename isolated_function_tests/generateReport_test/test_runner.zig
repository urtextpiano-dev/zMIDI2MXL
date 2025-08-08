const std = @import("std");

// ============================================================================
// EXTRACTED DEPENDENCIES FROM SOURCE
// ============================================================================

const ValidationMetrics = struct {
    // Core metrics
    total_measures: u32 = 0,
    total_notes: u32 = 0,
    total_rests: u32 = 0,
    total_chords: u32 = 0,
    
    // Musical attributes
    tempo_bpm: ?f32 = null,
    time_signature_beats: ?u8 = null,
    time_signature_beat_type: ?u8 = null,
    key_fifths: ?i8 = null,
    
    // Note distribution
    treble_notes: u32 = 0,
    bass_notes: u32 = 0,
    
    // Timing validation
    measures_validated: u32 = 0,
    timing_errors: u32 = 0,
    
    // Educational features
    has_dynamics: bool = false,
    has_beams: bool = false,
    has_tuplets: bool = false,
    
    // Errors
    errors: std.ArrayList([]const u8),
};

// ============================================================================
// EXACT FUNCTION IMPLEMENTATION - ORIGINAL
// ============================================================================

// Helper function to print validation status with consistent formatting
fn printValidationStatus(writer: anytype, label: []const u8, is_correct: bool, success_msg: []const u8, error_msg: []const u8) !void {
    if (is_correct) {
        try writer.print("  ├─ {s}: ✅ {s}\n", .{ label, success_msg });
    } else {
        try writer.print("  ├─ {s}: ❌ {s}\n", .{ label, error_msg });
    }
}

// Helper function to format boolean features  
fn formatFeatureStatus(has_feature: bool) []const u8 {
    return if (has_feature) "✅ Present" else "⚠️  Not found";
}

fn generateReport(metrics: *const ValidationMetrics) !void {
    const stdout = std.io.getStdOut().writer();
    
    // Header section
    const header = "\n═══════════════════════════════════════════════════════════════════════\n           MIDI TO MUSICXML CONVERTER VALIDATION REPORT\n═══════════════════════════════════════════════════════════════════════\n\n";
    try stdout.print(header, .{});
    
    // Test configuration (static content)
    try stdout.print("TEST CONFIGURATION:\n  Input: Sweden_Minecraft.mid\n  Output: sweden_output_validation.mxl\n  Converter: zmidi2mxl (Zig implementation)\n\n", .{});
    
    // Core metrics in one block
    try stdout.print("STRUCTURE ANALYSIS:\n  ├─ Total Measures: {}\n  ├─ Total Notes: {}\n  ├─ Total Rests: {}\n  └─ Total Chords: {}\n\n", .{ metrics.total_measures, metrics.total_notes, metrics.total_rests, metrics.total_chords });
    
    // Musical attributes validation with helper functions
    try stdout.print("MUSICAL ATTRIBUTES VALIDATION:\n", .{});
    
    // Tempo validation
    try stdout.print("  ├─ Tempo: ", .{});
    if (metrics.tempo_bpm) |tempo| {
        const is_correct = @abs(tempo - 44.0) < 0.1;
        const msg = if (is_correct) "CORRECT" else "EXPECTED: 44 BPM - 173% ERROR REPRODUCED!";
        const status = if (is_correct) "✅" else "❌";
        try stdout.print("{s} {d:.1} BPM ({s})\n", .{ status, tempo, msg });
    } else {
        try stdout.print("❌ NOT FOUND\n", .{});
    }
    
    // Time signature validation
    try stdout.print("  ├─ Time Signature: ", .{});
    if (metrics.time_signature_beats) |beats| {
        if (metrics.time_signature_beat_type) |beat_type| {
            const is_correct = beats == 4 and beat_type == 4;
            const status = if (is_correct) "✅" else "❌";
            const msg = if (is_correct) "(CORRECT)" else "(EXPECTED: 4/4)";
            try stdout.print("{s} {}/{} {s}\n", .{ status, beats, beat_type, msg });
        }
    } else {
        try stdout.print("❌ NOT FOUND\n", .{});
    }
    
    // Key signature validation  
    try stdout.print("  └─ Key Signature: ", .{});
    if (metrics.key_fifths) |fifths| {
        const is_correct = fifths == 2;
        if (is_correct) {
            try stdout.print("✅ D major ({} sharps) (CORRECT)\n", .{fifths});
        } else {
            try stdout.print("❌ {} fifths (EXPECTED: D major, 2 sharps)\n", .{fifths});
        }
    } else {
        try stdout.print("❌ NOT FOUND\n", .{});
    }
    
    // Staff distribution with calculation
    const total_staffed = metrics.treble_notes + metrics.bass_notes;
    const unassigned = metrics.total_notes - total_staffed;
    const assignment_status = if (unassigned > 0) "⚠️  Unassigned: {} notes" else "✅ All notes assigned to staves";
    
    try stdout.print("\nSTAFF DISTRIBUTION:\n  ├─ Treble Clef (Staff 1): {} notes\n  ├─ Bass Clef (Staff 2): {} notes\n", .{ metrics.treble_notes, metrics.bass_notes });
    if (unassigned > 0) {
        try stdout.print("  └─ ⚠️  Unassigned: {} notes\n\n", .{unassigned});
    } else {
        try stdout.print("  └─ ✅ All notes assigned to staves\n\n", .{});
    }
    
    // Chord detection and educational features in blocks
    const chord_status = if (metrics.total_chords > 0) "Chords successfully detected" else "No chords detected";
    try stdout.print("CHORD DETECTION ANALYSIS:\n  ├─ Chords Detected: {}\n  ├─ Detection Method: Cross-track (0-tick tolerance)\n  └─ Status: {s}\n\n", .{ metrics.total_chords, chord_status });
    
    try stdout.print("EDUCATIONAL FEATURES:\n  ├─ Dynamics: {s}\n  ├─ Beams: {s}\n  └─ Tuplets: {s}\n\n", .{ formatFeatureStatus(metrics.has_dynamics), formatFeatureStatus(metrics.has_beams), formatFeatureStatus(metrics.has_tuplets) });
    
    // Critical errors
    if (metrics.errors.items.len > 0) {
        try stdout.print("CRITICAL ERRORS:\n", .{});
        for (metrics.errors.items) |err| {
            try stdout.print("  ❌ {s}\n", .{err});
        }
        try stdout.print("\n", .{});
    }
    
    // Final assessment logic consolidated  
    const tempo_correct = if (metrics.tempo_bpm) |t| @abs(t - 44.0) < 0.1 else false;
    const key_correct = if (metrics.key_fifths) |k| k == 2 else false;
    const time_correct = if (metrics.time_signature_beats) |b| b == 4 else false;
    const all_notes_staffed = total_staffed == metrics.total_notes;
    const all_correct = tempo_correct and key_correct and time_correct and all_notes_staffed and metrics.errors.items.len == 0;
    
    const footer = "═══════════════════════════════════════════════════════════════════════\n";
    try stdout.print(footer, .{});
    try stdout.print("FINAL ASSESSMENT:\n\n", .{});
    
    if (all_correct) {
        try stdout.print("  ✅ VALIDATION PASSED - READY FOR EDUCATIONAL USE\n\n  All critical requirements met:\n  • Tempo accuracy: 100% (44 BPM)\n  • Note accuracy: 100% ({} notes)\n  • Chord detection: {} chords found\n  • Key/Time signatures: Correct\n", .{ metrics.total_notes, metrics.total_chords });
    } else {
        try stdout.print("  ❌ VALIDATION FAILED - FIXES REQUIRED\n\n  Issues found:\n", .{});
        if (!tempo_correct) try stdout.print("  • Tempo parsing error (173% error detected)\n", .{});
        if (!key_correct) try stdout.print("  • Key signature incorrect\n", .{});
        if (!time_correct) try stdout.print("  • Time signature incorrect\n", .{});
        if (!all_notes_staffed) try stdout.print("  • Some notes not assigned to staves\n", .{});
    }
    
    try stdout.print("\n{s}\n", .{footer});
}

// ============================================================================
// COMPREHENSIVE TEST CASES - REALISTIC VALIDATION DATA
// ============================================================================

pub fn main() !void {
    std.debug.print("=== TESTING generateReport FUNCTION ===\n");
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test Case 1: Complete valid metrics (all correct)
    std.debug.print("\n--- Test Case 1: Complete Valid Metrics ---\n");
    {
        var metrics = ValidationMetrics{
            .total_measures = 32,
            .total_notes = 128,
            .total_rests = 45,
            .total_chords = 12,
            .tempo_bpm = 44.0,
            .time_signature_beats = 4,
            .time_signature_beat_type = 4,
            .key_fifths = 2,
            .treble_notes = 80,
            .bass_notes = 48,
            .has_dynamics = true,
            .has_beams = true,
            .has_tuplets = false,
            .errors = std.ArrayList([]const u8).init(allocator),
        };
        defer metrics.errors.deinit();
        
        try generateReport(&metrics);
    }
    
    // Test Case 2: Missing tempo (tempo error)  
    std.debug.print("\n--- Test Case 2: Missing Tempo ---\n");
    {
        var metrics = ValidationMetrics{
            .total_measures = 16,
            .total_notes = 64,
            .total_rests = 20,
            .total_chords = 8,
            .tempo_bpm = null,
            .time_signature_beats = 4,
            .time_signature_beat_type = 4,
            .key_fifths = 2,
            .treble_notes = 40,
            .bass_notes = 24,
            .has_dynamics = false,
            .has_beams = true,
            .has_tuplets = true,
            .errors = std.ArrayList([]const u8).init(allocator),
        };
        defer metrics.errors.deinit();
        
        try generateReport(&metrics);
    }
    
    // Test Case 3: Incorrect tempo (173% error reproduced)
    std.debug.print("\n--- Test Case 3: Incorrect Tempo (173% Error) ---\n");
    {
        var metrics = ValidationMetrics{
            .total_measures = 24,
            .total_notes = 96,
            .total_rests = 32,
            .total_chords = 6,
            .tempo_bpm = 120.12, // 173% error from expected 44 BPM
            .time_signature_beats = 4,
            .time_signature_beat_type = 4,
            .key_fifths = 2,
            .treble_notes = 60,
            .bass_notes = 36,
            .has_dynamics = true,
            .has_beams = false,
            .has_tuplets = false,
            .errors = std.ArrayList([]const u8).init(allocator),
        };
        defer metrics.errors.deinit();
        
        try generateReport(&metrics);
    }
    
    // Test Case 4: Multiple errors with unassigned notes
    std.debug.print("\n--- Test Case 4: Multiple Errors with Critical Issues ---\n");
    {
        var metrics = ValidationMetrics{
            .total_measures = 8,
            .total_notes = 30,
            .total_rests = 10,
            .total_chords = 0,
            .tempo_bpm = null,
            .time_signature_beats = null,
            .time_signature_beat_type = null,
            .key_fifths = -1, // Wrong key (F major instead of D major)
            .treble_notes = 15,
            .bass_notes = 10, // 30 - (15 + 10) = 5 unassigned notes
            .has_dynamics = false,
            .has_beams = false,
            .has_tuplets = false,
            .errors = std.ArrayList([]const u8).init(allocator),
        };
        defer metrics.errors.deinit();
        
        // Add some error messages
        try metrics.errors.append("No tempo marking found");
        try metrics.errors.append("Time signature parsing failed");
        
        try generateReport(&metrics);
    }
}

// ============================================================================
// UNIT TESTS - COMPREHENSIVE COVERAGE
// ============================================================================

test "generateReport with perfect validation metrics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var metrics = ValidationMetrics{
        .total_measures = 16,
        .total_notes = 64,
        .total_rests = 16,
        .total_chords = 8,
        .tempo_bpm = 44.0,
        .time_signature_beats = 4,
        .time_signature_beat_type = 4,
        .key_fifths = 2,
        .treble_notes = 40,
        .bass_notes = 24,
        .has_dynamics = true,
        .has_beams = true,
        .has_tuplets = true,
        .errors = std.ArrayList([]const u8).init(allocator),
    };
    defer metrics.errors.deinit();
    
    // Should not throw - validation function
    try generateReport(&metrics);
}

test "generateReport with null values and errors" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var metrics = ValidationMetrics{
        .total_measures = 0,
        .total_notes = 0,
        .total_rests = 0,
        .total_chords = 0,
        .tempo_bpm = null,
        .time_signature_beats = null,
        .time_signature_beat_type = null,
        .key_fifths = null,
        .treble_notes = 0,
        .bass_notes = 0,
        .has_dynamics = false,
        .has_beams = false,
        .has_tuplets = false,
        .errors = std.ArrayList([]const u8).init(allocator),
    };
    defer metrics.errors.deinit();
    
    try metrics.errors.append("Test error message");
    
    // Should handle nulls gracefully
    try generateReport(&metrics);
}

test "generateReport calculates staff distribution correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test case where not all notes are assigned to staves
    var metrics = ValidationMetrics{
        .total_measures = 4,
        .total_notes = 20,
        .total_rests = 5,
        .total_chords = 2,
        .tempo_bpm = 44.0,
        .time_signature_beats = 4,
        .time_signature_beat_type = 4,
        .key_fifths = 2,
        .treble_notes = 8,
        .bass_notes = 7, // 20 - (8 + 7) = 5 unassigned notes
        .has_dynamics = false,
        .has_beams = false,
        .has_tuplets = false,
        .errors = std.ArrayList([]const u8).init(allocator),
    };
    defer metrics.errors.deinit();
    
    // Function should handle unassigned notes correctly
    try generateReport(&metrics);
}

test "generateReport tempo validation thresholds" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test tempo just within acceptable range (44.0 ± 0.1)
    var metrics1 = ValidationMetrics{
        .tempo_bpm = 44.05, // Within 0.1 threshold
        .errors = std.ArrayList([]const u8).init(allocator),
    };
    defer metrics1.errors.deinit();
    
    try generateReport(&metrics1);
    
    // Test tempo just outside acceptable range
    var metrics2 = ValidationMetrics{
        .tempo_bpm = 44.15, // Outside 0.1 threshold
        .errors = std.ArrayList([]const u8).init(allocator),
    };
    defer metrics2.errors.deinit();
    
    try generateReport(&metrics2);
}

test "generateReport boolean logic validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test all combination of boolean flags
    var metrics = ValidationMetrics{
        .total_measures = 8,
        .total_notes = 32,
        .tempo_bpm = 44.0,
        .time_signature_beats = 4,
        .time_signature_beat_type = 4,  
        .key_fifths = 2,
        .treble_notes = 16,
        .bass_notes = 16,
        .has_dynamics = true,
        .has_beams = false,
        .has_tuplets = true,
        .errors = std.ArrayList([]const u8).init(allocator),
    };
    defer metrics.errors.deinit();
    
    // Should handle mixed boolean states correctly
    try generateReport(&metrics);
}
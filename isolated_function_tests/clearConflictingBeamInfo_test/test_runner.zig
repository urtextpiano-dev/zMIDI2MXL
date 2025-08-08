const std = @import("std");
const testing = std.testing;

// Minimal TimedNote struct (from measure_detector.zig)
pub const TimedNote = struct {
    note: u8,
    channel: u8,
    velocity: u8,
    start_tick: u32,
    duration: u32,
    tied_to_next: bool = false,
    tied_from_previous: bool = false,
    track: u8 = 0,
    voice: u8 = 0,
};

// Minimal ProcessingFlags struct
pub const ProcessingFlags = struct {
    tuplet_processed: bool = false,
    beaming_processed: bool = false,
    rest_processed: bool = false,
    dynamics_processed: bool = false,
    stem_processed: bool = false,
};

// Minimal TupletInfo struct (placeholder)
pub const TupletInfo = struct {
    actual_notes: u8,
    normal_notes: u8,
};

// Minimal BeamingInfo struct (placeholder)
pub const BeamingInfo = struct {
    beam_number: u8,
    beam_type: u8,
};

// Minimal EnhancedTimedNote struct
pub const EnhancedTimedNote = struct {
    base_note: TimedNote,
    tuplet_info: ?*TupletInfo = null,
    beaming_info: ?*BeamingInfo = null,
    processing_flags: ProcessingFlags = .{},
};

// Minimal EducationalProcessor struct
pub const EducationalProcessor = struct {
    dummy_field: u32 = 0, // Just to have something in the struct
};

// ============= BASELINE IMPLEMENTATION (ORIGINAL) =============
fn clearConflictingBeamInfo_baseline(self: *EducationalProcessor, enhanced_notes: []EnhancedTimedNote) void {
    _ = self;
    
    for (enhanced_notes) |*note| {
        // Clear beam info for notes that have conflicts
        if (note.beaming_info != null and note.tuplet_info != null) {
            // In fallback mode, prefer keeping tuplet info and clearing beams
            note.beaming_info = null;
            note.processing_flags.beaming_processed = false;
        }
    }
}

// ============= ATTEMPTED SIMPLIFICATION =============
// NOTE: After analysis, the original function is already optimal.
// This "simplified" version is identical because:
// 1. The logic is already minimal (single if condition)
// 2. No unnecessary allocations or operations
// 3. Direct iteration without intermediate collections
// 4. Clear and necessary null checks
fn clearConflictingBeamInfo_simplified(self: *EducationalProcessor, enhanced_notes: []EnhancedTimedNote) void {
    _ = self;
    
    for (enhanced_notes) |*note| {
        if (note.beaming_info != null and note.tuplet_info != null) {
            note.beaming_info = null;
            note.processing_flags.beaming_processed = false;
        }
    }
}

// ============= TEST HELPERS =============
fn createTestNote(note_num: u8, has_tuplet: bool, has_beam: bool) EnhancedTimedNote {
    var tuplet = TupletInfo{ .actual_notes = 3, .normal_notes = 2 };
    var beam = BeamingInfo{ .beam_number = 1, .beam_type = 1 };
    
    return EnhancedTimedNote{
        .base_note = TimedNote{
            .note = note_num,
            .channel = 0,
            .velocity = 64,
            .start_tick = 0,
            .duration = 480,
        },
        .tuplet_info = if (has_tuplet) &tuplet else null,
        .beaming_info = if (has_beam) &beam else null,
        .processing_flags = ProcessingFlags{
            .beaming_processed = has_beam,
        },
    };
}

pub fn main() !void {
    var processor = EducationalProcessor{};
    
    // Test case storage (static allocation for simplicity)
    var tuplet1 = TupletInfo{ .actual_notes = 3, .normal_notes = 2 };
    var tuplet2 = TupletInfo{ .actual_notes = 5, .normal_notes = 4 };
    var beam1 = BeamingInfo{ .beam_number = 1, .beam_type = 1 };
    var beam2 = BeamingInfo{ .beam_number = 2, .beam_type = 2 };
    var beam3 = BeamingInfo{ .beam_number = 3, .beam_type = 1 };
    
    // Test Case 1: Note with both tuplet and beam (conflict - should clear beam)
    var notes1 = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
            },
            .tuplet_info = &tuplet1,
            .beaming_info = &beam1,
            .processing_flags = ProcessingFlags{ .beaming_processed = true },
        },
    };
    
    clearConflictingBeamInfo_simplified(&processor, &notes1);
    
    std.debug.print("Test 1 - Conflict case:\n", .{});
    std.debug.print("  Note has tuplet: {}\n", .{notes1[0].tuplet_info != null});
    std.debug.print("  Note has beam: {}\n", .{notes1[0].beaming_info != null});
    std.debug.print("  Beaming processed: {}\n", .{notes1[0].processing_flags.beaming_processed});
    
    // Test Case 2: Note with only tuplet (no conflict - should remain unchanged)
    var notes2 = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 62,
                .channel = 0,
                .velocity = 64,
                .start_tick = 480,
                .duration = 480,
            },
            .tuplet_info = &tuplet2,
            .beaming_info = null,
            .processing_flags = ProcessingFlags{},
        },
    };
    
    clearConflictingBeamInfo_simplified(&processor, &notes2);
    
    std.debug.print("\nTest 2 - Tuplet only:\n", .{});
    std.debug.print("  Note has tuplet: {}\n", .{notes2[0].tuplet_info != null});
    std.debug.print("  Note has beam: {}\n", .{notes2[0].beaming_info != null});
    std.debug.print("  Beaming processed: {}\n", .{notes2[0].processing_flags.beaming_processed});
    
    // Test Case 3: Note with only beam (no conflict - should remain unchanged)
    var notes3 = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 64,
                .channel = 0,
                .velocity = 64,
                .start_tick = 960,
                .duration = 480,
            },
            .tuplet_info = null,
            .beaming_info = &beam2,
            .processing_flags = ProcessingFlags{ .beaming_processed = true },
        },
    };
    
    clearConflictingBeamInfo_simplified(&processor, &notes3);
    
    std.debug.print("\nTest 3 - Beam only:\n", .{});
    std.debug.print("  Note has tuplet: {}\n", .{notes3[0].tuplet_info != null});
    std.debug.print("  Note has beam: {}\n", .{notes3[0].beaming_info != null});
    std.debug.print("  Beaming processed: {}\n", .{notes3[0].processing_flags.beaming_processed});
    
    // Test Case 4: Multiple notes with mixed conditions
    var notes4 = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 66, .channel = 0, .velocity = 64, .start_tick = 1440, .duration = 480 },
            .tuplet_info = &tuplet1,
            .beaming_info = &beam3,
            .processing_flags = ProcessingFlags{ .beaming_processed = true },
        },
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 68, .channel = 0, .velocity = 64, .start_tick = 1920, .duration = 480 },
            .tuplet_info = null,
            .beaming_info = &beam1,
            .processing_flags = ProcessingFlags{ .beaming_processed = true },
        },
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 70, .channel = 0, .velocity = 64, .start_tick = 2400, .duration = 480 },
            .tuplet_info = &tuplet2,
            .beaming_info = null,
            .processing_flags = ProcessingFlags{},
        },
    };
    
    clearConflictingBeamInfo_simplified(&processor, &notes4);
    
    std.debug.print("\nTest 4 - Multiple notes:\n", .{});
    for (notes4, 0..) |note, i| {
        std.debug.print("  Note {}: tuplet={}, beam={}, beaming_processed={}\n", .{
            i,
            note.tuplet_info != null,
            note.beaming_info != null,
            note.processing_flags.beaming_processed,
        });
    }
    
    // Test Case 5: Empty array
    var notes5 = [_]EnhancedTimedNote{};
    clearConflictingBeamInfo_simplified(&processor, &notes5);
    std.debug.print("\nTest 5 - Empty array: Passed (no crash)\n", .{});
}

test "clearConflictingBeamInfo clears beam when both tuplet and beam present" {
    var processor = EducationalProcessor{};
    var tuplet = TupletInfo{ .actual_notes = 3, .normal_notes = 2 };
    var beam = BeamingInfo{ .beam_number = 1, .beam_type = 1 };
    
    var notes = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
            },
            .tuplet_info = &tuplet,
            .beaming_info = &beam,
            .processing_flags = ProcessingFlags{ .beaming_processed = true },
        },
    };
    
    clearConflictingBeamInfo_baseline(&processor, &notes);
    
    try testing.expect(notes[0].tuplet_info != null);
    try testing.expect(notes[0].beaming_info == null);
    try testing.expect(notes[0].processing_flags.beaming_processed == false);
}

test "clearConflictingBeamInfo preserves tuplet-only notes" {
    var processor = EducationalProcessor{};
    var tuplet = TupletInfo{ .actual_notes = 3, .normal_notes = 2 };
    
    var notes = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
            },
            .tuplet_info = &tuplet,
            .beaming_info = null,
            .processing_flags = ProcessingFlags{},
        },
    };
    
    clearConflictingBeamInfo_baseline(&processor, &notes);
    
    try testing.expect(notes[0].tuplet_info != null);
    try testing.expect(notes[0].beaming_info == null);
    try testing.expect(notes[0].processing_flags.beaming_processed == false);
}

test "clearConflictingBeamInfo preserves beam-only notes" {
    var processor = EducationalProcessor{};
    var beam = BeamingInfo{ .beam_number = 1, .beam_type = 1 };
    
    var notes = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
            },
            .tuplet_info = null,
            .beaming_info = &beam,
            .processing_flags = ProcessingFlags{ .beaming_processed = true },
        },
    };
    
    clearConflictingBeamInfo_baseline(&processor, &notes);
    
    try testing.expect(notes[0].tuplet_info == null);
    try testing.expect(notes[0].beaming_info != null);
    try testing.expect(notes[0].processing_flags.beaming_processed == true);
}

test "clearConflictingBeamInfo handles empty array" {
    var processor = EducationalProcessor{};
    var notes = [_]EnhancedTimedNote{};
    
    clearConflictingBeamInfo_baseline(&processor, &notes);
    
    // Test passes if no crash occurs
    try testing.expect(true);
}

test "clearConflictingBeamInfo handles multiple notes correctly" {
    var processor = EducationalProcessor{};
    var tuplet1 = TupletInfo{ .actual_notes = 3, .normal_notes = 2 };
    var tuplet2 = TupletInfo{ .actual_notes = 5, .normal_notes = 4 };
    var beam1 = BeamingInfo{ .beam_number = 1, .beam_type = 1 };
    var beam2 = BeamingInfo{ .beam_number = 2, .beam_type = 2 };
    
    var notes = [_]EnhancedTimedNote{
        // Conflict: should clear beam
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480 },
            .tuplet_info = &tuplet1,
            .beaming_info = &beam1,
            .processing_flags = ProcessingFlags{ .beaming_processed = true },
        },
        // No conflict: beam only
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 480 },
            .tuplet_info = null,
            .beaming_info = &beam2,
            .processing_flags = ProcessingFlags{ .beaming_processed = true },
        },
        // No conflict: tuplet only
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 960, .duration = 480 },
            .tuplet_info = &tuplet2,
            .beaming_info = null,
            .processing_flags = ProcessingFlags{},
        },
    };
    
    clearConflictingBeamInfo_baseline(&processor, &notes);
    
    // First note: conflict resolved
    try testing.expect(notes[0].tuplet_info != null);
    try testing.expect(notes[0].beaming_info == null);
    try testing.expect(notes[0].processing_flags.beaming_processed == false);
    
    // Second note: unchanged
    try testing.expect(notes[1].tuplet_info == null);
    try testing.expect(notes[1].beaming_info != null);
    try testing.expect(notes[1].processing_flags.beaming_processed == true);
    
    // Third note: unchanged
    try testing.expect(notes[2].tuplet_info != null);
    try testing.expect(notes[2].beaming_info == null);
    try testing.expect(notes[2].processing_flags.beaming_processed == false);
}
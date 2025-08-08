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

// Minimal StemInfo struct (from enhanced_note.zig)
pub const StemInfo = struct {
    direction: u8 = 0, // Simplified from StemDirection enum
    beam_influenced: bool = false,
    voice: u8 = 1,
    in_beam_group: bool = false,
    beam_group_id: ?u32 = null,
    staff_position: ?u8 = null,
};

// Minimal EnhancedTimedNote struct
pub const EnhancedTimedNote = struct {
    base_note: TimedNote,
    stem_info: ?*StemInfo = null,
    processing_flags: ProcessingFlags = .{},
};

// Minimal EducationalProcessor struct
pub const EducationalProcessor = struct {
    dummy_field: u32 = 0, // Just to have something in the struct
};

// ============= BASELINE IMPLEMENTATION (ORIGINAL) =============
fn clearConflictingStemInfo_baseline(self: *EducationalProcessor, enhanced_notes: []EnhancedTimedNote) void {
    _ = self;
    
    for (enhanced_notes) |*note| {
        // Clear stem info and revert to basic stem direction rules
        note.stem_info = null;
        note.processing_flags.stem_processed = false;
    }
}

// ============= ANALYSIS: SIMPLIFIED IMPLEMENTATION =============
// ANALYSIS RESULT: This function is already optimal.
// No meaningful simplification possible because:
// 1. Single for loop - cannot be simplified further
// 2. Two simple assignments - no branching logic to optimize
// 3. No collections or allocations - direct memory operations only
// 4. No mathematical operations - just null assignment and boolean false
// 5. Total complexity: O(n) time, O(1) space - optimal for this operation

// The function serves a specific purpose: clearing stem information from enhanced notes
// to resolve conflicts. The implementation is already minimal and efficient.
fn clearConflictingStemInfo_simplified(self: *EducationalProcessor, enhanced_notes: []EnhancedTimedNote) void {
    _ = self;
    
    for (enhanced_notes) |*note| {
        note.stem_info = null;
        note.processing_flags.stem_processed = false;
    }
}

// ============= TEST HELPERS =============
pub fn main() !void {
    var processor = EducationalProcessor{};
    
    // Test case storage (static allocation for simplicity)
    var stem1 = StemInfo{ .direction = 1, .voice = 1, .beam_influenced = true };
    var stem2 = StemInfo{ .direction = 2, .voice = 2, .beam_influenced = false };
    var stem3 = StemInfo{ .direction = 1, .voice = 1, .in_beam_group = true, .beam_group_id = 42 };
    
    // Test Case 1: Single note with stem info (should clear)
    var notes1 = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
            },
            .stem_info = &stem1,
            .processing_flags = ProcessingFlags{ .stem_processed = true },
        },
    };
    
    clearConflictingStemInfo_simplified(&processor, &notes1);
    
    std.debug.print("Test 1 - Single note with stem info:\n", .{});
    std.debug.print("  Note has stem info: {}\n", .{notes1[0].stem_info != null});
    std.debug.print("  Stem processed: {}\n", .{notes1[0].processing_flags.stem_processed});
    
    // Test Case 2: Multiple notes with mixed stem states
    var notes2 = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480 },
            .stem_info = &stem1,
            .processing_flags = ProcessingFlags{ .stem_processed = true },
        },
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 480 },
            .stem_info = null,
            .processing_flags = ProcessingFlags{ .stem_processed = false },
        },
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 960, .duration = 480 },
            .stem_info = &stem2,
            .processing_flags = ProcessingFlags{ .stem_processed = true },
        },
    };
    
    clearConflictingStemInfo_simplified(&processor, &notes2);
    
    std.debug.print("\nTest 2 - Multiple notes with mixed stem states:\n", .{});
    for (notes2, 0..) |note, i| {
        std.debug.print("  Note {}: stem_info={}, stem_processed={}\n", .{
            i,
            note.stem_info != null,
            note.processing_flags.stem_processed,
        });
    }
    
    // Test Case 3: Complex stem info (should all be cleared)
    var notes3 = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 66, .channel = 0, .velocity = 64, .start_tick = 1440, .duration = 480 },
            .stem_info = &stem3,
            .processing_flags = ProcessingFlags{ .stem_processed = true, .beaming_processed = true },
        },
    };
    
    clearConflictingStemInfo_simplified(&processor, &notes3);
    
    std.debug.print("\nTest 3 - Complex stem info:\n", .{});
    std.debug.print("  Note has stem info: {}\n", .{notes3[0].stem_info != null});
    std.debug.print("  Stem processed: {}\n", .{notes3[0].processing_flags.stem_processed});
    std.debug.print("  Other flags unchanged - beaming processed: {}\n", .{notes3[0].processing_flags.beaming_processed});
    
    // Test Case 4: Empty array (should not crash)
    var notes4 = [_]EnhancedTimedNote{};
    clearConflictingStemInfo_simplified(&processor, &notes4);
    std.debug.print("\nTest 4 - Empty array: Passed (no crash)\n", .{});
    
    // Test Case 5: Already cleared notes (should remain cleared)
    var notes5 = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 68, .channel = 0, .velocity = 64, .start_tick = 1920, .duration = 480 },
            .stem_info = null,
            .processing_flags = ProcessingFlags{ .stem_processed = false },
        },
    };
    
    clearConflictingStemInfo_simplified(&processor, &notes5);
    
    std.debug.print("\nTest 5 - Already cleared note:\n", .{});
    std.debug.print("  Note has stem info: {}\n", .{notes5[0].stem_info != null});
    std.debug.print("  Stem processed: {}\n", .{notes5[0].processing_flags.stem_processed});
}

test "clearConflictingStemInfo clears stem info from note" {
    var processor = EducationalProcessor{};
    var stem = StemInfo{ .direction = 1, .voice = 1, .beam_influenced = true };
    
    var notes = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
            },
            .stem_info = &stem,
            .processing_flags = ProcessingFlags{ .stem_processed = true },
        },
    };
    
    clearConflictingStemInfo_baseline(&processor, &notes);
    
    try testing.expect(notes[0].stem_info == null);
    try testing.expect(notes[0].processing_flags.stem_processed == false);
}

test "clearConflictingStemInfo handles notes without stem info" {
    var processor = EducationalProcessor{};
    
    var notes = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
            },
            .stem_info = null,
            .processing_flags = ProcessingFlags{ .stem_processed = false },
        },
    };
    
    clearConflictingStemInfo_baseline(&processor, &notes);
    
    try testing.expect(notes[0].stem_info == null);
    try testing.expect(notes[0].processing_flags.stem_processed == false);
}

test "clearConflictingStemInfo handles empty array" {
    var processor = EducationalProcessor{};
    var notes = [_]EnhancedTimedNote{};
    
    clearConflictingStemInfo_baseline(&processor, &notes);
    
    // Test passes if no crash occurs
    try testing.expect(true);
}

test "clearConflictingStemInfo clears multiple notes correctly" {
    var processor = EducationalProcessor{};
    var stem1 = StemInfo{ .direction = 1, .voice = 1, .beam_influenced = true };
    var stem2 = StemInfo{ .direction = 2, .voice = 2, .beam_influenced = false };
    
    var notes = [_]EnhancedTimedNote{
        // Note with stem info
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480 },
            .stem_info = &stem1,
            .processing_flags = ProcessingFlags{ .stem_processed = true },
        },
        // Note without stem info
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 480 },
            .stem_info = null,
            .processing_flags = ProcessingFlags{ .stem_processed = false },
        },
        // Another note with stem info
        EnhancedTimedNote{
            .base_note = TimedNote{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 960, .duration = 480 },
            .stem_info = &stem2,
            .processing_flags = ProcessingFlags{ .stem_processed = true, .beaming_processed = true },
        },
    };
    
    clearConflictingStemInfo_baseline(&processor, &notes);
    
    // All notes should have stem info cleared and stem_processed false
    try testing.expect(notes[0].stem_info == null);
    try testing.expect(notes[0].processing_flags.stem_processed == false);
    
    try testing.expect(notes[1].stem_info == null);
    try testing.expect(notes[1].processing_flags.stem_processed == false);
    
    try testing.expect(notes[2].stem_info == null);
    try testing.expect(notes[2].processing_flags.stem_processed == false);
    // Other flags should remain unchanged
    try testing.expect(notes[2].processing_flags.beaming_processed == true);
}

test "clearConflictingStemInfo preserves other processing flags" {
    var processor = EducationalProcessor{};
    var stem = StemInfo{ .direction = 1, .voice = 1 };
    
    var notes = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
            },
            .stem_info = &stem,
            .processing_flags = ProcessingFlags{ 
                .stem_processed = true,
                .tuplet_processed = true,
                .beaming_processed = true,
                .rest_processed = true,
                .dynamics_processed = true,
            },
        },
    };
    
    clearConflictingStemInfo_baseline(&processor, &notes);
    
    // Only stem_processed should be false, others should remain true
    try testing.expect(notes[0].processing_flags.stem_processed == false);
    try testing.expect(notes[0].processing_flags.tuplet_processed == true);
    try testing.expect(notes[0].processing_flags.beaming_processed == true);
    try testing.expect(notes[0].processing_flags.rest_processed == true);
    try testing.expect(notes[0].processing_flags.dynamics_processed == true);
}
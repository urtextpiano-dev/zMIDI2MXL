const std = @import("std");
const testing = std.testing;

// Minimal structs needed for testing
pub const TimedNote = struct {
    track: u16,
    tick: u32,
    pitch: u8,
    velocity: u8,
    duration: u32,
    channel: u8,
    measure_number: u32,
    voice: u8,
};

pub const BeamingInfo = struct {
    beam_state: BeamState = .none,
    beam_level: u8 = 0,
    can_beam: bool = false,
    beat_position: f64 = 0.0,
    beam_group_id: ?u32 = null,
};

pub const BeamState = enum {
    none,
    begin,
    cont, // 'continue' is a reserved keyword
    end,
};

pub const RestInfo = struct {
    rest_data: ?Rest = null,
    is_optimized_rest: bool = false,
    original_duration: u32 = 0,
    alignment_score: f32 = 0.0,
};

pub const Rest = struct {
    duration: u32,
    measure_position: f32,
};

pub const ProcessingFlags = struct {
    tuplet_processed: bool = false,
    beaming_processed: bool = false,
    rest_processed: bool = false,
    dynamics_processed: bool = false,
    stem_processed: bool = false,
};

pub const EnhancedTimedNote = struct {
    base_note: TimedNote,
    tuplet_info: ?*TupletInfo = null,
    beaming_info: ?*BeamingInfo = null,
    rest_info: ?*RestInfo = null,
    dynamics_info: ?*DynamicsInfo = null,
    stem_info: ?*StemInfo = null,
    processing_flags: ProcessingFlags = .{},
    arena: ?*MockArena = null,
};

pub const TupletInfo = struct {};
pub const DynamicsInfo = struct {};
pub const StemInfo = struct {};

// Mock arena for testing
pub const MockArena = struct {
    allocator: std.mem.Allocator,
};

// Mock EducationalProcessor
pub const EducationalProcessor = struct {
    arena: MockArena,
};

// ===== ORIGINAL FUNCTION =====
fn clearConflictingRestInfo(self: *EducationalProcessor, enhanced_notes: []EnhancedTimedNote) void {
    _ = self;
    
    for (enhanced_notes) |*note| {
        // Clear rest info for notes that might have conflicts
        if (note.rest_info != null and note.beaming_info != null) {
            // If rest note also has beam info, that's a potential conflict
            note.rest_info = null;
            note.processing_flags.rest_processed = false;
        }
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var processor = EducationalProcessor{ .arena = MockArena{ .allocator = allocator } };
    
    // Test case 1: Note with both rest and beam info (conflict)
    var rest_info1 = RestInfo{ .is_optimized_rest = true, .original_duration = 480 };
    var beam_info1 = BeamingInfo{ .beam_state = .begin, .can_beam = true };
    
    // Test case 2: Note with only rest info (no conflict)
    var rest_info2 = RestInfo{ .is_optimized_rest = true, .original_duration = 240 };
    
    // Test case 3: Note with only beam info (no conflict)
    var beam_info3 = BeamingInfo{ .beam_state = .end, .can_beam = true };
    
    // Test case 4: Note with neither (no conflict)
    
    var notes = [_]EnhancedTimedNote{
        // Note 1: Has both rest and beam (should clear rest)
        EnhancedTimedNote{
            .base_note = TimedNote{ .track = 0, .tick = 0, .pitch = 60, .velocity = 0, .duration = 480, .channel = 0, .measure_number = 1, .voice = 1 },
            .rest_info = &rest_info1,
            .beaming_info = &beam_info1,
            .processing_flags = .{ .rest_processed = true, .beaming_processed = true },
        },
        // Note 2: Only rest info (should keep)
        EnhancedTimedNote{
            .base_note = TimedNote{ .track = 0, .tick = 480, .pitch = 0, .velocity = 0, .duration = 240, .channel = 0, .measure_number = 1, .voice = 1 },
            .rest_info = &rest_info2,
            .beaming_info = null,
            .processing_flags = .{ .rest_processed = true },
        },
        // Note 3: Only beam info (should keep)
        EnhancedTimedNote{
            .base_note = TimedNote{ .track = 0, .tick = 720, .pitch = 64, .velocity = 80, .duration = 240, .channel = 0, .measure_number = 1, .voice = 1 },
            .rest_info = null,
            .beaming_info = &beam_info3,
            .processing_flags = .{ .beaming_processed = true },
        },
        // Note 4: Neither rest nor beam (no change)
        EnhancedTimedNote{
            .base_note = TimedNote{ .track = 0, .tick = 960, .pitch = 67, .velocity = 90, .duration = 480, .channel = 0, .measure_number = 2, .voice = 1 },
            .rest_info = null,
            .beaming_info = null,
            .processing_flags = .{},
        },
    };
    
    std.debug.print("=== BEFORE clearConflictingRestInfo ===\n", .{});
    for (notes, 0..) |note, i| {
        std.debug.print("Note {}: rest_info={}, beaming_info={}, rest_processed={}\n", .{ 
            i, 
            note.rest_info != null,
            note.beaming_info != null,
            note.processing_flags.rest_processed 
        });
    }
    
    // Call the function
    clearConflictingRestInfo(&processor, &notes);
    
    std.debug.print("\n=== AFTER clearConflictingRestInfo ===\n", .{});
    for (notes, 0..) |note, i| {
        std.debug.print("Note {}: rest_info={}, beaming_info={}, rest_processed={}\n", .{ 
            i, 
            note.rest_info != null,
            note.beaming_info != null,
            note.processing_flags.rest_processed 
        });
    }
    
    // Verify expected behavior
    std.debug.print("\n=== VERIFICATION ===\n", .{});
    if (notes[0].rest_info == null and notes[0].processing_flags.rest_processed == false) {
        std.debug.print("✓ Note 0: Conflict resolved (rest cleared)\n", .{});
    } else {
        std.debug.print("✗ Note 0: Conflict NOT resolved\n", .{});
    }
    
    if (notes[1].rest_info != null and notes[1].processing_flags.rest_processed == true) {
        std.debug.print("✓ Note 1: Rest preserved (no conflict)\n", .{});
    } else {
        std.debug.print("✗ Note 1: Rest incorrectly modified\n", .{});
    }
    
    if (notes[2].beaming_info != null) {
        std.debug.print("✓ Note 2: Beam preserved\n", .{});
    } else {
        std.debug.print("✗ Note 2: Beam incorrectly modified\n", .{});
    }
    
    if (notes[3].rest_info == null and notes[3].beaming_info == null) {
        std.debug.print("✓ Note 3: Unchanged (no data)\n", .{});
    } else {
        std.debug.print("✗ Note 3: Incorrectly modified\n", .{});
    }
}

test "clearConflictingRestInfo basic functionality" {
    const allocator = testing.allocator;
    var processor = EducationalProcessor{ .arena = MockArena{ .allocator = allocator } };
    
    // Test with conflicting rest and beam info
    var rest_info = RestInfo{ .is_optimized_rest = true, .original_duration = 480 };
    var beam_info = BeamingInfo{ .beam_state = .begin, .can_beam = true };
    
    const note = EnhancedTimedNote{
        .base_note = TimedNote{ .track = 0, .tick = 0, .pitch = 60, .velocity = 0, .duration = 480, .channel = 0, .measure_number = 1, .voice = 1 },
        .rest_info = &rest_info,
        .beaming_info = &beam_info,
        .processing_flags = .{ .rest_processed = true },
    };
    
    var notes = [_]EnhancedTimedNote{note};
    
    clearConflictingRestInfo(&processor, &notes);
    
    // After clearing, rest_info should be null and rest_processed should be false
    try testing.expect(notes[0].rest_info == null);
    try testing.expect(notes[0].processing_flags.rest_processed == false);
    try testing.expect(notes[0].beaming_info != null); // Beam info should remain
}

test "clearConflictingRestInfo no conflict cases" {
    const allocator = testing.allocator;
    var processor = EducationalProcessor{ .arena = MockArena{ .allocator = allocator } };
    
    var rest_info = RestInfo{ .is_optimized_rest = true, .original_duration = 480 };
    var beam_info = BeamingInfo{ .beam_state = .begin, .can_beam = true };
    
    // Case 1: Only rest info (no conflict)
    const note1 = EnhancedTimedNote{
        .base_note = TimedNote{ .track = 0, .tick = 0, .pitch = 0, .velocity = 0, .duration = 480, .channel = 0, .measure_number = 1, .voice = 1 },
        .rest_info = &rest_info,
        .beaming_info = null,
        .processing_flags = .{ .rest_processed = true },
    };
    
    // Case 2: Only beam info (no conflict)
    const note2 = EnhancedTimedNote{
        .base_note = TimedNote{ .track = 0, .tick = 480, .pitch = 64, .velocity = 80, .duration = 240, .channel = 0, .measure_number = 1, .voice = 1 },
        .rest_info = null,
        .beaming_info = &beam_info,
        .processing_flags = .{ .beaming_processed = true },
    };
    
    // Case 3: Neither (no conflict)
    const note3 = EnhancedTimedNote{
        .base_note = TimedNote{ .track = 0, .tick = 720, .pitch = 67, .velocity = 90, .duration = 480, .channel = 0, .measure_number = 2, .voice = 1 },
        .rest_info = null,
        .beaming_info = null,
        .processing_flags = .{},
    };
    
    var notes = [_]EnhancedTimedNote{ note1, note2, note3 };
    
    clearConflictingRestInfo(&processor, &notes);
    
    // Nothing should change for non-conflicting cases
    try testing.expect(notes[0].rest_info != null);
    try testing.expect(notes[0].processing_flags.rest_processed == true);
    
    try testing.expect(notes[1].beaming_info != null);
    try testing.expect(notes[1].processing_flags.beaming_processed == true);
    
    try testing.expect(notes[2].rest_info == null);
    try testing.expect(notes[2].beaming_info == null);
}

test "clearConflictingRestInfo empty array" {
    const allocator = testing.allocator;
    var processor = EducationalProcessor{ .arena = MockArena{ .allocator = allocator } };
    
    var notes = [_]EnhancedTimedNote{};
    
    // Should handle empty array gracefully
    clearConflictingRestInfo(&processor, notes[0..0]);
    
    // No crash = success
    try testing.expect(true);
}

test "clearConflictingRestInfo multiple conflicts" {
    const allocator = testing.allocator;
    var processor = EducationalProcessor{ .arena = MockArena{ .allocator = allocator } };
    
    var rest_info1 = RestInfo{ .is_optimized_rest = true, .original_duration = 480 };
    var beam_info1 = BeamingInfo{ .beam_state = .begin, .can_beam = true };
    
    var rest_info2 = RestInfo{ .is_optimized_rest = false, .original_duration = 240 };
    var beam_info2 = BeamingInfo{ .beam_state = .cont, .can_beam = true };
    
    var notes = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{ .track = 0, .tick = 0, .pitch = 60, .velocity = 0, .duration = 480, .channel = 0, .measure_number = 1, .voice = 1 },
            .rest_info = &rest_info1,
            .beaming_info = &beam_info1,
            .processing_flags = .{ .rest_processed = true },
        },
        EnhancedTimedNote{
            .base_note = TimedNote{ .track = 0, .tick = 480, .pitch = 62, .velocity = 0, .duration = 240, .channel = 0, .measure_number = 1, .voice = 1 },
            .rest_info = &rest_info2,
            .beaming_info = &beam_info2,
            .processing_flags = .{ .rest_processed = true },
        },
    };
    
    clearConflictingRestInfo(&processor, &notes);
    
    // Both conflicts should be resolved
    try testing.expect(notes[0].rest_info == null);
    try testing.expect(notes[0].processing_flags.rest_processed == false);
    try testing.expect(notes[1].rest_info == null);
    try testing.expect(notes[1].processing_flags.rest_processed == false);
    
    // Beam info should remain for both
    try testing.expect(notes[0].beaming_info != null);
    try testing.expect(notes[1].beaming_info != null);
}
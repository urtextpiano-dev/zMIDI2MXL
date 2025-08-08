const std = @import("std");

// ============================================================================
// MINIMAL DEPENDENCIES EXTRACTED FROM SOURCE
// ============================================================================

/// Minimal TimedNote struct (from measure_detector.zig)
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

/// Minimal TupletType enum (from tuplet_detector.zig)
pub const TupletType = enum(u8) {
    duplet = 2,
    triplet = 3,
    quadruplet = 4,
    quintuplet = 5,
    sextuplet = 6,
    septuplet = 7,
};

/// Minimal Tuplet struct (from tuplet_detector.zig)
pub const Tuplet = struct {
    tuplet_type: TupletType,
    start_tick: u32,
    end_tick: u32,
    notes: []const TimedNote,
    beat_unit: []const u8,
    confidence: f64,
    arena: ?*anyopaque = null,
};

/// Minimal EducationalProcessor struct (only what's needed)
pub const EducationalProcessor = struct {
    // Empty - function doesn't actually use self
};

// ============================================================================
// ORIGINAL FUNCTION (BASELINE)
// ============================================================================

fn findPositionInTuplet(self: *EducationalProcessor, note: TimedNote, tuplet: Tuplet) u8 {
    _ = self; // Not used but kept for consistency
    
    for (tuplet.notes, 0..) |tuplet_note, i| {
        if (tuplet_note.start_tick == note.start_tick and 
            tuplet_note.note == note.note and
            tuplet_note.channel == note.channel) {
            return @intCast(i);
        }
    }
    return 0; // Default to first position if not found
}

// ============================================================================
// TEST CASES
// ============================================================================

fn createTestNote(note: u8, channel: u8, start_tick: u32) TimedNote {
    return TimedNote{
        .note = note,
        .channel = channel,
        .velocity = 64,
        .start_tick = start_tick,
        .duration = 480,
    };
}

fn runTests() !void {
    const stdout = std.io.getStdOut().writer();
    var processor = EducationalProcessor{};
    
    // Test 1: Find note at first position
    {
        const notes = [_]TimedNote{
            createTestNote(60, 0, 0),
            createTestNote(62, 0, 480),
            createTestNote(64, 0, 960),
        };
        const tuplet = Tuplet{
            .tuplet_type = .triplet,
            .start_tick = 0,
            .end_tick = 1440,
            .notes = &notes,
            .beat_unit = "eighth",
            .confidence = 0.95,
        };
        const search_note = createTestNote(60, 0, 0);
        const position = findPositionInTuplet(&processor, search_note, tuplet);
        try stdout.print("Test 1 - First position: {d}\n", .{position});
        std.debug.assert(position == 0);
    }
    
    // Test 2: Find note at middle position
    {
        const notes = [_]TimedNote{
            createTestNote(60, 0, 0),
            createTestNote(62, 0, 480),
            createTestNote(64, 0, 960),
        };
        const tuplet = Tuplet{
            .tuplet_type = .triplet,
            .start_tick = 0,
            .end_tick = 1440,
            .notes = &notes,
            .beat_unit = "eighth",
            .confidence = 0.95,
        };
        const search_note = createTestNote(62, 0, 480);
        const position = findPositionInTuplet(&processor, search_note, tuplet);
        try stdout.print("Test 2 - Middle position: {d}\n", .{position});
        std.debug.assert(position == 1);
    }
    
    // Test 3: Find note at last position
    {
        const notes = [_]TimedNote{
            createTestNote(60, 0, 0),
            createTestNote(62, 0, 480),
            createTestNote(64, 0, 960),
        };
        const tuplet = Tuplet{
            .tuplet_type = .triplet,
            .start_tick = 0,
            .end_tick = 1440,
            .notes = &notes,
            .beat_unit = "eighth",
            .confidence = 0.95,
        };
        const search_note = createTestNote(64, 0, 960);
        const position = findPositionInTuplet(&processor, search_note, tuplet);
        try stdout.print("Test 3 - Last position: {d}\n", .{position});
        std.debug.assert(position == 2);
    }
    
    // Test 4: Note not found (defaults to 0)
    {
        const notes = [_]TimedNote{
            createTestNote(60, 0, 0),
            createTestNote(62, 0, 480),
            createTestNote(64, 0, 960),
        };
        const tuplet = Tuplet{
            .tuplet_type = .triplet,
            .start_tick = 0,
            .end_tick = 1440,
            .notes = &notes,
            .beat_unit = "eighth",
            .confidence = 0.95,
        };
        const search_note = createTestNote(66, 0, 1440); // Note not in tuplet
        const position = findPositionInTuplet(&processor, search_note, tuplet);
        try stdout.print("Test 4 - Note not found: {d}\n", .{position});
        std.debug.assert(position == 0);
    }
    
    // Test 5: Different channel (not found)
    {
        const notes = [_]TimedNote{
            createTestNote(60, 0, 0),
            createTestNote(62, 0, 480),
            createTestNote(64, 0, 960),
        };
        const tuplet = Tuplet{
            .tuplet_type = .triplet,
            .start_tick = 0,
            .end_tick = 1440,
            .notes = &notes,
            .beat_unit = "eighth",
            .confidence = 0.95,
        };
        const search_note = createTestNote(60, 1, 0); // Same note, different channel
        const position = findPositionInTuplet(&processor, search_note, tuplet);
        try stdout.print("Test 5 - Different channel: {d}\n", .{position});
        std.debug.assert(position == 0);
    }
    
    // Test 6: Empty tuplet
    {
        const notes = [_]TimedNote{};
        const tuplet = Tuplet{
            .tuplet_type = .triplet,
            .start_tick = 0,
            .end_tick = 1440,
            .notes = &notes,
            .beat_unit = "eighth",
            .confidence = 0.95,
        };
        const search_note = createTestNote(60, 0, 0);
        const position = findPositionInTuplet(&processor, search_note, tuplet);
        try stdout.print("Test 6 - Empty tuplet: {d}\n", .{position});
        std.debug.assert(position == 0);
    }
    
    // Test 7: Large tuplet (sextuplet)
    {
        const notes = [_]TimedNote{
            createTestNote(60, 0, 0),
            createTestNote(61, 0, 240),
            createTestNote(62, 0, 480),
            createTestNote(63, 0, 720),
            createTestNote(64, 0, 960),
            createTestNote(65, 0, 1200),
        };
        const tuplet = Tuplet{
            .tuplet_type = .sextuplet,
            .start_tick = 0,
            .end_tick = 1440,
            .notes = &notes,
            .beat_unit = "eighth",
            .confidence = 0.95,
        };
        const search_note = createTestNote(64, 0, 960);
        const position = findPositionInTuplet(&processor, search_note, tuplet);
        try stdout.print("Test 7 - Sextuplet position 4: {d}\n", .{position});
        std.debug.assert(position == 4);
    }
    
    // Test 8: Match only on all three criteria
    {
        const notes = [_]TimedNote{
            createTestNote(60, 0, 0),
            createTestNote(60, 1, 0),     // Same note, same tick, different channel
            createTestNote(60, 0, 480),   // Same note, same channel, different tick
            createTestNote(62, 0, 0),     // Different note, same channel, same tick
        };
        const tuplet = Tuplet{
            .tuplet_type = .quadruplet,
            .start_tick = 0,
            .end_tick = 1440,
            .notes = &notes,
            .beat_unit = "eighth",
            .confidence = 0.95,
        };
        const search_note = createTestNote(60, 0, 480);
        const position = findPositionInTuplet(&processor, search_note, tuplet);
        try stdout.print("Test 8 - Exact match required: {d}\n", .{position});
        std.debug.assert(position == 2);
    }
}

// ============================================================================
// UNIT TESTS
// ============================================================================

test "findPositionInTuplet - basic functionality" {
    var processor = EducationalProcessor{};
    
    const notes = [_]TimedNote{
        createTestNote(60, 0, 0),
        createTestNote(62, 0, 480),
        createTestNote(64, 0, 960),
    };
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 0,
        .end_tick = 1440,
        .notes = &notes,
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    // Test finding each note
    try std.testing.expectEqual(@as(u8, 0), findPositionInTuplet(&processor, createTestNote(60, 0, 0), tuplet));
    try std.testing.expectEqual(@as(u8, 1), findPositionInTuplet(&processor, createTestNote(62, 0, 480), tuplet));
    try std.testing.expectEqual(@as(u8, 2), findPositionInTuplet(&processor, createTestNote(64, 0, 960), tuplet));
}

test "findPositionInTuplet - not found returns 0" {
    var processor = EducationalProcessor{};
    
    const notes = [_]TimedNote{
        createTestNote(60, 0, 0),
        createTestNote(62, 0, 480),
    };
    const tuplet = Tuplet{
        .tuplet_type = .duplet,
        .start_tick = 0,
        .end_tick = 960,
        .notes = &notes,
        .beat_unit = "quarter",
        .confidence = 0.90,
    };
    
    // Test note not in tuplet
    const not_found = createTestNote(70, 0, 1000);
    try std.testing.expectEqual(@as(u8, 0), findPositionInTuplet(&processor, not_found, tuplet));
}

test "findPositionInTuplet - channel matters" {
    var processor = EducationalProcessor{};
    
    const notes = [_]TimedNote{
        createTestNote(60, 0, 0),
        createTestNote(60, 1, 0), // Same note and tick, different channel
    };
    const tuplet = Tuplet{
        .tuplet_type = .duplet,
        .start_tick = 0,
        .end_tick = 960,
        .notes = &notes,
        .beat_unit = "quarter",
        .confidence = 0.90,
    };
    
    // Should find the correct channel
    try std.testing.expectEqual(@as(u8, 0), findPositionInTuplet(&processor, createTestNote(60, 0, 0), tuplet));
    try std.testing.expectEqual(@as(u8, 1), findPositionInTuplet(&processor, createTestNote(60, 1, 0), tuplet));
}

test "findPositionInTuplet - empty tuplet" {
    var processor = EducationalProcessor{};
    
    const notes = [_]TimedNote{};
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 0,
        .end_tick = 1440,
        .notes = &notes,
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    // Any search should return 0 for empty tuplet
    try std.testing.expectEqual(@as(u8, 0), findPositionInTuplet(&processor, createTestNote(60, 0, 0), tuplet));
}

test "findPositionInTuplet - large tuplet" {
    var processor = EducationalProcessor{};
    
    const notes = [_]TimedNote{
        createTestNote(60, 0, 0),
        createTestNote(61, 0, 200),
        createTestNote(62, 0, 400),
        createTestNote(63, 0, 600),
        createTestNote(64, 0, 800),
        createTestNote(65, 0, 1000),
        createTestNote(66, 0, 1200),
    };
    const tuplet = Tuplet{
        .tuplet_type = .septuplet,
        .start_tick = 0,
        .end_tick = 1400,
        .notes = &notes,
        .beat_unit = "eighth",
        .confidence = 0.85,
    };
    
    // Test finding last note in septuplet
    try std.testing.expectEqual(@as(u8, 6), findPositionInTuplet(&processor, createTestNote(66, 0, 1200), tuplet));
}

// ============================================================================
// MAIN ENTRY POINT
// ============================================================================

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== Testing findPositionInTuplet Function ===\n\n", .{});
    
    try stdout.print("Running functional tests...\n", .{});
    try runTests();
    
    try stdout.print("\nAll tests passed!\n", .{});
}
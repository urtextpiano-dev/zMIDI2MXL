const std = @import("std");
const t = @import("../../src/test_utils.zig");

// ============================================================================
// Minimal struct definitions for isolated testing
// ============================================================================

/// Base timed note data
pub const TimedNote = struct {
    note: u8,
    channel: u8,
    velocity: u8,
    start_tick: u32,
    duration: u32,
    tied_to_next: bool = false,
    tied_from_previous: bool = false,
};

/// Enhanced timed note (simplified for testing)
pub const EnhancedTimedNote = struct {
    base_note: TimedNote,
    // Other optional fields not needed for this test
};

/// Tuplet span information
pub const TupletSpan = struct {
    start_tick: u32,
    end_tick: u32,
    // Other fields not needed for boundary checking
};

/// Beam group information
pub const BeamGroupInfo = struct {
    group_id: u32,
    notes: []EnhancedTimedNote,
    start_tick: u32,
    end_tick: u32,
};

/// Mock EducationalProcessor (minimal for testing)
pub const EducationalProcessor = struct {
    // No fields needed for this test
};

// ============================================================================
// ORIGINAL FUNCTION (Baseline)
// ============================================================================

fn beamCrossesTupletBoundary_original(self: *EducationalProcessor, group: BeamGroupInfo, tuplet_spans: []const TupletSpan) bool {
    _ = self;
    
    // Check if beam group spans multiple tuplets or partial tuplets
    var tuplets_touched: u32 = 0;
    var in_tuplet = false;
    var out_of_tuplet = false;
    
    for (group.notes) |note| {
        var note_in_tuplet = false;
        
        for (tuplet_spans) |span| {
            if (note.base_note.start_tick >= span.start_tick and
                note.base_note.start_tick < span.end_tick) {
                note_in_tuplet = true;
                tuplets_touched += 1;  // BUG: This counts notes, not unique tuplets!
                break;
            }
        }
        
        if (note_in_tuplet) {
            in_tuplet = true;
        } else {
            out_of_tuplet = true;
        }
    }
    
    // Beam crosses boundary if it contains both tuplet and non-tuplet notes
    // or if it touches multiple tuplets
    return (in_tuplet and out_of_tuplet) or tuplets_touched > 1;
}

// ============================================================================
// SIMPLIFIED FUNCTION (Proposed)
// ============================================================================

fn beamCrossesTupletBoundary_simplified(self: *EducationalProcessor, group: BeamGroupInfo, tuplet_spans: []const TupletSpan) bool {
    _ = self;
    
    if (group.notes.len == 0 or tuplet_spans.len == 0) return false;
    
    // Track which tuplet index (if any) each note belongs to
    var first_tuplet: ?usize = null;
    var has_non_tuplet = false;
    
    for (group.notes) |note| {
        const tick = note.base_note.start_tick;
        
        // Check if note is in any tuplet
        var in_tuplet: ?usize = null;
        for (tuplet_spans, 0..) |span, i| {
            if (tick >= span.start_tick and tick < span.end_tick) {
                in_tuplet = i;
                break;
            }
        }
        
        // Check boundary conditions
        if (in_tuplet) |idx| {
            if (first_tuplet) |first| {
                if (first != idx) return true; // Multiple tuplets
            } else {
                first_tuplet = idx;
                if (has_non_tuplet) return true; // Mixed tuplet/non-tuplet
            }
        } else {
            has_non_tuplet = true;
            if (first_tuplet != null) return true; // Mixed tuplet/non-tuplet
        }
    }
    
    return false;
}

// ============================================================================
// TEST CASES
// ============================================================================

fn createNote(start_tick: u32) EnhancedTimedNote {
    return .{
        .base_note = .{
            .note = 60,
            .channel = 0,
            .velocity = 64,
            .start_tick = start_tick,
            .duration = 240,
            .tied_to_next = false,
            .tied_from_previous = false,
        },
    };
}

fn createTupletSpan(start: u32, end: u32) TupletSpan {
    return .{
        .start_tick = start,
        .end_tick = end,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var processor = EducationalProcessor{};
    
    std.debug.print("=== Testing beamCrossesTupletBoundary ===\n\n", .{});
    
    // Test Case 1: Notes all within one tuplet
    {
        var notes = try allocator.alloc(EnhancedTimedNote, 3);
        defer allocator.free(notes);
        notes[0] = createNote(100);
        notes[1] = createNote(200);
        notes[2] = createNote(300);
        
        var tuplets = try allocator.alloc(TupletSpan, 1);
        defer allocator.free(tuplets);
        tuplets[0] = createTupletSpan(0, 500);
        
        const group = BeamGroupInfo{
            .group_id = 1,
            .notes = notes,
            .start_tick = 100,
            .end_tick = 400,
        };
        
        const original = beamCrossesTupletBoundary_original(&processor, group, tuplets);
        const simplified = beamCrossesTupletBoundary_simplified(&processor, group, tuplets);
        
        std.debug.print("Test 1 (all in one tuplet): original={}, simplified={}\n", .{ original, simplified });
    }
    
    // Test Case 2: Notes spanning tuplet and non-tuplet
    {
        var notes = try allocator.alloc(EnhancedTimedNote, 3);
        defer allocator.free(notes);
        notes[0] = createNote(100);
        notes[1] = createNote(300);
        notes[2] = createNote(600);
        
        var tuplets = try allocator.alloc(TupletSpan, 1);
        defer allocator.free(tuplets);
        tuplets[0] = createTupletSpan(0, 400);
        
        const group = BeamGroupInfo{
            .group_id = 2,
            .notes = notes,
            .start_tick = 100,
            .end_tick = 700,
        };
        
        const original = beamCrossesTupletBoundary_original(&processor, group, tuplets);
        const simplified = beamCrossesTupletBoundary_simplified(&processor, group, tuplets);
        
        std.debug.print("Test 2 (spanning tuplet boundary): original={}, simplified={}\n", .{ original, simplified });
    }
    
    // Test Case 3: Notes spanning multiple tuplets
    {
        var notes = try allocator.alloc(EnhancedTimedNote, 3);
        defer allocator.free(notes);
        notes[0] = createNote(100);
        notes[1] = createNote(300);
        notes[2] = createNote(600);
        
        var tuplets = try allocator.alloc(TupletSpan, 2);
        defer allocator.free(tuplets);
        tuplets[0] = createTupletSpan(0, 200);
        tuplets[1] = createTupletSpan(500, 700);
        
        const group = BeamGroupInfo{
            .group_id = 3,
            .notes = notes,
            .start_tick = 100,
            .end_tick = 700,
        };
        
        const original = beamCrossesTupletBoundary_original(&processor, group, tuplets);
        const simplified = beamCrossesTupletBoundary_simplified(&processor, group, tuplets);
        
        std.debug.print("Test 3 (multiple tuplets): original={}, simplified={}\n", .{ original, simplified });
    }
    
    // Test Case 4: No tuplets
    {
        var notes = try allocator.alloc(EnhancedTimedNote, 3);
        defer allocator.free(notes);
        notes[0] = createNote(100);
        notes[1] = createNote(200);
        notes[2] = createNote(300);
        
        const tuplets = &[_]TupletSpan{};
        
        const group = BeamGroupInfo{
            .group_id = 4,
            .notes = notes,
            .start_tick = 100,
            .end_tick = 400,
        };
        
        const original = beamCrossesTupletBoundary_original(&processor, group, tuplets);
        const simplified = beamCrossesTupletBoundary_simplified(&processor, group, tuplets);
        
        std.debug.print("Test 4 (no tuplets): original={}, simplified={}\n", .{ original, simplified });
    }
    
    // Test Case 5: All notes outside tuplets
    {
        var notes = try allocator.alloc(EnhancedTimedNote, 3);
        defer allocator.free(notes);
        notes[0] = createNote(500);
        notes[1] = createNote(600);
        notes[2] = createNote(700);
        
        var tuplets = try allocator.alloc(TupletSpan, 1);
        defer allocator.free(tuplets);
        tuplets[0] = createTupletSpan(0, 400);
        
        const group = BeamGroupInfo{
            .group_id = 5,
            .notes = notes,
            .start_tick = 500,
            .end_tick = 800,
        };
        
        const original = beamCrossesTupletBoundary_original(&processor, group, tuplets);
        const simplified = beamCrossesTupletBoundary_simplified(&processor, group, tuplets);
        
        std.debug.print("Test 5 (all outside tuplets): original={}, simplified={}\n", .{ original, simplified });
    }
    
    std.debug.print("\nAll tests completed.\n", .{});
}

// ============================================================================
// UNIT TESTS
// ============================================================================

test "beamCrossesTupletBoundary - all notes in one tuplet" {
    var processor = EducationalProcessor{};
    
    var notes = [_]EnhancedTimedNote{
        createNote(100),
        createNote(200),
        createNote(300),
    };
    
    const tuplets = [_]TupletSpan{
        createTupletSpan(0, 500),
    };
    
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = &notes,
        .start_tick = 100,
        .end_tick = 400,
    };
    
    const original = beamCrossesTupletBoundary_original(&processor, group, &tuplets);
    const simplified = beamCrossesTupletBoundary_simplified(&processor, group, &tuplets);
    
    // The original has a bug - it counts notes in tuplets, not unique tuplets
    try t.expectEq(true, original);  // Bug: incorrectly returns true
    try t.expectEq(false, simplified); // Correct: returns false
}

test "beamCrossesTupletBoundary - notes spanning tuplet boundary" {
    var processor = EducationalProcessor{};
    
    var notes = [_]EnhancedTimedNote{
        createNote(100),
        createNote(300),
        createNote(600),
    };
    
    const tuplets = [_]TupletSpan{
        createTupletSpan(0, 400),
    };
    
    const group = BeamGroupInfo{
        .group_id = 2,
        .notes = &notes,
        .start_tick = 100,
        .end_tick = 700,
    };
    
    const original = beamCrossesTupletBoundary_original(&processor, group, &tuplets);
    const simplified = beamCrossesTupletBoundary_simplified(&processor, group, &tuplets);
    
    // Both correctly identify crossing tuplet boundary
    try t.expectEq(true, original);
    try t.expectEq(true, simplified);
}

test "beamCrossesTupletBoundary - multiple tuplets touched" {
    var processor = EducationalProcessor{};
    
    var notes = [_]EnhancedTimedNote{
        createNote(100),
        createNote(300),
        createNote(600),
    };
    
    const tuplets = [_]TupletSpan{
        createTupletSpan(0, 200),
        createTupletSpan(500, 700),
    };
    
    const group = BeamGroupInfo{
        .group_id = 3,
        .notes = &notes,
        .start_tick = 100,
        .end_tick = 700,
    };
    
    const original = beamCrossesTupletBoundary_original(&processor, group, &tuplets);
    const simplified = beamCrossesTupletBoundary_simplified(&processor, group, &tuplets);
    
    // Both correctly identify multiple tuplets
    try t.expectEq(true, original);
    try t.expectEq(true, simplified);
}

test "beamCrossesTupletBoundary - no tuplets" {
    var processor = EducationalProcessor{};
    
    var notes = [_]EnhancedTimedNote{
        createNote(100),
        createNote(200),
        createNote(300),
    };
    
    const tuplets = [_]TupletSpan{};
    
    const group = BeamGroupInfo{
        .group_id = 4,
        .notes = &notes,
        .start_tick = 100,
        .end_tick = 400,
    };
    
    const original = beamCrossesTupletBoundary_original(&processor, group, &tuplets);
    const simplified = beamCrossesTupletBoundary_simplified(&processor, group, &tuplets);
    
    // Both correctly return false for no tuplets
    try t.expectEq(false, original);
    try t.expectEq(false, simplified);
}

test "beamCrossesTupletBoundary - empty notes array" {
    var processor = EducationalProcessor{};
    
    const notes = [_]EnhancedTimedNote{};
    
    const tuplets = [_]TupletSpan{
        createTupletSpan(0, 500),
    };
    
    const group = BeamGroupInfo{
        .group_id = 5,
        .notes = &notes,
        .start_tick = 0,
        .end_tick = 0,
    };
    
    const original = beamCrossesTupletBoundary_original(&processor, group, &tuplets);
    const simplified = beamCrossesTupletBoundary_simplified(&processor, group, &tuplets);
    
    // Both correctly return false for empty notes
    try t.expectEq(false, original);
    try t.expectEq(false, simplified);
}

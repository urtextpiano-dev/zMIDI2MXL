const std = @import("std");
const testing = std.testing;

// Required struct definitions extracted from source
pub const TimedNote = struct {
    note: u8,
    channel: u8,
    velocity: u8,
    start_tick: u32,
    duration: u32,
};

pub const TupletType = enum(u8) {
    duplet = 2,
    triplet = 3,
    quadruplet = 4,
    quintuplet = 5,
    sextuplet = 6,
    septuplet = 7,
};

pub const Tuplet = struct {
    tuplet_type: TupletType,
    start_tick: u32,
    end_tick: u32,
    notes: []const TimedNote,
    beat_unit: []const u8,
    confidence: f64,
};

// Mock EducationalProcessor for function context
pub const EducationalProcessor = struct {
    // Minimal fields needed for the function
};

// ========================================
// ORIGINAL FUNCTION (BASELINE)
// ========================================
fn noteInTuplet(self: *EducationalProcessor, note: TimedNote, tuplet: Tuplet) bool {
    _ = self; // Not used but kept for consistency
    
    // Note is in tuplet if its start time is within the tuplet's time range
    return note.start_tick >= tuplet.start_tick and note.start_tick < tuplet.end_tick;
}

// ========================================
// TEST CASES
// ========================================
pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var processor = EducationalProcessor{};
    
    // Test data setup
    const notes_data = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 120 },     // Before tuplet
        .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 120 },   // At tuplet start
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 500, .duration = 120 },   // Inside tuplet
        .{ .note = 65, .channel = 0, .velocity = 64, .start_tick = 719, .duration = 120 },   // At tuplet end-1
        .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 720, .duration = 120 },   // At tuplet end (excluded)
        .{ .note = 69, .channel = 0, .velocity = 64, .start_tick = 800, .duration = 120 },   // After tuplet
    };
    
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 480,
        .end_tick = 720,
        .notes = notes_data[1..4], // Notes that are actually in the tuplet
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    try stdout.print("Testing noteInTuplet function with tuplet range: {} - {}\n", .{ tuplet.start_tick, tuplet.end_tick });
    try stdout.print("=================================================================\n", .{});
    
    // Test each note
    for (notes_data, 0..) |note, i| {
        const result = noteInTuplet(&processor, note, tuplet);
        try stdout.print("Note {} at tick {}: {s} tuplet\n", .{ 
            i, 
            note.start_tick, 
            if (result) "IN" else "NOT IN" 
        });
    }
    
    // Edge cases
    try stdout.print("\nEdge Cases:\n", .{});
    try stdout.print("-----------\n", .{});
    
    // Empty tuplet range (start == end)
    const empty_tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 500,
        .end_tick = 500,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const test_note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 500, .duration = 120 };
    const empty_result = noteInTuplet(&processor, test_note, empty_tuplet);
    try stdout.print("Note at tick 500 with empty tuplet [500,500): {s} tuplet\n", .{
        if (empty_result) "IN" else "NOT IN"
    });
    
    // Maximum boundary test
    const max_tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = std.math.maxInt(u32) - 100,
        .end_tick = std.math.maxInt(u32),
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const max_note = TimedNote{ 
        .note = 60, 
        .channel = 0, 
        .velocity = 64, 
        .start_tick = std.math.maxInt(u32) - 50, 
        .duration = 120 
    };
    const max_result = noteInTuplet(&processor, max_note, max_tuplet);
    try stdout.print("Note at tick {} with max tuplet: {s} tuplet\n", .{
        max_note.start_tick,
        if (max_result) "IN" else "NOT IN"
    });
}

// ========================================
// UNIT TESTS
// ========================================
test "noteInTuplet - note before tuplet" {
    var processor = EducationalProcessor{};
    const note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 100, .duration = 120 };
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 480,
        .end_tick = 720,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const result = noteInTuplet(&processor, note, tuplet);
    try testing.expect(result == false);
}

test "noteInTuplet - note at tuplet start" {
    var processor = EducationalProcessor{};
    const note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 120 };
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 480,
        .end_tick = 720,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const result = noteInTuplet(&processor, note, tuplet);
    try testing.expect(result == true);
}

test "noteInTuplet - note inside tuplet" {
    var processor = EducationalProcessor{};
    const note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 600, .duration = 120 };
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 480,
        .end_tick = 720,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const result = noteInTuplet(&processor, note, tuplet);
    try testing.expect(result == true);
}

test "noteInTuplet - note at tuplet end-1" {
    var processor = EducationalProcessor{};
    const note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 719, .duration = 120 };
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 480,
        .end_tick = 720,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const result = noteInTuplet(&processor, note, tuplet);
    try testing.expect(result == true);
}

test "noteInTuplet - note at tuplet end" {
    var processor = EducationalProcessor{};
    const note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 720, .duration = 120 };
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 480,
        .end_tick = 720,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const result = noteInTuplet(&processor, note, tuplet);
    try testing.expect(result == false);
}

test "noteInTuplet - note after tuplet" {
    var processor = EducationalProcessor{};
    const note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 800, .duration = 120 };
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 480,
        .end_tick = 720,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const result = noteInTuplet(&processor, note, tuplet);
    try testing.expect(result == false);
}

test "noteInTuplet - empty tuplet range" {
    var processor = EducationalProcessor{};
    const note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 500, .duration = 120 };
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 500,
        .end_tick = 500,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const result = noteInTuplet(&processor, note, tuplet);
    try testing.expect(result == false);
}

test "noteInTuplet - zero boundaries" {
    var processor = EducationalProcessor{};
    const note = TimedNote{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 120 };
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 0,
        .end_tick = 100,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const result = noteInTuplet(&processor, note, tuplet);
    try testing.expect(result == true);
}

test "noteInTuplet - max value boundaries" {
    var processor = EducationalProcessor{};
    const note = TimedNote{ 
        .note = 60, 
        .channel = 0, 
        .velocity = 64, 
        .start_tick = std.math.maxInt(u32) - 1, 
        .duration = 120 
    };
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = std.math.maxInt(u32) - 100,
        .end_tick = std.math.maxInt(u32),
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const result = noteInTuplet(&processor, note, tuplet);
    try testing.expect(result == true);
}
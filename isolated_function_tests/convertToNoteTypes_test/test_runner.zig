const std = @import("std");
const testing = std.testing;

// ==================== Required Structures ====================

// TimedNote structure from measure_detector.zig
pub const TimedNote = struct {
    note: u8,
    channel: u8,
    velocity: u8,
    start_tick: u32,
    duration: u32,
    tied_to_next: bool = false,
    tied_from_previous: bool = false,
    track_index: u32 = 0,
};

// TimeSignatureEvent from midi_parser.zig
pub const TimeSignatureEvent = struct {
    tick: u32,
    numerator: u8,
    denominator_power: u8,
    clocks_per_metronome: u8,
    thirtysecond_notes_per_quarter: u8,
    
    pub fn getDenominator(self: TimeSignatureEvent) u8 {
        return std.math.shl(u8, 1, self.denominator_power);
    }
};

// NoteType enum from note_type_converter.zig
pub const NoteType = enum {
    breve,
    whole,
    half,
    quarter,
    eighth,
    @"16th",
    @"32nd",
    @"64th",
    @"128th",
    @"256th",
    
    pub fn toString(self: NoteType) []const u8 {
        return switch (self) {
            .breve => "breve",
            .whole => "whole",
            .half => "half",
            .quarter => "quarter",
            .eighth => "eighth",
            .@"16th" => "16th",
            .@"32nd" => "32nd",
            .@"64th" => "64th",
            .@"128th" => "128th",
            .@"256th" => "256th",
        };
    }
};

// NoteTypeResult from note_type_converter.zig
pub const NoteTypeResult = struct {
    note_type: NoteType,
    dots: u8,
};

// Mock EducationalArena for memory management
pub const MockArena = struct {
    allocator: std.mem.Allocator,
    
    pub fn allocForEducational(self: *MockArena, comptime T: type, count: usize) ![]T {
        return self.allocator.alloc(T, count);
    }
};

// Mock EducationalProcessor
pub const EducationalProcessor = struct {
    arena: *MockArena,
};

// ==================== ORIGINAL FUNCTION ====================
fn convertToNoteTypes_original(self: *EducationalProcessor, base_notes: []const TimedNote, time_sig: TimeSignatureEvent) ![]NoteTypeResult {
    _ = time_sig; // May be used for more sophisticated conversion
    
    const note_types = try self.arena.allocForEducational(NoteTypeResult, base_notes.len);
    
    // Simple conversion based on duration
    // In real implementation, this would use note_type_converter properly
    for (base_notes, 0..) |note, i| {
        const note_type: NoteType = switch (note.duration) {
            0...119 => .@"32nd",
            120...239 => .@"16th",
            240...359 => .eighth,
            360...479 => .eighth, // Dotted eighth
            480...719 => .quarter,
            720...959 => .quarter, // Dotted quarter
            960...1439 => .half,
            1440...1919 => .half, // Dotted half
            else => .whole,
        };
        
        // Determine dots based on duration
        const dots: u8 = if (note.duration == 360 or note.duration == 720 or note.duration == 1440) 1 else 0;
        
        note_types[i] = .{
            .note_type = note_type,
            .dots = dots,
        };
    }
    
    return note_types;
}

// ==================== SIMPLIFIED FUNCTION ====================
fn convertToNoteTypes_simplified(self: *EducationalProcessor, base_notes: []const TimedNote, time_sig: TimeSignatureEvent) ![]NoteTypeResult {
    _ = time_sig;
    
    const note_types = try self.arena.allocForEducational(NoteTypeResult, base_notes.len);
    
    for (base_notes, 0..) |note, i| {
        const dur = note.duration;
        
        // Direct mapping using if-else chain (cleaner than switch with overlapping ranges)
        const note_type: NoteType = if (dur < 120) .@"32nd"
            else if (dur < 240) .@"16th"
            else if (dur < 480) .eighth
            else if (dur < 960) .quarter
            else if (dur < 1920) .half
            else .whole;
        
        // Use arithmetic for dots detection (@intFromBool pattern)
        const dots = @intFromBool(dur == 360 or dur == 720 or dur == 1440);
        
        note_types[i] = .{ .note_type = note_type, .dots = dots };
    }
    
    return note_types;
}

// ==================== TEST CASES ====================

fn runTests(allocator: std.mem.Allocator, test_name: []const u8, convertFn: fn(*EducationalProcessor, []const TimedNote, TimeSignatureEvent) anyerror![]NoteTypeResult) !void {
    std.debug.print("\n=== Testing: {s} ===\n", .{test_name});
    
    var arena = MockArena{ .allocator = allocator };
    var processor = EducationalProcessor{ .arena = &arena };
    
    // Test case 1: Various duration notes
    {
        const test_notes = [_]TimedNote{
            .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 60 },      // 32nd
            .{ .note = 61, .channel = 0, .velocity = 64, .start_tick = 60, .duration = 120 },    // 16th
            .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 180, .duration = 240 },   // eighth
            .{ .note = 63, .channel = 0, .velocity = 64, .start_tick = 420, .duration = 360 },   // dotted eighth
            .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 780, .duration = 480 },   // quarter
            .{ .note = 65, .channel = 0, .velocity = 64, .start_tick = 1260, .duration = 720 },  // dotted quarter
            .{ .note = 66, .channel = 0, .velocity = 64, .start_tick = 1980, .duration = 960 },  // half
            .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 2940, .duration = 1440 }, // dotted half
            .{ .note = 68, .channel = 0, .velocity = 64, .start_tick = 4380, .duration = 1920 }, // whole
        };
        
        const time_sig = TimeSignatureEvent{
            .tick = 0,
            .numerator = 4,
            .denominator_power = 2,
            .clocks_per_metronome = 24,
            .thirtysecond_notes_per_quarter = 8,
        };
        
        const results = try convertFn(&processor, &test_notes, time_sig);
        
        std.debug.print("Test 1 - Various durations:\n", .{});
        for (results, 0..) |result, i| {
            std.debug.print("  Note {}: duration={}, type={s}, dots={}\n", 
                .{i, test_notes[i].duration, result.note_type.toString(), result.dots});
        }
    }
    
    // Test case 2: Edge cases
    {
        const edge_notes = [_]TimedNote{
            .{ .note = 70, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 0 },       // minimum
            .{ .note = 71, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 119 },     // 32nd boundary
            .{ .note = 72, .channel = 0, .velocity = 64, .start_tick = 120, .duration = 239 },   // 16th boundary
            .{ .note = 73, .channel = 0, .velocity = 64, .start_tick = 360, .duration = 479 },   // eighth boundary
            .{ .note = 74, .channel = 0, .velocity = 64, .start_tick = 840, .duration = 959 },   // quarter boundary
            .{ .note = 75, .channel = 0, .velocity = 64, .start_tick = 1800, .duration = 1919 }, // half boundary
            .{ .note = 76, .channel = 0, .velocity = 64, .start_tick = 3720, .duration = 2000 }, // beyond whole
        };
        
        const time_sig = TimeSignatureEvent{
            .tick = 0,
            .numerator = 4,
            .denominator_power = 2,
            .clocks_per_metronome = 24,
            .thirtysecond_notes_per_quarter = 8,
        };
        
        const results = try convertFn(&processor, &edge_notes, time_sig);
        
        std.debug.print("\nTest 2 - Edge cases:\n", .{});
        for (results, 0..) |result, i| {
            std.debug.print("  Note {}: duration={}, type={s}, dots={}\n", 
                .{i, edge_notes[i].duration, result.note_type.toString(), result.dots});
        }
    }
    
    // Test case 3: Empty input
    {
        const empty_notes: []const TimedNote = &[_]TimedNote{};
        const time_sig = TimeSignatureEvent{
            .tick = 0,
            .numerator = 4,
            .denominator_power = 2,
            .clocks_per_metronome = 24,
            .thirtysecond_notes_per_quarter = 8,
        };
        
        const results = try convertFn(&processor, empty_notes, time_sig);
        std.debug.print("\nTest 3 - Empty input: {} results\n", .{results.len});
    }
    
    std.debug.print("\nAll tests completed for {s}\n", .{test_name});
}

// ==================== UNIT TESTS ====================

test "convertToNoteTypes correctly maps durations to note types" {
    const allocator = testing.allocator;
    var arena = MockArena{ .allocator = allocator };
    var processor = EducationalProcessor{ .arena = &arena };
    
    const test_notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 60 },    // 32nd
        .{ .note = 61, .channel = 0, .velocity = 64, .start_tick = 60, .duration = 180 },  // 16th
        .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 240, .duration = 300 }, // eighth
        .{ .note = 63, .channel = 0, .velocity = 64, .start_tick = 540, .duration = 500 }, // quarter
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 1040, .duration = 1000 }, // half
        .{ .note = 65, .channel = 0, .velocity = 64, .start_tick = 2040, .duration = 2000 }, // whole
    };
    
    const time_sig = TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    const results = try convertToNoteTypes_original(&processor, &test_notes, time_sig);
    
    try testing.expectEqual(@as(usize, 6), results.len);
    try testing.expectEqual(NoteType.@"32nd", results[0].note_type);
    try testing.expectEqual(NoteType.@"16th", results[1].note_type);
    try testing.expectEqual(NoteType.eighth, results[2].note_type);
    try testing.expectEqual(NoteType.quarter, results[3].note_type);
    try testing.expectEqual(NoteType.half, results[4].note_type);
    try testing.expectEqual(NoteType.whole, results[5].note_type);
}

test "convertToNoteTypes correctly identifies dotted notes" {
    const allocator = testing.allocator;
    var arena = MockArena{ .allocator = allocator };
    var processor = EducationalProcessor{ .arena = &arena };
    
    const test_notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 360 },   // dotted eighth
        .{ .note = 61, .channel = 0, .velocity = 64, .start_tick = 360, .duration = 720 }, // dotted quarter
        .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 1080, .duration = 1440 }, // dotted half
        .{ .note = 63, .channel = 0, .velocity = 64, .start_tick = 2520, .duration = 361 }, // not dotted
    };
    
    const time_sig = TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    const results = try convertToNoteTypes_original(&processor, &test_notes, time_sig);
    
    try testing.expectEqual(@as(u8, 1), results[0].dots);
    try testing.expectEqual(@as(u8, 1), results[1].dots);
    try testing.expectEqual(@as(u8, 1), results[2].dots);
    try testing.expectEqual(@as(u8, 0), results[3].dots);
}

test "convertToNoteTypes handles empty input" {
    const allocator = testing.allocator;
    var arena = MockArena{ .allocator = allocator };
    var processor = EducationalProcessor{ .arena = &arena };
    
    const empty_notes: []const TimedNote = &[_]TimedNote{};
    const time_sig = TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    const results = try convertToNoteTypes_original(&processor, empty_notes, time_sig);
    try testing.expectEqual(@as(usize, 0), results.len);
}

test "simplified version has identical behavior" {
    const allocator = testing.allocator;
    var arena = MockArena{ .allocator = allocator };
    var processor = EducationalProcessor{ .arena = &arena };
    
    const test_notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 60 },
        .{ .note = 61, .channel = 0, .velocity = 64, .start_tick = 60, .duration = 360 },   // dotted
        .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 420, .duration = 720 },  // dotted
        .{ .note = 63, .channel = 0, .velocity = 64, .start_tick = 1140, .duration = 1440 }, // dotted
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 2580, .duration = 1920 },
    };
    
    const time_sig = TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    const original_results = try convertToNoteTypes_original(&processor, &test_notes, time_sig);
    const simplified_results = try convertToNoteTypes_simplified(&processor, &test_notes, time_sig);
    
    // Verify identical behavior
    for (original_results, simplified_results) |orig, simp| {
        try testing.expectEqual(orig.note_type, simp.note_type);
        try testing.expectEqual(orig.dots, simp.dots);
    }
}

test "convertToNoteTypes handles boundary values" {
    const allocator = testing.allocator;
    var arena = MockArena{ .allocator = allocator };
    var processor = EducationalProcessor{ .arena = &arena };
    
    const boundary_notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 119 },  // max 32nd
        .{ .note = 61, .channel = 0, .velocity = 64, .start_tick = 120, .duration = 120 }, // min 16th
        .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 240, .duration = 239 }, // max 16th
        .{ .note = 63, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 240 }, // min eighth
    };
    
    const time_sig = TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    const results = try convertToNoteTypes_original(&processor, &boundary_notes, time_sig);
    
    try testing.expectEqual(NoteType.@"32nd", results[0].note_type);
    try testing.expectEqual(NoteType.@"16th", results[1].note_type);
    try testing.expectEqual(NoteType.@"16th", results[2].note_type);
    try testing.expectEqual(NoteType.eighth, results[3].note_type);
}

// ==================== MAIN ====================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== MIDI Duration to Note Type Converter Test ===\n", .{});
    std.debug.print("Testing function that converts MIDI tick durations to musical note types\n\n", .{});
    
    // Run tests for original version
    try runTests(allocator, "ORIGINAL IMPLEMENTATION", convertToNoteTypes_original);
    
    std.debug.print("\n" ++ "=" ** 60 ++ "\n\n", .{});
    
    // Run tests for simplified version
    try runTests(allocator, "SIMPLIFIED IMPLEMENTATION", convertToNoteTypes_simplified);
}
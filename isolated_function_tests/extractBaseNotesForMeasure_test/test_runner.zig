const std = @import("std");
const testing = std.testing;

// Mock TimedNote structure (simplified from measure_detector.zig)
pub const TimedNote = struct {
    note: u8,
    channel: u8,
    velocity: u8,
    start_tick: u32,
    duration: u32,
    tied_to_next: bool = false,
    tied_from_previous: bool = false,
    track_index: u8 = 0,
};

// Mock EnhancedTimedNote structure (simplified from enhanced_note.zig)
pub const EnhancedTimedNote = struct {
    base_note: TimedNote,
    
    // Educational metadata pointers (not needed for this test)
    tuplet_info: ?*anyopaque = null,
    beaming_info: ?*anyopaque = null,
    rest_info: ?*anyopaque = null,
    dynamics_info: ?*anyopaque = null,
    stem_info: ?*anyopaque = null,
    
    pub fn getBaseNote(self: *const EnhancedTimedNote) TimedNote {
        return self.base_note;
    }
};

// Mock EducationalArena for memory allocation
pub const MockArena = struct {
    allocator: std.mem.Allocator,
    allocation_count: usize = 0,
    total_bytes: usize = 0,
    
    pub fn allocForEducational(self: *MockArena, comptime T: type, count: usize) ![]T {
        self.allocation_count += 1;
        self.total_bytes += @sizeOf(T) * count;
        return try self.allocator.alloc(T, count);
    }
};

// Mock EducationalProcessor containing the function
pub const EducationalProcessor = struct {
    arena: *MockArena,
    
    // ORIGINAL FUNCTION - Exact copy from source
    fn extractBaseNotesForMeasure(self: *EducationalProcessor, enhanced_notes: []EnhancedTimedNote) ![]TimedNote {
        if (enhanced_notes.len == 0) return &[_]TimedNote{};
        
        const base_notes = try self.arena.allocForEducational(TimedNote, enhanced_notes.len);
        
        for (enhanced_notes, 0..) |note, i| {
            base_notes[i] = note.getBaseNote();
        }
        
        return base_notes;
    }
};

// Test helper to create sample data
fn createTestNote(note: u8, start: u32, duration: u32) TimedNote {
    return .{
        .note = note,
        .channel = 0,
        .velocity = 64,
        .start_tick = start,
        .duration = duration,
    };
}

fn createEnhancedNote(base: TimedNote) EnhancedTimedNote {
    return .{ .base_note = base };
}

// Main function for testing execution
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== Testing extractBaseNotesForMeasure ===\n", .{});
    
    // Test Case 1: Empty input
    {
        var arena = MockArena{ .allocator = allocator };
        var processor = EducationalProcessor{ .arena = &arena };
        
        const empty_notes = [_]EnhancedTimedNote{};
        const result = try processor.extractBaseNotesForMeasure(&empty_notes);
        
        std.debug.print("Test 1 - Empty input: {} notes returned\n", .{result.len});
    }
    
    // Test Case 2: Single note
    {
        var arena = MockArena{ .allocator = allocator };
        var processor = EducationalProcessor{ .arena = &arena };
        
        var enhanced_notes = [_]EnhancedTimedNote{
            createEnhancedNote(createTestNote(60, 0, 480)),
        };
        
        const result = try processor.extractBaseNotesForMeasure(&enhanced_notes);
        defer allocator.free(result);
        
        std.debug.print("Test 2 - Single note: {} notes extracted\n", .{result.len});
        std.debug.print("  Note: pitch={}, start={}, duration={}\n", .{
            result[0].note, result[0].start_tick, result[0].duration
        });
    }
    
    // Test Case 3: Multiple notes (typical measure)
    {
        var arena = MockArena{ .allocator = allocator };
        var processor = EducationalProcessor{ .arena = &arena };
        
        var enhanced_notes = [_]EnhancedTimedNote{
            createEnhancedNote(createTestNote(60, 0, 480)),    // C quarter
            createEnhancedNote(createTestNote(64, 480, 480)),  // E quarter
            createEnhancedNote(createTestNote(67, 960, 480)),  // G quarter
            createEnhancedNote(createTestNote(72, 1440, 480)), // C octave quarter
        };
        
        const result = try processor.extractBaseNotesForMeasure(&enhanced_notes);
        defer allocator.free(result);
        
        std.debug.print("Test 3 - Multiple notes: {} notes extracted\n", .{result.len});
        for (result, 0..) |note, i| {
            std.debug.print("  Note {}: pitch={}, start={}, duration={}\n", .{
                i, note.note, note.start_tick, note.duration
            });
        }
    }
    
    // Test Case 4: Large batch (performance test)
    {
        var arena = MockArena{ .allocator = allocator };
        var processor = EducationalProcessor{ .arena = &arena };
        
        const note_count = 100;
        var enhanced_notes = try allocator.alloc(EnhancedTimedNote, note_count);
        defer allocator.free(enhanced_notes);
        
        for (0..note_count) |i| {
            const note_num: u8 = @intCast(60 + (i % 12));
            const start: u32 = @intCast(i * 120);
            enhanced_notes[i] = createEnhancedNote(createTestNote(note_num, start, 120));
        }
        
        const result = try processor.extractBaseNotesForMeasure(enhanced_notes);
        defer allocator.free(result);
        
        std.debug.print("Test 4 - Large batch: {} notes extracted\n", .{result.len});
        std.debug.print("  Arena stats: {} allocations, {} bytes\n", .{
            arena.allocation_count, arena.total_bytes
        });
    }
    
    // Test Case 5: Complex measure with various note types
    {
        var arena = MockArena{ .allocator = allocator };
        var processor = EducationalProcessor{ .arena = &arena };
        
        var enhanced_notes = [_]EnhancedTimedNote{
            createEnhancedNote(createTestNote(60, 0, 960)),    // Half note
            createEnhancedNote(createTestNote(64, 960, 240)),  // Eighth note
            createEnhancedNote(createTestNote(67, 1200, 240)), // Eighth note
            createEnhancedNote(createTestNote(72, 1440, 120)), // Sixteenth note
            createEnhancedNote(createTestNote(76, 1560, 120)), // Sixteenth note
            createEnhancedNote(createTestNote(79, 1680, 120)), // Sixteenth note
            createEnhancedNote(createTestNote(84, 1800, 120)), // Sixteenth note
        };
        
        const result = try processor.extractBaseNotesForMeasure(&enhanced_notes);
        defer allocator.free(result);
        
        std.debug.print("Test 5 - Complex measure: {} notes extracted\n", .{result.len});
        
        // Verify all base notes are correctly extracted
        var all_match = true;
        for (result, enhanced_notes) |base, enhanced| {
            if (base.note != enhanced.base_note.note or
                base.start_tick != enhanced.base_note.start_tick or
                base.duration != enhanced.base_note.duration) {
                all_match = false;
                break;
            }
        }
        std.debug.print("  All base notes match: {}\n", .{all_match});
    }
    
    std.debug.print("\n=== All tests completed successfully ===\n", .{});
}

// Unit tests
test "extractBaseNotesForMeasure - empty input" {
    var arena = MockArena{ .allocator = testing.allocator };
    var processor = EducationalProcessor{ .arena = &arena };
    
    const empty_notes = [_]EnhancedTimedNote{};
    const result = try processor.extractBaseNotesForMeasure(&empty_notes);
    
    try testing.expectEqual(@as(usize, 0), result.len);
    try testing.expectEqual(@as(usize, 0), arena.allocation_count);
}

test "extractBaseNotesForMeasure - single note extraction" {
    var arena = MockArena{ .allocator = testing.allocator };
    var processor = EducationalProcessor{ .arena = &arena };
    
    var enhanced_notes = [_]EnhancedTimedNote{
        createEnhancedNote(createTestNote(60, 0, 480)),
    };
    
    const result = try processor.extractBaseNotesForMeasure(&enhanced_notes);
    defer testing.allocator.free(result);
    
    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(@as(u8, 60), result[0].note);
    try testing.expectEqual(@as(u32, 0), result[0].start_tick);
    try testing.expectEqual(@as(u32, 480), result[0].duration);
    try testing.expectEqual(@as(usize, 1), arena.allocation_count);
}

test "extractBaseNotesForMeasure - multiple notes extraction" {
    var arena = MockArena{ .allocator = testing.allocator };
    var processor = EducationalProcessor{ .arena = &arena };
    
    var enhanced_notes = [_]EnhancedTimedNote{
        createEnhancedNote(createTestNote(60, 0, 480)),
        createEnhancedNote(createTestNote(64, 480, 480)),
        createEnhancedNote(createTestNote(67, 960, 480)),
    };
    
    const result = try processor.extractBaseNotesForMeasure(&enhanced_notes);
    defer testing.allocator.free(result);
    
    try testing.expectEqual(@as(usize, 3), result.len);
    
    // Verify each note is correctly extracted
    for (result, enhanced_notes) |base, enhanced| {
        try testing.expectEqual(enhanced.base_note.note, base.note);
        try testing.expectEqual(enhanced.base_note.start_tick, base.start_tick);
        try testing.expectEqual(enhanced.base_note.duration, base.duration);
    }
}

test "extractBaseNotesForMeasure - preserves all fields" {
    var arena = MockArena{ .allocator = testing.allocator };
    var processor = EducationalProcessor{ .arena = &arena };
    
    const enhanced_note = EnhancedTimedNote{
        .base_note = .{
            .note = 72,
            .channel = 3,
            .velocity = 100,
            .start_tick = 1920,
            .duration = 960,
            .tied_to_next = true,
            .tied_from_previous = false,
            .track_index = 2,
        },
    };
    
    var enhanced_notes = [_]EnhancedTimedNote{enhanced_note};
    
    const result = try processor.extractBaseNotesForMeasure(&enhanced_notes);
    defer testing.allocator.free(result);
    
    try testing.expectEqual(@as(usize, 1), result.len);
    
    const extracted = result[0];
    try testing.expectEqual(@as(u8, 72), extracted.note);
    try testing.expectEqual(@as(u8, 3), extracted.channel);
    try testing.expectEqual(@as(u8, 100), extracted.velocity);
    try testing.expectEqual(@as(u32, 1920), extracted.start_tick);
    try testing.expectEqual(@as(u32, 960), extracted.duration);
    try testing.expectEqual(true, extracted.tied_to_next);
    try testing.expectEqual(false, extracted.tied_from_previous);
    try testing.expectEqual(@as(u8, 2), extracted.track_index);
}

test "extractBaseNotesForMeasure - stress test" {
    var arena = MockArena{ .allocator = testing.allocator };
    var processor = EducationalProcessor{ .arena = &arena };
    
    const note_count = 1000;
    var enhanced_notes = try testing.allocator.alloc(EnhancedTimedNote, note_count);
    defer testing.allocator.free(enhanced_notes);
    
    for (0..note_count) |i| {
        const note_num: u8 = @intCast(48 + (i % 36));
        const start: u32 = @intCast(i * 60);
        enhanced_notes[i] = createEnhancedNote(createTestNote(note_num, start, 60));
    }
    
    const result = try processor.extractBaseNotesForMeasure(enhanced_notes);
    defer testing.allocator.free(result);
    
    try testing.expectEqual(note_count, result.len);
    try testing.expectEqual(@as(usize, 1), arena.allocation_count);
    
    // Verify all notes extracted correctly
    for (result, enhanced_notes) |base, enhanced| {
        try testing.expectEqual(enhanced.base_note.note, base.note);
        try testing.expectEqual(enhanced.base_note.start_tick, base.start_tick);
    }
}
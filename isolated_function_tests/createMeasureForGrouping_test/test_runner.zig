const std = @import("std");
const testing = std.testing;

// ==== MINIMAL DEPENDENCIES ====

// TimeSignatureEvent from midi_parser
pub const TimeSignatureEvent = struct {
    tick: u32,
    numerator: u8,
    denominator_power: u8,
    clocks_per_metronome: u8,
    thirtysecond_notes_per_quarter: u8,
};

// TimedNote from measure_detector
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

// Measure from measure_detector
pub const Measure = struct {
    number: u32,
    start_tick: u32,
    end_tick: u32,
    time_signature: TimeSignatureEvent,
    notes: std.ArrayList(TimedNote),
    
    pub fn init(allocator: std.mem.Allocator, number: u32, start_tick: u32, end_tick: u32, time_signature: TimeSignatureEvent) Measure {
        return Measure{
            .number = number,
            .start_tick = start_tick,
            .end_tick = end_tick,
            .time_signature = time_signature,
            .notes = std.ArrayList(TimedNote).init(allocator),
        };
    }
    
    pub fn deinit(self: *Measure) void {
        self.notes.deinit();
    }
    
    pub fn addNote(self: *Measure, note: TimedNote) std.mem.Allocator.Error!void {
        try self.notes.append(note);
    }
};

// MeasureInfo from educational_processor
pub const MeasureInfo = struct {
    notes: []TimedNote,  // Simplified - just using TimedNote instead of EnhancedTimedNote
    start_tick: u32,
    end_tick: u32,
    time_signature: TimeSignatureEvent,
};

// Mock EducationalArena
pub const MockArena = struct {
    allocator_impl: std.mem.Allocator,
    
    pub fn init(base_allocator: std.mem.Allocator) MockArena {
        return .{
            .allocator_impl = base_allocator,
        };
    }
    
    pub fn allocator(self: *MockArena) std.mem.Allocator {
        return self.allocator_impl;
    }
};

// Mock EducationalProcessor
pub const EducationalProcessor = struct {
    arena: *MockArena,
    
    pub fn init(arena: *MockArena) EducationalProcessor {
        return .{
            .arena = arena,
        };
    }
    
    // ==== SIMPLIFIED FUNCTION - Using appendSlice ====
    fn createMeasureForGrouping(
        self: *EducationalProcessor,
        measure_info: MeasureInfo,
        base_notes: []const TimedNote,
        time_sig: TimeSignatureEvent
    ) !Measure {
        var measure = Measure.init(
            self.arena.allocator(),
            1, // Measure number
            measure_info.start_tick,
            measure_info.end_tick,
            time_sig
        );
        
        // Add all notes at once
        try measure.notes.appendSlice(base_notes);
        
        return measure;
    }
};

// ==== TEST HELPER FUNCTIONS ====

fn createTestNote(note: u8, start: u32, duration: u32) TimedNote {
    return TimedNote{
        .note = note,
        .channel = 0,
        .velocity = 64,
        .start_tick = start,
        .duration = duration,
        .tied_to_next = false,
        .tied_from_previous = false,
        .track = 0,
        .voice = 1,
    };
}

fn createTestTimeSignature() TimeSignatureEvent {
    return TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
}

// ==== MAIN FUNCTION FOR TESTING ====

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Testing createMeasureForGrouping function...\n", .{});
    
    // Test Case 1: Empty notes
    {
        var arena = MockArena.init(allocator);
        var processor = EducationalProcessor.init(&arena);
        
        const measure_info = MeasureInfo{
            .notes = &[_]TimedNote{},
            .start_tick = 0,
            .end_tick = 1920,
            .time_signature = createTestTimeSignature(),
        };
        
        const empty_notes = [_]TimedNote{};
        var measure = try processor.createMeasureForGrouping(measure_info, &empty_notes, createTestTimeSignature());
        defer measure.deinit();
        
        std.debug.print("Test 1 - Empty notes: ", .{});
        std.debug.print("Created measure with {} notes\n", .{measure.notes.items.len});
    }
    
    // Test Case 2: Single note
    {
        var arena = MockArena.init(allocator);
        var processor = EducationalProcessor.init(&arena);
        
        const test_notes = [_]TimedNote{
            createTestNote(60, 0, 480),
        };
        
        const measure_info = MeasureInfo{
            .notes = @constCast(&test_notes),
            .start_tick = 0,
            .end_tick = 1920,
            .time_signature = createTestTimeSignature(),
        };
        
        var measure = try processor.createMeasureForGrouping(measure_info, &test_notes, createTestTimeSignature());
        defer measure.deinit();
        
        std.debug.print("Test 2 - Single note: ", .{});
        std.debug.print("Created measure with {} notes\n", .{measure.notes.items.len});
    }
    
    // Test Case 3: Multiple notes
    {
        var arena = MockArena.init(allocator);
        var processor = EducationalProcessor.init(&arena);
        
        const test_notes = [_]TimedNote{
            createTestNote(60, 0, 480),
            createTestNote(62, 480, 480),
            createTestNote(64, 960, 480),
            createTestNote(65, 1440, 480),
        };
        
        const measure_info = MeasureInfo{
            .notes = @constCast(&test_notes),
            .start_tick = 0,
            .end_tick = 1920,
            .time_signature = createTestTimeSignature(),
        };
        
        var measure = try processor.createMeasureForGrouping(measure_info, &test_notes, createTestTimeSignature());
        defer measure.deinit();
        
        std.debug.print("Test 3 - Multiple notes: ", .{});
        std.debug.print("Created measure with {} notes\n", .{measure.notes.items.len});
    }
    
    // Test Case 4: Different time signature
    {
        var arena = MockArena.init(allocator);
        var processor = EducationalProcessor.init(&arena);
        
        const test_notes = [_]TimedNote{
            createTestNote(67, 0, 320),
            createTestNote(69, 320, 320),
            createTestNote(71, 640, 320),
        };
        
        const time_sig_6_8 = TimeSignatureEvent{
            .tick = 0,
            .numerator = 6,
            .denominator_power = 3,
            .clocks_per_metronome = 24,
            .thirtysecond_notes_per_quarter = 8,
        };
        
        const measure_info = MeasureInfo{
            .notes = @constCast(&test_notes),
            .start_tick = 0,
            .end_tick = 1440,
            .time_signature = time_sig_6_8,
        };
        
        var measure = try processor.createMeasureForGrouping(measure_info, &test_notes, time_sig_6_8);
        defer measure.deinit();
        
        std.debug.print("Test 4 - 6/8 time: ", .{});
        std.debug.print("Created measure with {} notes, time sig {}/{}\n", .{
            measure.notes.items.len,
            measure.time_signature.numerator,
            measure.time_signature.denominator_power,
        });
    }
    
    std.debug.print("\nAll tests completed successfully!\n", .{});
}

// ==== UNIT TESTS ====

test "createMeasureForGrouping - empty notes" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor.init(&arena);
    
    const measure_info = MeasureInfo{
        .notes = &[_]TimedNote{},
        .start_tick = 0,
        .end_tick = 1920,
        .time_signature = createTestTimeSignature(),
    };
    
    const empty_notes = [_]TimedNote{};
    var measure = try processor.createMeasureForGrouping(measure_info, &empty_notes, createTestTimeSignature());
    defer measure.deinit();
    
    try testing.expectEqual(@as(usize, 0), measure.notes.items.len);
    try testing.expectEqual(@as(u32, 1), measure.number);
    try testing.expectEqual(@as(u32, 0), measure.start_tick);
    try testing.expectEqual(@as(u32, 1920), measure.end_tick);
}

test "createMeasureForGrouping - single note" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor.init(&arena);
    
    const test_notes = [_]TimedNote{
        createTestNote(60, 0, 480),
    };
    
    const measure_info = MeasureInfo{
        .notes = @constCast(&test_notes),
        .start_tick = 0,
        .end_tick = 1920,
        .time_signature = createTestTimeSignature(),
    };
    
    var measure = try processor.createMeasureForGrouping(measure_info, &test_notes, createTestTimeSignature());
    defer measure.deinit();
    
    try testing.expectEqual(@as(usize, 1), measure.notes.items.len);
    try testing.expectEqual(@as(u8, 60), measure.notes.items[0].note);
}

test "createMeasureForGrouping - multiple notes" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor.init(&arena);
    
    const test_notes = [_]TimedNote{
        createTestNote(60, 0, 480),
        createTestNote(62, 480, 480),
        createTestNote(64, 960, 480),
    };
    
    const measure_info = MeasureInfo{
        .notes = @constCast(&test_notes),
        .start_tick = 0,
        .end_tick = 1920,
        .time_signature = createTestTimeSignature(),
    };
    
    var measure = try processor.createMeasureForGrouping(measure_info, &test_notes, createTestTimeSignature());
    defer measure.deinit();
    
    try testing.expectEqual(@as(usize, 3), measure.notes.items.len);
    
    // Verify notes are copied correctly
    for (test_notes, 0..) |expected, i| {
        const actual = measure.notes.items[i];
        try testing.expectEqual(expected.note, actual.note);
        try testing.expectEqual(expected.start_tick, actual.start_tick);
        try testing.expectEqual(expected.duration, actual.duration);
    }
}

test "createMeasureForGrouping - preserves time signature" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor.init(&arena);
    
    const time_sig_3_4 = TimeSignatureEvent{
        .tick = 0,
        .numerator = 3,
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    const test_notes = [_]TimedNote{
        createTestNote(72, 0, 480),
    };
    
    const measure_info = MeasureInfo{
        .notes = @constCast(&test_notes),
        .start_tick = 0,
        .end_tick = 1440,
        .time_signature = time_sig_3_4,
    };
    
    var measure = try processor.createMeasureForGrouping(measure_info, &test_notes, time_sig_3_4);
    defer measure.deinit();
    
    try testing.expectEqual(@as(u8, 3), measure.time_signature.numerator);
    try testing.expectEqual(@as(u8, 2), measure.time_signature.denominator_power);
}

test "createMeasureForGrouping - preserves measure boundaries" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor.init(&arena);
    
    const measure_info = MeasureInfo{
        .notes = &[_]TimedNote{},
        .start_tick = 1920,
        .end_tick = 3840,
        .time_signature = createTestTimeSignature(),
    };
    
    const empty_notes = [_]TimedNote{};
    var measure = try processor.createMeasureForGrouping(measure_info, &empty_notes, createTestTimeSignature());
    defer measure.deinit();
    
    try testing.expectEqual(@as(u32, 1920), measure.start_tick);
    try testing.expectEqual(@as(u32, 3840), measure.end_tick);
}
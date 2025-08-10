const std = @import("std");
const t = @import("../../src/test_utils.zig");

// ============================================================================
// REQUIRED STRUCTS AND DEPENDENCIES
// ============================================================================

// Time signature event from MIDI parser
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

// Timed note structure
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

// Enhanced timed note structure
pub const EnhancedTimedNote = struct {
    base_note: TimedNote,
    // Other fields omitted as they're not needed for this function
};

// Gap structure for rest optimization
pub const Gap = struct {
    start_time: u32,
    duration: u32,
    measure_number: u32,
};

// Measure info structure
pub const MeasureInfo = struct {
    notes: []EnhancedTimedNote,
    start_tick: u32,
    end_tick: u32,
    time_signature: TimeSignatureEvent,
};

// Mock educational arena for memory allocation
pub const MockArena = struct {
    allocator_impl: std.mem.Allocator,
    
    pub fn init(backing_allocator: std.mem.Allocator) MockArena {
        return .{
            .allocator_impl = backing_allocator,
        };
    }
    
    pub fn allocator(self: *MockArena) std.mem.Allocator {
        return self.allocator_impl;
    }
    
    pub fn allocForEducational(self: *MockArena, comptime T: type, count: usize) ![]T {
        return self.allocator_impl.alloc(T, count);
    }
};

// Mock processor struct
pub const MockProcessor = struct {
    arena: *MockArena,
};

// ============================================================================
// FUNCTION UNDER TEST - SIMPLIFIED VERSION
// ============================================================================

fn detectGapsInMeasure(self: *MockProcessor, measure: MeasureInfo) ![]Gap {
    const measure_duration = measure.end_tick - measure.start_tick;
    const measure_number = @as(u32, @intCast(measure.start_tick / measure_duration + 1));
    
    if (measure.notes.len == 0) {
        const gaps = try self.arena.allocForEducational(Gap, 1);
        gaps[0] = Gap{
            .start_time = measure.start_tick,
            .duration = measure_duration,
            .measure_number = measure_number,
        };
        return gaps;
    }
    
    // Sort notes by start time using std.sort
    const sorted_notes = try self.arena.allocForEducational(EnhancedTimedNote, measure.notes.len);
    @memcpy(sorted_notes, measure.notes);
    std.mem.sort(EnhancedTimedNote, sorted_notes, {}, struct {
        fn lessThan(_: void, a: EnhancedTimedNote, b: EnhancedTimedNote) bool {
            return a.base_note.start_tick < b.base_note.start_tick;
        }
    }.lessThan);
    
    // Two-pass approach: first count gaps, then allocate exact size
    var gap_count: usize = 0;
    var current_position = measure.start_tick;
    
    // First pass: count gaps
    for (sorted_notes) |note| {
        if (note.base_note.velocity == 0) continue;
        const note_start = note.base_note.start_tick;
        const note_end = note_start + note.base_note.duration;
        
        if (note_start > current_position) gap_count += 1;
        current_position = @max(current_position, note_end);
    }
    if (current_position < measure.end_tick) gap_count += 1;
    
    // Early return if no gaps
    if (gap_count == 0) {
        return &[_]Gap{};
    }
    
    // Allocate exact size needed
    const gaps = try self.arena.allocForEducational(Gap, gap_count);
    var gap_index: usize = 0;
    current_position = measure.start_tick;
    
    // Second pass: fill gaps
    for (sorted_notes) |note| {
        if (note.base_note.velocity == 0) continue;
        const note_start = note.base_note.start_tick;
        const note_end = note_start + note.base_note.duration;
        
        if (note_start > current_position) {
            gaps[gap_index] = Gap{
                .start_time = current_position,
                .duration = note_start - current_position,
                .measure_number = measure_number,
            };
            gap_index += 1;
        }
        current_position = @max(current_position, note_end);
    }
    
    if (current_position < measure.end_tick) {
        gaps[gap_index] = Gap{
            .start_time = current_position,
            .duration = measure.end_tick - current_position,
            .measure_number = measure_number,
        };
    }
    
    return gaps;
}

// ============================================================================
// TEST CASES
// ============================================================================

fn printGaps(gaps: []const Gap) void {
    std.debug.print("Gaps found: {}\n", .{gaps.len});
    for (gaps, 0..) |gap, i| {
        std.debug.print("  Gap {}: start={}, duration={}, measure={}\n", .{ 
            i, gap.start_time, gap.duration, gap.measure_number 
        });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var arena = MockArena.init(allocator);
    var processor = MockProcessor{ .arena = &arena };
    
    // Test 1: Empty measure
    {
        std.debug.print("\n=== Test 1: Empty measure ===\n", .{});
        const measure = MeasureInfo{
            .notes = &[_]EnhancedTimedNote{},
            .start_tick = 0,
            .end_tick = 1920,
            .time_signature = TimeSignatureEvent{
                .tick = 0,
                .numerator = 4,
                .denominator_power = 2,
                .clocks_per_metronome = 24,
                .thirtysecond_notes_per_quarter = 8,
            },
        };
        
        const gaps = try detectGapsInMeasure(&processor, measure);
        defer allocator.free(gaps);
        printGaps(gaps);
    }
    
    // Test 2: Single note with gaps before and after
    {
        std.debug.print("\n=== Test 2: Single note with gaps ===\n", .{});
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 480,
                .duration = 480,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = 0,
                .voice = 1,
            }},
        };
        
        const measure = MeasureInfo{
            .notes = &notes,
            .start_tick = 0,
            .end_tick = 1920,
            .time_signature = TimeSignatureEvent{
                .tick = 0,
                .numerator = 4,
                .denominator_power = 2,
                .clocks_per_metronome = 24,
                .thirtysecond_notes_per_quarter = 8,
            },
        };
        
        const gaps = try detectGapsInMeasure(&processor, measure);
        defer allocator.free(gaps);
        printGaps(gaps);
    }
    
    // Test 3: Multiple notes with gaps
    {
        std.debug.print("\n=== Test 3: Multiple notes with gaps ===\n", .{});
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 240,
                .duration = 240,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = 0,
                .voice = 1,
            }},
            .{ .base_note = TimedNote{
                .note = 62,
                .channel = 0,
                .velocity = 64,
                .start_tick = 720,
                .duration = 480,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = 0,
                .voice = 1,
            }},
            .{ .base_note = TimedNote{
                .note = 64,
                .channel = 0,
                .velocity = 64,
                .start_tick = 1440,
                .duration = 240,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = 0,
                .voice = 1,
            }},
        };
        
        const measure = MeasureInfo{
            .notes = &notes,
            .start_tick = 0,
            .end_tick = 1920,
            .time_signature = TimeSignatureEvent{
                .tick = 0,
                .numerator = 4,
                .denominator_power = 2,
                .clocks_per_metronome = 24,
                .thirtysecond_notes_per_quarter = 8,
            },
        };
        
        const gaps = try detectGapsInMeasure(&processor, measure);
        defer allocator.free(gaps);
        printGaps(gaps);
    }
    
    // Test 4: Notes out of order (needs sorting)
    {
        std.debug.print("\n=== Test 4: Unsorted notes ===\n", .{});
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = TimedNote{
                .note = 64,
                .channel = 0,
                .velocity = 64,
                .start_tick = 960,
                .duration = 480,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = 0,
                .voice = 1,
            }},
            .{ .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = 0,
                .voice = 1,
            }},
        };
        
        const measure = MeasureInfo{
            .notes = &notes,
            .start_tick = 0,
            .end_tick = 1920,
            .time_signature = TimeSignatureEvent{
                .tick = 0,
                .numerator = 4,
                .denominator_power = 2,
                .clocks_per_metronome = 24,
                .thirtysecond_notes_per_quarter = 8,
            },
        };
        
        const gaps = try detectGapsInMeasure(&processor, measure);
        defer allocator.free(gaps);
        printGaps(gaps);
    }
    
    // Test 5: Overlapping notes
    {
        std.debug.print("\n=== Test 5: Overlapping notes ===\n", .{});
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 960,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = 0,
                .voice = 1,
            }},
            .{ .base_note = TimedNote{
                .note = 64,
                .channel = 0,
                .velocity = 64,
                .start_tick = 480,
                .duration = 960,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = 0,
                .voice = 2,
            }},
        };
        
        const measure = MeasureInfo{
            .notes = &notes,
            .start_tick = 0,
            .end_tick = 1920,
            .time_signature = TimeSignatureEvent{
                .tick = 0,
                .numerator = 4,
                .denominator_power = 2,
                .clocks_per_metronome = 24,
                .thirtysecond_notes_per_quarter = 8,
            },
        };
        
        const gaps = try detectGapsInMeasure(&processor, measure);
        defer allocator.free(gaps);
        printGaps(gaps);
    }
    
    // Test 6: Notes with rests (velocity = 0)
    {
        std.debug.print("\n=== Test 6: Notes with rests (velocity=0) ===\n", .{});
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = 0,
                .voice = 1,
            }},
            .{ .base_note = TimedNote{
                .note = 0,
                .channel = 0,
                .velocity = 0, // Rest
                .start_tick = 480,
                .duration = 480,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = 0,
                .voice = 1,
            }},
            .{ .base_note = TimedNote{
                .note = 62,
                .channel = 0,
                .velocity = 64,
                .start_tick = 960,
                .duration = 480,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = 0,
                .voice = 1,
            }},
        };
        
        const measure = MeasureInfo{
            .notes = &notes,
            .start_tick = 0,
            .end_tick = 1920,
            .time_signature = TimeSignatureEvent{
                .tick = 0,
                .numerator = 4,
                .denominator_power = 2,
                .clocks_per_metronome = 24,
                .thirtysecond_notes_per_quarter = 8,
            },
        };
        
        const gaps = try detectGapsInMeasure(&processor, measure);
        defer allocator.free(gaps);
        printGaps(gaps);
    }
    
    std.debug.print("\n=== All tests completed ===\n", .{});
}

// ============================================================================
// UNIT TESTS
// ============================================================================

test "detectGapsInMeasure - empty measure" {
    var arena = MockArena.init(std.testing.allocator);
    var processor = MockProcessor{ .arena = &arena };
    
    const measure = MeasureInfo{
        .notes = &[_]EnhancedTimedNote{},
        .start_tick = 0,
        .end_tick = 1920,
        .time_signature = TimeSignatureEvent{
            .tick = 0,
            .numerator = 4,
            .denominator_power = 2,
            .clocks_per_metronome = 24,
            .thirtysecond_notes_per_quarter = 8,
        },
    };
    
    const gaps = try detectGapsInMeasure(&processor, measure);
    defer std.testing.allocator.free(gaps);
    
    try t.expectEq(@as(usize, 1), gaps.len);
    try t.expectEq(@as(u32, 0), gaps[0].start_time);
    try t.expectEq(@as(u32, 1920), gaps[0].duration);
    try t.expectEq(@as(u32, 1), gaps[0].measure_number);
}

test "detectGapsInMeasure - single note with gaps" {
    var arena = MockArena.init(std.testing.allocator);
    var processor = MockProcessor{ .arena = &arena };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = TimedNote{
            .note = 60,
            .channel = 0,
            .velocity = 64,
            .start_tick = 480,
            .duration = 480,
            .tied_to_next = false,
            .tied_from_previous = false,
            .track = 0,
            .voice = 1,
        }},
    };
    
    const measure = MeasureInfo{
        .notes = &notes,
        .start_tick = 0,
        .end_tick = 1920,
        .time_signature = TimeSignatureEvent{
            .tick = 0,
            .numerator = 4,
            .denominator_power = 2,
            .clocks_per_metronome = 24,
            .thirtysecond_notes_per_quarter = 8,
        },
    };
    
    const gaps = try detectGapsInMeasure(&processor, measure);
    defer std.testing.allocator.free(gaps);
    
    try t.expectEq(@as(usize, 2), gaps.len);
    // First gap: 0-480
    try t.expectEq(@as(u32, 0), gaps[0].start_time);
    try t.expectEq(@as(u32, 480), gaps[0].duration);
    // Second gap: 960-1920
    try t.expectEq(@as(u32, 960), gaps[1].start_time);
    try t.expectEq(@as(u32, 960), gaps[1].duration);
}

test "detectGapsInMeasure - no gaps" {
    var arena = MockArena.init(std.testing.allocator);
    var processor = MockProcessor{ .arena = &arena };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = TimedNote{
            .note = 60,
            .channel = 0,
            .velocity = 64,
            .start_tick = 0,
            .duration = 1920,
            .tied_to_next = false,
            .tied_from_previous = false,
            .track = 0,
            .voice = 1,
        }},
    };
    
    const measure = MeasureInfo{
        .notes = &notes,
        .start_tick = 0,
        .end_tick = 1920,
        .time_signature = TimeSignatureEvent{
            .tick = 0,
            .numerator = 4,
            .denominator_power = 2,
            .clocks_per_metronome = 24,
            .thirtysecond_notes_per_quarter = 8,
        },
    };
    
    const gaps = try detectGapsInMeasure(&processor, measure);
    defer std.testing.allocator.free(gaps);
    
    try t.expectEq(@as(usize, 0), gaps.len);
}

test "detectGapsInMeasure - rest notes ignored" {
    var arena = MockArena.init(std.testing.allocator);
    var processor = MockProcessor{ .arena = &arena };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = TimedNote{
            .note = 0,
            .channel = 0,
            .velocity = 0, // Rest note
            .start_tick = 0,
            .duration = 1920,
            .tied_to_next = false,
            .tied_from_previous = false,
            .track = 0,
            .voice = 1,
        }},
    };
    
    const measure = MeasureInfo{
        .notes = &notes,
        .start_tick = 0,
        .end_tick = 1920,
        .time_signature = TimeSignatureEvent{
            .tick = 0,
            .numerator = 4,
            .denominator_power = 2,
            .clocks_per_metronome = 24,
            .thirtysecond_notes_per_quarter = 8,
        },
    };
    
    const gaps = try detectGapsInMeasure(&processor, measure);
    defer std.testing.allocator.free(gaps);
    
    // Should detect a gap for the entire measure since rest notes are ignored
    try t.expectEq(@as(usize, 1), gaps.len);
    try t.expectEq(@as(u32, 0), gaps[0].start_time);
    try t.expectEq(@as(u32, 1920), gaps[0].duration);
}

test "detectGapsInMeasure - sorting works correctly" {
    var arena = MockArena.init(std.testing.allocator);
    var processor = MockProcessor{ .arena = &arena };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = TimedNote{
            .note = 64,
            .channel = 0,
            .velocity = 64,
            .start_tick = 960,
            .duration = 480,
            .tied_to_next = false,
            .tied_from_previous = false,
            .track = 0,
            .voice = 1,
        }},
        .{ .base_note = TimedNote{
            .note = 60,
            .channel = 0,
            .velocity = 64,
            .start_tick = 0,
            .duration = 480,
            .tied_to_next = false,
            .tied_from_previous = false,
            .track = 0,
            .voice = 1,
        }},
    };
    
    const measure = MeasureInfo{
        .notes = &notes,
        .start_tick = 0,
        .end_tick = 1920,
        .time_signature = TimeSignatureEvent{
            .tick = 0,
            .numerator = 4,
            .denominator_power = 2,
            .clocks_per_metronome = 24,
            .thirtysecond_notes_per_quarter = 8,
        },
    };
    
    const gaps = try detectGapsInMeasure(&processor, measure);
    defer std.testing.allocator.free(gaps);
    
    try t.expectEq(@as(usize, 2), gaps.len);
    // Gap between notes: 480-960
    try t.expectEq(@as(u32, 480), gaps[0].start_time);
    try t.expectEq(@as(u32, 480), gaps[0].duration);
    // Gap at end: 1440-1920
    try t.expectEq(@as(u32, 1440), gaps[1].start_time);
    try t.expectEq(@as(u32, 480), gaps[1].duration);
}
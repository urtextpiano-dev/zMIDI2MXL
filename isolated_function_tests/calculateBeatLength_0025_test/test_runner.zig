const std = @import("std");
const testing = std.testing;

// =============================================================================
// MINIMAL DEPENDENCIES
// =============================================================================

/// Simplified TimedNote struct with only required fields
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

/// Mock Arena for testing memory allocation
const MockArena = struct {
    allocator_impl: std.mem.Allocator,
    
    pub fn allocator(self: *MockArena) std.mem.Allocator {
        return self.allocator_impl;
    }
    
    pub fn init(alloc: std.mem.Allocator) MockArena {
        return .{
            .allocator_impl = alloc,
        };
    }
};

/// Mock EducationalProcessor with minimal required fields
const EducationalProcessor = struct {
    arena: *MockArena,
};

// =============================================================================
// ORIGINAL FUNCTION IMPLEMENTATION (Lines 1396-1422)
// =============================================================================

fn calculateBeatLength_ORIGINAL(self: *EducationalProcessor, notes: []const TimedNote) u32 {
    
    if (notes.len < 2) return 480; // Default quarter note length
    
    // Find the most common interval between consecutive note starts
    // This is a simple heuristic - could be improved with more sophisticated analysis
    var intervals = std.ArrayList(u32).init(self.arena.allocator());
    defer intervals.deinit();
    
    for (0..notes.len - 1) |i| {
        const interval = notes[i + 1].start_tick - notes[i].start_tick;
        if (interval > 0 and interval <= 960) { // Reasonable range for beat subdivisions
            intervals.append(interval) catch continue;
        }
    }
    
    if (intervals.items.len == 0) return 480;
    
    // For simplicity, use the first interval multiplied by a reasonable factor
    // This could be enhanced with statistical analysis
    const base_interval = intervals.items[0];
    
    // If the interval looks like a subdivision, multiply to get beat length
    if (base_interval <= 120) return base_interval * 4; // Sixteenth notes -> quarter note
    if (base_interval <= 240) return base_interval * 2; // Eighth notes -> quarter note
    return base_interval; // Assume it's already a beat length
}

// =============================================================================
// SIMPLIFIED FUNCTION IMPLEMENTATION
// =============================================================================

fn calculateBeatLength(self: *EducationalProcessor, notes: []const TimedNote) u32 {
    _ = self; // Function doesn't actually need self
    
    if (notes.len < 2) return 480;
    
    // Early return pattern: find first valid interval and process immediately
    for (0..notes.len - 1) |i| {
        const interval = notes[i + 1].start_tick - notes[i].start_tick;
        
        // Skip invalid intervals
        if (interval == 0 or interval > 960) continue;
        
        // Return immediately with appropriate multiplier
        return if (interval <= 120) interval * 4  // Sixteenth notes
               else if (interval <= 240) interval * 2  // Eighth notes  
               else interval;  // Quarter notes or larger
    }
    
    return 480; // Default if no valid intervals found
}

// =============================================================================
// TEST CASES
// =============================================================================

test "calculateBeatLength: empty array returns default" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor{ .arena = &arena };
    
    const notes: []const TimedNote = &[_]TimedNote{};
    const result = calculateBeatLength(&processor, notes);
    try testing.expectEqual(@as(u32, 480), result);
}

test "calculateBeatLength: single note returns default" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor{ .arena = &arena };
    
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480 },
    };
    const result = calculateBeatLength(&processor, &notes);
    try testing.expectEqual(@as(u32, 480), result);
}

test "calculateBeatLength: sixteenth notes pattern" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor{ .arena = &arena };
    
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 120 },
        .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 120, .duration = 120 },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 240, .duration = 120 },
        .{ .note = 65, .channel = 0, .velocity = 80, .start_tick = 360, .duration = 120 },
    };
    const result = calculateBeatLength(&processor, &notes);
    try testing.expectEqual(@as(u32, 480), result); // 120 * 4 = 480
}

test "calculateBeatLength: eighth notes pattern" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor{ .arena = &arena };
    
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 240 },
        .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 240, .duration = 240 },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 240 },
        .{ .note = 65, .channel = 0, .velocity = 80, .start_tick = 720, .duration = 240 },
    };
    const result = calculateBeatLength(&processor, &notes);
    try testing.expectEqual(@as(u32, 480), result); // 240 * 2 = 480
}

test "calculateBeatLength: quarter notes pattern" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor{ .arena = &arena };
    
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480 },
        .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 480 },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 960, .duration = 480 },
    };
    const result = calculateBeatLength(&processor, &notes);
    try testing.expectEqual(@as(u32, 480), result); // 480 is already beat length
}

test "calculateBeatLength: no valid intervals returns default" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor{ .arena = &arena };
    
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480 },
        .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 2000, .duration = 480 }, // Large gap > 960
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 4000, .duration = 480 }, // Large gap > 960
    };
    const result = calculateBeatLength(&processor, &notes);
    try testing.expectEqual(@as(u32, 480), result);
}

test "calculateBeatLength: mixed intervals uses first valid" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor{ .arena = &arena };
    
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 240 },
        .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 240, .duration = 120 }, // 240 interval
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 360, .duration = 360 }, // 120 interval
        .{ .note = 65, .channel = 0, .velocity = 80, .start_tick = 720, .duration = 240 }, // 360 interval
    };
    const result = calculateBeatLength(&processor, &notes);
    try testing.expectEqual(@as(u32, 480), result); // First interval 240 * 2 = 480
}

test "calculateBeatLength: verify equivalence with original" {
    var arena = MockArena.init(testing.allocator);
    var processor = EducationalProcessor{ .arena = &arena };
    
    // Test various scenarios to ensure both implementations are equivalent
    const test_cases = [_][]const TimedNote{
        &[_]TimedNote{}, // Empty
        &[_]TimedNote{.{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480 }}, // Single
        &[_]TimedNote{ // Sixteenth notes
            .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 120 },
            .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 120, .duration = 120 },
        },
        &[_]TimedNote{ // Zero interval (same start time)
            .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 100, .duration = 120 },
            .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 100, .duration = 120 },
        },
        &[_]TimedNote{ // Large interval > 960
            .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480 },
            .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 1000, .duration = 480 },
        },
    };
    
    for (test_cases) |notes| {
        const original_result = calculateBeatLength_ORIGINAL(&processor, notes);
        const simplified_result = calculateBeatLength(&processor, notes);
        try testing.expectEqual(original_result, simplified_result);
    }
}

// =============================================================================
// MAIN FUNCTION FOR STANDALONE TESTING
// =============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var arena = MockArena.init(allocator);
    var processor = EducationalProcessor{ .arena = &arena };
    
    std.debug.print("=== calculateBeatLength Function Test Runner ===\n", .{});
    std.debug.print("\nRunning sample test cases:\n\n", .{});
    
    // Test 1: Empty array
    {
        const notes: []const TimedNote = &[_]TimedNote{};
        const result = calculateBeatLength(&processor, notes);
        std.debug.print("Test 1 - Empty array: {} (expected 480)\n", .{result});
    }
    
    // Test 2: Sixteenth notes
    {
        const notes = [_]TimedNote{
            .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 120 },
            .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 120, .duration = 120 },
            .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 240, .duration = 120 },
        };
        const result = calculateBeatLength(&processor, &notes);
        std.debug.print("Test 2 - Sixteenth notes (interval=120): {} (expected 480)\n", .{result});
    }
    
    // Test 3: Eighth notes
    {
        const notes = [_]TimedNote{
            .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 240 },
            .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 240, .duration = 240 },
            .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 240 },
        };
        const result = calculateBeatLength(&processor, &notes);
        std.debug.print("Test 3 - Eighth notes (interval=240): {} (expected 480)\n", .{result});
    }
    
    // Test 4: Quarter notes
    {
        const notes = [_]TimedNote{
            .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480 },
            .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 480 },
            .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 960, .duration = 480 },
        };
        const result = calculateBeatLength(&processor, &notes);
        std.debug.print("Test 4 - Quarter notes (interval=480): {} (expected 480)\n", .{result});
    }
    
    // Test 5: Half notes (interval > 480)
    {
        const notes = [_]TimedNote{
            .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 960 },
            .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 960, .duration = 960 },
        };
        const result = calculateBeatLength(&processor, &notes);
        std.debug.print("Test 5 - Half notes (interval=960): {} (expected 960)\n", .{result});
    }
    
    std.debug.print("\nAll test cases completed!\n", .{});
}
const std = @import("std");
const t = @import("../../src/test_utils.zig");
// Removed: const testing = std.testing;

// Mock structures needed for the function

// Minimal TimedNote structure
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

// TupletType enum
pub const TupletType = enum(u8) {
    triplet = 3,
    quintuplet = 5,
    septuplet = 7,
    duplet = 2,
    sextuplet = 6,
};

// Tuplet structure
pub const Tuplet = struct {
    tuplet_type: TupletType,
    start_tick: u32,
    end_tick: u32,
    notes: []const TimedNote,
    beat_unit: []const u8,
    confidence: f64,
};

// TupletInfo structure with tuplet pointer (as expected by the function)
pub const TupletInfo = struct {
    tuplet: ?*const Tuplet = null,
    tuplet_type: TupletType = .triplet,
    start_tick: u32 = 0,
    end_tick: u32 = 0,
    beat_unit: []const u8 = "quarter",
    position_in_tuplet: u8 = 0,
    confidence: f64 = 0.0,
    starts_tuplet: bool = false,
    ends_tuplet: bool = false,
};

// EnhancedTimedNote structure
pub const EnhancedTimedNote = struct {
    base_note: TimedNote,
    tuplet_info: ?*TupletInfo = null,
};

// TupletSpan structure (as defined in the original code)
const TupletSpan = struct {
    start_tick: u32,
    end_tick: u32,
    tuplet_ref: ?*const Tuplet,
    note_indices: std.ArrayList(usize),
    
    pub fn deinit(self: *TupletSpan) void {
        self.note_indices.deinit();
    }
};

// Mock Arena allocator
const MockArena = struct {
    allocator_instance: std.mem.Allocator,
    
    pub fn init(alloc: std.mem.Allocator) MockArena {
        return .{
            .allocator_instance = alloc,
        };
    }
    
    pub fn allocator(self: *MockArena) std.mem.Allocator {
        return self.allocator_instance;
    }
    
    pub fn deinit(self: *MockArena) void {
        _ = self;
    }
};

// Mock EducationalProcessor structure
const EducationalProcessor = struct {
    arena: *MockArena,
    
    // Original buildTupletSpans function
    fn buildTupletSpans_ORIGINAL(self: *EducationalProcessor, enhanced_notes: []EnhancedTimedNote) ![]TupletSpan {
        var spans = std.ArrayList(TupletSpan).init(self.arena.allocator());
        defer spans.deinit();
        errdefer {
            for (spans.items) |*span| {
                span.deinit();
            }
        }
        
        var current_tuplet: ?*const Tuplet = null;
        var current_span: ?*TupletSpan = null;
        
        for (enhanced_notes, 0..) |note, i| {
            if (note.tuplet_info) |info| {
                if (info.tuplet != current_tuplet) {
                    // New tuplet or end of previous
                    if (current_span) |span| {
                        span.end_tick = note.base_note.start_tick;
                    }
                    
                    if (info.tuplet) |tuplet| {
                        // Start new span
                        var new_span = TupletSpan{
                            .start_tick = note.base_note.start_tick,
                            .end_tick = note.base_note.start_tick + note.base_note.duration,
                            .tuplet_ref = tuplet,
                            .note_indices = std.ArrayList(usize).init(self.arena.allocator()),
                        };
                        try new_span.note_indices.append(i);
                        try spans.append(new_span);
                        current_span = &spans.items[spans.items.len - 1];
                        current_tuplet = tuplet;
                    } else {
                        current_span = null;
                        current_tuplet = null;
                    }
                } else if (current_span) |span| {
                    // Continue current tuplet
                    try span.note_indices.append(i);
                    span.end_tick = note.base_note.start_tick + note.base_note.duration;
                }
            } else {
                // Note not in tuplet
                if (current_span != null) {
                    current_span = null;
                    current_tuplet = null;
                }
            }
        }
        
        return try spans.toOwnedSlice();
    }
    
    // Simplified buildTupletSpans function
    fn buildTupletSpans(self: *EducationalProcessor, enhanced_notes: []EnhancedTimedNote) ![]TupletSpan {
        var spans = std.ArrayList(TupletSpan).init(self.arena.allocator());
        defer spans.deinit();
        errdefer {
            for (spans.items) |*span| {
                span.deinit();
            }
        }
        
        var current_tuplet: ?*const Tuplet = null;
        
        for (enhanced_notes, 0..) |note, i| {
            const note_tuplet = if (note.tuplet_info) |info| info.tuplet else null;
            
            // Check if we're transitioning to a different tuplet state
            if (note_tuplet != current_tuplet) {
                // Start a new span if we have a tuplet
                if (note_tuplet) |tuplet| {
                    var new_span = TupletSpan{
                        .start_tick = note.base_note.start_tick,
                        .end_tick = note.base_note.start_tick + note.base_note.duration,
                        .tuplet_ref = tuplet,
                        .note_indices = std.ArrayList(usize).init(self.arena.allocator()),
                    };
                    try new_span.note_indices.append(i);
                    try spans.append(new_span);
                }
                current_tuplet = note_tuplet;
            } else if (current_tuplet != null and spans.items.len > 0) {
                // Continue current tuplet - we know we have a span
                var span = &spans.items[spans.items.len - 1];
                try span.note_indices.append(i);
                span.end_tick = note.base_note.start_tick + note.base_note.duration;
            }
        }
        
        return try spans.toOwnedSlice();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create mock arena
    var arena = MockArena.init(allocator);
    defer arena.deinit();
    
    // Create processor
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    // Test Case 1: No tuplets
    {
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 240 } },
            .{ .base_note = .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 240, .duration = 240 } },
            .{ .base_note = .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 240 } },
        };
        
        const result = try processor.buildTupletSpans(&notes);
        defer allocator.free(result);
        for (result) |*span| {
            span.deinit();
        }
        
        std.debug.print("Test 1 - No tuplets: {} spans\n", .{result.len});
    }
    
    // Test Case 2: Single triplet
    {
        const tuplet = Tuplet{
            .tuplet_type = .triplet,
            .start_tick = 0,
            .end_tick = 240,
            .notes = &[_]TimedNote{},
            .beat_unit = "eighth",
            .confidence = 0.95,
        };
        
        var tuplet_info1 = TupletInfo{
            .tuplet = &tuplet,
            .tuplet_type = .triplet,
            .start_tick = 0,
            .end_tick = 240,
            .confidence = 0.95,
        };
        var tuplet_info2 = TupletInfo{
            .tuplet = &tuplet,
            .tuplet_type = .triplet,
            .start_tick = 0,
            .end_tick = 240,
            .confidence = 0.95,
        };
        var tuplet_info3 = TupletInfo{
            .tuplet = &tuplet,
            .tuplet_type = .triplet,
            .start_tick = 0,
            .end_tick = 240,
            .confidence = 0.95,
        };
        
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 80 }, .tuplet_info = &tuplet_info1 },
            .{ .base_note = .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 80, .duration = 80 }, .tuplet_info = &tuplet_info2 },
            .{ .base_note = .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 160, .duration = 80 }, .tuplet_info = &tuplet_info3 },
        };
        
        const result = try processor.buildTupletSpans(&notes);
        defer allocator.free(result);
        for (result) |*span| {
            std.debug.print("  Span: start={}, end={}, indices={}\n", .{ span.start_tick, span.end_tick, span.note_indices.items.len });
            span.deinit();
        }
        
        std.debug.print("Test 2 - Single triplet: {} spans\n", .{result.len});
    }
    
    // Test Case 3: Multiple tuplets
    {
        const tuplet1 = Tuplet{
            .tuplet_type = .triplet,
            .start_tick = 0,
            .end_tick = 240,
            .notes = &[_]TimedNote{},
            .beat_unit = "eighth",
            .confidence = 0.95,
        };
        
        const tuplet2 = Tuplet{
            .tuplet_type = .quintuplet,
            .start_tick = 480,
            .end_tick = 720,
            .notes = &[_]TimedNote{},
            .beat_unit = "eighth",
            .confidence = 0.90,
        };
        
        var tuplet_info1 = TupletInfo{ .tuplet = &tuplet1, .tuplet_type = .triplet, .confidence = 0.95 };
        var tuplet_info2 = TupletInfo{ .tuplet = &tuplet1, .tuplet_type = .triplet, .confidence = 0.95 };
        var tuplet_info3 = TupletInfo{ .tuplet = &tuplet2, .tuplet_type = .quintuplet, .confidence = 0.90 };
        var tuplet_info4 = TupletInfo{ .tuplet = &tuplet2, .tuplet_type = .quintuplet, .confidence = 0.90 };
        
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 80 }, .tuplet_info = &tuplet_info1 },
            .{ .base_note = .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 80, .duration = 80 }, .tuplet_info = &tuplet_info2 },
            .{ .base_note = .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 240, .duration = 240 } }, // Non-tuplet note
            .{ .base_note = .{ .note = 65, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 48 }, .tuplet_info = &tuplet_info3 },
            .{ .base_note = .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 528, .duration = 48 }, .tuplet_info = &tuplet_info4 },
        };
        
        const result = try processor.buildTupletSpans(&notes);
        defer allocator.free(result);
        for (result) |*span| {
            std.debug.print("  Span: start={}, end={}, indices={}\n", .{ span.start_tick, span.end_tick, span.note_indices.items.len });
            span.deinit();
        }
        
        std.debug.print("Test 3 - Multiple tuplets: {} spans\n", .{result.len});
    }
    
    std.debug.print("\nAll tests completed successfully!\n", .{});
}

// Unit tests
test "buildTupletSpans - no tuplets" {
    var arena = MockArena.init(testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 240 } },
        .{ .base_note = .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 240, .duration = 240 } },
    };
    
    const result = try processor.buildTupletSpans(&notes);
    defer testing.allocator.free(result);
    for (result) |*span| {
        span.deinit();
    }
    
    try t.expectEq(@as(usize, 0), result.len);
}

test "buildTupletSpans - single tuplet" {
    var arena = MockArena.init(testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    const tuplet = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 0,
        .end_tick = 240,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    var tuplet_info1 = TupletInfo{ .tuplet = &tuplet };
    var tuplet_info2 = TupletInfo{ .tuplet = &tuplet };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 120 }, .tuplet_info = &tuplet_info1 },
        .{ .base_note = .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 120, .duration = 120 }, .tuplet_info = &tuplet_info2 },
    };
    
    const result = try processor.buildTupletSpans(&notes);
    defer testing.allocator.free(result);
    defer for (result) |*span| {
        span.deinit();
    };
    
    try t.expectEq(@as(usize, 1), result.len);
    try t.expectEq(@as(u32, 0), result[0].start_tick);
    try t.expectEq(@as(u32, 240), result[0].end_tick);
    try t.expectEq(@as(usize, 2), result[0].note_indices.items.len);
}

test "buildTupletSpans - multiple separate tuplets" {
    var arena = MockArena.init(testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    const tuplet1 = Tuplet{
        .tuplet_type = .triplet,
        .start_tick = 0,
        .end_tick = 240,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.95,
    };
    
    const tuplet2 = Tuplet{
        .tuplet_type = .quintuplet,
        .start_tick = 480,
        .end_tick = 720,
        .notes = &[_]TimedNote{},
        .beat_unit = "eighth",
        .confidence = 0.90,
    };
    
    var tuplet_info1 = TupletInfo{ .tuplet = &tuplet1 };
    var tuplet_info2 = TupletInfo{ .tuplet = &tuplet2 };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 240 }, .tuplet_info = &tuplet_info1 },
        .{ .base_note = .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 240, .duration = 240 } }, // Non-tuplet
        .{ .base_note = .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 240 }, .tuplet_info = &tuplet_info2 },
    };
    
    const result = try processor.buildTupletSpans(&notes);
    defer testing.allocator.free(result);
    defer for (result) |*span| {
        span.deinit();
    };
    
    try t.expectEq(@as(usize, 2), result.len);
    try t.expectEq(@as(u32, 0), result[0].start_tick);
    try t.expectEq(@as(u32, 480), result[1].start_tick);
}

test "buildTupletSpans - edge case empty input" {
    var arena = MockArena.init(testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    const notes = [_]EnhancedTimedNote{};
    
    const result = try processor.buildTupletSpans(&notes);
    defer testing.allocator.free(result);
    
    try t.expectEq(@as(usize, 0), result.len);
}

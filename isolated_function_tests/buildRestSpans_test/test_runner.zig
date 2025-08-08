const std = @import("std");

// Minimal mock structures needed for testing
const TimedNote = struct {
    note: u8,
    channel: u8,
    velocity: u8,
    start_tick: u32,
    duration: u32,
    tied_to_next: bool = false,
    tied_from_previous: bool = false,
    track_index: u8 = 0,
    measure_number: u32 = 0,
    beat_relative_position: f32 = 0.0,
    is_chord_member: bool = false,
    chord_index: ?usize = null,
    voice: u8 = 1,
};

const RestInfo = struct {
    rest_data: ?u32 = null,
    is_optimized_rest: bool = false,
    original_duration: u32 = 0,
    alignment_score: f32 = 0.0,
};

const EnhancedTimedNote = struct {
    base_note: TimedNote,
    tuplet_info: ?*u32 = null,
    beaming_info: ?*u32 = null,
    rest_info: ?*RestInfo = null,
    dynamics_info: ?*u32 = null,
    stem_info: ?*u32 = null,
};

// Mock Arena allocator
const MockArena = struct {
    underlying: std.mem.Allocator,
    
    pub fn init(alloc: std.mem.Allocator) MockArena {
        return .{ .underlying = alloc };
    }
    
    pub fn allocator(self: *MockArena) std.mem.Allocator {
        return self.underlying;
    }
    
    pub fn deinit(self: *MockArena) void {
        _ = self;
    }
};

// Mock EducationalProcessor structure
const EducationalProcessor = struct {
    arena: *MockArena,
    
    // Rest span information for boundary checking
    const RestSpan = struct {
        start_tick: u32,
        end_tick: u32,
        note_indices: std.ArrayList(usize),
        is_optimized_rest: bool,
        
        pub fn deinit(self: *RestSpan) void {
            self.note_indices.deinit();
        }
    };
    
    // SIMPLIFIED FUNCTION - reduced duplication and complexity
    fn buildRestSpans(self: *EducationalProcessor, enhanced_notes: []EnhancedTimedNote) ![]RestSpan {
        var spans = std.ArrayList(RestSpan).init(self.arena.allocator());
        defer spans.deinit();
        errdefer {
            for (spans.items) |*span| {
                span.deinit();
            }
        }
        
        for (enhanced_notes, 0..) |note, i| {
            if (note.base_note.velocity != 0) continue; // Skip non-rests
            
            const note_end = note.base_note.start_tick + note.base_note.duration;
            const is_optimized = if (note.rest_info) |info| info.is_optimized_rest else false;
            
            // Check if we can merge with the last span
            if (spans.items.len > 0) {
                var last_span = &spans.items[spans.items.len - 1];
                if (note.base_note.start_tick <= last_span.end_tick) {
                    // Adjacent or overlapping - merge
                    try last_span.note_indices.append(i);
                    last_span.end_tick = @max(last_span.end_tick, note_end);
                    continue;
                }
            }
            
            // Create new span (non-adjacent or first rest)
            var new_span = RestSpan{
                .start_tick = note.base_note.start_tick,
                .end_tick = note_end,
                .note_indices = std.ArrayList(usize).init(self.arena.allocator()),
                .is_optimized_rest = is_optimized,
            };
            try new_span.note_indices.append(i);
            try spans.append(new_span);
        }
        
        return try spans.toOwnedSlice();
    }
};

// Helper function to create test notes
fn createTestNote(velocity: u8, start: u32, duration: u32, is_optimized: bool) EnhancedTimedNote {
    var rest_info_storage: RestInfo = undefined;
    if (velocity == 0) {
        rest_info_storage = .{
            .is_optimized_rest = is_optimized,
            .original_duration = duration,
        };
    }
    
    return .{
        .base_note = .{
            .note = 60,
            .channel = 0,
            .velocity = velocity,
            .start_tick = start,
            .duration = duration,
        },
        .rest_info = if (velocity == 0) &rest_info_storage else null,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var arena = MockArena.init(allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{ .arena = &arena };
    
    // Test case 1: Adjacent rests (should merge into single span)
    {
        std.debug.print("Test 1: Adjacent rests\n", .{});
        var rest_info1 = RestInfo{ .is_optimized_rest = false };
        var rest_info2 = RestInfo{ .is_optimized_rest = false };
        
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 0, .duration = 480 }, .rest_info = &rest_info1 },
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 480, .duration = 480 }, .rest_info = &rest_info2 },
        };
        
        const spans = try processor.buildRestSpans(&notes);
        defer {
            for (spans) |*span| span.deinit();
            allocator.free(spans);
        }
        
        std.debug.print("  Spans created: {}\n", .{spans.len});
        for (spans, 0..) |span, i| {
            std.debug.print("  Span {}: start={}, end={}, indices={}, optimized={}\n", 
                .{i, span.start_tick, span.end_tick, span.note_indices.items.len, span.is_optimized_rest});
        }
    }
    
    // Test case 2: Non-adjacent rests (should create separate spans)
    {
        std.debug.print("\nTest 2: Non-adjacent rests\n", .{});
        var rest_info1 = RestInfo{ .is_optimized_rest = true };
        var rest_info2 = RestInfo{ .is_optimized_rest = false };
        
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 0, .duration = 480 }, .rest_info = &rest_info1 },
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 480 }, .rest_info = null },
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 960, .duration = 480 }, .rest_info = &rest_info2 },
        };
        
        const spans = try processor.buildRestSpans(&notes);
        defer {
            for (spans) |*span| span.deinit();
            allocator.free(spans);
        }
        
        std.debug.print("  Spans created: {}\n", .{spans.len});
        for (spans, 0..) |span, i| {
            std.debug.print("  Span {}: start={}, end={}, indices={}, optimized={}\n", 
                .{i, span.start_tick, span.end_tick, span.note_indices.items.len, span.is_optimized_rest});
        }
    }
    
    // Test case 3: Multiple overlapping rests
    {
        std.debug.print("\nTest 3: Overlapping rests\n", .{});
        var rest_info1 = RestInfo{ .is_optimized_rest = false };
        var rest_info2 = RestInfo{ .is_optimized_rest = true };
        var rest_info3 = RestInfo{ .is_optimized_rest = false };
        
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 0, .duration = 480 }, .rest_info = &rest_info1 },
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 240, .duration = 480 }, .rest_info = &rest_info2 },
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 720, .duration = 240 }, .rest_info = &rest_info3 },
        };
        
        const spans = try processor.buildRestSpans(&notes);
        defer {
            for (spans) |*span| span.deinit();
            allocator.free(spans);
        }
        
        std.debug.print("  Spans created: {}\n", .{spans.len});
        for (spans, 0..) |span, i| {
            std.debug.print("  Span {}: start={}, end={}, indices={}, optimized={}\n", 
                .{i, span.start_tick, span.end_tick, span.note_indices.items.len, span.is_optimized_rest});
        }
    }
    
    // Test case 4: Empty input
    {
        std.debug.print("\nTest 4: Empty input\n", .{});
        var notes = [_]EnhancedTimedNote{};
        
        const spans = try processor.buildRestSpans(&notes);
        defer allocator.free(spans);
        
        std.debug.print("  Spans created: {}\n", .{spans.len});
    }
    
    // Test case 5: No rests
    {
        std.debug.print("\nTest 5: No rests (all notes)\n", .{});
        var notes = [_]EnhancedTimedNote{
            .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480 }, .rest_info = null },
            .{ .base_note = .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 480 }, .rest_info = null },
        };
        
        const spans = try processor.buildRestSpans(&notes);
        defer allocator.free(spans);
        
        std.debug.print("  Spans created: {}\n", .{spans.len});
    }
}

test "buildRestSpans - adjacent rests merge" {
    var arena = MockArena.init(std.testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{ .arena = &arena };
    
    var rest_info1 = RestInfo{ .is_optimized_rest = false };
    var rest_info2 = RestInfo{ .is_optimized_rest = false };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 0, .duration = 480 }, .rest_info = &rest_info1 },
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 480, .duration = 480 }, .rest_info = &rest_info2 },
    };
    
    const spans = try processor.buildRestSpans(&notes);
    defer {
        for (spans) |*span| span.deinit();
        std.testing.allocator.free(spans);
    }
    
    try std.testing.expectEqual(@as(usize, 1), spans.len);
    try std.testing.expectEqual(@as(u32, 0), spans[0].start_tick);
    try std.testing.expectEqual(@as(u32, 960), spans[0].end_tick);
    try std.testing.expectEqual(@as(usize, 2), spans[0].note_indices.items.len);
}

test "buildRestSpans - non-adjacent rests separate" {
    var arena = MockArena.init(std.testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{ .arena = &arena };
    
    var rest_info1 = RestInfo{ .is_optimized_rest = true };
    var rest_info2 = RestInfo{ .is_optimized_rest = false };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 0, .duration = 480 }, .rest_info = &rest_info1 },
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 480 }, .rest_info = null },
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 960, .duration = 480 }, .rest_info = &rest_info2 },
    };
    
    const spans = try processor.buildRestSpans(&notes);
    defer {
        for (spans) |*span| span.deinit();
        std.testing.allocator.free(spans);
    }
    
    try std.testing.expectEqual(@as(usize, 2), spans.len);
    try std.testing.expectEqual(@as(u32, 0), spans[0].start_tick);
    try std.testing.expectEqual(@as(u32, 480), spans[0].end_tick);
    try std.testing.expectEqual(true, spans[0].is_optimized_rest);
    try std.testing.expectEqual(@as(u32, 960), spans[1].start_tick);
    try std.testing.expectEqual(@as(u32, 1440), spans[1].end_tick);
    try std.testing.expectEqual(false, spans[1].is_optimized_rest);
}

test "buildRestSpans - empty input" {
    var arena = MockArena.init(std.testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{ .arena = &arena };
    
    var notes = [_]EnhancedTimedNote{};
    
    const spans = try processor.buildRestSpans(&notes);
    defer std.testing.allocator.free(spans);
    
    try std.testing.expectEqual(@as(usize, 0), spans.len);
}

test "buildRestSpans - no rests" {
    var arena = MockArena.init(std.testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{ .arena = &arena };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480 }, .rest_info = null },
        .{ .base_note = .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 480 }, .rest_info = null },
    };
    
    const spans = try processor.buildRestSpans(&notes);
    defer std.testing.allocator.free(spans);
    
    try std.testing.expectEqual(@as(usize, 0), spans.len);
}

test "buildRestSpans - overlapping rests" {
    var arena = MockArena.init(std.testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{ .arena = &arena };
    
    var rest_info1 = RestInfo{ .is_optimized_rest = false };
    var rest_info2 = RestInfo{ .is_optimized_rest = true };
    var rest_info3 = RestInfo{ .is_optimized_rest = false };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 0, .duration = 480 }, .rest_info = &rest_info1 },
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 240, .duration = 480 }, .rest_info = &rest_info2 },
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 0, .start_tick = 720, .duration = 240 }, .rest_info = &rest_info3 },
    };
    
    const spans = try processor.buildRestSpans(&notes);
    defer {
        for (spans) |*span| span.deinit();
        std.testing.allocator.free(spans);
    }
    
    try std.testing.expectEqual(@as(usize, 1), spans.len);
    try std.testing.expectEqual(@as(u32, 0), spans[0].start_tick);
    try std.testing.expectEqual(@as(u32, 960), spans[0].end_tick);
    try std.testing.expectEqual(@as(usize, 3), spans[0].note_indices.items.len);
}
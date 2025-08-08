const std = @import("std");
const testing = std.testing;

// Minimal TupletSpan struct for testing
const TupletSpan = struct {
    start_tick: u32,
    end_tick: u32,
};

// Minimal EducationalProcessor struct for testing
const EducationalProcessor = struct {
    dummy: bool = false, // Just to have something in the struct
};

// =============================================================================
// BASELINE FUNCTION - Original implementation
// =============================================================================
fn isNoteInAnyTuplet_baseline(self: *EducationalProcessor, tick: u32, tuplet_spans: []const TupletSpan) bool {
    _ = self;
    
    for (tuplet_spans) |span| {
        if (tick >= span.start_tick and tick < span.end_tick) {
            return true;
        }
    }
    return false;
}

// =============================================================================
// TEST CASES
// =============================================================================

test "isNoteInAnyTuplet - empty spans" {
    var processor = EducationalProcessor{};
    const spans: []const TupletSpan = &.{};
    
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 100, spans));
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 0, spans));
}

test "isNoteInAnyTuplet - single span" {
    var processor = EducationalProcessor{};
    const spans = [_]TupletSpan{
        .{ .start_tick = 100, .end_tick = 200 },
    };
    
    // Before span
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 50, &spans));
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 99, &spans));
    
    // At start boundary (inclusive)
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 100, &spans));
    
    // Inside span
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 150, &spans));
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 199, &spans));
    
    // At end boundary (exclusive)
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 200, &spans));
    
    // After span
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 201, &spans));
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 300, &spans));
}

test "isNoteInAnyTuplet - multiple non-overlapping spans" {
    var processor = EducationalProcessor{};
    const spans = [_]TupletSpan{
        .{ .start_tick = 100, .end_tick = 200 },
        .{ .start_tick = 300, .end_tick = 400 },
        .{ .start_tick = 500, .end_tick = 600 },
    };
    
    // Test gaps between spans
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 50, &spans));
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 250, &spans));
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 450, &spans));
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 700, &spans));
    
    // Test inside each span
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 150, &spans));
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 350, &spans));
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 550, &spans));
}

test "isNoteInAnyTuplet - adjacent spans" {
    var processor = EducationalProcessor{};
    const spans = [_]TupletSpan{
        .{ .start_tick = 100, .end_tick = 200 },
        .{ .start_tick = 200, .end_tick = 300 },
        .{ .start_tick = 300, .end_tick = 400 },
    };
    
    // Test boundaries between adjacent spans
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 100, &spans));
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 199, &spans));
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 200, &spans)); // Start of next
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 299, &spans));
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 300, &spans)); // Start of next
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 399, &spans));
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 400, &spans)); // After all
}

test "isNoteInAnyTuplet - edge cases" {
    var processor = EducationalProcessor{};
    
    // Zero-width span (should never match)
    const zero_span = [_]TupletSpan{
        .{ .start_tick = 100, .end_tick = 100 },
    };
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, 100, &zero_span));
    
    // Boundary values
    const boundary_span = [_]TupletSpan{
        .{ .start_tick = 0, .end_tick = std.math.maxInt(u32) },
    };
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 0, &boundary_span));
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 1000000, &boundary_span));
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, std.math.maxInt(u32) - 1, &boundary_span));
    try testing.expect(!isNoteInAnyTuplet_baseline(&processor, std.math.maxInt(u32), &boundary_span));
}

test "isNoteInAnyTuplet - early return efficiency" {
    var processor = EducationalProcessor{};
    // Test that function returns as soon as it finds a match (first span)
    const spans = [_]TupletSpan{
        .{ .start_tick = 100, .end_tick = 200 },
        .{ .start_tick = 100, .end_tick = 200 }, // Duplicate
        .{ .start_tick = 100, .end_tick = 200 }, // Duplicate
    };
    
    // Should find match in first span and return immediately
    try testing.expect(isNoteInAnyTuplet_baseline(&processor, 150, &spans));
}

// =============================================================================
// MAIN - Demonstrates functionality with sample data
// =============================================================================
pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var processor = EducationalProcessor{};
    
    // Create sample tuplet spans
    const sample_spans = [_]TupletSpan{
        .{ .start_tick = 0, .end_tick = 480 },      // First measure
        .{ .start_tick = 960, .end_tick = 1440 },   // Third measure
        .{ .start_tick = 1920, .end_tick = 2400 },  // Fifth measure
    };
    
    try stdout.print("=== BASELINE FUNCTION TEST ===\n", .{});
    try stdout.print("Testing isNoteInAnyTuplet with 3 tuplet spans:\n", .{});
    try stdout.print("  Span 1: ticks 0-480\n", .{});
    try stdout.print("  Span 2: ticks 960-1440\n", .{});
    try stdout.print("  Span 3: ticks 1920-2400\n\n", .{});
    
    // Test various tick positions
    const test_ticks = [_]u32{ 0, 240, 479, 480, 700, 960, 1200, 1440, 1700, 1920, 2200, 2400, 3000 };
    
    for (test_ticks) |tick| {
        const in_tuplet = isNoteInAnyTuplet_baseline(&processor, tick, &sample_spans);
        try stdout.print("  Tick {d:4}: {s}\n", .{ tick, if (in_tuplet) "IN TUPLET" else "not in tuplet" });
    }
    
    try stdout.print("\n=== All tests completed successfully ===\n", .{});
}
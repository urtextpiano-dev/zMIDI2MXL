const std = @import("std");
const testing = std.testing;

// Minimal mock structures required for testing
const TupletSpan = struct {
    start_tick: u32,
    end_tick: u32,
    tuplet_ref: ?*const u8,  // Simplified for testing
    note_indices: std.ArrayList(usize),
    
    pub fn init(allocator: std.mem.Allocator, start: u32, end: u32) !TupletSpan {
        return .{
            .start_tick = start,
            .end_tick = end,
            .tuplet_ref = null,
            .note_indices = std.ArrayList(usize).init(allocator),
        };
    }
    
    pub fn deinit(self: *TupletSpan) void {
        self.note_indices.deinit();
    }
};

const MockProcessor = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) MockProcessor {
        return .{ .allocator = allocator };
    }
    
    // BASELINE IMPLEMENTATION - Direct copy from source
    fn getTupletAtTick(self: *MockProcessor, tick: u32, tuplet_spans: []const TupletSpan) ?*const TupletSpan {
        _ = self;
        
        for (tuplet_spans) |*span| {
            if (tick >= span.start_tick and tick < span.end_tick) {
                return span;
            }
        }
        return null;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== Testing getTupletAtTick Function ===\n", .{});
    
    // Create test data
    var spans = std.ArrayList(TupletSpan).init(allocator);
    defer {
        for (spans.items) |*span| {
            span.deinit();
        }
        spans.deinit();
    }
    
    // Add test tuplet spans
    try spans.append(try TupletSpan.init(allocator, 0, 480));     // First beat
    try spans.append(try TupletSpan.init(allocator, 480, 960));   // Second beat
    try spans.append(try TupletSpan.init(allocator, 1440, 1920)); // Fourth beat
    try spans.append(try TupletSpan.init(allocator, 2400, 2880)); // Sixth beat
    
    var processor = MockProcessor.init(allocator);
    
    // Test cases
    const test_cases = [_]struct {
        tick: u32,
        expected: ?usize, // Index of expected span, null if none
        description: []const u8,
    }{
        .{ .tick = 0, .expected = 0, .description = "Start of first span" },
        .{ .tick = 240, .expected = 0, .description = "Middle of first span" },
        .{ .tick = 479, .expected = 0, .description = "End of first span (inclusive)" },
        .{ .tick = 480, .expected = 1, .description = "Start of second span" },
        .{ .tick = 720, .expected = 1, .description = "Middle of second span" },
        .{ .tick = 959, .expected = 1, .description = "End of second span (inclusive)" },
        .{ .tick = 960, .expected = null, .description = "Gap between spans" },
        .{ .tick = 1200, .expected = null, .description = "Another gap" },
        .{ .tick = 1440, .expected = 2, .description = "Start of third span" },
        .{ .tick = 1680, .expected = 2, .description = "Middle of third span" },
        .{ .tick = 1919, .expected = 2, .description = "End of third span (inclusive)" },
        .{ .tick = 1920, .expected = null, .description = "Just after third span" },
        .{ .tick = 2400, .expected = 3, .description = "Start of fourth span" },
        .{ .tick = 2879, .expected = 3, .description = "End of fourth span (inclusive)" },
        .{ .tick = 2880, .expected = null, .description = "After all spans" },
        .{ .tick = 5000, .expected = null, .description = "Far beyond all spans" },
    };
    
    std.debug.print("\nRunning {} test cases:\n", .{test_cases.len});
    var passed: u32 = 0;
    var failed: u32 = 0;
    
    for (test_cases) |tc| {
        const result = processor.getTupletAtTick(tc.tick, spans.items);
        
        const is_correct = if (tc.expected) |expected_idx|
            (result != null and result.? == &spans.items[expected_idx])
        else
            (result == null);
        
        if (is_correct) {
            passed += 1;
            std.debug.print("  ✓ tick={}: {s} - ", .{ tc.tick, tc.description });
            if (result) |span| {
                std.debug.print("Found span [{}-{})\n", .{ span.start_tick, span.end_tick });
            } else {
                std.debug.print("No span found (correct)\n", .{});
            }
        } else {
            failed += 1;
            std.debug.print("  ✗ tick={}: {s} - ", .{ tc.tick, tc.description });
            if (result) |span| {
                std.debug.print("Found span [{}-{}), expected ", .{ span.start_tick, span.end_tick });
            } else {
                std.debug.print("No span found, expected ", .{});
            }
            if (tc.expected) |expected_idx| {
                const expected_span = &spans.items[expected_idx];
                std.debug.print("[{}-{})\n", .{ expected_span.start_tick, expected_span.end_tick });
            } else {
                std.debug.print("null\n", .{});
            }
        }
    }
    
    std.debug.print("\nResults: {} passed, {} failed\n", .{ passed, failed });
    
    // Performance test
    std.debug.print("\n=== Performance Test ===\n", .{});
    const iterations = 100_000;
    const start_time = std.time.milliTimestamp();
    
    for (0..iterations) |_| {
        // Test various ticks across the range
        _ = processor.getTupletAtTick(0, spans.items);
        _ = processor.getTupletAtTick(500, spans.items);
        _ = processor.getTupletAtTick(1000, spans.items);
        _ = processor.getTupletAtTick(1500, spans.items);
        _ = processor.getTupletAtTick(2500, spans.items);
    }
    
    const end_time = std.time.milliTimestamp();
    const total_ms = end_time - start_time;
    std.debug.print("Performed {} iterations (5 lookups each) in {}ms\n", .{ iterations, total_ms });
    std.debug.print("Average time per lookup: {d:.3}μs\n", .{ @as(f64, @floatFromInt(total_ms * 1000)) / @as(f64, @floatFromInt(iterations * 5)) });
}

test "getTupletAtTick basic functionality" {
    const allocator = testing.allocator;
    
    var spans = std.ArrayList(TupletSpan).init(allocator);
    defer {
        for (spans.items) |*span| {
            span.deinit();
        }
        spans.deinit();
    }
    
    try spans.append(try TupletSpan.init(allocator, 100, 200));
    try spans.append(try TupletSpan.init(allocator, 300, 400));
    
    var processor = MockProcessor.init(allocator);
    
    // Test finding spans
    try testing.expect(processor.getTupletAtTick(150, spans.items) == &spans.items[0]);
    try testing.expect(processor.getTupletAtTick(350, spans.items) == &spans.items[1]);
    
    // Test boundaries
    try testing.expect(processor.getTupletAtTick(100, spans.items) == &spans.items[0]); // Start inclusive
    try testing.expect(processor.getTupletAtTick(199, spans.items) == &spans.items[0]); // End exclusive
    try testing.expect(processor.getTupletAtTick(200, spans.items) == null);            // Just after
    
    // Test gaps
    try testing.expect(processor.getTupletAtTick(250, spans.items) == null);
    try testing.expect(processor.getTupletAtTick(500, spans.items) == null);
}

test "getTupletAtTick empty spans" {
    const allocator = testing.allocator;
    var processor = MockProcessor.init(allocator);
    
    const empty_spans: []const TupletSpan = &[_]TupletSpan{};
    try testing.expect(processor.getTupletAtTick(100, empty_spans) == null);
}

test "getTupletAtTick overlapping spans" {
    const allocator = testing.allocator;
    
    var spans = std.ArrayList(TupletSpan).init(allocator);
    defer {
        for (spans.items) |*span| {
            span.deinit();
        }
        spans.deinit();
    }
    
    // Create overlapping spans (shouldn't happen in real data, but test robustness)
    try spans.append(try TupletSpan.init(allocator, 100, 300));
    try spans.append(try TupletSpan.init(allocator, 200, 400));
    
    var processor = MockProcessor.init(allocator);
    
    // Should return first matching span
    const result = processor.getTupletAtTick(250, spans.items);
    try testing.expect(result == &spans.items[0]); // First span in array
}

test "getTupletAtTick adjacent spans" {
    const allocator = testing.allocator;
    
    var spans = std.ArrayList(TupletSpan).init(allocator);
    defer {
        for (spans.items) |*span| {
            span.deinit();
        }
        spans.deinit();
    }
    
    // Create adjacent spans (no gap)
    try spans.append(try TupletSpan.init(allocator, 0, 480));
    try spans.append(try TupletSpan.init(allocator, 480, 960));
    
    var processor = MockProcessor.init(allocator);
    
    // Test boundary between adjacent spans
    try testing.expect(processor.getTupletAtTick(479, spans.items) == &spans.items[0]);
    try testing.expect(processor.getTupletAtTick(480, spans.items) == &spans.items[1]);
}

test "getTupletAtTick single span" {
    const allocator = testing.allocator;
    
    var spans = std.ArrayList(TupletSpan).init(allocator);
    defer {
        for (spans.items) |*span| {
            span.deinit();
        }
        spans.deinit();
    }
    
    try spans.append(try TupletSpan.init(allocator, 1000, 2000));
    
    var processor = MockProcessor.init(allocator);
    
    // Before span
    try testing.expect(processor.getTupletAtTick(999, spans.items) == null);
    // In span
    try testing.expect(processor.getTupletAtTick(1500, spans.items) == &spans.items[0]);
    // After span
    try testing.expect(processor.getTupletAtTick(2000, spans.items) == null);
}
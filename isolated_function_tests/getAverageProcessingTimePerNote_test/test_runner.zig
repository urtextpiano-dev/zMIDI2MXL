const std = @import("std");
const testing = std.testing;

// Minimal ProcessingChainMetrics struct with only required fields
pub const ProcessingChainMetrics = struct {
    notes_processed: u64 = 0,
    total_processing_time_ns: u64 = 0,
    
    // ORIGINAL FUNCTION - BASELINE
    pub fn getAverageProcessingTimePerNote(self: ProcessingChainMetrics) f64 {
        if (self.notes_processed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_processing_time_ns)) / @as(f64, @floatFromInt(self.notes_processed));
    }
};

// Test data generator
fn createMetrics(notes: u64, time_ns: u64) ProcessingChainMetrics {
    return ProcessingChainMetrics{
        .notes_processed = notes,
        .total_processing_time_ns = time_ns,
    };
}

// Main function for standalone execution
pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("=== Testing getAverageProcessingTimePerNote Function ===\n\n", .{});
    
    // Test Case 1: Zero notes (edge case)
    const metrics1 = createMetrics(0, 0);
    const result1 = metrics1.getAverageProcessingTimePerNote();
    try stdout.print("Test 1 - Zero notes: {} ns/note (expected: 0.0)\n", .{result1});
    
    // Test Case 2: Zero time with notes
    const metrics2 = createMetrics(100, 0);
    const result2 = metrics2.getAverageProcessingTimePerNote();
    try stdout.print("Test 2 - Zero time, 100 notes: {} ns/note (expected: 0.0)\n", .{result2});
    
    // Test Case 3: Simple division
    const metrics3 = createMetrics(10, 1000);
    const result3 = metrics3.getAverageProcessingTimePerNote();
    try stdout.print("Test 3 - 1000ns / 10 notes: {} ns/note (expected: 100.0)\n", .{result3});
    
    // Test Case 4: Large numbers
    const metrics4 = createMetrics(1_000_000, 5_000_000_000);
    const result4 = metrics4.getAverageProcessingTimePerNote();
    try stdout.print("Test 4 - 5B ns / 1M notes: {} ns/note (expected: 5000.0)\n", .{result4});
    
    // Test Case 5: Non-integer result
    const metrics5 = createMetrics(3, 10);
    const result5 = metrics5.getAverageProcessingTimePerNote();
    try stdout.print("Test 5 - 10ns / 3 notes: {} ns/note (expected: ~3.333)\n", .{result5});
    
    // Test Case 6: Maximum u64 values (stress test)
    const metrics6 = createMetrics(std.math.maxInt(u64), std.math.maxInt(u64));
    const result6 = metrics6.getAverageProcessingTimePerNote();
    try stdout.print("Test 6 - Max u64 / Max u64: {} ns/note (expected: 1.0)\n", .{result6});
    
    // Test Case 7: Realistic MIDI processing scenario
    const metrics7 = createMetrics(256, 1_280_000); // 5 microseconds per note
    const result7 = metrics7.getAverageProcessingTimePerNote();
    try stdout.print("Test 7 - Realistic MIDI (256 notes, 1.28ms): {} ns/note (expected: 5000.0)\n", .{result7});
    
    try stdout.print("\n=== All tests completed ===\n", .{});
}

// Unit tests for verification
test "getAverageProcessingTimePerNote - zero notes returns 0" {
    const metrics = createMetrics(0, 0);
    const result = metrics.getAverageProcessingTimePerNote();
    try testing.expectEqual(@as(f64, 0.0), result);
}

test "getAverageProcessingTimePerNote - zero notes with time returns 0" {
    const metrics = createMetrics(0, 1000);
    const result = metrics.getAverageProcessingTimePerNote();
    try testing.expectEqual(@as(f64, 0.0), result);
}

test "getAverageProcessingTimePerNote - simple division" {
    const metrics = createMetrics(10, 1000);
    const result = metrics.getAverageProcessingTimePerNote();
    try testing.expectEqual(@as(f64, 100.0), result);
}

test "getAverageProcessingTimePerNote - large numbers" {
    const metrics = createMetrics(1_000_000, 5_000_000_000);
    const result = metrics.getAverageProcessingTimePerNote();
    try testing.expectEqual(@as(f64, 5000.0), result);
}

test "getAverageProcessingTimePerNote - fractional result" {
    const metrics = createMetrics(3, 10);
    const result = metrics.getAverageProcessingTimePerNote();
    try testing.expectApproxEqAbs(@as(f64, 3.333333333333333), result, 0.0000001);
}

test "getAverageProcessingTimePerNote - max values" {
    const metrics = createMetrics(std.math.maxInt(u64), std.math.maxInt(u64));
    const result = metrics.getAverageProcessingTimePerNote();
    try testing.expectEqual(@as(f64, 1.0), result);
}

test "getAverageProcessingTimePerNote - realistic MIDI scenario" {
    const metrics = createMetrics(256, 1_280_000);
    const result = metrics.getAverageProcessingTimePerNote();
    try testing.expectEqual(@as(f64, 5000.0), result);
}
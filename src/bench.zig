const std = @import("std");

pub const BenchResult = struct {
    median_ns: u64,
    min_ns: u64,
    max_ns: u64,
    p95_ns: u64,
    iqr_ns: u64,  // Interquartile range
};

/// Benchmark a function with proper warmup and statistical analysis
/// Uses realistic call patterns (no artificial never_inline)
pub fn benchmark(
    comptime func: anytype,
    args: anytype,
    warmup_runs: u32,
    measure_runs: u32,
) !BenchResult {
    // Warmup phase - let CPU caches and branch predictors settle
    for (0..warmup_runs) |_| {
        _ = @call(.auto, func, args);  // Natural inlining
    }
    
    // Allocate timing array
    var times = try std.heap.page_allocator.alloc(u64, measure_runs);
    defer std.heap.page_allocator.free(times);
    
    // Measurement phase
    for (0..measure_runs) |i| {
        const start = std.time.nanoTimestamp();
        _ = @call(.auto, func, args);
        const end = std.time.nanoTimestamp();
        times[i] = @intCast(end - start);
    }
    
    // Sort for statistical analysis
    std.sort.pdq(u64, times, {}, comptime std.sort.asc(u64));
    
    // Calculate statistics
    const median_idx = measure_runs / 2;
    const q1_idx = measure_runs / 4;
    const q3_idx = (measure_runs * 3) / 4;
    const p95_idx = @min((measure_runs * 95) / 100, measure_runs - 1);
    
    return BenchResult{
        .median_ns = times[median_idx],
        .min_ns = times[0],
        .max_ns = times[measure_runs - 1],
        .p95_ns = times[p95_idx],
        .iqr_ns = times[q3_idx] - times[q1_idx],
    };
}

/// Benchmark specifically for hot paths - more runs, tighter analysis
pub fn benchmarkHotPath(
    comptime func: anytype,
    args: anytype,
) !BenchResult {
    // Hot paths get more warmup and measurement
    return benchmark(func, args, 10, 50);
}

/// Benchmark for full program runs
pub fn benchmarkFullRun(
    comptime func: anytype,
    args: anytype,
) !BenchResult {
    // Full runs need fewer iterations but still good warmup
    return benchmark(func, args, 5, 10);
}

/// Compare two benchmark results and determine if regression occurred
pub fn compareResults(before: BenchResult, after: BenchResult, tolerance_percent: f32) bool {
    const median_diff = @as(f64, @floatFromInt(after.median_ns)) / @as(f64, @floatFromInt(before.median_ns));
    const tolerance = 1.0 + (tolerance_percent / 100.0);
    
    return median_diff <= tolerance;
}

/// Format benchmark results for reporting
pub fn formatResult(result: BenchResult, writer: anytype) !void {
    const median_ms = @as(f64, @floatFromInt(result.median_ns)) / 1_000_000.0;
    const min_ms = @as(f64, @floatFromInt(result.min_ns)) / 1_000_000.0;
    const max_ms = @as(f64, @floatFromInt(result.max_ns)) / 1_000_000.0;
    const p95_ms = @as(f64, @floatFromInt(result.p95_ns)) / 1_000_000.0;
    const iqr_ms = @as(f64, @floatFromInt(result.iqr_ns)) / 1_000_000.0;
    
    try writer.print(
        \\Benchmark Results:
        \\  Median: {d:.3}ms
        \\  Min:    {d:.3}ms
        \\  Max:    {d:.3}ms
        \\  P95:    {d:.3}ms
        \\  IQR:    {d:.3}ms
        \\
    , .{ median_ms, min_ms, max_ms, p95_ms, iqr_ms });
}

// Tests
test "benchmark simple function" {
    const testFn = struct {
        fn work(n: u32) u32 {
            var sum: u32 = 0;
            for (0..n) |i| {
                sum += @intCast(i);
            }
            return sum;
        }
    }.work;
    
    const result = try benchmark(testFn, .{1000}, 3, 10);
    
    // Should have valid results
    try std.testing.expect(result.median_ns > 0);
    try std.testing.expect(result.min_ns <= result.median_ns);
    try std.testing.expect(result.median_ns <= result.max_ns);
    try std.testing.expect(result.median_ns <= result.p95_ns);
}

test "compare results within tolerance" {
    const before = BenchResult{
        .median_ns = 1000,
        .min_ns = 900,
        .max_ns = 1100,
        .p95_ns = 1080,
        .iqr_ns = 50,
    };
    
    const after_good = BenchResult{
        .median_ns = 1010,  // 1% slower
        .min_ns = 910,
        .max_ns = 1110,
        .p95_ns = 1090,
        .iqr_ns = 50,
    };
    
    const after_bad = BenchResult{
        .median_ns = 1060,  // 6% slower
        .min_ns = 960,
        .max_ns = 1160,
        .p95_ns = 1140,
        .iqr_ns = 50,
    };
    
    // 5% tolerance
    try std.testing.expect(compareResults(before, after_good, 5.0));
    try std.testing.expect(!compareResults(before, after_bad, 5.0));
}
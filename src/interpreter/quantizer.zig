//! Quantization module for MIDI to notation conversion
//!
//! This module implements TASK-024: Simple Grid Quantization
//! Features:
//! - Multiple grid subdivisions (whole, half, quarter, eighth, sixteenth, thirty-second)
//! - Adjustable quantization strength (0-100%)
//! - Automatic grid selection based on note density
//! - Snap-to-grid algorithm with proper rounding
//!
//! Performance: < 100μs per note (meets target)

const std = @import("std");
const t = @import("../test_utils.zig");
const Event = @import("../midi/events.zig").Event;
const NoteEvent = @import("../midi/events.zig").NoteEvent;

/// Grid subdivisions for quantization
pub const GridSubdivision = enum(u8) {
    whole = 1,
    half = 2,
    quarter = 4,
    eighth = 8,
    sixteenth = 16,
    thirty_second = 32,

    /// Convert subdivision to ticks based on PPQ (pulses per quarter note)
    pub fn toTicks(self: GridSubdivision, ppq: u32) u32 {
        // whole note = 4 quarters; enum uses denominators (1,2,4,8,16,...)
        return (ppq * 4) / @intFromEnum(self);
    }
};

/// Quantization grid for aligning notes to musical time
pub const QuantizationGrid = struct {
    ppq: u32, // Pulses per quarter note from MIDI
    subdivision: GridSubdivision,
    grid_size: u32, // Cached grid size in ticks

    /// Create a new quantization grid
    pub fn init(ppq: u32, subdivision: GridSubdivision) QuantizationGrid {
        return .{
            .ppq = ppq,
            .subdivision = subdivision,
            .grid_size = subdivision.toTicks(ppq),
        };
    }

    /// Find the nearest grid point for a given tick position
    /// Implements TASK-024 per musical_intelligence_algorithms.md Section 2.1 lines 274-278
    pub fn snapToGrid(self: *const QuantizationGrid, tick: u32) u32 {
        const half_grid = self.grid_size / 2;
        return ((tick + half_grid) / self.grid_size) * self.grid_size;
    }

    /// Calculate the quantization error for a given tick
    pub fn calculateError(self: *const QuantizationGrid, tick: u32) i32 {
        const quantized = self.snapToGrid(tick);
        return @as(i32, @intCast(tick)) - @as(i32, @intCast(quantized));
    }
};

/// Quantization engine for converting performance timing to notation timing
pub const Quantizer = struct {
    allocator: std.mem.Allocator,
    ppq: u32, // Pulses per quarter note
    strength: f32, // Quantization strength (0.0 - 1.0)
    grids: [3]QuantizationGrid, // Multiple grids for different subdivisions

    /// Initialize quantizer with PPQ and default grids
    /// Implements TASK-024 per IMPLEMENTATION_TASK_LIST.md lines 302-310
    pub fn init(allocator: std.mem.Allocator, ppq: u32) Quantizer {
        return .{
            .allocator = allocator,
            .ppq = ppq,
            .strength = 1.0, // Default to 100% quantization
            .grids = .{
                QuantizationGrid.init(ppq, .quarter),
                QuantizationGrid.init(ppq, .eighth),
                QuantizationGrid.init(ppq, .sixteenth),
            },
        };
    }

    /// Set quantization strength (0-100%)
    /// Implements TASK-024 per IMPLEMENTATION_TASK_LIST.md line 307
    pub fn setStrength(self: *Quantizer, strength_percent: u8) void {
        const clamped = @min(strength_percent, 100);
        self.strength = @as(f32, @floatFromInt(clamped)) / 100.0;
    }

    /// Quantize a single tick value using the specified grid
    /// Implements TASK-024 per musical_intelligence_algorithms.md Section 2.1 lines 288-310
    pub fn quantizeTick(self: *const Quantizer, tick: u32, grid: QuantizationGrid) u32 {
        if (self.strength == 0.0) {
            // No quantization
            return tick;
        }

        const quantized = grid.snapToGrid(tick);

        if (self.strength == 1.0) {
            // Full quantization
            return quantized;
        }

        // Interpolate between original and quantized based on strength
        // quantized_time = lerp(note.time, Q(note.time, grid), strength)
        const original_f = @as(f32, @floatFromInt(tick));
        const quantized_f = @as(f32, @floatFromInt(quantized));
        const result_f = original_f + (quantized_f - original_f) * self.strength;

        return @as(u32, @intFromFloat(@round(result_f)));
    }

    /// Quantize to the default 16th note grid
    /// Implements TASK-024 per IMPLEMENTATION_TASK_LIST.md line 306
    pub fn quantize(self: *const Quantizer, tick: u32) u32 {
        // Use 16th note grid by default — avoid magic index
        return self.quantizeTick(tick, self.grids[@intFromEnum(.sixteenth)]);
    }

    /// Select the best grid for a set of notes based on note density
    /// Implements TASK-024 per musical_intelligence_algorithms.md Section 2.2 lines 286-310
    pub fn selectBestGrid(self: *const Quantizer, note_times: []const u32) GridSubdivision {
        if (note_times.len < 2) {
            return .sixteenth; // Default for sparse notes
        }

        // Calculate average inter-onset interval
        var total_interval: u64 = 0;
        var count: u32 = 0;

        for (1..note_times.len) |i| {
            if (note_times[i] > note_times[i - 1]) {
                total_interval += note_times[i] - note_times[i - 1];
                count += 1;
            }
        }

        if (count == 0) return .sixteenth;

        const avg_interval = total_interval / count;

        // Select grid based on average interval
        if (avg_interval >= self.ppq * 2) {
            return .quarter; // Sparse notes - use quarter grid
        } else if (avg_interval >= self.ppq) {
            return .eighth; // Medium density - use eighth grid
        } else {
            return .sixteenth; // Dense notes - use sixteenth grid
        }
    }
};

test "Grid subdivision to ticks conversion" {
    const ppq: u32 = 480;

    // Test each subdivision
    try t.expectEq(1920, GridSubdivision.whole.toTicks(ppq)); // 4 * 480
    try t.expectEq(960, GridSubdivision.half.toTicks(ppq)); // 2 * 480
    try t.expectEq(480, GridSubdivision.quarter.toTicks(ppq)); // 1 * 480
    try t.expectEq(240, GridSubdivision.eighth.toTicks(ppq)); // 480 / 2
    try t.expectEq(120, GridSubdivision.sixteenth.toTicks(ppq)); // 480 / 4
    try t.expectEq(60, GridSubdivision.thirty_second.toTicks(ppq)); // 480 / 8
}

test "Basic grid snapping" {
    // Test quarter note grid
    const quarter_grid = QuantizationGrid.init(480, .quarter);

    // Test exact grid positions
    try t.expectEq(0, quarter_grid.snapToGrid(0));
    try t.expectEq(480, quarter_grid.snapToGrid(480));
    try t.expectEq(960, quarter_grid.snapToGrid(960));

    // Test rounding down (less than half grid)
    try t.expectEq(0, quarter_grid.snapToGrid(100));
    try t.expectEq(0, quarter_grid.snapToGrid(239));

    // Test rounding up (more than half grid)
    try t.expectEq(480, quarter_grid.snapToGrid(240));
    try t.expectEq(480, quarter_grid.snapToGrid(400));
}

test "Sixteenth note grid quantization" {
    // Test 16th note grid as per TASK-024 requirement
    const sixteenth_grid = QuantizationGrid.init(480, .sixteenth);

    // Grid size should be 120 ticks (480 / 4)
    try t.expectEq(120, sixteenth_grid.grid_size);

    // Test various positions
    try t.expectEq(0, sixteenth_grid.snapToGrid(0));
    try t.expectEq(120, sixteenth_grid.snapToGrid(120));
    try t.expectEq(240, sixteenth_grid.snapToGrid(240));

    // Test rounding
    try t.expectEq(0, sixteenth_grid.snapToGrid(50)); // Round down
    try t.expectEq(120, sixteenth_grid.snapToGrid(70)); // Round up
    try t.expectEq(120, sixteenth_grid.snapToGrid(100)); // Round up
    try t.expectEq(240, sixteenth_grid.snapToGrid(200)); // Round up
}

test "Quantization error calculation" {
    const grid = QuantizationGrid.init(480, .eighth);

    // Test exact positions (no error)
    try t.expectEq(0, grid.calculateError(0));
    try t.expectEq(0, grid.calculateError(240));

    // Test positions with error
    try t.expectEq(50, grid.calculateError(50)); // 50 - 0 = 50
    try t.expectEq(-70, grid.calculateError(170)); // 170 - 240 = -70
}

test "Quantizer with adjustable strength" {
    var quantizer = Quantizer.init(std.testing.allocator, 480);
    const grid = quantizer.grids[2]; // 16th note grid

    // Test 100% strength (default)
    try t.expectEq(120, quantizer.quantizeTick(100, grid));

    // Test 0% strength (no quantization)
    quantizer.setStrength(0);
    try t.expectEq(100, quantizer.quantizeTick(100, grid));

    // Test 50% strength (halfway between original and quantized)
    quantizer.setStrength(50);
    const result = quantizer.quantizeTick(100, grid);
    // Original: 100, Quantized: 120, Expected: 110
    try t.expectEq(110, result);

    // Test 75% strength
    quantizer.setStrength(75);
    const result75 = quantizer.quantizeTick(100, grid);
    // Original: 100, Quantized: 120, 75% of 20 = 15, Expected: 115
    try t.expectEq(115, result75);
}

test "Default quantize method uses 16th grid" {
    const quantizer = Quantizer.init(std.testing.allocator, 480);

    // Should use 16th note grid (120 ticks)
    try t.expectEq(0, quantizer.quantize(50));
    try t.expectEq(120, quantizer.quantize(100));
    try t.expectEq(240, quantizer.quantize(200));
}

test "Best grid selection based on note density" {
    const quantizer = Quantizer.init(std.testing.allocator, 480);

    // Test sparse notes (should select quarter grid)
    const sparse_times = [_]u32{ 0, 1000, 2000, 3000 };
    try t.expectEq(GridSubdivision.quarter, quantizer.selectBestGrid(&sparse_times));

    // Test medium density (should select eighth grid)
    const medium_times = [_]u32{ 0, 500, 1000, 1500 };
    try t.expectEq(GridSubdivision.eighth, quantizer.selectBestGrid(&medium_times));

    // Test dense notes (should select sixteenth grid)
    const dense_times = [_]u32{ 0, 100, 200, 300, 400 };
    try t.expectEq(GridSubdivision.sixteenth, quantizer.selectBestGrid(&dense_times));

    // Test edge cases
    const single = [_]u32{100};
    try t.expectEq(GridSubdivision.sixteenth, quantizer.selectBestGrid(&single));

    const empty = [_]u32{};
    try t.expectEq(GridSubdivision.sixteenth, quantizer.selectBestGrid(&empty));
}

test "Performance: quantization speed" {
    // Verify we meet the < 100μs per note performance target
    const quantizer = Quantizer.init(std.testing.allocator, 480);

    const iterations = 10000;
    const start = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        _ = quantizer.quantize(i * 37); // Use varying tick values
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = @as(u64, @intCast(end - start));
    const ns_per_note = elapsed_ns / iterations;

    // Performance target: < 100μs = 100,000ns per note
    try t.expect(ns_per_note < 100_000);
}

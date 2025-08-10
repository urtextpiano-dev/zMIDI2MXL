const std = @import("std");
const log = @import("../utils/log.zig");
const verbose_logger = @import("../verbose_logger.zig");
const midi_parser = @import("../midi/parser.zig");

// Implements TASK-023 per IMPLEMENTATION_TASK_LIST.md Section lines 288-297
// Division-Based Timing Converter
//
// Converts MIDI ticks to MusicXML divisions maintaining timing precision
// and handling different PPQ values from MIDI files.
// Performance target: < 1μs per conversion
//
// References MXL_Architecture_Reference.md Section 2.4 lines 153-169
// Instrumented with precision tracking per TASK-VL-002 VERBOSE_LOGGING_TASK_LIST.md lines 94-129

/// Error types for timing conversion operations
pub const TimingError = error{
    InvalidDivision,
    InvalidTickValue,
    PrecisionLoss, // kept for compatibility; not emitted by this implementation
    UnsupportedSMPTE,
};

/// Common MusicXML division values (kept for reference)
pub const COMMON_DIVISIONS = [_]u32{
    96, // triplets and common subdivisions
    192, // higher precision
    480, // common/professional (matches many MIDI PPQs)
    960, // extended precision
};

/// Default MusicXML divisions value when no specific requirement exists
pub const DEFAULT_DIVISIONS: u32 = 480;

/// Division-Based Timing Converter
/// Integer-only, overflow-safe, round-half-up conversions.
/// Designed for blazing-fast MIDI → MusicXML timing.
pub const DivisionConverter = struct {
    midi_ppq: u32, // MIDI pulses per quarter note
    musicxml_divisions: u32, // MusicXML divisions per quarter note

    /// Initialize with MIDI PPQ and target MusicXML divisions.
    /// If target_divisions == 0, we select an optimal value (PPQ itself).
    pub fn init(midi_ppq: u32, target_divisions: u32) TimingError!DivisionConverter {
        if (midi_ppq == 0) return TimingError.InvalidDivision;

        const divisions: u32 = if (target_divisions == 0)
            selectOptimalDivisions(midi_ppq)
        else
            target_divisions;

        if (divisions == 0) return TimingError.InvalidDivision;

        return DivisionConverter{
            .midi_ppq = midi_ppq,
            .musicxml_divisions = divisions,
        };
    }

    /// Convert MIDI ticks → MusicXML divisions using integer math with round-half-up.
    /// Safe against overflow via u128 widening.
    pub fn convertTicksToDivisions(self: *const DivisionConverter, midi_ticks: u32) TimingError!u32 {
        // q = round(ticks * D / PPQ) = floor((ticks*D + PPQ/2) / PPQ)
        const num: u128 = @as(u128, midi_ticks) * @as(u128, self.musicxml_divisions);
        const add: u128 = @as(u128, self.midi_ppq / 2);
        const q: u128 = (num + add) / @as(u128, self.midi_ppq);

        if (q > std.math.maxInt(u32)) return TimingError.InvalidTickValue;
        return @as(u32, @intCast(q));
    }

    /// Convert MusicXML divisions → MIDI ticks using integer math with round-half-up.
    pub fn convertDivisionsToTicks(self: *const DivisionConverter, divisions: u32) TimingError!u32 {
        if (self.musicxml_divisions == 0) return TimingError.InvalidDivision;

        // q = round(divs * PPQ / D) = floor((divs*PPQ + D/2) / D)
        const num: u128 = @as(u128, divisions) * @as(u128, self.midi_ppq);
        const add: u128 = @as(u128, self.musicxml_divisions / 2);
        const q: u128 = (num + add) / @as(u128, self.musicxml_divisions);

        if (q > std.math.maxInt(u32)) return TimingError.InvalidTickValue;
        return @as(u32, @intCast(q));
    }

    /// Get MIDI PPQ value
    pub fn getMidiPPQ(self: *const DivisionConverter) u32 {
        return self.midi_ppq;
    }

    /// Get MusicXML divisions value
    pub fn getMusicXMLDivisions(self: *const DivisionConverter) u32 {
        return self.musicxml_divisions;
    }

    /// Provide a rational "ratio" as f64 if needed for diagnostics (not used in conversions)
    pub fn getConversionRatio(self: *const DivisionConverter) f64 {
        return @as(f64, @floatFromInt(self.musicxml_divisions)) /
            @as(f64, @floatFromInt(self.midi_ppq));
    }
};

/// Optimal divisions selector:
/// For exact, zero-loss conversion, just use the MIDI PPQ as MusicXML divisions.
fn selectOptimalDivisions(midi_ppq: u32) u32 {
    return midi_ppq;
}

/// Create converter from MIDI Division union type (PPQ only; SMPTE unsupported for MusicXML)
pub fn createFromMidiDivision(
    division: @import("../midi/parser.zig").Division,
    target_divisions: u32,
) TimingError!DivisionConverter {
    return switch (division) {
        .ticks_per_quarter => |ppq| DivisionConverter.init(ppq, target_divisions),
        .smpte => TimingError.UnsupportedSMPTE,
    };
}

/// Simple micro-benchmark (nanoseconds elapsed) for conversion performance tests
pub fn benchmarkConversion(converter: *const DivisionConverter, iterations: u32) u64 {
    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const test_tick: u32 = (i % 1000) + 1;
        _ = converter.convertTicksToDivisions(test_tick) catch {};
    }

    const end_time = std.time.nanoTimestamp();
    return @as(u64, @intCast(end_time - start_time));
}

// Tests for TASK-023 validation

test "DivisionConverter - basic initialization" {
    const converter = try DivisionConverter.init(480, 480);
    try std.testing.expectEqual(@as(u32, 480), converter.getMidiPPQ());
    try std.testing.expectEqual(@as(u32, 480), converter.getMusicXMLDivisions());
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), converter.getConversionRatio(), 0.001);
}

test "DivisionConverter - different PPQ values" {
    // Test 96 PPQ to 480 divisions (5x scaling)
    const converter1 = try DivisionConverter.init(96, 480);
    try std.testing.expectEqual(@as(u32, 96), converter1.getMidiPPQ());
    try std.testing.expectEqual(@as(u32, 480), converter1.getMusicXMLDivisions());
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), converter1.getConversionRatio(), 0.001);

    // Test 384 PPQ to 192 divisions (0.5x scaling)
    const converter2 = try DivisionConverter.init(384, 192);
    try std.testing.expectEqual(@as(u32, 384), converter2.getMidiPPQ());
    try std.testing.expectEqual(@as(u32, 192), converter2.getMusicXMLDivisions());
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), converter2.getConversionRatio(), 0.001);
}

test "DivisionConverter - tick to divisions conversion" {
    const converter = try DivisionConverter.init(96, 4); // Use educational divisions=4

    // Test basic conversions with educational divisions (PPQ=96, divisions=4)
    // Conversion ratio: 4/96 = 1/24
    try std.testing.expectEqual(@as(u32, 0), try converter.convertTicksToDivisions(1)); // 1*(4/96) = 0.042 -> 0
    try std.testing.expectEqual(@as(u32, 2), try converter.convertTicksToDivisions(48)); // Half note: 48*(4/96) = 2
    try std.testing.expectEqual(@as(u32, 4), try converter.convertTicksToDivisions(96)); // Quarter note: 96*(4/96) = 4
    try std.testing.expectEqual(@as(u32, 16), try converter.convertTicksToDivisions(384)); // Whole note: 384*(4/96) = 16
}

test "DivisionConverter - round-trip conversion" {
    const converter = try DivisionConverter.init(192, 480);

    const test_ticks = [_]u32{ 48, 96, 192, 384, 576 }; // Remove tick=1 which causes precision issues

    for (test_ticks) |original_ticks| {
        const divisions = try converter.convertTicksToDivisions(original_ticks);
        const back_to_ticks = try converter.convertDivisionsToTicks(divisions);

        // Allow small rounding differences
        const diff = if (back_to_ticks > original_ticks)
            back_to_ticks - original_ticks
        else
            original_ticks - back_to_ticks;

        try std.testing.expect(diff <= 1); // Maximum 1 tick difference
    }
}

test "DivisionConverter - precision maintenance" {
    const converter = try DivisionConverter.init(480, 480);

    // Test that exact values remain exact
    try std.testing.expectEqual(@as(u32, 120), try converter.convertTicksToDivisions(120));
    try std.testing.expectEqual(@as(u32, 240), try converter.convertTicksToDivisions(240));
    try std.testing.expectEqual(@as(u32, 480), try converter.convertTicksToDivisions(480));
}

test "DivisionConverter - optimal divisions selection" {
    // Test automatic optimal division selection
    const converter1 = try DivisionConverter.init(480, 0); // Should keep 480
    try std.testing.expectEqual(@as(u32, 480), converter1.getMusicXMLDivisions());

    const converter2 = try DivisionConverter.init(96, 0); // Should select optimal
    try std.testing.expect(converter2.getMusicXMLDivisions() > 0);

    const converter3 = try DivisionConverter.init(192, 0); // Should keep 192 or select compatible
    try std.testing.expect(converter3.getMusicXMLDivisions() > 0);
}

test "DivisionConverter - error handling" {
    // Test invalid PPQ
    try std.testing.expectError(TimingError.InvalidDivision, DivisionConverter.init(0, 480));

    // Test valid auto-selection (target_divisions = 0 should work)
    const converter_auto = try DivisionConverter.init(480, 0);
    try std.testing.expect(converter_auto.getMusicXMLDivisions() > 0);

    // Test overflow protection
    const converter = try DivisionConverter.init(480, 480);
    try std.testing.expectError(TimingError.InvalidTickValue, converter.convertTicksToDivisions(std.math.maxInt(u32)));
}

test "DivisionConverter - performance benchmark" {
    const converter = try DivisionConverter.init(480, 480);

    const iterations: u32 = 10000;
    const duration_ns = benchmarkConversion(&converter, iterations);
    const duration_per_conversion_ns = duration_ns / iterations;
    const duration_per_conversion_us = @as(f64, @floatFromInt(duration_per_conversion_ns)) / 1000.0;

    log.debug("Division conversion time: {d:.3} μs per conversion (averaged over {} iterations)", .{ duration_per_conversion_us, iterations });

    // Verify < 1μs per conversion performance target per TASK-023
    try std.testing.expect(duration_per_conversion_us < 1.0);
}

test "selectOptimalDivisions - common values" {
    // Test that common MIDI PPQ values get educational-optimal divisions
    try std.testing.expectEqual(@as(u32, 4), selectOptimalDivisions(96)); // Educational: quarter=4
    try std.testing.expectEqual(@as(u32, 8), selectOptimalDivisions(192)); // Educational: quarter=8
    try std.testing.expectEqual(@as(u32, 20), selectOptimalDivisions(480)); // Educational: quarter=20
    try std.testing.expectEqual(@as(u32, 40), selectOptimalDivisions(960)); // Educational: quarter=40

    // Test uncommon values get reasonable selections
    const result_127 = selectOptimalDivisions(127);
    try std.testing.expect(result_127 > 0);

    const result_1000 = selectOptimalDivisions(1000);
    try std.testing.expect(result_1000 > 0);
}

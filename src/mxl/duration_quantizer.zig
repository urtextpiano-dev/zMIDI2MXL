const std = @import("std");

// Implements EXECUTIVE MANDATE per critical timing accuracy issue
// Professional-grade duration normalization for MusicXML generation
// Reference: MuseScore/professional notation software standards

/// Standard note duration ratios relative to quarter note (1.0)
pub const StandardDurations = struct {
    pub const BREVE: f64 = 8.0;         // Double whole note
    pub const WHOLE: f64 = 4.0;         // Whole note  
    pub const HALF: f64 = 2.0;          // Half note
    pub const QUARTER: f64 = 1.0;       // Quarter note (base unit)
    pub const EIGHTH: f64 = 0.5;        // Eighth note
    pub const SIXTEENTH: f64 = 0.25;    // 16th note
    pub const THIRTY_SECOND: f64 = 0.125; // 32nd note
    pub const SIXTY_FOURTH: f64 = 0.0625; // 64th note
    pub const ONE_TWENTY_EIGHTH: f64 = 0.03125; // 128th note
    pub const TWO_FIFTY_SIXTH: f64 = 0.015625;  // 256th note
};

/// Quantization tolerance for professional rounding (2% variance)
pub const QUANTIZATION_TOLERANCE: f64 = 0.02;

/// Professional duration quantizer for MusicXML generation
pub const DurationQuantizer = struct {
    raw_divisions: u32,           // Original divisions from MIDI (e.g., 480)
    normalized_divisions: u32,    // Professional divisions for output (typically 1)
    
    /// Initialize quantizer with raw MIDI divisions
    /// Implements professional normalization per executive mandate
    pub fn init(raw_divisions: u32) DurationQuantizer {
        return .{
            .raw_divisions = raw_divisions,
            .normalized_divisions = raw_divisions, // Match input divisions for educational accuracy
        };
    }
    
    /// Quantize raw duration to nearest standard note value
    /// Implements professional 2% tolerance rounding per requirement
    pub fn quantizeDuration(self: *const DurationQuantizer, raw_duration: u32) QuantizedDuration {
        // Convert raw duration to ratio relative to quarter note
        const raw_ratio = @as(f64, @floatFromInt(raw_duration)) / @as(f64, @floatFromInt(self.raw_divisions));
        
        // CRITICAL: Reject quantization of tiny durations per EXECUTIVE AUTHORITY fix
        // Durations less than 5% of quarter note are measurement noise, not musical content
        if (raw_ratio < 0.05) {
            return QuantizedDuration{
                .normalized_duration = 0, // Zero = no rest generated
                .note_type = .quarter,
                .was_quantized = false,
                .original_duration = raw_duration,
            };
        }
        
        // Find closest standard duration within tolerance
        const standard_durations = [_]f64{
            StandardDurations.TWO_FIFTY_SIXTH,
            StandardDurations.ONE_TWENTY_EIGHTH,
            StandardDurations.SIXTY_FOURTH,
            StandardDurations.THIRTY_SECOND,
            StandardDurations.SIXTEENTH,
            StandardDurations.EIGHTH,
            StandardDurations.QUARTER,
            StandardDurations.HALF,
            StandardDurations.WHOLE,
            StandardDurations.BREVE,
        };
        
        var best_match: f64 = StandardDurations.QUARTER; // Default to quarter
        var min_error: f64 = std.math.inf(f64);
        
        for (standard_durations) |standard| {
            const diff = @abs(raw_ratio - standard);
            const tolerance = standard * QUANTIZATION_TOLERANCE;
            
            if (diff <= tolerance and diff < min_error) {
                best_match = standard;
                min_error = diff;
            }
        }
        
        // Calculate normalized duration with proper rounding
        // For divisions=1, we want quarter note = 1, half note = 2, eighth note rounds to 1 (minimum)
        const normalized_float = best_match * @as(f64, @floatFromInt(self.normalized_divisions));
        const normalized_duration = if (normalized_float < 1.0) 1 else @as(u32, @intFromFloat(@round(normalized_float)));
        
        return QuantizedDuration{
            .normalized_duration = normalized_duration,
            .note_type = self.ratioToNoteType(best_match),
            .was_quantized = min_error > 0.001, // Mark if significant quantization occurred
            .original_duration = raw_duration,
        };
    }
    
    /// Convert duration ratio to MusicXML note type
    fn ratioToNoteType(self: *const DurationQuantizer, ratio: f64) NoteType {
        _ = self;
        
        // Match ratio to note type with small tolerance for floating point comparison
        const epsilon = 0.001;
        
        if (@abs(ratio - StandardDurations.BREVE) < epsilon) return .breve;
        if (@abs(ratio - StandardDurations.WHOLE) < epsilon) return .whole;
        if (@abs(ratio - StandardDurations.HALF) < epsilon) return .half;
        if (@abs(ratio - StandardDurations.QUARTER) < epsilon) return .quarter;
        if (@abs(ratio - StandardDurations.EIGHTH) < epsilon) return .eighth;
        if (@abs(ratio - StandardDurations.SIXTEENTH) < epsilon) return .@"16th";
        if (@abs(ratio - StandardDurations.THIRTY_SECOND) < epsilon) return .@"32nd";
        if (@abs(ratio - StandardDurations.SIXTY_FOURTH) < epsilon) return .@"64th";
        if (@abs(ratio - StandardDurations.ONE_TWENTY_EIGHTH) < epsilon) return .@"128th";
        if (@abs(ratio - StandardDurations.TWO_FIFTY_SIXTH) < epsilon) return .@"256th";
        
        // Default to quarter note for any edge cases
        return .quarter;
    }
    
    /// Get normalized divisions for MusicXML output
    /// Professional standard: typically 1 for clean output
    pub fn getNormalizedDivisions(self: *const DurationQuantizer) u32 {
        return self.normalized_divisions;
    }
    
    /// Check if a raw duration should be quantized
    /// Returns true if duration is close to a standard value within tolerance
    pub fn shouldQuantize(self: *const DurationQuantizer, raw_duration: u32) bool {
        const raw_ratio = @as(f64, @floatFromInt(raw_duration)) / @as(f64, @floatFromInt(self.raw_divisions));
        
        const standard_durations = [_]f64{
            StandardDurations.TWO_FIFTY_SIXTH,
            StandardDurations.ONE_TWENTY_EIGHTH,
            StandardDurations.SIXTY_FOURTH,
            StandardDurations.THIRTY_SECOND,
            StandardDurations.SIXTEENTH,
            StandardDurations.EIGHTH,
            StandardDurations.QUARTER,
            StandardDurations.HALF,
            StandardDurations.WHOLE,
            StandardDurations.BREVE,
        };
        
        for (standard_durations) |standard| {
            const diff = @abs(raw_ratio - standard);
            const tolerance = standard * QUANTIZATION_TOLERANCE;
            
            if (diff <= tolerance) {
                return true;
            }
        }
        
        return false;
    }
};

/// Result of duration quantization
pub const QuantizedDuration = struct {
    normalized_duration: u32,     // Normalized duration for MusicXML output
    note_type: NoteType,         // Corresponding note type
    was_quantized: bool,         // Whether quantization was applied
    original_duration: u32,      // Original raw duration for reference
    
    /// Get the normalized duration as string for MusicXML
    pub fn toMusicXMLDuration(self: *const QuantizedDuration, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d}", .{self.normalized_duration});
    }
};

/// Note type enumeration matching MusicXML standards
pub const NoteType = enum {
    breve,
    whole,
    half,
    quarter,
    eighth,
    @"16th",
    @"32nd",
    @"64th",
    @"128th",
    @"256th",
    
    pub fn toString(self: NoteType) []const u8 {
        return switch (self) {
            .breve => "breve",
            .whole => "whole",
            .half => "half",
            .quarter => "quarter",
            .eighth => "eighth",
            .@"16th" => "16th",
            .@"32nd" => "32nd",
            .@"64th" => "64th",
            .@"128th" => "128th",
            .@"256th" => "256th",
        };
    }
};

// Tests for professional duration quantization

test "DurationQuantizer - initialization" {
    const quantizer = DurationQuantizer.init(480);
    try std.testing.expectEqual(@as(u32, 480), quantizer.raw_divisions);
    try std.testing.expectEqual(@as(u32, 1), quantizer.normalized_divisions);
}

test "DurationQuantizer - quarter note quantization" {
    const quantizer = DurationQuantizer.init(480);
    
    // Test exact quarter note (480 ticks)
    {
        const result = quantizer.quantizeDuration(480);
        try std.testing.expectEqual(@as(u32, 1), result.normalized_duration);
        try std.testing.expectEqual(NoteType.quarter, result.note_type);
        try std.testing.expectEqual(false, result.was_quantized);
    }
    
    // Test near quarter note (479 ticks - within 2% tolerance)
    {
        const result = quantizer.quantizeDuration(479);
        try std.testing.expectEqual(@as(u32, 1), result.normalized_duration);
        try std.testing.expectEqual(NoteType.quarter, result.note_type);
        try std.testing.expectEqual(true, result.was_quantized);
        try std.testing.expectEqual(@as(u32, 479), result.original_duration);
    }
    
    // Test near quarter note (481 ticks - within 2% tolerance)
    {
        const result = quantizer.quantizeDuration(481);
        try std.testing.expectEqual(@as(u32, 1), result.normalized_duration);
        try std.testing.expectEqual(NoteType.quarter, result.note_type);
        try std.testing.expectEqual(true, result.was_quantized);
    }
}

test "DurationQuantizer - various note types" {
    const quantizer = DurationQuantizer.init(480);
    
    // Half note (960 ticks)
    {
        const result = quantizer.quantizeDuration(960);
        try std.testing.expectEqual(@as(u32, 2), result.normalized_duration);
        try std.testing.expectEqual(NoteType.half, result.note_type);
    }
    
    // Eighth note (240 ticks) - rounds up to minimum duration 1
    {
        const result = quantizer.quantizeDuration(240);
        try std.testing.expectEqual(@as(u32, 1), result.normalized_duration); // Minimum duration
        try std.testing.expectEqual(NoteType.eighth, result.note_type);
    }
    
    // Whole note (1920 ticks)
    {
        const result = quantizer.quantizeDuration(1920);
        try std.testing.expectEqual(@as(u32, 4), result.normalized_duration);
        try std.testing.expectEqual(NoteType.whole, result.note_type);
    }
}

test "DurationQuantizer - tolerance testing" {
    const quantizer = DurationQuantizer.init(480);
    
    // Test 2% tolerance for quarter note (480 ± 9.6 = 470.4 to 489.6)
    const quarter_note_base = 480;
    const tolerance_range = @as(u32, @intFromFloat(@as(f64, @floatFromInt(quarter_note_base)) * QUANTIZATION_TOLERANCE));
    
    // Within tolerance - should quantize to quarter
    {
        const low_end = quarter_note_base - tolerance_range;
        const result = quantizer.quantizeDuration(low_end);
        try std.testing.expectEqual(NoteType.quarter, result.note_type);
        try std.testing.expectEqual(true, result.was_quantized);
    }
    
    {
        const high_end = quarter_note_base + tolerance_range;
        const result = quantizer.quantizeDuration(high_end);
        try std.testing.expectEqual(NoteType.quarter, result.note_type);
        try std.testing.expectEqual(true, result.was_quantized);
    }
}

test "DurationQuantizer - should quantize detection" {
    const quantizer = DurationQuantizer.init(480);
    
    // Should quantize values close to standard durations
    try std.testing.expect(quantizer.shouldQuantize(479)); // Close to quarter
    try std.testing.expect(quantizer.shouldQuantize(481)); // Close to quarter
    try std.testing.expect(quantizer.shouldQuantize(240)); // Close to eighth
    try std.testing.expect(quantizer.shouldQuantize(960)); // Close to half
    
    // Should not quantize values far from standard durations
    try std.testing.expect(!quantizer.shouldQuantize(100)); // Too far from any standard
    try std.testing.expect(!quantizer.shouldQuantize(2000)); // Too far from any standard
}

test "DurationQuantizer - tiny duration filtering (EXECUTIVE AUTHORITY fix)" {
    const quantizer = DurationQuantizer.init(480);
    
    // Test 4-tick remainder issue (0.83% of quarter note)
    {
        const result = quantizer.quantizeDuration(4);
        try std.testing.expectEqual(@as(u32, 0), result.normalized_duration);
        try std.testing.expectEqual(@as(u32, 4), result.original_duration);
        try std.testing.expectEqual(false, result.was_quantized);
    }
    
    // Test other tiny durations below 5% threshold
    {
        const result = quantizer.quantizeDuration(20); // ~4.2% of quarter
        try std.testing.expectEqual(@as(u32, 0), result.normalized_duration);
    }
    
    // Test exactly at 5% threshold (24 ticks) - should quantize
    {
        const result = quantizer.quantizeDuration(24); // Exactly 5% of quarter
        try std.testing.expect(result.normalized_duration > 0);
    }
}

test "QuantizedDuration - MusicXML output" {
    const allocator = std.testing.allocator;
    
    const duration = QuantizedDuration{
        .normalized_duration = 1,
        .note_type = .quarter,
        .was_quantized = true,
        .original_duration = 479,
    };
    
    const xml_duration = try duration.toMusicXMLDuration(allocator);
    defer allocator.free(xml_duration);
    
    try std.testing.expectEqualStrings("1", xml_duration);
}

test "NoteType - toString conversion" {
    try std.testing.expectEqualStrings("quarter", NoteType.quarter.toString());
    try std.testing.expectEqualStrings("half", NoteType.half.toString());
    try std.testing.expectEqualStrings("eighth", NoteType.eighth.toString());
    try std.testing.expectEqualStrings("16th", NoteType.@"16th".toString());
    try std.testing.expectEqualStrings("whole", NoteType.whole.toString());
}

test "DurationQuantizer - performance" {
    // Test that quantization meets performance requirements
    const quantizer = DurationQuantizer.init(480);
    
    const iterations = 10000;
    const start = std.time.nanoTimestamp();
    
    for (0..iterations) |i| {
        const test_duration = @as(u32, @intCast(400 + (i % 200))); // Vary duration
        _ = quantizer.quantizeDuration(test_duration);
    }
    
    const end = std.time.nanoTimestamp();
    const elapsed_ns = @as(u64, @intCast(end - start));
    const ns_per_quantization = elapsed_ns / iterations;
    
    // Should be very fast (< 1μs per quantization)
    try std.testing.expect(ns_per_quantization < 1000);
}
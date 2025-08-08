const std = @import("std");

// Implements TASK-028 per IMPLEMENTATION_TASK_LIST.md lines 347-357
// Duration to Note Type Converter
//
// Converts MusicXML divisions to note types with proper dot handling
// and fallback to tied notes when necessary.
// Performance target: < 5μs per conversion
//
// References:
// - MXL_Architecture_Reference.md Appendix B
// - MXL_Architecture_Review_Report.md correction about note type duration multipliers

/// Note type enumeration with correct duration multipliers
/// per MXL_Architecture_Review_Report.md correction
pub const NoteType = enum {
    breve,      // 8 quarter notes (not 2)
    whole,      // 4 quarter notes (not 1)
    half,       // 2 quarter notes (not 0.5)
    quarter,    // 1 quarter note
    eighth,     // 0.5 quarter notes
    @"16th",    // 0.25 quarter notes
    @"32nd",    // 0.125 quarter notes
    @"64th",    // 0.0625 quarter notes
    @"128th",   // 0.03125 quarter notes
    @"256th",   // 0.015625 quarter notes
    
    /// Get string representation for MusicXML
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
    
    /// Get duration in divisions for this note type
    /// Implements corrected multipliers per MXL_Architecture_Review_Report.md
    pub fn getDurationInDivisions(self: NoteType, divisions_per_quarter: u32) u32 {
        return switch (self) {
            .breve => divisions_per_quarter * 8,   // Corrected: 8 quarters
            .whole => divisions_per_quarter * 4,   // Corrected: 4 quarters
            .half => divisions_per_quarter * 2,    // Corrected: 2 quarters
            .quarter => divisions_per_quarter,
            .eighth => divisions_per_quarter / 2,
            .@"16th" => divisions_per_quarter / 4,
            .@"32nd" => divisions_per_quarter / 8,
            .@"64th" => divisions_per_quarter / 16,
            .@"128th" => divisions_per_quarter / 32,
            .@"256th" => divisions_per_quarter / 64,
        };
    }
};

/// Result of note type conversion
pub const NoteTypeResult = struct {
    note_type: NoteType,
    dots: u8,  // Number of dots (0-4)
    
    /// Get total duration including dots
    pub fn getTotalDuration(self: *const NoteTypeResult, divisions_per_quarter: u32) u32 {
        var duration = self.note_type.getDurationInDivisions(divisions_per_quarter);
        var dot_duration = duration / 2;
        
        // Add duration for each dot
        var dots_remaining = self.dots;
        while (dots_remaining > 0) : (dots_remaining -= 1) {
            duration += dot_duration;
            dot_duration /= 2;
        }
        
        return duration;
    }
};

/// Tied note representation for complex durations
pub const TiedNote = struct {
    note_type: NoteType,
    dots: u8,
    tie_type: TieType,
    
    pub const TieType = enum {
        start,      // First note in tie sequence
        middle,     // Middle note in tie sequence
        stop,       // Last note in tie sequence
    };
};

/// Note Type Converter
/// Implements TASK-028 per MXL_Architecture_Reference.md Appendix B
pub const NoteTypeConverter = struct {
    divisions_per_quarter: u32,
    tolerance_percent: f64,  // Tolerance for slight variations (default 10%)
    
    /// Initialize converter with divisions per quarter note
    pub fn init(divisions_per_quarter: u32) NoteTypeConverter {
        return .{
            .divisions_per_quarter = divisions_per_quarter,
            .tolerance_percent = 0.1,  // 10% tolerance by default
        };
    }
    
    /// Convert duration in divisions to note type with dots
    /// Implements algorithm from MXL_Architecture_Reference.md Appendix B
    pub fn convertDurationToNoteType(self: *const NoteTypeConverter, duration: u32) ?NoteTypeResult {
        // Try each note type from longest to shortest
        const note_types = [_]NoteType{
            .breve, .whole, .half, .quarter, .eighth,
            .@"16th", .@"32nd", .@"64th", .@"128th", .@"256th",
        };
        
        for (note_types) |note_type| {
            const base_duration = note_type.getDurationInDivisions(self.divisions_per_quarter);
            
            // Skip if duration is too small for this note type
            const min_duration = @as(f64, @floatFromInt(base_duration)) * (1.0 - self.tolerance_percent);
            if (@as(f64, @floatFromInt(duration)) < min_duration) {
                continue;
            }
            
            // Check if it's a simple note without dots
            if (self.isWithinTolerance(duration, base_duration)) {
                return NoteTypeResult{ .note_type = note_type, .dots = 0 };
            }
            
            // Check for dotted notes (up to 4 dots)
            var dots: u8 = 0;
            var total_duration = base_duration;
            var dot_duration = base_duration / 2;
            
            while (dots < 4) : (dots += 1) {
                const test_duration = total_duration + dot_duration;
                
                if (self.isWithinTolerance(duration, test_duration)) {
                    return NoteTypeResult{ .note_type = note_type, .dots = dots + 1 };
                }
                
                if (test_duration > duration) {
                    break;  // No point checking more dots
                }
                
                total_duration = test_duration;
                dot_duration /= 2;
            }
        }
        
        // No single note type with dots can represent this duration
        return null;
    }
    
    /// Decompose duration into multiple tied notes
    /// Fallback when single note type cannot represent duration
    pub fn decomposeIntoTiedNotes(
        self: *const NoteTypeConverter,
        duration: u32,
        allocator: std.mem.Allocator,
    ) ![]TiedNote {
        var tied_notes = std.ArrayList(TiedNote).init(allocator);
        errdefer tied_notes.deinit();
        
        var remaining_duration = duration;
        var is_first = true;
        
        while (remaining_duration > 0) {
            // Find largest note that fits
            if (self.convertDurationToNoteType(remaining_duration)) |result| {
                const tie_type: TiedNote.TieType = if (is_first)
                    .start
                else if (result.getTotalDuration(self.divisions_per_quarter) == remaining_duration)
                    .stop
                else
                    .middle;
                
                try tied_notes.append(.{
                    .note_type = result.note_type,
                    .dots = result.dots,
                    .tie_type = tie_type,
                });
                
                remaining_duration -= result.getTotalDuration(self.divisions_per_quarter);
                is_first = false;
            } else {
                // Find largest note type that's smaller than remaining duration
                const note_types = [_]NoteType{
                    .breve, .whole, .half, .quarter, .eighth,
                    .@"16th", .@"32nd", .@"64th", .@"128th", .@"256th",
                };
                
                var found = false;
                for (note_types) |note_type| {
                    const note_duration = note_type.getDurationInDivisions(self.divisions_per_quarter);
                    if (note_duration <= remaining_duration) {
                        const tie_type: TiedNote.TieType = if (is_first) .start else .middle;
                        
                        try tied_notes.append(.{
                            .note_type = note_type,
                            .dots = 0,
                            .tie_type = tie_type,
                        });
                        
                        remaining_duration -= note_duration;
                        is_first = false;
                        found = true;
                        break;
                    }
                }
                
                if (!found) {
                    // Use smallest available note type
                    const tie_type: TiedNote.TieType = if (is_first) .start else .middle;
                    
                    try tied_notes.append(.{
                        .note_type = .@"256th",
                        .dots = 0,
                        .tie_type = tie_type,
                    });
                    
                    const min_duration = NoteType.@"256th".getDurationInDivisions(self.divisions_per_quarter);
                    remaining_duration = if (remaining_duration > min_duration)
                        remaining_duration - min_duration
                    else
                        0;
                    is_first = false;
                }
            }
        }
        
        // Fix the last note's tie type
        if (tied_notes.items.len > 0) {
            tied_notes.items[tied_notes.items.len - 1].tie_type = .stop;
        }
        
        return tied_notes.toOwnedSlice();
    }
    
    /// Check if two durations are within tolerance
    fn isWithinTolerance(self: *const NoteTypeConverter, actual: u32, expected: u32) bool {
        const diff = if (actual > expected) actual - expected else expected - actual;
        const tolerance = @as(f64, @floatFromInt(expected)) * self.tolerance_percent;
        return @as(f64, @floatFromInt(diff)) <= tolerance;
    }
};

// Performance testing helper for TASK-028 validation

/// Benchmark note type conversion performance
pub fn benchmarkConversion(converter: *const NoteTypeConverter, iterations: u32) u64 {
    const start_time = std.time.nanoTimestamp();
    
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        // Test various durations
        const test_durations = [_]u32{ 120, 240, 360, 480, 720, 960, 1440, 1920 };
        const duration = test_durations[i % test_durations.len];
        _ = converter.convertDurationToNoteType(duration);
    }
    
    const end_time = std.time.nanoTimestamp();
    return @as(u64, @intCast(end_time - start_time));
}

// Tests for TASK-028 validation

test "NoteType - duration calculations with corrected multipliers" {
    const divisions = 480;
    
    // Test corrected multipliers per MXL_Architecture_Review_Report.md
    try std.testing.expectEqual(@as(u32, 3840), NoteType.breve.getDurationInDivisions(divisions));   // 8 * 480
    try std.testing.expectEqual(@as(u32, 1920), NoteType.whole.getDurationInDivisions(divisions));   // 4 * 480
    try std.testing.expectEqual(@as(u32, 960), NoteType.half.getDurationInDivisions(divisions));     // 2 * 480
    try std.testing.expectEqual(@as(u32, 480), NoteType.quarter.getDurationInDivisions(divisions));  // 1 * 480
    try std.testing.expectEqual(@as(u32, 240), NoteType.eighth.getDurationInDivisions(divisions));   // 0.5 * 480
    try std.testing.expectEqual(@as(u32, 120), NoteType.@"16th".getDurationInDivisions(divisions));  // 0.25 * 480
    try std.testing.expectEqual(@as(u32, 60), NoteType.@"32nd".getDurationInDivisions(divisions));   // 0.125 * 480
    try std.testing.expectEqual(@as(u32, 30), NoteType.@"64th".getDurationInDivisions(divisions));   // 0.0625 * 480
    try std.testing.expectEqual(@as(u32, 15), NoteType.@"128th".getDurationInDivisions(divisions));  // 0.03125 * 480
    try std.testing.expectEqual(@as(u32, 7), NoteType.@"256th".getDurationInDivisions(divisions));   // 0.015625 * 480
}

test "NoteTypeConverter - simple note types" {
    const converter = NoteTypeConverter.init(480);
    
    // Test exact matches
    if (converter.convertDurationToNoteType(1920)) |result| {
        try std.testing.expectEqual(NoteType.whole, result.note_type);
        try std.testing.expectEqual(@as(u8, 0), result.dots);
    } else {
        try std.testing.expect(false); // Should match
    }
    
    if (converter.convertDurationToNoteType(960)) |result| {
        try std.testing.expectEqual(NoteType.half, result.note_type);
        try std.testing.expectEqual(@as(u8, 0), result.dots);
    } else {
        try std.testing.expect(false); // Should match
    }
    
    if (converter.convertDurationToNoteType(480)) |result| {
        try std.testing.expectEqual(NoteType.quarter, result.note_type);
        try std.testing.expectEqual(@as(u8, 0), result.dots);
    } else {
        try std.testing.expect(false); // Should match
    }
}

test "NoteTypeConverter - dotted notes" {
    const converter = NoteTypeConverter.init(480);
    
    // Test dotted quarter (480 + 240 = 720)
    if (converter.convertDurationToNoteType(720)) |result| {
        try std.testing.expectEqual(NoteType.quarter, result.note_type);
        try std.testing.expectEqual(@as(u8, 1), result.dots);
        try std.testing.expectEqual(@as(u32, 720), result.getTotalDuration(480));
    } else {
        try std.testing.expect(false); // Should match
    }
    
    // Test double-dotted quarter (480 + 240 + 120 = 840)
    if (converter.convertDurationToNoteType(840)) |result| {
        try std.testing.expectEqual(NoteType.quarter, result.note_type);
        try std.testing.expectEqual(@as(u8, 2), result.dots);
        try std.testing.expectEqual(@as(u32, 840), result.getTotalDuration(480));
    } else {
        try std.testing.expect(false); // Should match
    }
    
    // Test dotted half (960 + 480 = 1440)
    if (converter.convertDurationToNoteType(1440)) |result| {
        try std.testing.expectEqual(NoteType.half, result.note_type);
        try std.testing.expectEqual(@as(u8, 1), result.dots);
        try std.testing.expectEqual(@as(u32, 1440), result.getTotalDuration(480));
    } else {
        try std.testing.expect(false); // Should match
    }
}

test "NoteTypeConverter - tolerance handling" {
    var converter = NoteTypeConverter.init(480);
    converter.tolerance_percent = 0.1; // 10% tolerance
    
    // Test value slightly off from quarter note (480 ± 10%)
    if (converter.convertDurationToNoteType(475)) |result| {
        try std.testing.expectEqual(NoteType.quarter, result.note_type);
        try std.testing.expectEqual(@as(u8, 0), result.dots);
    } else {
        try std.testing.expect(false); // Should match with tolerance
    }
    
    if (converter.convertDurationToNoteType(485)) |result| {
        try std.testing.expectEqual(NoteType.quarter, result.note_type);
        try std.testing.expectEqual(@as(u8, 0), result.dots);
    } else {
        try std.testing.expect(false); // Should match with tolerance
    }
}

test "NoteTypeConverter - tied notes decomposition" {
    const allocator = std.testing.allocator;
    const converter = NoteTypeConverter.init(480);
    
    // Test duration that requires tied notes (e.g., 5 quarter notes = 2400)
    const tied_notes = try converter.decomposeIntoTiedNotes(2400, allocator);
    defer allocator.free(tied_notes);
    
    try std.testing.expect(tied_notes.len > 1); // Should need multiple notes
    
    // First note should be "start"
    try std.testing.expectEqual(TiedNote.TieType.start, tied_notes[0].tie_type);
    
    // Last note should be "stop"
    try std.testing.expectEqual(TiedNote.TieType.stop, tied_notes[tied_notes.len - 1].tie_type);
    
    // Total duration should match
    var total_duration: u32 = 0;
    for (tied_notes) |tied_note| {
        const result = NoteTypeResult{
            .note_type = tied_note.note_type,
            .dots = tied_note.dots,
        };
        total_duration += result.getTotalDuration(480);
    }
    try std.testing.expectEqual(@as(u32, 2400), total_duration);
}

test "NoteTypeConverter - complex durations" {
    const allocator = std.testing.allocator;
    const converter = NoteTypeConverter.init(480);
    
    // Test various complex durations
    const test_cases = [_]u32{ 100, 333, 777, 1111, 2222, 3333 };
    
    for (test_cases) |duration| {
        // Try single note first
        const single_result = converter.convertDurationToNoteType(duration);
        
        // If no single note works, decompose
        if (single_result == null) {
            const tied_notes = try converter.decomposeIntoTiedNotes(duration, allocator);
            defer allocator.free(tied_notes);
            
            // Verify total duration
            var total: u32 = 0;
            for (tied_notes) |tied_note| {
                const result = NoteTypeResult{
                    .note_type = tied_note.note_type,
                    .dots = tied_note.dots,
                };
                total += result.getTotalDuration(480);
            }
            
            // Allow small rounding error for complex durations
            const diff = if (total > duration) total - duration else duration - total;
            try std.testing.expect(diff <= duration / 100); // Max 1% error
        }
    }
}

test "NoteTypeConverter - performance benchmark" {
    const converter = NoteTypeConverter.init(480);
    
    const iterations: u32 = 10000;
    const duration_ns = benchmarkConversion(&converter, iterations);
    const duration_per_conversion_ns = duration_ns / iterations;
    const duration_per_conversion_us = @as(f64, @floatFromInt(duration_per_conversion_ns)) / 1000.0;
    
    std.debug.print("Note type conversion time: {d:.3} μs per conversion (averaged over {} iterations)\n", 
        .{ duration_per_conversion_us, iterations });
    
    // Verify < 5μs per conversion performance target per TASK-028
    try std.testing.expect(duration_per_conversion_us < 5.0);
}

test "NoteType - string representation" {
    try std.testing.expectEqualStrings("breve", NoteType.breve.toString());
    try std.testing.expectEqualStrings("whole", NoteType.whole.toString());
    try std.testing.expectEqualStrings("half", NoteType.half.toString());
    try std.testing.expectEqualStrings("quarter", NoteType.quarter.toString());
    try std.testing.expectEqualStrings("eighth", NoteType.eighth.toString());
    try std.testing.expectEqualStrings("16th", NoteType.@"16th".toString());
    try std.testing.expectEqualStrings("32nd", NoteType.@"32nd".toString());
    try std.testing.expectEqualStrings("64th", NoteType.@"64th".toString());
    try std.testing.expectEqualStrings("128th", NoteType.@"128th".toString());
    try std.testing.expectEqualStrings("256th", NoteType.@"256th".toString());
}

test "NoteTypeConverter - integration with different divisions" {
    // Test with various common division values
    const division_values = [_]u32{ 96, 192, 384, 480, 768, 960 };
    
    for (division_values) |divisions| {
        const converter = NoteTypeConverter.init(divisions);
        
        // Quarter note should always be exactly the divisions value
        const quarter_result = converter.convertDurationToNoteType(divisions);
        try std.testing.expect(quarter_result != null);
        try std.testing.expectEqual(NoteType.quarter, quarter_result.?.note_type);
        try std.testing.expectEqual(@as(u8, 0), quarter_result.?.dots);
        
        // Whole note should be 4x divisions (corrected multiplier)
        const whole_result = converter.convertDurationToNoteType(divisions * 4);
        try std.testing.expect(whole_result != null);
        try std.testing.expectEqual(NoteType.whole, whole_result.?.note_type);
        try std.testing.expectEqual(@as(u8, 0), whole_result.?.dots);
        
        // Breve should be 8x divisions (corrected multiplier)
        const breve_result = converter.convertDurationToNoteType(divisions * 8);
        try std.testing.expect(breve_result != null);
        try std.testing.expectEqual(NoteType.breve, breve_result.?.note_type);
        try std.testing.expectEqual(@as(u8, 0), breve_result.?.dots);
    }
}
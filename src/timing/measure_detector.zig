//! Measure Boundary Detection Module
//! 
//! Implements TASK-025: Measure Boundary Detection per IMPLEMENTATION_TASK_LIST.md lines 312-321
//! 
//! This module detects measure boundaries from time signature information,
//! splits notes that cross measure boundaries, and generates proper ties.
//! 
//! Features:
//! - Detect measure boundaries from time signature events
//! - Split notes crossing measures with proper ties
//! - Handle time signature changes mid-piece
//! - O(n) complexity performance target
//! 
//! References MXL_Architecture_Reference.md Section 5.4 lines per TASK-025

const std = @import("std");
const containers = @import("../utils/containers.zig");
const timing = @import("division_converter.zig");
const midi_parser = @import("../midi/parser.zig");
const error_mod = @import("../error.zig");

/// Error types for measure boundary detection operations
pub const MeasureBoundaryError = error{
    InvalidTimeSignature,
    InvalidNote,
    NegativeDuration,
    NoTimeSignature,
    AllocationFailure,
};

/// Represents a musical note with timing information
/// Used for both input notes and split note results
pub const TimedNote = struct {
    /// MIDI note number (0-127)
    note: u8,
    /// MIDI channel (0-15) 
    channel: u8,
    /// MIDI velocity (0-127)
    velocity: u8,
    /// Start time in MIDI ticks (absolute time)
    start_tick: u32,
    /// Duration in MIDI ticks
    duration: u32,
    /// Whether this note is tied to the next note
    tied_to_next: bool = false,
    /// Whether this note is tied from the previous note
    tied_from_previous: bool = false,
    /// Track index this note belongs to (0-based)
    /// Implements TASK 1.1 per CHORD_DETECTION_FIX_TASK_LIST.md lines 9-26
    track: u8 = 0,
    /// Voice assignment (1-4 within staff, 0 = unassigned)
    /// Implements MVS-2.1 per MULTI_VOICE_SEPARATION_TASK_LIST.md
    voice: u8 = 0,
};

/// Represents a tied note pair created when splitting across measure boundary
pub const TiedNotePair = struct {
    /// First part of the split note (ends at measure boundary)
    first: TimedNote,
    /// Second part of the split note (starts at measure boundary)
    second: TimedNote,
};

/// Represents a complete measure with its timing boundaries and contained notes
pub const Measure = struct {
    /// Measure number (1-based indexing for MusicXML compatibility)
    number: u32,
    /// Start tick of this measure (inclusive)
    start_tick: u32,
    /// End tick of this measure (exclusive)
    end_tick: u32,
    /// Time signature active for this measure
    time_signature: midi_parser.TimeSignatureEvent,
    /// Notes that start and end within this measure
    notes: containers.List(TimedNote),
    
    /// Initialize a new measure
    pub fn init(allocator: std.mem.Allocator, number: u32, start_tick: u32, end_tick: u32, time_signature: midi_parser.TimeSignatureEvent) Measure {
        return Measure{
            .number = number,
            .start_tick = start_tick,
            .end_tick = end_tick,
            .time_signature = time_signature,
            .notes = containers.List(TimedNote).init(allocator),
        };
    }
    
    /// Clean up measure resources
    pub fn deinit(self: *Measure) void {
        self.notes.deinit();
    }
    
    /// Add a note to this measure
    pub fn addNote(self: *Measure, note: TimedNote) std.mem.Allocator.Error!void {
        try self.notes.append(note);
    }
    
    /// Get the duration of this measure in ticks
    pub fn getDurationTicks(self: *const Measure) u32 {
        return self.end_tick - self.start_tick;
    }
};

/// Measure Boundary Detector
/// Implements TASK-025 per IMPLEMENTATION_TASK_LIST.md lines 312-321
pub const MeasureBoundaryDetector = struct {
    allocator: std.mem.Allocator,
    division_converter: *const timing.DivisionConverter,
    
    /// Initialize the measure boundary detector
    pub fn init(allocator: std.mem.Allocator, division_converter: *const timing.DivisionConverter) MeasureBoundaryDetector {
        return MeasureBoundaryDetector{
            .allocator = allocator,
            .division_converter = division_converter,
        };
    }
    
    /// Calculate ticks per measure for a given time signature
    /// Implements TASK-025 per MXL_Architecture_Reference.md Section 5.4
    pub fn calculateTicksPerMeasure(self: *const MeasureBoundaryDetector, time_signature: midi_parser.TimeSignatureEvent) MeasureBoundaryError!u32 {
        // Validate time signature
        if (time_signature.numerator == 0 or time_signature.denominator_power > 7) {
            return MeasureBoundaryError.InvalidTimeSignature;
        }
        
        const ppq = self.division_converter.getMidiPPQ();
        const denominator = time_signature.getDenominator();
        
        // Calculate ticks per measure:
        // For 4/4: 4 quarter notes = 4 * ppq ticks
        // For 3/4: 3 quarter notes = 3 * ppq ticks  
        // For 6/8: 6 eighth notes = 6 * (ppq / 2) = 3 * ppq ticks
        // General formula: (numerator * ppq * 4) / denominator
        const ticks_per_measure = (time_signature.numerator * ppq * 4) / denominator;
        
        if (ticks_per_measure == 0) {
            return MeasureBoundaryError.InvalidTimeSignature;
        }
        
        return ticks_per_measure;
    }
    
    /// Detect measure boundaries and organize notes into measures
    /// Implements the core algorithm from MXL_Architecture_Reference.md Section 5.4
    /// Performance target: O(n) complexity per TASK-025
    pub fn detectMeasureBoundaries(
        self: *const MeasureBoundaryDetector,
        notes: []const TimedNote,
        time_signatures: []const midi_parser.TimeSignatureEvent
    ) (MeasureBoundaryError || std.mem.Allocator.Error)!containers.List(Measure) {
        
        if (time_signatures.len == 0) {
            return MeasureBoundaryError.NoTimeSignature;
        }
        
        var measures = containers.List(Measure).init(self.allocator);
        errdefer {
            // Clean up measures on error
            for (measures.items) |*measure| {
                measure.deinit();
            }
            measures.deinit();
        }
        
        // Start with first time signature (default to tick 0 if not specified)
        var current_time_sig_index: usize = 0;
        var current_time_sig = time_signatures[0];
        var current_tick: u32 = 0;
        var measure_number: u32 = 1;
        
        // Calculate initial ticks per measure
        var ticks_per_measure = try self.calculateTicksPerMeasure(current_time_sig);
        
        // Sort notes by start tick for efficient processing
        var sorted_notes = try self.allocator.dupe(TimedNote, notes);
        defer self.allocator.free(sorted_notes);
        std.mem.sort(TimedNote, sorted_notes, {}, compareNotesByStartTick);
        
        var note_index: usize = 0;
        
        // Process all notes and create measures
        while (note_index < sorted_notes.len or current_time_sig_index < time_signatures.len - 1) {
            // Calculate current measure boundaries
            const measure_start_tick = current_tick;
            var measure_end_tick = current_tick + ticks_per_measure;
            
            // Check if there's a time signature change within this measure
            if (current_time_sig_index + 1 < time_signatures.len) {
                const next_time_sig = time_signatures[current_time_sig_index + 1];
                if (next_time_sig.tick < measure_end_tick) {
                    // Time signature changes mid-measure - end measure at time sig change
                    measure_end_tick = next_time_sig.tick;
                }
            }
            
            // Create current measure
            var current_measure = Measure.init(
                self.allocator,
                measure_number,
                measure_start_tick,
                measure_end_tick,
                current_time_sig
            );
            
            // Process notes for this measure
            while (note_index < sorted_notes.len) {
                const note = sorted_notes[note_index];
                
                // Skip notes that start after this measure
                if (note.start_tick >= measure_end_tick) {
                    break;
                }
                
                // Handle note that crosses measure boundary
                if (note.start_tick + note.duration > measure_end_tick) {
                    const split_result = try self.splitNoteAtBoundary(note, measure_end_tick);
                    
                    // Add first part to current measure
                    try current_measure.addNote(split_result.first);
                    
                    // Replace current note with second part for next measure
                    sorted_notes[note_index] = split_result.second;
                    // Don't increment note_index - process the second part in next measure
                    break;
                } else {
                    // Note fits entirely in current measure
                    try current_measure.addNote(note);
                    note_index += 1;
                }
            }
            
            try measures.append(current_measure);
            
            // Advance to next measure
            current_tick = measure_end_tick;
            measure_number += 1;
            
            // Check for time signature change
            if (current_time_sig_index + 1 < time_signatures.len and 
                time_signatures[current_time_sig_index + 1].tick <= current_tick) {
                
                current_time_sig_index += 1;
                current_time_sig = time_signatures[current_time_sig_index];
                ticks_per_measure = try self.calculateTicksPerMeasure(current_time_sig);
            }
            
            // Break if no more notes to process
            if (note_index >= sorted_notes.len) {
                break;
            }
        }
        
        return measures;
    }
    
    /// Split a note at a specific tick boundary, creating tied notes
    /// Implements tie generation per MXL_Architecture_Reference.md Section 5.4
    pub fn splitNoteAtBoundary(self: *const MeasureBoundaryDetector, note: TimedNote, boundary_tick: u32) MeasureBoundaryError!TiedNotePair {
        _ = self; // splitNoteAtBoundary doesn't need detector state
        if (boundary_tick <= note.start_tick) {
            return MeasureBoundaryError.InvalidNote;
        }
        
        if (boundary_tick >= note.start_tick + note.duration) {
            return MeasureBoundaryError.InvalidNote;
        }
        
        const first_duration = boundary_tick - note.start_tick;
        const second_duration = (note.start_tick + note.duration) - boundary_tick;
        
        if (first_duration == 0 or second_duration == 0) {
            return MeasureBoundaryError.InvalidNote;
        }
        
        const first_note = TimedNote{
            .note = note.note,
            .channel = note.channel,
            .velocity = note.velocity,
            .start_tick = note.start_tick,
            .duration = first_duration,
            .tied_to_next = true,  // This note ties to the next part
            .tied_from_previous = note.tied_from_previous,  // Preserve incoming tie
            .track = note.track,  // Preserve track information
            .voice = note.voice,  // Preserve voice assignment
        };
        
        const second_note = TimedNote{
            .note = note.note,
            .channel = note.channel,
            .velocity = note.velocity,
            .start_tick = boundary_tick,
            .duration = second_duration,
            .tied_to_next = note.tied_to_next,  // Preserve outgoing tie
            .tied_from_previous = true,  // This note is tied from the previous part
            .track = note.track,  // Preserve track information
            .voice = note.voice,  // Preserve voice assignment
        };
        
        return TiedNotePair{
            .first = first_note,
            .second = second_note,
        };
    }
    
    /// Get the measure that contains a specific tick
    /// Useful for finding which measure a note belongs to
    pub fn findMeasureForTick(measures: []const Measure, tick: u32) ?*const Measure {
        for (measures) |*measure| {
            if (tick >= measure.start_tick and tick < measure.end_tick) {
                return measure;
            }
        }
        return null;
    }
    
    /// Validate that measures are correctly ordered and non-overlapping
    pub fn validateMeasures(measures: []const Measure) bool {
        if (measures.len == 0) return true;
        
        for (measures[1..], 1..) |measure, i| {
            const prev_measure = measures[i - 1];
            
            // Check ordering
            if (measure.number != prev_measure.number + 1) return false;
            if (measure.start_tick != prev_measure.end_tick) return false;
            if (measure.start_tick >= measure.end_tick) return false;
        }
        
        return true;
    }
};

/// Compare function for sorting notes by start tick
fn compareNotesByStartTick(context: void, a: TimedNote, b: TimedNote) bool {
    _ = context;
    return a.start_tick < b.start_tick;
}

// Performance testing helpers for TASK-025 validation

/// Benchmark measure boundary detection performance
/// Used to verify O(n) complexity requirement per TASK-025
pub fn benchmarkMeasureDetection(
    detector: *const MeasureBoundaryDetector,
    notes: []const TimedNote,
    time_signatures: []const midi_parser.TimeSignatureEvent,
    iterations: u32
) u64 {
    const start_time = std.time.nanoTimestamp();
    
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        var measures = detector.detectMeasureBoundaries(notes, time_signatures) catch continue;
        defer {
            for (measures.items) |*measure| {
                measure.deinit();
            }
            measures.deinit();
        }
    }
    
    const end_time = std.time.nanoTimestamp();
    return @as(u64, @intCast(end_time - start_time));
}

// Tests for TASK-025 validation

test "MeasureBoundaryDetector - initialization" {
    const allocator = std.testing.allocator;
    const converter = try timing.DivisionConverter.init(480, 480);
    const detector = MeasureBoundaryDetector.init(allocator, &converter);
    
    try std.testing.expect(detector.allocator.ptr == allocator.ptr);
}

test "MeasureBoundaryDetector - calculate ticks per measure" {
    const allocator = std.testing.allocator;
    const converter = try timing.DivisionConverter.init(480, 480);
    const detector = MeasureBoundaryDetector.init(allocator, &converter);
    
    // Test 4/4 time signature
    const time_sig_4_4 = midi_parser.TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2,  // 2^2 = 4 (quarter note)
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    const ticks_4_4 = try detector.calculateTicksPerMeasure(time_sig_4_4);
    try std.testing.expectEqual(@as(u32, 1920), ticks_4_4); // 4 * 480 = 1920
    
    // Test 3/4 time signature
    const time_sig_3_4 = midi_parser.TimeSignatureEvent{
        .tick = 0,
        .numerator = 3,
        .denominator_power = 2,  // 2^2 = 4 (quarter note)
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    const ticks_3_4 = try detector.calculateTicksPerMeasure(time_sig_3_4);
    try std.testing.expectEqual(@as(u32, 1440), ticks_3_4); // 3 * 480 = 1440
    
    // Test 6/8 time signature
    const time_sig_6_8 = midi_parser.TimeSignatureEvent{
        .tick = 0,
        .numerator = 6,
        .denominator_power = 3,  // 2^3 = 8 (eighth note)
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    const ticks_6_8 = try detector.calculateTicksPerMeasure(time_sig_6_8);
    try std.testing.expectEqual(@as(u32, 1440), ticks_6_8); // 6 * 480 * 4 / 8 = 1440
}

test "MeasureBoundaryDetector - split note at boundary" {
    const allocator = std.testing.allocator;
    const converter = try timing.DivisionConverter.init(480, 480);
    const detector = MeasureBoundaryDetector.init(allocator, &converter);
    
    const note = TimedNote{
        .note = 60,  // Middle C
        .channel = 0,
        .velocity = 80,
        .start_tick = 1800,  // Starts 120 ticks before measure boundary
        .duration = 240,     // Extends 120 ticks past measure boundary
        .tied_to_next = false,
        .tied_from_previous = false,
    };
    
    const boundary_tick: u32 = 1920;  // Measure boundary
    const split_result = try detector.splitNoteAtBoundary(note, boundary_tick);
    
    // Check first part
    try std.testing.expectEqual(@as(u32, 1800), split_result.first.start_tick);
    try std.testing.expectEqual(@as(u32, 120), split_result.first.duration);
    try std.testing.expect(split_result.first.tied_to_next);
    try std.testing.expect(!split_result.first.tied_from_previous);
    
    // Check second part  
    try std.testing.expectEqual(@as(u32, 1920), split_result.second.start_tick);
    try std.testing.expectEqual(@as(u32, 120), split_result.second.duration);
    try std.testing.expect(!split_result.second.tied_to_next);
    try std.testing.expect(split_result.second.tied_from_previous);
    
    // Check note properties preserved
    try std.testing.expectEqual(note.note, split_result.first.note);
    try std.testing.expectEqual(note.note, split_result.second.note);
    try std.testing.expectEqual(note.channel, split_result.first.channel);
    try std.testing.expectEqual(note.velocity, split_result.second.velocity);
}

test "MeasureBoundaryDetector - simple measure detection" {
    const allocator = std.testing.allocator;
    const converter = try timing.DivisionConverter.init(480, 480);
    const detector = MeasureBoundaryDetector.init(allocator, &converter);
    
    // Create test time signature (4/4)
    const time_sig = midi_parser.TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    const time_signatures = [_]midi_parser.TimeSignatureEvent{time_sig};
    
    // Create test notes
    const notes = [_]TimedNote{
        TimedNote{
            .note = 60, .channel = 0, .velocity = 80,
            .start_tick = 0, .duration = 480,  // First measure
        },
        TimedNote{
            .note = 62, .channel = 0, .velocity = 80,
            .start_tick = 480, .duration = 480,  // First measure
        },
        TimedNote{
            .note = 64, .channel = 0, .velocity = 80,
            .start_tick = 1920, .duration = 480,  // Second measure
        },
    };
    
    var measures = try detector.detectMeasureBoundaries(&notes, &time_signatures);
    defer {
        for (measures.items) |*measure| {
            measure.deinit();
        }
        measures.deinit();
    }
    
    // Should have 2 measures
    try std.testing.expectEqual(@as(usize, 2), measures.items.len);
    
    // Check first measure
    const first_measure = measures.items[0];
    try std.testing.expectEqual(@as(u32, 1), first_measure.number);
    try std.testing.expectEqual(@as(u32, 0), first_measure.start_tick);
    try std.testing.expectEqual(@as(u32, 1920), first_measure.end_tick);
    try std.testing.expectEqual(@as(usize, 2), first_measure.notes.items.len);
    
    // Check second measure
    const second_measure = measures.items[1];
    try std.testing.expectEqual(@as(u32, 2), second_measure.number);
    try std.testing.expectEqual(@as(u32, 1920), second_measure.start_tick);
    try std.testing.expectEqual(@as(u32, 3840), second_measure.end_tick);
    try std.testing.expectEqual(@as(usize, 1), second_measure.notes.items.len);
}

test "MeasureBoundaryDetector - note crossing measure boundary" {
    const allocator = std.testing.allocator;
    const converter = try timing.DivisionConverter.init(480, 480);
    const detector = MeasureBoundaryDetector.init(allocator, &converter);
    
    // Create test time signature (4/4) 
    const time_sig = midi_parser.TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    const time_signatures = [_]midi_parser.TimeSignatureEvent{time_sig};
    
    // Create note that crosses measure boundary
    const notes = [_]TimedNote{
        TimedNote{
            .note = 60, .channel = 0, .velocity = 80,
            .start_tick = 1800,   // Starts in first measure
            .duration = 240,      // Extends into second measure (boundary at 1920)
        },
    };
    
    var measures = try detector.detectMeasureBoundaries(&notes, &time_signatures);
    defer {
        for (measures.items) |*measure| {
            measure.deinit();
        }
        measures.deinit();
    }
    
    // Should have 2 measures
    try std.testing.expectEqual(@as(usize, 2), measures.items.len);
    
    // Check first measure - should have first part of split note
    const first_measure = measures.items[0];
    try std.testing.expectEqual(@as(usize, 1), first_measure.notes.items.len);
    const first_note = first_measure.notes.items[0];
    try std.testing.expectEqual(@as(u32, 1800), first_note.start_tick);
    try std.testing.expectEqual(@as(u32, 120), first_note.duration);
    try std.testing.expect(first_note.tied_to_next);
    
    // Check second measure - should have second part of split note
    const second_measure = measures.items[1];
    try std.testing.expectEqual(@as(usize, 1), second_measure.notes.items.len);
    const second_note = second_measure.notes.items[0];
    try std.testing.expectEqual(@as(u32, 1920), second_note.start_tick);
    try std.testing.expectEqual(@as(u32, 120), second_note.duration);
    try std.testing.expect(second_note.tied_from_previous);
}

test "MeasureBoundaryDetector - error handling" {
    const allocator = std.testing.allocator;
    const converter = try timing.DivisionConverter.init(480, 480);
    const detector = MeasureBoundaryDetector.init(allocator, &converter);
    
    // Test invalid time signature
    const invalid_time_sig = midi_parser.TimeSignatureEvent{
        .tick = 0,
        .numerator = 0,  // Invalid
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };
    
    try std.testing.expectError(MeasureBoundaryError.InvalidTimeSignature,
        detector.calculateTicksPerMeasure(invalid_time_sig));
    
    // Test no time signatures
    const notes = [_]TimedNote{};
    const time_signatures = [_]midi_parser.TimeSignatureEvent{};
    
    try std.testing.expectError(MeasureBoundaryError.NoTimeSignature,
        detector.detectMeasureBoundaries(&notes, &time_signatures));
}

test "compareNotesByStartTick" {
    const note1 = TimedNote{
        .note = 60, .channel = 0, .velocity = 80,
        .start_tick = 100, .duration = 240,
    };
    
    const note2 = TimedNote{
        .note = 62, .channel = 0, .velocity = 80,
        .start_tick = 200, .duration = 240,
    };
    
    try std.testing.expect(compareNotesByStartTick({}, note1, note2));
    try std.testing.expect(!compareNotesByStartTick({}, note2, note1));
}

test "findMeasureForTick" {
    const allocator = std.testing.allocator;
    
    const time_sig = midi_parser.TimeSignatureEvent{
        .tick = 0, .numerator = 4, .denominator_power = 2,
        .clocks_per_metronome = 24, .thirtysecond_notes_per_quarter = 8,
    };
    
    var measure1 = Measure.init(allocator, 1, 0, 1920, time_sig);
    defer measure1.deinit();
    
    var measure2 = Measure.init(allocator, 2, 1920, 3840, time_sig);
    defer measure2.deinit();
    
    const measures = [_]Measure{ measure1, measure2 };
    
    // Test finding measures
    const found1 = MeasureBoundaryDetector.findMeasureForTick(&measures, 100);
    try std.testing.expect(found1 != null);
    try std.testing.expectEqual(@as(u32, 1), found1.?.number);
    
    const found2 = MeasureBoundaryDetector.findMeasureForTick(&measures, 2000);
    try std.testing.expect(found2 != null);
    try std.testing.expectEqual(@as(u32, 2), found2.?.number);
    
    const not_found = MeasureBoundaryDetector.findMeasureForTick(&measures, 5000);
    try std.testing.expect(not_found == null);
}

test "validateMeasures" {
    const allocator = std.testing.allocator;
    
    const time_sig = midi_parser.TimeSignatureEvent{
        .tick = 0, .numerator = 4, .denominator_power = 2,
        .clocks_per_metronome = 24, .thirtysecond_notes_per_quarter = 8,
    };
    
    var measure1 = Measure.init(allocator, 1, 0, 1920, time_sig);
    defer measure1.deinit();
    
    var measure2 = Measure.init(allocator, 2, 1920, 3840, time_sig);
    defer measure2.deinit();
    
    const valid_measures = [_]Measure{ measure1, measure2 };
    try std.testing.expect(MeasureBoundaryDetector.validateMeasures(&valid_measures));
    
    // Test invalid measures (gap between them)
    var invalid_measure2 = Measure.init(allocator, 2, 2000, 3840, time_sig);
    defer invalid_measure2.deinit();
    
    const invalid_measures = [_]Measure{ measure1, invalid_measure2 };
    try std.testing.expect(!MeasureBoundaryDetector.validateMeasures(&invalid_measures));
}

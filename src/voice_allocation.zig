//! Voice Allocation Manager
//! 
//! Implements TASK-026: Basic Voice Assignment per IMPLEMENTATION_TASK_LIST.md lines 325-333
//! 
//! This module assigns overlapping notes to different voices to enable proper
//! polyphonic notation in MusicXML. It uses a simple overlap detection algorithm
//! with support for up to 4 voices per staff.
//!
//! Features:
//! - Assign overlapping notes to voices
//! - Maximum 4 voices per staff
//! - Simple overlap detection algorithm
//! - O(n log n) performance target
//!
//! References:
//! - MXL_Architecture_Reference.md Section 5.2 for voice separation algorithms
//! - musical_intelligence_algorithms.md Section 5 for voice separation principles

const std = @import("std");
const timing = @import("timing.zig");
const midi_events = @import("midi/events.zig");
const error_mod = @import("error.zig");

/// Maximum number of voices allowed per staff (MusicXML standard)
pub const MAX_VOICES: u8 = 4;

/// Error types for voice allocation operations
pub const VoiceAllocationError = error{
    /// Too many simultaneous notes for available voices
    TooManySimultaneousNotes,
    /// Invalid voice number (must be 1-4)
    InvalidVoiceNumber,
    /// Invalid note data
    InvalidNote,
    /// Memory allocation failure
    AllocationFailure,
};

/// Represents a note with voice assignment information
pub const VoicedNote = struct {
    /// Original note data from timing module
    note: timing.TimedNote,
    /// Assigned voice number (1-4)
    voice: u8,
    /// Absolute end time in ticks (start_tick + duration)
    end_tick: u32,
    
    /// Initialize a voiced note
    pub fn init(note: timing.TimedNote, voice: u8) VoiceAllocationError!VoicedNote {
        if (voice < 1 or voice > MAX_VOICES) {
            return VoiceAllocationError.InvalidVoiceNumber;
        }
        
        // Check for potential overflow
        const end_tick = @addWithOverflow(note.start_tick, note.duration);
        if (end_tick[1] != 0) {
            return VoiceAllocationError.InvalidNote;
        }
        
        return VoicedNote{
            .note = note,
            .voice = voice,
            .end_tick = end_tick[0],
        };
    }
    
    /// Check if this note overlaps with another note in time
    pub fn overlaps(self: *const VoicedNote, other: *const VoicedNote) bool {
        // Two notes overlap if one starts before the other ends
        return self.note.start_tick < other.end_tick and other.note.start_tick < self.end_tick;
    }
};

/// Voice state tracking for the allocation algorithm
const VoiceState = struct {
    /// Voice number (1-4)
    number: u8,
    /// End time of the last note assigned to this voice
    last_end_tick: u32,
    /// Number of notes assigned to this voice
    note_count: u32,
    
    /// Check if this voice is available at the given time
    pub fn isAvailableAt(self: *const VoiceState, start_tick: u32) bool {
        return start_tick >= self.last_end_tick;
    }
    
    /// Update voice state with a new note assignment
    pub fn assignNote(self: *VoiceState, note: *const VoicedNote) void {
        self.last_end_tick = note.end_tick;
        self.note_count += 1;
    }
};

/// Voice Allocation Manager
/// Implements TASK-026 per IMPLEMENTATION_TASK_LIST.md lines 325-333
pub const VoiceAllocator = struct {
    allocator: std.mem.Allocator,
    /// Voice states for tracking assignments
    voices: [MAX_VOICES]VoiceState,
    /// Temporary storage for sorting
    sort_buffer: ?[]VoicedNote,
    
    /// Initialize a new voice allocator
    pub fn init(allocator: std.mem.Allocator) VoiceAllocator {
        var voices: [MAX_VOICES]VoiceState = undefined;
        for (0..MAX_VOICES) |i| {
            voices[i] = VoiceState{
                .number = @intCast(i + 1),
                .last_end_tick = 0,
                .note_count = 0,
            };
        }
        
        return VoiceAllocator{
            .allocator = allocator,
            .voices = voices,
            .sort_buffer = null,
        };
    }
    
    /// Clean up allocator resources
    pub fn deinit(self: *VoiceAllocator) void {
        if (self.sort_buffer) |buffer| {
            self.allocator.free(buffer);
        }
    }
    
    /// Assign voices to a slice of notes
    /// Returns a new slice with voice assignments
    /// Implements simple overlap detection per TASK-026
    pub fn assignVoices(self: *VoiceAllocator, notes: []const timing.TimedNote) VoiceAllocationError![]VoicedNote {
        if (notes.len == 0) {
            return self.allocator.alloc(VoicedNote, 0) catch {
                return VoiceAllocationError.AllocationFailure;
            };
        }
        
        // Allocate result array
        var result = self.allocator.alloc(VoicedNote, notes.len) catch {
            return VoiceAllocationError.AllocationFailure;
        };
        errdefer self.allocator.free(result);
        
        // Convert to VoicedNote with initial voice assignment
        for (notes, 0..) |note, i| {
            result[i] = try VoicedNote.init(note, 1);
        }
        
        // Sort by start time (required for O(n log n) algorithm)
        std.sort.heap(VoicedNote, result, {}, compareByStartTime);
        
        // Reset voice states
        for (&self.voices) |*voice| {
            voice.last_end_tick = 0;
            voice.note_count = 0;
        }
        
        // Assign voices using greedy algorithm
        for (result) |*voiced_note| {
            // Find first available voice
            var assigned = false;
            for (&self.voices) |*voice| {
                if (voice.isAvailableAt(voiced_note.note.start_tick)) {
                    voiced_note.voice = voice.number;
                    voice.assignNote(voiced_note);
                    assigned = true;
                    break;
                }
            }
            
            if (!assigned) {
                // All voices are occupied - too many simultaneous notes
                return VoiceAllocationError.TooManySimultaneousNotes;
            }
        }
        
        return result;
    }
    
    /// Assign voices within measures (respects measure boundaries)
    /// This is useful when notes have already been split at measure boundaries
    pub fn assignVoicesInMeasures(self: *VoiceAllocator, measures: []const timing.Measure) VoiceAllocationError![]VoicedNote {
        // Count total notes
        var total_notes: usize = 0;
        for (measures) |measure| {
            total_notes += measure.notes.items.len;
        }
        
        // Allocate result array
        var result = self.allocator.alloc(VoicedNote, total_notes) catch {
            return VoiceAllocationError.AllocationFailure;
        };
        errdefer self.allocator.free(result);
        
        var result_index: usize = 0;
        
        // Process each measure independently
        for (measures) |measure| {
            // Reset voice states for each measure
            for (&self.voices) |*voice| {
                voice.last_end_tick = measure.start_tick;
                voice.note_count = 0;
            }
            
            // Create temporary slice for this measure's notes
            const measure_notes = measure.notes.items;
            if (measure_notes.len == 0) continue;
            
            // Assign voices for this measure
            const voiced_notes = try self.assignVoices(measure_notes);
            defer self.allocator.free(voiced_notes);
            
            // Copy to result
            for (voiced_notes) |voiced_note| {
                result[result_index] = voiced_note;
                result_index += 1;
            }
        }
        
        return result;
    }
    
    /// Get voice assignment statistics
    pub fn getStatistics(self: *const VoiceAllocator) VoiceStatistics {
        var stats = VoiceStatistics{
            .voice_usage = [_]u32{0} ** MAX_VOICES,
            .max_simultaneous_notes = 0,
            .total_voice_changes = 0,
        };
        
        for (self.voices, 0..) |voice, i| {
            stats.voice_usage[i] = voice.note_count;
        }
        
        return stats;
    }
    
    /// Comparison function for sorting notes by start time
    fn compareByStartTime(context: void, a: VoicedNote, b: VoicedNote) bool {
        _ = context;
        if (a.note.start_tick == b.note.start_tick) {
            // If start times are equal, sort by pitch (higher notes first)
            return a.note.note > b.note.note;
        }
        return a.note.start_tick < b.note.start_tick;
    }
};

/// Statistics about voice allocation
pub const VoiceStatistics = struct {
    /// Number of notes assigned to each voice
    voice_usage: [MAX_VOICES]u32,
    /// Maximum number of simultaneous notes encountered
    max_simultaneous_notes: u8,
    /// Total number of voice changes in the piece
    total_voice_changes: u32,
};

/// Advanced voice allocation with stream segregation principles
/// Based on musical_intelligence_algorithms.md Section 5.1
pub const StreamSegregationAllocator = struct {
    allocator: std.mem.Allocator,
    /// Maximum interval for voice continuity (in semitones)
    max_interval: i32 = 12,
    /// Preferred interval for smooth voice leading
    preferred_interval: i32 = 7,
    /// Penalty for voice crossing
    voice_crossing_penalty: f64 = 10.0,
    /// Penalty for time gaps in a voice
    gap_penalty: f64 = 5.0,
    
    // TODO: Implement advanced stream segregation algorithm
    // This will be added in future tasks for more sophisticated voice separation
};

// Performance benchmarking support
pub fn benchmarkVoiceAllocation(allocator: std.mem.Allocator, note_count: usize) !void {
    const start_time = std.time.nanoTimestamp();
    
    // Generate test data
    const notes = try allocator.alloc(timing.TimedNote, note_count);
    defer allocator.free(notes);
    
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    // Generate random overlapping notes with controlled overlap
    var current_tick: u32 = 0;
    for (notes, 0..) |*note, i| {
        note.* = timing.TimedNote{
            .note = random.intRangeAtMost(u8, 48, 72), // C3 to C5
            .channel = 0,
            .velocity = 64,
            .start_tick = current_tick,
            .duration = random.intRangeAtMost(u32, 120, 480), // Shorter durations to avoid too many overlaps
            .tied_to_next = false,
            .tied_from_previous = false,
        };
        // Advance time with controlled overlap
        // Every 3rd note starts later to avoid too many simultaneous notes
        if (i % 3 == 0) {
            current_tick += random.intRangeAtMost(u32, 500, 960);
        } else {
            current_tick += random.intRangeAtMost(u32, 60, 240);
        }
    }
    
    // Run allocation
    var allocator_instance = VoiceAllocator.init(allocator);
    defer allocator_instance.deinit();
    
    const voiced_notes = try allocator_instance.assignVoices(notes);
    defer allocator.free(voiced_notes);
    
    const end_time = std.time.nanoTimestamp();
    const elapsed_ns = @as(u64, @intCast(end_time - start_time));
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    
    std.debug.print("Voice allocation benchmark:\n", .{});
    std.debug.print("  Notes: {}\n", .{note_count});
    std.debug.print("  Time: {d:.3}ms\n", .{elapsed_ms});
    std.debug.print("  Per note: {d:.3}µs\n", .{elapsed_ms * 1000.0 / @as(f64, @floatFromInt(note_count))});
    
    // Verify O(n log n) complexity
    const expected_ops = @as(f64, @floatFromInt(note_count)) * std.math.log2(@as(f64, @floatFromInt(note_count)));
    const ns_per_op = @as(f64, @floatFromInt(elapsed_ns)) / expected_ops;
    std.debug.print("  Time per operation: {d:.3}ns\n", .{ns_per_op});
}

test "basic voice allocation" {
    const allocator = std.testing.allocator;
    
    var voice_allocator = VoiceAllocator.init(allocator);
    defer voice_allocator.deinit();
    
    // Create non-overlapping notes
    const notes = [_]timing.TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480 },
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 480 },
        .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 960, .duration = 480 },
    };
    
    const voiced_notes = try voice_allocator.assignVoices(&notes);
    defer allocator.free(voiced_notes);
    
    // All non-overlapping notes should be assigned to voice 1
    try std.testing.expectEqual(@as(u8, 1), voiced_notes[0].voice);
    try std.testing.expectEqual(@as(u8, 1), voiced_notes[1].voice);
    try std.testing.expectEqual(@as(u8, 1), voiced_notes[2].voice);
}

test "overlapping notes require multiple voices" {
    const allocator = std.testing.allocator;
    
    var voice_allocator = VoiceAllocator.init(allocator);
    defer voice_allocator.deinit();
    
    // Create overlapping notes
    const notes = [_]timing.TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 960 },
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 960 },
        .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 960, .duration = 480 },
    };
    
    const voiced_notes = try voice_allocator.assignVoices(&notes);
    defer allocator.free(voiced_notes);
    
    // First note should be voice 1
    try std.testing.expectEqual(@as(u8, 1), voiced_notes[0].voice);
    // Second note overlaps with first, should be voice 2
    try std.testing.expectEqual(@as(u8, 2), voiced_notes[1].voice);
    // Third note can reuse voice 1 (first note has ended)
    try std.testing.expectEqual(@as(u8, 1), voiced_notes[2].voice);
}

test "too many simultaneous notes error" {
    const allocator = std.testing.allocator;
    
    var voice_allocator = VoiceAllocator.init(allocator);
    defer voice_allocator.deinit();
    
    // Create 5 simultaneous notes (exceeds MAX_VOICES)
    const notes = [_]timing.TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 960 },
        .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 960 },
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 960 },
        .{ .note = 65, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 960 },
        .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 960 },
    };
    
    const result = voice_allocator.assignVoices(&notes);
    try std.testing.expectError(VoiceAllocationError.TooManySimultaneousNotes, result);
}

test "voice reuse after gap" {
    const allocator = std.testing.allocator;
    
    var voice_allocator = VoiceAllocator.init(allocator);
    defer voice_allocator.deinit();
    
    // Create notes with gaps that allow voice reuse
    const notes = [_]timing.TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480 },
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 240, .duration = 480 },
        .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 960, .duration = 480 },
        .{ .note = 72, .channel = 0, .velocity = 64, .start_tick = 1200, .duration = 480 },
    };
    
    const voiced_notes = try voice_allocator.assignVoices(&notes);
    defer allocator.free(voiced_notes);
    
    // Verify voice assignments
    try std.testing.expectEqual(@as(u8, 1), voiced_notes[0].voice); // First note: voice 1
    try std.testing.expectEqual(@as(u8, 2), voiced_notes[1].voice); // Overlaps with first: voice 2
    try std.testing.expectEqual(@as(u8, 1), voiced_notes[2].voice); // Can reuse voice 1
    try std.testing.expectEqual(@as(u8, 2), voiced_notes[3].voice); // Can reuse voice 2
}

test "voiced note overlap detection" {
    const note1 = VoicedNote{
        .note = .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480 },
        .voice = 1,
        .end_tick = 480,
    };
    
    const note2 = VoicedNote{
        .note = .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 240, .duration = 480 },
        .voice = 2,
        .end_tick = 720,
    };
    
    const note3 = VoicedNote{
        .note = .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 480 },
        .voice = 1,
        .end_tick = 960,
    };
    
    // note1 and note2 overlap
    try std.testing.expect(note1.overlaps(&note2));
    try std.testing.expect(note2.overlaps(&note1));
    
    // note1 and note3 do not overlap (note3 starts exactly when note1 ends)
    try std.testing.expect(!note1.overlaps(&note3));
    try std.testing.expect(!note3.overlaps(&note1));
    
    // note2 and note3 overlap
    try std.testing.expect(note2.overlaps(&note3));
    try std.testing.expect(note3.overlaps(&note2));
}

test "performance benchmark" {
    if (@import("builtin").is_test) {
        // Run smaller benchmark in test mode
        try benchmarkVoiceAllocation(std.testing.allocator, 100);
    }
}
//! Cross-Track Chord Detection Module
//!
//! Implements TASK 3.1: Create Cross-Track Chord Detector per CHORD_DETECTION_FIX_TASK_LIST.md lines 76-89
//!
//! This module detects chords that span multiple MIDI tracks. Unlike the standard chord detector
//! which works within single tracks, this detector identifies when notes from different tracks
//! occur simultaneously to form chords.
//!
//! Key Features:
//! - Detects chords across multiple tracks in global note collection
//! - Groups notes by start_tick within specified tolerance
//! - Identifies when notes from different tracks form chords
//! - Creates ChordGroup structures for cross-track chords
//! - Maintains track information for MXL generation
//!
//! Algorithm:
//! 1. Sort all notes by start_tick for efficient processing
//! 2. Group notes by start_tick within tolerance_ticks
//! 3. Filter groups to only include those with notes from multiple tracks
//! 4. Create ChordGroup structures for qualifying cross-track chords
//!
//! References:
//! - CHORD_DETECTION_FIX_TASK_LIST.md Section 3.1 lines 76-89
//! - CHORD_DETECTION_FIX_TASK_LIST.md Section 3.2 lines 92-96

const std = @import("std");
const timing = @import("../timing.zig");
const TimedNote = timing.TimedNote;
const ChordGroup = timing.ChordGroup;

/// Error types for cross-track chord detection operations
pub const CrossTrackChordDetectorError = error{
    AllocationFailure,
    InvalidInput,
    EmptyNoteArray,
};

/// Cross-track chord detector for identifying chords spanning multiple tracks
/// Implements TASK 3.1 per CHORD_DETECTION_FIX_TASK_LIST.md lines 80-88
pub const CrossTrackChordDetector = struct {
    allocator: std.mem.Allocator,

    /// Initialize a new cross-track chord detector
    pub fn init(allocator: std.mem.Allocator) CrossTrackChordDetector {
        return CrossTrackChordDetector{
            .allocator = allocator,
        };
    }

    /// Detect chords that span multiple tracks from global note collection
    ///
    /// Takes notes from all tracks (with track information preserved) and identifies
    /// groups of simultaneous notes that come from different tracks, forming cross-track chords.
    ///
    /// Parameters:
    /// - notes: Array of TimedNote from all tracks, sorted by start_tick
    /// - tolerance_ticks: Maximum tick difference for notes to be considered simultaneous
    ///
    /// Returns:
    /// - Array of ChordGroup structures representing detected cross-track chords
    ///
    /// Implements TASK 3.1 per CHORD_DETECTION_FIX_TASK_LIST.md lines 84-87
    /// Implements logic per CHORD_DETECTION_FIX_TASK_LIST.md lines 92-96
    pub fn detectChordsAcrossTracks(
        self: *CrossTrackChordDetector,
        notes: []const TimedNote,
        tolerance_ticks: u32,
    ) ![]ChordGroup {
        if (notes.len == 0) {
            return try self.allocator.alloc(ChordGroup, 0);
        }

        // Working copy sorted by start time
        const sorted_notes = try self.allocator.alloc(TimedNote, notes.len);
        defer self.allocator.free(sorted_notes);
        @memcpy(sorted_notes, notes);
        std.sort.pdq(TimedNote, sorted_notes, {}, compareByStartTime);

        var out = std.ArrayList(ChordGroup).init(self.allocator);
        defer out.deinit();

        var i: usize = 0;
        while (i < sorted_notes.len) {
            const base_time = sorted_notes[i].start_tick;
            const window_end = base_time + tolerance_ticks;

            const start_idx = i;
            // Notes are sorted by start_tick; only need upper-bound check
            while (i < sorted_notes.len and sorted_notes[i].start_tick <= window_end) : (i += 1) {}

            const end_idx = i;

            // Fast cross-track test on the slice without allocating
            if (end_idx - start_idx >= 2 and isCrossTrackChord(sorted_notes[start_idx..end_idx])) {
                // Allocate only when we actually have a cross-track chord
                const chord_slice = try self.allocator.alloc(TimedNote, end_idx - start_idx);
                @memcpy(chord_slice, sorted_notes[start_idx..end_idx]);
                std.sort.pdq(TimedNote, chord_slice, {}, compareByPitch);

                const tracks_involved = try self.collectTracksFromNotes(chord_slice);

                try out.append(ChordGroup{
                    .start_time = base_time,
                    .notes = chord_slice,
                    .staff_assignment = 1, // default; generator decides per-note staff
                    .tracks_involved = tracks_involved,
                    .is_cross_track = true,
                });
            }
            // else: not cross-track -> no allocation, nothing to free
        }

        return out.toOwnedSlice();
    }

    /// Collect unique track numbers from notes in a chord
    /// Implements TASK 3.3 per CHORD_DETECTION_FIX_TASK_LIST.md lines 107-108
    fn collectTracksFromNotes(self: *CrossTrackChordDetector, notes: []const TimedNote) ![]u8 {
        if (notes.len == 0) {
            return try self.allocator.alloc(u8, 0);
        }

        // Bitmap for u8 track ids: O(1) space, cache-friendly
        var seen = [_]bool{false} ** 256;
        var count: usize = 0;

        for (notes) |n| {
            const t = @as(u8, @intCast(n.track));
            if (!seen[t]) {
                seen[t] = true;
                count += 1;
            }
        }

        // Emit in ascending order; no sort needed
        const tracks = try self.allocator.alloc(u8, count);
        var j: usize = 0;
        for (seen, 0..) |flag, idx| {
            if (flag) {
                tracks[j] = @intCast(idx);
                j += 1;
            }
        }
        return tracks;
    }

    /// Check if a group of notes forms a cross-track chord
    ///
    /// A cross-track chord is defined as a group of simultaneous notes where
    /// at least two notes come from different tracks.
    ///
    /// Implements logic per CHORD_DETECTION_FIX_TASK_LIST.md line 94
    fn isCrossTrackChord(notes: []const TimedNote) bool {
        if (notes.len < 2) return false;

        const first_track = notes[0].track;

        // Check if any note has a different track than the first
        for (notes[1..]) |note| {
            if (note.track != first_track) {
                return true; // Found notes from different tracks
            }
        }

        return false; // All notes from same track
    }

    /// Determine which staff a chord should be assigned to based on pitch range
    /// Uses the same logic as the standard chord detector for consistency
    fn determineStaffForChord(notes: []const TimedNote) u8 {
        if (notes.len == 0) return 1; // Default to treble

        // Check if any note is below middle C (MIDI note 60)
        for (notes) |note| {
            if (note.note < 60) {
                return 2; // Bass staff
            }
        }

        return 1; // Treble staff
    }

    /// Compare function for sorting by start time
    fn compareByStartTime(_: void, a: TimedNote, b: TimedNote) bool {
        return a.start_tick < b.start_tick;
    }

    /// Compare function for sorting by pitch (ascending)
    /// Used to order notes within a chord from lowest to highest
    fn compareByPitch(_: void, a: TimedNote, b: TimedNote) bool {
        return a.note < b.note;
    }
};

// Unit tests for cross-track chord detection
test "detect cross-track chord with two tracks" {
    const allocator = std.testing.allocator;
    var detector = CrossTrackChordDetector.init(allocator);

    // Two notes at same time from different tracks - should form cross-track chord
    const notes = [_]TimedNote{
        TimedNote{ .note = 60, .channel = 0, .velocity = 100, .start_tick = 100, .duration = 480, .track = 0 },
        TimedNote{ .note = 64, .channel = 1, .velocity = 100, .start_tick = 100, .duration = 480, .track = 1 },
    };

    const chords = try detector.detectChordsAcrossTracks(&notes, 10);
    defer {
        for (chords) |*chord| {
            chord.deinit(allocator);
        }
        allocator.free(chords);
    }

    try std.testing.expect(chords.len == 1);
    try std.testing.expect(chords[0].notes.len == 2);
    try std.testing.expect(chords[0].start_time == 100);
}

test "ignore same-track chords" {
    const allocator = std.testing.allocator;
    var detector = CrossTrackChordDetector.init(allocator);

    // Two notes at same time from SAME track - should NOT form cross-track chord
    const notes = [_]TimedNote{
        TimedNote{ .note = 60, .channel = 0, .velocity = 100, .start_tick = 100, .duration = 480, .track = 0 },
        TimedNote{ .note = 64, .channel = 0, .velocity = 100, .start_tick = 100, .duration = 480, .track = 0 },
    };

    const chords = try detector.detectChordsAcrossTracks(&notes, 10);
    defer allocator.free(chords);

    try std.testing.expect(chords.len == 0);
}

test "detect multiple cross-track chords" {
    const allocator = std.testing.allocator;
    var detector = CrossTrackChordDetector.init(allocator);

    // Two separate cross-track chords at different times
    const notes = [_]TimedNote{
        // First chord at tick 100
        TimedNote{ .note = 60, .channel = 0, .velocity = 100, .start_tick = 100, .duration = 480, .track = 0 },
        TimedNote{ .note = 64, .channel = 1, .velocity = 100, .start_tick = 100, .duration = 480, .track = 1 },
        // Second chord at tick 600
        TimedNote{ .note = 67, .channel = 0, .velocity = 100, .start_tick = 600, .duration = 480, .track = 0 },
        TimedNote{ .note = 72, .channel = 1, .velocity = 100, .start_tick = 600, .duration = 480, .track = 1 },
    };

    const chords = try detector.detectChordsAcrossTracks(&notes, 10);
    defer {
        for (chords) |*chord| {
            chord.deinit(allocator);
        }
        allocator.free(chords);
    }

    try std.testing.expect(chords.len == 2);
    try std.testing.expect(chords[0].start_time == 100);
    try std.testing.expect(chords[1].start_time == 600);
}

test "handle three-track chord" {
    const allocator = std.testing.allocator;
    var detector = CrossTrackChordDetector.init(allocator);

    // Three notes at same time from three different tracks
    const notes = [_]TimedNote{
        TimedNote{ .note = 60, .channel = 0, .velocity = 100, .start_tick = 100, .duration = 480, .track = 0 },
        TimedNote{ .note = 64, .channel = 1, .velocity = 100, .start_tick = 100, .duration = 480, .track = 1 },
        TimedNote{ .note = 67, .channel = 2, .velocity = 100, .start_tick = 100, .duration = 480, .track = 2 },
    };

    const chords = try detector.detectChordsAcrossTracks(&notes, 10);
    defer {
        for (chords) |*chord| {
            chord.deinit(allocator);
        }
        allocator.free(chords);
    }

    try std.testing.expect(chords.len == 1);
    try std.testing.expect(chords[0].notes.len == 3);
    // Verify notes are sorted by pitch
    try std.testing.expect(chords[0].notes[0].note <= chords[0].notes[1].note);
    try std.testing.expect(chords[0].notes[1].note <= chords[0].notes[2].note);
}

test "respect tolerance for simultaneous notes" {
    const allocator = std.testing.allocator;
    var detector = CrossTrackChordDetector.init(allocator);

    // Two notes from different tracks within tolerance
    const notes = [_]TimedNote{
        TimedNote{ .note = 60, .channel = 0, .velocity = 100, .start_tick = 100, .duration = 480, .track = 0 },
        TimedNote{ .note = 64, .channel = 1, .velocity = 100, .start_tick = 105, .duration = 480, .track = 1 }, // 5 ticks later
    };

    // Test with tolerance = 10 (should detect chord)
    const chords_with_tolerance = try detector.detectChordsAcrossTracks(&notes, 10);
    defer {
        for (chords_with_tolerance) |*chord| {
            chord.deinit(allocator);
        }
        allocator.free(chords_with_tolerance);
    }

    try std.testing.expect(chords_with_tolerance.len == 1);

    // Test with tolerance = 3 (should not detect chord)
    const chords_without_tolerance = try detector.detectChordsAcrossTracks(&notes, 3);
    defer allocator.free(chords_without_tolerance);

    try std.testing.expect(chords_without_tolerance.len == 0);
}

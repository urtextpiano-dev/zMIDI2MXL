//! Chord Detection Module
//! 
//! Implements TASK 3.1: Simultaneous Note Detection per INCREMENTAL_IMPLEMENTATION_TASK_LIST.md lines 268-341
//! 
//! This module detects simultaneous notes (chords) in MIDI data by grouping notes
//! that start within a specified tolerance. This is essential for proper MusicXML
//! chord notation where simultaneous notes must be marked with <chord/> elements.
//!
//! References:
//! - INCREMENTAL_IMPLEMENTATION_TASK_LIST.md Section 3.1 lines 268-341
//! - MusicXML 4.0 specification for chord notation

const std = @import("std");
const containers = @import("../utils/containers.zig");
const timing = @import("../timing.zig");
const TimedNote = timing.TimedNote;
const t = @import("../test_utils.zig");

/// Error types for chord detection operations
pub const ChordDetectorError = error{
    AllocationFailure,
    InvalidInput,
    EmptyChord,
};

/// Represents a group of simultaneous notes (a chord)
/// Implements TASK 3.1 per INCREMENTAL_IMPLEMENTATION_TASK_LIST.md lines 286-292
/// Extended for TASK 3.3 per CHORD_DETECTION_FIX_TASK_LIST.md lines 98-111 
pub const ChordGroup = struct {
    /// Start time of the chord (earliest note start time)
    start_time: u32,
    /// Array of notes that form this chord
    notes: []TimedNote,
    /// Staff assignment (1 = treble, 2 = bass)
    staff_assignment: u8,
    /// NEW: Track information per TASK 3.3
    /// Which tracks contribute to this chord
    tracks_involved: []u8,
    /// Flag for cross-track chords
    is_cross_track: bool,
    
    /// Clean up chord group resources
    /// Updated for TASK 3.3 to handle tracks_involved array
    pub fn deinit(self: *ChordGroup, allocator: std.mem.Allocator) void {
        allocator.free(self.notes);
        allocator.free(self.tracks_involved);
    }
};

/// Chord detector for grouping simultaneous notes
pub const ChordDetector = struct {
    allocator: std.mem.Allocator,
    
    /// Initialize a new chord detector
    pub fn init(allocator: std.mem.Allocator) ChordDetector {
        return ChordDetector{
            .allocator = allocator,
        };
    }
    
    /// Detect chords in an array of timed notes
    /// 
    /// Groups notes that start within `tolerance_ticks` of each other as chords.
    /// Notes within a chord are sorted by pitch for proper chord notation order.
    /// 
    /// Implements TASK 3.1 per INCREMENTAL_IMPLEMENTATION_TASK_LIST.md lines 294-322
    pub fn detectChords(
        self: *ChordDetector,
        notes: []const TimedNote,
        tolerance_ticks: u32,
    ) ![]ChordGroup {
        if (notes.len == 0) {
            return self.allocator.alloc(ChordGroup, 0);
        }
        
        // First, create a working copy and sort by start time
        const sorted_notes = try self.allocator.alloc(TimedNote, notes.len);
        defer self.allocator.free(sorted_notes);
        @memcpy(sorted_notes, notes);
        
        // Sort notes by start time for efficient grouping
        std.sort.pdq(TimedNote, sorted_notes, {}, compareByStartTime);
        
        // Temporary storage for chord groups
        var groups = containers.List(ChordGroup).init(self.allocator);
        defer groups.deinit();
        
        // Process notes and group simultaneous ones
        var i: usize = 0;
        while (i < sorted_notes.len) {
            var chord_notes = containers.List(TimedNote).init(self.allocator);
            errdefer chord_notes.deinit();
            
            const base_time = sorted_notes[i].start_tick;
            
            // Collect all notes within tolerance of base_time
            while (i < sorted_notes.len) {
                const note_time = sorted_notes[i].start_tick;
                // Check if within tolerance (handle both directions)
                if (note_time >= base_time and note_time <= base_time + tolerance_ticks) {
                    try chord_notes.append(sorted_notes[i]);
                    i += 1;
                } else {
                    break;
                }
            }
            
            // Sort chord notes by pitch for proper notation order
            const chord_slice = try chord_notes.toOwnedSlice();
            std.sort.pdq(TimedNote, chord_slice, {}, compareByPitch);
            
            // Determine staff assignment for the chord
            const staff = determineStaffForChord(chord_slice);
            
            // Collect tracks involved in this chord (TASK 3.3)
            const tracks_involved = try self.collectTracksFromNotes(chord_slice);
            
            try groups.append(ChordGroup{
                .start_time = base_time,
                .notes = chord_slice,
                .staff_assignment = staff,
                .tracks_involved = tracks_involved,
                .is_cross_track = false, // Regular chord detector creates single-track chords
            });
        }
        
        return groups.toOwnedSlice();
    }
    
    /// Collect unique track numbers from notes in a chord
    /// Implements TASK 3.3 per CHORD_DETECTION_FIX_TASK_LIST.md lines 107-108
    fn collectTracksFromNotes(self: *ChordDetector, notes: []const TimedNote) ![]u8 {
        if (notes.len == 0) {
            return self.allocator.alloc(u8, 0);
        }
        
        // Use a temporary set to collect unique tracks
        var track_set = containers.AutoMap(u8, void).init(self.allocator);
        defer track_set.deinit();
        
        // Collect unique track numbers
        for (notes) |note| {
            try track_set.put(note.track, {});
        }
        
        // Convert to array
        const tracks = try self.allocator.alloc(u8, track_set.count());
        var i: usize = 0;
        var iterator = track_set.iterator();
        while (iterator.next()) |entry| {
            tracks[i] = entry.key_ptr.*;
            i += 1;
        }
        
        // Sort tracks for consistent ordering
        std.sort.pdq(u8, tracks, {}, std.sort.asc(u8));
        
        return tracks;
    }
    
    /// Determine which staff a chord should be assigned to based on pitch range
    /// Implements TASK 3.1 per INCREMENTAL_IMPLEMENTATION_TASK_LIST.md lines 429-444
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
    fn compareByStartTime(context: void, a: TimedNote, b: TimedNote) bool {
        _ = context;
        return a.start_tick < b.start_tick;
    }
    
    /// Compare function for sorting by pitch (MIDI note number)
    fn compareByPitch(context: void, a: TimedNote, b: TimedNote) bool {
        _ = context;
        return a.note < b.note;
    }
};

// Unit tests for chord detection
test "detect single notes as individual chords" {
    const allocator = std.testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    // Three notes far apart in time
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 67, .channel = 0, .velocity = 80, .start_tick = 960, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
    };
    
    const chord_groups = try detector.detectChords(&notes, 10);
    defer {
        for (chord_groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(chord_groups);
    }
    
    // Should create 3 separate chord groups
    try t.expectEq(3, chord_groups.len);
    
    // Each group should have one note
    for (chord_groups) |group| {
        try t.expectEq(1, group.notes.len);
    }
}

test "detect simultaneous notes as chord" {
    const allocator = std.testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    // C major chord - all notes at same time
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false }, // C
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false }, // E
        .{ .note = 67, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false }, // G
    };
    
    const chord_groups = try detector.detectChords(&notes, 10);
    defer {
        for (chord_groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(chord_groups);
    }
    
    // Should create 1 chord group
    try t.expectEq(1, chord_groups.len);
    
    // The group should have 3 notes
    try t.expectEq(3, chord_groups[0].notes.len);
    
    // Notes should be sorted by pitch
    try t.expectEq(60, chord_groups[0].notes[0].note);
    try t.expectEq(64, chord_groups[0].notes[1].note);
    try t.expectEq(67, chord_groups[0].notes[2].note);
}

test "detect notes within tolerance as chord" {
    const allocator = std.testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    // Notes slightly offset but within tolerance
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 5, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 67, .channel = 0, .velocity = 80, .start_tick = 10, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
    };
    
    const chord_groups = try detector.detectChords(&notes, 20); // Tolerance of 20 ticks
    defer {
        for (chord_groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(chord_groups);
    }
    
    // Should create 1 chord group
    try t.expectEq(1, chord_groups.len);
    try t.expectEq(3, chord_groups[0].notes.len);
}

test "staff assignment for bass notes" {
    const allocator = std.testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    // Low C chord (below middle C)
    const notes = [_]TimedNote{
        .{ .note = 36, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false }, // C2
        .{ .note = 40, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false }, // E2
        .{ .note = 43, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false }, // G2
    };
    
    const chord_groups = try detector.detectChords(&notes, 10);
    defer {
        for (chord_groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(chord_groups);
    }
    
    // Should assign to bass staff (2)
    try t.expectEq(2, chord_groups[0].staff_assignment);
}

test "complex chord pattern" {
    const allocator = std.testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    // Two chords and a single note
    const notes = [_]TimedNote{
        // First chord at tick 0
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 67, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
        // Single note at tick 480
        .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 240, .tied_to_next = false, .tied_from_previous = false },
        // Second chord at tick 960
        .{ .note = 65, .channel = 0, .velocity = 80, .start_tick = 960, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 69, .channel = 0, .velocity = 80, .start_tick = 960, .duration = 480, .tied_to_next = false, .tied_from_previous = false },
    };
    
    const chord_groups = try detector.detectChords(&notes, 10);
    defer {
        for (chord_groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(chord_groups);
    }
    
    // Should create 3 chord groups
    try t.expectEq(3, chord_groups.len);
    
    // First group: 3 notes
    try t.expectEq(3, chord_groups[0].notes.len);
    
    // Second group: 1 note
    try t.expectEq(1, chord_groups[1].notes.len);
    
    // Third group: 2 notes
    try t.expectEq(2, chord_groups[2].notes.len);
}

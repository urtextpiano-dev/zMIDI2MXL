const std = @import("std");
const testing = std.testing;

// =============================================================================
// DEPENDENCIES - Minimal types needed for detectChords function
// =============================================================================

/// Represents a musical note with timing information
pub const TimedNote = struct {
    note: u8,           // MIDI note number (0-127)
    channel: u8,        // MIDI channel (0-15)
    velocity: u8,       // MIDI velocity (0-127)
    start_tick: u32,    // Start time in MIDI ticks
    duration: u32,      // Duration in MIDI ticks
    tied_to_next: bool = false,
    tied_from_previous: bool = false,
    track: u8 = 0,      // Track index (0-based)
    voice: u8 = 0,      // Voice number
};

/// Represents a group of notes that form a chord
pub const ChordGroup = struct {
    start_time: u32,             // Start time of the chord
    notes: []TimedNote,          // Array of notes forming the chord
    staff_assignment: u8,        // Staff assignment (1=treble, 2=bass)
    tracks_involved: []u8,       // Which tracks contribute to this chord
    is_cross_track: bool,        // Flag for cross-track chords
    
    pub fn deinit(self: *ChordGroup, allocator: std.mem.Allocator) void {
        allocator.free(self.notes);
        allocator.free(self.tracks_involved);
    }
};

/// Chord detector for grouping simultaneous notes
pub const ChordDetector = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ChordDetector {
        return ChordDetector{ .allocator = allocator };
    }
    
    // =============================================================================
    // ORIGINAL FUNCTION - To be analyzed for simplification
    // =============================================================================
    
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
        var groups = std.ArrayList(ChordGroup).init(self.allocator);
        defer groups.deinit();
        
        // Process notes and group simultaneous ones
        var i: usize = 0;
        while (i < sorted_notes.len) {
            const base_time = sorted_notes[i].start_tick;
            const start_idx = i;
            
            // Find end of chord group (notes within tolerance)
            while (i < sorted_notes.len and sorted_notes[i].start_tick <= base_time + tolerance_ticks) {
                i += 1;
            }
            
            // Create chord from range [start_idx, i)
            const chord_len = i - start_idx;
            const chord_slice = try self.allocator.alloc(TimedNote, chord_len);
            @memcpy(chord_slice, sorted_notes[start_idx..i]);
            
            // Sort chord notes by pitch for proper notation order
            std.sort.pdq(TimedNote, chord_slice, {}, compareByPitch);
            
            // Determine staff assignment for the chord
            const staff = determineStaffForChord(chord_slice);
            
            // Collect tracks involved in this chord
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
    
    // Helper functions - SIMPLIFIED VERSION
    fn collectTracksFromNotes(self: *ChordDetector, notes: []const TimedNote) ![]u8 {
        if (notes.len == 0) {
            return self.allocator.alloc(u8, 0);
        }
        
        // Use a simple array for track collection (max 256 possible tracks)
        var track_seen = [_]bool{false} ** 256;
        var unique_count: usize = 0;
        
        // Mark tracks as seen and count uniques
        for (notes) |note| {
            if (!track_seen[note.track]) {
                track_seen[note.track] = true;
                unique_count += 1;
            }
        }
        
        // Collect unique tracks into result array
        var tracks = try self.allocator.alloc(u8, unique_count);
        var idx: usize = 0;
        for (track_seen, 0..) |seen, track_num| {
            if (seen) {
                tracks[idx] = @intCast(track_num);
                idx += 1;
            }
        }
        
        return tracks;
    }
    
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
    
    fn compareByStartTime(context: void, a: TimedNote, b: TimedNote) bool {
        _ = context;
        return a.start_tick < b.start_tick;
    }
    
    fn compareByPitch(context: void, a: TimedNote, b: TimedNote) bool {
        _ = context;
        return a.note < b.note;
    }
};

// =============================================================================
// TEST SUITE - Comprehensive tests for function validation
// =============================================================================

test "detect empty notes returns empty array" {
    const allocator = testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    const notes: []const TimedNote = &[_]TimedNote{};
    const result = try detector.detectChords(notes, 0);
    defer allocator.free(result);
    
    try testing.expectEqual(@as(usize, 0), result.len);
}

test "detect single note creates single chord" {
    const allocator = testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
    };
    
    const result = try detector.detectChords(&notes, 0);
    defer {
        for (result) |*chord| {
            chord.deinit(allocator);
        }
        allocator.free(result);
    }
    
    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(@as(u32, 0), result[0].start_time);
    try testing.expectEqual(@as(usize, 1), result[0].notes.len);
    try testing.expectEqual(@as(u8, 60), result[0].notes[0].note);
    try testing.expectEqual(@as(u8, 1), result[0].staff_assignment); // Treble staff for middle C
}

test "detect simultaneous notes as chord" {
    const allocator = testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    // C major chord: C4, E4, G4 (all starting at tick 0)
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
        .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
    };
    
    const result = try detector.detectChords(&notes, 0);
    defer {
        for (result) |*chord| {
            chord.deinit(allocator);
        }
        allocator.free(result);
    }
    
    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(@as(usize, 3), result[0].notes.len);
    // Notes should be sorted by pitch
    try testing.expectEqual(@as(u8, 60), result[0].notes[0].note);
    try testing.expectEqual(@as(u8, 64), result[0].notes[1].note);
    try testing.expectEqual(@as(u8, 67), result[0].notes[2].note);
}

test "detect notes within tolerance as chord" {
    const allocator = testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    // Notes within 10 tick tolerance
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 5, .duration = 475, .track = 0, .voice = 1 },
        .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 10, .duration = 470, .track = 0, .voice = 1 },
    };
    
    const result = try detector.detectChords(&notes, 10);
    defer {
        for (result) |*chord| {
            chord.deinit(allocator);
        }
        allocator.free(result);
    }
    
    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(@as(usize, 3), result[0].notes.len);
}

test "detect sequential notes as separate chords" {
    const allocator = testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    // Notes that are clearly sequential (100 ticks apart)
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
        .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 100, .duration = 480, .track = 0, .voice = 1 },
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 200, .duration = 480, .track = 0, .voice = 1 },
    };
    
    const result = try detector.detectChords(&notes, 10);
    defer {
        for (result) |*chord| {
            chord.deinit(allocator);
        }
        allocator.free(result);
    }
    
    try testing.expectEqual(@as(usize, 3), result.len);
    try testing.expectEqual(@as(u32, 0), result[0].start_time);
    try testing.expectEqual(@as(u32, 100), result[1].start_time);
    try testing.expectEqual(@as(u32, 200), result[2].start_time);
}

test "detect bass notes assigned to bass staff" {
    const allocator = testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    // Low notes (below middle C)
    const notes = [_]TimedNote{
        .{ .note = 48, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 5 }, // C3
        .{ .note = 52, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 5 }, // E3
        .{ .note = 55, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 5 }, // G3
    };
    
    const result = try detector.detectChords(&notes, 0);
    defer {
        for (result) |*chord| {
            chord.deinit(allocator);
        }
        allocator.free(result);
    }
    
    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(@as(u8, 2), result[0].staff_assignment); // Bass staff
}

test "detect multi-track chord properly" {
    const allocator = testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    // Notes from different tracks
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
        .{ .note = 64, .channel = 1, .velocity = 64, .start_tick = 0, .duration = 480, .track = 1, .voice = 2 },
        .{ .note = 67, .channel = 2, .velocity = 64, .start_tick = 0, .duration = 480, .track = 2, .voice = 3 },
    };
    
    const result = try detector.detectChords(&notes, 0);
    defer {
        for (result) |*chord| {
            chord.deinit(allocator);
        }
        allocator.free(result);
    }
    
    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqual(@as(usize, 3), result[0].notes.len);
    try testing.expectEqual(@as(usize, 3), result[0].tracks_involved.len);
    try testing.expectEqual(false, result[0].is_cross_track);
}

test "detect handles unsorted input" {
    const allocator = testing.allocator;
    var detector = ChordDetector.init(allocator);
    
    // Notes in random order (by time and pitch)
    const notes = [_]TimedNote{
        .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 200, .duration = 480, .track = 0, .voice = 1 },
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
        .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 100, .duration = 480, .track = 0, .voice = 1 },
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
    };
    
    const result = try detector.detectChords(&notes, 0);
    defer {
        for (result) |*chord| {
            chord.deinit(allocator);
        }
        allocator.free(result);
    }
    
    // Should create 3 chord groups: [60,64] at 0, [62] at 100, [67] at 200
    try testing.expectEqual(@as(usize, 3), result.len);
    try testing.expectEqual(@as(u32, 0), result[0].start_time);
    try testing.expectEqual(@as(usize, 2), result[0].notes.len);
    try testing.expectEqual(@as(u32, 100), result[1].start_time);
    try testing.expectEqual(@as(u32, 200), result[2].start_time);
}

// =============================================================================
// MAIN TEST RUNNER
// =============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Testing detectChords function...\n", .{});
    std.debug.print("================================\n\n", .{});
    
    // Test 1: Empty input
    {
        std.debug.print("Test 1: Empty input\n", .{});
        var detector = ChordDetector.init(allocator);
        const notes: []const TimedNote = &[_]TimedNote{};
        const result = try detector.detectChords(notes, 0);
        defer allocator.free(result);
        std.debug.print("  Result: {} chord groups (expected: 0)\n\n", .{result.len});
    }
    
    // Test 2: Single note
    {
        std.debug.print("Test 2: Single note\n", .{});
        var detector = ChordDetector.init(allocator);
        const notes = [_]TimedNote{
            .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
        };
        const result = try detector.detectChords(&notes, 0);
        defer {
            for (result) |*chord| {
                chord.deinit(allocator);
            }
            allocator.free(result);
        }
        std.debug.print("  Result: {} chord groups with {} notes\n", .{ result.len, result[0].notes.len });
        std.debug.print("  Staff assignment: {} (1=treble, 2=bass)\n\n", .{result[0].staff_assignment});
    }
    
    // Test 3: Simultaneous notes (chord)
    {
        std.debug.print("Test 3: C major chord (simultaneous)\n", .{});
        var detector = ChordDetector.init(allocator);
        const notes = [_]TimedNote{
            .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
            .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
            .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
        };
        const result = try detector.detectChords(&notes, 0);
        defer {
            for (result) |*chord| {
                chord.deinit(allocator);
            }
            allocator.free(result);
        }
        std.debug.print("  Result: {} chord groups with {} notes\n", .{ result.len, result[0].notes.len });
        std.debug.print("  Notes (sorted by pitch): ", .{});
        for (result[0].notes) |note| {
            std.debug.print("{} ", .{note.note});
        }
        std.debug.print("\n\n", .{});
    }
    
    // Test 4: Notes within tolerance
    {
        std.debug.print("Test 4: Notes within tolerance (10 ticks)\n", .{});
        var detector = ChordDetector.init(allocator);
        const notes = [_]TimedNote{
            .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
            .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 5, .duration = 475, .track = 0, .voice = 1 },
            .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 10, .duration = 470, .track = 0, .voice = 1 },
        };
        const result = try detector.detectChords(&notes, 10);
        defer {
            for (result) |*chord| {
                chord.deinit(allocator);
            }
            allocator.free(result);
        }
        std.debug.print("  Result: {} chord groups with {} notes\n", .{ result.len, result[0].notes.len });
        std.debug.print("  Start times: ", .{});
        for (result[0].notes) |note| {
            std.debug.print("{} ", .{note.start_tick});
        }
        std.debug.print("\n\n", .{});
    }
    
    // Test 5: Sequential notes
    {
        std.debug.print("Test 5: Sequential notes (100 ticks apart)\n", .{});
        var detector = ChordDetector.init(allocator);
        const notes = [_]TimedNote{
            .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 1 },
            .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 100, .duration = 480, .track = 0, .voice = 1 },
            .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 200, .duration = 480, .track = 0, .voice = 1 },
        };
        const result = try detector.detectChords(&notes, 10);
        defer {
            for (result) |*chord| {
                chord.deinit(allocator);
            }
            allocator.free(result);
        }
        std.debug.print("  Result: {} separate chord groups\n", .{result.len});
        for (result, 0..) |chord, i| {
            std.debug.print("    Group {}: start_time={}, notes={}\n", .{ i + 1, chord.start_time, chord.notes.len });
        }
        std.debug.print("\n", .{});
    }
    
    // Test 6: Bass staff assignment
    {
        std.debug.print("Test 6: Bass staff assignment (notes below middle C)\n", .{});
        var detector = ChordDetector.init(allocator);
        const notes = [_]TimedNote{
            .{ .note = 48, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 5 },
            .{ .note = 52, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 5 },
            .{ .note = 55, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480, .track = 0, .voice = 5 },
        };
        const result = try detector.detectChords(&notes, 0);
        defer {
            for (result) |*chord| {
                chord.deinit(allocator);
            }
            allocator.free(result);
        }
        std.debug.print("  Result: Staff assignment = {} (expected: 2 for bass)\n", .{result[0].staff_assignment});
        std.debug.print("  Note pitches: ", .{});
        for (result[0].notes) |note| {
            std.debug.print("{} ", .{note.note});
        }
        std.debug.print("\n\n", .{});
    }
    
    std.debug.print("All tests completed successfully!\n", .{});
}
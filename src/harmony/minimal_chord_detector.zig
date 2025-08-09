const std = @import("std");
const TimedNote = @import("../timing.zig").TimedNote;

/// Minimal chord detector - EXACT timing only (CDR-2.2) with CDR-2.5 optimizations
pub const MinimalChordDetector = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MinimalChordDetector {
        return .{ .allocator = allocator };
    }

    pub fn detectChords(self: *MinimalChordDetector, notes: []const TimedNote) ![]ChordGroup {
        if (notes.len == 0) return self.allocator.alloc(ChordGroup, 0);

        // Check if already sorted (common case from pipeline)
        var is_sorted = true;
        for (1..notes.len) |i| {
            if (notes[i].start_tick < notes[i - 1].start_tick) {
                is_sorted = false;
                break;
            }
        }

        // Only copy and sort if necessary
        const sorted = if (is_sorted) notes else blk: {
            const copy = try self.allocator.alloc(TimedNote, notes.len);
            @memcpy(copy, notes);
            std.sort.pdq(TimedNote, copy, {}, compareByStartTick);
            break :blk copy;
        };
        defer if (!is_sorted) self.allocator.free(sorted);

        // Pre-allocate groups array with estimated size
        var groups = try std.ArrayList(ChordGroup).initCapacity(self.allocator, notes.len / 2);
        defer groups.deinit();

        var i: usize = 0;
        while (i < sorted.len) {
            const base_tick = sorted[i].start_tick;
            const start_idx = i;

            // Advance to end of this tick's run; slice directly [start_idx..i]
            while (i < sorted.len and sorted[i].start_tick == base_tick) : (i += 1) {}
            const chord_slice = sorted[start_idx..i];

            if (validateChordGroupFast(chord_slice)) {
                // Valid chord (including single notes): copy + sort by pitch
                const owned = try self.allocator.alloc(TimedNote, chord_slice.len);
                @memcpy(owned, chord_slice);
                std.sort.pdq(TimedNote, owned, {}, compareByPitch);

                const tracks = try collectTracksFast(self.allocator, owned);

                // Preserve old single-note staff rule; use determineStaff for multi-note groups
                const staff: u8 =
                    if (owned.len == 1)
                        (if (owned[0].note < 60) @as(u8, 2) else @as(u8, 1))
                    else
                        determineStaff(owned);

                try groups.append(ChordGroup{
                    .start_time = base_tick,
                    .notes = owned,
                    .staff_assignment = staff,
                    .tracks_involved = tracks,
                    .is_cross_track = tracks.len > 1,
                });
            } else {
                // Fail-safe: create individual note groups
                for (chord_slice) |note| {
                    const single = try self.allocator.alloc(TimedNote, 1);
                    single[0] = note;

                    const tracks = try self.allocator.alloc(u8, 1);
                    tracks[0] = note.track;

                    try groups.append(ChordGroup{
                        .start_time = note.start_tick,
                        .notes = single,
                        .staff_assignment = if (note.note < 60) 2 else 1,
                        .tracks_involved = tracks,
                        .is_cross_track = false,
                    });
                }
            }
        }

        return groups.toOwnedSlice();
    }

    fn validateChordGroupFast(notes: []const TimedNote) bool {
        if (notes.len == 1) return true;
        if (notes.len > 8) return false;

        // Use stack array for small pitch sets (max 8 notes)
        var pitch_seen = [_]bool{false} ** 128;
        var min_p: u8 = 127;
        var max_p: u8 = 0;

        for (notes) |n| {
            if (pitch_seen[n.note]) return false; // Duplicate
            pitch_seen[n.note] = true;
            min_p = @min(min_p, n.note);
            max_p = @max(max_p, n.note);
        }

        return (max_p - min_p) <= 24;
    }

    fn compareByStartTick(_: void, a: TimedNote, b: TimedNote) bool {
        return a.start_tick < b.start_tick;
    }
    fn compareByPitch(_: void, a: TimedNote, b: TimedNote) bool {
        return a.note < b.note;
    }

    fn determineStaff(notes: []const TimedNote) u8 {
        for (notes) |n| if (n.note < 60) return 2;
        return 1;
    }

    fn collectTracksFast(allocator: std.mem.Allocator, notes: []const TimedNote) ![]u8 {
        // Use a 16-bit mask for tracks 0..15
        var mask: u16 = 0;
        const Shift = std.math.Log2Int(u16);

        for (notes) |n| {
            if (n.track < 16) {
                mask |= @as(u16, 1) << @as(Shift, @intCast(n.track));
            }
        }

        const count = @popCount(mask);
        const tracks = try allocator.alloc(u8, count);

        var idx: usize = 0;
        var t: u4 = 0;
        while (t < 16) : (t += 1) {
            if (((mask >> t) & 1) == 1) {
                tracks[idx] = @intCast(t); // context gives u8
                idx += 1;
            }
        }
        return tracks;
    }
};

// Use existing ChordGroup from chord_detector.zig for compatibility
pub const ChordGroup = @import("chord_detector.zig").ChordGroup;

// Critical test: Sequential bass line MUST NOT be grouped as chord
test "CDR-2.2: Sequential bass line NOT grouped (MVS-2.4 fix)" {
    const allocator = std.testing.allocator;
    var detector = MinimalChordDetector.init(allocator);

    // E2→F#2→G2→B2 at different ticks
    const notes = [_]TimedNote{
        .{ .note = 40, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 120, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 42, .channel = 0, .velocity = 80, .start_tick = 120, .duration = 120, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 43, .channel = 0, .velocity = 80, .start_tick = 240, .duration = 120, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 47, .channel = 0, .velocity = 80, .start_tick = 360, .duration = 120, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
    };

    const groups = try detector.detectChords(&notes);
    defer {
        for (groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(groups);
    }

    // MUST create 4 separate groups
    try std.testing.expectEqual(@as(usize, 4), groups.len);
    for (groups) |group| {
        try std.testing.expectEqual(@as(usize, 1), group.notes.len);
    }
}

test "CDR-2.2: Legitimate chord detected" {
    const allocator = std.testing.allocator;
    var detector = MinimalChordDetector.init(allocator);

    // C major chord at same tick
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 67, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
    };

    const groups = try detector.detectChords(&notes);
    defer {
        for (groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(groups);
    }

    // Should create 1 chord group with 3 notes
    try std.testing.expectEqual(@as(usize, 1), groups.len);
    try std.testing.expectEqual(@as(usize, 3), groups[0].notes.len);
}

test "CDR-2.2: NO tolerance (1 tick difference = separate)" {
    const allocator = std.testing.allocator;
    var detector = MinimalChordDetector.init(allocator);

    // Notes offset by 1 tick each
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 1, .duration = 480, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
    };

    const groups = try detector.detectChords(&notes);
    defer {
        for (groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(groups);
    }

    // MUST create 2 separate groups
    try std.testing.expectEqual(@as(usize, 2), groups.len);
}

test "CDR-2.2: Wide range fail-safe" {
    const allocator = std.testing.allocator;
    var detector = MinimalChordDetector.init(allocator);

    // 3 octave span
    const notes = [_]TimedNote{
        .{ .note = 36, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 72, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
    };

    const groups = try detector.detectChords(&notes);
    defer {
        for (groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(groups);
    }

    // Fail-safe: 2 separate groups
    try std.testing.expectEqual(@as(usize, 2), groups.len);
}

test "CDR-2.2: Duplicate pitch fail-safe" {
    const allocator = std.testing.allocator;
    var detector = MinimalChordDetector.init(allocator);

    // Same pitch twice
    const notes = [_]TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .track = 0, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480, .track = 1, .voice = 0, .tied_to_next = false, .tied_from_previous = false },
    };

    const groups = try detector.detectChords(&notes);
    defer {
        for (groups) |*group| {
            group.deinit(allocator);
        }
        allocator.free(groups);
    }

    // Fail-safe: 2 separate groups
    try std.testing.expectEqual(@as(usize, 2), groups.len);
}

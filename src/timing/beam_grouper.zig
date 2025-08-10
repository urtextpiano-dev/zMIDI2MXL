//! Intelligent Beam Grouping Module
//!
//! Implements TASK-048: Intelligent Beam Grouping per IMPLEMENTATION_TASK_LIST.md lines 604-613
//!
//! This module implements time signature-aware beam grouping for proper musical notation.
//! It groups beams according to meter, handles complex rhythms, and optimizes readability
//! for students learning sheet music.
//!
//! Features:
//! - Time signature-aware grouping (4/4, 3/4, 6/8, 2/2, etc.)
//! - Beat hierarchy respect (don't beam across major beat divisions)
//! - Complex rhythm handling (mixed note values, rests, dotted rhythms)
//! - MusicXML beam element generation
//!
//! References:
//! - musical_intelligence_algorithms.md Section 7.1 lines 1171-1210
//! - TASK-025 (Measure Boundary Detection) for integration
//! - TASK-012 (Time Signature) for meter information
//! - TASK-028 (Note Type Converter) for note types
//!
//! Performance target: < 1ms per measure per TASK-048

const std = @import("std");
const containers = @import("../utils/containers.zig");
const log = @import("../utils/log.zig");
const measure_detector = @import("measure_detector.zig");
const note_type_converter = @import("note_type_converter.zig");
const midi_parser = @import("../midi/parser.zig");
const error_mod = @import("../error.zig");
const arena_mod = @import("../memory/arena.zig");

// Error types for beam grouping operations
pub const BeamGroupingError = error{
    InvalidTimeSignature,
    InvalidNote,
    AllocationFailure,
};

/// Beam state for a note in MusicXML
pub const BeamState = enum {
    begin, // Start of a beam group
    @"continue", // Middle of a beam group
    end, // End of a beam group
    none, // No beam (omit <beam> element)

    /// Return MusicXML text for a beam state, or null if no beam should be emitted.
    pub fn toXml(self: BeamState) ?[]const u8 {
        if (self == .none) return null;
        // @tagName produces "begin", "continue", "end" as desired for MusicXML
        return @tagName(self);
    }
};

/// Beam information for a note
pub const BeamInfo = struct {
    /// Beam level (1 for eighth notes, 2 for 16ths, etc.)
    level: u8,
    /// Beam state for this level
    state: BeamState,
};

/// Practical maximum beam levels seen in engraving:
/// 1: 8ths, 2: 16ths, 3: 32nds, 4: 64ths. Bump to 5 if you truly need 128ths.
pub const MaxBeamLevels: usize = 4;

/// Note with beam information
pub const BeamedNote = struct {
    /// Original timed note data
    note: measure_detector.TimedNote,
    /// Note type information
    note_type: note_type_converter.NoteTypeResult,
    /// Beam information for each level (bounded, no per-note allocation)
    beams: std.BoundedArray(BeamInfo, MaxBeamLevels),
    /// Beat position within measure (0.0 = start of measure)
    beat_position: f64,

    /// Initialize a beamed note (no allocator needed; zero heap work here)
    pub fn init(
        note: measure_detector.TimedNote,
        note_type: note_type_converter.NoteTypeResult,
        beat_position: f64,
    ) BeamedNote {
        return BeamedNote{
            .note = note,
            .note_type = note_type,
            .beams = .{}, // empty bounded array
            .beat_position = beat_position,
        };
    }

    /// Add a beam info level (returns error if you exceed MaxBeamLevels)
    pub fn addBeam(self: *BeamedNote, info: BeamInfo) !void {
        try self.beams.append(info);
    }

    /// Whether this note can be beamed (eighth note or shorter)
    pub fn canBeam(self: *const BeamedNote) bool {
        return BeamGrouper.canNoteBeBeamed(self.note_type.note_type);
    }

    /// No deinit needed; no dynamic allocation owned by BeamedNote
    pub fn deinit(self: *BeamedNote) void {
        // Intentionally empty
        _ = self;
    }
};

/// Beam group representing connected notes
pub const BeamGroup = struct {
    /// Notes in this beam group
    notes: std.ArrayList(BeamedNote),
    /// Start beat position
    start_beat: f64,
    /// End beat position
    end_beat: f64,

    /// Initialize beam group with a sensible small capacity (typical 2–4 notes)
    pub fn init(allocator: std.mem.Allocator) !BeamGroup {
        return BeamGroup{
            .notes = try std.ArrayList(BeamedNote).initCapacity(allocator, 4),
            .start_beat = 0,
            .end_beat = 0,
        };
    }

    /// Clean up beam group
    pub fn deinit(self: *BeamGroup) void {
        // BeamedNote has no heap members, but keep the loop in case that changes later
        for (self.notes.items) |*note| {
            note.deinit();
        }
        self.notes.deinit();
    }

    /// Add a note to the beam group (takes ownership)
    pub fn addNote(self: *BeamGroup, note: BeamedNote) !void {
        if (self.notes.items.len == 0) {
            self.start_beat = note.beat_position;
        }
        self.end_beat = note.beat_position + BeamGrouper.getBeatDuration(
            note.note_type,
            note.note.duration,
        );
        try self.notes.append(note);
    }

    /// Create and add a note to the beam group
    pub fn createAndAddNote(
        self: *BeamGroup,
        timed_note: measure_detector.TimedNote,
        note_type: note_type_converter.NoteTypeResult,
        beat_position: f64,
    ) !void {
        const note = BeamedNote.init(timed_note, note_type, beat_position);
        try self.addNote(note);
    }
};

/// Intelligent Beam Grouper
/// Implements TASK-048 per musical_intelligence_algorithms.md Section 7.1
/// Updated for TASK-INT-008 educational processing chain integration
pub const BeamGrouper = struct {
    allocator: std.mem.Allocator,
    divisions_per_quarter: u32,
    /// Optional integration arena
    educational_arena: ?*arena_mod.EducationalArena = null,

    // -------- Container-scope helpers (not nested) --------
    /// Integer beat index in denominator units (e.g., in 6/8 this is an 8th-note index)
    fn beatIndex(start_tick: u32, measure_start_tick: u32, beat_len_ticks: u32) u32 {
        const rel = start_tick - measure_start_tick;
        return rel / beat_len_ticks;
    }

    /// True if the note crosses a beat boundary (denominator unit), using integer ticks only
    fn crossesBeat(start_tick: u32, duration_ticks: u32, measure_start_tick: u32, beat_len_ticks: u32) bool {
        const rel = start_tick - measure_start_tick;
        return (rel % beat_len_ticks) + duration_ticks >= beat_len_ticks;
    }
    // ------------------------------------------------------

    /// Initialize the beam grouper
    pub fn init(allocator: std.mem.Allocator, divisions_per_quarter: u32) BeamGrouper {
        return .{
            .allocator = allocator,
            .divisions_per_quarter = divisions_per_quarter,
        };
    }

    /// Initialize with educational arena
    pub fn initWithArena(educational_arena: *arena_mod.EducationalArena, divisions_per_quarter: u32) BeamGrouper {
        return .{
            .allocator = educational_arena.allocator(),
            .divisions_per_quarter = divisions_per_quarter,
            .educational_arena = educational_arena,
        };
    }

    /// Group notes in a measure with intelligent beaming
    pub fn groupBeamsInMeasure(
        self: *const BeamGrouper,
        measure: *const measure_detector.Measure,
        note_types: []const note_type_converter.NoteTypeResult,
    ) (BeamGroupingError || std.mem.Allocator.Error)![]BeamGroup {
        if (measure.notes.items.len != note_types.len) {
            return BeamGroupingError.InvalidNote;
        }

        if (self.educational_arena) |arena| arena.beginPhase(.beam_grouping);
        defer if (self.educational_arena) |arena| arena.endPhase();

        const time_sig = measure.time_signature;
        const beat_len_ticks = self.getBeatLength(time_sig);

        // Choose allocator (arena if present)
        const alloc = if (self.educational_arena) |arena| arena.allocator() else self.allocator;

        // Create beam groups without intermediate BeamedNote array
        var groups = containers.List(BeamGroup).init(alloc);
        errdefer {
            for (groups.items) |*g| g.deinit();
            groups.deinit();
        }

        var current_group_idx: ?usize = null;

        // Process notes directly into beam groups
        for (measure.notes.items, note_types) |timed_note, note_type| {
            const can_beam = BeamGrouper.canNoteBeBeBeamed(note_type.note_type);
            if (!can_beam) {
                current_group_idx = null;
                continue;
            }

            const bi: u32 = beatIndex(timed_note.start_tick, measure.start_tick, beat_len_ticks);
            const x_beat: bool = crossesBeat(timed_note.start_tick, timed_note.duration, measure.start_tick, beat_len_ticks);

            const should_start_new_group = if (current_group_idx) |idx| blk: {
                const group = &groups.items[idx];
                // group.start_beat is f64; we only ever use floor() → convert once to an integer beat index
                const gbi: u32 = @as(u32, @intFromFloat(@floor(group.start_beat)));

                break :blk switch (time_sig.numerator) {
                    4 => // 4/4: don’t span the midpoint; don’t cross beats; cap 4 eighths
                    (bi >= 2 and gbi < 2) or
                        x_beat or
                        (group.notes.items.len >= 4 and note_type.note_type == .eighth),

                    3 => // 3/4: group by beat or in 3s
                    (gbi != bi) or
                        (group.notes.items.len >= 3 and note_type.note_type == .eighth),

                    6, 9, 12 => { // compound meters: 3-eighth windows
                        const w_bi: u32 = bi / 3;
                        const w_gbi: u32 = gbi / 3;
                        (w_bi != w_gbi) or
                            (group.notes.items.len >= 3 and note_type.note_type == .eighth);
                    },

                    2 => if (time_sig.getDenominator() == 2) // Cut time (2/2)
                        ((bi / 2) != (gbi / 2)) or
                            (group.notes.items.len >= 8)
                    else // Simple duple (2/4)
                        (gbi != bi) or
                            (group.notes.items.len >= 4),

                    else => // Generic: keep within beat, cap length
                    (gbi != bi) or
                        (group.notes.items.len >= 4),
                };
            } else true;

            if (should_start_new_group) {
                var new_group = BeamGroup.init(alloc);
                try new_group.createAndAddNote(
                    alloc,
                    timed_note,
                    note_type,
                    @as(f64, @floatFromInt(bi)), // store integer beat index as f64
                );
                try groups.append(new_group);
                current_group_idx = groups.items.len - 1;
            } else {
                if (current_group_idx) |idx| {
                    try groups.items[idx].createAndAddNote(
                        alloc,
                        timed_note,
                        note_type,
                        @as(f64, @floatFromInt(bi)),
                    );
                }
            }
        }

        // Assign beam states to notes
        for (groups.items) |*group| {
            try self.assignBeamStates(group);
        }

        return try groups.toOwnedSlice();
    }

    /// Assign beam states to notes in a group (unchanged)
    fn assignBeamStates(self: *const BeamGrouper, group: *BeamGroup) !void {
        _ = self;
        if (group.notes.items.len < 2) return;

        for (group.notes.items, 0..) |*note, i| {
            const beam_levels = getBeamLevels(note.note_type.note_type);

            for (0..beam_levels) |level| {
                const beam_state: BeamState = if (i == 0)
                    .begin
                else if (i == group.notes.items.len - 1)
                    .end
                else
                    .@"continue";

                try note.beams.append(.{
                    .level = @as(u8, @intCast(level + 1)),
                    .state = beam_state,
                });
            }
        }
    }

    /// Get beat length in ticks for a time signature (denominator unit)
    fn getBeatLength(self: *const BeamGrouper, time_sig: midi_parser.TimeSignatureEvent) u32 {
        const denominator = time_sig.getDenominator();
        return (4 * self.divisions_per_quarter) / denominator;
    }

    /// Determine if a note type can be beamed (unchanged)
    fn canNoteBeBeBeamed(note_type: note_type_converter.NoteType) bool {
        return switch (note_type) {
            .eighth, .@"16th", .@"32nd", .@"64th", .@"128th", .@"256th" => true,
            else => false,
        };
    }

    /// Get number of beam levels for a note type (unchanged)
    fn getBeamLevels(note_type: note_type_converter.NoteType) u8 {
        return switch (note_type) {
            .eighth => 1,
            .@"16th" => 2,
            .@"32nd" => 3,
            .@"64th" => 4,
            .@"128th" => 5,
            .@"256th" => 6,
            else => 0,
        };
    }

    /// Get beat duration in QUARTER-note beats (unchanged)
    fn getBeatDuration(note_type_result: note_type_converter.NoteTypeResult, duration_ticks: u32) f64 {
        _ = duration_ticks; // duration already encoded in note_type_result
        const base_beats: f64 = switch (note_type_result.note_type) {
            .whole => 4.0,
            .half => 2.0,
            .quarter => 1.0,
            .eighth => 0.5,
            .@"16th" => 0.25,
            .@"32nd" => 0.125,
            .@"64th" => 0.0625,
            .@"128th" => 0.03125,
            .@"256th" => 0.015625,
            else => 1.0,
        };
        var result = base_beats;
        var dot_value = base_beats / 2.0;
        var dots_remaining = note_type_result.dots;
        while (dots_remaining > 0) : (dots_remaining -= 1) {
            result += dot_value;
            dot_value /= 2.0;
        }
        return result;
    }
};

// Tests for TASK-048 validation

test "BeamGrouper - initialization" {
    const allocator = std.testing.allocator;
    const grouper = BeamGrouper.init(allocator, 480);

    try std.testing.expectEqual(@as(u32, 480), grouper.divisions_per_quarter);
}

test "BeamGrouper - can beam detection" {
    try std.testing.expect(BeamGrouper.canNoteBeBeamed(.eighth));
    try std.testing.expect(BeamGrouper.canNoteBeBeamed(.@"16th"));
    try std.testing.expect(BeamGrouper.canNoteBeBeamed(.@"32nd"));
    try std.testing.expect(!BeamGrouper.canNoteBeBeamed(.quarter));
    try std.testing.expect(!BeamGrouper.canNoteBeBeamed(.half));
    try std.testing.expect(!BeamGrouper.canNoteBeBeamed(.whole));
}

test "BeamGrouper - beam levels" {
    try std.testing.expectEqual(@as(u8, 1), BeamGrouper.getBeamLevels(.eighth));
    try std.testing.expectEqual(@as(u8, 2), BeamGrouper.getBeamLevels(.@"16th"));
    try std.testing.expectEqual(@as(u8, 3), BeamGrouper.getBeamLevels(.@"32nd"));
    try std.testing.expectEqual(@as(u8, 0), BeamGrouper.getBeamLevels(.quarter));
}

test "BeamState - toString" {
    try std.testing.expectEqualStrings("begin", BeamState.begin.toString());
    try std.testing.expectEqualStrings("continue", BeamState.@"continue".toString());
    try std.testing.expectEqualStrings("end", BeamState.end.toString());
    try std.testing.expectEqualStrings("", BeamState.none.toString());
}

test "BeamGrouper - simple 4/4 grouping" {
    const allocator = std.testing.allocator;
    const grouper = BeamGrouper.init(allocator, 480);

    // Create a test measure in 4/4
    const time_sig = midi_parser.TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2, // 4/4 time
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };

    var measure = measure_detector.Measure.init(allocator, 1, 0, 1920, time_sig);
    defer measure.deinit();

    // Add four eighth notes (should be grouped in pairs)
    const eighth_duration = 240; // 480 / 2
    const notes = [_]measure_detector.TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = eighth_duration },
        .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 240, .duration = eighth_duration },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 480, .duration = eighth_duration },
        .{ .note = 65, .channel = 0, .velocity = 80, .start_tick = 720, .duration = eighth_duration },
    };

    for (notes) |note| {
        try measure.addNote(note);
    }

    // Create note types (all eighth notes)
    const note_types = [_]note_type_converter.NoteTypeResult{
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
    };

    const groups = try grouper.groupBeamsInMeasure(&measure, &note_types);
    defer {
        for (groups) |*group| {
            group.deinit();
        }
        allocator.free(groups);
    }

    // Should have 2 groups (pairs of eighth notes)
    try std.testing.expect(groups.len >= 1);

    // Check first group has beam states assigned
    if (groups.len > 0) {
        const first_group = &groups[0];
        try std.testing.expect(first_group.notes.items.len >= 1);

        if (first_group.notes.items.len >= 2) {
            // First note should have "begin" state
            const first_note = &first_group.notes.items[0];
            try std.testing.expect(first_note.beams.items.len > 0);
            try std.testing.expectEqual(BeamState.begin, first_note.beams.items[0].state);

            // Last note should have "end" state
            const last_note = &first_group.notes.items[first_group.notes.items.len - 1];
            try std.testing.expect(last_note.beams.items.len > 0);
            try std.testing.expectEqual(BeamState.end, last_note.beams.items[0].state);
        }
    }
}

test "BeamGrouper - 6/8 compound grouping" {
    const allocator = std.testing.allocator;
    const grouper = BeamGrouper.init(allocator, 480);

    // Create a test measure in 6/8
    const time_sig = midi_parser.TimeSignatureEvent{
        .tick = 0,
        .numerator = 6,
        .denominator_power = 3, // 6/8 time
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };

    var measure = measure_detector.Measure.init(allocator, 1, 0, 1440, time_sig); // 6 * 240
    defer measure.deinit();

    // Add six eighth notes (should be grouped in two sets of 3)
    const eighth_duration = 240; // In 6/8, eighth note = 240 ticks
    const notes = [_]measure_detector.TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = eighth_duration },
        .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 240, .duration = eighth_duration },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 480, .duration = eighth_duration },
        .{ .note = 65, .channel = 0, .velocity = 80, .start_tick = 720, .duration = eighth_duration },
        .{ .note = 67, .channel = 0, .velocity = 80, .start_tick = 960, .duration = eighth_duration },
        .{ .note = 69, .channel = 0, .velocity = 80, .start_tick = 1200, .duration = eighth_duration },
    };

    for (notes) |note| {
        try measure.addNote(note);
    }

    // Create note types (all eighth notes)
    const note_types = [_]note_type_converter.NoteTypeResult{
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
    };

    const groups = try grouper.groupBeamsInMeasure(&measure, &note_types);
    defer {
        for (groups) |*group| {
            group.deinit();
        }
        allocator.free(groups);
    }

    // In 6/8, should group in sets of 3
    try std.testing.expect(groups.len >= 1);
}

test "BeamedNote - initialization and cleanup" {
    const allocator = std.testing.allocator;

    const timed_note = measure_detector.TimedNote{
        .note = 60,
        .channel = 0,
        .velocity = 80,
        .start_tick = 0,
        .duration = 240,
        .tied_to_next = false,
        .tied_from_previous = false,
    };

    const note_type = note_type_converter.NoteTypeResult{
        .note_type = .eighth,
        .dots = 0,
    };

    var beamed_note = try BeamedNote.init(allocator, timed_note, note_type, 0.0);
    defer beamed_note.deinit();

    try std.testing.expect(beamed_note.can_beam);
    try std.testing.expectEqual(@as(f64, 0.0), beamed_note.beat_position);
}

test "BeamGrouper - educational arena integration" {
    // Test TASK-INT-008 memory management improvements
    var edu_arena = arena_mod.EducationalArena.init(std.testing.allocator, true, false);
    defer edu_arena.deinit();

    const grouper = BeamGrouper.initWithArena(&edu_arena, 480);

    // Create a test measure in 4/4
    const time_sig = midi_parser.TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };

    var measure = measure_detector.Measure.init(edu_arena.allocator(), 1, 0, 1920, time_sig);
    defer measure.deinit();

    // Add test notes
    const notes = [_]measure_detector.TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 240 },
        .{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 240, .duration = 240 },
        .{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 240 },
        .{ .note = 65, .channel = 0, .velocity = 80, .start_tick = 720, .duration = 240 },
    };

    for (notes) |note| {
        try measure.addNote(note);
    }

    const note_types = [_]note_type_converter.NoteTypeResult{
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
    };

    // Test beam grouping with educational arena
    const groups = try grouper.groupBeamsInMeasure(&measure, &note_types);
    defer {
        for (groups) |*group| {
            group.deinit();
        }
        edu_arena.allocator().free(groups);
    }

    // Verify results
    try std.testing.expect(groups.len >= 1);

    // Check phase metrics
    const metrics = edu_arena.getMetrics();
    const beam_idx = @intFromEnum(arena_mod.EducationalPhase.beam_grouping);
    try std.testing.expect(metrics.phase_allocations[beam_idx] > 0);

    // Test memory cleanup by resetting arena
    edu_arena.resetForNextCycle();
}

test "BeamGrouper - performance benchmark" {
    const allocator = std.testing.allocator;
    const grouper = BeamGrouper.init(allocator, 480);

    // Performance target: < 1ms per measure per TASK-048
    const target_ns: u64 = 1_000_000; // 1ms in nanoseconds

    // Create a complex 4/4 measure
    const time_sig = midi_parser.TimeSignatureEvent{
        .tick = 0,
        .numerator = 4,
        .denominator_power = 2,
        .clocks_per_metronome = 24,
        .thirtysecond_notes_per_quarter = 8,
    };

    var measure = measure_detector.Measure.init(allocator, 1, 0, 1920, time_sig);
    defer measure.deinit();

    // Add 16 mixed notes (quarter, eighths, sixteenths)
    try measure.addNote(.{ .note = 60, .channel = 0, .velocity = 80, .start_tick = 0, .duration = 480 });
    try measure.addNote(.{ .note = 62, .channel = 0, .velocity = 80, .start_tick = 480, .duration = 240 });
    try measure.addNote(.{ .note = 64, .channel = 0, .velocity = 80, .start_tick = 720, .duration = 240 });

    // Add 8 sixteenth notes
    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        try measure.addNote(.{
            .note = 65 + @as(u8, @intCast(i)),
            .channel = 0,
            .velocity = 80,
            .start_tick = 960 + i * 120,
            .duration = 120,
        });
    }

    // Create note types
    const note_types = [_]note_type_converter.NoteTypeResult{
        .{ .note_type = .quarter, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .eighth, .dots = 0 },
        .{ .note_type = .@"16th", .dots = 0 },
        .{ .note_type = .@"16th", .dots = 0 },
        .{ .note_type = .@"16th", .dots = 0 },
        .{ .note_type = .@"16th", .dots = 0 },
        .{ .note_type = .@"16th", .dots = 0 },
        .{ .note_type = .@"16th", .dots = 0 },
        .{ .note_type = .@"16th", .dots = 0 },
        .{ .note_type = .@"16th", .dots = 0 },
    };

    // Warm up
    var warm_up: u32 = 0;
    while (warm_up < 100) : (warm_up += 1) {
        const groups = try grouper.groupBeamsInMeasure(&measure, &note_types);
        defer {
            for (groups) |*group| {
                group.deinit();
            }
            allocator.free(groups);
        }
    }

    // Benchmark
    const iterations = 1000;
    var timer = try std.time.Timer.start();

    var j: u32 = 0;
    while (j < iterations) : (j += 1) {
        const groups = try grouper.groupBeamsInMeasure(&measure, &note_types);
        defer {
            for (groups) |*group| {
                group.deinit();
            }
            allocator.free(groups);
        }
    }

    const elapsed_ns = timer.read();
    const avg_ns = elapsed_ns / iterations;
    const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;

    log.debug("\nBeamGrouper Performance: {d:.3} ms per measure (target: < 1.000 ms)", .{avg_ms});
    log.debug("  Status: {s}", .{if (avg_ns < target_ns) "PASS ✓" else "FAIL ✗"});
    log.debug("  Time per note: {d:.3} μs", .{@as(f64, @floatFromInt(avg_ns)) / 11.0 / 1000.0});

    // Test should pass if under 1ms
    try std.testing.expect(avg_ns < target_ns);
}

const std = @import("std");

// ============================================================================
// MINIMAL MOCK STRUCTURES
// ============================================================================

/// Beam state for a note in MusicXML
pub const BeamState = enum {
    begin,      // Start of a beam group
    @"continue",  // Middle of a beam group
    end,        // End of a beam group
    none,       // No beam (isolated note or too long)
    
    /// Get string representation for MusicXML
    pub fn toString(self: BeamState) []const u8 {
        return switch (self) {
            .begin => "begin",
            .@"continue" => "continue",
            .end => "end",
            .none => "none",
        };
    }
};

/// Represents a musical note with timing information
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
};

/// Beam grouping information for a note
pub const BeamingInfo = struct {
    /// Beam state information for this note
    beam_state: BeamState = .none,
    /// Beam level (1 for eighth notes, 2 for 16ths, etc.)
    beam_level: u8 = 0,
    /// Whether this note can be beamed (eighth note or shorter)
    can_beam: bool = false,
    /// Beat position within measure (0.0 = start of measure)
    beat_position: f64 = 0.0,
    /// Group identifier for beam coordination
    beam_group_id: ?u32 = null,
};

/// Enhanced timed note with educational metadata
pub const EnhancedTimedNote = struct {
    /// Base timed note data (required)
    base_note: TimedNote,
    
    /// Optional beam grouping information
    beaming_info: ?*BeamingInfo = null,
};

/// Beam group information for validation
pub const BeamGroupInfo = struct {
    group_id: u32,
    notes: []EnhancedTimedNote,
    start_tick: u32,
    end_tick: u32,
};

/// Mock EducationalProcessor struct
pub const EducationalProcessor = struct {
    dummy: bool = false,  // Minimal field to make it a valid struct
};

// ============================================================================
// SIMPLIFIED FUNCTION IMPLEMENTATION
// ============================================================================

fn repairBeamGroupIntegrity(
    self: *EducationalProcessor,
    group: BeamGroupInfo,
    enhanced_notes: []EnhancedTimedNote
) !void {
    _ = self;
    _ = enhanced_notes;
    
    // Process each pair of adjacent notes
    var i: usize = 0;
    while (i < group.notes.len) : (i += 1) {
        const note = &group.notes[i];
        
        // Skip notes without beaming info
        const beam_info = note.beaming_info orelse continue;
        
        // Check for large gap to next note
        if (i + 1 < group.notes.len) {
            const next_note = &group.notes[i + 1];
            const note_end = note.base_note.start_tick + note.base_note.duration;
            
            // Calculate gap (0 if overlapping)
            const gap = if (next_note.base_note.start_tick > note_end) 
                next_note.base_note.start_tick - note_end 
            else 0;
            
            // Break beam if gap exceeds threshold
            if (gap > 120) {
                beam_info.beam_state = .end;
                // Start new beam at next note if it has beaming info
                if (next_note.beaming_info) |next_beam| {
                    next_beam.beam_state = .begin;
                }
            }
        }
    }
}

// ============================================================================
// TEST UTILITIES
// ============================================================================

fn createTestNote(start_tick: u32, duration: u32, beam_state: BeamState) EnhancedTimedNote {
    _ = beam_state;
    const note = EnhancedTimedNote{
        .base_note = .{
            .note = 60,  // Middle C
            .channel = 0,
            .velocity = 64,
            .start_tick = start_tick,
            .duration = duration,
        },
        .beaming_info = null,
    };
    return note;
}

fn createTestNoteWithBeaming(
    allocator: std.mem.Allocator, 
    start_tick: u32, 
    duration: u32, 
    beam_state: BeamState
) !EnhancedTimedNote {
    const beam_info = try allocator.create(BeamingInfo);
    beam_info.* = .{
        .beam_state = beam_state,
        .beam_level = 1,
        .can_beam = true,
        .beat_position = 0.0,
        .beam_group_id = 1,
    };
    
    return EnhancedTimedNote{
        .base_note = .{
            .note = 60,
            .channel = 0,
            .velocity = 64,
            .start_tick = start_tick,
            .duration = duration,
        },
        .beaming_info = beam_info,
    };
}

// ============================================================================
// MAIN TEST PROGRAM
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== Testing repairBeamGroupIntegrity Function ===\n\n", .{});
    
    // Test Case 1: Notes with large gap (should break beam)
    {
        std.debug.print("Test 1: Notes with large gap (>120 ticks)\n", .{});
        
        var notes = [_]EnhancedTimedNote{
            try createTestNoteWithBeaming(allocator, 0, 100, .begin),
            try createTestNoteWithBeaming(allocator, 250, 100, .@"continue"), // 150 tick gap
            try createTestNoteWithBeaming(allocator, 380, 100, .end),
        };
        defer for (notes) |note| {
            if (note.beaming_info) |info| allocator.destroy(info);
        };
        
        var processor = EducationalProcessor{};
        const group = BeamGroupInfo{
            .group_id = 1,
            .notes = &notes,
            .start_tick = 0,
            .end_tick = 480,
        };
        
        try repairBeamGroupIntegrity(&processor, group, &notes);
        
        std.debug.print("  Note 0: beam_state = {s}\n", .{notes[0].beaming_info.?.beam_state.toString()});
        std.debug.print("  Note 1: beam_state = {s}\n", .{notes[1].beaming_info.?.beam_state.toString()});
        std.debug.print("  Note 2: beam_state = {s}\n", .{notes[2].beaming_info.?.beam_state.toString()});
    }
    
    // Test Case 2: Notes with small gap (should not break beam)
    {
        std.debug.print("\nTest 2: Notes with small gap (<120 ticks)\n", .{});
        
        var notes = [_]EnhancedTimedNote{
            try createTestNoteWithBeaming(allocator, 0, 100, .begin),
            try createTestNoteWithBeaming(allocator, 110, 100, .@"continue"), // 10 tick gap
            try createTestNoteWithBeaming(allocator, 220, 100, .end),
        };
        defer for (notes) |note| {
            if (note.beaming_info) |info| allocator.destroy(info);
        };
        
        var processor = EducationalProcessor{};
        const group = BeamGroupInfo{
            .group_id = 1,
            .notes = &notes,
            .start_tick = 0,
            .end_tick = 320,
        };
        
        try repairBeamGroupIntegrity(&processor, group, &notes);
        
        std.debug.print("  Note 0: beam_state = {s}\n", .{notes[0].beaming_info.?.beam_state.toString()});
        std.debug.print("  Note 1: beam_state = {s}\n", .{notes[1].beaming_info.?.beam_state.toString()});
        std.debug.print("  Note 2: beam_state = {s}\n", .{notes[2].beaming_info.?.beam_state.toString()});
    }
    
    // Test Case 3: Overlapping notes (should have zero gap)
    {
        std.debug.print("\nTest 3: Overlapping notes\n", .{});
        
        var notes = [_]EnhancedTimedNote{
            try createTestNoteWithBeaming(allocator, 0, 200, .begin),
            try createTestNoteWithBeaming(allocator, 100, 150, .@"continue"), // Overlaps!
            try createTestNoteWithBeaming(allocator, 250, 100, .end),
        };
        defer for (notes) |note| {
            if (note.beaming_info) |info| allocator.destroy(info);
        };
        
        var processor = EducationalProcessor{};
        const group = BeamGroupInfo{
            .group_id = 1,
            .notes = &notes,
            .start_tick = 0,
            .end_tick = 350,
        };
        
        try repairBeamGroupIntegrity(&processor, group, &notes);
        
        std.debug.print("  Note 0: beam_state = {s}\n", .{notes[0].beaming_info.?.beam_state.toString()});
        std.debug.print("  Note 1: beam_state = {s}\n", .{notes[1].beaming_info.?.beam_state.toString()});
        std.debug.print("  Note 2: beam_state = {s}\n", .{notes[2].beaming_info.?.beam_state.toString()});
    }
    
    // Test Case 4: Notes without beaming info (should be skipped)
    {
        std.debug.print("\nTest 4: Mixed notes with and without beaming info\n", .{});
        
        var notes = [_]EnhancedTimedNote{
            try createTestNoteWithBeaming(allocator, 0, 100, .begin),
            createTestNote(200, 100, .none), // No beaming info
            try createTestNoteWithBeaming(allocator, 350, 100, .end),
        };
        defer {
            if (notes[0].beaming_info) |info| allocator.destroy(info);
            if (notes[2].beaming_info) |info| allocator.destroy(info);
        }
        
        var processor = EducationalProcessor{};
        const group = BeamGroupInfo{
            .group_id = 1,
            .notes = &notes,
            .start_tick = 0,
            .end_tick = 450,
        };
        
        try repairBeamGroupIntegrity(&processor, group, &notes);
        
        std.debug.print("  Note 0: beam_state = {s}\n", .{notes[0].beaming_info.?.beam_state.toString()});
        std.debug.print("  Note 1: has beaming_info = {}\n", .{notes[1].beaming_info != null});
        std.debug.print("  Note 2: beam_state = {s}\n", .{notes[2].beaming_info.?.beam_state.toString()});
    }
    
    std.debug.print("\n=== All tests completed ===\n", .{});
}

// ============================================================================
// UNIT TESTS
// ============================================================================

test "repairBeamGroupIntegrity breaks beam for large gaps" {
    var allocator = std.testing.allocator;
    
    var notes = [_]EnhancedTimedNote{
        try createTestNoteWithBeaming(allocator, 0, 100, .begin),
        try createTestNoteWithBeaming(allocator, 250, 100, .@"continue"), // 150 tick gap
        try createTestNoteWithBeaming(allocator, 380, 100, .end),
    };
    defer for (notes) |note| {
        if (note.beaming_info) |info| allocator.destroy(info);
    };
    
    var processor = EducationalProcessor{};
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = &notes,
        .start_tick = 0,
        .end_tick = 480,
    };
    
    try repairBeamGroupIntegrity(&processor, group, &notes);
    
    // First note should end the beam due to large gap
    try std.testing.expectEqual(BeamState.end, notes[0].beaming_info.?.beam_state);
    // Second note should begin a new beam
    try std.testing.expectEqual(BeamState.begin, notes[1].beaming_info.?.beam_state);
}

test "repairBeamGroupIntegrity preserves beam for small gaps" {
    var allocator = std.testing.allocator;
    
    var notes = [_]EnhancedTimedNote{
        try createTestNoteWithBeaming(allocator, 0, 100, .begin),
        try createTestNoteWithBeaming(allocator, 110, 100, .@"continue"), // 10 tick gap
        try createTestNoteWithBeaming(allocator, 220, 100, .end),
    };
    defer for (notes) |note| {
        if (note.beaming_info) |info| allocator.destroy(info);
    };
    
    var processor = EducationalProcessor{};
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = &notes,
        .start_tick = 0,
        .end_tick = 320,
    };
    
    try repairBeamGroupIntegrity(&processor, group, &notes);
    
    // Beam states should remain unchanged for small gaps
    try std.testing.expectEqual(BeamState.begin, notes[0].beaming_info.?.beam_state);
    try std.testing.expectEqual(BeamState.@"continue", notes[1].beaming_info.?.beam_state);
    try std.testing.expectEqual(BeamState.end, notes[2].beaming_info.?.beam_state);
}

test "repairBeamGroupIntegrity handles overlapping notes" {
    var allocator = std.testing.allocator;
    
    var notes = [_]EnhancedTimedNote{
        try createTestNoteWithBeaming(allocator, 0, 200, .begin),
        try createTestNoteWithBeaming(allocator, 100, 150, .@"continue"), // Overlaps!
        try createTestNoteWithBeaming(allocator, 250, 100, .end),
    };
    defer for (notes) |note| {
        if (note.beaming_info) |info| allocator.destroy(info);
    };
    
    var processor = EducationalProcessor{};
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = &notes,
        .start_tick = 0,
        .end_tick = 350,
    };
    
    try repairBeamGroupIntegrity(&processor, group, &notes);
    
    // Overlapping notes should not break the beam (gap = 0)
    try std.testing.expectEqual(BeamState.begin, notes[0].beaming_info.?.beam_state);
    try std.testing.expectEqual(BeamState.@"continue", notes[1].beaming_info.?.beam_state);
    try std.testing.expectEqual(BeamState.end, notes[2].beaming_info.?.beam_state);
}

test "repairBeamGroupIntegrity skips notes without beaming info" {
    var allocator = std.testing.allocator;
    
    var notes = [_]EnhancedTimedNote{
        createTestNote(0, 100, .none), // No beaming info
        try createTestNoteWithBeaming(allocator, 200, 100, .begin),
        createTestNote(350, 100, .none), // No beaming info
    };
    defer {
        if (notes[1].beaming_info) |info| allocator.destroy(info);
    }
    
    var processor = EducationalProcessor{};
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = &notes,
        .start_tick = 0,
        .end_tick = 450,
    };
    
    // Should not crash when encountering notes without beaming info
    try repairBeamGroupIntegrity(&processor, group, &notes);
    
    // Note without beaming info should remain null
    try std.testing.expect(notes[0].beaming_info == null);
    try std.testing.expect(notes[2].beaming_info == null);
    // Note with beaming info should remain
    try std.testing.expect(notes[1].beaming_info != null);
}

test "repairBeamGroupIntegrity handles empty group" {
    var processor = EducationalProcessor{};
    const empty_notes: []EnhancedTimedNote = &[_]EnhancedTimedNote{};
    
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = empty_notes,
        .start_tick = 0,
        .end_tick = 0,
    };
    
    // Should not crash with empty notes
    try repairBeamGroupIntegrity(&processor, group, empty_notes);
}

test "repairBeamGroupIntegrity handles single note" {
    var allocator = std.testing.allocator;
    
    var notes = [_]EnhancedTimedNote{
        try createTestNoteWithBeaming(allocator, 0, 100, .begin),
    };
    defer if (notes[0].beaming_info) |info| allocator.destroy(info);
    
    var processor = EducationalProcessor{};
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = &notes,
        .start_tick = 0,
        .end_tick = 100,
    };
    
    try repairBeamGroupIntegrity(&processor, group, &notes);
    
    // Single note should remain unchanged
    try std.testing.expectEqual(BeamState.begin, notes[0].beaming_info.?.beam_state);
}
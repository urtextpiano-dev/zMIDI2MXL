const std = @import("std");
const testing = std.testing;

// ============================================================================
// MINIMAL DEPENDENCIES (copied from source)
// ============================================================================

/// Beam state for a note in MusicXML
pub const BeamState = enum {
    begin,      // Start of a beam group
    @"continue",  // Middle of a beam group
    end,        // End of a beam group
    none,       // No beam (isolated note or too long)
};

/// Beam grouping information for a note
pub const BeamingInfo = struct {
    beam_state: BeamState = .none,
    beam_level: u8 = 0,
    can_beam: bool = false,
    beat_position: f64 = 0.0,
    beam_group_id: ?u32 = null,
};

/// Enhanced timed note structure (simplified for testing)
pub const EnhancedTimedNote = struct {
    // Base note data (simplified)
    pitch: u8 = 60,
    start_time: u64 = 0,
    duration: u64 = 480,
    
    // Optional beam grouping information
    beaming_info: ?*BeamingInfo = null,
};

/// Mock educational processor (minimal for testing)
pub const EducationalProcessor = struct {
    dummy_field: bool = true,
};

// ============================================================================
// ORIGINAL FUNCTION (BASELINE)
// ============================================================================

fn ensureConsistentBeamingInRange_original(self: *EducationalProcessor, notes: []EnhancedTimedNote) void {
    _ = self;
    
    if (notes.len < 2) return;
    
    // Check if any notes are beamed
    var any_beamed = false;
    for (notes) |note| {
        if (note.beaming_info != null and note.beaming_info.?.beam_state != .none) {
            any_beamed = true;
            break;
        }
    }
    
    if (!any_beamed) return;
    
    // Ensure proper beam states for the range
    for (notes, 0..) |*note, i| {
        if (note.beaming_info) |info| {
            if (i == 0) {
                info.*.beam_state = .begin;
            } else if (i == notes.len - 1) {
                info.*.beam_state = .end;
            } else {
                info.*.beam_state = .@"continue";
            }
        }
    }
}

// ============================================================================
// ANALYSIS: NO MEANINGFUL SIMPLIFICATION FOUND
// ============================================================================
// After analysis, the original function is already optimal:
// - Early returns minimize unnecessary work
// - Single responsibility: ensure beam consistency
// - Clear logic flow with no redundancy
// - Efficient two-pass algorithm (check then apply)
//
// The function could theoretically be "simplified" by:
// 1. Combining the two loops into one - BUT this would actually make it
//    MORE complex by requiring tracking state during modification
// 2. Using nested ternary operators - BUT Zig already optimizes the 
//    if-else chain effectively
// 3. Eliminating the any_beamed check - BUT this would waste cycles
//    updating notes that don't need it
//
// The current implementation is the simplest that correctly handles:
// - Empty arrays
// - Single notes  
// - Mixed beaming (some with, some without info)
// - Proper begin/continue/end state assignment
//
// NO SIMPLIFICATION RECOMMENDED - Function is already optimal.

// ============================================================================
// TEST HARNESS
// ============================================================================

fn createTestNotes(allocator: std.mem.Allocator, count: usize, beamed: bool) ![]EnhancedTimedNote {
    const notes = try allocator.alloc(EnhancedTimedNote, count);
    
    for (notes, 0..) |*note, i| {
        note.* = EnhancedTimedNote{
            .pitch = @intCast(60 + i),
            .start_time = i * 480,
            .duration = 240, // Eighth notes
            .beaming_info = if (beamed) try allocator.create(BeamingInfo) else null,
        };
        
        if (note.beaming_info) |info| {
            info.* = BeamingInfo{
                .beam_state = if (beamed) .@"continue" else .none,
                .beam_level = 1,
                .can_beam = true,
                .beat_position = @floatFromInt(i),
                .beam_group_id = 1,
            };
        }
    }
    
    return notes;
}

fn printBeamStates(notes: []EnhancedTimedNote) void {
    for (notes, 0..) |note, i| {
        if (note.beaming_info) |info| {
            std.debug.print("Note {}: beam_state = {s}\n", .{ 
                i, 
                switch (info.beam_state) {
                    .begin => "begin",
                    .@"continue" => "continue",
                    .end => "end",
                    .none => "none",
                }
            });
        } else {
            std.debug.print("Note {}: no beaming info\n", .{i});
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var processor = EducationalProcessor{};
    
    std.debug.print("=== BASELINE FUNCTION TEST ===\n\n", .{});
    
    // Test 1: Empty array
    std.debug.print("Test 1: Empty array\n", .{});
    const empty_notes = try allocator.alloc(EnhancedTimedNote, 0);
    defer allocator.free(empty_notes);
    ensureConsistentBeamingInRange_original(&processor, empty_notes);
    std.debug.print("Result: No crash (expected)\n\n", .{});
    
    // Test 2: Single note (no beaming possible)
    std.debug.print("Test 2: Single note\n", .{});
    const single_note = try createTestNotes(allocator, 1, true);
    defer {
        for (single_note) |note| {
            if (note.beaming_info) |info| allocator.destroy(info);
        }
        allocator.free(single_note);
    }
    ensureConsistentBeamingInRange_original(&processor, single_note);
    printBeamStates(single_note);
    std.debug.print("\n", .{});
    
    // Test 3: Two notes with beaming
    std.debug.print("Test 3: Two notes with beaming\n", .{});
    const two_notes = try createTestNotes(allocator, 2, true);
    defer {
        for (two_notes) |note| {
            if (note.beaming_info) |info| allocator.destroy(info);
        }
        allocator.free(two_notes);
    }
    ensureConsistentBeamingInRange_original(&processor, two_notes);
    printBeamStates(two_notes);
    std.debug.print("\n", .{});
    
    // Test 4: Multiple notes with beaming
    std.debug.print("Test 4: Five notes with beaming\n", .{});
    const five_notes = try createTestNotes(allocator, 5, true);
    defer {
        for (five_notes) |note| {
            if (note.beaming_info) |info| allocator.destroy(info);
        }
        allocator.free(five_notes);
    }
    ensureConsistentBeamingInRange_original(&processor, five_notes);
    printBeamStates(five_notes);
    std.debug.print("\n", .{});
    
    // Test 5: Notes without beaming info
    std.debug.print("Test 5: Notes without beaming info\n", .{});
    const no_beam_notes = try createTestNotes(allocator, 3, false);
    defer allocator.free(no_beam_notes);
    ensureConsistentBeamingInRange_original(&processor, no_beam_notes);
    printBeamStates(no_beam_notes);
    std.debug.print("\n", .{});
    
    // Test 6: Mixed beaming (some with, some without)
    std.debug.print("Test 6: Mixed beaming info\n", .{});
    const mixed_notes = try allocator.alloc(EnhancedTimedNote, 4);
    defer {
        for (mixed_notes) |note| {
            if (note.beaming_info) |info| allocator.destroy(info);
        }
        allocator.free(mixed_notes);
    }
    
    for (mixed_notes, 0..) |*note, i| {
        const has_beam = i % 2 == 0; // Even indices have beaming
        note.* = EnhancedTimedNote{
            .pitch = @intCast(60 + i),
            .start_time = i * 480,
            .duration = 240,
            .beaming_info = if (has_beam) try allocator.create(BeamingInfo) else null,
        };
        
        if (note.beaming_info) |info| {
            info.* = BeamingInfo{
                .beam_state = .@"continue",
                .beam_level = 1,
                .can_beam = true,
                .beat_position = @floatFromInt(i),
                .beam_group_id = 1,
            };
        }
    }
    
    ensureConsistentBeamingInRange_original(&processor, mixed_notes);
    printBeamStates(mixed_notes);
    
    std.debug.print("\n=== ALL TESTS COMPLETED ===\n", .{});
}

// ============================================================================
// UNIT TESTS
// ============================================================================

test "ensureConsistentBeamingInRange handles empty array" {
    var processor = EducationalProcessor{};
    const empty_notes: []EnhancedTimedNote = &[_]EnhancedTimedNote{};
    ensureConsistentBeamingInRange_original(&processor, empty_notes);
    // Should not crash
}

test "ensureConsistentBeamingInRange handles single note" {
    var processor = EducationalProcessor{};
    var beaming = BeamingInfo{ .beam_state = .@"continue" };
    var notes = [_]EnhancedTimedNote{
        .{ .beaming_info = &beaming },
    };
    ensureConsistentBeamingInRange_original(&processor, &notes);
    // Single note should remain unchanged (less than 2 notes)
    try testing.expectEqual(BeamState.@"continue", beaming.beam_state);
}

test "ensureConsistentBeamingInRange handles two beamed notes" {
    var processor = EducationalProcessor{};
    var beaming1 = BeamingInfo{ .beam_state = .@"continue" };
    var beaming2 = BeamingInfo{ .beam_state = .@"continue" };
    var notes = [_]EnhancedTimedNote{
        .{ .beaming_info = &beaming1 },
        .{ .beaming_info = &beaming2 },
    };
    
    ensureConsistentBeamingInRange_original(&processor, &notes);
    
    try testing.expectEqual(BeamState.begin, beaming1.beam_state);
    try testing.expectEqual(BeamState.end, beaming2.beam_state);
}

test "ensureConsistentBeamingInRange handles multiple beamed notes" {
    var processor = EducationalProcessor{};
    var beaming1 = BeamingInfo{ .beam_state = .@"continue" };
    var beaming2 = BeamingInfo{ .beam_state = .@"continue" };
    var beaming3 = BeamingInfo{ .beam_state = .@"continue" };
    var beaming4 = BeamingInfo{ .beam_state = .@"continue" };
    
    var notes = [_]EnhancedTimedNote{
        .{ .beaming_info = &beaming1 },
        .{ .beaming_info = &beaming2 },
        .{ .beaming_info = &beaming3 },
        .{ .beaming_info = &beaming4 },
    };
    
    ensureConsistentBeamingInRange_original(&processor, &notes);
    
    try testing.expectEqual(BeamState.begin, beaming1.beam_state);
    try testing.expectEqual(BeamState.@"continue", beaming2.beam_state);
    try testing.expectEqual(BeamState.@"continue", beaming3.beam_state);
    try testing.expectEqual(BeamState.end, beaming4.beam_state);
}

test "ensureConsistentBeamingInRange skips notes without beaming" {
    var processor = EducationalProcessor{};
    var notes = [_]EnhancedTimedNote{
        .{ .beaming_info = null },
        .{ .beaming_info = null },
        .{ .beaming_info = null },
    };
    
    ensureConsistentBeamingInRange_original(&processor, &notes);
    
    // Should not crash and notes remain unchanged
    for (notes) |note| {
        try testing.expectEqual(@as(?*BeamingInfo, null), note.beaming_info);
    }
}

test "ensureConsistentBeamingInRange requires at least one beamed note" {
    var processor = EducationalProcessor{};
    var beaming1 = BeamingInfo{ .beam_state = .none };
    var beaming2 = BeamingInfo{ .beam_state = .none };
    
    var notes = [_]EnhancedTimedNote{
        .{ .beaming_info = &beaming1 },
        .{ .beaming_info = &beaming2 },
    };
    
    ensureConsistentBeamingInRange_original(&processor, &notes);
    
    // No notes are actually beamed (all have .none), so no changes
    try testing.expectEqual(BeamState.none, beaming1.beam_state);
    try testing.expectEqual(BeamState.none, beaming2.beam_state);
}

test "ensureConsistentBeamingInRange handles mixed beaming info" {
    var processor = EducationalProcessor{};
    var beaming1 = BeamingInfo{ .beam_state = .@"continue" };
    var beaming3 = BeamingInfo{ .beam_state = .@"continue" };
    
    var notes = [_]EnhancedTimedNote{
        .{ .beaming_info = &beaming1 },
        .{ .beaming_info = null },
        .{ .beaming_info = &beaming3 },
    };
    
    ensureConsistentBeamingInRange_original(&processor, &notes);
    
    // First note with beaming gets begin, last gets end
    try testing.expectEqual(BeamState.begin, beaming1.beam_state);
    try testing.expectEqual(BeamState.end, beaming3.beam_state);
}
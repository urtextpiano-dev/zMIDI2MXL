const std = @import("std");
const testing = std.testing;

// Minimal struct definitions required for the function
const TimedNote = struct {
    note: u8,
    channel: u8,
    velocity: u8,
    start_tick: u32,
    duration: u32,
    tied_to_next: bool = false,
    tied_from_previous: bool = false,
    track_index: u8 = 0,
    voice: u8 = 1,
    is_chord: bool = false,
    is_rest: bool = false,
};

const EnhancedTimedNote = struct {
    base_note: TimedNote,
    // Optional fields not needed for this function
};

const BeamGroupInfo = struct {
    group_id: u32,
    notes: []EnhancedTimedNote,
    start_tick: u32,
    end_tick: u32,
};

// Mock EducationalProcessor - minimal implementation
const EducationalProcessor = struct {
    // Fields not needed for this function since self is ignored
};

// ========== ORIGINAL FUNCTION ==========
fn restConflictsWithBeamGroups_original(self: *EducationalProcessor, rest_note: *const EnhancedTimedNote, beam_groups: []const BeamGroupInfo) bool {
    _ = self;
    
    const rest_start = rest_note.base_note.start_tick;
    const rest_end = rest_start + rest_note.base_note.duration;
    
    for (beam_groups) |group| {
        // Check if rest inappropriately intersects with beam group
        if (rest_start < group.end_tick and rest_end > group.start_tick) {
            // Rest overlaps with beam group
            
            // Check if it's a partial overlap (bad) vs complete containment (potentially ok)
            const partial_start = rest_start > group.start_tick and rest_start < group.end_tick;
            const partial_end = rest_end > group.start_tick and rest_end < group.end_tick;
            
            if (partial_start or partial_end) {
                return true; // Partial overlap is problematic
            }
        }
    }
    
    return false;
}

// ========== SIMPLIFIED FUNCTION ==========
fn restConflictsWithBeamGroups(self: *EducationalProcessor, rest_note: *const EnhancedTimedNote, beam_groups: []const BeamGroupInfo) bool {
    _ = self;
    
    const rest_start = rest_note.base_note.start_tick;
    const rest_end = rest_start + rest_note.base_note.duration;
    
    for (beam_groups) |group| {
        // Direct check: partial overlap = exactly one boundary within beam group
        const starts_within = rest_start > group.start_tick and rest_start < group.end_tick;
        const ends_within = rest_end > group.start_tick and rest_end < group.end_tick;
        
        if (starts_within != ends_within) {
            return true;
        }
    }
    
    return false;
}

// ========== TEST HELPERS ==========
fn createRest(start: u32, duration: u32) EnhancedTimedNote {
    return EnhancedTimedNote{
        .base_note = TimedNote{
            .note = 0,
            .channel = 0,
            .velocity = 0,
            .start_tick = start,
            .duration = duration,
            .is_rest = true,
        },
    };
}

fn createBeamGroup(id: u32, start: u32, end: u32) BeamGroupInfo {
    // Notes array not needed for conflict checking
    return BeamGroupInfo{
        .group_id = id,
        .notes = &[_]EnhancedTimedNote{},
        .start_tick = start,
        .end_tick = end,
    };
}

// ========== MAIN TEST PROGRAM ==========
pub fn main() !void {
    var processor = EducationalProcessor{};
    
    std.debug.print("Testing restConflictsWithBeamGroups function\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    
    // Test Case 1: No overlap
    {
        const rest = createRest(100, 50); // 100-150
        const groups = [_]BeamGroupInfo{
            createBeamGroup(1, 0, 90),    // Before rest
            createBeamGroup(2, 160, 200), // After rest
        };
        const orig = restConflictsWithBeamGroups_original(&processor, &rest, &groups);
        const simp = restConflictsWithBeamGroups(&processor, &rest, &groups);
        std.debug.print("Test 1 - No overlap: orig={}, simp={}\n", .{orig, simp});
    }
    
    // Test Case 2: Partial overlap at start
    {
        const rest = createRest(100, 50); // 100-150
        const groups = [_]BeamGroupInfo{
            createBeamGroup(1, 80, 120), // Overlaps start
        };
        const orig = restConflictsWithBeamGroups_original(&processor, &rest, &groups);
        const simp = restConflictsWithBeamGroups(&processor, &rest, &groups);
        std.debug.print("Test 2 - Partial overlap at start: orig={}, simp={}\n", .{orig, simp});
    }
    
    // Test Case 3: Partial overlap at end
    {
        const rest = createRest(100, 50); // 100-150
        const groups = [_]BeamGroupInfo{
            createBeamGroup(1, 130, 170), // Overlaps end
        };
        const orig = restConflictsWithBeamGroups_original(&processor, &rest, &groups);
        const simp = restConflictsWithBeamGroups(&processor, &rest, &groups);
        std.debug.print("Test 3 - Partial overlap at end: orig={}, simp={}\n", .{orig, simp});
    }
    
    // Test Case 4: Complete containment (rest inside beam group)
    {
        const rest = createRest(100, 50); // 100-150
        const groups = [_]BeamGroupInfo{
            createBeamGroup(1, 50, 200), // Completely contains rest
        };
        const orig = restConflictsWithBeamGroups_original(&processor, &rest, &groups);
        const simp = restConflictsWithBeamGroups(&processor, &rest, &groups);
        std.debug.print("Test 4 - Complete containment: orig={}, simp={}\n", .{orig, simp});
    }
    
    // Test Case 5: Beam group inside rest
    {
        const rest = createRest(100, 100); // 100-200
        const groups = [_]BeamGroupInfo{
            createBeamGroup(1, 120, 180), // Inside rest
        };
        const orig = restConflictsWithBeamGroups_original(&processor, &rest, &groups);
        const simp = restConflictsWithBeamGroups(&processor, &rest, &groups);
        std.debug.print("Test 5 - Beam group inside rest: orig={}, simp={}\n", .{orig, simp});
    }
    
    // Test Case 6: Exact boundary touch (start)
    {
        const rest = createRest(100, 50); // 100-150
        const groups = [_]BeamGroupInfo{
            createBeamGroup(1, 50, 100), // Touches at start
        };
        const orig = restConflictsWithBeamGroups_original(&processor, &rest, &groups);
        const simp = restConflictsWithBeamGroups(&processor, &rest, &groups);
        std.debug.print("Test 6 - Exact boundary touch (start): orig={}, simp={}\n", .{orig, simp});
    }
    
    // Test Case 7: Exact boundary touch (end)
    {
        const rest = createRest(100, 50); // 100-150
        const groups = [_]BeamGroupInfo{
            createBeamGroup(1, 150, 200), // Touches at end
        };
        const orig = restConflictsWithBeamGroups_original(&processor, &rest, &groups);
        const simp = restConflictsWithBeamGroups(&processor, &rest, &groups);
        std.debug.print("Test 7 - Exact boundary touch (end): orig={}, simp={}\n", .{orig, simp});
    }
    
    // Test Case 8: Multiple groups with mixed overlaps
    {
        const rest = createRest(100, 50); // 100-150
        const groups = [_]BeamGroupInfo{
            createBeamGroup(1, 0, 90),    // No overlap
            createBeamGroup(2, 120, 180), // Partial overlap
            createBeamGroup(3, 200, 250), // No overlap
        };
        const orig = restConflictsWithBeamGroups_original(&processor, &rest, &groups);
        const simp = restConflictsWithBeamGroups(&processor, &rest, &groups);
        std.debug.print("Test 8 - Multiple groups (should detect conflict): orig={}, simp={}\n", .{orig, simp});
    }
    
    // Test Case 9: Empty beam groups
    {
        const rest = createRest(100, 50);
        const groups = [_]BeamGroupInfo{};
        const orig = restConflictsWithBeamGroups_original(&processor, &rest, &groups);
        const simp = restConflictsWithBeamGroups(&processor, &rest, &groups);
        std.debug.print("Test 9 - Empty beam groups: orig={}, simp={}\n", .{orig, simp});
    }
    
    std.debug.print("=" ** 50 ++ "\n", .{});
    std.debug.print("All functional tests completed\n", .{});
}

// ========== UNIT TESTS ==========
test "no overlap returns false" {
    var processor = EducationalProcessor{};
    const rest = createRest(100, 50); // 100-150
    const groups = [_]BeamGroupInfo{
        createBeamGroup(1, 0, 90),    // Before
        createBeamGroup(2, 160, 200), // After
    };
    try testing.expect(!restConflictsWithBeamGroups(&processor, &rest, &groups));
}

test "partial overlap at start returns true" {
    var processor = EducationalProcessor{};
    const rest = createRest(100, 50); // 100-150
    const groups = [_]BeamGroupInfo{
        createBeamGroup(1, 80, 120), // Overlaps start
    };
    try testing.expect(restConflictsWithBeamGroups(&processor, &rest, &groups));
}

test "partial overlap at end returns true" {
    var processor = EducationalProcessor{};
    const rest = createRest(100, 50); // 100-150
    const groups = [_]BeamGroupInfo{
        createBeamGroup(1, 130, 170), // Overlaps end
    };
    try testing.expect(restConflictsWithBeamGroups(&processor, &rest, &groups));
}

test "complete containment returns false" {
    var processor = EducationalProcessor{};
    const rest = createRest(100, 50); // 100-150
    const groups = [_]BeamGroupInfo{
        createBeamGroup(1, 50, 200), // Contains rest
    };
    try testing.expect(!restConflictsWithBeamGroups(&processor, &rest, &groups));
}

test "beam group inside rest returns false" {
    var processor = EducationalProcessor{};
    const rest = createRest(100, 100); // 100-200
    const groups = [_]BeamGroupInfo{
        createBeamGroup(1, 120, 180), // Inside rest
    };
    try testing.expect(!restConflictsWithBeamGroups(&processor, &rest, &groups));
}

test "exact boundary touch returns false" {
    var processor = EducationalProcessor{};
    const rest1 = createRest(100, 50); // 100-150
    const groups1 = [_]BeamGroupInfo{
        createBeamGroup(1, 50, 100), // Touches at start
    };
    try testing.expect(!restConflictsWithBeamGroups(&processor, &rest1, &groups1));
    
    const rest2 = createRest(100, 50); // 100-150
    const groups2 = [_]BeamGroupInfo{
        createBeamGroup(1, 150, 200), // Touches at end
    };
    try testing.expect(!restConflictsWithBeamGroups(&processor, &rest2, &groups2));
}

test "empty beam groups returns false" {
    var processor = EducationalProcessor{};
    const rest = createRest(100, 50);
    const groups = [_]BeamGroupInfo{};
    try testing.expect(!restConflictsWithBeamGroups(&processor, &rest, &groups));
}

test "multiple groups with one conflict returns true" {
    var processor = EducationalProcessor{};
    const rest = createRest(100, 50); // 100-150
    const groups = [_]BeamGroupInfo{
        createBeamGroup(1, 0, 90),    // No overlap
        createBeamGroup(2, 120, 180), // Partial overlap - CONFLICT!
        createBeamGroup(3, 200, 250), // No overlap
    };
    try testing.expect(restConflictsWithBeamGroups(&processor, &rest, &groups));
}
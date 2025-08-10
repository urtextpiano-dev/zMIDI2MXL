const std = @import("std");
const testing = std.testing;

// Mock structures needed for the function
const TimedNote = struct {
    note: u8,
    channel: u8,
    velocity: u8,
    start_tick: u32,
    duration: u32,
};

const BeamingInfo = struct {
    beam_state: enum { none, begin, cont, end } = .none,
    beam_level: u8 = 0,
    can_beam: bool = false,
    beat_position: f64 = 0.0,
    beam_group_id: ?u32 = null,
};

const EnhancedTimedNote = struct {
    base_note: TimedNote,
    beaming_info: ?*BeamingInfo = null,
};

const BeamGroupInfo = struct {
    group_id: u32,
    notes: []EnhancedTimedNote,
    start_tick: u32,
    end_tick: u32,
};

const RestSpan = struct {
    start_tick: u32,
    end_tick: u32,
    note_indices: std.ArrayList(usize),
    is_optimized_rest: bool,
    
    pub fn deinit(self: *RestSpan) void {
        self.note_indices.deinit();
    }
};

// Mock processor for testing
const EducationalProcessor = struct {
    arena: *std.heap.ArenaAllocator,
};

// Simplified: Combined conditions and early exit from inner loop
fn validateBeamGroupIntegrity(self: *EducationalProcessor, group: BeamGroupInfo, rest_spans: []const RestSpan) bool {
    _ = self;
    
    for (rest_spans) |rest_span| {
        // Skip if rest span is not fully within beam group
        if (rest_span.start_tick <= group.start_tick or rest_span.end_tick >= group.end_tick) 
            continue;
        
        var has_beam_before = false;
        var has_beam_after = false;
        
        for (group.notes) |note| {
            if (note.beaming_info == null) continue;
            
            const tick = note.base_note.start_tick;
            if (tick < rest_span.start_tick) {
                has_beam_before = true;
            } else if (tick >= rest_span.end_tick) {
                has_beam_after = true;
            }
            
            // Early exit when both conditions met
            if (has_beam_before and has_beam_after) return false;
        }
    }
    
    return true;
}

// Helper function to create test data
fn createTestNote(allocator: std.mem.Allocator, start_tick: u32, has_beaming: bool) !EnhancedTimedNote {
    var note = EnhancedTimedNote{
        .base_note = TimedNote{
            .note = 60,
            .channel = 0,
            .velocity = 64,
            .start_tick = start_tick,
            .duration = 120,
        },
        .beaming_info = null,
    };
    
    if (has_beaming) {
        const beaming = try allocator.create(BeamingInfo);
        beaming.* = BeamingInfo{
            .beam_state = .begin,
            .beam_level = 1,
            .can_beam = true,
            .beat_position = 0.0,
            .beam_group_id = 1,
        };
        note.beaming_info = beaming;
    }
    
    return note;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{
        .arena = &sa.arena,
    };
    
    // Test Case 1: No rest spans - should return true
    {
        var notes = try arena.allocator().alloc(EnhancedTimedNote, 3);
        notes[0] = try createTestNote(arena.allocator(), 0, true);
        notes[1] = try createTestNote(arena.allocator(), 120, true);
        notes[2] = try createTestNote(arena.allocator(), 240, true);
        
        const group = BeamGroupInfo{
            .group_id = 1,
            .notes = notes,
            .start_tick = 0,
            .end_tick = 360,
        };
        
        const rest_spans = try arena.allocator().alloc(RestSpan, 0);
        
        const result = validateBeamGroupIntegrity(&processor, group, rest_spans);
        std.debug.print("Test 1 - No rest spans: {}\n", .{result});
    }
    
    // Test Case 2: Rest span breaks continuity - should return false
    {
        var notes = try arena.allocator().alloc(EnhancedTimedNote, 3);
        notes[0] = try createTestNote(arena.allocator(), 0, true);
        notes[1] = try createTestNote(arena.allocator(), 120, false); // No beaming (rest)
        notes[2] = try createTestNote(arena.allocator(), 240, true);
        
        const group = BeamGroupInfo{
            .group_id = 1,
            .notes = notes,
            .start_tick = 0,
            .end_tick = 360,
        };
        
        var rest_spans = try arena.allocator().alloc(RestSpan, 1);
        rest_spans[0] = RestSpan{
            .start_tick = 100,
            .end_tick = 200,
            .note_indices = std.ArrayList(usize).init(arena.allocator()),
            .is_optimized_rest = false,
        };
        
        const result = validateBeamGroupIntegrity(&processor, group, rest_spans);
        std.debug.print("Test 2 - Rest breaks continuity: {}\n", .{result});
    }
    
    // Test Case 3: Rest span outside beam group - should return true
    {
        var notes = try arena.allocator().alloc(EnhancedTimedNote, 2);
        notes[0] = try createTestNote(arena.allocator(), 120, true);
        notes[1] = try createTestNote(arena.allocator(), 240, true);
        
        const group = BeamGroupInfo{
            .group_id = 1,
            .notes = notes,
            .start_tick = 120,
            .end_tick = 360,
        };
        
        var rest_spans = try arena.allocator().alloc(RestSpan, 1);
        rest_spans[0] = RestSpan{
            .start_tick = 0,
            .end_tick = 100,
            .note_indices = std.ArrayList(usize).init(arena.allocator()),
            .is_optimized_rest = false,
        };
        
        const result = validateBeamGroupIntegrity(&processor, group, rest_spans);
        std.debug.print("Test 3 - Rest outside group: {}\n", .{result});
    }
    
    // Test Case 4: Rest span with no beamed notes after - should return true
    {
        var notes = try arena.allocator().alloc(EnhancedTimedNote, 3);
        notes[0] = try createTestNote(arena.allocator(), 0, true);
        notes[1] = try createTestNote(arena.allocator(), 120, false);
        notes[2] = try createTestNote(arena.allocator(), 240, false); // No beaming after rest
        
        const group = BeamGroupInfo{
            .group_id = 1,
            .notes = notes,
            .start_tick = 0,
            .end_tick = 360,
        };
        
        var rest_spans = try arena.allocator().alloc(RestSpan, 1);
        rest_spans[0] = RestSpan{
            .start_tick = 100,
            .end_tick = 200,
            .note_indices = std.ArrayList(usize).init(arena.allocator()),
            .is_optimized_rest = false,
        };
        
        const result = validateBeamGroupIntegrity(&processor, group, rest_spans);
        std.debug.print("Test 4 - No beamed notes after rest: {}\n", .{result});
    }
    
    std.debug.print("\nAll manual tests completed.\n", .{});
}

test "validateBeamGroupIntegrity - no rest spans" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{
        .arena = &sa.arena,
    };
    
    var notes = try arena.allocator().alloc(EnhancedTimedNote, 2);
    notes[0] = try createTestNote(arena.allocator(), 0, true);
    notes[1] = try createTestNote(arena.allocator(), 120, true);
    
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = notes,
        .start_tick = 0,
        .end_tick = 240,
    };
    
    const rest_spans = try arena.allocator().alloc(RestSpan, 0);
    
    const result = validateBeamGroupIntegrity(&processor, group, rest_spans);
    try testing.expect(result == true);
}

test "validateBeamGroupIntegrity - rest breaks continuity" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{
        .arena = &sa.arena,
    };
    
    var notes = try arena.allocator().alloc(EnhancedTimedNote, 3);
    notes[0] = try createTestNote(arena.allocator(), 0, true);
    notes[1] = try createTestNote(arena.allocator(), 120, false);
    notes[2] = try createTestNote(arena.allocator(), 240, true);
    
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = notes,
        .start_tick = 0,
        .end_tick = 360,
    };
    
    var rest_spans = try arena.allocator().alloc(RestSpan, 1);
    rest_spans[0] = RestSpan{
        .start_tick = 100,
        .end_tick = 200,
        .note_indices = std.ArrayList(usize).init(arena.allocator()),
        .is_optimized_rest = false,
    };
    
    const result = validateBeamGroupIntegrity(&processor, group, rest_spans);
    try testing.expect(result == false);
}

test "validateBeamGroupIntegrity - rest outside group" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{
        .arena = &sa.arena,
    };
    
    var notes = try arena.allocator().alloc(EnhancedTimedNote, 2);
    notes[0] = try createTestNote(arena.allocator(), 120, true);
    notes[1] = try createTestNote(arena.allocator(), 240, true);
    
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = notes,
        .start_tick = 120,
        .end_tick = 360,
    };
    
    var rest_spans = try arena.allocator().alloc(RestSpan, 1);
    rest_spans[0] = RestSpan{
        .start_tick = 0,
        .end_tick = 100,
        .note_indices = std.ArrayList(usize).init(arena.allocator()),
        .is_optimized_rest = false,
    };
    
    const result = validateBeamGroupIntegrity(&processor, group, rest_spans);
    try testing.expect(result == true);
}

test "validateBeamGroupIntegrity - no beamed notes after rest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{
        .arena = &sa.arena,
    };
    
    var notes = try arena.allocator().alloc(EnhancedTimedNote, 3);
    notes[0] = try createTestNote(arena.allocator(), 0, true);
    notes[1] = try createTestNote(arena.allocator(), 120, false);
    notes[2] = try createTestNote(arena.allocator(), 240, false);
    
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = notes,
        .start_tick = 0,
        .end_tick = 360,
    };
    
    var rest_spans = try arena.allocator().alloc(RestSpan, 1);
    rest_spans[0] = RestSpan{
        .start_tick = 100,
        .end_tick = 200,
        .note_indices = std.ArrayList(usize).init(arena.allocator()),
        .is_optimized_rest = false,
    };
    
    const result = validateBeamGroupIntegrity(&processor, group, rest_spans);
    try testing.expect(result == true);
}

test "validateBeamGroupIntegrity - multiple rest spans" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    var processor = EducationalProcessor{
        .arena = &sa.arena,
    };
    
    var notes = try arena.allocator().alloc(EnhancedTimedNote, 5);
    notes[0] = try createTestNote(arena.allocator(), 0, true);
    notes[1] = try createTestNote(arena.allocator(), 120, false);
    notes[2] = try createTestNote(arena.allocator(), 240, true);
    notes[3] = try createTestNote(arena.allocator(), 360, false);
    notes[4] = try createTestNote(arena.allocator(), 480, true);
    
    const group = BeamGroupInfo{
        .group_id = 1,
        .notes = notes,
        .start_tick = 0,
        .end_tick = 600,
    };
    
    var rest_spans = try arena.allocator().alloc(RestSpan, 2);
    rest_spans[0] = RestSpan{
        .start_tick = 100,
        .end_tick = 200,
        .note_indices = std.ArrayList(usize).init(arena.allocator()),
        .is_optimized_rest = false,
    };
    rest_spans[1] = RestSpan{
        .start_tick = 340,
        .end_tick = 440,
        .note_indices = std.ArrayList(usize).init(arena.allocator()),
        .is_optimized_rest = false,
    };
    
    const result = validateBeamGroupIntegrity(&processor, group, rest_spans);
    try testing.expect(result == false); // Both rests break continuity
}
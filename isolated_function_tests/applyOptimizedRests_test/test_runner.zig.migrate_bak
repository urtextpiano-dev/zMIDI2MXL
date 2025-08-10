const std = @import("std");
const testing = std.testing;

// ===== MINIMAL MOCKS AND DEPENDENCIES =====

// Mock NoteType enum for Rest structure
const NoteType = enum {
    breve, whole, half, quarter, eighth,
    @"16th", @"32nd", @"64th", @"128th", @"256th",
};

// Mock Rest structure from rest_optimizer.zig
const Rest = struct {
    start_time: u32,
    duration: u32,
    note_type: NoteType,
    dots: u8,
    alignment_score: f32,
    measure_number: u32,
};

// Mock RestInfo structure from enhanced_note.zig
const RestInfo = struct {
    rest_data: ?Rest = null,
    is_optimized_rest: bool = false,
    original_duration: u32 = 0,
    alignment_score: f32 = 0.0,
};

// Mock TimedNote structure from measure_detector.zig
const TimedNote = struct {
    note: u8,
    channel: u8,
    velocity: u8,
    start_tick: u32,
    duration: u32,
};

// Mock EnhancedTimedNote structure
const EnhancedTimedNote = struct {
    base_note: TimedNote,
    rest_info: ?*RestInfo = null,
    rest_info_storage: ?RestInfo = null, // Internal storage to avoid allocator
    
    // Mock setRestInfo method
    fn setRestInfo(self: *EnhancedTimedNote, rest_info: RestInfo) !void {
        // Store directly without allocation for testing
        self.rest_info_storage = rest_info;
        self.rest_info = &self.rest_info_storage.?;
    }
};

// Mock EducationalProcessor structure
const EducationalProcessor = struct {
    // Empty - function doesn't use self
};

// ===== ORIGINAL FUNCTION =====
fn applyOptimizedRests_original(self: *EducationalProcessor, notes: []EnhancedTimedNote, optimized_rests: []Rest) !void {
    _ = self; // Suppress unused parameter warning
    
    // Find existing rest notes to update or mark for replacement
    for (notes) |*note| {
        if (note.base_note.velocity == 0) { // This is a rest note
            // Try to match with an optimized rest
            for (optimized_rests) |opt_rest| {
                // Check if this rest note should be replaced by the optimized rest
                if (note.base_note.start_tick >= opt_rest.start_time and 
                    note.base_note.start_tick < opt_rest.start_time + opt_rest.duration) {
                    
                    // Update the note's rest information
                    const rest_info = RestInfo{
                        .rest_data = opt_rest,
                        .is_optimized_rest = true,
                        .original_duration = note.base_note.duration,
                        .alignment_score = opt_rest.alignment_score,
                    };
                    
                    try note.setRestInfo(rest_info);
                    
                    // Update the base note duration if it's different
                    if (note.base_note.duration != opt_rest.duration) {
                        note.base_note.duration = opt_rest.duration;
                    }
                    break;
                }
            }
        }
    }
}

// ===== SIMPLIFIED FUNCTION =====
fn applyOptimizedRests(self: *EducationalProcessor, notes: []EnhancedTimedNote, optimized_rests: []Rest) !void {
    _ = self;
    
    for (notes) |*note| {
        if (note.base_note.velocity != 0) continue; // Skip non-rest notes
        
        const start = note.base_note.start_tick;
        for (optimized_rests) |opt_rest| {
            // Simplified overlap check
            if (start >= opt_rest.start_time and start < opt_rest.start_time + opt_rest.duration) {
                try note.setRestInfo(.{
                    .rest_data = opt_rest,
                    .is_optimized_rest = true,
                    .original_duration = note.base_note.duration,
                    .alignment_score = opt_rest.alignment_score,
                });
                note.base_note.duration = opt_rest.duration; // Always update
                break;
            }
        }
    }
}

// ===== TEST CASES =====

test "applyOptimizedRests - no rests in notes" {
    var processor = EducationalProcessor{};
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480 }},
        .{ .base_note = .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 480 }},
    };
    
    var optimized_rests = [_]Rest{
        .{ .start_time = 960, .duration = 240, .note_type = .quarter, .dots = 0, .alignment_score = 1.0, .measure_number = 1 },
    };
    
    try applyOptimizedRests(&processor, &notes, &optimized_rests);
    
    // No notes should have rest info since they have non-zero velocity
    try testing.expect(notes[0].rest_info == null);
    try testing.expect(notes[1].rest_info == null);
}

test "applyOptimizedRests - rest note gets optimized" {
    var processor = EducationalProcessor{};
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 0, .channel = 0, .velocity = 0, .start_tick = 100, .duration = 200 }},
    };
    
    var optimized_rests = [_]Rest{
        .{ .start_time = 100, .duration = 240, .note_type = .quarter, .dots = 0, .alignment_score = 0.8, .measure_number = 1 },
    };
    
    try applyOptimizedRests(&processor, &notes, &optimized_rests);
    
    // Rest note should have been optimized
    try testing.expect(notes[0].rest_info != null);
    try testing.expect(notes[0].rest_info.?.is_optimized_rest == true);
    try testing.expect(notes[0].rest_info.?.original_duration == 200);
    try testing.expect(notes[0].rest_info.?.alignment_score == 0.8);
    try testing.expect(notes[0].base_note.duration == 240); // Duration updated
}

test "applyOptimizedRests - multiple rests with partial overlap" {
    var processor = EducationalProcessor{};
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 0, .channel = 0, .velocity = 0, .start_tick = 50, .duration = 100 }},
        .{ .base_note = .{ .note = 0, .channel = 0, .velocity = 0, .start_tick = 150, .duration = 100 }},
        .{ .base_note = .{ .note = 0, .channel = 0, .velocity = 0, .start_tick = 400, .duration = 100 }}, // Changed to 400 to be outside range
    };
    
    var optimized_rests = [_]Rest{
        .{ .start_time = 0, .duration = 120, .note_type = .eighth, .dots = 0, .alignment_score = 0.5, .measure_number = 1 },
        .{ .start_time = 120, .duration = 240, .note_type = .quarter, .dots = 1, .alignment_score = 0.9, .measure_number = 1 },
    };
    
    try applyOptimizedRests(&processor, &notes, &optimized_rests);
    
    // First note overlaps with first optimized rest
    try testing.expect(notes[0].rest_info != null);
    try testing.expect(notes[0].rest_info.?.alignment_score == 0.5);
    
    // Second note overlaps with second optimized rest
    try testing.expect(notes[1].rest_info != null);
    try testing.expect(notes[1].rest_info.?.alignment_score == 0.9);
    
    // Third note doesn't overlap with any optimized rest (400 >= 360)
    try testing.expect(notes[2].rest_info == null);
}

test "applyOptimizedRests - rest at exact boundary" {
    var processor = EducationalProcessor{};
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 0, .channel = 0, .velocity = 0, .start_tick = 100, .duration = 50 }},
        .{ .base_note = .{ .note = 0, .channel = 0, .velocity = 0, .start_tick = 200, .duration = 50 }}, // At boundary
    };
    
    var optimized_rests = [_]Rest{
        .{ .start_time = 100, .duration = 100, .note_type = .eighth, .dots = 0, .alignment_score = 0.7, .measure_number = 1 },
    };
    
    try applyOptimizedRests(&processor, &notes, &optimized_rests);
    
    // First note should be optimized
    try testing.expect(notes[0].rest_info != null);
    
    // Second note at exact boundary (200 >= 200 is false in the condition)
    try testing.expect(notes[1].rest_info == null);
}

test "applyOptimizedRests - mixed notes and rests" {
    var processor = EducationalProcessor{};
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480 }},
        .{ .base_note = .{ .note = 0, .channel = 0, .velocity = 0, .start_tick = 480, .duration = 240 }},
        .{ .base_note = .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 720, .duration = 480 }},
        .{ .base_note = .{ .note = 0, .channel = 0, .velocity = 0, .start_tick = 1200, .duration = 240 }},
    };
    
    var optimized_rests = [_]Rest{
        .{ .start_time = 480, .duration = 240, .note_type = .quarter, .dots = 0, .alignment_score = 1.0, .measure_number = 1 },
        .{ .start_time = 1200, .duration = 480, .note_type = .half, .dots = 0, .alignment_score = 0.95, .measure_number = 2 },
    };
    
    try applyOptimizedRests(&processor, &notes, &optimized_rests);
    
    // Non-rest notes should not be affected
    try testing.expect(notes[0].rest_info == null);
    try testing.expect(notes[2].rest_info == null);
    
    // Rest notes should be optimized
    try testing.expect(notes[1].rest_info != null);
    try testing.expect(notes[1].rest_info.?.alignment_score == 1.0);
    try testing.expect(notes[1].base_note.duration == 240); // Duration unchanged
    
    try testing.expect(notes[3].rest_info != null);
    try testing.expect(notes[3].rest_info.?.alignment_score == 0.95);
    try testing.expect(notes[3].base_note.duration == 480); // Duration updated
}

// ===== MAIN FUNCTION FOR TESTING =====
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var processor = EducationalProcessor{};
    
    // Test scenario: Apply optimized rests to a mix of notes and rests
    var notes = try allocator.alloc(EnhancedTimedNote, 6);
    defer allocator.free(notes);
    
    notes[0] = .{ .base_note = .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480 }};
    notes[1] = .{ .base_note = .{ .note = 0, .channel = 0, .velocity = 0, .start_tick = 480, .duration = 240 }}; // Rest
    notes[2] = .{ .base_note = .{ .note = 62, .channel = 0, .velocity = 64, .start_tick = 720, .duration = 480 }};
    notes[3] = .{ .base_note = .{ .note = 0, .channel = 0, .velocity = 0, .start_tick = 1200, .duration = 240 }}; // Rest
    notes[4] = .{ .base_note = .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 1440, .duration = 480 }};
    notes[5] = .{ .base_note = .{ .note = 0, .channel = 0, .velocity = 0, .start_tick = 1920, .duration = 240 }}; // Rest
    
    var optimized_rests = try allocator.alloc(Rest, 3);
    defer allocator.free(optimized_rests);
    
    optimized_rests[0] = .{ .start_time = 480, .duration = 240, .note_type = .quarter, .dots = 0, .alignment_score = 1.0, .measure_number = 1 };
    optimized_rests[1] = .{ .start_time = 1200, .duration = 480, .note_type = .half, .dots = 0, .alignment_score = 0.95, .measure_number = 2 };
    optimized_rests[2] = .{ .start_time = 1920, .duration = 240, .note_type = .quarter, .dots = 0, .alignment_score = 0.85, .measure_number = 3 };
    
    std.debug.print("Before optimization:\n", .{});
    for (notes, 0..) |note, i| {
        if (note.base_note.velocity == 0) {
            std.debug.print("  Note {}: REST at tick {} duration {}\n", .{i, note.base_note.start_tick, note.base_note.duration});
        } else {
            std.debug.print("  Note {}: pitch {} at tick {} duration {}\n", .{i, note.base_note.note, note.base_note.start_tick, note.base_note.duration});
        }
    }
    
    try applyOptimizedRests(&processor, notes, optimized_rests);
    
    std.debug.print("\nAfter optimization:\n", .{});
    for (notes, 0..) |note, i| {
        if (note.base_note.velocity == 0) {
            if (note.rest_info) |rest_info| {
                std.debug.print("  Note {}: OPTIMIZED REST at tick {} duration {} (was {}) score {d:.2}\n", 
                    .{i, note.base_note.start_tick, note.base_note.duration, rest_info.original_duration, rest_info.alignment_score});
            } else {
                std.debug.print("  Note {}: REST at tick {} duration {} (not optimized)\n", 
                    .{i, note.base_note.start_tick, note.base_note.duration});
            }
        } else {
            std.debug.print("  Note {}: pitch {} at tick {} duration {}\n", 
                .{i, note.base_note.note, note.base_note.start_tick, note.base_note.duration});
        }
    }
    
    std.debug.print("\nFunction execution completed successfully!\n", .{});
}
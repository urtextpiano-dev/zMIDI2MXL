const std = @import("std");
const t = @import("../../src/test_utils.zig");
// Removed: const testing = std.testing;

// Mock structures needed for the function
const RestInfo = struct {
    rest_data: ?u32 = null,  // Simplified rest data
    is_optimized_rest: bool = false,
    original_duration: u32 = 0,
    alignment_score: f32 = 0.0,
};

const TimedNote = struct {
    start_tick: u32,
    duration: u32,
    pitch: u8,
    velocity: u8,
    voice: u8,
    measure_number: u32,
};

const EnhancedTimedNote = struct {
    base_note: TimedNote,
    rest_info: ?*RestInfo = null,
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

const EducationalProcessor = struct {
    dummy_field: u32 = 0,  // Just a placeholder field
    
    // ORIGINAL FUNCTION - exactly as extracted
    fn adjustRestPlacementForBeamConsistency(
        self: *EducationalProcessor,
        rest_span: RestSpan,
        enhanced_notes: []EnhancedTimedNote
    ) !void {
        _ = self;
        
        // Strategy: Split rest that inappropriately interrupts beam groups
        for (rest_span.note_indices.items) |idx| {
            const note = &enhanced_notes[idx];
            
            // Mark rest as needing re-optimization
            if (note.rest_info) |info| {
                // Reset optimization flag to force re-processing with beam awareness
                info.is_optimized_rest = false;
            }
        }
    }
};

// Test runner main function
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Testing adjustRestPlacementForBeamConsistency function\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});
    
    // Create test data
    var processor = EducationalProcessor{};
    
    // Create rest info structures
    var rest_info1 = RestInfo{ .is_optimized_rest = true };
    var rest_info2 = RestInfo{ .is_optimized_rest = true };
    var rest_info3 = RestInfo{ .is_optimized_rest = false };
    
    // Create enhanced notes with various configurations
    var enhanced_notes = [_]EnhancedTimedNote{
        .{ 
            .base_note = TimedNote{ 
                .start_tick = 0, 
                .duration = 480, 
                .pitch = 60, 
                .velocity = 0,  // Rest
                .voice = 1,
                .measure_number = 1
            },
            .rest_info = &rest_info1,
        },
        .{ 
            .base_note = TimedNote{ 
                .start_tick = 480, 
                .duration = 240, 
                .pitch = 64, 
                .velocity = 80,  // Normal note
                .voice = 1,
                .measure_number = 1
            },
            .rest_info = null,  // No rest info
        },
        .{ 
            .base_note = TimedNote{ 
                .start_tick = 720, 
                .duration = 480, 
                .pitch = 67, 
                .velocity = 0,  // Rest
                .voice = 1,
                .measure_number = 1
            },
            .rest_info = &rest_info2,
        },
        .{ 
            .base_note = TimedNote{ 
                .start_tick = 1200, 
                .duration = 240, 
                .pitch = 69, 
                .velocity = 0,  // Rest
                .voice = 1,
                .measure_number = 2
            },
            .rest_info = &rest_info3,
        },
    };
    
    // Create rest span with indices
    var note_indices = std.ArrayList(usize).init(allocator);
    defer note_indices.deinit();
    
    // Test Case 1: Process multiple rests
    try note_indices.append(0);  // Rest with optimized flag = true
    try note_indices.append(2);  // Rest with optimized flag = true
    try note_indices.append(3);  // Rest with optimized flag = false
    
    const rest_span = RestSpan{
        .start_tick = 0,
        .end_tick = 1440,
        .note_indices = note_indices,
        .is_optimized_rest = true,
    };
    
    std.debug.print("\nTest Case 1: Process multiple rests\n", .{});
    std.debug.print("Initial state:\n", .{});
    std.debug.print("  Note 0: rest_info.is_optimized_rest = {}\n", .{rest_info1.is_optimized_rest});
    std.debug.print("  Note 2: rest_info.is_optimized_rest = {}\n", .{rest_info2.is_optimized_rest});
    std.debug.print("  Note 3: rest_info.is_optimized_rest = {}\n", .{rest_info3.is_optimized_rest});
    
    // Call the function
    try processor.adjustRestPlacementForBeamConsistency(rest_span, &enhanced_notes);
    
    std.debug.print("After processing:\n", .{});
    std.debug.print("  Note 0: rest_info.is_optimized_rest = {}\n", .{rest_info1.is_optimized_rest});
    std.debug.print("  Note 2: rest_info.is_optimized_rest = {}\n", .{rest_info2.is_optimized_rest});
    std.debug.print("  Note 3: rest_info.is_optimized_rest = {}\n", .{rest_info3.is_optimized_rest});
    
    // Test Case 2: Process with index pointing to non-rest note
    var note_indices2 = std.ArrayList(usize).init(allocator);
    defer note_indices2.deinit();
    try note_indices2.append(1);  // This points to a note without rest_info
    
    const rest_span2 = RestSpan{
        .start_tick = 480,
        .end_tick = 720,
        .note_indices = note_indices2,
        .is_optimized_rest = false,
    };
    
    std.debug.print("\nTest Case 2: Process note without rest_info\n", .{});
    try processor.adjustRestPlacementForBeamConsistency(rest_span2, &enhanced_notes);
    std.debug.print("  No crash when processing note without rest_info\n", .{});
    
    // Test Case 3: Empty rest span
    var note_indices3 = std.ArrayList(usize).init(allocator);
    defer note_indices3.deinit();
    
    const rest_span3 = RestSpan{
        .start_tick = 0,
        .end_tick = 0,
        .note_indices = note_indices3,
        .is_optimized_rest = false,
    };
    
    std.debug.print("\nTest Case 3: Empty rest span\n", .{});
    try processor.adjustRestPlacementForBeamConsistency(rest_span3, &enhanced_notes);
    std.debug.print("  No crash with empty rest span\n", .{});
    
    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("All tests completed successfully!\n", .{});
}

// Unit tests
test "adjustRestPlacementForBeamConsistency resets optimization flag" {
    var processor = EducationalProcessor{};
    
    var rest_info = RestInfo{ .is_optimized_rest = true };
    var enhanced_notes = [_]EnhancedTimedNote{
        .{ 
            .base_note = TimedNote{ 
                .start_tick = 0, 
                .duration = 480, 
                .pitch = 60, 
                .velocity = 0,
                .voice = 1,
                .measure_number = 1
            },
            .rest_info = &rest_info,
        },
    };
    
    var note_indices = std.ArrayList(usize).init(testing.allocator);
    defer note_indices.deinit();
    try note_indices.append(0);
    
    const rest_span = RestSpan{
        .start_tick = 0,
        .end_tick = 480,
        .note_indices = note_indices,
        .is_optimized_rest = true,
    };
    
    try t.expect\1rest_info.is_optimized_rest == true);
    try processor.adjustRestPlacementForBeamConsistency(rest_span, &enhanced_notes);
    try t.expect\1rest_info.is_optimized_rest == false);
}

test "adjustRestPlacementForBeamConsistency handles null rest_info" {
    var processor = EducationalProcessor{};
    
    var enhanced_notes = [_]EnhancedTimedNote{
        .{ 
            .base_note = TimedNote{ 
                .start_tick = 0, 
                .duration = 480, 
                .pitch = 60, 
                .velocity = 80,
                .voice = 1,
                .measure_number = 1
            },
            .rest_info = null,
        },
    };
    
    var note_indices = std.ArrayList(usize).init(testing.allocator);
    defer note_indices.deinit();
    try note_indices.append(0);
    
    const rest_span = RestSpan{
        .start_tick = 0,
        .end_tick = 480,
        .note_indices = note_indices,
        .is_optimized_rest = false,
    };
    
    // Should not crash when rest_info is null
    try processor.adjustRestPlacementForBeamConsistency(rest_span, &enhanced_notes);
}

test "adjustRestPlacementForBeamConsistency processes multiple indices" {
    var processor = EducationalProcessor{};
    
    var rest_info1 = RestInfo{ .is_optimized_rest = true };
    var rest_info2 = RestInfo{ .is_optimized_rest = true };
    var rest_info3 = RestInfo{ .is_optimized_rest = false };
    
    var enhanced_notes = [_]EnhancedTimedNote{
        .{ 
            .base_note = TimedNote{ 
                .start_tick = 0, 
                .duration = 480, 
                .pitch = 60, 
                .velocity = 0,
                .voice = 1,
                .measure_number = 1
            },
            .rest_info = &rest_info1,
        },
        .{ 
            .base_note = TimedNote{ 
                .start_tick = 480, 
                .duration = 480, 
                .pitch = 64, 
                .velocity = 0,
                .voice = 1,
                .measure_number = 1
            },
            .rest_info = &rest_info2,
        },
        .{ 
            .base_note = TimedNote{ 
                .start_tick = 960, 
                .duration = 480, 
                .pitch = 67, 
                .velocity = 0,
                .voice = 1,
                .measure_number = 1
            },
            .rest_info = &rest_info3,
        },
    };
    
    var note_indices = std.ArrayList(usize).init(testing.allocator);
    defer note_indices.deinit();
    try note_indices.append(0);
    try note_indices.append(1);
    try note_indices.append(2);
    
    const rest_span = RestSpan{
        .start_tick = 0,
        .end_tick = 1440,
        .note_indices = note_indices,
        .is_optimized_rest = true,
    };
    
    try processor.adjustRestPlacementForBeamConsistency(rest_span, &enhanced_notes);
    
    // All should be reset to false
    try t.expect\1rest_info1.is_optimized_rest == false);
    try t.expect\1rest_info2.is_optimized_rest == false);
    try t.expect\1rest_info3.is_optimized_rest == false);
}

test "adjustRestPlacementForBeamConsistency handles empty indices" {
    var processor = EducationalProcessor{};
    
    var enhanced_notes = [_]EnhancedTimedNote{
        .{ 
            .base_note = TimedNote{ 
                .start_tick = 0, 
                .duration = 480, 
                .pitch = 60, 
                .velocity = 0,
                .voice = 1,
                .measure_number = 1
            },
            .rest_info = null,
        },
    };
    
    var note_indices = std.ArrayList(usize).init(testing.allocator);
    defer note_indices.deinit();
    
    const rest_span = RestSpan{
        .start_tick = 0,
        .end_tick = 480,
        .note_indices = note_indices,
        .is_optimized_rest = false,
    };
    
    // Should handle empty indices gracefully
    try processor.adjustRestPlacementForBeamConsistency(rest_span, &enhanced_notes);
}

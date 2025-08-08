const std = @import("std");
const testing = std.testing;

// Required structs from the original codebase
pub const TimedNote = struct {
    note: u8,
    channel: u8,
    velocity: u8,
    start_tick: u32,
    duration: u32,
    
    // Add track field that's used in the actual implementation
    track: u8 = 0,
    
    // Add voice field that's also used
    voice: u8 = 0,
};

pub const ChordGroup = struct {
    start_time: u32,
    notes: []TimedNote,
    staff_assignment: u8,
    tracks_involved: []u8,
    is_cross_track: bool,
    
    // ORIGINAL FUNCTION (4 lines)
    pub fn deinit(self: *ChordGroup, allocator: std.mem.Allocator) void {
        allocator.free(self.notes);
        allocator.free(self.tracks_involved);
    }
};

// Test helper to create a ChordGroup
fn createTestChordGroup(allocator: std.mem.Allocator) !ChordGroup {
    var notes = try allocator.alloc(TimedNote, 3);
    notes[0] = TimedNote{
        .note = 60,
        .channel = 0,
        .velocity = 80,
        .start_tick = 0,
        .duration = 480,
        .track = 0,
        .voice = 1,
    };
    notes[1] = TimedNote{
        .note = 64,
        .channel = 0,
        .velocity = 80,
        .start_tick = 0,
        .duration = 480,
        .track = 0,
        .voice = 1,
    };
    notes[2] = TimedNote{
        .note = 67,
        .channel = 0,
        .velocity = 80,
        .start_tick = 0,
        .duration = 480,
        .track = 1,
        .voice = 2,
    };
    
    var tracks = try allocator.alloc(u8, 2);
    tracks[0] = 0;
    tracks[1] = 1;
    
    return ChordGroup{
        .start_time = 0,
        .notes = notes,
        .staff_assignment = 1,
        .tracks_involved = tracks,
        .is_cross_track = true,
    };
}

// Unit tests
test "deinit frees notes array" {
    const allocator = testing.allocator;
    
    var chord = try createTestChordGroup(allocator);
    chord.deinit(allocator);
    
    // If this test completes without memory leaks, the deinit worked
    // The testing allocator will detect any leaks
}

test "deinit frees tracks_involved array" {
    const allocator = testing.allocator;
    
    var chord = try createTestChordGroup(allocator);
    chord.deinit(allocator);
    
    // Same as above - testing allocator validates proper freeing
}

test "deinit handles empty arrays" {
    const allocator = testing.allocator;
    
    var chord = ChordGroup{
        .start_time = 0,
        .notes = try allocator.alloc(TimedNote, 0),
        .staff_assignment = 1,
        .tracks_involved = try allocator.alloc(u8, 0),
        .is_cross_track = false,
    };
    
    chord.deinit(allocator);
    // Should handle empty arrays without issues
}

test "deinit with large arrays" {
    const allocator = testing.allocator;
    
    const notes = try allocator.alloc(TimedNote, 1000);
    for (notes, 0..) |*note, i| {
        note.* = TimedNote{
            .note = @intCast(60 + (i % 12)),
            .channel = 0,
            .velocity = 80,
            .start_tick = @intCast(i * 10),
            .duration = 480,
            .track = @intCast(i % 4),
            .voice = @intCast(1 + (i % 4)),
        };
    }
    
    const tracks = try allocator.alloc(u8, 4);
    for (tracks, 0..) |*track, i| {
        track.* = @intCast(i);
    }
    
    var chord = ChordGroup{
        .start_time = 0,
        .notes = notes,
        .staff_assignment = 1,
        .tracks_involved = tracks,
        .is_cross_track = true,
    };
    
    chord.deinit(allocator);
    // Should handle large arrays efficiently
}

test "multiple deinit calls in sequence" {
    const allocator = testing.allocator;
    
    // Create multiple ChordGroups
    var chords: [5]ChordGroup = undefined;
    
    for (&chords) |*chord| {
        chord.* = try createTestChordGroup(allocator);
    }
    
    // Deinit all of them
    for (&chords) |*chord| {
        chord.deinit(allocator);
    }
    
    // Should handle multiple deallocations correctly
}

// Main function for demonstration
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== Testing deinit function ===\n", .{});
    
    // Test 1: Basic deallocation
    {
        var chord = try createTestChordGroup(allocator);
        std.debug.print("Created ChordGroup with {} notes and {} tracks\n", .{
            chord.notes.len,
            chord.tracks_involved.len,
        });
        
        chord.deinit(allocator);
        std.debug.print("Successfully deallocated ChordGroup\n", .{});
    }
    
    // Test 2: Empty arrays
    {
        var chord = ChordGroup{
            .start_time = 0,
            .notes = try allocator.alloc(TimedNote, 0),
            .staff_assignment = 1,
            .tracks_involved = try allocator.alloc(u8, 0),
            .is_cross_track = false,
        };
        
        std.debug.print("Created ChordGroup with empty arrays\n", .{});
        chord.deinit(allocator);
        std.debug.print("Successfully deallocated empty ChordGroup\n", .{});
    }
    
    // Test 3: Large arrays
    {
        const notes = try allocator.alloc(TimedNote, 100);
        for (notes, 0..) |*note, i| {
            note.* = TimedNote{
                .note = @intCast(60 + (i % 12)),
                .channel = 0,
                .velocity = 80,
                .start_tick = @intCast(i * 10),
                .duration = 480,
                .track = @intCast(i % 4),
                .voice = @intCast(1 + (i % 4)),
            };
        }
        
        const tracks = try allocator.alloc(u8, 4);
        for (tracks, 0..) |*track, i| {
            track.* = @intCast(i);
        }
        
        var chord = ChordGroup{
            .start_time = 0,
            .notes = notes,
            .staff_assignment = 1,
            .tracks_involved = tracks,
            .is_cross_track = true,
        };
        
        std.debug.print("Created ChordGroup with {} notes and {} tracks\n", .{
            chord.notes.len,
            chord.tracks_involved.len,
        });
        
        chord.deinit(allocator);
        std.debug.print("Successfully deallocated large ChordGroup\n", .{});
    }
    
    std.debug.print("\nAll deallocation tests passed!\n", .{});
}
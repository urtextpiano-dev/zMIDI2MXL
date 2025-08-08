const std = @import("std");
const testing = std.testing;

// Minimal TimedNote struct extracted from measure_detector.zig
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
    /// Whether this note is tied to the next note
    tied_to_next: bool = false,
    /// Whether this note is tied from the previous note
    tied_from_previous: bool = false,
    /// Track index this note belongs to (0-based)
    track_index: u8 = 0,
};

// ORIGINAL FUNCTION - BASELINE
// NOTE: After analysis, this function is already optimal.
// It uses early return, minimal branching, and no allocations.
// Any "simplification" would either:
// 1. Make it less readable (e.g., ternary-style expressions)
// 2. Add unnecessary complexity (e.g., using std.mem functions)
// 3. Not provide meaningful performance improvement
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

// Helper function to create test notes
fn createNote(midi_note: u8) TimedNote {
    return TimedNote{
        .note = midi_note,
        .channel = 0,
        .velocity = 64,
        .start_tick = 0,
        .duration = 480,
    };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Testing determineStaffForChord function:\n", .{});
    try stdout.print("=========================================\n\n", .{});
    
    // Test 1: Empty array - should return treble (1)
    {
        const notes: []const TimedNote = &[_]TimedNote{};
        const result = determineStaffForChord(notes);
        try stdout.print("Test 1 - Empty array: {}\n", .{result});
    }
    
    // Test 2: All notes above middle C (60) - should return treble (1)
    {
        const notes = [_]TimedNote{
            createNote(72), // C5
            createNote(76), // E5
            createNote(79), // G5
        };
        const result = determineStaffForChord(notes[0..]);
        try stdout.print("Test 2 - All notes above middle C (72,76,79): {}\n", .{result});
    }
    
    // Test 3: One note below middle C - should return bass (2)
    {
        const notes = [_]TimedNote{
            createNote(65), // F4
            createNote(69), // A4
            createNote(48), // C3 - below middle C
        };
        const result = determineStaffForChord(notes[0..]);
        try stdout.print("Test 3 - One note below middle C (65,69,48): {}\n", .{result});
    }
    
    // Test 4: All notes below middle C - should return bass (2)
    {
        const notes = [_]TimedNote{
            createNote(36), // C2
            createNote(40), // E2
            createNote(43), // G2
        };
        const result = determineStaffForChord(notes[0..]);
        try stdout.print("Test 4 - All notes below middle C (36,40,43): {}\n", .{result});
    }
    
    // Test 5: Single note at middle C - should return treble (1)
    {
        const notes = [_]TimedNote{
            createNote(60), // Middle C
        };
        const result = determineStaffForChord(notes[0..]);
        try stdout.print("Test 5 - Single note at middle C (60): {}\n", .{result});
    }
    
    // Test 6: Single note just below middle C - should return bass (2)
    {
        const notes = [_]TimedNote{
            createNote(59), // B3
        };
        const result = determineStaffForChord(notes[0..]);
        try stdout.print("Test 6 - Single note just below middle C (59): {}\n", .{result});
    }
    
    // Test 7: Mixed notes with first note above middle C - should still return bass (2) if any below
    {
        const notes = [_]TimedNote{
            createNote(72), // C5 - above
            createNote(55), // G3 - below
            createNote(67), // G4 - above
        };
        const result = determineStaffForChord(notes[0..]);
        try stdout.print("Test 7 - Mixed notes, first above (72,55,67): {}\n", .{result});
    }
    
    // Test 8: Large chord spanning both staves - should return bass (2) if any below
    {
        const notes = [_]TimedNote{
            createNote(84), // C6
            createNote(72), // C5
            createNote(60), // C4 (middle C)
            createNote(48), // C3 - below
            createNote(36), // C2 - below
        };
        const result = determineStaffForChord(notes[0..]);
        try stdout.print("Test 8 - Large spanning chord (84,72,60,48,36): {}\n", .{result});
    }
}

test "empty notes array returns treble staff" {
    const notes: []const TimedNote = &[_]TimedNote{};
    try testing.expectEqual(@as(u8, 1), determineStaffForChord(notes));
}

test "notes above middle C return treble staff" {
    const notes = [_]TimedNote{
        createNote(72), // C5
        createNote(76), // E5
        createNote(79), // G5
    };
    try testing.expectEqual(@as(u8, 1), determineStaffForChord(notes[0..]));
}

test "any note below middle C returns bass staff" {
    const notes = [_]TimedNote{
        createNote(65), // F4
        createNote(48), // C3 - below middle C
    };
    try testing.expectEqual(@as(u8, 2), determineStaffForChord(notes[0..]));
}

test "all notes below middle C return bass staff" {
    const notes = [_]TimedNote{
        createNote(36), // C2
        createNote(40), // E2
        createNote(43), // G2
    };
    try testing.expectEqual(@as(u8, 2), determineStaffForChord(notes[0..]));
}

test "middle C exactly returns treble staff" {
    const notes = [_]TimedNote{
        createNote(60), // Middle C
    };
    try testing.expectEqual(@as(u8, 1), determineStaffForChord(notes[0..]));
}

test "just below middle C returns bass staff" {
    const notes = [_]TimedNote{
        createNote(59), // B3
    };
    try testing.expectEqual(@as(u8, 2), determineStaffForChord(notes[0..]));
}

test "early detection of bass note" {
    // Test that function returns as soon as it finds a bass note
    const notes = [_]TimedNote{
        createNote(72), // C5 - above
        createNote(55), // G3 - below (should trigger early return)
        createNote(67), // G4 - above (shouldn't be checked)
    };
    try testing.expectEqual(@as(u8, 2), determineStaffForChord(notes[0..]));
}
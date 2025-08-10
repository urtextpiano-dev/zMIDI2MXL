const std = @import("std");
const t = @import("../../src/test_utils.zig");
const print = std.debug.print;

// Mock Arena Allocator
const MockArena = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }
    
    pub fn allocForEducational(self: *Self, comptime T: type, count: usize) ![]T {
        return self.allocator.alloc(T, count);
    }
    
    pub fn beginPhase(self: *Self, phase: anytype) void {
        _ = self;
        _ = phase;
    }
    
    pub fn endPhase(self: *Self) void {
        _ = self;
    }
};

// Mock stem_direction module
const stem_direction = struct {
    pub const StemDirection = enum {
        up,
        down,
        none,
    };
    
    pub const StaffPosition = struct {
        line: i8,
        spaces: i8,
        
        pub fn fromMidiNote(midi_note: u8) StaffPosition {
            const middle_line_midi: i16 = 71; // B4
            const midi_offset = @as(i16, midi_note) - middle_line_midi;
            
            if (midi_offset >= -1 and midi_offset <= 1) {
                return StaffPosition{ .line = 3, .spaces = 0 };
            } else if (midi_offset > 1) {
                const lines_above = @divFloor(midi_offset + 1, 2);
                return StaffPosition{ .line = 3 + @as(i8, @intCast(lines_above)), .spaces = 0 };
            } else {
                const lines_below = @divFloor(-midi_offset + 1, 2);
                return StaffPosition{ .line = 3 - @as(i8, @intCast(lines_below)), .spaces = 0 };
            }
        }
    };
    
    pub const StemDirectionCalculator = struct {
        pub fn calculateStemDirection(
            midi_note: u8,
            voice: u8,
            beam_group_notes: ?[]const u8,
        ) StemDirection {
            _ = beam_group_notes;
            
            // Basic stem direction rule: below middle line (B4 = 71) = up, at or above = down
            if (midi_note < 71) {
                return .up;
            } else if (midi_note == 71) {
                // Voice-based rule for middle line
                return if (voice <= 2) .up else .down;
            } else {
                return .down;
            }
        }
    };
};

// Mock enhanced_note module
const enhanced_note = struct {
    pub const EnhancedNoteError = error{
        AllocationFailure,
        InvalidConversion,
        NullArena,
        IncompatibleMetadata,
    };
    
    pub const StemInfo = struct {
        direction: stem_direction.StemDirection = .none,
        beam_influenced: bool = false,
        voice: u8 = 1,
        in_beam_group: bool = false,
        beam_group_id: ?u32 = null,
        staff_position: ?stem_direction.StaffPosition = null,
    };
    
    pub const TimedNote = struct {
        note: u8,
        channel: u8,
        velocity: u8,
        start_tick: u32,
        duration: u32,
        tied_to_next: bool = false,
        tied_from_previous: bool = false,
        track: u8 = 0,
    };
    
    pub const EnhancedTimedNote = struct {
        base_note: TimedNote,
        stem_info: ?*StemInfo = null,
        arena: ?*MockArena = null,
        
        pub fn setStemInfo(self: *EnhancedTimedNote, stem_info: StemInfo) EnhancedNoteError!void {
            if (self.arena == null) return EnhancedNoteError.NullArena;
            
            if (self.stem_info == null) {
                self.arena.?.beginPhase(.coordination);
                defer self.arena.?.endPhase();
                
                const allocated_info = self.arena.?.allocForEducational(StemInfo, 1) catch {
                    return EnhancedNoteError.AllocationFailure;
                };
                self.stem_info = &allocated_info[0];
            }
            
            self.stem_info.?.* = stem_info;
        }
    };
};

// Mock BeamGroupInfo
const BeamGroupInfo = struct {
    group_id: u32,
    notes: []enhanced_note.EnhancedTimedNote,
    start_tick: u32,
    end_tick: u32,
};

// Mock EducationalProcessor and Error
const EducationalProcessingError = error{
    AllocationFailure,
    ArenaNotInitialized,
    CoordinationConflict,
};

const EducationalProcessor = struct {
    arena: *MockArena,
    
    // SIMPLIFIED FUNCTION
    fn calculateAndSetStemDirection(
        self: *EducationalProcessor,
        note: *enhanced_note.EnhancedTimedNote,
        beam_groups: []const BeamGroupInfo
    ) EducationalProcessingError!void {
        const midi_note = note.base_note.note;
        const voice: u8 = @intCast(note.base_note.channel + 1);
        
        // Find matching beam group using single-pass search
        const BeamInfo = struct { notes: ?[]u8, id: ?u32 };
        const beam_info: BeamInfo = blk: {
            for (beam_groups) |beam_group| {
                for (beam_group.notes) |beam_note| {
                    if (beam_note.base_note.start_tick == note.base_note.start_tick and 
                        beam_note.base_note.note == midi_note) {
                        // Found beam group - collect notes and return
                        const beam_notes = self.arena.allocForEducational(u8, beam_group.notes.len) catch {
                            return EducationalProcessingError.AllocationFailure;
                        };
                        for (beam_group.notes, 0..) |group_note, i| {
                            beam_notes[i] = group_note.base_note.note;
                        }
                        break :blk BeamInfo{ .notes = beam_notes, .id = beam_group.group_id };
                    }
                }
            }
            break :blk BeamInfo{ .notes = null, .id = null };
        };
        
        const stem_info = enhanced_note.StemInfo{
            .direction = stem_direction.StemDirectionCalculator.calculateStemDirection(
                midi_note,
                voice,
                beam_info.notes
            ),
            .beam_influenced = beam_info.notes != null,
            .voice = voice,
            .in_beam_group = beam_info.notes != null,
            .beam_group_id = beam_info.id,
            .staff_position = stem_direction.StaffPosition.fromMidiNote(midi_note),
        };
        
        note.setStemInfo(stem_info) catch |err| {
            return switch (err) {
                enhanced_note.EnhancedNoteError.AllocationFailure => EducationalProcessingError.AllocationFailure,
                enhanced_note.EnhancedNoteError.NullArena => EducationalProcessingError.ArenaNotInitialized,
                enhanced_note.EnhancedNoteError.InvalidConversion,
                enhanced_note.EnhancedNoteError.IncompatibleMetadata => EducationalProcessingError.CoordinationConflict,
            };
        };
    }
};

fn testCalculateAndSetStemDirection() !void {
    print("=== Testing calculateAndSetStemDirection ===\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var arena = MockArena.init(allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    // Test Case 1: Single note, no beam group, below middle line (should be up)
    {
        print("Test 1: Single note below middle line (C4, midi=60)\n", .{});
        
        var note = enhanced_note.EnhancedTimedNote{
            .base_note = enhanced_note.TimedNote{
                .note = 60, // C4
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
            },
            .arena = &arena,
        };
        
        const beam_groups: []const BeamGroupInfo = &.{};
        
        try processor.calculateAndSetStemDirection(&note, beam_groups);
        
        t.expect(note.stem_info != null) catch |err| {
            print("ERROR: stem_info should not be null: {}\n", .{err});
            return err;
        };
        
        const stem_info = note.stem_info.?;
        print("Result: direction={}, voice={}, in_beam_group={}\n", 
            .{stem_info.direction, stem_info.voice, stem_info.in_beam_group});
        
        t.expect(stem_info.direction == .up) catch |err| {
            print("ERROR: Expected .up, got {}\n", .{stem_info.direction});
            return err;
        };
        t.expect(stem_info.voice == 1) catch |err| {
            print("ERROR: Expected voice 1, got {}\n", .{stem_info.voice});
            return err;
        };
        t.expect(!stem_info.in_beam_group) catch |err| {
            print("ERROR: Expected not in beam group\n", .{});
            return err;
        };
        
        print("✓ Test 1 passed\n\n", .{});
    }
    
    // Test Case 2: Single note, no beam group, above middle line (should be down)
    {
        print("Test 2: Single note above middle line (C5, midi=72)\n", .{});
        
        var note = enhanced_note.EnhancedTimedNote{
            .base_note = enhanced_note.TimedNote{
                .note = 72, // C5
                .channel = 1,
                .velocity = 64,
                .start_tick = 480,
                .duration = 480,
            },
            .arena = &arena,
        };
        
        const beam_groups: []const BeamGroupInfo = &.{};
        
        try processor.calculateAndSetStemDirection(&note, beam_groups);
        
        const stem_info = note.stem_info.?;
        print("Result: direction={}, voice={}, in_beam_group={}\n", 
            .{stem_info.direction, stem_info.voice, stem_info.in_beam_group});
        
        t.expect(stem_info.direction == .down) catch |err| {
            print("ERROR: Expected .down, got {}\n", .{stem_info.direction});
            return err;
        };
        t.expect(stem_info.voice == 2) catch |err| {
            print("ERROR: Expected voice 2, got {}\n", .{stem_info.voice});
            return err;
        };
        
        print("✓ Test 2 passed\n\n", .{});
    }
    
    // Test Case 3: Note in beam group
    {
        print("Test 3: Note in beam group\n", .{});
        
        var note1 = enhanced_note.EnhancedTimedNote{
            .base_note = enhanced_note.TimedNote{
                .note = 67, // G4
                .channel = 0,
                .velocity = 64,
                .start_tick = 960,
                .duration = 240,
            },
            .arena = &arena,
        };
        
        const note2 = enhanced_note.EnhancedTimedNote{
            .base_note = enhanced_note.TimedNote{
                .note = 69, // A4
                .channel = 0,
                .velocity = 64,
                .start_tick = 1200,
                .duration = 240,
            },
            .arena = &arena,
        };
        
        const beam_notes = try allocator.alloc(enhanced_note.EnhancedTimedNote, 2);
        defer allocator.free(beam_notes);
        beam_notes[0] = note1;
        beam_notes[1] = note2;
        
        const beam_group = BeamGroupInfo{
            .group_id = 1,
            .notes = beam_notes,
            .start_tick = 960,
            .end_tick = 1440,
        };
        
        const beam_groups = [_]BeamGroupInfo{beam_group};
        
        try processor.calculateAndSetStemDirection(&note1, &beam_groups);
        
        const stem_info = note1.stem_info.?;
        print("Result: direction={}, voice={}, in_beam_group={}, beam_group_id={?}\n", 
            .{stem_info.direction, stem_info.voice, stem_info.in_beam_group, stem_info.beam_group_id});
        
        t.expect(stem_info.in_beam_group) catch |err| {
            print("ERROR: Expected to be in beam group\n", .{});
            return err;
        };
        t.expect(stem_info.beam_group_id == 1) catch |err| {
            print("ERROR: Expected beam_group_id 1, got {?}\n", .{stem_info.beam_group_id});
            return err;
        };
        
        print("✓ Test 3 passed\n\n", .{});
    }
    
    // Test Case 4: Middle line note with voice-based decision
    {
        print("Test 4: Middle line note (B4, midi=71) with different voices\n", .{});
        
        // Voice 1 (should be up)
        var note_v1 = enhanced_note.EnhancedTimedNote{
            .base_note = enhanced_note.TimedNote{
                .note = 71, // B4 (middle line)
                .channel = 0, // voice 1
                .velocity = 64,
                .start_tick = 1440,
                .duration = 480,
            },
            .arena = &arena,
        };
        
        const beam_groups: []const BeamGroupInfo = &.{};
        try processor.calculateAndSetStemDirection(&note_v1, beam_groups);
        
        const stem_info_v1 = note_v1.stem_info.?;
        print("Voice 1 result: direction={}\n", .{stem_info_v1.direction});
        
        t.expect(stem_info_v1.direction == .up) catch |err| {
            print("ERROR: Expected voice 1 middle line to be .up, got {}\n", .{stem_info_v1.direction});
            return err;
        };
        
        // Voice 3 (should be down)
        var note_v3 = enhanced_note.EnhancedTimedNote{
            .base_note = enhanced_note.TimedNote{
                .note = 71, // B4 (middle line)
                .channel = 2, // voice 3
                .velocity = 64,
                .start_tick = 1920,
                .duration = 480,
            },
            .arena = &arena,
        };
        
        try processor.calculateAndSetStemDirection(&note_v3, beam_groups);
        
        const stem_info_v3 = note_v3.stem_info.?;
        print("Voice 3 result: direction={}\n", .{stem_info_v3.direction});
        
        t.expect(stem_info_v3.direction == .down) catch |err| {
            print("ERROR: Expected voice 3 middle line to be .down, got {}\n", .{stem_info_v3.direction});
            return err;
        };
        
        print("✓ Test 4 passed\n\n", .{});
    }
    
    print("=== All tests passed! ===\n", .{});
}

// Unit Tests
test "calculateAndSetStemDirection basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var arena = MockArena.init(allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    var note = enhanced_note.EnhancedTimedNote{
        .base_note = enhanced_note.TimedNote{
            .note = 60,
            .channel = 0,
            .velocity = 64,
            .start_tick = 0,
            .duration = 480,
        },
        .arena = &arena,
    };
    
    const beam_groups: []const BeamGroupInfo = &.{};
    try processor.calculateAndSetStemDirection(&note, beam_groups);
    
    try t.expect(note.stem_info != null);
    try t.expect(note.stem_info.?.direction == .up);
}

test "calculateAndSetStemDirection beam group detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var arena = MockArena.init(allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    var note = enhanced_note.EnhancedTimedNote{
        .base_note = enhanced_note.TimedNote{
            .note = 67,
            .channel = 0,
            .velocity = 64,
            .start_tick = 960,
            .duration = 240,
        },
        .arena = &arena,
    };
    
    const beam_notes = try allocator.alloc(enhanced_note.EnhancedTimedNote, 1);
    defer allocator.free(beam_notes);
    beam_notes[0] = note;
    
    const beam_group = BeamGroupInfo{
        .group_id = 1,
        .notes = beam_notes,
        .start_tick = 960,
        .end_tick = 1200,
    };
    
    const beam_groups = [_]BeamGroupInfo{beam_group};
    try processor.calculateAndSetStemDirection(&note, &beam_groups);
    
    try t.expect(note.stem_info != null);
    try t.expect(note.stem_info.?.in_beam_group);
    try t.expect(note.stem_info.?.beam_group_id == 1);
}

test "calculateAndSetStemDirection error handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var arena = MockArena.init(allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    // Test with null arena
    var note = enhanced_note.EnhancedTimedNote{
        .base_note = enhanced_note.TimedNote{
            .note = 60,
            .channel = 0,
            .velocity = 64,
            .start_tick = 0,
            .duration = 480,
        },
        .arena = null, // This should cause error
    };
    
    const beam_groups: []const BeamGroupInfo = &.{};
    const result = processor.calculateAndSetStemDirection(&note, beam_groups);
    
    try t.expect(result == EducationalProcessingError.ArenaNotInitialized);
}

test "calculateAndSetStemDirection voice calculation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var arena = MockArena.init(allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    var note = enhanced_note.EnhancedTimedNote{
        .base_note = enhanced_note.TimedNote{
            .note = 60,
            .channel = 3, // Should become voice 4
            .velocity = 64,
            .start_tick = 0,
            .duration = 480,
        },
        .arena = &arena,
    };
    
    const beam_groups: []const BeamGroupInfo = &.{};
    try processor.calculateAndSetStemDirection(&note, beam_groups);
    
    try t.expect(note.stem_info != null);
    try t.expect(note.stem_info.?.voice == 4);
}

test "calculateAndSetStemDirection staff position" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var arena = MockArena.init(allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    var note = enhanced_note.EnhancedTimedNote{
        .base_note = enhanced_note.TimedNote{
            .note = 71, // B4 (middle line)
            .channel = 0,
            .velocity = 64,
            .start_tick = 0,
            .duration = 480,
        },
        .arena = &arena,
    };
    
    const beam_groups: []const BeamGroupInfo = &.{};
    try processor.calculateAndSetStemDirection(&note, beam_groups);
    
    try t.expect(note.stem_info != null);
    try t.expect(note.stem_info.?.staff_position != null);
    try t.expect(note.stem_info.?.staff_position.?.line == 3);
}

test "calculateAndSetStemDirection direction rules" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var arena = MockArena.init(allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
    };
    
    const beam_groups: []const BeamGroupInfo = &.{};
    
    // Test below middle line (should be up)
    var note_low = enhanced_note.EnhancedTimedNote{
        .base_note = enhanced_note.TimedNote{
            .note = 60, // C4
            .channel = 0,
            .velocity = 64,
            .start_tick = 0,
            .duration = 480,
        },
        .arena = &arena,
    };
    try processor.calculateAndSetStemDirection(&note_low, beam_groups);
    try t.expect(note_low.stem_info.?.direction == .up);
    
    // Test above middle line (should be down)
    var note_high = enhanced_note.EnhancedTimedNote{
        .base_note = enhanced_note.TimedNote{
            .note = 72, // C5
            .channel = 0,
            .velocity = 64,
            .start_tick = 480,
            .duration = 480,
        },
        .arena = &arena,
    };
    try processor.calculateAndSetStemDirection(&note_high, beam_groups);
    try t.expect(note_high.stem_info.?.direction == .down);
}

pub fn main() !void {
    try testCalculateAndSetStemDirection();
}

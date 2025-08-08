const std = @import("std");
const parser = @import("parser.zig");
const error_mod = @import("../error.zig");

// Implements TASK-029 per MXL_Architecture_Reference.md Section 4.3 lines 416-435
// Multi-Track Support - Track to part mapping and multi-part structure generation
//
// This module provides structures and logic for managing multiple MIDI tracks
// and converting them to MusicXML parts with proper part-list structure.
// Performance target: Linear scaling with tracks

/// Track information for multi-track MIDI files
pub const TrackInfo = struct {
    track_index: u16,                    // Original MIDI track index (0-based)
    track_name: ?[]const u8,             // Track name from meta events (if any)
    instrument_name: ?[]const u8,        // Instrument name from meta events
    channel_mask: u16,                   // Bitmask of channels used in this track
    note_count: u32,                     // Number of note events in track
    has_percussion: bool,                // True if track uses channel 9 (drums)
    
    /// Check if track uses a specific MIDI channel
    pub fn usesChannel(self: TrackInfo, channel: u4) bool {
        return (self.channel_mask & (@as(u16, 1) << channel)) != 0;
    }
    
    /// Add a channel to the track's channel mask
    pub fn addChannel(self: *TrackInfo, channel: u4) void {
        self.channel_mask |= @as(u16, 1) << channel;
        if (channel == 9) {
            self.has_percussion = true;
        }
    }
    
    /// Get count of unique channels used
    pub fn getChannelCount(self: TrackInfo) u8 {
        return @popCount(self.channel_mask);
    }
};

/// Part information for MusicXML generation
pub const PartInfo = struct {
    part_id: []const u8,                 // MusicXML part ID (e.g., "P1", "P2")
    part_name: []const u8,               // Display name for the part
    part_abbreviation: ?[]const u8,      // Abbreviated name (optional)
    midi_channel: ?u4,                   // Primary MIDI channel (if single channel)
    midi_program: ?u8,                   // MIDI program number (if set)
    track_indices: std.ArrayList(u16),   // Source MIDI track indices
    is_percussion: bool,                 // True for percussion parts
    
    pub fn init(allocator: std.mem.Allocator, id: []const u8, name: []const u8) !PartInfo {
        const id_copy = try allocator.dupe(u8, id);
        const name_copy = try allocator.dupe(u8, name);
        
        return PartInfo{
            .part_id = id_copy,
            .part_name = name_copy,
            .part_abbreviation = null,
            .midi_channel = null,
            .midi_program = null,
            .track_indices = std.ArrayList(u16).init(allocator),
            .is_percussion = false,
        };
    }
    
    pub fn deinit(self: *PartInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.part_id);
        allocator.free(self.part_name);
        if (self.part_abbreviation) |abbr| {
            allocator.free(abbr);
        }
        self.track_indices.deinit();
    }
    
    /// Add a track to this part
    pub fn addTrack(self: *PartInfo, track_index: u16) !void {
        try self.track_indices.append(track_index);
    }
};

/// Multi-track container for managing multiple MIDI tracks
pub const MultiTrackContainer = struct {
    allocator: std.mem.Allocator,
    tracks: std.ArrayList(parser.TrackParseResult),
    track_info: std.ArrayList(TrackInfo),
    parts: std.ArrayList(PartInfo),
    format: parser.MidiFormat,
    division: u16,
    
    pub fn init(allocator: std.mem.Allocator, format: parser.MidiFormat, division: u16) MultiTrackContainer {
        return .{
            .allocator = allocator,
            .tracks = std.ArrayList(parser.TrackParseResult).init(allocator),
            .track_info = std.ArrayList(TrackInfo).init(allocator),
            .parts = std.ArrayList(PartInfo).init(allocator),
            .format = format,
            .division = division,
        };
    }
    
    pub fn deinit(self: *MultiTrackContainer) void {
        // Deinit all tracks
        for (self.tracks.items) |*track| {
            track.deinit(self.allocator);
        }
        self.tracks.deinit();
        
        // Free track info strings
        for (self.track_info.items) |*info| {
            if (info.track_name) |name| {
                self.allocator.free(name);
            }
            if (info.instrument_name) |name| {
                self.allocator.free(name);
            }
        }
        self.track_info.deinit();
        
        // Deinit all parts
        for (self.parts.items) |*part| {
            part.deinit(self.allocator);
        }
        self.parts.deinit();
    }
    
    /// Add a parsed track to the container
    pub fn addTrack(self: *MultiTrackContainer, track: parser.TrackParseResult) !void {
        const track_index = self.tracks.items.len;
        try self.tracks.append(track);
        
        // Create track info
        var info = TrackInfo{
            .track_index = @intCast(track_index),
            .track_name = null,
            .instrument_name = null,
            .channel_mask = 0,
            .note_count = @intCast(track.note_events.items.len),
            .has_percussion = false,
        };
        
        // Extract track name from text events
        for (track.text_events.items) |text_event| {
            if (text_event.event_type == @intFromEnum(parser.TextEvent.TextType.track_name) and info.track_name == null) {
                info.track_name = try self.allocator.dupe(u8, text_event.text);
            } else if (text_event.event_type == @intFromEnum(parser.TextEvent.TextType.instrument_name) and info.instrument_name == null) {
                info.instrument_name = try self.allocator.dupe(u8, text_event.text);
            }
        }
        
        // Analyze channel usage
        for (track.note_events.items) |note_event| {
            info.addChannel(note_event.channel);
        }
        
        try self.track_info.append(info);
    }
    
    /// Create parts from tracks based on the MIDI format
    /// Implements the track-to-part mapping logic
    pub fn createParts(self: *MultiTrackContainer) !void {
        // Clear existing parts
        for (self.parts.items) |*part| {
            part.deinit(self.allocator);
        }
        self.parts.clearRetainingCapacity();
        
        switch (self.format) {
            .single_track => {
                // Format 0: Create parts based on channels
                try self.createPartsFromChannels();
            },
            .multi_track_sync => {
                // Format 1: Create one part per track (excluding conductor track)
                try self.createPartsFromTracks();
            },
            .multi_track_async => {
                // Format 2: Create one part per track (independent sequences)
                try self.createPartsFromTracks();
            },
        }
    }
    
    /// Create parts based on MIDI channels (for Format 0)
    fn createPartsFromChannels(self: *MultiTrackContainer) !void {
        // Collect all unique channels across all tracks
        var channel_mask: u16 = 0;
        for (self.track_info.items) |info| {
            channel_mask |= info.channel_mask;
        }
        
        // Create a part for each used channel
        var part_number: u8 = 1;
        for (0..16) |ch| {
            const channel: u4 = @intCast(ch);
            if ((channel_mask & (@as(u16, 1) << channel)) != 0) {
                var part_id_buf: [8]u8 = undefined;
                const part_id = try std.fmt.bufPrint(&part_id_buf, "P{d}", .{part_number});
                
                var part_name_buf: [32]u8 = undefined;
                const part_name = if (channel == 9)
                    try std.fmt.bufPrint(&part_name_buf, "Percussion", .{})
                else
                    try std.fmt.bufPrint(&part_name_buf, "Part {d}", .{part_number});
                
                var part = try PartInfo.init(self.allocator, part_id, part_name);
                part.midi_channel = channel;
                part.is_percussion = (channel == 9);
                
                // Add all tracks that use this channel
                for (self.track_info.items, 0..) |info, track_idx| {
                    if (info.usesChannel(channel)) {
                        try part.addTrack(@intCast(track_idx));
                    }
                }
                
                try self.parts.append(part);
                part_number += 1;
            }
        }
    }
    
    /// Create parts based on tracks (for Format 1 and 2)
    fn createPartsFromTracks(self: *MultiTrackContainer) !void {
        for (self.track_info.items, 0..) |info, idx| {
            // Skip conductor track (track 0 in Format 1 with no notes)
            if (self.format == .multi_track_sync and idx == 0 and info.note_count == 0) {
                continue;
            }
            
            var part_id_buf: [8]u8 = undefined;
            const part_id = try std.fmt.bufPrint(&part_id_buf, "P{d}", .{self.parts.items.len + 1});
            
            // Use track name if available, otherwise generate default name
            const part_name = if (info.track_name) |name|
                name
            else if (info.instrument_name) |name|
                name
            else if (info.has_percussion)
                "Percussion"
            else blk: {
                // Use stack memory - PartInfo.init() will make its own copy
                var name_buf: [32]u8 = undefined;
                break :blk try std.fmt.bufPrint(&name_buf, "Track {d}", .{idx + 1});
            };
            
            var part = try PartInfo.init(self.allocator, part_id, part_name);
            part.is_percussion = info.has_percussion;
            
            // Set primary channel if track uses only one channel
            if (info.getChannelCount() == 1) {
                // Find the single channel
                for (0..16) |ch| {
                    if (info.usesChannel(@intCast(ch))) {
                        part.midi_channel = @intCast(ch);
                        break;
                    }
                }
            }
            
            try part.addTrack(@intCast(idx));
            try self.parts.append(part);
        }
    }
    
    /// Get total number of note events across all tracks
    pub fn getTotalNoteCount(self: *const MultiTrackContainer) u32 {
        var total: u32 = 0;
        for (self.track_info.items) |info| {
            total += info.note_count;
        }
        return total;
    }
    
    /// Get notes for a specific part
    pub fn getNotesForPart(self: *const MultiTrackContainer, part_index: usize) !std.ArrayList(parser.NoteEvent) {
        if (part_index >= self.parts.items.len) {
            return error_mod.MidiError.InvalidEventData;
        }
        
        const part = &self.parts.items[part_index];
        var notes = std.ArrayList(parser.NoteEvent).init(self.allocator);
        
        // Collect notes from all tracks in this part
        for (part.track_indices.items) |track_idx| {
            const track = &self.tracks.items[track_idx];
            
            // Filter notes by channel if part has a specific channel
            if (part.midi_channel) |channel| {
                for (track.note_events.items) |note| {
                    if (note.channel == channel) {
                        try notes.append(note);
                    }
                }
            } else {
                // Include all notes from the track
                try notes.appendSlice(track.note_events.items);
            }
        }
        
        // Sort notes by tick position for proper ordering
        std.sort.pdq(parser.NoteEvent, notes.items, {}, compareNotesByTick);
        
        return notes;
    }
    
    /// Get all tempo events from all tracks, sorted by tick position
    /// Implements TASK-2.1 per MIDI_Architecture_Reference.md tempo event extraction
    pub fn getAllTempoEvents(self: *const MultiTrackContainer) !std.ArrayList(parser.TempoEvent) {
        var tempo_events = std.ArrayList(parser.TempoEvent).init(self.allocator);
        
        // Collect tempo events from all tracks
        for (self.tracks.items) |*track| {
            try tempo_events.appendSlice(track.tempo_events.items);
        }
        
        // Sort by tick position for proper temporal ordering
        std.sort.pdq(parser.TempoEvent, tempo_events.items, {}, compareTempoEventsByTick);
        
        return tempo_events;
    }
    
    /// Get the effective tempo at the start of the MIDI file
    /// Returns the first tempo event or default 120 BPM if none found
    /// Implements TASK-2.1 per MIDI_Architecture_Reference.md tempo extraction
    pub fn getInitialTempo(self: *const MultiTrackContainer) f64 {
        // Find the earliest tempo event across all tracks
        var earliest_tempo: ?parser.TempoEvent = null;
        
        for (self.tracks.items) |*track| {
            for (track.tempo_events.items) |tempo_event| {
                if (earliest_tempo == null or tempo_event.tick < earliest_tempo.?.tick) {
                    earliest_tempo = tempo_event;
                }
            }
        }
        
        if (earliest_tempo) |tempo| {
            return tempo.toBPM();
        } else {
            // Default MIDI tempo: 120 BPM (500,000 microseconds per quarter note)
            return 120.0;
        }
    }
};

/// Comparison function for sorting notes by tick
fn compareNotesByTick(context: void, a: parser.NoteEvent, b: parser.NoteEvent) bool {
    _ = context;
    return a.tick < b.tick;
}

/// Comparison function for sorting tempo events by tick
/// Implements TASK-2.1 tempo event sorting per MIDI_Architecture_Reference.md
fn compareTempoEventsByTick(context: void, a: parser.TempoEvent, b: parser.TempoEvent) bool {
    _ = context;
    return a.tick < b.tick;
}

// Tests for multi-track support
test "TrackInfo channel operations" {
    var info = TrackInfo{
        .track_index = 0,
        .track_name = null,
        .instrument_name = null,
        .channel_mask = 0,
        .note_count = 0,
        .has_percussion = false,
    };
    
    // Test adding channels
    info.addChannel(0);
    info.addChannel(4);
    info.addChannel(9); // Percussion channel
    
    try std.testing.expect(info.usesChannel(0));
    try std.testing.expect(info.usesChannel(4));
    try std.testing.expect(info.usesChannel(9));
    try std.testing.expect(!info.usesChannel(1));
    
    try std.testing.expect(info.has_percussion);
    try std.testing.expectEqual(@as(u8, 3), info.getChannelCount());
}

test "MultiTrackContainer basic operations" {
    const allocator = std.testing.allocator;
    var container = MultiTrackContainer.init(allocator, .multi_track_sync, 480);
    defer container.deinit();
    
    // Create a dummy track
    var track = parser.TrackParseResult{
        .note_events = std.ArrayList(parser.NoteEvent).init(allocator),
        .tempo_events = std.ArrayList(parser.TempoEvent).init(allocator),
        .time_signature_events = std.ArrayList(parser.TimeSignatureEvent).init(allocator),
        .key_signature_events = std.ArrayList(parser.KeySignatureEvent).init(allocator),
        .text_events = std.ArrayList(parser.TextEvent).init(allocator),
        .control_change_events = std.ArrayList(parser.ControlChangeEvent).init(allocator),
        .program_change_events = std.ArrayList(parser.ProgramChangeEvent).init(allocator),
        .polyphonic_pressure_events = std.ArrayList(parser.PolyphonicPressureEvent).init(allocator),
        .channel_pressure_events = std.ArrayList(parser.ChannelPressureEvent).init(allocator),
        .pitch_bend_events = std.ArrayList(parser.PitchBendEvent).init(allocator),
        .rpn_events = std.ArrayList(parser.RpnEvent).init(allocator),
        .note_duration_tracker = parser.NoteDurationTracker.init(allocator),
        .track_length = 1000,
        .events_parsed = 10,
        .events_skipped = 0,
    };
    
    // Add some note events
    try track.note_events.append(.{
        .event_type = .note_on,
        .channel = 0,
        .note = 60,
        .velocity = 64,
        .tick = 0,
    });
    
    try container.addTrack(track);
    
    try std.testing.expectEqual(@as(usize, 1), container.tracks.items.len);
    try std.testing.expectEqual(@as(usize, 1), container.track_info.items.len);
    try std.testing.expectEqual(@as(u32, 1), container.track_info.items[0].note_count);
}

test "Multi-track part creation - Format 1" {
    const allocator = std.testing.allocator;
    var container = MultiTrackContainer.init(allocator, .multi_track_sync, 480);
    defer container.deinit();
    
    // Add conductor track (no notes)
    const conductor_track = parser.TrackParseResult{
        .note_events = std.ArrayList(parser.NoteEvent).init(allocator),
        .tempo_events = std.ArrayList(parser.TempoEvent).init(allocator),
        .time_signature_events = std.ArrayList(parser.TimeSignatureEvent).init(allocator),
        .key_signature_events = std.ArrayList(parser.KeySignatureEvent).init(allocator),
        .text_events = std.ArrayList(parser.TextEvent).init(allocator),
        .control_change_events = std.ArrayList(parser.ControlChangeEvent).init(allocator),
        .program_change_events = std.ArrayList(parser.ProgramChangeEvent).init(allocator),
        .polyphonic_pressure_events = std.ArrayList(parser.PolyphonicPressureEvent).init(allocator),
        .channel_pressure_events = std.ArrayList(parser.ChannelPressureEvent).init(allocator),
        .pitch_bend_events = std.ArrayList(parser.PitchBendEvent).init(allocator),
        .rpn_events = std.ArrayList(parser.RpnEvent).init(allocator),
        .note_duration_tracker = parser.NoteDurationTracker.init(allocator),
        .track_length = 1000,
        .events_parsed = 5,
        .events_skipped = 0,
    };
    
    try container.addTrack(conductor_track);
    
    // Add instrument tracks
    for (0..2) |i| {
        var track = parser.TrackParseResult{
            .note_events = std.ArrayList(parser.NoteEvent).init(allocator),
            .tempo_events = std.ArrayList(parser.TempoEvent).init(allocator),
            .time_signature_events = std.ArrayList(parser.TimeSignatureEvent).init(allocator),
            .key_signature_events = std.ArrayList(parser.KeySignatureEvent).init(allocator),
            .text_events = std.ArrayList(parser.TextEvent).init(allocator),
            .control_change_events = std.ArrayList(parser.ControlChangeEvent).init(allocator),
            .program_change_events = std.ArrayList(parser.ProgramChangeEvent).init(allocator),
            .polyphonic_pressure_events = std.ArrayList(parser.PolyphonicPressureEvent).init(allocator),
            .channel_pressure_events = std.ArrayList(parser.ChannelPressureEvent).init(allocator),
            .pitch_bend_events = std.ArrayList(parser.PitchBendEvent).init(allocator),
            .rpn_events = std.ArrayList(parser.RpnEvent).init(allocator),
            .note_duration_tracker = parser.NoteDurationTracker.init(allocator),
            .track_length = 1000,
            .events_parsed = 20,
            .events_skipped = 0,
        };
        
        // Add notes on different channels
        try track.note_events.append(.{
            .event_type = .note_on,
            .channel = @intCast(i),
            .note = 60 + @as(u8, @intCast(i)),
            .velocity = 64,
            .tick = 0,
        });
        
        try container.addTrack(track);
    }
    
    // Create parts
    try container.createParts();
    
    // Should have 2 parts (conductor track excluded)
    try std.testing.expectEqual(@as(usize, 2), container.parts.items.len);
    
    // Check part IDs
    try std.testing.expectEqualStrings("P1", container.parts.items[0].part_id);
    try std.testing.expectEqualStrings("P2", container.parts.items[1].part_id);
}
//! Voice Tracking Integration Module
//!
//! Bridges voice allocation with the interpreter pipeline
//! Integrates TASK-026 voice allocation with existing timing components
//!
//! This module provides the glue between the voice allocator and the rest
//! of the interpreter pipeline, managing voice state across measures and
//! providing voice-aware note tracking.

const std = @import("std");
const containers = @import("../utils/containers.zig");
const t = @import("../test_utils.zig");
const voice_allocation = @import("../voice_allocation.zig");
const timing = @import("../timing.zig");
const midi_events = @import("../midi/events.zig");
const error_mod = @import("../error.zig");

/// Voice tracking state for the interpreter
pub const VoiceTracker = struct {
    allocator: std.mem.Allocator,
    voice_allocator: voice_allocation.VoiceAllocator,
    /// Currently active notes per voice per channel
    active_notes: [16][voice_allocation.MAX_VOICES]?ActiveNote,
    /// Voice assignment history for continuity
    voice_history: containers.List(VoiceEvent),

    const ActiveNote = struct {
        note: u8,
        velocity: u8,
        start_tick: u32,
        channel: u8,
        voice: u8,
    };

    const VoiceEvent = struct {
        tick: u32,
        channel: u8,
        voice: u8,
        event_type: enum { note_on, note_off },
        note: u8,
    };

    /// Initialize a new voice tracker
    pub fn init(allocator: std.mem.Allocator) VoiceTracker {
        return VoiceTracker{
            .allocator = allocator,
            .voice_allocator = voice_allocation.VoiceAllocator.init(allocator),
            .active_notes = [_][voice_allocation.MAX_VOICES]?ActiveNote{[_]?ActiveNote{null} ** voice_allocation.MAX_VOICES} ** 16,
            .voice_history = containers.List(VoiceEvent).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *VoiceTracker) void {
        self.voice_allocator.deinit();
        self.voice_history.deinit();
    }

    /// Process a MIDI event and update voice tracking
    pub fn processEvent(self: *VoiceTracker, event: midi_events.Event, tick: u32) !void {
        switch (event) {
            .note_on => |note_event| {
                if (note_event.velocity > 0) {
                    try self.handleNoteOn(note_event, tick);
                } else {
                    // Velocity 0 is treated as note off
                    try self.handleNoteOff(.{
                        .channel = note_event.channel,
                        .note = note_event.note,
                        .velocity = 0,
                        .delta_time = note_event.delta_time,
                    }, tick);
                }
            },
            .note_off => |note_event| try self.handleNoteOff(note_event, tick),
            else => {}, // Other events don't affect voice tracking
        }
    }

    /// Handle note on event with voice assignment
    fn handleNoteOn(self: *VoiceTracker, event: midi_events.NoteEvent, tick: u32) !void {
        const channel = event.channel;

        // Try to find an empty voice slot
        for (&self.active_notes[channel], 1..) |*voice_slot, voice_num| {
            if (voice_slot.* == null) {
                voice_slot.* = ActiveNote{
                    .note = event.note,
                    .velocity = event.velocity,
                    .start_tick = tick,
                    .channel = channel,
                    .voice = @intCast(voice_num), // preserve 1-based voice numbering
                };

                // Record voice event and return immediately
                try self.voice_history.append(.{
                    .tick = tick,
                    .channel = channel,
                    .voice = @intCast(voice_num),
                    .event_type = .note_on,
                    .note = event.note,
                });
                return;
            }
        }

        // No empty slot available
        return voice_allocation.VoiceAllocationError.TooManySimultaneousNotes;
    }

    /// Handle note off event
    fn handleNoteOff(self: *VoiceTracker, event: midi_events.NoteEvent, tick: u32) !void {
        const channel = event.channel;

        // Find the voice playing this note
        for (&self.active_notes[channel], 1..) |*voice_slot, voice_num| {
            if (voice_slot.*) |active_note| {
                if (active_note.note == event.note) {
                    // Record voice event
                    try self.voice_history.append(.{
                        .tick = tick,
                        .channel = channel,
                        .voice = @intCast(voice_num),
                        .event_type = .note_off,
                        .note = event.note,
                    });

                    // Clear the voice slot
                    voice_slot.* = null;
                    break;
                }
            }
        }
    }

    /// Get completed notes with voice assignments for a channel
    pub fn getCompletedNotes(self: *VoiceTracker, channel: u8) ![]voice_allocation.VoicedNote {
        var notes = containers.List(timing.TimedNote).init(self.allocator);
        defer notes.deinit();

        // Track start events per MIDI note (0..127)
        var note_starts: [128]?VoiceEvent = [_]?VoiceEvent{null} ** 128;

        for (self.voice_history.items) |event| {
            if (event.channel != channel) continue;

            switch (event.event_type) {
                .note_on => {
                    const idx: usize = @intCast(event.note);
                    note_starts[idx] = event;
                },
                .note_off => {
                    const idx: usize = @intCast(event.note);
                    if (note_starts[idx]) |start_event| {
                        const duration = event.tick - start_event.tick;
                        if (duration > 0) {
                            try notes.append(.{
                                .note = event.note,
                                .channel = channel,
                                .velocity = 64, // velocity not tracked in history yet
                                .start_tick = start_event.tick,
                                .duration = duration,
                                .tied_to_next = false,
                                .tied_from_previous = false,
                            });
                        }
                        note_starts[idx] = null;
                    }
                },
            }
        }

        return self.voice_allocator.assignVoices(notes.items);
    }

    /// Process notes that have already been timed and possibly split at measure boundaries
    pub fn processTimedNotes(self: *VoiceTracker, measures: []const timing.Measure) ![]voice_allocation.VoicedNote {
        return self.voice_allocator.assignVoicesInMeasures(measures);
    }

    /// Get voice allocation statistics
    pub fn getStatistics(self: *const VoiceTracker) voice_allocation.VoiceStatistics {
        return self.voice_allocator.getStatistics();
    }

    /// Clear all tracking state
    pub fn reset(self: *VoiceTracker) void {
        // Clear active notes (one pass per channel)
        for (&self.active_notes) |*channel_voices| {
            // channel_voices: *[voice_allocation.MAX_VOICES]?ActiveNote
            std.mem.set(?ActiveNote, channel_voices.*[0..], null);
        }

        // Clear history but keep capacity
        self.voice_history.clearRetainingCapacity();

        // Reset voice allocator (use struct literal so new fields default sanely)
        for (&self.voice_allocator.voices) |*voice| {
            voice.* = .{
                .last_end_tick = 0,
                .note_count = 0,
            };
        }
    }
};

test "voice tracker basic functionality" {
    const allocator = std.testing.allocator;

    var tracker = VoiceTracker.init(allocator);
    defer tracker.deinit();

    // Simulate some MIDI events
    const note_on_60 = midi_events.Event{
        .note_on = .{
            .channel = 0,
            .note = 60,
            .velocity = 64,
            .delta_time = 0,
        },
    };

    const note_on_64 = midi_events.Event{
        .note_on = .{
            .channel = 0,
            .note = 64,
            .velocity = 64,
            .delta_time = 240,
        },
    };

    const note_off_60 = midi_events.Event{
        .note_off = .{
            .channel = 0,
            .note = 60,
            .velocity = 0,
            .delta_time = 240,
        },
    };

    const note_off_64 = midi_events.Event{
        .note_off = .{
            .channel = 0,
            .note = 64,
            .velocity = 0,
            .delta_time = 480,
        },
    };

    // Process events
    try tracker.processEvent(note_on_60, 0);
    try tracker.processEvent(note_on_64, 240);
    try tracker.processEvent(note_off_60, 480);
    try tracker.processEvent(note_off_64, 960);

    // Verify active notes during overlap
    try t.expect(tracker.active_notes[0][0] != null);
    try t.expect(tracker.active_notes[0][1] != null);

    // Get completed notes
    const voiced_notes = try tracker.getCompletedNotes(0);
    defer allocator.free(voiced_notes);

    try t.expectEq(2, voiced_notes.len);
}

test "voice tracker with measure integration" {
    const allocator = std.testing.allocator;

    var tracker = VoiceTracker.init(allocator);
    defer tracker.deinit();

    // Create test measures with notes
    var measures = [_]timing.Measure{
        timing.Measure.init(allocator, 1, 0, 1920, .{
            .numerator = 4,
            .denominator = 4,
            .clocks_per_metronome = 24,
            .thirtyseconds_per_quarter = 8,
        }),
    };
    defer measures[0].deinit();

    // Add some notes to the measure
    try measures[0].addNote(.{
        .note = 60,
        .channel = 0,
        .velocity = 64,
        .start_tick = 0,
        .duration = 960,
        .tied_to_next = false,
        .tied_from_previous = false,
    });

    try measures[0].addNote(.{
        .note = 64,
        .channel = 0,
        .velocity = 64,
        .start_tick = 480,
        .duration = 960,
        .tied_to_next = false,
        .tied_from_previous = false,
    });

    // Process timed notes
    const voiced_notes = try tracker.processTimedNotes(&measures);
    defer allocator.free(voiced_notes);

    try t.expectEq(2, voiced_notes.len);
    // First note should be voice 1
    try t.expectEq(1, voiced_notes[0].voice);
    // Second note overlaps, should be voice 2
    try t.expectEq(2, voiced_notes[1].voice);
}

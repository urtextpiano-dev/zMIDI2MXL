const std = @import("std");

/// MIDI event types and structures
pub const EventType = enum(u8) {
    note_off = 0x80,
    note_on = 0x90,
    key_pressure = 0xA0,
    control_change = 0xB0,
    program_change = 0xC0,
    channel_pressure = 0xD0,
    pitch_bend = 0xE0,
    system_exclusive = 0xF0,
    meta_event = 0xFF,
};

pub const Event = union(enum) {
    note_on: NoteEvent,
    note_off: NoteEvent,
    control_change: ControlChangeEvent,
    meta: MetaEvent,
    // More event types will be added
};

pub const NoteEvent = struct {
    channel: u4,
    note: u7,
    velocity: u7,
    delta_time: u32,
};

pub const ControlChangeEvent = struct {
    channel: u4,
    controller: u7,
    value: u7,
    delta_time: u32,
};

pub const MetaEvent = struct {
    type: u8,
    data: []const u8,
    delta_time: u32,
};

test "Event types" {
    try std.testing.expect(@intFromEnum(EventType.note_on) == 0x90);
    try std.testing.expect(@intFromEnum(EventType.note_off) == 0x80);
}
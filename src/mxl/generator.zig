const std = @import("std");
const containers = @import("../utils/containers.zig");
const log = @import("../utils/log.zig");
const XmlWriter = @import("xml_writer.zig").XmlWriter;
const Attribute = @import("xml_writer.zig").Attribute;
const error_mod = @import("../error.zig");
const NoteEvent = @import("../midi/parser.zig").NoteEvent;
const timing = @import("../timing.zig");
const t = @import("../test_utils.zig");
const note_attributes = @import("note_attributes.zig");
const multi_track = @import("../midi/multi_track.zig");
const stem_direction = @import("stem_direction.zig");
const enhanced_note = @import("../timing/enhanced_note.zig");
const beam_grouper = @import("../timing/beam_grouper.zig");
const tuplet_detector = @import("../timing/tuplet_detector.zig");
const dynamics_mapper = @import("../interpreter/dynamics_mapper.zig");
const duration_quantizer = @import("duration_quantizer.zig");
const chord_detector = @import("../harmony/chord_detector.zig");
const xmlh = @import("xml_helpers.zig");
const conversion_utils = @import("../timing/conversion_utils.zig");

// Implements TASK-008 per MXL_Architecture_Reference.md Section 8.3 lines 1016-1034
// Generate Minimal Valid MusicXML that validates against MusicXML 4.0 DTD
//
// Implements TASK-009 per MXL_Architecture_Reference.md Section 4.1 lines 303-410
// Basic Note Element Generation - Convert MIDI notes to MusicXML pitch elements

/// Pitch representation for MusicXML
pub const Pitch = struct {
    step: []const u8, // "C", "D", "E", "F", "G", "A", "B"
    alter: i8, // 0 = natural, 1 = sharp, -1 = flat
    octave: i8, // MIDI octave (middle C = 4)
};

/// Note type enumeration for MusicXML
pub const NoteType = enum {
    breve,
    whole,
    half,
    quarter,
    eighth,
    @"16th",
    @"32nd",
    @"64th",
    @"128th",
    @"256th",

    pub fn toString(self: NoteType) []const u8 {
        return @tagName(self);
    }
};

/// Convert MIDI note number to MusicXML pitch
/// Implements TASK-009 per MXL_Architecture_Reference.md Section 4.1 lines 387-402
pub fn midiToPitch(midi_note: u8) Pitch {
    // MIDI note 60 = Middle C (C4)
    // Octave calculation: MIDI uses -1 offset (MIDI octave 5 = MusicXML octave 4)
    const octave = @as(i8, @intCast(midi_note / 12)) - 1;
    const pitch_class = midi_note % 12;

    // Pitch class to step and alter mapping
    // Using sharps for chromatic notes (C#, D#, F#, G#, A#)
    const steps = [_][]const u8{ "C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B" };
    const alters = [_]i8{ 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0 };

    return Pitch{
        .step = steps[pitch_class],
        .alter = alters[pitch_class],
        .octave = octave,
    };
}

/// Calculate note type from duration in divisions
/// Implements TASK-009 per MXL_Architecture_Reference.md Section 4.1 lines 366-383
pub fn durationToNoteType(duration: u32, divisions_per_quarter: u32) NoteType {
    // Whole note = 4 quarter notes
    const whole_note_duration = divisions_per_quarter * 4;

    // Using simple ratios for now; dots/tuplets handled elsewhere
    if (duration >= whole_note_duration * 2) {
        return .breve;
    } else if (duration >= whole_note_duration) {
        return .whole;
    } else if (duration >= whole_note_duration / 2) {
        return .half;
    } else if (duration >= whole_note_duration / 4) {
        return .quarter;
    } else if (duration >= whole_note_duration / 8) {
        return .eighth;
    } else if (duration >= whole_note_duration / 16) {
        return .@"16th";
    } else if (duration >= whole_note_duration / 32) {
        return .@"32nd";
    } else if (duration >= whole_note_duration / 64) {
        return .@"64th";
    } else if (duration >= whole_note_duration / 128) {
        return .@"128th";
    } else {
        return .@"256th";
    }
}

/// Measure state tracking for proper measure boundary logic
/// Implements barline visibility fix per CRITICAL ISSUE IDENTIFIED
const MeasureState = struct {
    current_duration: u32 = 0,
    measure_number: u32 = 1,
    /// max_duration = beats * beat_type * divisions / 4
    max_duration: u32,

    pub fn init(beats: u8, beat_type: u8, divisions: u32) MeasureState {
        // For 4/4 time: 4 * 4 * 480 / 4 = 1920 duration units
        const max_duration = @as(u32, beats) * @as(u32, beat_type) * divisions / 4;
        return MeasureState{ .max_duration = max_duration };
    }

    /// Overflow-safe capacity check
    pub fn canAddNote(self: *const MeasureState, note_duration: u32) bool {
        // If invariant were ever violated, refuse to place more
        if (self.current_duration > self.max_duration) return false;
        const remaining = self.max_duration - self.current_duration;
        return note_duration <= remaining;
    }

    pub fn addNote(self: *MeasureState, note_duration: u32) void {
        // Maintain invariant in debug; zero cost in release.
        std.debug.assert(self.canAddNote(note_duration));
        self.current_duration += note_duration;
    }

    pub fn startNewMeasure(self: *MeasureState) void {
        self.measure_number += 1;
        self.current_duration = 0;
    }

    pub fn getRemainingDuration(self: *const MeasureState) u32 {
        return self.max_duration - self.current_duration;
    }

    pub fn isMeasureFull(self: *const MeasureState) bool {
        return self.current_duration >= self.max_duration;
    }
};

/// MusicXML/MXL generator module
pub const Generator = struct {
    allocator: std.mem.Allocator,
    divisions: u32, // Target MusicXML divisions per quarter note
    midi_ppq: u32, // Original MIDI PPQ for tick conversion
    quantizer: duration_quantizer.DurationQuantizer, // Professional duration quantization
    note_attr_generator: note_attributes.NoteAttributeGenerator,
    division_converter: ?timing.DivisionConverter, // For MIDI tick to MXL division conversion

    pub fn init(allocator: std.mem.Allocator, divisions: u32) Generator {
        return .{
            .allocator = allocator,
            .divisions = divisions,
            .midi_ppq = divisions, // Default: assume divisions ARE the MIDI PPQ (backward compat)
            .quantizer = duration_quantizer.DurationQuantizer.init(divisions),
            .note_attr_generator = note_attributes.NoteAttributeGenerator.init(allocator, divisions),
            .division_converter = null, // Not initialized by default
        };
    }

    /// Initialize with proper MIDI to MusicXML conversion
    /// This is the correct way to initialize for accurate timing conversion
    pub fn initWithConversion(
        allocator: std.mem.Allocator,
        midi_ppq: u32,
        target_divisions: u32,
    ) !Generator {
        const converter = try timing.DivisionConverter.init(midi_ppq, target_divisions);
        const mxl_divs = converter.getMusicXMLDivisions(); // read once

        return .{
            .allocator = allocator,
            .divisions = mxl_divs,
            .midi_ppq = midi_ppq,
            .quantizer = duration_quantizer.DurationQuantizer.init(mxl_divs),
            .note_attr_generator = note_attributes.NoteAttributeGenerator.init(allocator, mxl_divs),
            .division_converter = converter,
        };
    }

    pub fn deinit(self: *Generator) void {
        _ = self;
        // Cleanup code will go here
    }

    /// Generate a MusicXML note element from MIDI note event
    /// Implements TASK-009 per MXL_Architecture_Reference.md Section 4.1 lines 303-365
    /// Enhanced with automatic stem direction per educational requirements
    pub fn generateNoteElement(
        self: *const Generator,
        xml_writer: *XmlWriter,
        note: u8,
        duration: u32,
        is_rest: bool,
    ) !void {
        try xml_writer.startElement("note", null);

        if (is_rest) {
            try xml_writer.startElement("rest", null);
            try xml_writer.endElement(); // rest
        } else {
            const pitch = midiToPitch(note);
            try xml_writer.startElement("pitch", null);
            try xml_writer.writeElement("step", pitch.step, null);

            if (pitch.alter != 0) {
                try xmlh.writeIntElement(xml_writer, "alter", pitch.alter);
            }

            try xmlh.writeIntElement(xml_writer, "octave", pitch.octave);

            try xml_writer.endElement(); // pitch
        }

        // Use centralized conversion helper
        const duration_in_divisions = try conversion_utils.convertTicksOrSame(duration, self.division_converter);

        try xmlh.writeIntElement(xml_writer, "duration", duration_in_divisions);

        // Determine note type string and write it
        const note_type = try self.determineNoteType(duration_in_divisions);
        try xml_writer.writeElement("type", note_type, null);

        // Stem for pitched notes only
        if (!is_rest) {
            const stem_dir =
                stem_direction.StemDirectionCalculator.calculateVoiceAwareStemDirection(note, 1);
            try xml_writer.writeElement("stem", stem_dir.toMusicXML(), null);
        }

        try xml_writer.endElement(); // note
    }

    /// Generate a MusicXML note element with voice and staff information
    /// Enhanced version for multi-track support with automatic stem direction
    /// Implements automatic stem direction per educational requirements
    pub fn generateNoteElementWithAttributes(
        self: *const Generator,
        xml_writer: *XmlWriter,
        note: u8,
        duration: u32,
        is_rest: bool,
        voice: u8,
        staff: u8,
    ) !void {
        try xml_writer.startElement("note", null);

        if (is_rest) {
            // Generate rest element
            try xml_writer.startElement("rest", null);
            try xml_writer.endElement(); // rest
        } else {
            // Generate pitch element
            const pitch = midiToPitch(note);
            try xml_writer.startElement("pitch", null);
            try xml_writer.writeElement("step", pitch.step, null);

            // Only write alter if non-zero
            if (pitch.alter != 0) {
                try xmlh.writeIntElement(xml_writer, "alter", pitch.alter);
            }

            try xmlh.writeIntElement(xml_writer, "octave", pitch.octave);

            try xml_writer.endElement(); // pitch
        }

        // TIMING-2.3 FIX: Convert MIDI ticks to MusicXML divisions if converter available
        const duration_in_divisions = try conversion_utils.convertTicksOrSame(duration, self.division_converter);

        // Write the actual duration without forcing to standard note values
        try xmlh.writeIntElement(xml_writer, "duration", duration_in_divisions);

        // Write voice
        try xmlh.writeIntElement(xml_writer, "voice", voice);

        // Determine note type based on duration
        const note_type = try self.determineNoteType(duration_in_divisions);
        try xml_writer.writeElement("type", note_type, null);

        // Calculate and write stem direction (only for pitched notes, not rests)
        if (!is_rest) {
            const stem_dir = stem_direction.StemDirectionCalculator.calculateVoiceAwareStemDirection(note, voice);
            try xml_writer.writeElement("stem", stem_dir.toMusicXML(), null);
        }

        // Write staff
        try xmlh.writeIntElement(xml_writer, "staff", staff);

        try xml_writer.endElement(); // note
    }

    /// Generate note elements from MIDI note events
    /// Implements TASK-009 - converts MIDI notes to MusicXML note elements
    pub fn generateNotesFromMidiEvents(
        self: *const Generator,
        xml_writer: *XmlWriter,
        note_events: []const NoteEvent,
        start_tick: u32,
        end_tick: u32,
    ) !void {
        // TASK-009: basic note elements; duration will be refined in TASK-021
        for (note_events) |event| {
            // Flattened predicate (equivalent to nested ifs)
            if (event.tick < start_tick or event.tick >= end_tick or !event.isNoteOn())
                continue;

            const duration = self.divisions; // Quarter note placeholder
            try self.generateNoteElement(xml_writer, event.note, duration, false);
        }
    }

    /// Generate the XML header using the new XmlWriter
    pub fn writeXmlHeader(self: *const Generator, writer: anytype) !void {
        var xml_writer = XmlWriter.init(self.allocator, writer.any());
        defer xml_writer.deinit();

        try xml_writer.writeDeclaration();
        try xml_writer.writeDoctype(
            "score-partwise",
            "-//Recordare//DTD MusicXML 4.0 Partwise//EN",
            "http://www.musicxml.org/dtds/partwise.dtd",
        );
    }

    /// Generate a minimal valid MusicXML document
    /// This creates the bare minimum structure required for a valid MusicXML file
    pub fn generateMinimalMusicXML(self: *const Generator, writer: anytype) !void {
        // Reuse the centralized header routine
        try self.writeXmlHeader(writer);

        // Continue with a fresh XmlWriter on the same sink
        var xml_writer = XmlWriter.init(self.allocator, writer.any());
        defer xml_writer.deinit();

        // Start root element with version attribute
        try xml_writer.startElement("score-partwise", &[_]Attribute{
            .{ .name = "version", .value = "4.0" },
        });

        // part-list (required)
        try xml_writer.startElement("part-list", null);
        try xml_writer.startElement("score-part", &[_]Attribute{
            .{ .name = "id", .value = "P1" },
        });
        try xml_writer.writeElement("part-name", "Piano", null);
        try xml_writer.endElement(); // score-part
        try xml_writer.endElement(); // part-list

        // part (required)
        try xml_writer.startElement("part", &[_]Attribute{
            .{ .name = "id", .value = "P1" },
        });

        // measure 1 (required)
        try xml_writer.startElement("measure", &[_]Attribute{
            .{ .name = "number", .value = "1" },
        });

        // attributes with divisions (required)
        try xml_writer.startElement("attributes", null);

        try xmlh.writeIntElement(xml_writer, "divisions", self.quantizer.getNormalizedDivisions());

        try xml_writer.endElement(); // attributes
        try xml_writer.endElement(); // measure
        try xml_writer.endElement(); // part
        try xml_writer.endElement(); // score-partwise
    }

    /// Generate a minimal MusicXML with basic musical content
    pub fn generateMinimalWithNotes(self: *const Generator, writer: anytype) !void {
        // Centralized header
        try self.writeXmlHeader(writer);

        // Proceed with content
        var xml_writer = XmlWriter.init(self.allocator, writer.any());
        defer xml_writer.deinit();

        // Root
        try xml_writer.startElement("score-partwise", &[_]Attribute{
            .{ .name = "version", .value = "4.0" },
        });

        // part-list
        try xml_writer.startElement("part-list", null);
        try xml_writer.startElement("score-part", &[_]Attribute{
            .{ .name = "id", .value = "P1" },
        });
        try xml_writer.writeElement("part-name", "Piano", null);
        try xml_writer.endElement(); // score-part
        try xml_writer.endElement(); // part-list

        // part
        try xml_writer.startElement("part", &[_]Attribute{
            .{ .name = "id", .value = "P1" },
        });

        // measure 1
        try xml_writer.startElement("measure", &[_]Attribute{
            .{ .name = "number", .value = "1" },
        });

        // attributes
        try xml_writer.startElement("attributes", null);

        try xmlh.writeIntElement(&xml_writer, "divisions", self.quantizer.getNormalizedDivisions());

        // key: C major
        try xml_writer.startElement("key", null);
        try xmlh.writeIntElement(&xml_writer, "fifths", 0);
        try xml_writer.endElement(); // key

        // time: 4/4
        try xml_writer.startElement("time", null);
        try xmlh.writeIntElement(&xml_writer, "beats", 4);
        try xmlh.writeIntElement(&xml_writer, "beat-type", 4);
        try xml_writer.endElement(); // time

        // clef: treble
        try xml_writer.startElement("clef", null);
        try xml_writer.writeElement("sign", "G", null);
        try xmlh.writeIntElement(&xml_writer, "line", 2);
        try xml_writer.endElement(); // clef

        try xml_writer.endElement(); // attributes

        // note: middle C, quarter duration
        try xml_writer.startElement("note", null);

        try xml_writer.startElement("pitch", null);
        try xml_writer.writeElement("step", "C", null);
        try xmlh.writeIntElement(&xml_writer, "octave", 4);
        try xml_writer.endElement(); // pitch

        try xmlh.writeIntElement(&xml_writer, "duration", self.divisions);
        try xml_writer.writeElement("type", "quarter", null);

        try xml_writer.endElement(); // note

        try xml_writer.endElement(); // measure
        try xml_writer.endElement(); // part
        try xml_writer.endElement(); // score-partwise
    }

    /// Generate MusicXML with complete note attributes
    /// Implements TASK-027 - includes measure numbers, time signatures, and tempo markings
    pub fn generateMusicXMLWithCompleteAttributes(
        self: *const Generator,
        writer: anytype,
        measures: []const @import("../timing/measure_detector.zig").Measure,
        tempo_events: []const @import("../midi/parser.zig").TempoEvent,
    ) !void {
        // Reuse centralized header writer for declaration + DOCTYPE
        try self.writeXmlHeader(writer);

        // Proceed with content
        var xml_writer = XmlWriter.init(self.allocator, writer.any());
        defer xml_writer.deinit();

        // Start root element
        try xml_writer.startElement("score-partwise", &[_]Attribute{
            .{ .name = "version", .value = "4.0" },
        });

        // Part-list (single default part)
        try xml_writer.startElement("part-list", null);
        try xml_writer.startElement("score-part", &[_]Attribute{
            .{ .name = "id", .value = "P1" },
        });
        try xml_writer.writeElement("part-name", "Piano", null);
        try xml_writer.endElement(); // score-part
        try xml_writer.endElement(); // part-list

        // Part
        try xml_writer.startElement("part", &[_]Attribute{
            .{ .name = "id", .value = "P1" },
        });

        // Track tempo changes for each measure
        var tempo_index: usize = 0;

        // Generate each measure with complete attributes
        for (measures, 0..) |measure, i| {
            // Find tempo event for this measure if any (keep last in [start,end))
            var measure_tempo: ?*const @import("../midi/parser.zig").TempoEvent = null;
            while (tempo_index < tempo_events.len and
                tempo_events[tempo_index].tick >= measure.start_tick and
                tempo_events[tempo_index].tick < measure.end_tick)
            {
                measure_tempo = &tempo_events[tempo_index];
                tempo_index += 1;
            }

            try self.note_attr_generator.writeMeasureWithAttributes(
                &xml_writer,
                &measure,
                measure.notes.items,
                measure_tempo,
                i == 0, // is_first_measure
            );
        }

        try xml_writer.endElement(); // part
        try xml_writer.endElement(); // score-partwise
    }

    /// Generate part-list element for multi-track support
    /// Implements TASK-029 per MXL_Architecture_Reference.md Section 4.3 lines 416-435
    pub fn generatePartList(
        self: *const Generator,
        xml_writer: *XmlWriter,
        parts: []const multi_track.PartInfo,
    ) !void {
        _ = self; // Self parameter unused but kept for API consistency
        try xml_writer.startElement("part-list", null);

        for (parts) |part| {
            try xml_writer.startElement("score-part", &[_]Attribute{
                .{ .name = "id", .value = part.part_id },
            });

            try xml_writer.writeElement("part-name", part.part_name, null);

            // Add part abbreviation if available
            try xmlh.writeStringElement(xml_writer, "part-abbreviation", part.part_abbreviation);

            // Add MIDI instrument information if available
            if (part.midi_channel) |channel| {
                // Score instrument
                var instrument_id_buf: [16]u8 = undefined;
                const instrument_id = try std.fmt.bufPrint(&instrument_id_buf, "{s}-I1", .{part.part_id});

                try xml_writer.startElement("score-instrument", &[_]Attribute{
                    .{ .name = "id", .value = instrument_id },
                });

                // Use part name as instrument name
                try xml_writer.writeElement("instrument-name", part.part_name, null);

                // Add instrument sound if percussion
                if (part.is_percussion) {
                    try xml_writer.writeElement("instrument-sound", "percussion", null);
                }

                try xml_writer.endElement(); // score-instrument

                // MIDI device
                try xml_writer.writeElement("midi-device", "GM", null);

                // MIDI instrument
                try xml_writer.startElement("midi-instrument", &[_]Attribute{
                    .{ .name = "id", .value = instrument_id },
                });

                try xmlh.writeIntElement(xml_writer, "midi-channel", channel + 1); // Display channel (1-16)

                if (part.midi_program) |program| {
                    try xmlh.writeIntElement(xml_writer, "midi-program", program + 1); // MIDI programs are 1-128 in MusicXML
                }

                try xml_writer.endElement(); // midi-instrument
            }

            try xml_writer.endElement(); // score-part
        }

        try xml_writer.endElement(); // part-list
    }

    /// Generate MusicXML from multi-track container
    /// Implements TASK-029 - Generate multiple parts with proper part-list structure
    pub fn generateMultiTrackMusicXML(
        self: *const Generator,
        writer: anytype,
        container: *const multi_track.MultiTrackContainer,
    ) !void {
        var xml_writer = XmlWriter.init(self.allocator, writer.any());
        defer xml_writer.deinit();

        // Write header
        try xml_writer.writeDeclaration();
        try xml_writer.writeDoctype("score-partwise", "-//Recordare//DTD MusicXML 4.0 Partwise//EN", "http://www.musicxml.org/dtds/partwise.dtd");

        // Start root element
        try xml_writer.startElement("score-partwise", &[_]Attribute{
            .{ .name = "version", .value = "4.0" },
        });

        // Extract key signature from conductor track (track 0)
        var fifths: i8 = 0; // Default to C major
        if (container.tracks.items.len > 0) {
            const conductor_track = container.tracks.items[0];
            if (conductor_track.key_signature_events.items.len > 0) {
                fifths = conductor_track.key_signature_events.items[0].sharps_flats;
            }
        }

        // Generate part-list
        try self.generatePartList(&xml_writer, container.parts.items);

        // Generate each part
        for (container.parts.items, 0..) |part, part_idx| {
            try xml_writer.startElement("part", &[_]Attribute{
                .{ .name = "id", .value = part.part_id },
            });

            // For now, generate a simple measure with divisions
            // This will be expanded to include actual notes in the next iteration
            try xml_writer.startElement("measure", &[_]Attribute{
                .{ .name = "number", .value = "1" },
            });

            // Write attributes in first measure
            try xml_writer.startElement("attributes", null);

            try xmlh.writeIntElement(&xml_writer, "divisions", self.quantizer.getNormalizedDivisions());

            // Add key signature from MIDI data
            try xml_writer.startElement("key", null);
            try xmlh.writeIntElement(&xml_writer, "fifths", fifths);
            try xml_writer.endElement(); // key

            // Add default time signature
            try xml_writer.startElement("time", null);
            try xmlh.writeIntElement(&xml_writer, "beats", 4);
            try xmlh.writeIntElement(&xml_writer, "beat-type", 4);
            try xml_writer.endElement(); // time

            // Add clef based on part type
            try xml_writer.startElement("clef", null);
            if (part.is_percussion) {
                try xml_writer.writeElement("sign", "percussion", null);
            } else {
                // Default to treble clef, could be improved with range analysis
                try xml_writer.writeElement("sign", "G", null);
                try xmlh.writeIntElement(&xml_writer, "line", 2);
            }
            try xml_writer.endElement(); // clef

            try xml_writer.endElement(); // attributes

            // Get notes for this part
            var notes = try container.getNotesForPart(part_idx);
            defer notes.deinit();

            // Generate note elements for this part
            if (notes.items.len > 0) {
                // Process actual MIDI notes instead of generating placeholder rests
                // Implements critical fix for MIDI to MXL converter note processing
                for (notes.items) |note_event| {
                    if (note_event.isNoteOn()) {
                        // Use parsed note data: pitch, duration from MIDI events
                        // For now, use quarter note duration (will be enhanced with proper duration tracking)
                        const duration = self.divisions; // Quarter note duration

                        // Generate proper note element with voice and staff information
                        try self.generateNoteElementWithAttributes(&xml_writer, note_event.note, duration, false, 1, 1);
                    }
                }
            } else {
                // Only generate rest if no notes are present
                try self.generateNoteElementWithAttributes(&xml_writer, 0, self.divisions * 4, true, 1, 1);
            }

            try xml_writer.endElement(); // measure
            try xml_writer.endElement(); // part
        }

        try xml_writer.endElement(); // score-partwise
    }

    /// Generate MusicXML with proper measure boundaries and barline visibility
    /// Implements the barline visibility fix per CRITICAL ISSUE IDENTIFIED
    /// Enhanced with dynamic tempo support per TASK 2.2
    /// CRITICAL FIX: Now accepts TimedNote[] to preserve actual note durations
    pub fn generateMusicXMLWithMeasureBoundaries(
        self: *const Generator,
        writer: anytype,
        timed_notes: []const timing.TimedNote,
        tempo_bpm: u32,
    ) !void {
        var xml_writer = XmlWriter.init(self.allocator, writer.any());
        defer xml_writer.deinit();

        // Write header
        try xml_writer.writeDeclaration();
        try xml_writer.writeDoctype("score-partwise", "-//Recordare//DTD MusicXML 4.0 Partwise//EN", "http://www.musicxml.org/dtds/partwise.dtd");

        // Start root element
        try xml_writer.startElement("score-partwise", &[_]Attribute{
            .{ .name = "version", .value = "4.0" },
        });

        // Part-list
        try xml_writer.startElement("part-list", null);
        try xml_writer.startElement("score-part", &[_]Attribute{
            .{ .name = "id", .value = "P1" },
        });
        try xml_writer.writeElement("part-name", "Piano", null);
        try xml_writer.endElement(); // score-part
        try xml_writer.endElement(); // part-list

        // Part
        try xml_writer.startElement("part", &[_]Attribute{
            .{ .name = "id", .value = "P1" },
        });

        // Initialize measure state for 4/4 time
        var measure_state = MeasureState.init(4, 4, self.divisions);

        // Process notes and split across measures
        var note_index: usize = 0;

        while (note_index < timed_notes.len or !measure_state.isMeasureFull()) {
            // Start new measure
            try self.note_attr_generator.writeMeasureStart(&xml_writer, measure_state.measure_number);
            // Use piano grand staff with clefs only in first measure
            const is_first_measure = measure_state.measure_number == 1;
            try self.note_attr_generator.writeCompleteAttributes(&xml_writer, measure_state.measure_number, true, is_first_measure, 0); // Default to C major for backward compatibility

            // Add tempo marking for first measure - implements TASK 2.2
            if (is_first_measure) {
                try self.generateTempoMarking(&xml_writer, tempo_bpm);
            }

            // Fill measure with notes
            while (note_index < timed_notes.len and !measure_state.isMeasureFull()) {
                const note = timed_notes[note_index];

                // CRITICAL FIX: Use actual note duration from TimedNote
                // Convert MIDI ticks to MusicXML divisions using the division converter
                const note_duration = try conversion_utils.convertTicksOrSame(note.duration, self.division_converter);

                if (measure_state.canAddNote(note_duration)) {
                    // Note fits in current measure - use appropriate staff for piano grand staff
                    const staff_number = @import("note_attributes.zig").getStaffForNote(note.note);
                    try self.generateNoteElementWithAttributes(&xml_writer, note.note, note_duration, false, 1, staff_number);
                    measure_state.addNote(note_duration);
                    note_index += 1;
                } else {
                    // Need to start new measure
                    break;
                }
            }

            // Fill remaining space with rest if measure is not full
            if (!measure_state.isMeasureFull()) {
                const remaining_duration = measure_state.getRemainingDuration();
                if (remaining_duration > 0) {
                    // Use staff 1 (treble) for rests by default
                    try self.generateNoteElementWithAttributes(&xml_writer, 0, remaining_duration, true, 1, 1);
                    measure_state.addNote(remaining_duration);
                }
            }

            // Add explicit barline for visibility
            try self.note_attr_generator.writeBarline(&xml_writer);

            try xml_writer.endElement(); // measure

            // Prepare for next measure
            measure_state.startNewMeasure();

            // Break if no more notes
            if (note_index >= timed_notes.len) {
                break;
            }
        }

        try xml_writer.endElement(); // part
        try xml_writer.endElement(); // score-partwise
    }

    /// Generate a rest element with specified duration
    /// Helper function for filling incomplete measures
    fn generateRestElement(
        self: *const Generator,
        xml_writer: *XmlWriter,
        duration: u32,
    ) !void {
        // Duration using professional quantization
        // Implements EXECUTIVE MANDATE per critical timing accuracy issue
        // TIMING-2.3 FIX: Convert MIDI ticks to MusicXML divisions if converter available
        const duration_in_divisions = try conversion_utils.convertTicksOrSame(duration, self.division_converter);

        // CRITICAL: Don't generate XML for tiny durations (filtered as noise)
        // Durations less than 5% of quarter note are measurement noise
        const min_duration = self.divisions / 20;
        if (duration_in_divisions < min_duration) {
            return; // Tiny durations absorbed as timing tolerance
        }

        try xml_writer.startElement("note", null);

        // Rest element
        try xml_writer.startElement("rest", null);
        try xml_writer.endElement(); // rest

        try xmlh.writeIntElement(xml_writer, "duration", duration_in_divisions);

        // Determine note type based on duration
        const note_type = try self.determineNoteType(duration_in_divisions);
        try xml_writer.writeElement("type", note_type, null);

        try xml_writer.endElement(); // note
    }

    /// Generate MusicXML from enhanced notes with educational metadata
    /// Implements TASK-INT-016 - Outputs educational features to MusicXML
    /// TASK 4.1: Updated to accept pre-detected global chords per CHORD_DETECTION_FIX_TASK_LIST.md lines 115-121
    /// FIX-2.1: Updated to accept key signature from MIDI data
    pub fn generateMusicXMLFromEnhancedNotes(
        self: *const Generator,
        writer: anytype,
        enhanced_notes: []const enhanced_note.EnhancedTimedNote,
        tempo_bpm: u32,
        global_chords: ?[]const chord_detector.ChordGroup,
        key_fifths: i8,
    ) !void {
        var xml_writer = XmlWriter.init(self.allocator, writer.any());
        defer xml_writer.deinit();

        // Write header
        try xml_writer.writeDeclaration();
        try xml_writer.writeDoctype("score-partwise", "-//Recordare//DTD MusicXML 4.0 Partwise//EN", "http://www.musicxml.org/dtds/partwise.dtd");

        // Start root element
        try xml_writer.startElement("score-partwise", &[_]Attribute{
            .{ .name = "version", .value = "4.0" },
        });

        // Part-list
        try xml_writer.startElement("part-list", null);
        try xml_writer.startElement("score-part", &[_]Attribute{
            .{ .name = "id", .value = "P1" },
        });
        try xml_writer.writeElement("part-name", "Piano", null);
        try xml_writer.endElement(); // score-part
        try xml_writer.endElement(); // part-list

        // Part
        try xml_writer.startElement("part", &[_]Attribute{
            .{ .name = "id", .value = "P1" },
        });

        // Generate measures with enhanced notes
        try self.generateMeasuresFromEnhancedNotes(&xml_writer, enhanced_notes, tempo_bpm, global_chords, key_fifths);

        try xml_writer.endElement(); // part
        try xml_writer.endElement(); // score-partwise
    }

    /// Generate measures from enhanced notes with educational metadata
    /// Helper function to check if chord groups have multiple voices
    fn hasMultipleVoices(chord_groups: []const chord_detector.ChordGroup) bool {
        var first_voice: ?u8 = null;

        for (chord_groups) |group| {
            for (group.notes) |note| {
                const v: u8 = if (note.voice > 0) @intCast(note.voice) else 1;
                if (first_voice) |fv| {
                    if (v != fv) return true; // early exit on second distinct voice
                } else {
                    first_voice = v;
                }
            }
        }
        return false;
    }

    /// Helper function to collect notes for a measure from chord groups
    fn collectMeasureNotes(
        self: *const Generator,
        chord_groups: []const chord_detector.ChordGroup,
        start_index: usize,
        measure_state: *MeasureState,
        notes_list: *std.ArrayList(enhanced_note.EnhancedTimedNote),
    ) !usize {
        _ = self; // unused

        var i: usize = start_index;
        while (i < chord_groups.len) {
            // Preserve original "stop when measure is full" behavior.
            if (measure_state.isMeasureFull()) break;

            const group = chord_groups[i];

            // Explicitly skip empty chord groups (no notes, no capacity impact).
            if (group.notes.len == 0) {
                i += 1;
                continue;
            }

            const chord_duration = group.notes[0].duration;

            // Respect capacity decision based on the first note's duration.
            if (!measure_state.canAddNote(chord_duration)) break;

            // Append all notes from this chord group.
            for (group.notes) |note| {
                try notes_list.append(enhanced_note.EnhancedTimedNote.init(note, null));
            }

            measure_state.addNote(chord_duration);
            i += 1;
        }

        return i;
    }

    /// TASK 4.1: Updated to use pre-detected global chords per CHORD_DETECTION_FIX_TASK_LIST.md lines 115-121
    /// FIX-2.1: Updated to accept key signature from MIDI data
    /// BUG #2 FIX: Integrate generateMeasureWithVoices for multi-voice support
    fn generateMeasuresFromEnhancedNotes(
        self: *const Generator,
        xml_writer: *XmlWriter,
        enhanced_notes: []const enhanced_note.EnhancedTimedNote,
        tempo_bpm: u32,
        global_chords: ?[]const chord_detector.ChordGroup,
        key_fifths: i8,
    ) !void {
        // 4/4 initialization (as before)
        var measure_state = MeasureState.init(4, 4, self.divisions);

        // Use provided global chords or fall back to local detection (unchanged ownership rules)
        const chord_groups = if (global_chords) |chords| blk: {
            break :blk chords;
        } else blk: {
            const timed_notes = try self.convertEnhancedToTimedNotes(enhanced_notes);
            defer self.allocator.free(timed_notes);

            var detector = chord_detector.ChordDetector.init(self.allocator);
            const detected = try detector.detectChords(timed_notes, 10);
            break :blk detected;
        };

        // Only free if we allocated locally
        defer if (global_chords == null) {
            const mutable_chords = @constCast(chord_groups);
            for (mutable_chords) |*group| group.deinit(self.allocator);
            self.allocator.free(mutable_chords);
        };

        var chord_index: usize = 0;

        // Outer safety guard (unchanged)
        var measure_iterations: u32 = 0;
        const max_measures: u32 = 10000;

        while (chord_index < chord_groups.len) {
            measure_iterations += 1;
            if (measure_iterations > max_measures) {
                std.debug.print("SAFETY: Too many measures generated ({d}), breaking to prevent hang\n", .{max_measures});
                break;
            }

            const start_chord_index = chord_index;

            // Build the measure span once
            var measure_notes = std.ArrayList(enhanced_note.EnhancedTimedNote).init(self.allocator);
            defer measure_notes.deinit();

            var temp_measure_state = MeasureState.init(4, 4, self.divisions);
            temp_measure_state.measure_number = measure_state.measure_number;

            const next_chord_index = try self.collectMeasureNotes(
                chord_groups,
                chord_index,
                &temp_measure_state,
                &measure_notes,
            );

            // Early-exit voice detection (clearer & safer than a tiny bitset)
            const measure_has_multiple_voices = blk: {
                var first_voice: ?u8 = null;
                for (measure_notes.items) |nt| {
                    const v: u8 = if (nt.base_note.voice > 0) @intCast(nt.base_note.voice) else 1;
                    if (first_voice) |fv| {
                        if (v != fv) break :blk true;
                    } else {
                        first_voice = v;
                    }
                }
                break :blk false;
            };

            if (measure_has_multiple_voices) {
                // Voice-aware generation remains unchanged
                try self.generateMeasureWithVoices(
                    xml_writer,
                    measure_notes.items,
                    measure_state.measure_number,
                    measure_state.measure_number == 1,
                    key_fifths,
                    tempo_bpm,
                );
            } else {
                // Single-voice: emit exactly the span we already computed.
                try self.note_attr_generator.writeMeasureStart(xml_writer, measure_state.measure_number);

                if (measure_state.measure_number == 1) {
                    try self.note_attr_generator.writeCompleteAttributes(
                        xml_writer,
                        measure_state.measure_number,
                        true,
                        true,
                        key_fifths,
                    );
                    try self.generateTempoMarking(xml_writer, tempo_bpm);
                }

                // No second capacity loop: just generate [chord_index .. next_chord_index)
                var i: usize = chord_index;
                while (i < next_chord_index) : (i += 1) {
                    const group = chord_groups[i];
                    if (group.notes.len == 0) continue; // no-op groups
                    try self.generateChordGroup(xml_writer, group, true);
                    // Keep measure_state’s total aligned (used for rest logic in original)
                    measure_state.addNote(group.notes[0].duration);
                }

                // Compute remainder from the same temporary state used to pick the span
                const remaining_duration = temp_measure_state.getRemainingDuration();
                const min_rest_threshold = self.divisions / 8; // 32nd-note minimum
                if (remaining_duration >= min_rest_threshold) {
                    try self.generateRestElement(xml_writer, remaining_duration);
                    measure_state.addNote(remaining_duration);
                }

                try self.note_attr_generator.writeBarline(xml_writer);
                try xml_writer.endElement(); // measure
            }

            // Advance by the span we collected
            chord_index = next_chord_index;

            // Next measure
            measure_state.startNewMeasure();

            // Progress safety fallback (unchanged)
            if (chord_index == start_chord_index and chord_index < chord_groups.len) {
                chord_index += 1;
            }
        }
    }

    /// Determine note type from duration in divisions
    // Exact, integer-only mapping (no floating point).
    // Keeps the same signature and return values as your current function.
    fn determineNoteType(self: *const Generator, duration: u32) ![]const u8 {
        // Based on half-way thresholds between standard note lengths
        // relative to a quarter note. We avoid floats by cross-multiplying.
        const d: u64 = duration;
        const div: u64 = self.divisions;
        const three_div: u64 = 3 * div;

        // >= 6.0 quarters  -> breve
        if (d >= 6 * div) return "breve";
        // >= 3.0 quarters  -> whole
        if (d >= 3 * div) return "whole";
        // >= 1.5 quarters  -> half       (2d >= 3div)
        if (2 * d >= three_div) return "half";
        // >= 0.75 quarters -> quarter    (4d >= 3div)
        if (4 * d >= three_div) return "quarter";
        // >= 0.375         -> eighth     (8d >= 3div)
        if (8 * d >= three_div) return "eighth";
        // >= 0.1875        -> 16th       (16d >= 3div)
        if (16 * d >= three_div) return "16th";
        // >= 0.09375       -> 32nd       (32d >= 3div)
        if (32 * d >= three_div) return "32nd";
        // >= 0.046875      -> 64th       (64d >= 3div)
        if (64 * d >= three_div) return "64th";
        // >= 0.0234375     -> 128th      (128d >= 3div)
        if (128 * d >= three_div) return "128th";
        return "256th";
    }

    /// Generate tempo marking as a direction element
    fn generateTempoMarking(
        self: *const Generator,
        xml_writer: *XmlWriter,
        tempo_bpm: u32,
    ) !void {
        _ = self;

        try xml_writer.startElement("direction", &[_]Attribute{
            .{ .name = "placement", .value = "above" },
        });

        try xml_writer.startElement("direction-type", null);
        try xml_writer.startElement("metronome", null);

        try xml_writer.writeElement("beat-unit", "quarter", null);

        try xmlh.writeIntElement(xml_writer, "per-minute", tempo_bpm);

        try xml_writer.endElement(); // metronome
        try xml_writer.endElement(); // direction-type

        try xml_writer.endElement(); // direction
    }

    /// Generate backup element for multi-voice support
    /// Implements MVS-2.3 per MULTI_VOICE_SEPARATION_TASK_LIST.md
    ///
    /// The backup element moves the temporal position backward within a measure,
    /// enabling multiple voices to start at the same time point. This is essential
    /// for proper multi-voice MusicXML representation.
    ///
    /// Duration calculation follows MusicXML standard:
    /// Backup Duration = (Quarter Notes to Move Back) × Divisions Per Quarter Note
    ///
    /// Example with divisions=480:
    /// - To move back one quarter note: duration=480
    /// - To move back a half note: duration=960
    /// - To move back a whole note: duration=1920
    ///
    /// Args:
    ///   xml_writer: The XML writer to output the backup element
    ///   duration: Duration to move backward in divisions (must be positive)
    ///
    /// MusicXML Output:
    /// ```xml
    /// <backup>
    ///   <duration>480</duration>
    /// </backup>
    /// ```
    pub fn generateBackupElement(
        self: *const Generator,
        xml_writer: *XmlWriter,
        duration: u32,
    ) !void {
        _ = self; // Unused parameter

        // Validate input - duration must be positive
        if (duration == 0) {
            return; // No backup needed for zero duration
        }

        // Start backup element (no attributes)
        try xml_writer.startElement("backup", null);

        // Write duration as child element
        try xmlh.writeIntElement(xml_writer, "duration", duration);

        // Close backup element
        try xml_writer.endElement(); // backup
    }

    /// Voice group structure for organizing notes by voice within measures
    /// Used by generateMeasureWithVoices for proper multi-voice MusicXML generation
    const VoiceGroup = struct {
        voice_number: u8,
        notes: containers.List(enhanced_note.EnhancedTimedNote),
        total_duration: u32,

        pub fn init(allocator: std.mem.Allocator, voice_number: u8) VoiceGroup {
            return VoiceGroup{
                .voice_number = voice_number,
                .notes = containers.List(enhanced_note.EnhancedTimedNote).init(allocator),
                .total_duration = 0,
            };
        }

        pub fn deinit(self: *VoiceGroup) void {
            self.notes.deinit();
        }

        pub fn addNote(self: *VoiceGroup, note: enhanced_note.EnhancedTimedNote) !void {
            try self.notes.append(note);
            self.total_duration += note.base_note.duration;
        }
    };

    /// Group enhanced notes by voice for multi-voice measure generation
    /// Implements MVS-2.3 voice grouping algorithm per MUSICXML_VOICE_BACKUP_RESEARCH.md
    ///
    /// This function takes a collection of enhanced notes and groups them by voice number,
    /// maintaining the order within each voice for proper temporal sequencing.
    /// Voice groups are sorted by voice number (1, 2, 5, 6, etc.) for consistent output.
    ///
    /// Args:
    ///   allocator: Memory allocator for voice group storage
    ///   notes: Array of enhanced notes to group by voice
    ///
    /// Returns:
    ///   ArrayList of VoiceGroup structures, sorted by voice number
    ///   Caller is responsible for deinitializing all voice groups
    ///
    /// Algorithm:
    ///   1. Create a map from voice numbers to voice groups
    ///   2. Iterate through all notes, adding each to its voice group
    ///   3. Sort voice groups by voice number for consistent output
    ///   4. Return sorted list for measure generation
    pub fn groupNotesByVoice(
        self: *const Generator,
        allocator: std.mem.Allocator,
        notes: []const enhanced_note.EnhancedTimedNote,
    ) !containers.List(VoiceGroup) {
        _ = self; // Unused parameter

        // Use a hash map to collect notes by voice number
        var voice_map = containers.AutoMap(u8, VoiceGroup).init(allocator);
        defer voice_map.deinit();

        // Group notes by voice number
        for (notes) |note| {
            // Get voice number from TimedNote, default to 1 if unassigned
            const voice_num = if (note.base_note.voice > 0) note.base_note.voice else 1;

            // Get or create voice group for this voice number
            const result = try voice_map.getOrPut(voice_num);
            if (!result.found_existing) {
                result.value_ptr.* = VoiceGroup.init(allocator, voice_num);
            }

            // Add note to the voice group
            try result.value_ptr.addNote(note);
        }

        // Convert hash map to sorted array list
        var voice_groups = containers.List(VoiceGroup).init(allocator);
        var iterator = voice_map.iterator();
        while (iterator.next()) |entry| {
            try voice_groups.append(entry.value_ptr.*);
        }

        // Sort voice groups by voice number for consistent output
        // This ensures voices are processed in order: 1, 2, 5, 6, etc.
        std.sort.insertion(VoiceGroup, voice_groups.items, {}, struct {
            fn lessThan(_: void, a: VoiceGroup, b: VoiceGroup) bool {
                return a.voice_number < b.voice_number;
            }
        }.lessThan);

        return voice_groups;
    }

    /// Generate a single measure with proper multi-voice support using backup elements
    /// Implements MVS-2.3 backup insertion algorithm per MUSICXML_VOICE_BACKUP_RESEARCH.md
    ///
    /// This function implements the core multi-voice MusicXML generation pattern:
    /// 1. Group notes by voice within the measure
    /// 2. Generate notes for voice 1 (complete measure)
    /// 3. Insert backup element to return to measure start
    /// 4. Generate notes for voice 2, 5, 6, etc. with appropriate backups
    ///
    /// Args:
    ///   xml_writer: XML writer for output generation
    ///   notes: Enhanced notes for this measure (should fit within measure bounds)
    ///   measure_number: Measure number for XML attributes
    ///   is_first_measure: Whether this is the first measure (needs complete attributes)
    ///   key_fifths: Key signature (fifths circle value)
    ///   tempo_bpm: Tempo for first measure tempo marking
    ///
    /// Algorithm follows research from MUSICXML_VOICE_BACKUP_RESEARCH.md Section 4.1:
    /// ```
    /// 1. Initialize cumulative_duration = 0
    /// 2. Group notes by voice within each measure
    /// 3. For each voice in order (1, 2, 5, 6, etc.):
    ///    a. If cumulative_duration > 0:
    ///       - Insert backup element with duration = cumulative_duration
    ///       - Reset cumulative_duration = 0
    ///    b. For each note in voice:
    ///       - Write note element
    ///       - cumulative_duration += note.duration
    /// ```
    fn generateMeasureWithVoices(
        self: *const Generator,
        xml_writer: *XmlWriter,
        notes: []const enhanced_note.EnhancedTimedNote,
        measure_number: u32,
        is_first_measure: bool,
        key_fifths: i8,
        tempo_bpm: u32,
    ) !void {
        // Start measure element
        try self.note_attr_generator.writeMeasureStart(xml_writer, measure_number);

        // Write attributes for first measure
        if (is_first_measure) {
            try self.note_attr_generator.writeCompleteAttributes(xml_writer, measure_number, true, true, key_fifths);
            // Add tempo marking
            try self.generateTempoMarking(xml_writer, tempo_bpm);
        }

        // Group notes by voice for processing
        var voice_groups = try self.groupNotesByVoice(self.allocator, notes);
        defer {
            for (voice_groups.items) |*group| {
                group.deinit();
            }
            voice_groups.deinit();
        }

        // If no voices, generate a measure rest and return
        if (voice_groups.items.len == 0) {
            // Generate a full measure rest
            const measure_duration = self.divisions * 4; // Whole note duration for 4/4 time
            try self.generateRestElement(xml_writer, measure_duration);
            try self.note_attr_generator.writeBarline(xml_writer);
            try xml_writer.endElement(); // measure
            return;
        }

        // Track cumulative duration for backup calculations
        var cumulative_duration: u32 = 0;

        // Process each voice group in order
        for (voice_groups.items) |voice_group| {
            // Insert backup element if this is not the first voice
            if (cumulative_duration > 0) {
                try self.generateBackupElement(xml_writer, cumulative_duration);
                // Reset cumulative duration since we've backed up to start of measure
                cumulative_duration = 0;
            }

            // Generate all notes for this voice, detecting chords
            for (voice_group.notes.items, 0..) |note, i| {
                // Check if this note is part of a chord (same start_tick as previous note)
                const is_chord = if (i > 0) blk: {
                    const prev_note = voice_group.notes.items[i - 1];
                    break :blk note.base_note.start_tick == prev_note.base_note.start_tick;
                } else false;

                try self.generateEnhancedNoteElement(xml_writer, &note, is_chord);
                cumulative_duration += note.base_note.duration;
            }
        }

        // Add barline
        try self.note_attr_generator.writeBarline(xml_writer);

        // End measure element
        try xml_writer.endElement(); // measure
    }

    /// Generate dynamics direction element
    fn generateDynamicsDirection(
        self: *const Generator,
        xml_writer: *XmlWriter,
        marking: dynamics_mapper.DynamicMarking,
    ) !void {
        _ = self;

        try xml_writer.startElement("direction", &[_]Attribute{
            .{ .name = "placement", .value = "below" },
        });

        try xml_writer.startElement("direction-type", null);
        try xml_writer.startElement("dynamics", null);

        // Use enum tag directly as XML element name
        const dynamic_element = std.meta.tagName(marking.dynamic);
        try xml_writer.startElement(dynamic_element, null);
        try xml_writer.endElement(); // dynamic element

        try xml_writer.endElement(); // dynamics
        try xml_writer.endElement(); // direction-type

        // Add <sound dynamics="..."> for playback velocity
        var velocity_buf: [8]u8 = undefined;
        const velocity_str = try std.fmt.bufPrint(&velocity_buf, "{d}", .{marking.dynamic.toMidiValue()});
        try xml_writer.startElement("sound", &[_]Attribute{
            .{ .name = "dynamics", .value = velocity_str },
        });
        try xml_writer.endElement(); // sound

        try xml_writer.endElement(); // direction
    }

    /// Generate an enhanced note element with educational metadata
    fn generateEnhancedNoteElement(
        self: *const Generator,
        xml_writer: *XmlWriter,
        enhanced: *const enhanced_note.EnhancedTimedNote,
        is_chord: bool,
    ) !void {
        const base_note = enhanced.getBaseNote();
        const is_rest = base_note.velocity == 0;

        try xml_writer.startElement("note", null);

        // Add chord element if this note is simultaneous with previous
        if (is_chord and !is_rest) {
            try xml_writer.writeEmptyElement("chord", null);
        }

        // Generate basic note content
        if (is_rest) {
            // Simpler: empty element instead of start+end
            try xml_writer.writeEmptyElement("rest", null);
        } else {
            const pitch = midiToPitch(base_note.note);
            try xml_writer.startElement("pitch", null);
            try xml_writer.writeElement("step", pitch.step, null);

            if (pitch.alter != 0) {
                var alter_buf: [8]u8 = undefined;
                const alter_str = try std.fmt.bufPrint(&alter_buf, "{d}", .{pitch.alter});
                try xml_writer.writeElement("alter", alter_str, null);
            }

            var octave_buf: [8]u8 = undefined;
            const octave_str = try std.fmt.bufPrint(&octave_buf, "{d}", .{pitch.octave});
            try xml_writer.writeElement("octave", octave_str, null);

            try xml_writer.endElement(); // pitch
        }

        // Convert MIDI ticks to MusicXML divisions (unchanged behavior)
        const duration_in_divisions = if (self.division_converter) |converter|
            try converter.convertTicksToDivisions(base_note.duration)
        else
            base_note.duration;

        // Write the actual duration (no forced quantization)
        var duration_buf: [32]u8 = undefined;
        const duration_str = try std.fmt.bufPrint(&duration_buf, "{d}", .{duration_in_divisions});
        try xml_writer.writeElement("duration", duration_str, null);

        // Compute staff once and reuse for both voice mapping and <staff>
        const staff_opt: ?u8 = if (!is_rest)
            @import("note_attributes.zig").getStaffForNote(base_note.note)
        else
            null;

        const staff_number: u8 = if (staff_opt) |s| s else 1;

        // Write voice with piano convention mapping
        const raw_voice_i = if (base_note.voice > 0) base_note.voice else 1;
        const mapped_voice = @import("note_attributes.zig").mapVoiceForPiano(raw_voice_i, staff_number);
        var voice_buf: [8]u8 = undefined;
        const voice_str = try std.fmt.bufPrint(&voice_buf, "{d}", .{mapped_voice});
        try xml_writer.writeElement("voice", voice_str, null);

        // Determine note type based on duration (integer-only version recommended earlier)
        const note_type = try self.determineNoteType(duration_in_divisions);
        try xml_writer.writeElement("type", note_type, null);

        // Write staff assignment for pitched notes
        if (!is_rest) {
            var staff_buf: [8]u8 = undefined;
            const staff_str = try std.fmt.bufPrint(&staff_buf, "{d}", .{staff_number});
            try xml_writer.writeElement("staff", staff_str, null);
        }

        // Tuplet handling (same semantics; start takes precedence over stop)
        if (enhanced.tuplet_info) |tuplet_info| {
            if (tuplet_info.isValid()) {
                try xml_writer.startElement("time-modification", null);

                var actual_buf: [8]u8 = undefined;
                const actual_str = try std.fmt.bufPrint(&actual_buf, "{d}", .{tuplet_info.tuplet_type.getActualCount()});
                try xml_writer.writeElement("actual-notes", actual_str, null);

                var normal_buf: [8]u8 = undefined;
                const normal_str = try std.fmt.bufPrint(&normal_buf, "{d}", .{tuplet_info.tuplet_type.getNormalCount()});
                try xml_writer.writeElement("normal-notes", normal_str, null);

                try xml_writer.endElement(); // time-modification

                if (tuplet_info.starts_tuplet) {
                    try xml_writer.startElement("notations", null);
                    try xml_writer.startElement("tuplet", &[_]Attribute{
                        .{ .name = "type", .value = "start" },
                        .{ .name = "number", .value = "1" },
                        .{ .name = "bracket", .value = "yes" },
                    });
                    try xml_writer.endElement(); // tuplet
                    try xml_writer.endElement(); // notations
                } else if (tuplet_info.ends_tuplet) {
                    try xml_writer.startElement("notations", null);
                    try xml_writer.startElement("tuplet", &[_]Attribute{
                        .{ .name = "type", .value = "stop" },
                        .{ .name = "number", .value = "1" },
                    });
                    try xml_writer.endElement(); // tuplet
                    try xml_writer.endElement(); // notations
                }
            }
        }

        // Stem direction for pitched notes (unchanged logic)
        if (!is_rest) {
            if (enhanced.stem_info) |stem_info| {
                const stem_str = stem_info.direction.toMusicXML();
                try xml_writer.writeElement("stem", stem_str, null);
            } else {
                const stem_dir = stem_direction.StemDirectionCalculator.calculateVoiceAwareStemDirection(base_note.note, 1);
                try xml_writer.writeElement("stem", stem_dir.toMusicXML(), null);
            }
        }

        // Beam information: simpler, no switch duplication
        if (enhanced.beaming_info) |beam_info| {
            if (beam_info.can_beam and beam_info.beam_state != .none) {
                const beam_text = std.meta.tagName(beam_info.beam_state); // "begin","continue","end"
                try xml_writer.writeElement("beam", beam_text, &[_]Attribute{
                    .{ .name = "number", .value = "1" },
                });
            }
        }

        try xml_writer.endElement(); // note
    }

    /// Generate a chord group with proper MusicXML chord notation
    /// Implements TASK 3.2 per INCREMENTAL_IMPLEMENTATION_TASK_LIST.md lines 342-415
    pub fn generateChordGroup(
        self: *const Generator,
        xml_writer: *XmlWriter,
        chord_group: chord_detector.ChordGroup,
        is_enhanced: bool,
    ) !void {
        if (chord_group.notes.len == 0) return;

        // First note in chord is written without <chord/> (establishes duration/voice)
        if (is_enhanced) {
            const first_enhanced = enhanced_note.EnhancedTimedNote.init(chord_group.notes[0], null);
            try self.generateEnhancedNoteElement(xml_writer, &first_enhanced, false);
        } else {
            // Preserve legacy behavior: first note uses voice = 1 in the non-enhanced path
            var first_note = chord_group.notes[0];
            first_note.voice = 1;
            const first_enhanced = enhanced_note.EnhancedTimedNote.init(first_note, null);
            try self.generateEnhancedNoteElement(xml_writer, &first_enhanced, false);
        }

        // Remaining notes in chord need <chord/>; reuse the same generator
        for (chord_group.notes[1..]) |note| {
            const enh = enhanced_note.EnhancedTimedNote.init(note, null);
            try self.generateEnhancedNoteElement(xml_writer, &enh, true);
        }
    }

    /// Convert enhanced notes to timed notes for chord detection
    fn convertEnhancedToTimedNotes(
        self: *const Generator,
        enhanced_notes: []const enhanced_note.EnhancedTimedNote,
    ) ![]timing.TimedNote {
        var timed_notes = try self.allocator.alloc(timing.TimedNote, enhanced_notes.len);
        for (enhanced_notes, 0..) |enhanced, i| {
            timed_notes[i] = enhanced.getBaseNote();
        }
        return timed_notes;
    }
};

test "XML header generation" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    try generator.writeXmlHeader(buffer.writer());

    const expected = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n" ++
        "<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">\n";

    try t.expectEqStrings(expected, buffer.items);
}

test "generate minimal valid MusicXML" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    try generator.generateMinimalMusicXML(buffer.writer());

    // Verify the output contains required elements
    const output = buffer.items;

    // Check for XML declaration
    try t.expect(std.mem.indexOf(u8, output, "<?xml version=\"1.0\"") != null);

    // Check for DOCTYPE
    try t.expect(std.mem.indexOf(u8, output, "<!DOCTYPE score-partwise") != null);

    // Check for required elements
    try t.expect(std.mem.indexOf(u8, output, "<score-partwise version=\"4.0\">") != null);
    try t.expect(std.mem.indexOf(u8, output, "<part-list>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<score-part id=\"P1\">") != null);
    try t.expect(std.mem.indexOf(u8, output, "<part-name>Music</part-name>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<part id=\"P1\">") != null);
    try t.expect(std.mem.indexOf(u8, output, "<measure number=\"1\">") != null);
    try t.expect(std.mem.indexOf(u8, output, "<divisions>480</divisions>") != null);

    // Check proper closing tags
    try t.expect(std.mem.indexOf(u8, output, "</score-partwise>") != null);
}

test "generate minimal MusicXML with notes" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    try generator.generateMinimalWithNotes(buffer.writer());

    const output = buffer.items;

    // Check for musical elements
    try t.expect(std.mem.indexOf(u8, output, "<key>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<fifths>0</fifths>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<time>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<beats>4</beats>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<beat-type>4</beat-type>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<clef>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<note>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<pitch>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<step>C</step>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<octave>4</octave>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<duration>480</duration>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<type>quarter</type>") != null);
}

test "generateBackupElement basic functionality" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);

    // Test backup element generation with quarter note duration
    try generator.generateBackupElement(&xml_writer, 480);

    const output = buffer.items;

    // Verify backup element structure
    try t.expect(std.mem.indexOf(u8, output, "<backup>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<duration>480</duration>") != null);
    try t.expect(std.mem.indexOf(u8, output, "</backup>") != null);
}

test "generateBackupElement with different durations" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);

    // Test half note backup (960 divisions)
    try generator.generateBackupElement(&xml_writer, 960);

    // Test whole note backup (1920 divisions)
    try generator.generateBackupElement(&xml_writer, 1920);

    const output = buffer.items;

    // Verify multiple backup elements with correct durations
    try t.expect(std.mem.indexOf(u8, output, "<duration>960</duration>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<duration>1920</duration>") != null);

    // Count backup elements (should be 2)
    var count: u32 = 0;
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, output, search_start, "<backup>")) |pos| {
        count += 1;
        search_start = pos + 8; // Move past "<backup>"
    }
    try t.expect(count == 2);
}

test "generateBackupElement with zero duration" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);

    // Test that zero duration produces no output
    try generator.generateBackupElement(&xml_writer, 0);

    const output = buffer.items;

    // Should produce no backup elements for zero duration
    try t.expect(std.mem.indexOf(u8, output, "<backup>") == null);
    try t.expect(output.len == 0);
}

test "groupNotesByVoice basic functionality" {
    const allocator = std.testing.allocator;
    const generator = Generator.init(allocator, 480);

    // Create test enhanced notes with different voices
    var test_notes = [_]enhanced_note.EnhancedTimedNote{
        enhanced_note.EnhancedTimedNote{
            .base_note = .{
                .note = 60, // C4
                .channel = 0,
                .velocity = 64,
                .duration = 480,
                .start_tick = 0,
                .track = 0,
                .voice = 1,
            },
        },
        enhanced_note.EnhancedTimedNote{
            .base_note = .{
                .note = 64, // E4
                .channel = 0,
                .velocity = 64,
                .duration = 480,
                .start_tick = 0,
                .track = 0,
                .voice = 1,
            },
        },
        enhanced_note.EnhancedTimedNote{
            .base_note = .{
                .note = 48, // C3
                .channel = 0,
                .velocity = 64,
                .duration = 960,
                .start_tick = 0,
                .track = 0,
                .voice = 5, // Bass voice
            },
        },
    };

    // Group notes by voice
    var voice_groups = try generator.groupNotesByVoice(allocator, &test_notes);
    defer {
        for (voice_groups.items) |*group| {
            group.deinit();
        }
        voice_groups.deinit();
    }

    // Should have 2 voice groups (voice 1 and voice 5)
    try t.expect(voice_groups.items.len == 2);

    // Check voice numbers are sorted correctly
    try t.expect(voice_groups.items[0].voice_number == 1);
    try t.expect(voice_groups.items[1].voice_number == 5);

    // Check note counts per voice
    try t.expect(voice_groups.items[0].notes.items.len == 2); // Two treble notes
    try t.expect(voice_groups.items[1].notes.items.len == 1); // One bass note

    // Check total durations
    try t.expect(voice_groups.items[0].total_duration == 960); // 480 + 480
    try t.expect(voice_groups.items[1].total_duration == 960); // 960
}

test "groupNotesByVoice with unassigned voice defaults to 1" {
    const allocator = std.testing.allocator;
    const generator = Generator.init(allocator, 480);

    // Create test note with voice = 0 (unassigned)
    var test_notes = [_]enhanced_note.EnhancedTimedNote{
        enhanced_note.EnhancedTimedNote{
            .base_note = .{
                .note = 60, // C4
                .channel = 0,
                .velocity = 64,
                .duration = 480,
                .start_tick = 0,
                .track = 0,
                .voice = 0, // Unassigned
            },
        },
    };

    // Group notes by voice
    var voice_groups = try generator.groupNotesByVoice(allocator, &test_notes);
    defer {
        for (voice_groups.items) |*group| {
            group.deinit();
        }
        voice_groups.deinit();
    }

    // Should default to voice 1
    try t.expect(voice_groups.items.len == 1);
    try t.expect(voice_groups.items[0].voice_number == 1);
    try t.expect(voice_groups.items[0].notes.items.len == 1);
}

test "performance - minimal MusicXML generation" {
    // Test that generation meets performance target (< 10ms)
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);

    const start = std.time.nanoTimestamp();
    try generator.generateMinimalMusicXML(buffer.writer());
    const end = std.time.nanoTimestamp();

    const elapsed_ns = end - start;
    const elapsed_ms = @divFloor(elapsed_ns, 1_000_000);

    // Should be well under 10ms
    try t.expect(elapsed_ms < 10);
}

// Tests for TASK-009: Basic Note Element Generation

test "MIDI to pitch conversion" {
    // Test middle C (MIDI note 60)
    {
        const pitch = midiToPitch(60);
        try t.expectEqStrings("C", pitch.step);
        try t.expectEq(0, pitch.alter);
        try t.expectEq(4, pitch.octave);
    }

    // Test C# (MIDI note 61)
    {
        const pitch = midiToPitch(61);
        try t.expectEqStrings("C", pitch.step);
        try t.expectEq(1, pitch.alter);
        try t.expectEq(4, pitch.octave);
    }

    // Test A4 (MIDI note 69) - concert pitch
    {
        const pitch = midiToPitch(69);
        try t.expectEqStrings("A", pitch.step);
        try t.expectEq(0, pitch.alter);
        try t.expectEq(4, pitch.octave);
    }

    // Test low C (MIDI note 24) - C1
    {
        const pitch = midiToPitch(24);
        try t.expectEqStrings("C", pitch.step);
        try t.expectEq(0, pitch.alter);
        try t.expectEq(1, pitch.octave);
    }

    // Test high C (MIDI note 108) - C8
    {
        const pitch = midiToPitch(108);
        try t.expectEqStrings("C", pitch.step);
        try t.expectEq(0, pitch.alter);
        try t.expectEq(8, pitch.octave);
    }

    // Test all chromatic notes in one octave
    const expected_steps = [_][]const u8{ "C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B" };
    const expected_alters = [_]i8{ 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0 };

    for (0..12) |i| {
        const pitch = midiToPitch(@as(u8, @intCast(60 + i)));
        try t.expectEqStrings(expected_steps[i], pitch.step);
        try t.expectEq(expected_alters[i], pitch.alter);
        try t.expectEq(4, pitch.octave);
    }
}

test "duration to note type conversion" {
    const divisions = 480; // Common divisions per quarter note

    // Test whole note (4 quarters)
    {
        const note_type = durationToNoteType(divisions * 4, divisions);
        try t.expectEq(NoteType.whole, note_type);
    }

    // Test half note (2 quarters)
    {
        const note_type = durationToNoteType(divisions * 2, divisions);
        try t.expectEq(NoteType.half, note_type);
    }

    // Test quarter note
    {
        const note_type = durationToNoteType(divisions, divisions);
        try t.expectEq(NoteType.quarter, note_type);
    }

    // Test eighth note
    {
        const note_type = durationToNoteType(divisions / 2, divisions);
        try t.expectEq(NoteType.eighth, note_type);
    }

    // Test sixteenth note
    {
        const note_type = durationToNoteType(divisions / 4, divisions);
        try t.expectEq(NoteType.@"16th", note_type);
    }

    // Test very short duration (256th note)
    {
        const note_type = durationToNoteType(1, divisions);
        try t.expectEq(NoteType.@"256th", note_type);
    }

    // Test breve (double whole note)
    {
        const note_type = durationToNoteType(divisions * 8, divisions);
        try t.expectEq(NoteType.breve, note_type);
    }
}

test "note type toString" {
    try t.expectEqStrings("whole", NoteType.whole.toString());
    try t.expectEqStrings("half", NoteType.half.toString());
    try t.expectEqStrings("quarter", NoteType.quarter.toString());
    try t.expectEqStrings("eighth", NoteType.eighth.toString());
    try t.expectEqStrings("16th", NoteType.@"16th".toString());
    try t.expectEqStrings("32nd", NoteType.@"32nd".toString());
}

test "generate single note element" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    // Generate a middle C quarter note
    try generator.generateNoteElement(&xml_writer, 60, 480, false);

    const output = buffer.items;

    // Check for required elements
    try t.expect(std.mem.indexOf(u8, output, "<note>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<pitch>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<step>C</step>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<octave>4</octave>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<duration>480</duration>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<type>quarter</type>") != null);
    try t.expect(std.mem.indexOf(u8, output, "</note>") != null);

    // Should not have alter element for natural note
    try t.expect(std.mem.indexOf(u8, output, "<alter>") == null);
}

test "generate note with accidental" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    // Generate a C# quarter note
    try generator.generateNoteElement(&xml_writer, 61, 480, false);

    const output = buffer.items;

    // Check for alter element
    try t.expect(std.mem.indexOf(u8, output, "<alter>1</alter>") != null);
}

test "generate rest element" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    // Generate a quarter rest
    try generator.generateNoteElement(&xml_writer, 0, 480, true);

    const output = buffer.items;

    // Check for rest element instead of pitch
    try t.expect(std.mem.indexOf(u8, output, "<rest>") != null);
    try t.expect(std.mem.indexOf(u8, output, "</rest>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<pitch>") == null);
    try t.expect(std.mem.indexOf(u8, output, "<duration>480</duration>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<type>quarter</type>") != null);
}

test "generate notes from MIDI events" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    // Create test MIDI events
    const events = [_]NoteEvent{
        .{
            .event_type = @import("../midi/parser.zig").MidiEventType.note_on,
            .channel = 0,
            .note = 60, // C4
            .velocity = 64,
            .tick = 0,
        },
        .{
            .event_type = @import("../midi/parser.zig").MidiEventType.note_on,
            .channel = 0,
            .note = 64, // E4
            .velocity = 64,
            .tick = 480,
        },
    };

    // Generate notes for tick range 0-960
    try generator.generateNotesFromMidiEvents(&xml_writer, &events, 0, 960);

    const output = buffer.items;

    // Should have generated two notes
    var note_count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOf(u8, output[pos..], "<note>")) |idx| {
        note_count += 1;
        pos += idx + 6;
    }
    try t.expectEq(2, note_count);
}

test "performance - note element generation" {
    // Test that note generation meets performance target (< 1μs per note)
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    const iterations = 10000;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        buffer.clearRetainingCapacity();
        try generator.generateNoteElement(&xml_writer, 60, 480, false);
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ns = @as(u64, @intCast(end - start));
    const ns_per_note = elapsed_ns / iterations;

    log.debug("Note element generation performance: {d} ns per note", .{ns_per_note});

    // Should be well under 1μs (1000ns) per note
    try t.expect(ns_per_note < 1000);
}

// Tests for automatic stem direction integration

test "stem direction in basic note generation" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    // Generate note below middle line (should have stem up)
    try generator.generateNoteElement(&xml_writer, 60, 480, false); // C4

    const output = buffer.items;

    // Verify stem direction is included
    try t.expect(std.mem.indexOf(u8, output, "<stem>up</stem>") != null);

    // Clear buffer and test note above middle line
    buffer.clearRetainingCapacity();
    xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    try generator.generateNoteElement(&xml_writer, 77, 480, false); // F5

    const output2 = buffer.items;
    try t.expect(std.mem.indexOf(u8, output2, "<stem>down</stem>") != null);
}

test "stem direction in note with attributes" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    // Test voice 1 (upper voice) with middle line note (should go up)
    try generator.generateNoteElementWithAttributes(&xml_writer, 71, 480, false, 1, 1); // B4 (middle line)

    const output = buffer.items;
    try t.expect(std.mem.indexOf(u8, output, "<stem>up</stem>") != null);

    // Clear buffer and test voice 2 (lower voice) with same note
    buffer.clearRetainingCapacity();
    xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    try generator.generateNoteElementWithAttributes(&xml_writer, 71, 480, false, 2, 1); // B4, voice 2

    const output2 = buffer.items;
    try t.expect(std.mem.indexOf(u8, output2, "<stem>down</stem>") != null);
}

test "stem direction not included for rests" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    // Generate rest - should not have stem direction
    try generator.generateNoteElement(&xml_writer, 0, 480, true);

    const output = buffer.items;

    // Verify no stem element for rests
    try t.expect(std.mem.indexOf(u8, output, "<stem>") == null);
    try t.expect(std.mem.indexOf(u8, output, "<rest>") != null);
}

test "polyphonic voice stem directions" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);
    var xml_writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer xml_writer.deinit();

    // Generate two notes on same pitch but different voices
    // Voice 1 (upper) should prefer up, Voice 2 (lower) should prefer down
    const middle_note: u8 = 71; // B4 (middle line)

    // Voice 1 note
    try generator.generateNoteElementWithAttributes(&xml_writer, middle_note, 480, false, 1, 1);

    // Voice 2 note
    try generator.generateNoteElementWithAttributes(&xml_writer, middle_note, 480, false, 2, 1);

    const output = buffer.items;

    // Should have both up and down stem directions
    try t.expect(std.mem.indexOf(u8, output, "<stem>up</stem>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<stem>down</stem>") != null);

    // Count occurrences to ensure both are present
    var up_count: usize = 0;
    var down_count: usize = 0;
    var pos: usize = 0;

    while (std.mem.indexOf(u8, output[pos..], "<stem>up</stem>")) |idx| {
        up_count += 1;
        pos += idx + 14; // Length of "<stem>up</stem>"
    }

    pos = 0;
    while (std.mem.indexOf(u8, output[pos..], "<stem>down</stem>")) |idx| {
        down_count += 1;
        pos += idx + 16; // Length of "<stem>down</stem>"
    }

    try t.expectEq(1, up_count);
    try t.expectEq(1, down_count);
}

// Tests for barline visibility fix and measure boundary logic

test "MeasureState - initialization and basic operations" {
    // Test 4/4 time signature
    var measure_state = MeasureState.init(4, 4, 480);
    try t.expectEq(1920, measure_state.max_duration); // 4 * 4 * 480 / 4
    try t.expectEq(0, measure_state.current_duration);
    try t.expectEq(1, measure_state.measure_number);

    // Test adding notes
    try t.expect(measure_state.canAddNote(480)); // Quarter note
    measure_state.addNote(480);
    try t.expectEq(480, measure_state.current_duration);
    try t.expectEq(1440, measure_state.getRemainingDuration());

    // Test measure overflow detection
    try t.expect(measure_state.canAddNote(1440)); // Can fit 3 more quarter notes
    try t.expectFalse(measure_state.canAddNote(1441)); // Cannot fit more than 1440

    // Fill measure completely
    measure_state.addNote(1440);
    try t.expect(measure_state.isMeasureFull());
    try t.expectEq(0, measure_state.getRemainingDuration());

    // Start new measure
    measure_state.startNewMeasure();
    try t.expectEq(2, measure_state.measure_number);
    try t.expectEq(0, measure_state.current_duration);
}

test "MeasureState - different time signatures" {
    // Test 3/4 time
    const measure_3_4 = MeasureState.init(3, 4, 480);
    try t.expectEq(1440, measure_3_4.max_duration); // 3 * 4 * 480 / 4

    // Test 6/8 time
    const measure_6_8 = MeasureState.init(6, 8, 480);
    try t.expectEq(1440, measure_6_8.max_duration); // 6 * 8 * 480 / 4 / 2
}

test "generate MusicXML with measure boundaries" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const generator = Generator.init(std.testing.allocator, 480);

    // Create test MIDI events that span multiple measures
    const events = [_]NoteEvent{
        .{ .event_type = @import("../midi/parser.zig").MidiEventType.note_on, .channel = 0, .note = 60, .velocity = 64, .tick = 0 }, // C4
        .{ .event_type = @import("../midi/parser.zig").MidiEventType.note_on, .channel = 0, .note = 62, .velocity = 64, .tick = 480 }, // D4
        .{ .event_type = @import("../midi/parser.zig").MidiEventType.note_on, .channel = 0, .note = 64, .velocity = 64, .tick = 960 }, // E4
        .{ .event_type = @import("../midi/parser.zig").MidiEventType.note_on, .channel = 0, .note = 65, .velocity = 64, .tick = 1440 }, // F4
        .{ .event_type = @import("../midi/parser.zig").MidiEventType.note_on, .channel = 0, .note = 67, .velocity = 64, .tick = 1920 }, // G4 (start of measure 2)
        .{ .event_type = @import("../midi/parser.zig").MidiEventType.note_on, .channel = 0, .note = 69, .velocity = 64, .tick = 2400 }, // A4
        .{ .event_type = @import("../midi/parser.zig").MidiEventType.note_on, .channel = 0, .note = 71, .velocity = 64, .tick = 2880 }, // B4
    };

    try generator.generateMusicXMLWithMeasureBoundaries(buffer.writer(), &events, 120); // Default tempo for test

    const output = buffer.items;

    // Check for proper structure
    try t.expect(std.mem.indexOf(u8, output, "<?xml version=\"1.0\"") != null);
    try t.expect(std.mem.indexOf(u8, output, "<score-partwise version=\"4.0\">") != null);

    // Check for multiple measures
    var measure_count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOf(u8, output[pos..], "<measure number=")) |idx| {
        measure_count += 1;
        pos += idx + 1;
    }
    try t.expect(measure_count >= 2); // Should have at least 2 measures

    // Check for attributes in each measure
    try t.expect(std.mem.indexOf(u8, output, "<attributes>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<divisions>480</divisions>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<key>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<fifths>0</fifths>") != null);
    try t.expect(std.mem.indexOf(u8, output, "<staves>1</staves>") != null);

    // Check for barlines
    try t.expect(std.mem.indexOf(u8, output, "<barline location=\"right\">") != null);
    try t.expect(std.mem.indexOf(u8, output, "<bar-style>regular</bar-style>") != null);

    // Check for time signature only in first measure
    const time_occurrences = std.mem.count(u8, output, "<time>");
    try t.expectEq(1, time_occurrences);
}

test "measure duration validation - 4/4 time" {
    // Verify that each measure has exactly 1920 duration units for 4/4 time
    const measure_state = MeasureState.init(4, 4, 480);
    try t.expectEq(1920, measure_state.max_duration);

    // 4 quarter notes should exactly fill a measure
    var test_state = measure_state;
    try t.expect(test_state.canAddNote(480)); // 1st quarter
    test_state.addNote(480);
    try t.expect(test_state.canAddNote(480)); // 2nd quarter
    test_state.addNote(480);
    try t.expect(test_state.canAddNote(480)); // 3rd quarter
    test_state.addNote(480);
    try t.expect(test_state.canAddNote(480)); // 4th quarter
    test_state.addNote(480);

    try t.expect(test_state.isMeasureFull());
    try t.expectFalse(test_state.canAddNote(1)); // No room for even 1 more tick
}

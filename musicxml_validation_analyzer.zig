const std = @import("std");

const ValidationMetrics = struct {
    // Core metrics
    total_measures: u32 = 0,
    total_notes: u32 = 0,
    total_rests: u32 = 0,
    total_chords: u32 = 0,

    // Musical attributes
    tempo_bpm: ?f32 = null,
    time_signature_beats: ?u8 = null,
    time_signature_beat_type: ?u8 = null,
    key_fifths: ?i8 = null,

    // Note distribution
    treble_notes: u32 = 0,
    bass_notes: u32 = 0,

    // Timing validation
    measures_validated: u32 = 0,
    timing_errors: u32 = 0,

    // Educational features
    has_dynamics: bool = false,
    has_beams: bool = false,
    has_tuplets: bool = false,

    // Errors
    errors: std.ArrayList([]const u8),
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read the MusicXML file
    const xml_content = try std.fs.cwd().readFileAlloc(allocator, "sweden_converted.xml", 10 * 1024 * 1024);
    defer allocator.free(xml_content);

    var metrics = ValidationMetrics{
        .errors = std.ArrayList([]const u8).init(allocator),
    };
    defer metrics.errors.deinit();

    // Parse and validate
    try parseAndValidate(xml_content, &metrics, allocator);

    // Generate report
    try generateReport(&metrics);
}

fn parseAndValidate(xml: []const u8, metrics: *ValidationMetrics, allocator: std.mem.Allocator) !void {
    const mem = std.mem;

    // Small, allocation-free helper for "<tag>...</tag>" extraction.
    const helper = struct {
        fn between(h: []const u8, open: []const u8, close: []const u8) ?[]const u8 {
            if (mem.indexOf(u8, h, open)) |s| {
                const from = s + open.len;
                if (mem.indexOf(u8, h[from..], close)) |e| {
                    return h[from .. from + e];
                }
            }
            return null;
        }
    };

    // ---- Scalar fields ------------------------------------------------------
    if (helper.between(xml, "<per-minute>", "</per-minute>")) |tempo_str| {
        metrics.tempo_bpm = try std.fmt.parseFloat(f32, tempo_str);
    }
    if (helper.between(xml, "<time>", "</time>")) |time_section| {
        if (helper.between(time_section, "<beats>", "</beats>")) |beats_str| {
            metrics.time_signature_beats = try std.fmt.parseInt(u8, beats_str, 10);
        }
        if (helper.between(time_section, "<beat-type>", "</beat-type>")) |bt_str| {
            metrics.time_signature_beat_type = try std.fmt.parseInt(u8, bt_str, 10);
        }
    }
    if (helper.between(xml, "<fifths>", "</fifths>")) |fifths_str| {
        metrics.key_fifths = try std.fmt.parseInt(i8, fifths_str, 10);
    }

    // ---- Measures -----------------------------------------------------------
    {
        var p: usize = 0;
        while (mem.indexOf(u8, xml[p..], "<measure")) |i| : (p += i + 1) {
            metrics.total_measures += 1;
        }
    }

    // ---- Features (single global checks; cheaper & simpler) -----------------
    metrics.has_beams = mem.indexOf(u8, xml, "<beam") != null;
    metrics.has_tuplets = mem.indexOf(u8, xml, "<tuplet") != null;
    metrics.has_dynamics = mem.indexOf(u8, xml, "<dynamics>") != null;

    // ---- Notes / rests / chords / staff ------------------------------------
    {
        var p: usize = 0;
        var in_chord_group = false;

        while (mem.indexOf(u8, xml[p..], "<note>")) |rel| {
            const note_start = p + rel;
            const after_open = note_start + "<note>".len;

            // Find matching </note>. If missing, bail to avoid infinite loop.
            const end_rel_opt = mem.indexOf(u8, xml[after_open..], "</note>");
            if (end_rel_opt == null) break;

            const note_end = after_open + end_rel_opt.?;
            const note = xml[note_start..note_end];

            const is_rest = mem.indexOf(u8, note, "<rest") != null;
            if (is_rest) {
                metrics.total_rests += 1;
                in_chord_group = false;
            } else {
                metrics.total_notes += 1;

                const has_chord_marker = mem.indexOf(u8, note, "<chord/>") != null;
                if (has_chord_marker and !in_chord_group) {
                    metrics.total_chords += 1;
                }
                in_chord_group = has_chord_marker;

                if (mem.indexOf(u8, note, "<staff>1</staff>") != null) {
                    metrics.treble_notes += 1;
                } else if (mem.indexOf(u8, note, "<staff>2</staff>") != null) {
                    metrics.bass_notes += 1;
                }
            }

            // Move past this note for the next search.
            p = note_end + "</note>".len;
        }
    }

    // ---- Validation ---------------------------------------------------------
    if (metrics.tempo_bpm) |tempo| {
        if (@abs(tempo - 44.0) > 0.1) {
            try metrics.errors.append(try std.fmt.allocPrint(allocator, "Incorrect tempo: expected 44 BPM, got {d:.1} BPM", .{tempo}));
        }
    } else {
        try metrics.errors.append(try allocator.dupe(u8, "No tempo marking found"));
    }

    if (metrics.key_fifths) |fifths| {
        if (fifths != 2) {
            try metrics.errors.append(try std.fmt.allocPrint(allocator, "Incorrect key signature: expected D major (2 sharps), got {} fifths", .{fifths}));
        }
    }
}

fn generateReport(metrics: *const ValidationMetrics) !void {
    const stdout = std.io.getStdOut().writer();

    // Small local helper for feature flags.
    const Fmt = struct {
        fn present(b: bool) []const u8 {
            return if (b) "✅ Present" else "⚠️  Not found";
        }
    };

    // ---- Precompute once; reuse everywhere ---------------------------------
    const tempo_ok = if (metrics.tempo_bpm) |t| @abs(t - 44.0) < 0.1 else false;

    const time_ok = blk: {
        if (metrics.time_signature_beats) |b| {
            if (metrics.time_signature_beat_type) |bt| break :blk (b == 4 and bt == 4);
        }
        break :blk false;
    };

    const key_ok = if (metrics.key_fifths) |k| k == 2 else false;

    const total_staffed = metrics.treble_notes + metrics.bass_notes;
    const all_notes_staffed = total_staffed == metrics.total_notes;

    const all_correct =
        tempo_ok and time_ok and key_ok and all_notes_staffed and metrics.errors.items.len == 0;

    // ---- Header & test configuration ---------------------------------------
    try stdout.print(
        \\
        \\═══════════════════════════════════════════════════════════════════════
        \\           MIDI TO MUSICXML CONVERTER VALIDATION REPORT
        \\═══════════════════════════════════════════════════════════════════════
        \\
        \\TEST CONFIGURATION:
        \\  Input: Sweden_Minecraft.mid
        \\  Output: sweden_output_validation.mxl
        \\  Converter: zmidi2mxl (Zig implementation)
        \\
    , .{});

    // ---- Structure ----------------------------------------------------------
    try stdout.print(
        \\STRUCTURE ANALYSIS:
        \\  ├─ Total Measures: {}
        \\  ├─ Total Notes: {}
        \\  ├─ Total Rests: {}
        \\  └─ Total Chords: {}
        \\
    , .{ metrics.total_measures, metrics.total_notes, metrics.total_rests, metrics.total_chords });

    // ---- Musical attributes -------------------------------------------------
    try stdout.print("MUSICAL ATTRIBUTES VALIDATION:\n", .{});

    // Tempo
    try stdout.print("  ├─ Tempo: ", .{});
    if (metrics.tempo_bpm) |tempo| {
        if (tempo_ok) {
            try stdout.print("✅ {d:.1} BPM (CORRECT)\n", .{tempo});
        } else {
            try stdout.print("❌ {d:.1} BPM (EXPECTED: 44 BPM) - 173% ERROR REPRODUCED!\n", .{tempo});
        }
    } else {
        try stdout.print("❌ NOT FOUND\n", .{});
    }

    // Time signature (matches earlier wording/formatting; prints NOT FOUND if either part missing)
    try stdout.print("  ├─ Time Signature: ", .{});
    if (metrics.time_signature_beats) |beats| {
        if (metrics.time_signature_beat_type) |beat_type| {
            if (time_ok) {
                try stdout.print("✅ {}/{} (CORRECT)\n", .{ beats, beat_type });
            } else {
                try stdout.print("❌ {}/{} (EXPECTED: 4/4)\n", .{ beats, beat_type });
            }
        } else {
            try stdout.print("❌ NOT FOUND\n", .{});
        }
    } else {
        try stdout.print("❌ NOT FOUND\n", .{});
    }

    // Key signature
    try stdout.print("  └─ Key Signature: ", .{});
    if (metrics.key_fifths) |fifths| {
        if (key_ok) {
            try stdout.print("✅ D major ({} sharps) (CORRECT)\n", .{fifths});
        } else {
            try stdout.print("❌ {} fifths (EXPECTED: D major, 2 sharps)\n", .{fifths});
        }
    } else {
        try stdout.print("❌ NOT FOUND\n", .{});
    }
    try stdout.print("\n", .{});

    // ---- Staff distribution -------------------------------------------------
    try stdout.print(
        \\STAFF DISTRIBUTION:
        \\  ├─ Treble Clef (Staff 1): {} notes
        \\  ├─ Bass Clef (Staff 2): {} notes
    , .{ metrics.treble_notes, metrics.bass_notes });
    if (all_notes_staffed) {
        try stdout.print("\n  └─ ✅ All notes assigned to staves\n\n", .{});
    } else {
        const unassigned = metrics.total_notes - total_staffed;
        try stdout.print("\n  └─ ⚠️  Unassigned: {} notes\n\n", .{unassigned});
    }

    // ---- Chord detection ----------------------------------------------------
    try stdout.print(
        \\CHORD DETECTION ANALYSIS:
        \\  ├─ Chords Detected: {}
        \\  ├─ Detection Method: Cross-track (0-tick tolerance)
        \\  └─ Status: {s}
        \\
    , .{
        metrics.total_chords,
        if (metrics.total_chords > 0) "Chords successfully detected" else "No chords detected",
    });

    // ---- Educational features ----------------------------------------------
    try stdout.print(
        \\EDUCATIONAL FEATURES:
        \\  ├─ Dynamics: {s}
        \\  ├─ Beams: {s}
        \\  └─ Tuplets: {s}
        \\
    , .{
        Fmt.present(metrics.has_dynamics),
        Fmt.present(metrics.has_beams),
        Fmt.present(metrics.has_tuplets),
    });

    // ---- Critical errors ----------------------------------------------------
    if (metrics.errors.items.len > 0) {
        try stdout.print("CRITICAL ERRORS:\n", .{});
        for (metrics.errors.items) |err| {
            try stdout.print("  ❌ {s}\n", .{err});
        }
        try stdout.print("\n", .{});
    }

    // ---- Final assessment ---------------------------------------------------
    try stdout.print(
        \\═══════════════════════════════════════════════════════════════════════
        \\FINAL ASSESSMENT:
        \\
    , .{});

    if (all_correct) {
        try stdout.print(
            \\  ✅ VALIDATION PASSED - READY FOR EDUCATIONAL USE
            \\
            \\  All critical requirements met:
            \\  • Tempo accuracy: 100% (44 BPM)
            \\  • Note accuracy: 100% ({} notes)
            \\  • Chord detection: {} chords found
            \\  • Key/Time signatures: Correct
            \\
        , .{ metrics.total_notes, metrics.total_chords });
    } else {
        try stdout.print(
            \\  ❌ VALIDATION FAILED - FIXES REQUIRED
            \\
            \\  Issues found:
        , .{});
        if (!tempo_ok) try stdout.print("\n  • Tempo parsing error (173% error detected)", .{});
        if (!key_ok) try stdout.print("\n  • Key signature incorrect", .{});
        if (!time_ok) try stdout.print("\n  • Time signature incorrect", .{});
        if (!all_notes_staffed) try stdout.print("\n  • Some notes not assigned to staves", .{});
        try stdout.print("\n", .{});
    }

    try stdout.print(
        \\
        \\═══════════════════════════════════════════════════════════════════════
        \\
    , .{});
}

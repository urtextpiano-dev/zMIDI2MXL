const std = @import("std");
const Pipeline = @import("../../src/pipeline.zig").Pipeline;
const PipelineConfig = @import("../../src/pipeline.zig").PipelineConfig;

const golden_files = [_][]const u8{
    "simple_scale.mid",
    "chord_progression.mid", 
    "tuplet_example.mid",
    "key_change.mid",
    "tempo_change.mid",
    "accidentals.mid",
    "multi_voice.mid",
    "dynamics.mid",
};

/// Safe XML canonicalization that preserves text content
fn canonicalizeXML(alloc: std.mem.Allocator, xml: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();

    var buf = std.ArrayList(u8).init(alloc); // between-tags candidate buffer
    defer buf.deinit();

    var in_tag = false;
    var i: usize = 0;

    while (i < xml.len) : (i += 1) {
        var c = xml[i];
        // Normalize newlines to \n
        if (c == '\r') {
            if (i + 1 < xml.len and xml[i + 1] == '\n') i += 1;
            c = '\n';
        }

        if (in_tag) {
            try out.append(c);
            if (c == '>') in_tag = false;
            continue;
        }

        if (c == '<') {
            // Decide how to flush buffered run
            const run = buf.items;
            var all_ws = true;
            for (run) |rc| {
                if (!std.ascii.isWhitespace(rc)) { 
                    all_ws = false; 
                    break; 
                }
            }
            if (all_ws and run.len > 0) {
                // Collapse whitespace-only inter-tag region
                if (out.items.len == 0 or out.items[out.items.len - 1] != '\n')
                    try out.append('\n');
            } else {
                // Preserve text content verbatim
                try out.appendSlice(run);
            }
            buf.clearRetainingCapacity();

            try out.append('<');
            in_tag = true;
            continue;
        }

        // Outside tags: buffer until we know if it's whitespace-only
        try buf.append(c);
    }

    // Handle trailing content
    if (buf.items.len != 0) {
        // Check if trailing content is all whitespace
        var all_ws = true;
        for (buf.items) |rc| {
            if (!std.ascii.isWhitespace(rc)) {
                all_ws = false;
                break;
            }
        }
        
        if (all_ws) {
            // Collapse trailing whitespace to single newline
            if (out.items.len == 0 or out.items[out.items.len - 1] != '\n')
                try out.append('\n');
        } else {
            // Preserve non-whitespace trailing content
            try out.appendSlice(buf.items);
        }
    }

    return out.toOwnedSlice();
}

test "golden output validation" {
    const allocator = std.testing.allocator;
    
    // Safe env var check
    const update = std.process.hasEnvVar("UPDATE_GOLDEN") catch false;
    
    // Ensure expected directory exists if updating
    if (update) {
        const expected_dir = "tests/golden/expected";
        try std.fs.cwd().makePath(expected_dir);
    }
    
    for (golden_files) |filename| {
        // Read input MIDI
        const input_path = try std.fmt.allocPrint(allocator, "tests/golden/inputs/{s}", .{filename});
        defer allocator.free(input_path);
        
        // Skip if input doesn't exist
        const midi_data = std.fs.cwd().readFileAlloc(allocator, input_path, 1024 * 1024) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("Skipping {s}: input not found\n", .{filename});
                continue;
            }
            return err;
        };
        defer allocator.free(midi_data);
        
        // CRITICAL: Use the REAL converter pipeline
        const config = PipelineConfig{
            .enable_educational_processing = false,
            .enable_measure_detection = true,
            .enable_notation_processing = true,
            .educational_config = null,
        };
        var pipeline = Pipeline.init(allocator, config);
        defer pipeline.deinit();
        
        var result = try pipeline.convertMidiToMxl(midi_data);
        defer result.deinit(allocator);
        
        // Canonicalize output
        const canonical_output = try canonicalizeXML(allocator, result.musicxml_content);
        defer allocator.free(canonical_output);
        
        // Read or create expected output
        const base_name = std.fs.path.stem(filename);
        const expected_path = try std.fmt.allocPrint(allocator, "tests/golden/expected/{s}.xml", .{base_name});
        defer allocator.free(expected_path);
        
        const expected_raw = std.fs.cwd().readFileAlloc(allocator, expected_path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                if (!update) {
                    std.debug.print("Missing baseline for {s}; set UPDATE_GOLDEN=1 to create.\n", .{filename});
                    continue;
                }
                std.debug.print("Creating baseline for {s}\n", .{filename});
                try std.fs.cwd().writeFile(.{ .sub_path = expected_path, .data = canonical_output });
                continue;
            },
            else => return err,
        };
        defer allocator.free(expected_raw);
        
        // Canonicalize expected
        const canonical_expected = try canonicalizeXML(allocator, expected_raw);
        defer allocator.free(canonical_expected);
        
        // Compare
        if (!std.mem.eql(u8, canonical_output, canonical_expected)) {
            std.debug.print("Golden test failed for {s}\n", .{filename});
            
            // Show diff preview
            const preview_len = @min(500, @min(canonical_expected.len, canonical_output.len));
            std.debug.print("Expected (first {d} chars):\n{s}\n", .{preview_len, canonical_expected[0..preview_len]});
            std.debug.print("Got (first {d} chars):\n{s}\n", .{preview_len, canonical_output[0..preview_len]});
            
            if (update) {
                std.debug.print("Updating baseline for {s}\n", .{filename});
                try std.fs.cwd().writeFile(.{ .sub_path = expected_path, .data = canonical_output });
            } else {
                return error.GoldenTestFailed;
            }
        } else {
            std.debug.print("✓ {s} matches baseline\n", .{filename});
        }
    }
}

test "canonicalizeXML preserves text content" {
    const allocator = std.testing.allocator;
    
    // Test that text content is preserved
    const input = 
        \\<root>
        \\  <lyric>Hello World</lyric>
        \\  <direction>Allegro  molto</direction>
        \\</root>
    ;
    
    const canonical = try canonicalizeXML(allocator, input);
    defer allocator.free(canonical);
    
    // Text content should be preserved exactly
    try std.testing.expect(std.mem.indexOf(u8, canonical, "Hello World") != null);
    try std.testing.expect(std.mem.indexOf(u8, canonical, "Allegro  molto") != null);
}

test "canonicalizeXML collapses trailing whitespace" {
    const allocator = std.testing.allocator;
    
    const input = "<root>text</root>   \n\t  ";
    const canonical = try canonicalizeXML(allocator, input);
    defer allocator.free(canonical);
    
    // Should end with single newline, not the trailing whitespace
    try std.testing.expect(canonical[canonical.len - 1] == '\n');
    try std.testing.expect(!std.ascii.isWhitespace(canonical[canonical.len - 2]) or canonical[canonical.len - 2] == '>');
}
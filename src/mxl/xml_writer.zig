const std = @import("std");
const containers = @import("../utils/containers.zig");
const error_mod = @import("../error.zig");

// Implements TASK-007 per MXL_Architecture_Reference.md Section 6.2 lines 770-880
// XML Writer Infrastructure for generating well-formed XML with proper character escaping

/// XML writer that generates well-formed XML with proper UTF-8 encoding
pub const XmlWriter = struct {
    writer: std.io.AnyWriter,
    indent_level: u32 = 0,
    indent_string: []const u8 = "  ",
    element_stack: containers.List([]const u8),
    allocator: std.mem.Allocator,
    bytes_written: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter) XmlWriter {
        return .{
            .writer = writer,
            .allocator = allocator,
            .element_stack = containers.List([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *XmlWriter) void {
        self.element_stack.deinit();
    }

    /// Write XML declaration
    pub fn writeDeclaration(self: *XmlWriter) !void {
        const decl = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n";
        try self.writer.writeAll(decl);
        self.bytes_written += decl.len;
    }

    /// Write DOCTYPE declaration
    pub fn writeDoctype(self: *XmlWriter, root_element: []const u8, public_id: []const u8, system_id: []const u8) !void {
        try self.writer.print("<!DOCTYPE {s} PUBLIC \"{s}\" \"{s}\">\n", .{ root_element, public_id, system_id });
        // Keep existing approximate count to preserve current side-effects.
        self.bytes_written += 50 + root_element.len + public_id.len + system_id.len;
    }

    /// Start an XML element with optional attributes
    pub fn startElement(self: *XmlWriter, name: []const u8, attributes: ?[]const Attribute) !void {
        try self.writeIndent();
        try self.writer.writeByte('<');
        try self.writer.writeAll(name);
        try self.writeAttributes(attributes);
        try self.writer.writeByte('>');

        // Track element for proper closing
        try self.element_stack.append(name);
        self.indent_level += 1;
    }

    /// Write an empty element (self-closing)
    pub fn writeEmptyElement(self: *XmlWriter, name: []const u8, attributes: ?[]const Attribute) !void {
        try self.writeIndent();
        try self.writer.writeByte('<');
        try self.writer.writeAll(name);
        try self.writeAttributes(attributes);
        try self.writer.writeAll("/>\n");
    }

    /// End the current element
    pub fn endElement(self: *XmlWriter) !void {
        // Pop first to avoid indent underflow and duplicate checks
        const name = self.element_stack.pop() orelse {
            return error_mod.MxlError.InvalidXmlStructure;
        };
        if (self.indent_level > 0) self.indent_level -= 1;

        try self.writeIndent();
        try self.writer.print("</{s}>\n", .{name});
    }

    /// Write text content with proper escaping
    pub fn writeText(self: *XmlWriter, text: []const u8) !void {
        try self.writeEscapedText(text);
    }

    /// Write a complete element with text content
    pub fn writeElement(self: *XmlWriter, name: []const u8, text: []const u8, attributes: ?[]const Attribute) !void {
        try self.writeIndent();
        try self.writer.writeByte('<');
        try self.writer.writeAll(name);
        try self.writeAttributes(attributes);
        try self.writer.writeByte('>');
        try self.writeEscapedText(text);
        try self.writer.print("</{s}>\n", .{name});
    }

    /// Write raw content (already escaped/formatted)
    pub fn writeRaw(self: *XmlWriter, content: []const u8) !void {
        try self.writer.writeAll(content);
        self.bytes_written += content.len;
    }

    /// Write newline
    pub fn writeNewline(self: *XmlWriter) !void {
        try self.writer.writeByte('\n');
        self.bytes_written += 1;
    }

    // ----------------
    // Private helpers
    // ----------------

    fn writeIndent(self: *XmlWriter) !void {
        var i: u32 = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.writer.writeAll(self.indent_string);
        }
    }

    /// Single place to emit attributes with escaping (DRY).
    fn writeAttributes(self: *XmlWriter, attributes: ?[]const Attribute) !void {
        if (attributes) |attrs| {
            for (attrs) |attr| {
                try self.writer.writeByte(' ');
                try self.writer.writeAll(attr.name);
                try self.writer.writeAll("=\"");
                try self.writeEscapedAttribute(attr.value);
                try self.writer.writeByte('"');
            }
        }
    }

    fn writeEscapedText(self: *XmlWriter, text: []const u8) !void {
        for (text) |char| {
            switch (char) {
                '&' => try self.writer.writeAll("&amp;"),
                '<' => try self.writer.writeAll("&lt;"),
                '>' => try self.writer.writeAll("&gt;"),
                else => try self.writer.writeByte(char),
            }
        }
    }

    fn writeEscapedAttribute(self: *XmlWriter, text: []const u8) !void {
        for (text) |char| {
            switch (char) {
                '&' => try self.writer.writeAll("&amp;"),
                '<' => try self.writer.writeAll("&lt;"),
                '>' => try self.writer.writeAll("&gt;"),
                '"' => try self.writer.writeAll("&quot;"),
                '\'' => try self.writer.writeAll("&apos;"),
                else => try self.writer.writeByte(char),
            }
        }
    }
};

/// Attribute key-value pair
pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
};

/// Validate UTF-8 encoding (correct and simple).
/// Uses the standard library to reject overlongs, surrogates, and >U+10FFFF.
pub fn validateUtf8(bytes: []const u8) bool {
    _ = std.unicode.Utf8View.init(bytes) catch return false;
    return true;
}

// Tests

test "XML declaration and doctype" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer writer.deinit();

    try writer.writeDeclaration();
    try writer.writeDoctype("score-partwise", "-//Recordare//DTD MusicXML 4.0 Partwise//EN", "http://www.musicxml.org/dtds/partwise.dtd");

    const expected =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n" ++
        "<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">\n";

    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "XML element generation" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer writer.deinit();

    try writer.startElement("note", null);
    try writer.writeElement("pitch", "C4", null);
    try writer.writeElement("duration", "480", null);
    try writer.endElement();

    const expected =
        "<note>\n" ++
        "  <pitch>C4</pitch>\n" ++
        "  <duration>480</duration>\n" ++
        "</note>\n";

    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "XML character escaping" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer writer.deinit();

    try writer.writeElement("text", "This & that < more > content", null);

    const expected = "<text>This &amp; that &lt; more &gt; content</text>\n";
    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "XML attributes" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer writer.deinit();

    const attrs = [_]Attribute{
        .{ .name = "id", .value = "P1" },
        .{ .name = "name", .value = "Piano \"Solo\"" },
    };

    try writer.writeElement("part", "content", &attrs);

    const expected = "<part id=\"P1\" name=\"Piano &quot;Solo&quot;\">content</part>\n";
    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "UTF-8 validation" {
    // Valid UTF-8
    try std.testing.expect(validateUtf8("Hello"));
    try std.testing.expect(validateUtf8("Café"));
    try std.testing.expect(validateUtf8("𝄞")); // Musical symbol

    // Invalid UTF-8
    try std.testing.expect(!validateUtf8(&[_]u8{ 0xFF, 0xFE }));
    try std.testing.expect(!validateUtf8(&[_]u8{ 0xC0, 0x00 })); // Invalid continuation
}

test "Empty elements" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer writer.deinit();

    try writer.writeEmptyElement("chord", null);
    try writer.writeEmptyElement("rest", &[_]Attribute{
        .{ .name = "measure", .value = "yes" },
    });

    const expected =
        "<chord/>\n" ++
        "<rest measure=\"yes\"/>\n";

    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "Nested elements" {
    var buffer = containers.List(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = XmlWriter.init(std.testing.allocator, buffer.writer().any());
    defer writer.deinit();

    try writer.startElement("measure", &[_]Attribute{
        .{ .name = "number", .value = "1" },
    });
    try writer.startElement("note", null);
    try writer.writeElement("duration", "480", null);
    try writer.endElement(); // note
    try writer.endElement(); // measure

    const expected =
        "<measure number=\"1\">\n" ++
        "  <note>\n" ++
        "    <duration>480</duration>\n" ++
        "  </note>\n" ++
        "</measure>\n";

    try std.testing.expectEqualStrings(expected, buffer.items);
}

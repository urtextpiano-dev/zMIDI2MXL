const std = @import("std");
const XmlWriter = @import("xml_writer.zig").XmlWriter;

/// Helper to write integer values as XML elements - reduces code duplication
/// This is a zero-cost abstraction that will be inlined by the compiler
pub fn writeIntElement(xml_writer: *XmlWriter, comptime tag: []const u8, value: anytype) !void {
    var buf: [32]u8 = undefined;
    const str = try std.fmt.bufPrint(&buf, "{d}", .{value});
    try xml_writer.writeElement(tag, str, null);
}

/// Write float/decimal values as XML elements with specified precision
/// Example: writeFloatElement(writer, "tempo", 120.5, 1) outputs <tempo>120.5</tempo>
pub fn writeFloatElement(
    xml_writer: *XmlWriter,
    comptime tag: []const u8,
    value: anytype,
    comptime precision: u8,
) !void {
    var buf: [64]u8 = undefined;
    const format = comptime std.fmt.comptimePrint("{{d:.{d}}}", .{precision});
    const str = try std.fmt.bufPrint(&buf, format, .{value});
    try xml_writer.writeElement(tag, str, null);
}

/// Write boolean values as yes/no XML elements
/// Example: writeBoolElement(writer, "print", true) outputs <print>yes</print>
pub fn writeBoolElement(
    xml_writer: *XmlWriter,
    comptime tag: []const u8,
    value: bool,
) !void {
    try xml_writer.writeElement(tag, if (value) "yes" else "no", null);
}

/// Write string element with null check - only writes if value is non-null
/// Example: writeStringElement(writer, "text", optional_text) only writes if optional_text has value
pub fn writeStringElement(
    xml_writer: *XmlWriter,
    comptime tag: []const u8,
    value: ?[]const u8,
) !void {
    if (value) |v| {
        try xml_writer.writeElement(tag, v, null);
    }
}
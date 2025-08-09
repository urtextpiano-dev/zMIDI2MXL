const std = @import("std");
const XmlWriter = @import("xml_writer.zig").XmlWriter;

/// Helper to write integer values as XML elements - reduces code duplication
/// This is a zero-cost abstraction that will be inlined by the compiler
pub fn writeIntElement(xml_writer: *XmlWriter, comptime tag: []const u8, value: anytype) !void {
    var buf: [32]u8 = undefined;
    const str = try std.fmt.bufPrint(&buf, "{d}", .{value});
    try xml_writer.writeElement(tag, str, null);
}
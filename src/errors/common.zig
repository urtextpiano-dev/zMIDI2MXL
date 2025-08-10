const std = @import("std");

/// Common errors used across the codebase - ONLY generic, cross-cutting errors
pub const CommonErrors = error{
    OutOfMemory,
    InvalidInput,
    InvalidData,
    InvalidFormat,
    EndOfStream,
    UnsupportedOperation,
    NotImplemented,
};

/// Extend with module-specific errors
pub fn withModuleErrors(comptime module_errors: type) type {
    return CommonErrors || module_errors;
}

/// Error context for detailed error reporting
pub const ErrorContext = struct {
    message: []const u8,
    file_position: ?u64 = null,
    line_number: ?u32 = null,
    column_number: ?u32 = null,

    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}", .{self.message});
        if (self.file_position) |pos| {
            try writer.print(" at byte 0x{X}", .{pos});
        }
        if (self.line_number) |line| {
            try writer.print(" (line {d}", .{line});
            if (self.column_number) |col| {
                try writer.print(":{d}", .{col});
            }
            try writer.print(")", .{});
        }
    }
};

/// Create error context
pub fn makeContext(
    message: []const u8,
    file_position: ?u64,
    line_number: ?u32,
    column_number: ?u32,
) ErrorContext {
    return .{
        .message = message,
        .file_position = file_position,
        .line_number = line_number,
        .column_number = column_number,
    };
}

/// Print an error value paired with context
pub fn printErrorWithContext(writer: anytype, err: anyerror, ctx: ErrorContext) !void {
    try writer.print("{s}: {}", .{ @errorName(err), ctx });
}

// Tests
test "error context formatting" {
    const ctx = makeContext("Failed to parse", 1024, 42, 10);
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try stream.writer().print("{}", .{ctx});
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Failed to parse") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "0x400") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line 42:10") != null);
}

test "printErrorWithContext" {
    const ctx = makeContext("Invalid format", null, 10, null);
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try printErrorWithContext(stream.writer(), error.InvalidFormat, ctx);
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "InvalidFormat:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Invalid format") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line 10") != null);
}
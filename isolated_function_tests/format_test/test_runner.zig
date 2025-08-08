const std = @import("std");

// ========== EXTRACTED DEPENDENCIES ==========

// Error severity levels from src/error.zig
pub const ErrorSeverity = enum(u8) {
    info = 0,     // Informational, continue processing
    warning = 1,  // Potentially problematic, but recoverable
    err = 2,      // Serious issue, may affect output
    fatal = 3,    // Cannot continue processing
};

// Error context information for better debugging
pub const ErrorContext = struct {
    severity: ErrorSeverity,
    message: []const u8,
    file_position: ?u64 = null,
    track_number: ?u32 = null,
    tick_position: ?u32 = null,
    
    // ========== ORIGINAL FUNCTION (NO SIMPLIFICATION FOUND) ==========
    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("[{s}] {s}", .{ @tagName(self.severity), self.message });
        
        if (self.file_position) |pos| {
            try writer.print(" at byte 0x{X}", .{pos});
        }
        
        if (self.track_number) |track| {
            try writer.print(" in track {d}", .{track});
        }
        
        if (self.tick_position) |tick| {
            try writer.print(" at tick {d}", .{tick});
        }
    }
};

// ========== TEST CASES ==========

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    // Test case 1: Minimal error (only severity and message)
    {
        const err1 = ErrorContext{
            .severity = .info,
            .message = "This is an informational message",
        };
        
        try stdout.print("Test 1 (minimal): ", .{});
        try err1.format("", .{}, stdout);
        try stdout.print("\n", .{});
    }
    
    // Test case 2: Error with file position
    {
        const err2 = ErrorContext{
            .severity = .warning,
            .message = "Invalid data detected",
            .file_position = 0x1234,
        };
        
        try stdout.print("Test 2 (with file pos): ", .{});
        try err2.format("", .{}, stdout);
        try stdout.print("\n", .{});
    }
    
    // Test case 3: Error with track number
    {
        const err3 = ErrorContext{
            .severity = .err,
            .message = "Track parsing failed",
            .track_number = 3,
        };
        
        try stdout.print("Test 3 (with track): ", .{});
        try err3.format("", .{}, stdout);
        try stdout.print("\n", .{});
    }
    
    // Test case 4: Error with tick position
    {
        const err4 = ErrorContext{
            .severity = .fatal,
            .message = "Critical timing error",
            .tick_position = 480,
        };
        
        try stdout.print("Test 4 (with tick): ", .{});
        try err4.format("", .{}, stdout);
        try stdout.print("\n", .{});
    }
    
    // Test case 5: Complete error with all fields
    {
        const err5 = ErrorContext{
            .severity = .err,
            .message = "Note duration mismatch",
            .file_position = 0xDEADBEEF,
            .track_number = 7,
            .tick_position = 960,
        };
        
        try stdout.print("Test 5 (all fields): ", .{});
        try err5.format("", .{}, stdout);
        try stdout.print("\n", .{});
    }
    
    // Test case 6: Edge case - zero values
    {
        const err6 = ErrorContext{
            .severity = .info,
            .message = "Zero position test",
            .file_position = 0,
            .track_number = 0,
            .tick_position = 0,
        };
        
        try stdout.print("Test 6 (zero values): ", .{});
        try err6.format("", .{}, stdout);
        try stdout.print("\n", .{});
    }
    
    // Test case 7: Large values
    {
        const err7 = ErrorContext{
            .severity = .warning,
            .message = "Large value test",
            .file_position = 0xFFFFFFFFFFFFFFFF,
            .track_number = 4294967295,
            .tick_position = 4294967295,
        };
        
        try stdout.print("Test 7 (large values): ", .{});
        try err7.format("", .{}, stdout);
        try stdout.print("\n", .{});
    }
}

// ========== UNIT TESTS ==========

test "format outputs correct severity tag" {
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    
    const err = ErrorContext{
        .severity = .warning,
        .message = "Test message",
    };
    
    try err.format("", .{}, stream.writer());
    const result = stream.getWritten();
    
    try std.testing.expect(std.mem.startsWith(u8, result, "[warning]"));
}

test "format includes all provided fields" {
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    
    const err = ErrorContext{
        .severity = .err,
        .message = "Complete error",
        .file_position = 0x100,
        .track_number = 2,
        .tick_position = 480,
    };
    
    try err.format("", .{}, stream.writer());
    const result = stream.getWritten();
    
    // Check all components are present
    try std.testing.expect(std.mem.indexOf(u8, result, "[err]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Complete error") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "at byte 0x100") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "in track 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "at tick 480") != null);
}

test "format handles null optional fields correctly" {
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    
    const err = ErrorContext{
        .severity = .info,
        .message = "Minimal error",
        // All optional fields are null by default
    };
    
    try err.format("", .{}, stream.writer());
    const result = stream.getWritten();
    
    // Should only have severity and message
    try std.testing.expectEqualStrings("[info] Minimal error", result);
}

test "format handles zero values correctly" {
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    
    const err = ErrorContext{
        .severity = .fatal,
        .message = "Zero test",
        .file_position = 0,
        .track_number = 0,
        .tick_position = 0,
    };
    
    try err.format("", .{}, stream.writer());
    const result = stream.getWritten();
    
    // Should print zeros correctly
    try std.testing.expect(std.mem.indexOf(u8, result, "at byte 0x0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "in track 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "at tick 0") != null);
}

test "format preserves exact message content" {
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    
    const test_message = "Special chars: !@#$%^&*() and numbers: 123";
    const err = ErrorContext{
        .severity = .warning,
        .message = test_message,
    };
    
    try err.format("", .{}, stream.writer());
    const result = stream.getWritten();
    
    try std.testing.expect(std.mem.indexOf(u8, result, test_message) != null);
}
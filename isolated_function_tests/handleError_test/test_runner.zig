const std = @import("std");
const testing = std.testing;

// ============= Dependencies =============

pub const ErrorSeverity = enum(u8) {
    info = 0,     // Informational, continue processing
    warning = 1,  // Potentially problematic, but recoverable
    err = 2,      // Serious issue, may affect output
    fatal = 3,    // Cannot continue processing
};

pub const MidiError = error{
    InvalidEventData,
    UnexpectedEndOfFile,
};

pub const ErrorContext = struct {
    severity: ErrorSeverity,
    message: []const u8,
    file_position: ?u64 = null,
    track_number: ?u32 = null,
    tick_position: ?u32 = null,
};

pub const ErrorHandler = struct {
    errors: std.ArrayList(ErrorContext),
    strict_mode: bool,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, strict: bool) ErrorHandler {
        return .{
            .errors = std.ArrayList(ErrorContext).init(allocator),
            .strict_mode = strict,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ErrorHandler) void {
        self.errors.deinit();
    }
    
    // ============= FUNCTION UNDER TEST =============
    pub fn handleError(
        self: *ErrorHandler,
        severity: ErrorSeverity,
        message: []const u8,
        context: struct {
            file_position: ?u64 = null,
            track_number: ?u32 = null,
            tick_position: ?u32 = null,
        },
    ) !void {
        const err_context = ErrorContext{
            .severity = severity,
            .message = message,
            .file_position = context.file_position,
            .track_number = context.track_number,
            .tick_position = context.tick_position,
        };
        
        try self.errors.append(err_context);
        
        // In strict mode, throw on errors
        if (self.strict_mode and @intFromEnum(severity) >= @intFromEnum(ErrorSeverity.err)) {
            return MidiError.InvalidEventData;
        }
        
        // Always throw on fatal errors
        if (severity == .fatal) {
            return MidiError.UnexpectedEndOfFile;
        }
    }
};

// ============= Test Cases =============

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== handleError Function Test ===\n\n", .{});

    // Test 1: Info message in non-strict mode
    {
        var handler = ErrorHandler.init(allocator, false);
        defer handler.deinit();
        
        try handler.handleError(.info, "Info message", .{
            .file_position = 100,
            .track_number = 1,
        });
        
        std.debug.print("Test 1: Info message stored\n", .{});
        std.debug.print("  Errors count: {}\n", .{handler.errors.items.len});
        std.debug.print("  Message: {s}\n", .{handler.errors.items[0].message});
    }

    // Test 2: Warning in strict mode
    {
        var handler = ErrorHandler.init(allocator, true);
        defer handler.deinit();
        
        try handler.handleError(.warning, "Warning message", .{
            .tick_position = 480,
        });
        
        std.debug.print("\nTest 2: Warning in strict mode\n", .{});
        std.debug.print("  Errors count: {}\n", .{handler.errors.items.len});
        std.debug.print("  No error thrown (warning < err threshold)\n", .{});
    }

    // Test 3: Error in strict mode (should throw)
    {
        var handler = ErrorHandler.init(allocator, true);
        defer handler.deinit();
        
        const result = handler.handleError(.err, "Error message", .{});
        
        std.debug.print("\nTest 3: Error in strict mode\n", .{});
        if (result) |_| {
            std.debug.print("  ERROR: Should have thrown!\n", .{});
        } else |err| {
            std.debug.print("  Correctly threw: {}\n", .{err});
            std.debug.print("  Errors still recorded: {}\n", .{handler.errors.items.len});
        }
    }

    // Test 4: Fatal error (always throws)
    {
        var handler = ErrorHandler.init(allocator, false);
        defer handler.deinit();
        
        const result = handler.handleError(.fatal, "Fatal error", .{
            .file_position = 999,
        });
        
        std.debug.print("\nTest 4: Fatal error (non-strict mode)\n", .{});
        if (result) |_| {
            std.debug.print("  ERROR: Should have thrown!\n", .{});
        } else |err| {
            std.debug.print("  Correctly threw: {}\n", .{err});
        }
    }
    
    // Test 5: Multiple errors accumulation
    {
        var handler = ErrorHandler.init(allocator, false);
        defer handler.deinit();
        
        try handler.handleError(.info, "First", .{});
        try handler.handleError(.warning, "Second", .{});
        try handler.handleError(.err, "Third", .{});
        
        std.debug.print("\nTest 5: Multiple errors (non-strict)\n", .{});
        std.debug.print("  Total errors: {}\n", .{handler.errors.items.len});
        for (handler.errors.items, 0..) |err, i| {
            std.debug.print("  [{d}] Severity: {}, Message: {s}\n", .{i, err.severity, err.message});
        }
    }
}

// ============= Unit Tests =============

test "handleError: info message in non-strict mode" {
    var handler = ErrorHandler.init(testing.allocator, false);
    defer handler.deinit();
    
    try handler.handleError(.info, "Test info", .{
        .file_position = 42,
    });
    
    try testing.expectEqual(@as(usize, 1), handler.errors.items.len);
    try testing.expectEqualStrings("Test info", handler.errors.items[0].message);
    try testing.expectEqual(@as(?u64, 42), handler.errors.items[0].file_position);
}

test "handleError: warning in strict mode doesn't throw" {
    var handler = ErrorHandler.init(testing.allocator, true);
    defer handler.deinit();
    
    try handler.handleError(.warning, "Warning", .{});
    try testing.expectEqual(@as(usize, 1), handler.errors.items.len);
}

test "handleError: error in strict mode throws" {
    var handler = ErrorHandler.init(testing.allocator, true);
    defer handler.deinit();
    
    const result = handler.handleError(.err, "Error", .{});
    try testing.expectError(MidiError.InvalidEventData, result);
    // Error should still be recorded before throwing
    try testing.expectEqual(@as(usize, 1), handler.errors.items.len);
}

test "handleError: fatal always throws" {
    var handler = ErrorHandler.init(testing.allocator, false);
    defer handler.deinit();
    
    const result = handler.handleError(.fatal, "Fatal", .{});
    try testing.expectError(MidiError.UnexpectedEndOfFile, result);
}

test "handleError: error in non-strict mode doesn't throw" {
    var handler = ErrorHandler.init(testing.allocator, false);
    defer handler.deinit();
    
    try handler.handleError(.err, "Error", .{});
    try testing.expectEqual(@as(usize, 1), handler.errors.items.len);
}

test "handleError: context fields are properly stored" {
    var handler = ErrorHandler.init(testing.allocator, false);
    defer handler.deinit();
    
    try handler.handleError(.warning, "Test", .{
        .file_position = 123,
        .track_number = 2,
        .tick_position = 480,
    });
    
    const ctx = handler.errors.items[0];
    try testing.expectEqual(@as(?u64, 123), ctx.file_position);
    try testing.expectEqual(@as(?u32, 2), ctx.track_number);
    try testing.expectEqual(@as(?u32, 480), ctx.tick_position);
}

test "handleError: severity threshold check" {
    var handler = ErrorHandler.init(testing.allocator, true);
    defer handler.deinit();
    
    // Info and warning should not throw in strict mode
    try handler.handleError(.info, "Info", .{});
    try handler.handleError(.warning, "Warning", .{});
    
    // Error should throw in strict mode
    const err_result = handler.handleError(.err, "Error", .{});
    try testing.expectError(MidiError.InvalidEventData, err_result);
    
    // Fatal should always throw
    var handler2 = ErrorHandler.init(testing.allocator, false);
    defer handler2.deinit();
    const fatal_result = handler2.handleError(.fatal, "Fatal", .{});
    try testing.expectError(MidiError.UnexpectedEndOfFile, fatal_result);
}
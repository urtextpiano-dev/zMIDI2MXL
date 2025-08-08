const std = @import("std");
const testing = std.testing;

// ===== DEPENDENCIES EXTRACTED FROM src/error.zig =====

// Error severity levels
pub const ErrorSeverity = enum(u8) {
    info = 0,
    warning = 1,
    err = 2,
    fatal = 3,
};

// Error context information
pub const ErrorContext = struct {
    severity: ErrorSeverity,
    message: []const u8,
    file_position: ?u64 = null,
    track_number: ?u32 = null,
    tick_position: ?u32 = null,
};

// Simplified ErrorHandler struct (only what getErrorCount needs)
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
    
    // Helper function to add errors for testing
    pub fn addError(self: *ErrorHandler, severity: ErrorSeverity, message: []const u8) !void {
        try self.errors.append(.{
            .severity = severity,
            .message = message,
        });
    }
    
    // ===== ORIGINAL FUNCTION IMPLEMENTATION =====
    pub fn getErrorCount(self: *const ErrorHandler, severity: ErrorSeverity) usize {
        var count: usize = 0;
        for (self.errors.items) |err| {
            if (err.severity == severity) {
                count += 1;
            }
        }
        return count;
    }
};

// ===== MAIN FUNCTION FOR DEMONSTRATION =====
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Create error handler
    var handler = ErrorHandler.init(allocator, false);
    defer handler.deinit();
    
    // Add various errors for testing
    try handler.addError(.info, "Info message 1");
    try handler.addError(.warning, "Warning message 1");
    try handler.addError(.err, "Error message 1");
    try handler.addError(.fatal, "Fatal message 1");
    try handler.addError(.warning, "Warning message 2");
    try handler.addError(.info, "Info message 2");
    try handler.addError(.err, "Error message 2");
    try handler.addError(.info, "Info message 3");
    
    // Test getErrorCount for each severity
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Testing getErrorCount function:\n", .{});
    try stdout.print("  Info errors: {}\n", .{handler.getErrorCount(.info)});
    try stdout.print("  Warning errors: {}\n", .{handler.getErrorCount(.warning)});
    try stdout.print("  Error errors: {}\n", .{handler.getErrorCount(.err)});
    try stdout.print("  Fatal errors: {}\n", .{handler.getErrorCount(.fatal)});
    
    // Test with empty handler
    var empty_handler = ErrorHandler.init(allocator, false);
    defer empty_handler.deinit();
    try stdout.print("\nEmpty handler counts:\n", .{});
    try stdout.print("  Info errors: {}\n", .{empty_handler.getErrorCount(.info)});
    try stdout.print("  Warning errors: {}\n", .{empty_handler.getErrorCount(.warning)});
    try stdout.print("  Error errors: {}\n", .{empty_handler.getErrorCount(.err)});
    try stdout.print("  Fatal errors: {}\n", .{empty_handler.getErrorCount(.fatal)});
}

// ===== UNIT TESTS =====
test "getErrorCount with mixed errors" {
    const allocator = testing.allocator;
    
    var handler = ErrorHandler.init(allocator, false);
    defer handler.deinit();
    
    // Add test data
    try handler.addError(.info, "Test info 1");
    try handler.addError(.warning, "Test warning 1");
    try handler.addError(.err, "Test error 1");
    try handler.addError(.fatal, "Test fatal 1");
    try handler.addError(.warning, "Test warning 2");
    try handler.addError(.info, "Test info 2");
    try handler.addError(.err, "Test error 2");
    try handler.addError(.info, "Test info 3");
    
    try testing.expectEqual(@as(usize, 3), handler.getErrorCount(.info));
    try testing.expectEqual(@as(usize, 2), handler.getErrorCount(.warning));
    try testing.expectEqual(@as(usize, 2), handler.getErrorCount(.err));
    try testing.expectEqual(@as(usize, 1), handler.getErrorCount(.fatal));
}

test "getErrorCount with empty handler" {
    const allocator = testing.allocator;
    
    var handler = ErrorHandler.init(allocator, false);
    defer handler.deinit();
    
    try testing.expectEqual(@as(usize, 0), handler.getErrorCount(.info));
    try testing.expectEqual(@as(usize, 0), handler.getErrorCount(.warning));
    try testing.expectEqual(@as(usize, 0), handler.getErrorCount(.err));
    try testing.expectEqual(@as(usize, 0), handler.getErrorCount(.fatal));
}

test "getErrorCount with single severity only" {
    const allocator = testing.allocator;
    
    var handler = ErrorHandler.init(allocator, false);
    defer handler.deinit();
    
    // Add only warnings
    try handler.addError(.warning, "Warning 1");
    try handler.addError(.warning, "Warning 2");
    try handler.addError(.warning, "Warning 3");
    try handler.addError(.warning, "Warning 4");
    try handler.addError(.warning, "Warning 5");
    
    try testing.expectEqual(@as(usize, 0), handler.getErrorCount(.info));
    try testing.expectEqual(@as(usize, 5), handler.getErrorCount(.warning));
    try testing.expectEqual(@as(usize, 0), handler.getErrorCount(.err));
    try testing.expectEqual(@as(usize, 0), handler.getErrorCount(.fatal));
}

test "getErrorCount with large number of errors" {
    const allocator = testing.allocator;
    
    var handler = ErrorHandler.init(allocator, false);
    defer handler.deinit();
    
    // Add many errors of different types
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const severity = switch (i % 4) {
            0 => ErrorSeverity.info,
            1 => ErrorSeverity.warning,
            2 => ErrorSeverity.err,
            3 => ErrorSeverity.fatal,
            else => unreachable,
        };
        try handler.addError(severity, "Test message");
    }
    
    try testing.expectEqual(@as(usize, 25), handler.getErrorCount(.info));
    try testing.expectEqual(@as(usize, 25), handler.getErrorCount(.warning));
    try testing.expectEqual(@as(usize, 25), handler.getErrorCount(.err));
    try testing.expectEqual(@as(usize, 25), handler.getErrorCount(.fatal));
}

test "getErrorCount performance with 1000 errors" {
    const allocator = testing.allocator;
    
    var handler = ErrorHandler.init(allocator, false);
    defer handler.deinit();
    
    // Add 1000 errors with different severities
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const severity = switch (i % 7) {
            0, 1, 2 => ErrorSeverity.info,      // ~43% info
            3, 4 => ErrorSeverity.warning,       // ~29% warning  
            5 => ErrorSeverity.err,              // ~14% error
            6 => ErrorSeverity.fatal,            // ~14% fatal
            else => unreachable,
        };
        try handler.addError(severity, "Test");
    }
    
    // Verify counts
    const info_count = handler.getErrorCount(.info);
    const warning_count = handler.getErrorCount(.warning);
    const err_count = handler.getErrorCount(.err);
    const fatal_count = handler.getErrorCount(.fatal);
    
    try testing.expect(info_count > 400 and info_count < 450);
    try testing.expect(warning_count > 280 and warning_count < 300);
    try testing.expect(err_count > 140 and err_count < 150);
    try testing.expect(fatal_count > 140 and fatal_count < 150);
    try testing.expectEqual(@as(usize, 1000), info_count + warning_count + err_count + fatal_count);
}
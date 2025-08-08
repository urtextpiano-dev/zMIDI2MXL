const std = @import("std");
const testing = std.testing;

// Minimal ErrorSeverity enum for testing
pub const ErrorSeverity = enum(u8) {
    info = 0,
    warning = 1,
    err = 2,
    fatal = 3,
};

// Minimal ErrorContext struct for testing
pub const ErrorContext = struct {
    severity: ErrorSeverity,
    message: []const u8,
    file_position: ?u64 = null,
    track_number: ?u32 = null,
    tick_position: ?u32 = null,
};

// ErrorHandler struct with the clear function we're testing
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
    
    // ORIGINAL FUNCTION UNDER TEST
    pub fn clear(self: *ErrorHandler) void {
        self.errors.clearRetainingCapacity();
    }
    
    // Helper function to add errors for testing
    pub fn addError(self: *ErrorHandler, context: ErrorContext) !void {
        try self.errors.append(context);
    }
};

// Main function to demonstrate the clear function behavior
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var handler = ErrorHandler.init(allocator, false);
    defer handler.deinit();
    
    std.debug.print("=== Testing clear function ===\n", .{});
    
    // Add some test errors
    try handler.addError(.{
        .severity = .err,
        .message = "Test error 1",
    });
    
    try handler.addError(.{
        .severity = .warning,
        .message = "Test warning",
    });
    
    try handler.addError(.{
        .severity = .fatal,
        .message = "Fatal error",
    });
    
    std.debug.print("Before clear: {} errors\n", .{handler.errors.items.len});
    std.debug.print("Before clear: capacity = {}\n", .{handler.errors.capacity});
    
    // Call the function under test
    handler.clear();
    
    std.debug.print("After clear: {} errors\n", .{handler.errors.items.len});
    std.debug.print("After clear: capacity = {} (retained)\n", .{handler.errors.capacity});
    
    // Verify we can still add errors after clearing
    try handler.addError(.{
        .severity = .info,
        .message = "New error after clear",
    });
    
    std.debug.print("After adding new error: {} errors\n", .{handler.errors.items.len});
}

// Unit tests for the clear function
test "clear removes all errors" {
    var handler = ErrorHandler.init(testing.allocator, false);
    defer handler.deinit();
    
    // Add multiple errors
    try handler.addError(.{ .severity = .err, .message = "Error 1" });
    try handler.addError(.{ .severity = .warning, .message = "Warning 1" });
    try handler.addError(.{ .severity = .fatal, .message = "Fatal 1" });
    
    try testing.expectEqual(@as(usize, 3), handler.errors.items.len);
    
    // Clear errors
    handler.clear();
    
    // Verify all errors are removed
    try testing.expectEqual(@as(usize, 0), handler.errors.items.len);
}

test "clear retains capacity" {
    var handler = ErrorHandler.init(testing.allocator, false);
    defer handler.deinit();
    
    // Add errors to establish capacity
    for (0..10) |i| {
        try handler.addError(.{
            .severity = .info,
            .message = "Test",
        });
        _ = i;
    }
    
    const capacity_before = handler.errors.capacity;
    try testing.expect(capacity_before >= 10);
    
    // Clear errors
    handler.clear();
    
    // Verify capacity is retained
    const capacity_after = handler.errors.capacity;
    try testing.expectEqual(capacity_before, capacity_after);
    try testing.expectEqual(@as(usize, 0), handler.errors.items.len);
}

test "clear on empty handler" {
    var handler = ErrorHandler.init(testing.allocator, false);
    defer handler.deinit();
    
    // Clear empty handler (should not crash)
    handler.clear();
    
    try testing.expectEqual(@as(usize, 0), handler.errors.items.len);
}

test "can add errors after clear" {
    var handler = ErrorHandler.init(testing.allocator, false);
    defer handler.deinit();
    
    // Add and clear errors
    try handler.addError(.{ .severity = .err, .message = "Old error" });
    handler.clear();
    
    // Add new errors after clear
    try handler.addError(.{ .severity = .warning, .message = "New warning" });
    try handler.addError(.{ .severity = .info, .message = "New info" });
    
    try testing.expectEqual(@as(usize, 2), handler.errors.items.len);
}

test "multiple clears work correctly" {
    var handler = ErrorHandler.init(testing.allocator, false);
    defer handler.deinit();
    
    // First cycle
    try handler.addError(.{ .severity = .err, .message = "Error 1" });
    handler.clear();
    try testing.expectEqual(@as(usize, 0), handler.errors.items.len);
    
    // Second cycle
    try handler.addError(.{ .severity = .warning, .message = "Warning 1" });
    try handler.addError(.{ .severity = .info, .message = "Info 1" });
    handler.clear();
    try testing.expectEqual(@as(usize, 0), handler.errors.items.len);
    
    // Third cycle
    try handler.addError(.{ .severity = .fatal, .message = "Fatal 1" });
    handler.clear();
    try testing.expectEqual(@as(usize, 0), handler.errors.items.len);
}
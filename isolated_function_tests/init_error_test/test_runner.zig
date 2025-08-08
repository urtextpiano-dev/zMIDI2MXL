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

// ErrorHandler struct as defined in the source
pub const ErrorHandler = struct {
    errors: std.ArrayList(ErrorContext),
    strict_mode: bool,
    allocator: std.mem.Allocator,
    
    // ORIGINAL FUNCTION (7 lines)
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
};

// Main function for standalone execution
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Testing ErrorHandler.init function\n", .{});
    std.debug.print("==================================\n\n", .{});
    
    // Test case 1: Init with strict mode true
    {
        var handler = ErrorHandler.init(allocator, true);
        defer handler.deinit();
        
        std.debug.print("Test 1 - Strict mode true:\n", .{});
        std.debug.print("  strict_mode: {}\n", .{handler.strict_mode});
        std.debug.print("  errors capacity: {}\n", .{handler.errors.capacity});
        std.debug.print("  errors length: {}\n", .{handler.errors.items.len});
        std.debug.print("  allocator matches: {}\n", .{handler.allocator.ptr == allocator.ptr});
    }
    
    std.debug.print("\n", .{});
    
    // Test case 2: Init with strict mode false
    {
        var handler = ErrorHandler.init(allocator, false);
        defer handler.deinit();
        
        std.debug.print("Test 2 - Strict mode false:\n", .{});
        std.debug.print("  strict_mode: {}\n", .{handler.strict_mode});
        std.debug.print("  errors capacity: {}\n", .{handler.errors.capacity});
        std.debug.print("  errors length: {}\n", .{handler.errors.items.len});
        std.debug.print("  allocator matches: {}\n", .{handler.allocator.ptr == allocator.ptr});
    }
    
    std.debug.print("\n", .{});
    
    // Test case 3: Multiple inits with same allocator
    {
        var handler1 = ErrorHandler.init(allocator, true);
        defer handler1.deinit();
        
        var handler2 = ErrorHandler.init(allocator, false);
        defer handler2.deinit();
        
        std.debug.print("Test 3 - Multiple handlers:\n", .{});
        std.debug.print("  handler1.strict_mode: {}\n", .{handler1.strict_mode});
        std.debug.print("  handler2.strict_mode: {}\n", .{handler2.strict_mode});
        std.debug.print("  Both use same allocator: {}\n", .{handler1.allocator.ptr == handler2.allocator.ptr});
    }
    
    std.debug.print("\nAll tests completed successfully!\n", .{});
}

// Unit tests
test "init creates ErrorHandler with correct fields" {
    const allocator = testing.allocator;
    
    // Test with strict mode true
    {
        var handler = ErrorHandler.init(allocator, true);
        defer handler.deinit();
        
        try testing.expect(handler.strict_mode == true);
        try testing.expect(handler.errors.items.len == 0);
        try testing.expect(handler.allocator.ptr == allocator.ptr);
    }
    
    // Test with strict mode false
    {
        var handler = ErrorHandler.init(allocator, false);
        defer handler.deinit();
        
        try testing.expect(handler.strict_mode == false);
        try testing.expect(handler.errors.items.len == 0);
        try testing.expect(handler.allocator.ptr == allocator.ptr);
    }
}

test "init creates independent instances" {
    const allocator = testing.allocator;
    
    var handler1 = ErrorHandler.init(allocator, true);
    defer handler1.deinit();
    
    var handler2 = ErrorHandler.init(allocator, false);
    defer handler2.deinit();
    
    // Each handler should have independent state
    try testing.expect(handler1.strict_mode != handler2.strict_mode);
    try testing.expect(&handler1.errors != &handler2.errors);
    
    // But they share the same allocator
    try testing.expect(handler1.allocator.ptr == handler2.allocator.ptr);
}

test "init allocates empty ArrayList" {
    const allocator = testing.allocator;
    
    var handler = ErrorHandler.init(allocator, true);
    defer handler.deinit();
    
    // ArrayList should be empty initially
    try testing.expect(handler.errors.items.len == 0);
    try testing.expect(handler.errors.capacity == 0);
    
    // Should be able to append to it
    try handler.errors.append(ErrorContext{
        .severity = .info,
        .message = "test message",
    });
    
    try testing.expect(handler.errors.items.len == 1);
}

test "memory safety - no leaks" {
    const allocator = testing.allocator;
    
    // Create and destroy multiple handlers
    for (0..10) |i| {
        var handler = ErrorHandler.init(allocator, i % 2 == 0);
        defer handler.deinit();
        
        // Add some errors to exercise the ArrayList
        for (0..5) |j| {
            try handler.errors.append(ErrorContext{
                .severity = .info,
                .message = "test",
                .file_position = j,
            });
        }
    }
    
    // If there are leaks, the test allocator will detect them
}
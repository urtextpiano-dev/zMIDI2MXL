const std = @import("std");
const error_mod = @import("error.zig");
const log_mod = @import("log.zig");

// Implements TASK-002 per MIDI_Architecture_Reference.md Section 10.1 lines 1213-1244
// Error propagation strategy with Result type for better error handling

// Result type for operations that can fail with context
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok_value: T,
        err_value: ErrorInfo,
        
        pub const ErrorInfo = struct {
            code: error_mod.Error,
            context: error_mod.ErrorContext,
        };
        
        // Create a successful result
        pub fn ok(value: T) Result(T) {
            return .{ .ok_value = value };
        }
        
        // Create an error result
        pub fn err(code: error_mod.Error, context: error_mod.ErrorContext) Result(T) {
            return .{ .err_value = .{ .code = code, .context = context } };
        }
        
        // Check if result is ok
        pub fn isOk(self: Result(T)) bool {
            return switch (self) {
                .ok_value => true,
                .err_value => false,
            };
        }
        
        // Check if result is error
        pub fn isErr(self: Result(T)) bool {
            return !self.isOk();
        }
        
        // Get the value or return a default
        pub fn unwrapOr(self: Result(T), default: T) T {
            return switch (self) {
                .ok_value => |value| value,
                .err_value => default,
            };
        }
        
        // Get the value or panic (for testing)
        pub fn unwrap(self: Result(T)) T {
            return switch (self) {
                .ok_value => |value| value,
                .err_value => |e| std.debug.panic("Unwrap failed: {}", .{e.context}),
            };
        }
        
        // Map the value if ok
        pub fn map(self: Result(T), comptime U: type, f: fn (T) U) Result(U) {
            return switch (self) {
                .ok_value => |value| Result(U).ok(f(value)),
                .err_value => |e| Result(U).err(e.code, e.context),
            };
        }
        
        // Try to get the value, propagating error
        pub fn try_(self: Result(T)) error_mod.Error!T {
            return switch (self) {
                .ok_value => |value| value,
                .err_value => |e| e.code,
            };
        }
    };
}

// Error recovery strategies
pub const RecoveryStrategy = enum {
    skip_byte,          // Skip one byte and continue
    skip_to_next_event, // Skip to next valid status byte
    skip_to_next_track, // Skip remainder of current track
    use_default,        // Use a default value
    abort,              // Stop processing
};

// Recovery helper functions
pub const Recovery = struct {
    // Attempt to recover from a parsing error
    pub fn recover(
        strategy: RecoveryStrategy,
        reader: anytype,
        logger: *log_mod.Logger,
    ) !void {
        switch (strategy) {
            .skip_byte => {
                _ = try reader.readByte();
                logger.debug("Recovery: Skipped one byte", .{});
            },
            .skip_to_next_event => {
                var byte: u8 = 0;
                while (byte < 0x80) {
                    byte = try reader.readByte();
                }
                try reader.seekBy(-1); // Back up to status byte
                logger.debug("Recovery: Found next event at status byte 0x{X:0>2}", .{byte});
            },
            .skip_to_next_track => {
                logger.warn("Recovery: Skipping to next track", .{});
                // This would be handled at a higher level
            },
            .use_default => {
                logger.debug("Recovery: Using default value", .{});
                // Caller handles the default
            },
            .abort => {
                logger.err("Recovery: Aborting processing", .{});
                return error_mod.MidiError.UnexpectedEndOfFile;
            },
        }
    }
    
    // Find a safe point to resume parsing
    pub fn findSafePoint(
        data: []const u8,
        start_pos: usize,
    ) ?usize {
        var pos = start_pos;
        
        // Look for next status byte
        while (pos < data.len) {
            if (data[pos] >= 0x80) {
                // Found a status byte
                return pos;
            }
            pos += 1;
        }
        
        return null;
    }
    
    // Validate and potentially fix a value
    pub fn validateOrDefault(
        comptime T: type,
        value: T,
        min: T,
        max: T,
        default: T,
        logger: *log_mod.Logger,
    ) T {
        if (value < min or value > max) {
            logger.warn(
                "Value {any} out of range [{any}, {any}], using default {any}",
                .{ value, min, max, default },
            );
            return default;
        }
        return value;
    }
};

// Chain multiple operations that return Results
pub fn chain(comptime T: type, operations: []const fn () Result(T)) Result(T) {
    for (operations) |op| {
        const result = op();
        if (result.isErr()) {
            return result;
        }
    }
    return Result(T).ok(undefined); // Should be overridden by actual operation
}

// Tests for Result type and recovery
test "Result type basic operations" {
    const IntResult = Result(i32);
    
    // Test ok result
    const ok_result = IntResult.ok(42);
    try std.testing.expect(ok_result.isOk());
    try std.testing.expect(!ok_result.isErr());
    try std.testing.expectEqual(@as(i32, 42), ok_result.unwrap());
    
    // Test error result
    const err_result = IntResult.err(
        error_mod.MidiError.InvalidStatusByte,
        .{
            .severity = .err,
            .message = "Test error",
        },
    );
    try std.testing.expect(!err_result.isOk());
    try std.testing.expect(err_result.isErr());
    try std.testing.expectEqual(@as(i32, -1), err_result.unwrapOr(-1));
}

test "Result map operation" {
    const IntResult = Result(i32);
    
    const ok_result = IntResult.ok(42);
    const mapped = ok_result.map(f32, struct {
        fn convert(x: i32) f32 {
            return @as(f32, @floatFromInt(x)) * 2.0;
        }
    }.convert);
    
    try std.testing.expect(mapped.isOk());
    try std.testing.expectEqual(@as(f32, 84.0), mapped.unwrap());
}

test "Recovery findSafePoint" {
    const data = [_]u8{ 0x00, 0x10, 0x20, 0x90, 0x3C, 0x64 };
    
    // Should find the status byte at position 3
    const safe_point = Recovery.findSafePoint(&data, 0);
    try std.testing.expectEqual(@as(?usize, 3), safe_point);
    
    // No status byte after position 4
    const no_point = Recovery.findSafePoint(&data, 4);
    try std.testing.expectEqual(@as(?usize, null), no_point);
}

test "Recovery validateOrDefault" {
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    
    var logger = log_mod.Logger.init(.{
        .level = .debug,
        .show_timestamp = false,
        .writer = stream.writer().any(),
    });
    
    // Valid value should pass through
    const valid = Recovery.validateOrDefault(u8, 64, 0, 127, 60, &logger);
    try std.testing.expectEqual(@as(u8, 64), valid);
    
    // Invalid value should use default
    const invalid = Recovery.validateOrDefault(u8, 200, 0, 127, 60, &logger);
    try std.testing.expectEqual(@as(u8, 60), invalid);
    
    // Check that warning was logged
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "out of range") != null);
}
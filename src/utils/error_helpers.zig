const std = @import("std");
const log = @import("log.zig"); // Sibling import - both in src/utils

/// Log an error with context and return it (preserving exact type)
/// Zero-cost abstraction with inline
pub inline fn logAndReturn(comptime context: []const u8, err: anytype) @TypeOf(err) {
    log.err("{s}: {}", .{ context, err });
    return err;
}

/// Log with formatted message and return the error (preserving type)
/// Use when you need runtime values in the message
pub inline fn logAndReturnFmt(comptime fmt: []const u8, args: anytype, err: anytype) @TypeOf(err) {
    log.err(fmt, args);
    return err;
}

/// Log original error and map to a specific error type
/// Caller's function must include @TypeOf(return_err) in its error set
pub inline fn mapAndReturn(comptime context: []const u8, err: anytype, comptime return_err: anytype) @TypeOf(return_err) {
    log.err("{s}: {} (mapped to {})", .{ context, err, return_err });
    return return_err;
}

/// Simple error return without logging (for consistency)
/// Use when error is already logged elsewhere
pub inline fn justReturn(err: anytype) @TypeOf(err) {
    return err;
}
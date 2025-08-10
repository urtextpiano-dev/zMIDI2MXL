const std = @import("std");

pub const log = std.log.scoped(.zmidi);

// Thin, zero-maintenance aliases:
pub const debug = log.debug;
pub const warn = log.warn;
pub const err = log.err;

// Keep the truly useful sugar:
pub inline fn tag(comptime tag_name: []const u8, comptime fmt: []const u8, args: anytype) void {
    log.debug("[{s}] " ++ fmt, .{tag_name} ++ args);
}

pub inline fn perf(comptime metric: []const u8, value: anytype, comptime unit: []const u8) void {
    log.debug("{s}: {any} {s}", .{ metric, value, unit });
}
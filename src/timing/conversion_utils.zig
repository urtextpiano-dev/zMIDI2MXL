const std = @import("std");
const timing = @import("../timing.zig");

/// Convert ticks using optional division converter, or return unchanged if no converter
pub inline fn convertTicksOrSame(ticks: u32, converter: ?timing.DivisionConverter) !u32 {
    return if (converter) |c|
        try c.convertTicksToDivisions(ticks)
    else
        ticks;
}

// Alias for compatibility if existing code uses "duration" terminology
pub const convertDuration = convertTicksOrSame;
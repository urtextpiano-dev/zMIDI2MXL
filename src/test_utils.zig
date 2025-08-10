const std = @import("std");

// Re-export commonly used test items (NO ALLOCATOR!)
pub const expect = std.testing.expect;
pub const expectEq = std.testing.expectEqual;
pub const expectStrEq = std.testing.expectEqualStrings;
pub const expectErr = std.testing.expectError;
// NO allocator export - we don't touch allocator at all

// Minimal helpers
pub inline fn expectFalse(cond: bool) !void {
    return std.testing.expect(!cond);
}

pub inline fn expectSliceEq(comptime T: type, expected: []const T, actual: []const T) !void {
    return std.testing.expectEqualSlices(T, expected, actual);
}

pub inline fn expectNull(value: anytype) !void {
    return std.testing.expect(value == null);
}

pub inline fn expectNotNull(value: anytype) !void {
    return std.testing.expect(value != null);
}

pub inline fn expectApproxAbs(comptime T: type, expected: T, actual: T, tol: T) !void {
    return std.testing.expectApproxEqAbs(expected, actual, tol);
}

pub inline fn expectApproxRel(comptime T: type, expected: T, actual: T, rel: T) !void {
    return std.testing.expectApproxEqRel(expected, actual, rel);
}
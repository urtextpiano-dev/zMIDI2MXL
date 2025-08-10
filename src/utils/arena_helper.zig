const std = @import("std");

// Keep API order consistent: (comptime func, parent, args)
pub inline fn withArenaValue(
    comptime func: anytype,
    parent: std.mem.Allocator,
    args: anytype,
) @TypeOf(@call(.auto, func, .{@as(std.mem.Allocator, undefined)} ++ args)) {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();

    const Ret = @TypeOf(@call(.auto, func, .{@as(std.mem.Allocator, undefined)} ++ args));
    return switch (@typeInfo(Ret)) {
        .error_union => blk: {
            const v = try @call(.auto, func, .{arena.allocator()} ++ args);
            break :blk v;
        },
        else => @call(.auto, func, .{arena.allocator()} ++ args),
    };
}

// Make withArena explicitly require !void-returning funcs
pub fn withArena(comptime func: anytype, parent: std.mem.Allocator, args: anytype) !void {
    const FnInfo = @typeInfo(@TypeOf(func)).@"fn";
    const Ret = FnInfo.return_type.?;
    comptime {
        const ti = @typeInfo(Ret);
        if (ti != .error_union or ti.error_union.payload != void)
            @compileError("withArena expects a function of type fn(Allocator, ...) !void");
    }
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    try @call(.auto, func, .{arena.allocator()} ++ args);
}

// ScopedArena is fine as-is - it's a clear 2-liner at call sites
pub const ScopedArena = struct {
    arena: std.heap.ArenaAllocator,
    
    pub fn init(parent: std.mem.Allocator) ScopedArena {
        return .{ .arena = std.heap.ArenaAllocator.init(parent) };
    }
    
    pub fn allocator(self: *ScopedArena) std.mem.Allocator {
        return self.arena.allocator();
    }
    
    pub fn deinit(self: *ScopedArena) void {
        self.arena.deinit();
    }
};

// Tests to verify correct behavior
test "withArenaValue with error union" {
    const testFn = struct {
        fn run(alloc: std.mem.Allocator, x: u32) !u32 {
            _ = alloc;
            if (x == 0) return error.InvalidInput;
            return x * 2;
        }
    }.run;
    
    const result = try withArenaValue(testFn, std.testing.allocator, .{5});
    try std.testing.expectEqual(@as(u32, 10), result);
}

test "withArenaValue with non-error type" {
    const testFn = struct {
        fn run(alloc: std.mem.Allocator, x: u32) u32 {
            _ = alloc;
            return x * 2;
        }
    }.run;
    
    const result = withArenaValue(testFn, std.testing.allocator, .{5});
    try std.testing.expectEqual(@as(u32, 10), result);
}

test "withArena with void error union" {
    const testFn = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            // Do something
        }
    }.run;
    
    try withArena(testFn, std.testing.allocator, .{});
}

test "ScopedArena basic usage" {
    var sa = ScopedArena.init(std.testing.allocator);
    defer sa.deinit();
    const alloc = sa.allocator();
    
    const data = try alloc.alloc(u8, 100);
    data[0] = 42;
    try std.testing.expectEqual(@as(u8, 42), data[0]);
}
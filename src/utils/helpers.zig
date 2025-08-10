const std = @import("std");

// Simple, explicit withArena helper for NON-HOT paths only
// Returns void to avoid type gymnastics
pub fn withArena(comptime func: anytype, parent: std.mem.Allocator, args: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    
    // Pass arena allocator as first argument, then remaining args
    _ = try @call(.auto, func, .{arena.allocator()} ++ args);
}

// Parse utilities - let compiler decide on inlining
pub fn readU32BE(reader: anytype) !u32 {
    return try reader.readInt(u32, .big);
}

pub fn readU16BE(reader: anytype) !u16 {
    return try reader.readInt(u16, .big);
}

pub fn expectBytes(reader: anytype, expected: []const u8, allocator: std.mem.Allocator) !void {
    const buf = try allocator.alloc(u8, expected.len);
    defer allocator.free(buf);
    
    try reader.readNoEof(buf);
    if (!std.mem.eql(u8, buf, expected)) {
        return error.UnexpectedBytes;
    }
}

// Test helper - simplified for test scaffolding only
pub fn TestContext(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        data: T,
        
        pub fn init() !@This() {
            const allocator = std.testing.allocator;
            return .{
                .allocator = allocator,
                .data = try T.init(allocator),
            };
        }
        
        pub fn deinit(self: *@This()) void {
            if (@hasDecl(T, "deinit")) {
                self.data.deinit();
            }
        }
    };
}
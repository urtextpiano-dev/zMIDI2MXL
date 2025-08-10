const std = @import("std");

/// Read a big-endian u32 from data at the specified offset
pub inline fn readU32BE(data: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, data[offset..offset+4][0..4], .big);
}

/// Read a big-endian u16 from data at the specified offset  
pub inline fn readU16BE(data: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..offset+2][0..2], .big);
}

/// Read a big-endian u24 (3 bytes) as u32 from data at the specified offset
pub inline fn readU24BE(data: []const u8, offset: usize) u32 {
    return (@as(u32, data[offset]) << 16) | 
           (@as(u32, data[offset + 1]) << 8) | 
           @as(u32, data[offset + 2]);
}
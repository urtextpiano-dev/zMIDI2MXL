const std = @import("std");

/// Generate comparison for sorting by field with compile-time validation
pub inline fn compareByField(
    comptime T: type,
    comptime field: []const u8,
    comptime order: enum { asc, desc },
) fn (void, T, T) bool {
    comptime {
        if (!@hasField(T, field))
            @compileError("Type " ++ @typeName(T) ++ " has no field '" ++ field ++ "'");
    }
    
    return struct {
        fn compare(_: void, a: T, b: T) bool {
            const a_val = @field(a, field);
            const b_val = @field(b, field);
            return if (order == .asc) a_val < b_val else a_val > b_val;
        }
    }.compare;
}

/// Compare by string field - FIXED descending logic
pub inline fn byStringField(
    comptime T: type,
    comptime field: []const u8,
    comptime order: enum { asc, desc },
) fn (void, T, T) bool {
    comptime {
        if (!@hasField(T, field))
            @compileError("Type " ++ @typeName(T) ++ " has no field '" ++ field ++ "'");
        
        // Validate field is []const u8
        const FT = @TypeOf(@field(@as(T, undefined), field));
        const ti = @typeInfo(FT);
        if (ti != .pointer or ti.pointer.size != .slice or ti.pointer.child != u8)
            @compileError("byStringField requires a []const u8 field");
    }
    
    return struct {
        fn compare(_: void, a: T, b: T) bool {
            const a_val = @field(a, field);
            const b_val = @field(b, field);
            if (order == .asc) {
                return std.mem.lessThan(u8, a_val, b_val);
            } else {
                return std.mem.lessThan(u8, b_val, a_val); // CORRECT descending
            }
        }
    }.compare;
}

/// Handle nullable fields with type validation
pub inline fn nullsFirstByField(
    comptime T: type,
    comptime field: []const u8,
    comptime order: enum { asc, desc },
) fn (void, T, T) bool {
    comptime {
        if (!@hasField(T, field))
            @compileError("Type " ++ @typeName(T) ++ " has no field '" ++ field ++ "'");
        
        // Validate field is optional
        const FT = @TypeOf(@field(@as(T, undefined), field));
        if (@typeInfo(FT) != .optional)
            @compileError("nullsFirstByField requires an optional field (?T)");
    }
    
    return struct {
        fn compare(_: void, a: T, b: T) bool {
            const a_val = @field(a, field);
            const b_val = @field(b, field);
            
            if (a_val == null and b_val == null) return false;
            if (a_val == null) return true;
            if (b_val == null) return false;
            
            return if (order == .asc) 
                a_val.? < b_val.?
            else 
                a_val.? > b_val.?;
        }
    }.compare;
}

/// Generate a comparison function for sorting by multiple fields
/// Fields are compared in order - if first field is equal, compare second, etc.
/// 
/// Example usage:
/// ```zig
/// const compareByTickAndChannel = comparison.compareByFields(NoteEvent, &.{"tick", "channel"});
/// std.sort.insertion(NoteEvent, notes.items[0..], {}, compareByTickAndChannel);
/// ```
/// 
/// Note: All field types must support < and > operators.
pub fn compareByFields(
    comptime T: type,
    comptime fields: []const []const u8,
) fn (void, T, T) bool {
    // Compile-time validation that all fields exist
    comptime {
        for (fields) |field| {
            if (!@hasField(T, field)) {
                @compileError("Type " ++ @typeName(T) ++ " has no field named '" ++ field ++ "'");
            }
        }
    }
    
    return struct {
        fn compare(_: void, a: T, b: T) bool {
            inline for (fields) |field| {
                const a_val = @field(a, field);
                const b_val = @field(b, field);
                if (a_val < b_val) return true;
                if (a_val > b_val) return false;
            }
            return false;
        }
    }.compare;
}

/// Generate a comparison function with custom comparison logic per field
/// Allows mixing ascending and descending order for different fields
///
/// Example usage:
/// ```zig
/// const compareCustom = comparison.compareByFieldsWithOrder(
///     NoteEvent, 
///     &.{.{ .field = "tick", .order = .asc }, .{ .field = "pitch", .order = .desc }}
/// );
/// std.sort.insertion(NoteEvent, notes.items[0..], {}, compareCustom);
/// ```
///
/// Note: All field types must support < and > operators.
pub fn compareByFieldsWithOrder(
    comptime T: type,
    comptime field_orders: []const struct { field: []const u8, order: enum { asc, desc } },
) fn (void, T, T) bool {
    // Compile-time validation that all fields exist
    comptime {
        for (field_orders) |fo| {
            if (!@hasField(T, fo.field)) {
                @compileError("Type " ++ @typeName(T) ++ " has no field named '" ++ fo.field ++ "'");
            }
        }
    }
    
    return struct {
        fn compare(_: void, a: T, b: T) bool {
            inline for (field_orders) |fo| {
                const a_val = @field(a, fo.field);
                const b_val = @field(b, fo.field);
                if (fo.order == .asc) {
                    if (a_val < b_val) return true;
                    if (a_val > b_val) return false;
                } else {
                    if (a_val > b_val) return true;
                    if (a_val < b_val) return false;
                }
            }
            return false;
        }
    }.compare;
}

// CRITICAL TESTS

test "compareByField ascending and descending" {
    const Item = struct { value: u32 };
    const items = [_]Item{
        .{ .value = 3 },
        .{ .value = 1 },
        .{ .value = 2 },
    };
    
    // Test ascending
    var asc_sorted = items;
    std.sort.insertion(Item, asc_sorted[0..], {}, compareByField(Item, "value", .asc));
    try std.testing.expectEqual(@as(u32, 1), asc_sorted[0].value);
    try std.testing.expectEqual(@as(u32, 2), asc_sorted[1].value);
    try std.testing.expectEqual(@as(u32, 3), asc_sorted[2].value);
    
    // Test descending
    var desc_sorted = items;
    std.sort.insertion(Item, desc_sorted[0..], {}, compareByField(Item, "value", .desc));
    try std.testing.expectEqual(@as(u32, 3), desc_sorted[0].value);
    try std.testing.expectEqual(@as(u32, 2), desc_sorted[1].value);
    try std.testing.expectEqual(@as(u32, 1), desc_sorted[2].value);
}

test "byStringField descending and equality" {
    const Item = struct { name: []const u8 };
    const items = [_]Item{
        .{ .name = "charlie" },
        .{ .name = "alice" },
        .{ .name = "bob" },
        .{ .name = "alice" }, // duplicate to test equality
    };
    
    // Test ascending
    var asc_sorted = items;
    std.sort.insertion(Item, asc_sorted[0..], {}, byStringField(Item, "name", .asc));
    try std.testing.expect(std.mem.eql(u8, "alice", asc_sorted[0].name));
    try std.testing.expect(std.mem.eql(u8, "alice", asc_sorted[1].name));
    try std.testing.expect(std.mem.eql(u8, "bob", asc_sorted[2].name));
    try std.testing.expect(std.mem.eql(u8, "charlie", asc_sorted[3].name));
    
    // Test descending - CRITICAL test for the fix
    var desc_sorted = items;
    std.sort.insertion(Item, desc_sorted[0..], {}, byStringField(Item, "name", .desc));
    try std.testing.expect(std.mem.eql(u8, "charlie", desc_sorted[0].name));
    try std.testing.expect(std.mem.eql(u8, "bob", desc_sorted[1].name));
    try std.testing.expect(std.mem.eql(u8, "alice", desc_sorted[2].name));
    try std.testing.expect(std.mem.eql(u8, "alice", desc_sorted[3].name));
}

test "nullsFirstByField descending" {
    const Item = struct { value: ?u32 };
    const items = [_]Item{
        .{ .value = 3 },
        .{ .value = null },
        .{ .value = 1 },
        .{ .value = null },
        .{ .value = 2 },
    };
    
    // Test ascending (nulls first)
    var asc_sorted = items;
    std.sort.insertion(Item, asc_sorted[0..], {}, nullsFirstByField(Item, "value", .asc));
    try std.testing.expectEqual(@as(?u32, null), asc_sorted[0].value);
    try std.testing.expectEqual(@as(?u32, null), asc_sorted[1].value);
    try std.testing.expectEqual(@as(?u32, 1), asc_sorted[2].value);
    try std.testing.expectEqual(@as(?u32, 2), asc_sorted[3].value);
    try std.testing.expectEqual(@as(?u32, 3), asc_sorted[4].value);
    
    // Test descending (nulls still first)
    var desc_sorted = items;
    std.sort.insertion(Item, desc_sorted[0..], {}, nullsFirstByField(Item, "value", .desc));
    try std.testing.expectEqual(@as(?u32, null), desc_sorted[0].value);
    try std.testing.expectEqual(@as(?u32, null), desc_sorted[1].value);
    try std.testing.expectEqual(@as(?u32, 3), desc_sorted[2].value);
    try std.testing.expectEqual(@as(?u32, 2), desc_sorted[3].value);
    try std.testing.expectEqual(@as(?u32, 1), desc_sorted[4].value);
}

test "compareByFields multiple fields" {
    const TestStruct = struct {
        primary: i32,
        secondary: i32,
    };

    var items = [_]TestStruct{
        .{ .primary = 2, .secondary = 3 },
        .{ .primary = 1, .secondary = 2 },
        .{ .primary = 2, .secondary = 1 },
        .{ .primary = 1, .secondary = 1 },
    };

    const compare = compareByFields(TestStruct, &.{ "primary", "secondary" });
    std.sort.insertion(TestStruct, items[0..], {}, compare);

    try std.testing.expectEqual(@as(i32, 1), items[0].primary);
    try std.testing.expectEqual(@as(i32, 1), items[0].secondary);
    try std.testing.expectEqual(@as(i32, 1), items[1].primary);
    try std.testing.expectEqual(@as(i32, 2), items[1].secondary);
    try std.testing.expectEqual(@as(i32, 2), items[2].primary);
    try std.testing.expectEqual(@as(i32, 1), items[2].secondary);
    try std.testing.expectEqual(@as(i32, 2), items[3].primary);
    try std.testing.expectEqual(@as(i32, 3), items[3].secondary);
}

test "compareByFieldsWithOrder mixed ordering" {
    const TestStruct = struct {
        priority: i32,
        score: i32,
    };

    var items = [_]TestStruct{
        .{ .priority = 2, .score = 10 },
        .{ .priority = 1, .score = 20 },
        .{ .priority = 1, .score = 30 },
        .{ .priority = 2, .score = 5 },
    };

    const compare = compareByFieldsWithOrder(TestStruct, &.{
        .{ .field = "priority", .order = .asc },
        .{ .field = "score", .order = .desc },
    });
    std.sort.insertion(TestStruct, items[0..], {}, compare);

    // Priority 1 items first (ascending), then by score descending
    try std.testing.expectEqual(@as(i32, 1), items[0].priority);
    try std.testing.expectEqual(@as(i32, 30), items[0].score);
    try std.testing.expectEqual(@as(i32, 1), items[1].priority);
    try std.testing.expectEqual(@as(i32, 20), items[1].score);
    try std.testing.expectEqual(@as(i32, 2), items[2].priority);
    try std.testing.expectEqual(@as(i32, 10), items[2].score);
    try std.testing.expectEqual(@as(i32, 2), items[3].priority);
    try std.testing.expectEqual(@as(i32, 5), items[3].score);
}
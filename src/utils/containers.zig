const std = @import("std");

// Type aliases to shorten std prefix - NO wrapper functions!
// These are zero-cost aliases that compile to exactly the same code
pub const List = std.ArrayList;
pub const AutoMap = std.AutoHashMap;
pub const ArrayMap = std.ArrayHashMap;
pub const StrMap = std.StringHashMap;
pub const StrSet = std.BufSet;
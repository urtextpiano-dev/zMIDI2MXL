const std = @import("std");
const print = std.debug.print;
const testing = std.testing;

// ProcessingPhase enum - extracted from educational_processor.zig
pub const ProcessingPhase = enum {
    tuplet_detection,
    beam_grouping,
    rest_optimization,
    dynamics_mapping,
    coordination,

    // SIMPLIFIED IMPLEMENTATION using @tagName
    pub fn toString(self: ProcessingPhase) []const u8 {
        return @tagName(self);
    }
};

// Test all enum values
pub fn main() !void {
    print("Testing ProcessingPhase.toString() function\n");
    print("==========================================\n");

    // Test all enum variants
    const phases = [_]ProcessingPhase{
        .tuplet_detection,
        .beam_grouping,
        .rest_optimization,
        .dynamics_mapping,
        .coordination,
    };

    for (phases) |phase| {
        const result = phase.toString();
        print("ProcessingPhase.{s} -> \"{s}\"\n", .{ @tagName(phase), result });
    }

    print("\nAll tests completed successfully!\n");
}

// Unit tests
test "toString returns correct string for tuplet_detection" {
    const phase = ProcessingPhase.tuplet_detection;
    const result = phase.toString();
    try testing.expectEqualSlices(u8, "tuplet_detection", result);
}

test "toString returns correct string for beam_grouping" {
    const phase = ProcessingPhase.beam_grouping;
    const result = phase.toString();
    try testing.expectEqualSlices(u8, "beam_grouping", result);
}

test "toString returns correct string for rest_optimization" {
    const phase = ProcessingPhase.rest_optimization;
    const result = phase.toString();
    try testing.expectEqualSlices(u8, "rest_optimization", result);
}

test "toString returns correct string for dynamics_mapping" {
    const phase = ProcessingPhase.dynamics_mapping;
    const result = phase.toString();
    try testing.expectEqualSlices(u8, "dynamics_mapping", result);
}

test "toString returns correct string for coordination" {
    const phase = ProcessingPhase.coordination;
    const result = phase.toString();
    try testing.expectEqualSlices(u8, "coordination", result);
}

test "toString comprehensive validation" {
    // Test that all enum values return expected strings
    const expected_mapping = [_]struct {
        phase: ProcessingPhase,
        expected: []const u8,
    }{
        .{ .phase = .tuplet_detection, .expected = "tuplet_detection" },
        .{ .phase = .beam_grouping, .expected = "beam_grouping" },
        .{ .phase = .rest_optimization, .expected = "rest_optimization" },
        .{ .phase = .dynamics_mapping, .expected = "dynamics_mapping" },
        .{ .phase = .coordination, .expected = "coordination" },
    };

    for (expected_mapping) |mapping| {
        const result = mapping.phase.toString();
        try testing.expectEqualSlices(u8, mapping.expected, result);
        
        // Additional validation: result should match tagName for this enum
        try testing.expectEqualSlices(u8, @tagName(mapping.phase), result);
    }
}
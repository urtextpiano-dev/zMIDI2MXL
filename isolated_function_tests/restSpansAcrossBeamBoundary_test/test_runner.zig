const std = @import("std");
const testing = std.testing;

// Minimal struct definitions extracted from source
const RestSpan = struct {
    start_tick: u32,
    end_tick: u32,
};

const BeamGroupInfo = struct {
    start_tick: u32,
    end_tick: u32,
};

// Mock EducationalProcessor for isolated testing
const EducationalProcessor = struct {
    dummy: bool = true,
};

// Original function implementation
fn restSpansAcrossBeamBoundary(self: *EducationalProcessor, rest_span: RestSpan, beam_groups: []const BeamGroupInfo) bool {
    _ = self;
    
    var beam_groups_touched: u32 = 0;
    var starts_in_beam = false;
    var ends_in_beam = false;
    
    for (beam_groups) |group| {
        // Check if rest span starts within this beam group
        if (rest_span.start_tick >= group.start_tick and rest_span.start_tick < group.end_tick) {
            starts_in_beam = true;
            beam_groups_touched += 1;
        }
        
        // Check if rest span ends within this beam group
        if (rest_span.end_tick > group.start_tick and rest_span.end_tick <= group.end_tick) {
            ends_in_beam = true;
            beam_groups_touched += 1;
        }
        
        // Check if rest span completely encompasses beam group
        if (rest_span.start_tick <= group.start_tick and rest_span.end_tick >= group.end_tick) {
            beam_groups_touched += 1;
        }
    }
    
    // Rest spans across boundary if it touches multiple beam groups
    // or if it starts/ends in the middle of a beam group
    return beam_groups_touched > 1 or (starts_in_beam and !ends_in_beam) or (!starts_in_beam and ends_in_beam);
}

// Test cases
pub fn main() !void {
    var processor = EducationalProcessor{};
    
    // Test Case 1: Rest completely within single beam
    {
        const rest = RestSpan{ .start_tick = 100, .end_tick = 200 };
        const beams = [_]BeamGroupInfo{
            .{ .start_tick = 50, .end_tick = 250 },
        };
        const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
        std.debug.print("Test 1 (within single beam): {}\n", .{result});
    }
    
    // Test Case 2: Rest spans across two beams
    {
        const rest = RestSpan{ .start_tick = 150, .end_tick = 350 };
        const beams = [_]BeamGroupInfo{
            .{ .start_tick = 100, .end_tick = 200 },
            .{ .start_tick = 300, .end_tick = 400 },
        };
        const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
        std.debug.print("Test 2 (spans two beams): {}\n", .{result});
    }
    
    // Test Case 3: Rest starts in beam, ends outside
    {
        const rest = RestSpan{ .start_tick = 150, .end_tick = 250 };
        const beams = [_]BeamGroupInfo{
            .{ .start_tick = 100, .end_tick = 200 },
        };
        const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
        std.debug.print("Test 3 (starts in, ends out): {}\n", .{result});
    }
    
    // Test Case 4: Rest starts outside, ends in beam
    {
        const rest = RestSpan{ .start_tick = 50, .end_tick = 150 };
        const beams = [_]BeamGroupInfo{
            .{ .start_tick = 100, .end_tick = 200 },
        };
        const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
        std.debug.print("Test 4 (starts out, ends in): {}\n", .{result});
    }
    
    // Test Case 5: Rest encompasses entire beam
    {
        const rest = RestSpan{ .start_tick = 50, .end_tick = 250 };
        const beams = [_]BeamGroupInfo{
            .{ .start_tick = 100, .end_tick = 200 },
        };
        const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
        std.debug.print("Test 5 (encompasses beam): {}\n", .{result});
    }
    
    // Test Case 6: Rest touches multiple beams
    {
        const rest = RestSpan{ .start_tick = 150, .end_tick = 450 };
        const beams = [_]BeamGroupInfo{
            .{ .start_tick = 100, .end_tick = 200 },
            .{ .start_tick = 300, .end_tick = 400 },
            .{ .start_tick = 400, .end_tick = 500 },
        };
        const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
        std.debug.print("Test 6 (touches multiple): {}\n", .{result});
    }
    
    // Test Case 7: No overlap
    {
        const rest = RestSpan{ .start_tick = 500, .end_tick = 600 };
        const beams = [_]BeamGroupInfo{
            .{ .start_tick = 100, .end_tick = 200 },
            .{ .start_tick = 300, .end_tick = 400 },
        };
        const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
        std.debug.print("Test 7 (no overlap): {}\n", .{result});
    }
}

test "rest within single beam" {
    var processor = EducationalProcessor{};
    const rest = RestSpan{ .start_tick = 100, .end_tick = 200 };
    const beams = [_]BeamGroupInfo{
        .{ .start_tick = 50, .end_tick = 250 },
    };
    const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
    try testing.expect(result == false);
}

test "rest spans two beams" {
    var processor = EducationalProcessor{};
    const rest = RestSpan{ .start_tick = 150, .end_tick = 350 };
    const beams = [_]BeamGroupInfo{
        .{ .start_tick = 100, .end_tick = 200 },
        .{ .start_tick = 300, .end_tick = 400 },
    };
    const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
    try testing.expect(result == true);
}

test "rest starts in beam ends outside" {
    var processor = EducationalProcessor{};
    const rest = RestSpan{ .start_tick = 150, .end_tick = 250 };
    const beams = [_]BeamGroupInfo{
        .{ .start_tick = 100, .end_tick = 200 },
    };
    const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
    try testing.expect(result == true);
}

test "rest starts outside ends in beam" {
    var processor = EducationalProcessor{};
    const rest = RestSpan{ .start_tick = 50, .end_tick = 150 };
    const beams = [_]BeamGroupInfo{
        .{ .start_tick = 100, .end_tick = 200 },
    };
    const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
    try testing.expect(result == true);
}

test "rest encompasses beam" {
    var processor = EducationalProcessor{};
    const rest = RestSpan{ .start_tick = 50, .end_tick = 250 };
    const beams = [_]BeamGroupInfo{
        .{ .start_tick = 100, .end_tick = 200 },
    };
    const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
    try testing.expect(result == false);
}

test "rest touches multiple beams" {
    var processor = EducationalProcessor{};
    const rest = RestSpan{ .start_tick = 150, .end_tick = 450 };
    const beams = [_]BeamGroupInfo{
        .{ .start_tick = 100, .end_tick = 200 },
        .{ .start_tick = 300, .end_tick = 400 },
        .{ .start_tick = 400, .end_tick = 500 },
    };
    const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
    try testing.expect(result == true);
}

test "no overlap" {
    var processor = EducationalProcessor{};
    const rest = RestSpan{ .start_tick = 500, .end_tick = 600 };
    const beams = [_]BeamGroupInfo{
        .{ .start_tick = 100, .end_tick = 200 },
        .{ .start_tick = 300, .end_tick = 400 },
    };
    const result = restSpansAcrossBeamBoundary(&processor, rest, &beams);
    try testing.expect(result == false);
}
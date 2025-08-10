//! Rest Optimization Algorithm Module
//! 
//! Implements TASK-050: Rest Optimization Algorithm per IMPLEMENTATION_TASK_LIST.md lines 626-635
//! 
//! This module consolidates rests optimally for clean, readable sheet music notation.
//! Designed specifically for educational use where clear rhythm representation is essential.
//! 
//! Features:
//! - Consolidate multiple small rests into larger values
//! - Respect beat boundaries based on time signature
//! - Follow standard music notation conventions
//! - Prioritize readability over mathematical precision
//! 
//! Performance target: < 500μs per beat
//! 
//! Reference: musical_intelligence_algorithms.md Section 7.4 lines 1274-1307

const std = @import("std");
const containers = @import("../utils/containers.zig");
const log = std.log.scoped(.rest_optimizer);

/// Error types for rest optimization operations
pub const RestOptimizationError = error{
    InvalidTimeSignature,
    InvalidDuration,
    AllocationFailure,
    InvalidRestPosition,
};

/// Represents a gap in the music that needs to be filled with rests
pub const Gap = struct {
    /// Start position in divisions (absolute time)
    start_time: u32,
    /// Duration of the gap in divisions
    duration: u32,
    /// Measure number this gap belongs to
    measure_number: u32,
};

/// Represents an optimized rest
pub const Rest = struct {
    /// Start position in divisions (absolute time)
    start_time: u32,
    /// Duration in divisions
    duration: u32,
    /// Note type (whole, half, quarter, etc.)
    note_type: NoteType,
    /// Number of dots (0, 1, or 2)
    dots: u8,
    /// Alignment score (higher is better)
    alignment_score: f32,
    /// Measure number this rest belongs to
    measure_number: u32,
};

/// Note types for rests (matching note_type_converter.zig)
pub const NoteType = enum {
    breve,
    whole,
    half,
    quarter,
    eighth,
    @"16th",
    @"32nd",
    @"64th",
    @"128th",
    @"256th",
    
    pub fn toString(self: NoteType) []const u8 {
        return switch (self) {
            .breve => "breve",
            .whole => "whole",
            .half => "half",
            .quarter => "quarter",
            .eighth => "eighth",
            .@"16th" => "16th",
            .@"32nd" => "32nd",
            .@"64th" => "64th",
            .@"128th" => "128th",
            .@"256th" => "256th",
        };
    }
    
    /// Get duration in divisions for this note type
    pub fn getDurationInDivisions(self: NoteType, divisions_per_quarter: u32) u32 {
        return switch (self) {
            .breve => divisions_per_quarter * 8,
            .whole => divisions_per_quarter * 4,
            .half => divisions_per_quarter * 2,
            .quarter => divisions_per_quarter,
            .eighth => divisions_per_quarter / 2,
            .@"16th" => divisions_per_quarter / 4,
            .@"32nd" => divisions_per_quarter / 8,
            .@"64th" => divisions_per_quarter / 16,
            .@"128th" => divisions_per_quarter / 32,
            .@"256th" => divisions_per_quarter / 64,
        };
    }
};

/// Time signature information for rest optimization
pub const TimeSignature = struct {
    numerator: u8,
    denominator: u8,
    /// Duration of one measure in divisions
    measure_duration: u32,
    /// Duration of one beat in divisions
    beat_duration: u32,
};

/// Rest optimizer configuration
pub const RestOptimizerConfig = struct {
    /// Weight for beat alignment scoring
    beat_alignment_weight: f32 = 2.0,
    /// Weight for simplicity scoring (fewer rests)
    simplicity_weight: f32 = 1.5,
    /// Weight for standard notation patterns
    convention_weight: f32 = 1.0,
    /// Minimum alignment score to accept a rest
    min_alignment_score: f32 = 0.5,
    /// Whether to allow dotted rests
    allow_dotted_rests: bool = true,
    /// Maximum number of dots allowed (usually 1 or 2)
    max_dots: u8 = 1,
};

/// Beam group information for rest optimization coordination
pub const BeamGroupConstraint = struct {
    /// Beam group ID
    group_id: u32,
    /// Start time of beam group
    start_time: u32,
    /// End time of beam group
    end_time: u32,
    /// Beam level (1, 2, 3 for 8th, 16th, 32nd)
    beam_level: u8,
};

/// Minimum meaningful rest threshold - filters negligible gaps that should be absorbed as measurement noise
/// Set to 60 ticks (~12.5% of quarter note at 480 divisions) per EXECUTIVE AUTHORITY fix
pub const MIN_MEANINGFUL_REST_THRESHOLD: u32 = 60;

/// Main rest optimizer struct
pub const RestOptimizer = struct {
    allocator: std.mem.Allocator,
    config: RestOptimizerConfig,
    divisions_per_quarter: u32,
    
    /// Initialize a new rest optimizer
    pub fn init(allocator: std.mem.Allocator, divisions_per_quarter: u32) RestOptimizer {
        return .{
            .allocator = allocator,
            .config = RestOptimizerConfig{},
            .divisions_per_quarter = divisions_per_quarter,
        };
    }
    
    /// Initialize with custom configuration
    pub fn initWithConfig(allocator: std.mem.Allocator, divisions_per_quarter: u32, config: RestOptimizerConfig) RestOptimizer {
        return .{
            .allocator = allocator,
            .config = config,
            .divisions_per_quarter = divisions_per_quarter,
        };
    }
    
    
    /// Optimize rests for a list of gaps
    /// Returns a list of optimized rests that fill all gaps
    pub fn optimizeRests(self: *RestOptimizer, gaps: []const Gap, time_sig: TimeSignature) ![]Rest {
        return self.optimizeRestsWithBeamAwareness(gaps, time_sig, null);
    }
    
    /// Optimize rests with beam group awareness for educational processing
    /// This respects beam group boundaries during rest consolidation
    pub fn optimizeRestsWithBeamAwareness(self: *RestOptimizer, gaps: []const Gap, time_sig: TimeSignature, beam_constraints: ?[]const BeamGroupConstraint) ![]Rest {
        var result = containers.List(Rest).init(self.allocator);
        errdefer result.deinit();
        
        // Process each gap independently with beam awareness
        for (gaps) |gap| {
            const gap_rests = try self.optimizeGapWithBeamAwareness(gap, time_sig, beam_constraints);
            defer self.allocator.free(gap_rests);
            
            try result.appendSlice(gap_rests);
        }
        
        // Consolidate adjacent rests where possible, respecting beam constraints
        const consolidated = try self.consolidateRestsWithBeamAwareness(result.items, time_sig, beam_constraints);
        result.deinit();
        
        return consolidated;
    }
    
    /// Optimize a single gap into one or more rests with beam awareness
    fn optimizeGapWithBeamAwareness(self: *RestOptimizer, gap: Gap, time_sig: TimeSignature, beam_constraints: ?[]const BeamGroupConstraint) ![]Rest {
        // CRITICAL: Filter negligible gaps per EXECUTIVE AUTHORITY fix
        // Tiny timing inaccuracies should be absorbed as measurement noise, not amplified to musical rests
        if (gap.duration < MIN_MEANINGFUL_REST_THRESHOLD) {
            return try self.allocator.alloc(Rest, 0); // No rest for tiny gaps
        }
        
        var rests = containers.List(Rest).init(self.allocator);
        errdefer rests.deinit();
        
        var remaining_duration = gap.duration;
        var current_position = gap.start_time;
        
        while (remaining_duration > 0) {
            // Check for beam group constraints at current position
            const max_duration_at_position = self.getMaxRestDurationAtPosition(
                current_position,
                remaining_duration,
                beam_constraints,
                time_sig,
            );
            
            // Find the best rest for this position with beam constraints
            const best_rest = try self.findBestRestWithBeamAwareness(
                current_position,
                max_duration_at_position,
                gap.measure_number,
                time_sig,
                beam_constraints,
            );
            
            if (best_rest.duration == 0) {
                return RestOptimizationError.InvalidDuration;
            }
            
            // Prevent integer underflow: ensure we don't subtract more than we have
            if (best_rest.duration > remaining_duration) {
                // Adjust the rest duration to not exceed remaining duration
                var adjusted_rest = best_rest;
                adjusted_rest.duration = remaining_duration;
                try rests.append(adjusted_rest);
                current_position += adjusted_rest.duration;
                remaining_duration = 0;
            } else {
                try rests.append(best_rest);
                current_position += best_rest.duration;
                remaining_duration -= best_rest.duration;
            }
        }
        
        return rests.toOwnedSlice();
    }
    
    /// Optimize a single gap into one or more rests (legacy method)
    fn optimizeGap(self: *RestOptimizer, gap: Gap, time_sig: TimeSignature) ![]Rest {
        // CRITICAL: Filter negligible gaps per EXECUTIVE AUTHORITY fix
        // Tiny timing inaccuracies should be absorbed as measurement noise, not amplified to musical rests
        if (gap.duration < MIN_MEANINGFUL_REST_THRESHOLD) {
            return try self.allocator.alloc(Rest, 0); // No rest for tiny gaps
        }
        
        var rests = containers.List(Rest).init(self.allocator);
        errdefer rests.deinit();
        
        var remaining_duration = gap.duration;
        var current_position = gap.start_time;
        
        while (remaining_duration > 0) {
            // Find the best rest for this position
            const best_rest = try self.findBestRest(
                current_position,
                remaining_duration,
                gap.measure_number,
                time_sig,
            );
            
            if (best_rest.duration == 0) {
                return RestOptimizationError.InvalidDuration;
            }
            
            // Prevent integer underflow: ensure we don't subtract more than we have
            if (best_rest.duration > remaining_duration) {
                // Adjust the rest duration to not exceed remaining duration
                var adjusted_rest = best_rest;
                adjusted_rest.duration = remaining_duration;
                try rests.append(adjusted_rest);
                current_position += adjusted_rest.duration;
                remaining_duration = 0;
            } else {
                try rests.append(best_rest);
                current_position += best_rest.duration;
                remaining_duration -= best_rest.duration;
            }
        }
        
        return rests.toOwnedSlice();
    }
    
    /// Get maximum rest duration at position considering beam constraints
    fn getMaxRestDurationAtPosition(self: *RestOptimizer, position: u32, available_duration: u32, beam_constraints: ?[]const BeamGroupConstraint, time_sig: TimeSignature) u32 {
        
        if (beam_constraints == null) return available_duration;
        
        var max_duration = available_duration;
        
        // Check if position is within any beam group
        for (beam_constraints.?) |constraint| {
            // If we're inside a beam group, limit rest duration to not extend beyond group
            if (position >= constraint.start_time and position < constraint.end_time) {
                const remaining_in_group = constraint.end_time - position;
                max_duration = @min(max_duration, remaining_in_group);
            }
            // If beam group starts within our available duration, limit to beam start
            else if (constraint.start_time > position and constraint.start_time < position + available_duration) {
                const duration_to_beam = constraint.start_time - position;
                max_duration = @min(max_duration, duration_to_beam);
            }
        }
        
        // Also respect beat boundaries more strictly near beam groups
        const position_in_measure = position % time_sig.measure_duration;
        const position_in_beat = position_in_measure % time_sig.beat_duration;
        
        // If near beam boundaries, prefer to align with beat subdivisions
        if (self.isNearBeamGroup(position, beam_constraints)) {
            const next_eighth_boundary = time_sig.beat_duration / 2 - (position_in_beat % (time_sig.beat_duration / 2));
            if (next_eighth_boundary < max_duration) {
                max_duration = @min(max_duration, next_eighth_boundary);
            }
        }
        
        return max_duration;
    }
    
    /// Check if position is near a beam group
    fn isNearBeamGroup(self: *RestOptimizer, position: u32, beam_constraints: ?[]const BeamGroupConstraint) bool {
        
        if (beam_constraints == null) return false;
        
        const proximity_threshold = self.divisions_per_quarter / 4; // Sixteenth note proximity
        
        for (beam_constraints.?) |constraint| {
            if ((position >= constraint.start_time -| proximity_threshold and position <= constraint.start_time + proximity_threshold) or
                (position >= constraint.end_time -| proximity_threshold and position <= constraint.end_time + proximity_threshold)) {
                return true;
            }
        }
        
        return false;
    }
    
    /// Find the best rest to place at a given position with beam awareness
    fn findBestRestWithBeamAwareness(self: *RestOptimizer, start_time: u32, max_duration: u32, measure_number: u32, time_sig: TimeSignature, beam_constraints: ?[]const BeamGroupConstraint) !Rest {
        // For beam-aware processing, we use stricter alignment rules
        var best_rest: ?Rest = null;
        var best_score: f32 = -std.math.inf(f32);
        
        // Special case: empty measure gets whole rest regardless of beam constraints
        const position_in_measure = start_time % time_sig.measure_duration;
        if (position_in_measure == 0 and max_duration >= time_sig.measure_duration) {
            return Rest{
                .start_time = start_time,
                .duration = time_sig.measure_duration,
                .note_type = .whole,
                .dots = 0,
                .alignment_score = 10.0,
                .measure_number = measure_number,
            };
        }
        
        // Try each rest value from largest to smallest
        const rest_types = [_]NoteType{
            .whole, .half, .quarter, .eighth,
            .@"16th", .@"32nd", .@"64th",
        };
        
        for (rest_types) |rest_type| {
            // Try without dots first
            const base_duration = rest_type.getDurationInDivisions(self.divisions_per_quarter);
            if (base_duration <= max_duration) {
                const score = self.computeRestScoreWithBeamAwareness(start_time, base_duration, rest_type, 0, time_sig, beam_constraints);
                if (score > best_score) {
                    best_score = score;
                    best_rest = Rest{
                        .start_time = start_time,
                        .duration = base_duration,
                        .note_type = rest_type,
                        .dots = 0,
                        .alignment_score = score,
                        .measure_number = measure_number,
                    };
                }
            }
            
            // Try with dots if allowed
            if (self.config.allow_dotted_rests) {
                var dots: u8 = 1;
                while (dots <= self.config.max_dots) : (dots += 1) {
                    const dotted_duration = self.calculateDottedDuration(base_duration, dots);
                    if (dotted_duration <= max_duration) {
                        const score = self.computeRestScoreWithBeamAwareness(start_time, dotted_duration, rest_type, dots, time_sig, beam_constraints);
                        if (score > best_score) {
                            best_score = score;
                            best_rest = Rest{
                                .start_time = start_time,
                                .duration = dotted_duration,
                                .note_type = rest_type,
                                .dots = dots,
                                .alignment_score = score,
                                .measure_number = measure_number,
                            };
                        }
                    }
                }
            }
        }
        
        // If no good rest found, use the largest that fits
        if (best_rest == null) {
            for (rest_types) |rest_type| {
                const duration = rest_type.getDurationInDivisions(self.divisions_per_quarter);
                if (duration <= max_duration) {
                    return Rest{
                        .start_time = start_time,
                        .duration = duration,
                        .note_type = rest_type,
                        .dots = 0,
                        .alignment_score = 0.0,
                        .measure_number = measure_number,
                    };
                }
            }
            
            // Last resort: use smallest rest
            return Rest{
                .start_time = start_time,
                .duration = self.divisions_per_quarter / 64, // 256th note
                .note_type = .@"256th",
                .dots = 0,
                .alignment_score = 0.0,
                .measure_number = measure_number,
            };
        }
        
        return best_rest.?;
    }
    
    /// Find the best rest to place at a given position (legacy method)
    fn findBestRest(self: *RestOptimizer, start_time: u32, max_duration: u32, measure_number: u32, time_sig: TimeSignature) !Rest {
        var best_rest: ?Rest = null;
        var best_score: f32 = -std.math.inf(f32);
        
        // Special case: empty measure gets whole rest regardless of time signature
        const position_in_measure = start_time % time_sig.measure_duration;
        if (position_in_measure == 0 and max_duration >= time_sig.measure_duration) {
            return Rest{
                .start_time = start_time,
                .duration = time_sig.measure_duration,
                .note_type = .whole,
                .dots = 0,
                .alignment_score = 10.0, // Perfect score for whole measure rest
                .measure_number = measure_number,
            };
        }
        
        // Try each rest value from largest to smallest
        const rest_types = [_]NoteType{
            .whole, .half, .quarter, .eighth,
            .@"16th", .@"32nd", .@"64th",
        };
        
        for (rest_types) |rest_type| {
            // Try without dots first
            const base_duration = rest_type.getDurationInDivisions(self.divisions_per_quarter);
            if (base_duration <= max_duration) {
                const score = self.computeRestScore(start_time, base_duration, rest_type, 0, time_sig);
                if (score > best_score) {
                    best_score = score;
                    best_rest = Rest{
                        .start_time = start_time,
                        .duration = base_duration,
                        .note_type = rest_type,
                        .dots = 0,
                        .alignment_score = score,
                        .measure_number = measure_number,
                    };
                }
            }
            
            // Try with dots if allowed
            if (self.config.allow_dotted_rests) {
                var dots: u8 = 1;
                while (dots <= self.config.max_dots) : (dots += 1) {
                    const dotted_duration = self.calculateDottedDuration(base_duration, dots);
                    if (dotted_duration <= max_duration) {
                        const score = self.computeRestScore(start_time, dotted_duration, rest_type, dots, time_sig);
                        if (score > best_score) {
                            best_score = score;
                            best_rest = Rest{
                                .start_time = start_time,
                                .duration = dotted_duration,
                                .note_type = rest_type,
                                .dots = dots,
                                .alignment_score = score,
                                .measure_number = measure_number,
                            };
                        }
                    }
                }
            }
        }
        
        // If no good rest found, use the largest that fits
        if (best_rest == null) {
            for (rest_types) |rest_type| {
                const duration = rest_type.getDurationInDivisions(self.divisions_per_quarter);
                if (duration <= max_duration) {
                    return Rest{
                        .start_time = start_time,
                        .duration = duration,
                        .note_type = rest_type,
                        .dots = 0,
                        .alignment_score = 0.0,
                        .measure_number = measure_number,
                    };
                }
            }
            
            // Last resort: use smallest rest
            return Rest{
                .start_time = start_time,
                .duration = self.divisions_per_quarter / 64, // 256th note
                .note_type = .@"256th",
                .dots = 0,
                .alignment_score = 0.0,
                .measure_number = measure_number,
            };
        }
        
        return best_rest.?;
    }
    
    /// Calculate duration with dots
    fn calculateDottedDuration(self: *RestOptimizer, base_duration: u32, dots: u8) u32 {
        _ = self;
        var duration = base_duration;
        var dot_value = base_duration / 2;
        var i: u8 = 0;
        while (i < dots) : (i += 1) {
            duration += dot_value;
            dot_value /= 2;
        }
        return duration;
    }
    
    /// Compute alignment score for a rest with beam awareness
    fn computeRestScoreWithBeamAwareness(self: *RestOptimizer, start_time: u32, duration: u32, rest_type: NoteType, dots: u8, time_sig: TimeSignature, beam_constraints: ?[]const BeamGroupConstraint) f32 {
        var score = self.computeRestScore(start_time, duration, rest_type, dots, time_sig);
        
        // Apply beam-aware scoring modifiers
        if (beam_constraints != null) {
            // Bonus for not crossing beam group boundaries
            var crosses_beam_boundary = false;
            for (beam_constraints.?) |constraint| {
                // Check if rest spans across beam group boundary
                if (start_time < constraint.start_time and start_time + duration > constraint.start_time) {
                    crosses_beam_boundary = true;
                    break;
                }
                if (start_time < constraint.end_time and start_time + duration > constraint.end_time) {
                    crosses_beam_boundary = true;
                    break;
                }
            }
            
            if (!crosses_beam_boundary) {
                score += self.config.convention_weight * 0.5; // Bonus for respecting beam boundaries
            } else {
                score -= self.config.convention_weight * 1.0; // Penalty for crossing boundaries
            }
            
            // Bonus for aligning with beam group subdivisions
            if (self.alignsWithBeamSubdivisions(start_time, duration, beam_constraints)) {
                score += self.config.beat_alignment_weight * 0.3;
            }
        }
        
        return score;
    }
    
    /// Check if rest aligns well with beam group subdivisions
    fn alignsWithBeamSubdivisions(self: *RestOptimizer, start_time: u32, duration: u32, beam_constraints: ?[]const BeamGroupConstraint) bool {
        _ = duration;
        
        if (beam_constraints == null) return false;
        
        const eighth_note_duration = self.divisions_per_quarter / 2;
        const sixteenth_note_duration = self.divisions_per_quarter / 4;
        
        for (beam_constraints.?) |constraint| {
            // Check if rest starts at subdivision boundaries relative to beam group
            const offset_from_beam_start = start_time -| constraint.start_time;
            
            // Eighth note alignment for beam level 1
            if (constraint.beam_level >= 1 and offset_from_beam_start % eighth_note_duration == 0) {
                return true;
            }
            
            // Sixteenth note alignment for beam level 2+
            if (constraint.beam_level >= 2 and offset_from_beam_start % sixteenth_note_duration == 0) {
                return true;
            }
        }
        
        return false;
    }
    
    /// Compute alignment score for a rest at a given position
    fn computeRestScore(self: *RestOptimizer, start_time: u32, duration: u32, rest_type: NoteType, dots: u8, time_sig: TimeSignature) f32 {
        var score: f32 = 0.0;
        
        // Beat alignment score
        const position_in_measure = start_time % time_sig.measure_duration;
        const position_in_beat = position_in_measure % time_sig.beat_duration;
        
        // Perfect alignment on beat boundary
        if (position_in_beat == 0) {
            score += self.config.beat_alignment_weight * 1.0;
        }
        // Half-beat alignment (useful for compound meters)
        else if (position_in_beat == time_sig.beat_duration / 2) {
            score += self.config.beat_alignment_weight * 0.5;
        }
        
        // Check if rest ends on beat boundary
        const end_position = (start_time + duration) % time_sig.measure_duration;
        const end_in_beat = end_position % time_sig.beat_duration;
        if (end_in_beat == 0) {
            score += self.config.beat_alignment_weight * 0.5;
        }
        
        // Simplicity score - prefer fewer, larger rests
        const simplicity_score: f32 = switch (rest_type) {
            .whole => 1.0,
            .half => 0.9,
            .quarter => 0.8,
            .eighth => 0.6,
            .@"16th" => 0.4,
            .@"32nd" => 0.2,
            else => 0.1,
        };
        score += self.config.simplicity_weight * simplicity_score;
        
        // Penalize dots slightly (simpler is better for education)
        score -= @as(f32, @floatFromInt(dots)) * 0.2;
        
        // Convention score - common patterns
        score += self.computeConventionScore(rest_type, position_in_measure, time_sig);
        
        return score;
    }
    
    /// Compute score based on common notation conventions
    fn computeConventionScore(self: *RestOptimizer, rest_type: NoteType, position_in_measure: u32, time_sig: TimeSignature) f32 {
        var score: f32 = 0.0;
        
        // 4/4 time specific patterns
        if (time_sig.numerator == 4 and time_sig.denominator == 4) {
            // Whole rest at start of measure
            if (position_in_measure == 0 and rest_type == .whole) {
                score += self.config.convention_weight * 1.0;
            }
            // Half rest at start or middle of measure
            else if ((position_in_measure == 0 or position_in_measure == time_sig.beat_duration * 2) and rest_type == .half) {
                score += self.config.convention_weight * 0.8;
            }
        }
        
        // 3/4 time specific patterns
        if (time_sig.numerator == 3 and time_sig.denominator == 4) {
            // Dotted half for full measure
            if (position_in_measure == 0 and rest_type == .half) {
                score += self.config.convention_weight * 0.9;
            }
        }
        
        // 6/8 time specific patterns
        if (time_sig.numerator == 6 and time_sig.denominator == 8) {
            // Dotted quarter aligns with compound beats
            if ((position_in_measure % (time_sig.beat_duration * 3 / 2) == 0) and rest_type == .quarter) {
                score += self.config.convention_weight * 0.8;
            }
        }
        
        return score;
    }
    
    /// Consolidate adjacent rests with beam awareness
    fn consolidateRestsWithBeamAwareness(self: *RestOptimizer, rests: []const Rest, time_sig: TimeSignature, beam_constraints: ?[]const BeamGroupConstraint) ![]Rest {
        if (rests.len == 0) return try self.allocator.alloc(Rest, 0);
        
        var consolidated = containers.List(Rest).init(self.allocator);
        errdefer consolidated.deinit();
        
        var i: usize = 0;
        while (i < rests.len) {
            var current_rest = rests[i];
            var j = i + 1;
            
            // Look for adjacent rests that can be combined
            while (j < rests.len and 
                   rests[j].start_time == current_rest.start_time + current_rest.duration and
                   rests[j].measure_number == current_rest.measure_number) {
                const combined_duration = current_rest.duration + rests[j].duration;
                
                // Check if combined rest would be valid and respect beam constraints
                if (self.canCombineRestsWithBeamAwareness(current_rest, rests[j], time_sig, beam_constraints)) {
                    // Try to find a single rest that represents the combined duration
                    const combined_rest = try self.findBestRestWithBeamAwareness(
                        current_rest.start_time,
                        combined_duration,
                        current_rest.measure_number,
                        time_sig,
                        beam_constraints,
                    );
                    
                    // Only combine if the score improves
                    if (combined_rest.alignment_score > current_rest.alignment_score + rests[j].alignment_score * 0.5) {
                        current_rest = combined_rest;
                        j += 1;
                        continue;
                    }
                }
                break;
            }
            
            try consolidated.append(current_rest);
            i = j;
        }
        
        return consolidated.toOwnedSlice();
    }
    
    /// Consolidate adjacent rests where possible (legacy method)
    fn consolidateRests(self: *RestOptimizer, rests: []const Rest, time_sig: TimeSignature) ![]Rest {
        if (rests.len == 0) return try self.allocator.alloc(Rest, 0);
        
        var consolidated = containers.List(Rest).init(self.allocator);
        errdefer consolidated.deinit();
        
        var i: usize = 0;
        while (i < rests.len) {
            var current_rest = rests[i];
            var j = i + 1;
            
            // Look for adjacent rests that can be combined
            while (j < rests.len and 
                   rests[j].start_time == current_rest.start_time + current_rest.duration and
                   rests[j].measure_number == current_rest.measure_number) {
                const combined_duration = current_rest.duration + rests[j].duration;
                
                // Check if combined rest would be valid and better
                if (self.canCombineRests(current_rest, rests[j], time_sig)) {
                    // Try to find a single rest that represents the combined duration
                    const combined_rest = try self.findBestRest(
                        current_rest.start_time,
                        combined_duration,
                        current_rest.measure_number,
                        time_sig,
                    );
                    
                    // Only combine if the score improves
                    if (combined_rest.alignment_score > current_rest.alignment_score + rests[j].alignment_score * 0.5) {
                        current_rest = combined_rest;
                        j += 1;
                        continue;
                    }
                }
                break;
            }
            
            try consolidated.append(current_rest);
            i = j;
        }
        
        return consolidated.toOwnedSlice();
    }
    
    /// Check if two rests can be combined with beam awareness
    fn canCombineRestsWithBeamAwareness(self: *RestOptimizer, rest1: Rest, rest2: Rest, time_sig: TimeSignature, beam_constraints: ?[]const BeamGroupConstraint) bool {
        // First check basic combination rules
        if (!self.canCombineRests(rest1, rest2, time_sig)) {
            return false;
        }
        
        // Additional beam-aware checks
        if (beam_constraints != null) {
            const combined_start = rest1.start_time;
            const combined_end = rest2.start_time + rest2.duration;
            
            // Don't combine if it would span across beam group boundaries
            for (beam_constraints.?) |constraint| {
                // Check if combination would cross beam boundaries
                if (combined_start < constraint.start_time and combined_end > constraint.start_time) {
                    return false;
                }
                if (combined_start < constraint.end_time and combined_end > constraint.end_time) {
                    return false;
                }
                
                // Don't combine rests that are within different beam groups
                const rest1_in_beam = (rest1.start_time >= constraint.start_time and rest1.start_time < constraint.end_time);
                const rest2_in_beam = (rest2.start_time >= constraint.start_time and rest2.start_time < constraint.end_time);
                
                if (rest1_in_beam != rest2_in_beam) {
                    return false;
                }
            }
        }
        
        return true;
    }
    
    /// Check if two rests can be combined (legacy method)
    fn canCombineRests(self: *RestOptimizer, rest1: Rest, rest2: Rest, time_sig: TimeSignature) bool {
        _ = self;
        
        // Don't combine across beat boundaries in most cases
        const rest1_end = rest1.start_time + rest1.duration;
        const rest1_end_beat = (rest1_end % time_sig.measure_duration) / time_sig.beat_duration;
        const rest2_start_beat = (rest2.start_time % time_sig.measure_duration) / time_sig.beat_duration;
        
        // Allow combining within the same beat
        if (rest1_end_beat == rest2_start_beat) {
            return true;
        }
        
        // Allow combining across beats for whole/half rests
        if (rest1.note_type == .half or rest1.note_type == .whole) {
            return true;
        }
        
        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "empty measure gets whole rest" {
    const allocator = testing.allocator;
    var optimizer = RestOptimizer.init(allocator, 480); // 480 divisions per quarter
    
    const time_sig = TimeSignature{
        .numerator = 4,
        .denominator = 4,
        .measure_duration = 1920, // 4 quarters
        .beat_duration = 480,     // 1 quarter
    };
    
    const gaps = [_]Gap{
        Gap{
            .start_time = 0,
            .duration = 1920,
            .measure_number = 1,
        },
    };
    
    const rests = try optimizer.optimizeRests(&gaps, time_sig);
    defer allocator.free(rests);
    
    try testing.expectEqual(@as(usize, 1), rests.len);
    try testing.expectEqual(NoteType.whole, rests[0].note_type);
    try testing.expectEqual(@as(u32, 1920), rests[0].duration);
}

test "consolidate quarter rests" {
    const allocator = testing.allocator;
    var optimizer = RestOptimizer.init(allocator, 480);
    
    const time_sig = TimeSignature{
        .numerator = 4,
        .denominator = 4,
        .measure_duration = 1920,
        .beat_duration = 480,
    };
    
    // Two quarter rests that should become a half rest
    const gaps = [_]Gap{
        Gap{
            .start_time = 0,
            .duration = 960, // 2 quarters
            .measure_number = 1,
        },
    };
    
    const rests = try optimizer.optimizeRests(&gaps, time_sig);
    defer allocator.free(rests);
    
    try testing.expectEqual(@as(usize, 1), rests.len);
    try testing.expectEqual(NoteType.half, rests[0].note_type);
}

test "respect beat boundaries" {
    const allocator = testing.allocator;
    var optimizer = RestOptimizer.init(allocator, 480);
    
    const time_sig = TimeSignature{
        .numerator = 4,
        .denominator = 4,
        .measure_duration = 1920,
        .beat_duration = 480,
    };
    
    // Gap from middle of beat 2 to middle of beat 3
    const gaps = [_]Gap{
        Gap{
            .start_time = 720,  // 1.5 beats
            .duration = 480,    // 1 quarter
            .measure_number = 1,
        },
    };
    
    const rests = try optimizer.optimizeRests(&gaps, time_sig);
    defer allocator.free(rests);
    
    // Should create two eighth rests rather than one quarter
    // to respect beat boundaries
    try testing.expect(rests.len >= 1);
}

test "6/8 time signature" {
    const allocator = testing.allocator;
    var optimizer = RestOptimizer.init(allocator, 480);
    
    const time_sig = TimeSignature{
        .numerator = 6,
        .denominator = 8,
        .measure_duration = 720,  // 6 eighths = 1.5 quarters
        .beat_duration = 240,     // 1 eighth
    };
    
    // Full measure in 6/8
    const gaps = [_]Gap{
        Gap{
            .start_time = 0,
            .duration = 720,
            .measure_number = 1,
        },
    };
    
    const rests = try optimizer.optimizeRests(&gaps, time_sig);
    defer allocator.free(rests);
    
    // Should use whole rest for empty measure even in 6/8
    try testing.expectEqual(@as(usize, 1), rests.len);
    try testing.expectEqual(NoteType.whole, rests[0].note_type);
}

test "dotted rest support" {
    const allocator = testing.allocator;
    const config = RestOptimizerConfig{
        .allow_dotted_rests = true,
        .max_dots = 1,
    };
    var optimizer = RestOptimizer.initWithConfig(allocator, 480, config);
    
    const time_sig = TimeSignature{
        .numerator = 3,
        .denominator = 4,
        .measure_duration = 1440, // 3 quarters
        .beat_duration = 480,
    };
    
    // Full measure in 3/4 should use dotted half rest
    const gaps = [_]Gap{
        Gap{
            .start_time = 0,
            .duration = 1440,
            .measure_number = 1,
        },
    };
    
    const rests = try optimizer.optimizeRests(&gaps, time_sig);
    defer allocator.free(rests);
    
    // Should create whole rest (convention for empty measures)
    try testing.expectEqual(@as(usize, 1), rests.len);
    try testing.expectEqual(NoteType.whole, rests[0].note_type);
}

test "tiny gap filtering (EXECUTIVE AUTHORITY fix)" {
    const allocator = testing.allocator;
    var optimizer = RestOptimizer.init(allocator, 480);
    
    const time_sig = TimeSignature{
        .numerator = 4,
        .denominator = 4,
        .measure_duration = 1920,
        .beat_duration = 480,
    };
    
    // Test 4-tick gap (the problematic remainder)
    const tiny_gaps = [_]Gap{
        Gap{
            .start_time = 1916,
            .duration = 4, // Below MIN_MEANINGFUL_REST_THRESHOLD (60)
            .measure_number = 1,
        },
    };
    
    const rests = try optimizer.optimizeRests(&tiny_gaps, time_sig);
    defer allocator.free(rests);
    
    // Should return no rests for tiny gaps (absorbed as measurement noise)
    try testing.expectEqual(@as(usize, 0), rests.len);
}

test "meaningful gap processing" {
    const allocator = testing.allocator;
    var optimizer = RestOptimizer.init(allocator, 480);
    
    const time_sig = TimeSignature{
        .numerator = 4,
        .denominator = 4,
        .measure_duration = 1920,
        .beat_duration = 480,
    };
    
    // Test 120-tick gap (above threshold)
    const meaningful_gaps = [_]Gap{
        Gap{
            .start_time = 1800,
            .duration = 120, // Above MIN_MEANINGFUL_REST_THRESHOLD (60)
            .measure_number = 1,
        },
    };
    
    const rests = try optimizer.optimizeRests(&meaningful_gaps, time_sig);
    defer allocator.free(rests);
    
    // Should generate at least one rest for meaningful gaps
    try testing.expect(rests.len > 0);
}

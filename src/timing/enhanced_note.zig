//! Enhanced Timed Note Structure for Educational Feature Integration
//! 
//! Implements TASK-INT-002 per EDUCATIONAL_FEATURE_INTEGRATION_TASK_LIST.md
//!
//! This module provides the EnhancedTimedNote structure that extends the basic
//! TimedNote with educational metadata for:
//! - Tuplet detection information
//! - Beam grouping state
//! - Rest optimization data
//! - Dynamic markings
//!
//! Performance targets:
//! - Zero memory overhead when educational features are not used
//! - Efficient conversion between TimedNote and EnhancedTimedNote
//! - Arena-based memory management for educational metadata

const std = @import("std");

// Import directly from measure_detector to avoid circular import
const measure_detector = @import("measure_detector.zig");
const arena = @import("../memory/arena.zig");

// Import educational feature structures
const tuplet_detector = @import("tuplet_detector.zig");
const beam_grouper = @import("beam_grouper.zig");
const rest_optimizer = @import("rest_optimizer.zig");
const dynamics_mapper = @import("../interpreter/dynamics_mapper.zig");
const stem_direction = @import("../mxl/stem_direction.zig");

/// Error types for enhanced note operations
pub const EnhancedNoteError = error{
    AllocationFailure,
    InvalidConversion,
    NullArena,
    IncompatibleMetadata,
};

/// Tuplet information for a note
/// Self-contained to avoid dangling pointer issues
pub const TupletInfo = struct {
    /// Tuplet type (stored directly to avoid pointer issues)
    tuplet_type: tuplet_detector.TupletType = .triplet,
    /// Start tick of the tuplet
    start_tick: u32 = 0,
    /// End tick of the tuplet  
    end_tick: u32 = 0,
    /// Beat unit for display ("eighth", "quarter", etc.)
    beat_unit: []const u8 = "quarter",
    /// Position within the tuplet (0-based index)
    position_in_tuplet: u8 = 0,
    /// Confidence score for tuplet detection (0.0 to 1.0)
    confidence: f64 = 0.0,
    /// Whether this note starts the tuplet
    starts_tuplet: bool = false,
    /// Whether this note ends the tuplet
    ends_tuplet: bool = false,
    
    /// Check if this tuplet info is valid (has been set)
    pub fn isValid(self: *const TupletInfo) bool {
        return self.confidence > 0.0 and self.end_tick > self.start_tick;
    }
};

/// Beam grouping information for a note
/// Optional pointer to avoid memory overhead when not used
pub const BeamingInfo = struct {
    /// Beam state information for this note
    beam_state: beam_grouper.BeamState = .none,
    /// Beam level (1 for eighth notes, 2 for 16ths, etc.)
    beam_level: u8 = 0,
    /// Whether this note can be beamed (eighth note or shorter)
    can_beam: bool = false,
    /// Beat position within measure (0.0 = start of measure)
    beat_position: f64 = 0.0,
    /// Group identifier for beam coordination
    beam_group_id: ?u32 = null,
};

/// Rest optimization information
/// Only applicable for rest notes (velocity = 0)
pub const RestInfo = struct {
    /// Optimized rest data (if this represents a rest)
    rest_data: ?rest_optimizer.Rest = null,
    /// Whether this rest was created by optimization
    is_optimized_rest: bool = false,
    /// Original duration before optimization
    original_duration: u32 = 0,
    /// Alignment score for this rest placement
    alignment_score: f32 = 0.0,
};

/// Dynamic marking information for a note
/// Optional pointer to avoid memory overhead when not used
pub const DynamicsInfo = struct {
    /// Dynamic marking for this note (if any)
    marking: ?dynamics_mapper.DynamicMarking = null,
    /// Whether this note triggers a new dynamic marking
    triggers_new_dynamic: bool = false,
    /// Interpolated dynamic level based on velocity
    interpolated_dynamic: ?dynamics_mapper.Dynamic = null,
    /// Previous dynamic for context
    previous_dynamic: ?dynamics_mapper.Dynamic = null,
};

/// Stem direction information for a note
/// Coordinates with beam grouping for consistent visual appearance
pub const StemInfo = struct {
    /// Calculated stem direction for this note
    direction: stem_direction.StemDirection = .none,
    /// Whether this direction was influenced by beam grouping
    beam_influenced: bool = false,
    /// Voice number that influenced stem direction (1-4 for piano music)
    voice: u8 = 1,
    /// Whether this note is part of a beam group
    in_beam_group: bool = false,
    /// Beam group identifier for coordination
    beam_group_id: ?u32 = null,
    /// Staff position that influenced the direction calculation
    staff_position: ?stem_direction.StaffPosition = null,
};

/// Enhanced TimedNote structure with educational metadata
/// 
/// This structure extends the basic TimedNote with optional educational
/// feature metadata. Memory overhead is zero when educational features
/// are not used (all optional pointers are null).
pub const EnhancedTimedNote = struct {
    /// Base timed note data (required)
    base_note: measure_detector.TimedNote,
    
    /// Optional tuplet information
    tuplet_info: ?*TupletInfo = null,
    
    /// Optional beam grouping information
    beaming_info: ?*BeamingInfo = null,
    
    /// Optional rest optimization information
    rest_info: ?*RestInfo = null,
    
    /// Optional dynamics information
    dynamics_info: ?*DynamicsInfo = null,
    
    /// Optional stem direction information
    stem_info: ?*StemInfo = null,
    
    /// Educational processing metadata
    /// Tracks which educational features have processed this note
    processing_flags: ProcessingFlags = .{},
    
    /// Educational arena reference for memory management
    arena: ?*arena.EducationalArena = null,
    
    /// Processing flags to track which educational features have been applied
    pub const ProcessingFlags = struct {
        tuplet_processed: bool = false,
        beaming_processed: bool = false,
        rest_processed: bool = false,
        dynamics_processed: bool = false,
        stem_processed: bool = false,
        
        /// Check if all educational features have been processed
        pub fn isFullyProcessed(self: ProcessingFlags) bool {
            return self.tuplet_processed and 
                   self.beaming_processed and 
                   self.rest_processed and 
                   self.dynamics_processed and
                   self.stem_processed;
        }
        
        /// Reset all processing flags
        pub fn reset(self: *ProcessingFlags) void {
            self.* = .{};
        }
    };
    
    /// Initialize EnhancedTimedNote from TimedNote
    /// 
    /// Args:
    ///   base_note: The basic TimedNote to enhance
    ///   educational_arena: Arena for educational metadata allocation (optional)
    pub fn init(base_note: measure_detector.TimedNote, educational_arena: ?*arena.EducationalArena) EnhancedTimedNote {
        return .{
            .base_note = base_note,
            .arena = educational_arena,
        };
    }
    
    /// Initialize EnhancedTimedNote with all educational metadata
    /// 
    /// This is a convenience constructor for cases where all metadata is known
    pub fn initWithMetadata(
        base_note: measure_detector.TimedNote,
        educational_arena: *arena.EducationalArena,
        tuplet_info: ?*TupletInfo,
        beaming_info: ?*BeamingInfo,
        rest_info: ?*RestInfo,
        dynamics_info: ?*DynamicsInfo,
        stem_info: ?*StemInfo,
    ) EnhancedTimedNote {
        return .{
            .base_note = base_note,
            .tuplet_info = tuplet_info,
            .beaming_info = beaming_info,
            .rest_info = rest_info,
            .dynamics_info = dynamics_info,
            .stem_info = stem_info,
            .arena = educational_arena,
        };
    }
    
    /// Get the base TimedNote (for compatibility with existing code)
    pub fn getBaseNote(self: *const EnhancedTimedNote) measure_detector.TimedNote {
        return self.base_note;
    }
    
    /// Check if this note has any educational metadata
    pub fn hasEducationalMetadata(self: *const EnhancedTimedNote) bool {
        return self.tuplet_info != null or 
               self.beaming_info != null or 
               self.rest_info != null or 
               self.dynamics_info != null or
               self.stem_info != null;
    }
    
    /// Get memory footprint of educational metadata in bytes
    pub fn getEducationalMemoryFootprint(self: *const EnhancedTimedNote) usize {
        var total: usize = 0;
        
        if (self.tuplet_info != null) total += @sizeOf(TupletInfo);
        if (self.beaming_info != null) total += @sizeOf(BeamingInfo);
        if (self.rest_info != null) total += @sizeOf(RestInfo);
        if (self.dynamics_info != null) total += @sizeOf(DynamicsInfo);
        if (self.stem_info != null) total += @sizeOf(StemInfo);
        
        return total;
    }
    
    /// Set tuplet information for this note
    /// 
    /// Allocates TupletInfo using the educational arena if not already allocated
    pub fn setTupletInfo(self: *EnhancedTimedNote, tuplet_info: TupletInfo) EnhancedNoteError!void {
        if (self.arena == null) return EnhancedNoteError.NullArena;
        
        if (self.tuplet_info == null) {
            self.arena.?.beginPhase(.tuplet_detection);
            defer self.arena.?.endPhase();
            
            const allocated_info = self.arena.?.allocForEducational(TupletInfo, 1) catch {
                return EnhancedNoteError.AllocationFailure;
            };
            self.tuplet_info = &allocated_info[0];
        }
        
        self.tuplet_info.?.* = tuplet_info;
        self.processing_flags.tuplet_processed = true;
    }
    
    /// Set beam grouping information for this note
    pub fn setBeamingInfo(self: *EnhancedTimedNote, beaming_info: BeamingInfo) EnhancedNoteError!void {
        if (self.arena == null) return EnhancedNoteError.NullArena;
        
        if (self.beaming_info == null) {
            self.arena.?.beginPhase(.beam_grouping);
            defer self.arena.?.endPhase();
            
            const allocated_info = self.arena.?.allocForEducational(BeamingInfo, 1) catch {
                return EnhancedNoteError.AllocationFailure;
            };
            self.beaming_info = &allocated_info[0];
        }
        
        self.beaming_info.?.* = beaming_info;
        self.processing_flags.beaming_processed = true;
    }
    
    /// Set rest optimization information for this note
    pub fn setRestInfo(self: *EnhancedTimedNote, rest_info: RestInfo) EnhancedNoteError!void {
        if (self.arena == null) return EnhancedNoteError.NullArena;
        
        if (self.rest_info == null) {
            self.arena.?.beginPhase(.rest_optimization);
            defer self.arena.?.endPhase();
            
            const allocated_info = self.arena.?.allocForEducational(RestInfo, 1) catch {
                return EnhancedNoteError.AllocationFailure;
            };
            self.rest_info = &allocated_info[0];
        }
        
        self.rest_info.?.* = rest_info;
        self.processing_flags.rest_processed = true;
    }
    
    /// Set dynamics information for this note
    pub fn setDynamicsInfo(self: *EnhancedTimedNote, dynamics_info: DynamicsInfo) EnhancedNoteError!void {
        if (self.arena == null) return EnhancedNoteError.NullArena;
        
        if (self.dynamics_info == null) {
            self.arena.?.beginPhase(.dynamics_mapping);
            defer self.arena.?.endPhase();
            
            const allocated_info = self.arena.?.allocForEducational(DynamicsInfo, 1) catch {
                return EnhancedNoteError.AllocationFailure;
            };
            self.dynamics_info = &allocated_info[0];
        }
        
        self.dynamics_info.?.* = dynamics_info;
        self.processing_flags.dynamics_processed = true;
    }
    
    /// Set stem direction information for this note
    /// Uses coordination phase as stem direction is part of feature coordination
    pub fn setStemInfo(self: *EnhancedTimedNote, stem_info: StemInfo) EnhancedNoteError!void {
        if (self.arena == null) return EnhancedNoteError.NullArena;
        
        if (self.stem_info == null) {
            self.arena.?.beginPhase(.coordination);
            defer self.arena.?.endPhase();
            
            const allocated_info = self.arena.?.allocForEducational(StemInfo, 1) catch {
                return EnhancedNoteError.AllocationFailure;
            };
            self.stem_info = &allocated_info[0];
        }
        
        self.stem_info.?.* = stem_info;
        self.processing_flags.stem_processed = true;
    }
    
    /// Clear all educational metadata and reset to base note
    pub fn clearEducationalMetadata(self: *EnhancedTimedNote) void {
        self.tuplet_info = null;
        self.beaming_info = null;
        self.rest_info = null;
        self.dynamics_info = null;
        self.stem_info = null;
        self.processing_flags.reset();
    }
    
    /// Create a copy with only base note data (strips educational metadata)
    pub fn toBaseNote(self: *const EnhancedTimedNote) measure_detector.TimedNote {
        return self.base_note;
    }
    
    /// Validate internal consistency of educational metadata
    pub fn validateConsistency(self: *const EnhancedTimedNote) bool {
        // Validate tuplet info consistency
        if (self.tuplet_info) |tuplet_info| {
            if (tuplet_info.confidence < 0.0 or tuplet_info.confidence > 1.0) {
                return false;
            }
            if (tuplet_info.starts_tuplet and tuplet_info.position_in_tuplet != 0) {
                return false;
            }
        }
        
        // Validate beam info consistency
        if (self.beaming_info) |beam_info| {
            if (beam_info.beam_level > 6) return false; // Max reasonable beam level
            if (beam_info.beam_state != .none and !beam_info.can_beam) {
                return false;
            }
            if (beam_info.beat_position < 0.0) return false;
        }
        
        // Validate rest info consistency
        if (self.rest_info) |rest_info| {
            if (rest_info.is_optimized_rest and rest_info.rest_data == null) {
                return false;
            }
            if (rest_info.alignment_score < 0.0) return false;
        }
        
        // Validate that note is actually a rest if rest_info is present
        if (self.rest_info != null and self.base_note.velocity != 0) {
            return false; // Rest info should only be present for rest notes (velocity=0)
        }
        
        return true;
    }
};

/// Conversion utilities between TimedNote and EnhancedTimedNote
pub const ConversionUtils = struct {
    /// Convert TimedNote to EnhancedTimedNote without educational metadata
    /// 
    /// This provides zero-overhead conversion for the base case
    pub fn fromTimedNote(base_note: measure_detector.TimedNote) EnhancedTimedNote {
        return EnhancedTimedNote.init(base_note, null);
    }
    
    /// Convert TimedNote to EnhancedTimedNote with arena for educational processing
    pub fn fromTimedNoteWithArena(base_note: measure_detector.TimedNote, educational_arena: *arena.EducationalArena) EnhancedTimedNote {
        return EnhancedTimedNote.init(base_note, educational_arena);
    }
    
    /// Convert EnhancedTimedNote back to TimedNote
    /// 
    /// This strips all educational metadata and returns the base note
    pub fn toTimedNote(enhanced_note: *const EnhancedTimedNote) measure_detector.TimedNote {
        return enhanced_note.toBaseNote();
    }
    
    /// Convert array of TimedNote to array of EnhancedTimedNote
    /// 
    /// Allocates new array using the provided arena
    pub fn fromTimedNoteArray(
        base_notes: []const measure_detector.TimedNote,
        educational_arena: *arena.EducationalArena,
    ) EnhancedNoteError![]EnhancedTimedNote {
        educational_arena.beginPhase(.coordination);
        defer educational_arena.endPhase();
        
        const enhanced_notes = educational_arena.allocForEducational(EnhancedTimedNote, base_notes.len) catch {
            return EnhancedNoteError.AllocationFailure;
        };
        
        for (base_notes, 0..) |base_note, i| {
            enhanced_notes[i] = fromTimedNoteWithArena(base_note, educational_arena);
        }
        
        return enhanced_notes;
    }
    
    /// Convert array of EnhancedTimedNote back to array of TimedNote
    /// 
    /// Allocates new array using the provided allocator
    pub fn toTimedNoteArray(
        enhanced_notes: []const EnhancedTimedNote,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error![]measure_detector.TimedNote {
        const base_notes = try allocator.alloc(measure_detector.TimedNote, enhanced_notes.len);
        
        for (enhanced_notes, 0..) |enhanced_note, i| {
            base_notes[i] = enhanced_note.toBaseNote();
        }
        
        return base_notes;
    }
    
    /// Batch conversion with validation
    /// 
    /// Converts and validates consistency of educational metadata
    pub fn convertAndValidate(
        base_notes: []const measure_detector.TimedNote,
        educational_arena: *arena.EducationalArena,
    ) EnhancedNoteError![]EnhancedTimedNote {
        const enhanced_notes = try fromTimedNoteArray(base_notes, educational_arena);
        
        // Validate each converted note
        for (enhanced_notes) |enhanced_note| {
            if (!enhanced_note.validateConsistency()) {
                return EnhancedNoteError.InvalidConversion;
            }
        }
        
        return enhanced_notes;
    }
};

// Tests for EnhancedTimedNote functionality
test "enhanced timed note basic initialization" {
    const base_note = measure_detector.TimedNote{
        .note = 60,  // Middle C
        .channel = 0,
        .velocity = 64,
        .start_tick = 0,
        .duration = 480,
    };
    
    // Test initialization without arena (zero overhead case)
    const enhanced_note = EnhancedTimedNote.init(base_note, null);
    try std.testing.expect(enhanced_note.getBaseNote().note == 60);
    try std.testing.expect(enhanced_note.getBaseNote().velocity == 64);
    try std.testing.expect(!enhanced_note.hasEducationalMetadata());
    try std.testing.expect(enhanced_note.getEducationalMemoryFootprint() == 0);
}

test "enhanced timed note with educational arena" {
    var educational_arena = arena.EducationalArena.init(std.testing.allocator, false, false);
    defer educational_arena.deinit();
    
    const base_note = measure_detector.TimedNote{
        .note = 67,  // G
        .channel = 0,
        .velocity = 80,
        .start_tick = 480,
        .duration = 240,
    };
    
    var enhanced_note = EnhancedTimedNote.init(base_note, &educational_arena);
    
    // Test setting tuplet information
    const tuplet_info = TupletInfo{
        .confidence = 0.95,
        .starts_tuplet = true,
        .position_in_tuplet = 0,
    };
    
    try enhanced_note.setTupletInfo(tuplet_info);
    try std.testing.expect(enhanced_note.hasEducationalMetadata());
    try std.testing.expect(enhanced_note.processing_flags.tuplet_processed);
    try std.testing.expect(enhanced_note.tuplet_info.?.confidence == 0.95);
    try std.testing.expect(enhanced_note.tuplet_info.?.starts_tuplet);
}

test "enhanced timed note beaming information" {
    var educational_arena = arena.EducationalArena.init(std.testing.allocator, false, false);
    defer educational_arena.deinit();
    
    const base_note = measure_detector.TimedNote{
        .note = 64,  // E
        .channel = 0,
        .velocity = 70,
        .start_tick = 0,
        .duration = 120, // Eighth note
    };
    
    var enhanced_note = EnhancedTimedNote.init(base_note, &educational_arena);
    
    const beaming_info = BeamingInfo{
        .beam_state = .begin,
        .beam_level = 1,
        .can_beam = true,
        .beat_position = 0.0,
        .beam_group_id = 1,
    };
    
    try enhanced_note.setBeamingInfo(beaming_info);
    try std.testing.expect(enhanced_note.beaming_info.?.beam_state == .begin);
    try std.testing.expect(enhanced_note.beaming_info.?.beam_level == 1);
    try std.testing.expect(enhanced_note.beaming_info.?.can_beam);
    try std.testing.expect(enhanced_note.processing_flags.beaming_processed);
}

test "enhanced timed note rest information" {
    var educational_arena = arena.EducationalArena.init(std.testing.allocator, false, false);
    defer educational_arena.deinit();
    
    const rest_note = measure_detector.TimedNote{
        .note = 0,   // Rest represented with note 0
        .channel = 0,
        .velocity = 0, // Rest has velocity 0
        .start_tick = 480,
        .duration = 480, // Quarter rest
    };
    
    var enhanced_note = EnhancedTimedNote.init(rest_note, &educational_arena);
    
    const rest_info = RestInfo{
        .is_optimized_rest = true,
        .original_duration = 360,
        .alignment_score = 0.8,
    };
    
    try enhanced_note.setRestInfo(rest_info);
    try std.testing.expect(enhanced_note.rest_info.?.is_optimized_rest);
    try std.testing.expect(enhanced_note.rest_info.?.original_duration == 360);
    try std.testing.expect(enhanced_note.rest_info.?.alignment_score == 0.8);
    try std.testing.expect(enhanced_note.processing_flags.rest_processed);
}

test "enhanced timed note dynamics information" {
    var educational_arena = arena.EducationalArena.init(std.testing.allocator, false, false);
    defer educational_arena.deinit();
    
    const base_note = measure_detector.TimedNote{
        .note = 72,  // C5
        .channel = 0,
        .velocity = 100,
        .start_tick = 0,
        .duration = 480,
    };
    
    var enhanced_note = EnhancedTimedNote.init(base_note, &educational_arena);
    
    const dynamics_info = DynamicsInfo{
        .triggers_new_dynamic = true,
        .interpolated_dynamic = .f,
        .previous_dynamic = .mf,
    };
    
    try enhanced_note.setDynamicsInfo(dynamics_info);
    try std.testing.expect(enhanced_note.dynamics_info.?.triggers_new_dynamic);
    try std.testing.expect(enhanced_note.dynamics_info.?.interpolated_dynamic == .f);
    try std.testing.expect(enhanced_note.dynamics_info.?.previous_dynamic == .mf);
    try std.testing.expect(enhanced_note.processing_flags.dynamics_processed);
}

test "enhanced timed note consistency validation" {
    var educational_arena = arena.EducationalArena.init(std.testing.allocator, false, false);
    defer educational_arena.deinit();
    
    const base_note = measure_detector.TimedNote{
        .note = 60,
        .channel = 0,
        .velocity = 64,
        .start_tick = 0,
        .duration = 480,
    };
    
    var enhanced_note = EnhancedTimedNote.init(base_note, &educational_arena);
    
    // Valid tuplet info
    const valid_tuplet_info = TupletInfo{
        .confidence = 0.8,
        .starts_tuplet = true,
        .position_in_tuplet = 0,
    };
    try enhanced_note.setTupletInfo(valid_tuplet_info);
    try std.testing.expect(enhanced_note.validateConsistency());
    
    // Invalid tuplet info (confidence out of range)
    enhanced_note.tuplet_info.?.confidence = 1.5;
    try std.testing.expect(!enhanced_note.validateConsistency());
}

test "conversion utilities basic functionality" {
    const base_note = measure_detector.TimedNote{
        .note = 65,  // F
        .channel = 1,
        .velocity = 90,
        .start_tick = 240,
        .duration = 360,
    };
    
    // Test conversion without arena
    const enhanced_note = ConversionUtils.fromTimedNote(base_note);
    try std.testing.expect(enhanced_note.getBaseNote().note == 65);
    try std.testing.expect(!enhanced_note.hasEducationalMetadata());
    
    // Test conversion back to TimedNote
    const converted_back = ConversionUtils.toTimedNote(&enhanced_note);
    try std.testing.expect(converted_back.note == base_note.note);
    try std.testing.expect(converted_back.velocity == base_note.velocity);
    try std.testing.expect(converted_back.start_tick == base_note.start_tick);
    try std.testing.expect(converted_back.duration == base_note.duration);
}

test "conversion utilities array operations" {
    var educational_arena = arena.EducationalArena.init(std.testing.allocator, false, false);
    defer educational_arena.deinit();
    
    const base_notes = [_]measure_detector.TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480 },
        .{ .note = 64, .channel = 0, .velocity = 70, .start_tick = 480, .duration = 240 },
        .{ .note = 67, .channel = 0, .velocity = 75, .start_tick = 720, .duration = 240 },
    };
    
    // Convert array to enhanced notes
    const enhanced_notes = try ConversionUtils.fromTimedNoteArray(base_notes[0..], &educational_arena);
    try std.testing.expect(enhanced_notes.len == 3);
    try std.testing.expect(enhanced_notes[0].getBaseNote().note == 60);
    try std.testing.expect(enhanced_notes[1].getBaseNote().note == 64);
    try std.testing.expect(enhanced_notes[2].getBaseNote().note == 67);
    
    // Convert back to base notes array
    const converted_back = try ConversionUtils.toTimedNoteArray(enhanced_notes, std.testing.allocator);
    defer std.testing.allocator.free(converted_back);
    
    try std.testing.expect(converted_back.len == 3);
    try std.testing.expect(converted_back[0].note == 60);
    try std.testing.expect(converted_back[1].note == 64);
    try std.testing.expect(converted_back[2].note == 67);
}

test "enhanced timed note memory footprint tracking" {
    var educational_arena = arena.EducationalArena.init(std.testing.allocator, false, false);
    defer educational_arena.deinit();
    
    const base_note = measure_detector.TimedNote{
        .note = 60,
        .channel = 0,
        .velocity = 64,
        .start_tick = 0,
        .duration = 480,
    };
    
    var enhanced_note = EnhancedTimedNote.init(base_note, &educational_arena);
    
    // Initial footprint should be zero
    try std.testing.expect(enhanced_note.getEducationalMemoryFootprint() == 0);
    
    // Add tuplet info
    const tuplet_info = TupletInfo{};
    try enhanced_note.setTupletInfo(tuplet_info);
    const tuplet_size = @sizeOf(TupletInfo);
    try std.testing.expect(enhanced_note.getEducationalMemoryFootprint() == tuplet_size);
    
    // Add beaming info
    const beaming_info = BeamingInfo{};
    try enhanced_note.setBeamingInfo(beaming_info);
    const expected_footprint = tuplet_size + @sizeOf(BeamingInfo);
    try std.testing.expect(enhanced_note.getEducationalMemoryFootprint() == expected_footprint);
    
    // Clear metadata
    enhanced_note.clearEducationalMetadata();
    try std.testing.expect(enhanced_note.getEducationalMemoryFootprint() == 0);
    try std.testing.expect(!enhanced_note.hasEducationalMetadata());
}

test "enhanced timed note processing flags" {
    var flags = EnhancedTimedNote.ProcessingFlags{};
    
    try std.testing.expect(!flags.isFullyProcessed());
    
    flags.tuplet_processed = true;
    flags.beaming_processed = true;
    flags.rest_processed = true;
    try std.testing.expect(!flags.isFullyProcessed());
    
    flags.dynamics_processed = true;
    try std.testing.expect(!flags.isFullyProcessed());
    
    flags.stem_processed = true;
    try std.testing.expect(flags.isFullyProcessed());
    
    flags.reset();
    try std.testing.expect(!flags.tuplet_processed);
    try std.testing.expect(!flags.isFullyProcessed());
}
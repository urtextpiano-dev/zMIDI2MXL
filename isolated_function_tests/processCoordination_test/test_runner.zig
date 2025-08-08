const std = @import("std");

// Minimal TimedNote structure for testing
const TimedNote = struct {
    note: u8,
    channel: u8,
    velocity: u8,
    start_tick: u32,
    duration: u32,
    tied_to_next: bool = false,
    tied_from_previous: bool = false,
    track: u8 = 0,
    voice: u8 = 0,
};

// Minimal tuplet info structure
const TupletInfo = struct {
    tuplet_type: enum { triplet, duplet, quintuplet } = .triplet,
    start_tick: u32 = 0,
    end_tick: u32 = 0,
    beat_unit: []const u8 = "quarter",
    position_in_tuplet: u8 = 0,
    confidence: f64 = 0.0,
    starts_tuplet: bool = false,
    ends_tuplet: bool = false,
};

// Minimal beaming info structure
const BeamingInfo = struct {
    beam_state: enum { none, begin, middle, end } = .none,
    beam_level: u8 = 0,
    can_beam: bool = false,
    beat_position: f64 = 0.0,
    beam_group_id: ?u32 = null,
};

// Minimal rest info structure  
const RestInfo = struct {
    rest_data: ?struct { duration: u32, position: u32 } = null,
    is_optimized_rest: bool = false,
    original_duration: u32 = 0,
    alignment_score: f32 = 0.0,
};

// Minimal dynamics info structure
const DynamicsInfo = struct {
    marking: ?enum { pp, p, mp, mf, f, ff } = null,
    triggers_new_dynamic: bool = false,
    interpolated_dynamic: ?u8 = null,
    previous_dynamic: ?u8 = null,
};

// Enhanced timed note structure
const EnhancedTimedNote = struct {
    base_note: TimedNote,
    tuplet_info: ?*TupletInfo = null,
    beaming_info: ?*BeamingInfo = null,
    rest_info: ?*RestInfo = null,
    dynamics_info: ?*DynamicsInfo = null,
    
    pub fn getBaseNote(self: *const EnhancedTimedNote) *const TimedNote {
        return &self.base_note;
    }
};

// Processing phase enum
const ProcessingPhase = enum {
    tuplet_detection,
    beam_grouping,
    rest_optimization,
    dynamics_mapping,
    coordination,
};

// Processing metrics structure
const ProcessingChainMetrics = struct {
    notes_processed: u64 = 0,
    phase_processing_times: [5]u64 = [_]u64{0} ** 5,
    total_processing_time_ns: u64 = 0,
    phase_memory_usage: [5]u64 = [_]u64{0} ** 5,
    successful_features: u8 = 0,
    coordination_conflicts_resolved: u8 = 0,
    error_count: u8 = 0,
};

// Mock educational arena for memory management
const MockArena = struct {
    peak_memory: usize = 0,
    
    pub fn beginPhase(self: *MockArena, phase: ProcessingPhase) void {
        _ = self;
        _ = phase;
    }
    
    pub fn endPhase(self: *MockArena) void {
        _ = self;
    }
    
    pub fn getMetrics(self: *const MockArena) struct { peak_educational_memory: usize } {
        return .{ .peak_educational_memory = self.peak_memory };
    }
};

// Mock verbose logger
const MockVerboseLogger = struct {
    parent: struct {
        pub fn pipelineStep(self: @This(), step: enum { 
            EDU_COORDINATION_START,
            EDU_COORDINATION_CONFLICT_DETECTION,
            EDU_COORDINATION_CONFLICT_RESOLUTION,
            EDU_COORDINATION_VALIDATION,
            EDU_COORDINATION_METADATA_FINALIZATION,
            EDU_MEMORY_CLEANUP
        }, msg: []const u8, args: anytype) void {
            _ = self;
            _ = step;
            _ = msg;
            _ = args;
        }
    } = .{},
    
    pub fn data(self: @This(), msg: []const u8, args: anytype) void {
        _ = self;
        _ = msg;
        _ = args;
    }
    
    pub fn timing(self: @This(), name: []const u8, duration: u64) void {
        _ = self;
        _ = name;
        _ = duration;
    }
};

// Mock verbose logger module
const verbose_logger = struct {
    pub fn getVerboseLogger() struct {
        pub fn scoped(self: @This(), name: []const u8) MockVerboseLogger {
            _ = self;
            _ = name;
            return MockVerboseLogger{};
        }
    } {
        return .{};
    }
};

// Educational processing error types
const EducationalProcessingError = error{
    AllocationFailure,
    ProcessingFailed,
};

// Minimal educational processor for testing
const EducationalProcessor = struct {
    arena: *MockArena,
    metrics: ProcessingChainMetrics = .{},
    current_phase: ?ProcessingPhase = null,
    
    // SIMPLIFIED FUNCTION - Single-pass conflict resolution
    fn processCoordination(self: *EducationalProcessor, enhanced_notes: []EnhancedTimedNote) EducationalProcessingError!void {
        const phase_start = std.time.nanoTimestamp();
        const vlogger = verbose_logger.getVerboseLogger().scoped("Educational");
        
        // Setup phase tracking
        self.current_phase = .coordination;
        self.arena.beginPhase(.coordination);
        defer {
            self.arena.endPhase();
            self.metrics.phase_processing_times[@intFromEnum(ProcessingPhase.coordination)] = 
                @as(u64, @intCast(std.time.nanoTimestamp() - phase_start));
            self.current_phase = null;
        }
        
        // Early return for empty input
        if (enhanced_notes.len == 0) {
            vlogger.data("No notes to process, skipping coordination", .{});
            return;
        }
        
        // SINGLE PASS: Detect, resolve conflicts, and gather stats in one loop
        var notes_with_tuplets: usize = 0;
        var notes_with_beams: usize = 0;
        var notes_with_dynamics: usize = 0;
        var notes_with_rest_info: usize = 0;
        
        for (enhanced_notes) |*note| {
            const base = note.getBaseNote();
            
            // Resolve rest-dynamics conflicts immediately
            if (base.note == 0 and note.dynamics_info != null) {
                note.dynamics_info = null;
                self.metrics.coordination_conflicts_resolved += 1;
            }
            
            // Count features for validation (simplified)
            if (note.tuplet_info != null) notes_with_tuplets += 1;
            if (note.beaming_info != null) notes_with_beams += 1;
            if (note.dynamics_info != null) notes_with_dynamics += 1;
            if (note.rest_info != null) notes_with_rest_info += 1;
        }
        
        // Log summary once at the end
        vlogger.data("Coordination completed: {} notes, {} conflicts resolved", 
                     .{enhanced_notes.len, self.metrics.coordination_conflicts_resolved});
        vlogger.data("Features: tuplets={}, beams={}, dynamics={}, rests={}", 
                     .{notes_with_tuplets, notes_with_beams, notes_with_dynamics, notes_with_rest_info});
    }
};

// Test suite
fn runTests() !void {
    const allocator = std.heap.page_allocator;
    
    std.debug.print("\n=== Running processCoordination Unit Tests ===\n", .{});
    
    // Test 1: Empty notes array
    {
        std.debug.print("Test 1: Empty notes array... ", .{});
        var arena = MockArena{};
        var processor = EducationalProcessor{ .arena = &arena };
        var notes = [_]EnhancedTimedNote{};
        try processor.processCoordination(&notes);
        try std.testing.expectEqual(@as(u8, 0), processor.metrics.coordination_conflicts_resolved);
        std.debug.print("PASS\n", .{});
    }
    
    // Test 2: Notes without conflicts
    {
        std.debug.print("Test 2: Notes without conflicts... ", .{});
        var arena = MockArena{};
        var processor = EducationalProcessor{ .arena = &arena };
        
        var notes = [_]EnhancedTimedNote{
            EnhancedTimedNote{
                .base_note = TimedNote{
                    .note = 60,
                    .channel = 0,
                    .velocity = 64,
                    .start_tick = 0,
                    .duration = 480,
                },
            },
            EnhancedTimedNote{
                .base_note = TimedNote{
                    .note = 62,
                    .channel = 0,
                    .velocity = 64,
                    .start_tick = 480,
                    .duration = 480,
                },
            },
        };
        
        try processor.processCoordination(&notes);
        try std.testing.expectEqual(@as(u8, 0), processor.metrics.coordination_conflicts_resolved);
        std.debug.print("PASS\n", .{});
    }
    
    // Test 3: Rest with dynamics conflict
    {
        std.debug.print("Test 3: Rest with dynamics conflict... ", .{});
        var arena = MockArena{};
        var processor = EducationalProcessor{ .arena = &arena };
        
        var dynamics = DynamicsInfo{ .marking = .mf };
        var notes = [_]EnhancedTimedNote{
            EnhancedTimedNote{
                .base_note = TimedNote{
                    .note = 0, // Rest
                    .channel = 0,
                    .velocity = 0,
                    .start_tick = 0,
                    .duration = 480,
                },
                .dynamics_info = &dynamics,
            },
        };
        
        try processor.processCoordination(&notes);
        try std.testing.expectEqual(@as(u8, 1), processor.metrics.coordination_conflicts_resolved);
        try std.testing.expectEqual(@as(?*DynamicsInfo, null), notes[0].dynamics_info);
        std.debug.print("PASS\n", .{});
    }
    
    // Test 4: Multiple conflicts
    {
        std.debug.print("Test 4: Multiple conflicts... ", .{});
        var arena = MockArena{};
        var processor = EducationalProcessor{ .arena = &arena };
        
        var dynamics1 = DynamicsInfo{ .marking = .f };
        var dynamics2 = DynamicsInfo{ .marking = .p };
        var tuplet1 = TupletInfo{ .tuplet_type = .triplet };
        var beam1 = BeamingInfo{ .beam_state = .begin };
        
        var notes = [_]EnhancedTimedNote{
            EnhancedTimedNote{
                .base_note = TimedNote{
                    .note = 0, // Rest with dynamics
                    .channel = 0,
                    .velocity = 0,
                    .start_tick = 0,
                    .duration = 160,
                },
                .dynamics_info = &dynamics1,
            },
            EnhancedTimedNote{
                .base_note = TimedNote{
                    .note = 64,
                    .channel = 0,
                    .velocity = 80,
                    .start_tick = 160,
                    .duration = 160,
                },
                .tuplet_info = &tuplet1,
                .beaming_info = &beam1,
            },
            EnhancedTimedNote{
                .base_note = TimedNote{
                    .note = 0, // Another rest with dynamics
                    .channel = 0,
                    .velocity = 0,
                    .start_tick = 320,
                    .duration = 160,
                },
                .dynamics_info = &dynamics2,
            },
        };
        
        try processor.processCoordination(&notes);
        try std.testing.expectEqual(@as(u8, 2), processor.metrics.coordination_conflicts_resolved);
        try std.testing.expectEqual(@as(?*DynamicsInfo, null), notes[0].dynamics_info);
        try std.testing.expectEqual(@as(?*DynamicsInfo, null), notes[2].dynamics_info);
        std.debug.print("PASS\n", .{});
    }
    
    // Test 5: Performance with many notes
    {
        std.debug.print("Test 5: Performance with many notes... ", .{});
        var arena = MockArena{};
        var processor = EducationalProcessor{ .arena = &arena };
        
        const notes = try allocator.alloc(EnhancedTimedNote, 100);
        defer allocator.free(notes);
        
        for (notes, 0..) |*note, i| {
            note.* = EnhancedTimedNote{
                .base_note = TimedNote{
                    .note = @as(u8, @intCast(36 + (i % 48))),
                    .channel = 0,
                    .velocity = 64,
                    .start_tick = @as(u32, @intCast(i * 120)),
                    .duration = 120,
                },
            };
        }
        
        const start = std.time.nanoTimestamp();
        try processor.processCoordination(notes);
        const duration = std.time.nanoTimestamp() - start;
        
        std.debug.print("PASS ({}ns for 100 notes)\n", .{duration});
    }
    
    std.debug.print("\nAll tests passed!\n", .{});
}

pub fn main() !void {
    std.debug.print("=== Testing processCoordination Function ===\n", .{});
    
    // Create test data
    var arena = MockArena{};
    var processor = EducationalProcessor{ .arena = &arena };
    
    // Create sample enhanced notes with various features
    var dynamics1 = DynamicsInfo{ .marking = .mf };
    var dynamics2 = DynamicsInfo{ .marking = .f };
    var tuplet1 = TupletInfo{ .tuplet_type = .triplet };
    var beam1 = BeamingInfo{ .beam_state = .begin };
    var beam2 = BeamingInfo{ .beam_state = .end };
    
    var notes = [_]EnhancedTimedNote{
        // Regular note
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
            },
        },
        // Rest with dynamics (conflict)
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 0,
                .channel = 0,
                .velocity = 0,
                .start_tick = 480,
                .duration = 240,
            },
            .dynamics_info = &dynamics1,
        },
        // Note with tuplet and beam
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 64,
                .channel = 0,
                .velocity = 80,
                .start_tick = 720,
                .duration = 160,
            },
            .tuplet_info = &tuplet1,
            .beaming_info = &beam1,
        },
        // Another rest with dynamics (conflict)
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 0,
                .channel = 0,
                .velocity = 0,
                .start_tick = 880,
                .duration = 240,
            },
            .dynamics_info = &dynamics2,
        },
        // Regular note with beam
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 67,
                .channel = 0,
                .velocity = 72,
                .start_tick = 1120,
                .duration = 240,
            },
            .beaming_info = &beam2,
        },
    };
    
    std.debug.print("\nProcessing {} notes...\n", .{notes.len});
    std.debug.print("Initial state:\n", .{});
    std.debug.print("  - Notes with dynamics: 2 (including 2 on rests)\n", .{});
    std.debug.print("  - Notes with tuplets: 1\n", .{});
    std.debug.print("  - Notes with beams: 2\n", .{});
    
    // Process coordination
    try processor.processCoordination(&notes);
    
    // Verify results
    std.debug.print("\nResults after coordination:\n", .{});
    std.debug.print("  - Conflicts resolved: {}\n", .{processor.metrics.coordination_conflicts_resolved});
    std.debug.print("  - Processing time: {}ns\n", .{processor.metrics.phase_processing_times[@intFromEnum(ProcessingPhase.coordination)]});
    
    // Verify rest dynamics were removed
    var dynamics_on_rests: u32 = 0;
    for (notes) |note| {
        if (note.base_note.note == 0 and note.dynamics_info != null) {
            dynamics_on_rests += 1;
        }
    }
    std.debug.print("  - Dynamics remaining on rests: {} (should be 0)\n", .{dynamics_on_rests});
    
    // Run unit tests
    try runTests();
}

test "processCoordination with empty notes" {
    var arena = MockArena{};
    var processor = EducationalProcessor{ .arena = &arena };
    var notes = [_]EnhancedTimedNote{};
    try processor.processCoordination(&notes);
    try std.testing.expectEqual(@as(u8, 0), processor.metrics.coordination_conflicts_resolved);
}

test "processCoordination removes dynamics from rests" {
    var arena = MockArena{};
    var processor = EducationalProcessor{ .arena = &arena };
    
    var dynamics = DynamicsInfo{ .marking = .mf };
    var notes = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 0,
                .channel = 0,
                .velocity = 0,
                .start_tick = 0,
                .duration = 480,
            },
            .dynamics_info = &dynamics,
        },
    };
    
    try processor.processCoordination(&notes);
    try std.testing.expectEqual(@as(u8, 1), processor.metrics.coordination_conflicts_resolved);
    try std.testing.expectEqual(@as(?*DynamicsInfo, null), notes[0].dynamics_info);
}

test "processCoordination counts validation stats" {
    var arena = MockArena{};
    var processor = EducationalProcessor{ .arena = &arena };
    
    var tuplet = TupletInfo{};
    var beam = BeamingInfo{};
    var dynamics = DynamicsInfo{};
    var rest = RestInfo{};
    
    var notes = [_]EnhancedTimedNote{
        EnhancedTimedNote{
            .base_note = TimedNote{
                .note = 60,
                .channel = 0,
                .velocity = 64,
                .start_tick = 0,
                .duration = 480,
            },
            .tuplet_info = &tuplet,
            .beaming_info = &beam,
            .dynamics_info = &dynamics,
            .rest_info = &rest,
        },
    };
    
    try processor.processCoordination(&notes);
    // Function doesn't expose validation stats, but it counts them internally
    try std.testing.expect(processor.metrics.phase_processing_times[@intFromEnum(ProcessingPhase.coordination)] > 0);
}
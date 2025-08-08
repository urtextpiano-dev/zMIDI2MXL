const std = @import("std");

// =============================================================================
// MINIMAL MOCKS AND DEPENDENCIES
// =============================================================================

// Mock arena allocator
const MockArena = struct {
    allocator: std.mem.Allocator,
    allocated_count: usize = 0,
    phase_active: bool = false,
    
    pub fn init(allocator: std.mem.Allocator) MockArena {
        return .{ .allocator = allocator };
    }
    
    pub fn beginPhase(self: *MockArena, phase: ProcessingPhase) void {
        _ = phase;
        self.phase_active = true;
    }
    
    pub fn endPhase(self: *MockArena) void {
        self.phase_active = false;
    }
    
    pub fn allocForEducational(self: *MockArena, comptime T: type, count: usize) ![]T {
        self.allocated_count += count;
        return self.allocator.alloc(T, count);
    }
    
    pub fn getMetrics(self: *MockArena) struct { peak_educational_memory: usize } {
        return .{ .peak_educational_memory = self.allocated_count * 64 };
    }
};

// Mock verbose logger
const MockVerboseLogger = struct {
    parent: struct {
        pub fn pipelineStep(_: anytype, _: anytype, msg: []const u8, args: anytype) void {
            _ = msg;
            _ = args;
        }
        pub fn pipelineStepWithTiming(_: anytype, _: u64, msg: []const u8, args: anytype) void {
            _ = msg;
            _ = args;
        }
    } = .{},
    
    pub fn scoped(self: *const MockVerboseLogger, name: []const u8) MockVerboseLogger {
        _ = self;
        _ = name;
        return .{};
    }
    
    pub fn data(self: *const MockVerboseLogger, msg: []const u8, args: anytype) void {
        _ = self;
        _ = msg;
        _ = args;
    }
    
    pub fn timing(self: *const MockVerboseLogger, name: []const u8, duration: u64) void {
        _ = self;
        _ = name;
        _ = duration;
    }
};

var global_verbose_logger = MockVerboseLogger{};

const verbose_logger = struct {
    pub fn getVerboseLogger() *MockVerboseLogger {
        return &global_verbose_logger;
    }
};

// Minimal TimedNote structure
const TimedNote = struct {
    start_tick: u32,
    duration: u32,
    note: u8,  // 0 = rest, >0 = note
    velocity: u8,
    channel: u8 = 0,
};

// Note type enum for rests
const NoteType = enum {
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
};

// Rest structure
const Rest = struct {
    start_time: u32,
    duration: u32,
    note_type: NoteType,
    dots: u8,
    alignment_score: f32,
    measure_number: u32,
};

// Rest info structure
const RestInfo = struct {
    rest_data: Rest,
    is_optimized_rest: bool,
    original_duration: u32,
};

// Processing flags
const ProcessingFlags = struct {
    tuplet_processed: bool = false,
    beaming_processed: bool = false,
    rest_processed: bool = false,
    dynamics_processed: bool = false,
    stem_processed: bool = false,
};

// Enhanced timed note
const EnhancedTimedNote = struct {
    base_note: TimedNote,
    rest_info: ?*RestInfo = null,
    beaming_info: ?*struct{} = null,  // Simplified mock
    processing_flags: ProcessingFlags = .{},
    
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

// Educational processing error types
const EducationalProcessingError = error{
    AllocationFailure,
    InvalidConfiguration,
    ProcessingChainFailure,
};

// Configuration structures
const EducationalProcessingConfig = struct {
    performance: PerformanceConfig = .{},
    quality: QualityConfig = .{},
    
    const PerformanceConfig = struct {
        max_iterations_per_loop: usize = 10000,
    };
    
    const QualityConfig = struct {
        enable_beam_tuplet_coordination: bool = true,
    };
};

// Metrics structure
const ProcessingChainMetrics = struct {
    phase_processing_times: [5]u64 = [_]u64{0} ** 5,
};

// Pipeline step enum (mock)
const PipelineStep = enum {
    EDU_REST_OPTIMIZATION_START,
    EDU_MEMORY_CLEANUP,
    EDU_REST_ANALYSIS,
    EDU_REST_CONSOLIDATION,
    EDU_REST_BEAM_COORDINATION,
    EDU_REST_METADATA_ASSIGNMENT,
};

// Educational processor struct
const EducationalProcessor = struct {
    arena: *MockArena,
    config: EducationalProcessingConfig,
    metrics: ProcessingChainMetrics = .{},
    current_phase: ?ProcessingPhase = null,
    
    // =============================================================================
    // ORIGINAL FUNCTION TO TEST
    // =============================================================================
    fn processRestOptimization(self: *EducationalProcessor, enhanced_notes: []EnhancedTimedNote) EducationalProcessingError!void {
        const phase_start = std.time.nanoTimestamp();
        const vlogger = verbose_logger.getVerboseLogger().scoped("Educational");
        
        vlogger.parent.pipelineStep(.EDU_REST_OPTIMIZATION_START, "Starting rest optimization phase", .{});
        vlogger.data("Input notes: {}, Memory before: {}B", .{enhanced_notes.len, self.arena.getMetrics().peak_educational_memory});
        
        self.current_phase = .rest_optimization;
        self.arena.beginPhase(.rest_optimization);
        defer {
            self.arena.endPhase();
            const phase_end = std.time.nanoTimestamp();
            self.metrics.phase_processing_times[@intFromEnum(ProcessingPhase.rest_optimization)] = @as(u64, @intCast(phase_end - phase_start));
            self.current_phase = null;
            
            const cleanup_start = std.time.nanoTimestamp();
            vlogger.parent.pipelineStep(.EDU_MEMORY_CLEANUP, "Cleaning up rest optimization phase memory", .{});
            const cleanup_duration = std.time.nanoTimestamp() - cleanup_start;
            vlogger.timing("rest_cleanup", @as(u64, @intCast(cleanup_duration)));
            vlogger.data("Memory after cleanup: {}B", .{self.arena.getMetrics().peak_educational_memory});
        }
        
        if (enhanced_notes.len == 0) {
            vlogger.data("No notes to process, skipping rest optimization", .{});
            return;
        }
        
        // Single-pass consolidation with integrated analysis
        const consolidation_start = std.time.nanoTimestamp();
        vlogger.parent.pipelineStep(.EDU_REST_CONSOLIDATION, "Processing and consolidating rest sequences", .{});
        
        var i: usize = 0;
        var rest_count: usize = 0;
        var consolidations_made: usize = 0;
        var optimized_rests: usize = 0;
        var coordination_issues: usize = 0;
        const max_iterations = self.config.performance.max_iterations_per_loop;
        
        while (i < enhanced_notes.len) : (i += 1) {
            // Safety check integrated into loop condition
            if (i >= max_iterations) {
                std.debug.print("SAFETY: Iteration limit reached in rest optimization\n", .{});
                break;
            }
            
            const note = &enhanced_notes[i];
            const base = note.getBaseNote();
            
            // Process non-rests
            if (base.note != 0) {
                note.processing_flags.rest_processed = true;
                continue;
            }
            
            // Count rest (integrated analysis)
            rest_count += 1;
            
            // Find consecutive rests to consolidate
            var j = i + 1;
            var total_duration = base.duration;
            var last_end_tick = base.start_tick + base.duration;
            
            while (j < enhanced_notes.len and j - i < 1000) : (j += 1) {
                const next_note = enhanced_notes[j].getBaseNote();
                
                // Check consolidation conditions
                if (next_note.note != 0 or 
                    next_note.start_tick > last_end_tick + 10) break;
                
                // Beat boundary check
                const beat_boundary = ((next_note.start_tick / 480) * 480);
                if (beat_boundary > base.start_tick and beat_boundary < next_note.start_tick) {
                    if (total_duration < 480 and total_duration + next_note.duration > 480) break;
                }
                
                total_duration += next_note.duration;
                last_end_tick = next_note.start_tick + next_note.duration;
            }
            
            // Apply consolidation if multiple rests found
            if (j > i + 1) {
                consolidations_made += 1;
                const rest_info = self.arena.allocForEducational(RestInfo, 1) catch {
                    // Mark as processed even if allocation fails
                    for (i..j) |k| {
                        enhanced_notes[k].processing_flags.rest_processed = true;
                    }
                    i = j - 1; // -1 because loop will increment
                    continue;
                };
                
                rest_info[0] = .{
                    .rest_data = .{
                        .start_time = base.start_tick,
                        .duration = total_duration,
                        .note_type = .whole,
                        .dots = 0,
                        .alignment_score = 1.0,
                        .measure_number = 0,
                    },
                    .is_optimized_rest = true,
                    .original_duration = base.duration,
                };
                note.rest_info = &rest_info[0];
                optimized_rests += 1;
            }
            
            // Mark all processed and check coordination
            for (i..j) |k| {
                enhanced_notes[k].processing_flags.rest_processed = true;
                
                // Integrated beam coordination check
                if (self.config.quality.enable_beam_tuplet_coordination) {
                    const n = enhanced_notes[k];
                    if (n.getBaseNote().note == 0 and n.rest_info != null and n.beaming_info != null) {
                        coordination_issues += 1;
                    }
                }
            }
            
            i = j - 1; // -1 because loop will increment
        }
        
        const consolidation_duration = std.time.nanoTimestamp() - consolidation_start;
        vlogger.timing("rest_consolidation", @as(u64, @intCast(consolidation_duration)));
        vlogger.data("Rest processing completed: {} rests, {} consolidated, {} optimized", .{rest_count, consolidations_made, optimized_rests});
        
        if (coordination_issues > 0) {
            vlogger.data("Beam coordination: {} potential issues detected", .{coordination_issues});
        }
        
        const total_phase_duration = std.time.nanoTimestamp() - phase_start;
        vlogger.data("Rest optimization phase completed: {}ns total", .{total_phase_duration});
        
        if (rest_count > 0) {
            const ns_per_rest = @divTrunc(@as(u64, @intCast(total_phase_duration)), rest_count);
            vlogger.data("Performance: {}ns per rest note processed", .{ns_per_rest});
        }
    }
};

// =============================================================================
// TEST HARNESS
// =============================================================================

fn createTestNotes(allocator: std.mem.Allocator, scenario: []const u8) ![]EnhancedTimedNote {
    var notes = std.ArrayList(EnhancedTimedNote).init(allocator);
    
    if (std.mem.eql(u8, scenario, "empty")) {
        // Empty array
    } else if (std.mem.eql(u8, scenario, "no_rests")) {
        // All regular notes, no rests
        try notes.append(.{ .base_note = .{ .start_tick = 0, .duration = 480, .note = 60, .velocity = 64 } });
        try notes.append(.{ .base_note = .{ .start_tick = 480, .duration = 480, .note = 62, .velocity = 64 } });
        try notes.append(.{ .base_note = .{ .start_tick = 960, .duration = 480, .note = 64, .velocity = 64 } });
    } else if (std.mem.eql(u8, scenario, "single_rest")) {
        // Mix of notes and a single rest
        try notes.append(.{ .base_note = .{ .start_tick = 0, .duration = 480, .note = 60, .velocity = 64 } });
        try notes.append(.{ .base_note = .{ .start_tick = 480, .duration = 480, .note = 0, .velocity = 0 } });
        try notes.append(.{ .base_note = .{ .start_tick = 960, .duration = 480, .note = 64, .velocity = 64 } });
    } else if (std.mem.eql(u8, scenario, "consecutive_rests")) {
        // Consecutive rests that should be consolidated
        try notes.append(.{ .base_note = .{ .start_tick = 0, .duration = 240, .note = 0, .velocity = 0 } });
        try notes.append(.{ .base_note = .{ .start_tick = 240, .duration = 240, .note = 0, .velocity = 0 } });
        try notes.append(.{ .base_note = .{ .start_tick = 480, .duration = 240, .note = 0, .velocity = 0 } });
        try notes.append(.{ .base_note = .{ .start_tick = 720, .duration = 240, .note = 60, .velocity = 64 } });
    } else if (std.mem.eql(u8, scenario, "gapped_rests")) {
        // Rests with gaps between them (should NOT be consolidated)
        try notes.append(.{ .base_note = .{ .start_tick = 0, .duration = 240, .note = 0, .velocity = 0 } });
        try notes.append(.{ .base_note = .{ .start_tick = 300, .duration = 240, .note = 0, .velocity = 0 } }); // Gap of 60
        try notes.append(.{ .base_note = .{ .start_tick = 600, .duration = 240, .note = 0, .velocity = 0 } }); // Gap of 60
    } else if (std.mem.eql(u8, scenario, "beat_boundary")) {
        // Rests crossing beat boundary
        try notes.append(.{ .base_note = .{ .start_tick = 400, .duration = 160, .note = 0, .velocity = 0 } });
        try notes.append(.{ .base_note = .{ .start_tick = 560, .duration = 160, .note = 0, .velocity = 0 } }); // Crosses 480 beat
    } else if (std.mem.eql(u8, scenario, "mixed_complex")) {
        // Complex mix for stress testing
        try notes.append(.{ .base_note = .{ .start_tick = 0, .duration = 120, .note = 60, .velocity = 64 } });
        try notes.append(.{ .base_note = .{ .start_tick = 120, .duration = 120, .note = 0, .velocity = 0 } });
        try notes.append(.{ .base_note = .{ .start_tick = 240, .duration = 120, .note = 0, .velocity = 0 } });
        try notes.append(.{ .base_note = .{ .start_tick = 360, .duration = 120, .note = 62, .velocity = 64 } });
        try notes.append(.{ .base_note = .{ .start_tick = 480, .duration = 240, .note = 0, .velocity = 0 } });
        try notes.append(.{ .base_note = .{ .start_tick = 720, .duration = 240, .note = 0, .velocity = 0 } });
        try notes.append(.{ .base_note = .{ .start_tick = 960, .duration = 480, .note = 64, .velocity = 64 } });
    }
    
    return notes.toOwnedSlice();
}

fn runTestScenario(allocator: std.mem.Allocator, scenario: []const u8) !void {
    std.debug.print("Testing scenario: {s}\n", .{scenario});
    
    // Create arena and processor
    var arena = MockArena.init(allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
        .config = .{},
    };
    
    // Create test notes
    const notes = try createTestNotes(allocator, scenario);
    defer allocator.free(notes);
    
    // Run the function
    try processor.processRestOptimization(notes);
    
    // Report results
    var rest_count: usize = 0;
    var consolidated_count: usize = 0;
    var processed_count: usize = 0;
    
    for (notes) |note| {
        if (note.getBaseNote().note == 0) {
            rest_count += 1;
        }
        if (note.rest_info != null and note.rest_info.?.is_optimized_rest) {
            consolidated_count += 1;
        }
        if (note.processing_flags.rest_processed) {
            processed_count += 1;
        }
    }
    
    std.debug.print("  Input notes: {}\n", .{notes.len});
    std.debug.print("  Rest notes: {}\n", .{rest_count});
    std.debug.print("  Consolidated: {}\n", .{consolidated_count});
    std.debug.print("  Processed: {}\n", .{processed_count});
    std.debug.print("  Allocations: {}\n", .{arena.allocated_count});
    std.debug.print("\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== processRestOptimization Function Test ===\n\n", .{});
    
    // Test various scenarios
    try runTestScenario(allocator, "empty");
    try runTestScenario(allocator, "no_rests");
    try runTestScenario(allocator, "single_rest");
    try runTestScenario(allocator, "consecutive_rests");
    try runTestScenario(allocator, "gapped_rests");
    try runTestScenario(allocator, "beat_boundary");
    try runTestScenario(allocator, "mixed_complex");
}

// =============================================================================
// UNIT TESTS
// =============================================================================

test "processRestOptimization - empty input" {
    var arena = MockArena.init(std.testing.allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
        .config = .{},
    };
    
    var notes = [_]EnhancedTimedNote{};
    try processor.processRestOptimization(&notes);
    
    try std.testing.expectEqual(@as(usize, 0), arena.allocated_count);
}

test "processRestOptimization - no rests" {
    var arena = MockArena.init(std.testing.allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
        .config = .{},
    };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .start_tick = 0, .duration = 480, .note = 60, .velocity = 64 } },
        .{ .base_note = .{ .start_tick = 480, .duration = 480, .note = 62, .velocity = 64 } },
    };
    
    try processor.processRestOptimization(&notes);
    
    // All notes should be marked as processed
    try std.testing.expect(notes[0].processing_flags.rest_processed);
    try std.testing.expect(notes[1].processing_flags.rest_processed);
    try std.testing.expectEqual(@as(usize, 0), arena.allocated_count);
}

test "processRestOptimization - consecutive rests consolidated" {
    var arena = MockArena.init(std.testing.allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
        .config = .{},
    };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .start_tick = 0, .duration = 240, .note = 0, .velocity = 0 } },
        .{ .base_note = .{ .start_tick = 240, .duration = 240, .note = 0, .velocity = 0 } },
        .{ .base_note = .{ .start_tick = 480, .duration = 240, .note = 0, .velocity = 0 } },
    };
    
    try processor.processRestOptimization(&notes);
    
    // First rest should have consolidated info
    try std.testing.expect(notes[0].rest_info != null);
    try std.testing.expect(notes[0].rest_info.?.is_optimized_rest);
    try std.testing.expectEqual(@as(u32, 720), notes[0].rest_info.?.rest_data.duration);
    
    // All should be marked as processed
    try std.testing.expect(notes[0].processing_flags.rest_processed);
    try std.testing.expect(notes[1].processing_flags.rest_processed);
    try std.testing.expect(notes[2].processing_flags.rest_processed);
    
    // Should have allocated one RestInfo
    try std.testing.expectEqual(@as(usize, 1), arena.allocated_count);
}

test "processRestOptimization - gapped rests not consolidated" {
    var arena = MockArena.init(std.testing.allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
        .config = .{},
    };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .start_tick = 0, .duration = 240, .note = 0, .velocity = 0 } },
        .{ .base_note = .{ .start_tick = 300, .duration = 240, .note = 0, .velocity = 0 } }, // Gap
    };
    
    try processor.processRestOptimization(&notes);
    
    // Should not be consolidated due to gap
    try std.testing.expectEqual(@as(?*RestInfo, null), notes[0].rest_info);
    try std.testing.expectEqual(@as(?*RestInfo, null), notes[1].rest_info);
    
    // But should still be marked as processed
    try std.testing.expect(notes[0].processing_flags.rest_processed);
    try std.testing.expect(notes[1].processing_flags.rest_processed);
    
    // No allocations since no consolidation
    try std.testing.expectEqual(@as(usize, 0), arena.allocated_count);
}

test "processRestOptimization - safety limits respected" {
    var arena = MockArena.init(std.testing.allocator);
    var processor = EducationalProcessor{
        .arena = &arena,
        .config = .{
            .performance = .{
                .max_iterations_per_loop = 2, // Very low limit for testing
            },
        },
    };
    
    var notes = [_]EnhancedTimedNote{
        .{ .base_note = .{ .start_tick = 0, .duration = 240, .note = 0, .velocity = 0 } },
        .{ .base_note = .{ .start_tick = 240, .duration = 240, .note = 0, .velocity = 0 } },
        .{ .base_note = .{ .start_tick = 480, .duration = 240, .note = 0, .velocity = 0 } },
    };
    
    // Should not fail despite low iteration limit
    try processor.processRestOptimization(&notes);
}
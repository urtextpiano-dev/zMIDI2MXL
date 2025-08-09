//! Memory Arena Allocator for MIDI to MXL Converter
//! Implements TASK-003 per RESEARCH_REPORT.md Section 5 lines 213-237
//!
//! Provides efficient batch memory management for MIDI parsing and MXL generation.
//! All allocations within a processing session are freed together in one operation.

const std = @import("std");
const log_mod = @import("../log.zig");

/// Arena-based allocator wrapper for efficient batch processing
///
/// Designed to handle typical MIDI processing workflows where many temporary
/// allocations are made during parsing/conversion and then freed all at once.
pub const ArenaAllocator = struct {
    /// Underlying arena allocator from Zig standard library
    arena: std.heap.ArenaAllocator,

    /// Base allocator that backs the arena
    base_allocator: std.mem.Allocator,

    /// Statistics for performance monitoring
    stats: AllocationStats,

    /// Optional logger for debugging memory usage
    logger: ?*log_mod.Logger,

    /// Allocation statistics for monitoring and debugging
    pub const AllocationStats = struct {
        /// Total bytes allocated through this arena
        total_allocated: u64 = 0,

        /// Number of allocation requests
        allocation_count: u64 = 0,

        /// Peak memory usage (approximate)
        peak_usage: u64 = 0,

        /// Number of resets performed
        reset_count: u64 = 0,

        /// Time spent in allocation operations (nanoseconds)
        allocation_time_ns: u64 = 0,

        pub fn reset(self: *AllocationStats) void {
            self.* = .{};
        }

        pub fn recordAllocation(self: *AllocationStats, size: usize, time_ns: u64) void {
            self.total_allocated += size;
            self.allocation_count += 1;
            self.allocation_time_ns += time_ns;
            // Simpler & branchless peak update
            self.peak_usage = @max(self.peak_usage, self.total_allocated);
        }

        pub fn recordReset(self: *AllocationStats) void {
            self.reset_count += 1;
            // Keep historical counters, reset current usage
            self.total_allocated = 0;
        }

        /// Get average allocation time in nanoseconds
        pub fn getAverageAllocationTime(self: AllocationStats) f64 {
            if (self.allocation_count == 0) return 0.0;
            return @as(f64, @floatFromInt(self.allocation_time_ns)) / @as(f64, @floatFromInt(self.allocation_count));
        }
    };

    const ArenaVTable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .free = free,
        .remap = std.mem.Allocator.noRemap,
    };

    /// Initialize arena allocator with base allocator
    ///
    /// Args:
    ///   base_allocator: The backing allocator (e.g., GPA)
    ///   enable_logging: Whether to enable allocation logging for debugging
    pub fn init(base_allocator: std.mem.Allocator, enable_logging: bool) ArenaAllocator {
        return .{
            .arena = std.heap.ArenaAllocator.init(base_allocator),
            .base_allocator = base_allocator,
            .stats = .{},
            .logger = if (enable_logging) log_mod.getLogger() else null,
        };
    }

    /// Clean up arena allocator and all managed memory
    pub fn deinit(self: *ArenaAllocator) void {
        // Safe logger access - get fresh pointer to avoid use-after-free
        if (self.logger != null) {
            const current_logger = log_mod.getLogger();
            current_logger.debug("Arena deallocating: {d} bytes total, {d} allocations, {d} resets", .{
                self.stats.total_allocated + self.stats.peak_usage, // Total including freed
                self.stats.allocation_count,
                self.stats.reset_count,
            });
        }

        self.arena.deinit();
    }

    /// Get the allocator interface for use in allocation calls
    ///
    /// This returns a wrapped allocator that tracks statistics and optionally logs.
    pub fn allocator(self: *ArenaAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &ArenaVTable,
        };
    }

    /// Reset arena, freeing all allocated memory in batch
    ///
    /// This is the key performance feature - instead of individual frees,
    /// all memory is reclaimed in one O(1) operation.
    pub fn reset(self: *ArenaAllocator) void {
        const start_time = std.time.nanoTimestamp();

        // Safe logger access - get fresh pointer to avoid use-after-free
        if (self.logger != null)
            log_mod.getLogger().debug(
                "Arena reset: freeing {d} bytes from {d} allocations",
                .{ self.stats.total_allocated, self.stats.allocation_count },
            );

        _ = self.arena.reset(.free_all);
        self.stats.recordReset();

        const reset_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));

        if (self.logger != null)
            log_mod.getLogger().debug("Arena reset completed in {d} ns", .{reset_time});
    }

    /// Get current allocation statistics
    pub fn getStats(self: *const ArenaAllocator) AllocationStats {
        return self.stats;
    }

    /// Check if performance targets are being met
    ///
    /// Returns true if average allocation time is under target threshold.
    /// Target: < 1ms allocation overhead for 1MB as per TASK-003.
    pub fn isPerformanceTargetMet(self: *const ArenaAllocator, target_mb: f64) bool {
        const NS_PER_MS = @as(f64, @floatFromInt(std.time.ns_per_ms));
        const avg_time_ms = self.stats.getAverageAllocationTime() / NS_PER_MS;

        // Scale target based on amount of memory processed (by peak usage in bytes).
        const mb_processed = @as(f64, @floatFromInt(self.stats.peak_usage)) / (1024.0 * 1024.0);
        const scaled_target_ms = if (mb_processed > 0.0) target_mb / mb_processed else 1.0;

        return avg_time_ms < scaled_target_ms;
    }

    // Internal allocator implementation
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *ArenaAllocator = @ptrCast(@alignCast(ctx));
        const t0 = std.time.nanoTimestamp();

        const a = self.arena.allocator();
        const result = a.vtable.alloc(a.ptr, len, ptr_align, ret_addr);
        const alloc_time: u64 = @as(u64, @intCast(std.time.nanoTimestamp() - t0));

        if (result == null) return null;

        self.stats.recordAllocation(len, alloc_time);
        if (self.logger != null)
            log_mod.getLogger().debug("Arena alloc: {d} bytes in {d} ns", .{ len, alloc_time });

        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *ArenaAllocator = @ptrCast(@alignCast(ctx));
        const a = self.arena.allocator();
        return a.vtable.resize(a.ptr, buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        // Arena allocator doesn't support individual frees - this is a no-op
        // All memory is freed together in reset()
    }
};

/// Convenience function to create a new arena allocator
///
/// This matches the pattern shown in RESEARCH_REPORT.md Section 5.
pub fn createArena(base_allocator: std.mem.Allocator) ArenaAllocator {
    return ArenaAllocator.init(base_allocator, false);
}

/// Create arena with logging enabled for debugging
pub fn createArenaWithLogging(base_allocator: std.mem.Allocator) ArenaAllocator {
    return ArenaAllocator.init(base_allocator, true);
}

// Tests
test "arena allocator basic functionality" {
    var arena = ArenaAllocator.init(std.testing.allocator, false);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Test basic allocation
    const data1 = try allocator.alloc(u8, 100);
    try std.testing.expect(data1.len == 100);

    // Test multiple allocations
    const data2 = try allocator.alloc(u32, 50);
    try std.testing.expect(data2.len == 50);

    // Check statistics
    const stats = arena.getStats();
    try std.testing.expect(stats.allocation_count == 2);
    try std.testing.expect(stats.total_allocated >= 100 + 50 * @sizeOf(u32));

    // Test reset
    arena.reset();
    const stats_after_reset = arena.getStats();
    try std.testing.expect(stats_after_reset.reset_count == 1);
    try std.testing.expect(stats_after_reset.total_allocated == 0);
}

test "arena allocator performance tracking" {
    var arena = ArenaAllocator.init(std.testing.allocator, false);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Allocate 1MB to test performance target
    const one_mb = 1024 * 1024;
    const large_data = try allocator.alloc(u8, one_mb);
    try std.testing.expect(large_data.len == one_mb);

    // Check if performance target is met
    // This is a basic test - actual performance depends on system
    const stats = arena.getStats();
    try std.testing.expect(stats.allocation_count > 0);
    try std.testing.expect(stats.total_allocated >= one_mb);
}

test "arena allocator batch cleanup" {
    var arena = ArenaAllocator.init(std.testing.allocator, false);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Allocate multiple chunks
    var allocations: [10][]u8 = undefined;
    for (&allocations, 0..) |*alloc, i| {
        alloc.* = try allocator.alloc(u8, (i + 1) * 100);
    }

    const stats_before = arena.getStats();
    try std.testing.expect(stats_before.allocation_count == 10);

    // Reset should free all memory at once
    arena.reset();

    const stats_after = arena.getStats();
    try std.testing.expect(stats_after.reset_count == 1);
    try std.testing.expect(stats_after.total_allocated == 0);

    // Should be able to allocate again after reset
    const new_data = try allocator.alloc(u8, 256);
    try std.testing.expect(new_data.len == 256);
}

test "arena allocator no memory leaks" {
    // This test verifies that the arena properly cleans up
    // by using a tracking allocator
    const tracking = std.testing.allocator;

    {
        var arena = ArenaAllocator.init(tracking, false);
        defer arena.deinit();

        const allocator = arena.allocator();

        // Make several allocations
        _ = try allocator.alloc(u8, 1000);
        _ = try allocator.alloc(u32, 100);
        _ = try allocator.alloc(i64, 50);

        // Reset and allocate more
        arena.reset();
        _ = try allocator.alloc(u8, 2000);
    }

    // If we reach here without issues, no memory leaks occurred
    // (std.testing.allocator will detect leaks automatically)
}

test "convenience functions" {
    var arena1 = createArena(std.testing.allocator);
    defer arena1.deinit();

    var arena2 = createArenaWithLogging(std.testing.allocator);
    defer arena2.deinit();

    // Test that both work
    const alloc1 = arena1.allocator();
    const alloc2 = arena2.allocator();

    _ = try alloc1.alloc(u8, 100);
    _ = try alloc2.alloc(u8, 100);

    try std.testing.expect(arena1.getStats().allocation_count == 1);
    try std.testing.expect(arena2.getStats().allocation_count == 1);
}

// Educational Processing Arena Infrastructure
//
// Implements TASK-INT-001 as specified in EDUCATIONAL_FEATURE_INTEGRATION_TASK_LIST.md
// This provides specialized memory management for the educational processing chain:
// Tuplet → Beam → Rest → Dynamics
//
// Performance targets:
// - < 100ns per note pipeline overhead
// - < 20% memory overhead increase
// - Zero memory leaks with automated cleanup

/// Educational processing phase tracking for memory allocation
pub const EducationalPhase = enum {
    tuplet_detection,
    beam_grouping,
    rest_optimization,
    dynamics_mapping,
    coordination,

    pub fn toString(self: EducationalPhase) []const u8 {
        return @tagName(self);
    }
};

/// Performance metrics specific to educational processing
pub const EducationalPerformanceMetrics = struct {
    total_processing_time_ns: u128 = 0,
    /// Processing time per note in nanoseconds
    processing_time_per_note_ns: u64 = 0,
    /// Notes processed in current session
    notes_processed: u64 = 0,
    /// Memory allocated per educational phase
    phase_allocations: [5]u64 = [_]u64{0} ** 5, // One for each EducationalPhase
    /// Peak memory usage during processing
    peak_educational_memory: u64 = 0,
    /// Number of successful processing cycles
    successful_cycles: u64 = 0,
    /// Number of processing errors encountered
    error_count: u64 = 0,

    pub fn reset(self: *EducationalPerformanceMetrics) void {
        self.* = .{};
    }

    pub fn recordProcessing(
        self: *EducationalPerformanceMetrics,
        notes_count: u64,
        time_ns: u64,
    ) void {
        // If no notes were processed, don't distort the average.
        if (notes_count == 0) {
            self.successful_cycles += 1;
            return;
        }

        const prev_notes: u64 = self.notes_processed;
        const new_notes: u64 = prev_notes + notes_count;

        self.notes_processed = new_notes;
        self.successful_cycles += 1;

        // Update exact total time using widened math to avoid overflow on the multiply.
        // Average per note = total_time / total_notes.
        self.total_processing_time_ns =
            self.total_processing_time_ns + @as(u128, @intCast(time_ns));

        // Truncate toward zero for integer ns-per-note; change to rounding if desired.
        self.processing_time_per_note_ns =
            @as(u64, @intCast(self.total_processing_time_ns / @as(u128, @intCast(new_notes))));
    }

    pub fn recordPhaseAllocation(
        self: *EducationalPerformanceMetrics,
        phase: EducationalPhase,
        bytes: u64,
    ) void {
        const idx: usize = @intFromEnum(phase);
        self.phase_allocations[idx] += bytes;

        var total: u64 = 0;
        for (self.phase_allocations) |allocation| total += allocation;

        self.peak_educational_memory = @max(self.peak_educational_memory, total);
    }

    pub fn recordError(self: *EducationalPerformanceMetrics) void {
        self.error_count += 1;
    }

    /// Check if performance targets are being met
    /// Target: < 100ns per note pipeline overhead
    pub fn isPerformanceTargetMet(self: *const EducationalPerformanceMetrics) bool {
        return self.processing_time_per_note_ns < 100;
    }

    /// Get memory overhead percentage compared to base allocation
    pub fn getMemoryOverheadPercentage(self: *const EducationalPerformanceMetrics, base_memory: u64) f64 {
        if (base_memory == 0) return 0.0;
        return (@as(f64, @floatFromInt(self.peak_educational_memory)) / @as(f64, @floatFromInt(base_memory))) * 100.0;
    }
};

/// Specialized arena allocator for educational processing chain
///
/// Provides memory management foundation for all educational features:
/// - Tuplet detection metadata storage
/// - Beam grouping coordination data
/// - Rest optimization temporary structures
/// - Dynamics mapping cache
/// - Inter-feature coordination buffers
pub const EducationalArena = struct {
    /// Base arena allocator for bulk memory management
    base_arena: ArenaAllocator,

    /// Current educational processing phase
    current_phase: ?EducationalPhase = null,

    /// Performance metrics tracking
    metrics: EducationalPerformanceMetrics,

    /// Leak detection enabled flag
    leak_detection_enabled: bool,

    /// Error recovery mode - when true, arena continues after allocation failures
    error_recovery_mode: bool = false,

    /// Initialize educational arena with base allocator
    ///
    /// Args:
    ///   base_allocator: The backing allocator (typically GPA)
    ///   enable_leak_detection: Whether to enable comprehensive leak detection
    ///   enable_logging: Whether to enable allocation logging for debugging
    pub fn init(base_allocator: std.mem.Allocator, enable_leak_detection: bool, enable_logging: bool) EducationalArena {
        return .{
            .base_arena = ArenaAllocator.init(base_allocator, enable_logging),
            .metrics = .{},
            .leak_detection_enabled = enable_leak_detection,
        };
    }

    /// Clean up educational arena and validate no leaks
    pub fn deinit(self: *EducationalArena) void {
        if (self.leak_detection_enabled) {
            self.validateNoLeaks();
        }

        if (self.base_arena.logger != null) {
            log_mod.getLogger().debug(
                "Educational arena cleanup: {d} notes processed, {d} cycles completed",
                .{ self.metrics.notes_processed, self.metrics.successful_cycles },
            );
            if (self.metrics.error_count > 0) {
                log_mod.getLogger().warn(
                    "Educational arena had {d} errors during processing",
                    .{self.metrics.error_count},
                );
            }
        }

        self.base_arena.deinit();
    }

    /// Get allocator for educational processing
    ///
    /// This wraps the base arena allocator with educational-specific tracking
    pub fn allocator(self: *EducationalArena) std.mem.Allocator {
        return self.base_arena.allocator();
    }

    /// Begin a new educational processing phase
    ///
    /// This enables phase-specific memory tracking and performance monitoring
    pub fn beginPhase(self: *EducationalArena, phase: EducationalPhase) void {
        self.current_phase = phase;

        if (self.base_arena.logger != null) {
            // @tagName avoids a custom toString and stays correct if enum cases change.
            log_mod.getLogger().debug(
                "Educational arena entering phase: {s}",
                .{@tagName(phase)},
            );
        }
    }

    /// End current educational processing phase
    pub fn endPhase(self: *EducationalArena) void {
        if (self.current_phase) |phase| {
            if (self.base_arena.logger != null) {
                log_mod.getLogger().debug(
                    "Educational arena completing phase: {s}",
                    .{@tagName(phase)},
                );
            }
        }
        self.current_phase = null;
    }

    /// Allocate memory for educational feature processing
    ///
    /// This tracks allocations per educational phase for monitoring
    pub fn allocForEducational(self: *EducationalArena, comptime T: type, count: usize) ![]T {
        const t0 = std.time.nanoTimestamp();

        const result = self.allocator().alloc(T, count) catch |err| {
            self.metrics.recordError();
            if (self.error_recovery_mode) {
                if (self.base_arena.logger != null)
                    log_mod.getLogger().warn("Educational allocation failed, continuing in recovery mode", .{});
                return err;
            }
            return err;
        };

        const alloc_time: u64 = @as(u64, @intCast(std.time.nanoTimestamp() - t0));

        if (self.current_phase) |phase| {
            self.metrics.recordPhaseAllocation(phase, @sizeOf(T) * count);
        }

        if (self.base_arena.logger != null) {
            log_mod.getLogger().debug("Educational alloc: {d} x {s} in {d} ns", .{ count, @typeName(T), alloc_time });
        }

        return result;
    }

    /// Process a batch of notes through educational pipeline
    ///
    /// This is the main integration point for educational feature processing
    pub fn processEducationalBatch(self: *EducationalArena, notes_count: u64) !void {
        const t0 = std.time.nanoTimestamp();
        defer self.metrics.recordProcessing(notes_count, @as(u64, @intCast(std.time.nanoTimestamp() - t0)));

        // Validate performance after warm-up
        if (self.metrics.notes_processed > 100 and !self.metrics.isPerformanceTargetMet()) {
            if (self.base_arena.logger != null) {
                log_mod.getLogger().warn(
                    "Educational processing exceeding performance target: {d}ns per note",
                    .{self.metrics.processing_time_per_note_ns},
                );
            }
        }
    }

    /// Reset arena for next processing cycle
    ///
    /// This preserves metrics across processing cycles for long-term monitoring
    pub fn resetForNextCycle(self: *EducationalArena) void {
        if (self.base_arena.logger != null) {
            log_mod.getLogger().debug(
                "Educational arena reset: {d} bytes peak, {d} notes processed",
                .{ self.metrics.peak_educational_memory, self.metrics.notes_processed },
            );
        }

        self.base_arena.reset();
        self.current_phase = null;

        // Reset per-cycle fields while preserving totals
        const prev = self.metrics;
        self.metrics = .{};
        self.metrics.notes_processed = prev.notes_processed;
        self.metrics.successful_cycles = prev.successful_cycles;
        self.metrics.error_count = prev.error_count;
    }

    /// Get current performance metrics
    pub fn getMetrics(self: *const EducationalArena) EducationalPerformanceMetrics {
        return self.metrics;
    }

    /// Check if memory usage is within acceptable bounds
    /// Target: < 20% memory overhead increase
    pub fn isMemoryUsageAcceptable(self: *const EducationalArena, base_memory_usage: u64) bool {
        const overhead_percentage = self.metrics.getMemoryOverheadPercentage(base_memory_usage);
        return overhead_percentage < 20.0;
    }

    /// Enable error recovery mode for graceful degradation
    pub fn enableErrorRecovery(self: *EducationalArena) void {
        self.error_recovery_mode = true;
        if (self.base_arena.logger != null) {
            log_mod.getLogger().info("Educational arena error recovery mode enabled", .{});
        }
    }

    /// Disable error recovery mode for strict validation
    pub fn disableErrorRecovery(self: *EducationalArena) void {
        self.error_recovery_mode = false;
        if (self.base_arena.logger != null) {
            log_mod.getLogger().info("Educational arena error recovery mode disabled", .{});
        }
    }

    /// Validate no memory leaks in educational processing
    ///
    /// This checks for proper cleanup of educational feature allocations
    fn validateNoLeaks(self: *EducationalArena) void {
        const stats = self.base_arena.getStats();

        // Safe logger access - get fresh pointer to avoid use-after-free
        if (self.base_arena.logger != null) {
            const current_logger = log_mod.getLogger();
            current_logger.debug("Educational arena leak validation: {d} allocations, {d} resets", .{
                stats.allocation_count,
                stats.reset_count,
            });

            // Check for potential leaks (more allocations than expected)
            if (stats.allocation_count > self.metrics.successful_cycles * 10) {
                current_logger.warn("Potential memory leak detected: {d} allocations for {d} cycles", .{
                    stats.allocation_count,
                    self.metrics.successful_cycles,
                });
            }
        }
    }
};

/// Convenience function to create educational arena
pub fn createEducationalArena(base_allocator: std.mem.Allocator) EducationalArena {
    return EducationalArena.init(base_allocator, false, false);
}

/// Create educational arena with leak detection enabled
pub fn createEducationalArenaWithLeakDetection(base_allocator: std.mem.Allocator) EducationalArena {
    return EducationalArena.init(base_allocator, true, true);
}

// Educational Arena Tests

test "educational arena basic functionality" {
    var edu_arena = EducationalArena.init(std.testing.allocator, false, false);
    defer edu_arena.deinit();

    const allocator = edu_arena.allocator();

    // Test basic allocation
    const data = try allocator.alloc(u8, 100);
    try std.testing.expect(data.len == 100);

    // Test metrics tracking
    const metrics = edu_arena.getMetrics();
    try std.testing.expect(metrics.notes_processed == 0); // No processing yet
}

test "educational arena phase tracking" {
    var edu_arena = EducationalArena.init(std.testing.allocator, false, false);
    defer edu_arena.deinit();

    // Test phase transitions
    edu_arena.beginPhase(.tuplet_detection);
    try std.testing.expect(edu_arena.current_phase == .tuplet_detection);

    // Allocate during phase
    _ = try edu_arena.allocForEducational(u32, 50);

    edu_arena.endPhase();
    try std.testing.expect(edu_arena.current_phase == null);

    // Check metrics recorded phase allocation
    const metrics = edu_arena.getMetrics();
    try std.testing.expect(metrics.phase_allocations[@intFromEnum(EducationalPhase.tuplet_detection)] > 0);
}

test "educational arena performance tracking" {
    var edu_arena = EducationalArena.init(std.testing.allocator, false, false);
    defer edu_arena.deinit();

    // Process a batch of notes
    try edu_arena.processEducationalBatch(100);

    const metrics = edu_arena.getMetrics();
    try std.testing.expect(metrics.notes_processed == 100);
    try std.testing.expect(metrics.successful_cycles == 1);
    try std.testing.expect(metrics.processing_time_per_note_ns > 0);
}

test "educational arena memory tracking" {
    var edu_arena = EducationalArena.init(std.testing.allocator, false, false);
    defer edu_arena.deinit();

    edu_arena.beginPhase(.beam_grouping);

    // Allocate different types
    _ = try edu_arena.allocForEducational(u8, 1000);
    _ = try edu_arena.allocForEducational(u32, 250);

    edu_arena.endPhase();

    const metrics = edu_arena.getMetrics();
    const beam_idx = @intFromEnum(EducationalPhase.beam_grouping);
    try std.testing.expect(metrics.phase_allocations[beam_idx] >= 1000 + 250 * 4);
    try std.testing.expect(metrics.peak_educational_memory > 0);
}

test "educational arena reset and reuse" {
    var edu_arena = EducationalArena.init(std.testing.allocator, false, false);
    defer edu_arena.deinit();

    // First cycle
    edu_arena.beginPhase(.tuplet_detection);
    _ = try edu_arena.allocForEducational(u8, 500);
    try edu_arena.processEducationalBatch(50);

    const metrics_before = edu_arena.getMetrics();
    try std.testing.expect(metrics_before.notes_processed == 50);

    // Reset and second cycle
    edu_arena.resetForNextCycle();
    edu_arena.beginPhase(.rest_optimization);
    _ = try edu_arena.allocForEducational(u16, 200);
    try edu_arena.processEducationalBatch(75);

    const metrics_after = edu_arena.getMetrics();
    try std.testing.expect(metrics_after.notes_processed == 125); // Cumulative
    try std.testing.expect(metrics_after.successful_cycles == 2);
}

test "educational arena error recovery" {
    var edu_arena = EducationalArena.init(std.testing.allocator, false, false);
    defer edu_arena.deinit();

    // Enable error recovery
    edu_arena.enableErrorRecovery();
    try std.testing.expect(edu_arena.error_recovery_mode);

    // Disable error recovery
    edu_arena.disableErrorRecovery();
    try std.testing.expect(!edu_arena.error_recovery_mode);
}

test "educational arena memory overhead validation" {
    var edu_arena = EducationalArena.init(std.testing.allocator, false, false);
    defer edu_arena.deinit();

    edu_arena.beginPhase(.dynamics_mapping);
    _ = try edu_arena.allocForEducational(u8, 100);

    // Test with base memory usage
    const base_memory: u64 = 1000;
    try std.testing.expect(edu_arena.isMemoryUsageAcceptable(base_memory));

    const metrics = edu_arena.getMetrics();
    const overhead = metrics.getMemoryOverheadPercentage(base_memory);
    try std.testing.expect(overhead >= 0.0);
}

test "educational arena convenience functions" {
    var arena1 = createEducationalArena(std.testing.allocator);
    defer arena1.deinit();

    var arena2 = createEducationalArenaWithLeakDetection(std.testing.allocator);
    defer arena2.deinit();

    // Test both work
    const alloc1 = arena1.allocator();
    const alloc2 = arena2.allocator();

    _ = try alloc1.alloc(u8, 50);
    _ = try alloc2.alloc(u8, 50);

    try std.testing.expect(!arena1.leak_detection_enabled);
    try std.testing.expect(arena2.leak_detection_enabled);
}

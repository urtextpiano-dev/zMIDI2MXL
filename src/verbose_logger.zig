const std = @import("std");
const containers = @import("utils/containers.zig");
const log_mod = @import("log.zig");

/// Source location information for tracking where precision loss occurs
pub const SourceLocation = struct {
    file: []const u8,
    function: []const u8,
    line: u32,
};

/// Hierarchical step ID system for tracking pipeline execution
/// Implements TASK-VL-006 per VERBOSE_LOGGING_TASK_LIST.md lines 226-273
pub const StepID = struct {
    major: u16,
    minor: u16,
    micro: u16,
    
    /// Increment the step ID at the specified level
    /// When incrementing a level, all lower levels reset to 0
    pub fn next(self: *StepID, level: enum { major, minor, micro }) void {
        switch (level) {
            .major => {
                self.major += 1;
                self.minor = 0;
                self.micro = 0;
            },
            .minor => {
                self.minor += 1;
                self.micro = 0;
            },
            .micro => {
                self.micro += 1;
            },
        }
    }
    
    /// Format the step ID as [XXX.YYY.ZZZ]
    pub fn format(self: StepID, buf: []u8) ![]const u8 {
        return std.fmt.bufPrint(buf, "[{d:0>3}.{d:0>3}.{d:0>3}]", .{
            self.major, self.minor, self.micro
        });
    }
    
    /// Reset the step ID to initial state [000.000.000]
    pub fn reset(self: *StepID) void {
        self.major = 0;
        self.minor = 0;
        self.micro = 0;
    }
    
    /// Create a copy of the current step ID
    pub fn clone(self: StepID) StepID {
        return .{
            .major = self.major,
            .minor = self.minor,
            .micro = self.micro,
        };
    }
    
    /// Compare two step IDs for equality
    pub fn equals(self: StepID, other: StepID) bool {
        return self.major == other.major and 
               self.minor == other.minor and 
               self.micro == other.micro;
    }
    
    /// Get the total step count (for statistics)
    /// Major steps count as 1000, minor as 1
    pub fn getTotalStepCount(self: StepID) u32 {
        return @as(u32, self.major) * 1000000 + 
               @as(u32, self.minor) * 1000 + 
               @as(u32, self.micro);
    }
};

/// Precision monitoring system for tracking floating-point precision loss
/// Implements TASK-VL-001 per VERBOSE_LOGGING_TASK_LIST.md lines 50-91
pub const PrecisionMonitor = struct {
    enabled: bool,
    warnings: containers.List(PrecisionWarning),
    threshold: f64 = 0.001, // 0.1% default threshold
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex, // For thread-safety
    
    pub const PrecisionWarning = struct {
        operation: []const u8,
        input: f64,
        expected: f64,
        actual: f64,
        loss_percent: f64,
        location: SourceLocation,
        timestamp_ns: i64,
    };
    
    /// Initialize the precision monitor
    pub fn init(allocator: std.mem.Allocator, enabled: bool) PrecisionMonitor {
        return .{
            .enabled = enabled,
            .warnings = containers.List(PrecisionWarning).init(allocator),
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
        };
    }
    
    /// Deinitialize and free resources
    pub fn deinit(self: *PrecisionMonitor) void {
        // Free operation strings that were allocated
        for (self.warnings.items) |warn| {
            self.allocator.free(warn.operation);
            self.allocator.free(warn.location.file);
            self.allocator.free(warn.location.function);
        }
        self.warnings.deinit();
    }
    
    /// Track a precision-sensitive operation
    /// Zero-cost when disabled due to inline and early return
    pub inline fn trackOperation(
        self: *PrecisionMonitor,
        operation: []const u8,
        input: f64,
        output: f64,
        expected_precision: f64,
        location: SourceLocation,
    ) void {
        // Zero-cost when disabled - compiler will optimize this out
        if (!self.enabled) return;
        
        // Calculate precision loss
        const expected = input * expected_precision;
        const loss = @abs(output - expected);
        
        // Only track if loss exceeds threshold
        if (expected != 0) {
            const loss_percent = (loss / @abs(expected)) * 100.0;
            
            if (loss_percent > self.threshold * 100.0) {
                self.addWarning(operation, input, expected, output, loss_percent, location) catch {
                    // Silently ignore allocation failures in monitoring
                    return;
                };
            }
        }
    }
    
    /// Track operations that should have no precision loss
    pub inline fn trackExactOperation(
        self: *PrecisionMonitor,
        operation: []const u8,
        input: f64,
        output: f64,
        location: SourceLocation,
    ) void {
        if (!self.enabled) return;
        
        if (input != output) {
            const loss_percent = if (input != 0) 
                (@abs(output - input) / @abs(input)) * 100.0
            else 
                100.0;
                
            self.addWarning(operation, input, input, output, loss_percent, location) catch {
                return;
            };
        }
    }
    
    /// Internal method to add a warning (thread-safe)
    fn addWarning(
        self: *PrecisionMonitor,
        operation: []const u8,
        input: f64,
        expected: f64,
        actual: f64,
        loss_percent: f64,
        location: SourceLocation,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Clone strings to ensure they persist
        const op_copy = try self.allocator.dupe(u8, operation);
        errdefer self.allocator.free(op_copy);
        
        const file_copy = try self.allocator.dupe(u8, location.file);
        errdefer self.allocator.free(file_copy);
        
        const func_copy = try self.allocator.dupe(u8, location.function);
        errdefer self.allocator.free(func_copy);
        
        try self.warnings.append(.{
            .operation = op_copy,
            .input = input,
            .expected = expected,
            .actual = actual,
            .loss_percent = loss_percent,
            .location = .{
                .file = file_copy,
                .function = func_copy,
                .line = location.line,
            },
            .timestamp_ns = @intCast(std.time.nanoTimestamp()),
        });
    }
    
    /// Get number of warnings recorded
    pub fn getWarningCount(self: *const PrecisionMonitor) usize {
        return self.warnings.items.len;
    }
    
    /// Clear all warnings
    pub fn clearWarnings(self: *PrecisionMonitor) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Free operation strings
        for (self.warnings.items) |warn| {
            self.allocator.free(warn.operation);
            self.allocator.free(warn.location.file);
            self.allocator.free(warn.location.function);
        }
        self.warnings.clearRetainingCapacity();
    }
    
    /// Set precision threshold (as a fraction, e.g., 0.001 = 0.1%)
    pub fn setThreshold(self: *PrecisionMonitor, threshold: f64) void {
        self.threshold = threshold;
    }
};

/// Comprehensive pipeline step registry for tracking all conversion steps
/// Implements TASK-VL-007 per VERBOSE_LOGGING_TASK_LIST.md lines 276-333
pub const PipelineSteps = enum(u32) {
    // Initialization Phase (001.xxx.xxx)
    INIT_START = 1_000_000,
    INIT_PARSE_ARGS = 1_001_000,
    INIT_SETUP_LOGGING = 1_002_000,
    INIT_SETUP_ERROR_HANDLER = 1_003_000,
    INIT_SETUP_VERBOSE_LOGGER = 1_004_000,
    INIT_PARSE_CONFIG = 1_005_000,
    INIT_SETUP_ALLOCATORS = 1_006_000,
    
    // File Operations Phase (002.xxx.xxx)
    FILE_READ_START = 2_000_000,
    FILE_OPEN = 2_001_000,
    FILE_READ_CONTENT = 2_002_000,
    FILE_VALIDATE_SIZE = 2_003_000,
    FILE_VALIDATE_FORMAT = 2_004_000,
    
    // MIDI Parsing Phase (003.xxx.xxx)
    MIDI_PARSE_START = 3_000_000,
    MIDI_PARSE_HEADER = 3_001_000,
    MIDI_PARSE_TRACKS = 3_002_000,
    MIDI_PARSE_EVENTS = 3_003_000,
    MIDI_VALIDATE_STRUCTURE = 3_004_000,
    MIDI_CREATE_CONTAINER = 3_005_000,
    MIDI_CREATE_PARTS = 3_006_000,
    
    // Timing Conversion Phase (004.xxx.xxx)
    TIMING_START = 4_000_000,
    TIMING_DIVISION_SETUP = 4_001_000,
    TIMING_NOTE_DURATION_TRACKING = 4_002_000,
    TIMING_CONVERT_TO_TIMED_NOTES = 4_003_000,
    TIMING_VALIDATE_DURATIONS = 4_004_000,
    
    // Voice Assignment Phase (005.xxx.xxx) - Optional
    VOICE_START = 5_000_000,
    VOICE_ALLOCATOR_INIT = 5_001_000,
    VOICE_ASSIGNMENT = 5_002_000,
    VOICE_VALIDATION = 5_003_000,
    
    // Measure Detection Phase (006.xxx.xxx) - Optional
    MEASURE_START = 6_000_000,
    MEASURE_BOUNDARY_DETECTION = 6_001_000,
    MEASURE_TIME_SIGNATURE_EXTRACTION = 6_002_000,
    MEASURE_ORGANIZATION = 6_003_000,
    MEASURE_VALIDATION = 6_004_000,
    
    // Educational Processing Phase (007.xxx.xxx) - Optional
    EDU_START = 7_000_000,
    EDU_ARENA_INIT = 7_001_000,
    EDU_PROCESSOR_INIT = 7_002_000,
    EDU_CONVERT_TO_ENHANCED_NOTES = 7_003_000,
    
    // Educational Sub-phases (007.xxx.yyy)
    EDU_TUPLET_DETECTION_START = 7_010_000,
    EDU_TUPLET_ANALYSIS = 7_010_001,
    EDU_TUPLET_PATTERN_MATCHING = 7_010_002,
    EDU_TUPLET_VALIDATION = 7_010_003,
    EDU_TUPLET_METADATA_ASSIGNMENT = 7_010_004,
    
    EDU_BEAM_GROUPING_START = 7_020_000,
    EDU_BEAM_ANALYSIS = 7_020_001,
    EDU_BEAM_GROUP_FORMATION = 7_020_002,
    EDU_BEAM_TUPLET_COORDINATION = 7_020_003,
    EDU_BEAM_METADATA_ASSIGNMENT = 7_020_004,
    
    EDU_REST_OPTIMIZATION_START = 7_030_000,
    EDU_REST_ANALYSIS = 7_030_001,
    EDU_REST_CONSOLIDATION = 7_030_002,
    EDU_REST_BEAM_COORDINATION = 7_030_003,
    EDU_REST_METADATA_ASSIGNMENT = 7_030_004,
    
    EDU_DYNAMICS_MAPPING_START = 7_040_000,
    EDU_DYNAMICS_VELOCITY_ANALYSIS = 7_040_001,
    EDU_DYNAMICS_MARKING_ASSIGNMENT = 7_040_002,
    EDU_DYNAMICS_CONTEXT_ANALYSIS = 7_040_003,
    EDU_DYNAMICS_METADATA_ASSIGNMENT = 7_040_004,
    
    EDU_STEM_DIRECTION_START = 7_050_000,
    EDU_STEM_PITCH_ANALYSIS = 7_050_001,
    EDU_STEM_BEAM_COORDINATION = 7_050_002,
    EDU_STEM_VOICE_COORDINATION = 7_050_003,
    EDU_STEM_METADATA_ASSIGNMENT = 7_050_004,
    
    EDU_COORDINATION_START = 7_060_000,
    EDU_COORDINATION_CONFLICT_DETECTION = 7_060_001,
    EDU_COORDINATION_CONFLICT_RESOLUTION = 7_060_002,
    EDU_COORDINATION_VALIDATION = 7_060_003,
    EDU_COORDINATION_METADATA_FINALIZATION = 7_060_004,
    
    EDU_PERFORMANCE_MONITORING = 7_070_000,
    EDU_MEMORY_CLEANUP = 7_080_000,
    EDU_METRICS_COLLECTION = 7_090_000,
    
    // MusicXML Generation Phase (008.xxx.xxx)
    MXL_START = 8_000_000,
    MXL_GENERATOR_INIT = 8_001_000,
    MXL_HEADER_GENERATION = 8_002_000,
    MXL_PART_LIST_GENERATION = 8_003_000,
    MXL_SCORE_PART_GENERATION = 8_004_000,
    MXL_MEASURE_GENERATION = 8_005_000,
    MXL_NOTE_GENERATION = 8_006_000,
    MXL_ENHANCED_NOTE_PROCESSING = 8_007_000,
    MXL_TUPLET_XML_GENERATION = 8_008_000,
    MXL_BEAM_XML_GENERATION = 8_009_000,
    MXL_DYNAMICS_XML_GENERATION = 8_010_000,
    MXL_REST_XML_GENERATION = 8_011_000,
    MXL_STEM_XML_GENERATION = 8_012_000,
    MXL_VALIDATION = 8_013_000,
    
    // MXL Archive Creation Phase (009.xxx.xxx)
    MXL_ARCHIVE_START = 9_000_000,
    MXL_ZIP_WRITER_INIT = 9_001_000,
    MXL_ADD_MUSICXML_FILE = 9_002_000,
    MXL_CREATE_CONTAINER_XML = 9_003_000,
    MXL_ADD_CONTAINER_XML = 9_004_000,
    MXL_FINALIZE_ARCHIVE = 9_005_000,
    
    // Finalization Phase (010.xxx.xxx)
    FINAL_START = 10_000_000,
    FINAL_PRECISION_WARNINGS = 10_001_000,
    FINAL_ERROR_REPORTING = 10_002_000,
    FINAL_METRICS_REPORTING = 10_003_000,
    FINAL_CLEANUP = 10_004_000,
    FINAL_SUCCESS = 10_005_000,
    
    /// Get the phase number (major component)
    pub fn getPhase(self: PipelineSteps) u16 {
        return @intCast(@intFromEnum(self) / 1_000_000);
    }
    
    /// Get the section number (minor component)
    pub fn getSection(self: PipelineSteps) u16 {
        return @intCast((@intFromEnum(self) % 1_000_000) / 1_000);
    }
    
    /// Get the step number (micro component)
    pub fn getStep(self: PipelineSteps) u16 {
        return @intCast(@intFromEnum(self) % 1_000);
    }
    
    /// Format as [XXX.YYY.ZZZ] string
    pub fn format(self: PipelineSteps, buf: []u8) ![]const u8 {
        return std.fmt.bufPrint(buf, "[{d:0>3}.{d:0>3}.{d:0>3}]", .{
            self.getPhase(), self.getSection(), self.getStep()
        });
    }
    
    /// Get human-readable description
    pub fn getDescription(self: PipelineSteps) []const u8 {
        return switch (self) {
            .INIT_START => "Initialize MIDI to MXL converter",
            .INIT_PARSE_ARGS => "Parse command-line arguments",
            .INIT_SETUP_LOGGING => "Setup logging system",
            .INIT_SETUP_ERROR_HANDLER => "Setup error handler",
            .INIT_SETUP_VERBOSE_LOGGER => "Setup verbose logger",
            .INIT_PARSE_CONFIG => "Parse pipeline configuration",
            .INIT_SETUP_ALLOCATORS => "Setup memory allocators",
            
            .FILE_READ_START => "Start file operations",
            .FILE_OPEN => "Open MIDI input file",
            .FILE_READ_CONTENT => "Read MIDI file content",
            .FILE_VALIDATE_SIZE => "Validate file size",
            .FILE_VALIDATE_FORMAT => "Validate MIDI format",
            
            .MIDI_PARSE_START => "Start MIDI parsing",
            .MIDI_PARSE_HEADER => "Parse MIDI header",
            .MIDI_PARSE_TRACKS => "Parse MIDI tracks", 
            .MIDI_PARSE_EVENTS => "Parse MIDI events",
            .MIDI_VALIDATE_STRUCTURE => "Validate MIDI structure",
            .MIDI_CREATE_CONTAINER => "Create multi-track container",
            .MIDI_CREATE_PARTS => "Create parts from tracks",
            
            .TIMING_START => "Start timing conversion",
            .TIMING_DIVISION_SETUP => "Setup division converter",
            .TIMING_NOTE_DURATION_TRACKING => "Track note durations",
            .TIMING_CONVERT_TO_TIMED_NOTES => "Convert to timed notes",
            .TIMING_VALIDATE_DURATIONS => "Validate note durations",
            
            .VOICE_START => "Start voice assignment",
            .VOICE_ALLOCATOR_INIT => "Initialize voice allocator",
            .VOICE_ASSIGNMENT => "Assign voices to notes",
            .VOICE_VALIDATION => "Validate voice assignments",
            
            .MEASURE_START => "Start measure detection",
            .MEASURE_BOUNDARY_DETECTION => "Detect measure boundaries",
            .MEASURE_TIME_SIGNATURE_EXTRACTION => "Extract time signatures",
            .MEASURE_ORGANIZATION => "Organize measures",
            .MEASURE_VALIDATION => "Validate measure structure",
            
            .EDU_START => "Start educational processing",
            .EDU_ARENA_INIT => "Initialize educational arena",
            .EDU_PROCESSOR_INIT => "Initialize educational processor",
            .EDU_CONVERT_TO_ENHANCED_NOTES => "Convert to enhanced notes",
            
            .EDU_TUPLET_DETECTION_START => "Start tuplet detection",
            .EDU_TUPLET_ANALYSIS => "Analyze tuplet patterns",
            .EDU_TUPLET_PATTERN_MATCHING => "Match tuplet patterns",
            .EDU_TUPLET_VALIDATION => "Validate tuplet detection",
            .EDU_TUPLET_METADATA_ASSIGNMENT => "Assign tuplet metadata",
            
            .EDU_BEAM_GROUPING_START => "Start beam grouping",
            .EDU_BEAM_ANALYSIS => "Analyze beam patterns",
            .EDU_BEAM_GROUP_FORMATION => "Form beam groups",
            .EDU_BEAM_TUPLET_COORDINATION => "Coordinate beams with tuplets",
            .EDU_BEAM_METADATA_ASSIGNMENT => "Assign beam metadata",
            
            .EDU_REST_OPTIMIZATION_START => "Start rest optimization",
            .EDU_REST_ANALYSIS => "Analyze rest patterns",
            .EDU_REST_CONSOLIDATION => "Consolidate rests",
            .EDU_REST_BEAM_COORDINATION => "Coordinate rests with beams",
            .EDU_REST_METADATA_ASSIGNMENT => "Assign rest metadata",
            
            .EDU_DYNAMICS_MAPPING_START => "Start dynamics mapping",
            .EDU_DYNAMICS_VELOCITY_ANALYSIS => "Analyze velocity dynamics",
            .EDU_DYNAMICS_MARKING_ASSIGNMENT => "Assign dynamic markings",
            .EDU_DYNAMICS_CONTEXT_ANALYSIS => "Analyze dynamic context",
            .EDU_DYNAMICS_METADATA_ASSIGNMENT => "Assign dynamics metadata",
            
            .EDU_STEM_DIRECTION_START => "Start stem direction processing",
            .EDU_STEM_PITCH_ANALYSIS => "Analyze stem pitch positioning",
            .EDU_STEM_BEAM_COORDINATION => "Coordinate stems with beams",
            .EDU_STEM_VOICE_COORDINATION => "Coordinate stems with voices",
            .EDU_STEM_METADATA_ASSIGNMENT => "Assign stem metadata",
            
            .EDU_COORDINATION_START => "Start feature coordination",
            .EDU_COORDINATION_CONFLICT_DETECTION => "Detect feature conflicts",
            .EDU_COORDINATION_CONFLICT_RESOLUTION => "Resolve feature conflicts",
            .EDU_COORDINATION_VALIDATION => "Validate coordination",
            .EDU_COORDINATION_METADATA_FINALIZATION => "Finalize coordination metadata",
            
            .EDU_PERFORMANCE_MONITORING => "Monitor educational performance",
            .EDU_MEMORY_CLEANUP => "Cleanup educational memory",
            .EDU_METRICS_COLLECTION => "Collect educational metrics",
            
            .MXL_START => "Start MusicXML generation",
            .MXL_GENERATOR_INIT => "Initialize MXL generator",
            .MXL_HEADER_GENERATION => "Generate MusicXML header",
            .MXL_PART_LIST_GENERATION => "Generate part list",
            .MXL_SCORE_PART_GENERATION => "Generate score parts",
            .MXL_MEASURE_GENERATION => "Generate measures",
            .MXL_NOTE_GENERATION => "Generate notes",
            .MXL_ENHANCED_NOTE_PROCESSING => "Process enhanced notes",
            .MXL_TUPLET_XML_GENERATION => "Generate tuplet XML",
            .MXL_BEAM_XML_GENERATION => "Generate beam XML",
            .MXL_DYNAMICS_XML_GENERATION => "Generate dynamics XML",
            .MXL_REST_XML_GENERATION => "Generate rest XML",
            .MXL_STEM_XML_GENERATION => "Generate stem XML",
            .MXL_VALIDATION => "Validate MusicXML output",
            
            .MXL_ARCHIVE_START => "Start MXL archive creation",
            .MXL_ZIP_WRITER_INIT => "Initialize ZIP writer",
            .MXL_ADD_MUSICXML_FILE => "Add MusicXML file to archive",
            .MXL_CREATE_CONTAINER_XML => "Create container XML",
            .MXL_ADD_CONTAINER_XML => "Add container XML to archive",
            .MXL_FINALIZE_ARCHIVE => "Finalize MXL archive",
            
            .FINAL_START => "Start finalization",
            .FINAL_PRECISION_WARNINGS => "Report precision warnings",
            .FINAL_ERROR_REPORTING => "Report errors",
            .FINAL_METRICS_REPORTING => "Report metrics",
            .FINAL_CLEANUP => "Final cleanup",
            .FINAL_SUCCESS => "Conversion completed successfully",
        };
    }
};

/// Pipeline step execution registry for tracking completion and verification
/// Implements TASK-VL-007 per VERBOSE_LOGGING_TASK_LIST.md lines 315-325
pub const StepRegistry = struct {
    /// HashMap tracking which steps have been executed
    executed_steps: containers.AutoMap(PipelineSteps, StepExecution),
    /// Allocator for the registry
    allocator: std.mem.Allocator,
    /// Mutex for thread-safe step marking
    mutex: std.Thread.Mutex,
    /// Start time for execution timing
    start_time: i64,
    /// Statistics
    total_steps_expected: u32,
    required_steps_expected: u32,
    
    /// Information about step execution
    pub const StepExecution = struct {
        /// Whether this step was executed
        executed: bool = false,
        /// Timestamp when step was executed (nanoseconds since start)
        execution_time_ns: i64 = 0,
        /// Duration of step execution (nanoseconds) 
        duration_ns: u64 = 0,
        /// Whether this step is required for successful conversion
        is_required: bool = true,
        /// Error that occurred during step (if any)
        error_info: ?[]const u8 = null,
    };
    
    /// Initialize the step registry
    pub fn init(allocator: std.mem.Allocator) StepRegistry {
        return .{
            .executed_steps = containers.AutoMap(PipelineSteps, StepExecution).init(allocator),
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
            .start_time = @as(i64, @intCast(std.time.nanoTimestamp())),
            .total_steps_expected = 0,
            .required_steps_expected = 0,
        };
    }
    
    /// Deinitialize the registry and free resources
    pub fn deinit(self: *StepRegistry) void {
        self.cleanupErrorStrings();
        self.executed_steps.deinit();
    }
    
    /// Clean up all allocated error info strings
    pub fn cleanupErrorStrings(self: *StepRegistry) void {
        var iterator = self.executed_steps.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.error_info) |error_str| {
                self.allocator.free(error_str);
                entry.value_ptr.error_info = null;
            }
        }
    }
    
    /// Mark a step as executed (thread-safe)
    pub fn markExecuted(self: *StepRegistry, step: PipelineSteps) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const current_time = @as(i64, @intCast(std.time.nanoTimestamp()));
        const execution_time = current_time - self.start_time;
        
        const result = self.executed_steps.getOrPut(step) catch return;
        if (!result.found_existing) {
            result.value_ptr.* = StepExecution{};
        }
        
        result.value_ptr.executed = true;
        result.value_ptr.execution_time_ns = execution_time;
        result.value_ptr.is_required = self.isRequiredStep(step);
    }
    
    /// Mark a step as executed with timing information (thread-safe)
    pub fn markExecutedWithTiming(self: *StepRegistry, step: PipelineSteps, duration_ns: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const current_time = @as(i64, @intCast(std.time.nanoTimestamp()));
        const execution_time = current_time - self.start_time;
        
        const result = self.executed_steps.getOrPut(step) catch return;
        if (!result.found_existing) {
            result.value_ptr.* = StepExecution{};
        }
        
        result.value_ptr.executed = true;
        result.value_ptr.execution_time_ns = execution_time;
        result.value_ptr.duration_ns = duration_ns;
        result.value_ptr.is_required = self.isRequiredStep(step);
    }
    
    /// Mark a step as failed with error information (thread-safe)
    pub fn markFailed(self: *StepRegistry, step: PipelineSteps, error_msg: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const current_time = @as(i64, @intCast(std.time.nanoTimestamp()));
        const execution_time = current_time - self.start_time;
        
        const result = self.executed_steps.getOrPut(step) catch return;
        if (!result.found_existing) {
            result.value_ptr.* = StepExecution{};
        } else {
            // Free existing error_info to prevent leak
            if (result.value_ptr.error_info) |existing_error| {
                self.allocator.free(existing_error);
            }
        }
        
        result.value_ptr.executed = false;
        result.value_ptr.execution_time_ns = execution_time;
        result.value_ptr.is_required = self.isRequiredStep(step);
        result.value_ptr.error_info = self.allocator.dupe(u8, error_msg) catch null;
    }
    
    /// Check if a specific step was executed
    pub fn wasExecuted(self: *const StepRegistry, step: PipelineSteps) bool {
        // Use @constCast for thread-safe access to the mutex
        const self_mut = @constCast(self);
        self_mut.mutex.lock();
        defer self_mut.mutex.unlock();
        
        if (self.executed_steps.get(step)) |execution| {
            return execution.executed;
        }
        return false;
    }
    
    /// Get execution information for a step
    pub fn getStepExecution(self: *const StepRegistry, step: PipelineSteps) ?StepExecution {
        // Use @constCast for thread-safe access to the mutex
        const self_mut = @constCast(self);
        self_mut.mutex.lock();
        defer self_mut.mutex.unlock();
        
        return self.executed_steps.get(step);
    }
    
    /// Verify that all required steps were executed
    pub fn verifyAllRequiredExecuted(self: *const StepRegistry) !void {
        // Use @constCast for thread-safe access to the mutex
        const self_mut = @constCast(self);
        self_mut.mutex.lock();
        defer self_mut.mutex.unlock();
        
        const required_steps = self.getRequiredSteps();
        
        for (required_steps) |required_step| {
            if (self.executed_steps.get(required_step)) |execution| {
                if (!execution.executed) {
                    std.log.err("Required step not executed: {s}", .{required_step.getDescription()});
                    return error.RequiredStepNotExecuted;
                }
            } else {
                std.log.err("Required step not tracked: {s}", .{required_step.getDescription()});
                return error.RequiredStepNotTracked;
            }
        }
    }
    
    /// Get list of all required steps for a basic conversion
    /// Optional steps (voice assignment, measure detection, educational processing) are not included
    fn getRequiredSteps(self: *const StepRegistry) []const PipelineSteps {
        _ = self; // Suppress unused parameter warning
        return &[_]PipelineSteps{
            // Initialization is always required
            .INIT_START,
            .INIT_PARSE_ARGS,
            .INIT_SETUP_LOGGING,
            
            // File operations are always required
            .FILE_READ_START,
            .FILE_OPEN,
            .FILE_READ_CONTENT,
            
            // MIDI parsing is always required
            .MIDI_PARSE_START,
            .MIDI_PARSE_HEADER,
            .MIDI_PARSE_TRACKS,
            .MIDI_CREATE_CONTAINER,
            
            // Timing conversion is always required
            .TIMING_START,
            .TIMING_CONVERT_TO_TIMED_NOTES,
            
            // MusicXML generation is always required
            .MXL_START,
            .MXL_GENERATOR_INIT,
            .MXL_NOTE_GENERATION,
            
            // MXL archive creation is always required
            .MXL_ARCHIVE_START,
            .MXL_ADD_MUSICXML_FILE,
            .MXL_FINALIZE_ARCHIVE,
            
            // Finalization is always required
            .FINAL_SUCCESS,
        };
    }
    
    /// Check if a step is considered required for basic conversion
    fn isRequiredStep(self: *const StepRegistry, step: PipelineSteps) bool {
        const required_steps = self.getRequiredSteps();
        for (required_steps) |required_step| {
            if (step == required_step) return true;
        }
        return false;
    }
    
    /// Get execution statistics
    pub fn getExecutionStats(self: *const StepRegistry) ExecutionStats {
        // Use @constCast for thread-safe access to the mutex
        const self_mut = @constCast(self);
        self_mut.mutex.lock();
        defer self_mut.mutex.unlock();
        
        var stats = ExecutionStats{};
        
        var iterator = self.executed_steps.iterator();
        while (iterator.next()) |entry| {
            const execution = entry.value_ptr.*;
            
            if (execution.executed) {
                stats.executed_count += 1;
                if (execution.is_required) {
                    stats.required_executed += 1;
                } else {
                    stats.optional_executed += 1;
                }
                
                stats.total_execution_time_ns += execution.duration_ns;
                if (execution.duration_ns > stats.longest_step_duration_ns) {
                    stats.longest_step_duration_ns = execution.duration_ns;
                    stats.longest_step = entry.key_ptr.*;
                }
            } else {
                stats.failed_count += 1;
                if (execution.is_required) {
                    stats.required_failed += 1;
                } else {
                    stats.optional_failed += 1;
                }
            }
        }
        
        return stats;
    }
    
    /// Execution statistics
    pub const ExecutionStats = struct {
        executed_count: u32 = 0,
        failed_count: u32 = 0,
        required_executed: u32 = 0,
        required_failed: u32 = 0,
        optional_executed: u32 = 0,
        optional_failed: u32 = 0,
        total_execution_time_ns: u64 = 0,
        longest_step_duration_ns: u64 = 0,
        longest_step: ?PipelineSteps = null,
        
        /// Calculate success rate
        pub fn getSuccessRate(self: ExecutionStats) f64 {
            const total = self.executed_count + self.failed_count;
            if (total == 0) return 0.0;
            return @as(f64, @floatFromInt(self.executed_count)) / @as(f64, @floatFromInt(total));
        }
        
        /// Check if all required steps were executed
        pub fn allRequiredExecuted(self: ExecutionStats) bool {
            return self.required_failed == 0;
        }
    };
    
    /// Generate execution report
    pub fn generateReport(self: *const StepRegistry, writer: anytype) !void {
        // Use @constCast for thread-safe access to the mutex
        const self_mut = @constCast(self);
        self_mut.mutex.lock();
        defer self_mut.mutex.unlock();
        
        // Calculate stats directly here to avoid deadlock
        var stats = ExecutionStats{};
        
        var iterator = self.executed_steps.iterator();
        while (iterator.next()) |entry| {
            const execution = entry.value_ptr.*;
            
            if (execution.executed) {
                stats.executed_count += 1;
                if (execution.is_required) {
                    stats.required_executed += 1;
                } else {
                    stats.optional_executed += 1;
                }
                
                stats.total_execution_time_ns += execution.duration_ns;
                if (execution.duration_ns > stats.longest_step_duration_ns) {
                    stats.longest_step_duration_ns = execution.duration_ns;
                    stats.longest_step = entry.key_ptr.*;
                }
            } else {
                stats.failed_count += 1;
                if (execution.is_required) {
                    stats.required_failed += 1;
                } else {
                    stats.optional_failed += 1;
                }
            }
        }
        
        try writer.print("\n", .{});
        try writer.print("╔═══════════════════════════════════════════════════════════════════╗\n", .{});
        try writer.print("║                     PIPELINE EXECUTION REPORT                    ║\n", .{});
        try writer.print("╚═══════════════════════════════════════════════════════════════════╝\n", .{});
        try writer.print("\n", .{});
        
        try writer.print("EXECUTION SUMMARY:\n", .{});
        try writer.print("  Steps executed: {} / {}\n", .{ stats.executed_count, stats.executed_count + stats.failed_count });
        try writer.print("  Success rate: {d:.1}%\n", .{ stats.getSuccessRate() * 100.0 });
        try writer.print("  Required steps: {} executed, {} failed\n", .{ stats.required_executed, stats.required_failed });
        try writer.print("  Optional steps: {} executed, {} failed\n", .{ stats.optional_executed, stats.optional_failed });
        try writer.print("  Total execution time: {d:.2}ms\n", .{ @as(f64, @floatFromInt(stats.total_execution_time_ns)) / 1_000_000.0 });
        
        if (stats.longest_step) |longest| {
            try writer.print("  Longest step: {s} ({d:.2}ms)\n", .{ 
                longest.getDescription(), 
                @as(f64, @floatFromInt(stats.longest_step_duration_ns)) / 1_000_000.0 
            });
        }
        
        if (stats.failed_count > 0) {
            try writer.print("\nFAILED STEPS:\n", .{});
            var failed_iterator = self.executed_steps.iterator();
            while (failed_iterator.next()) |entry| {
                const step = entry.key_ptr.*;
                const execution = entry.value_ptr.*;
                
                if (!execution.executed) {
                    var buf: [32]u8 = undefined;
                    const step_id = try step.format(&buf);
                    try writer.print("  {s} {s}", .{ step_id, step.getDescription() });
                    if (execution.error_info) |error_msg| {
                        try writer.print(" - {s}", .{error_msg});
                    }
                    try writer.print("\n", .{});
                }
            }
        }
        
        try writer.print("\n", .{});
        
        if (stats.allRequiredExecuted()) {
            try writer.print("✅ All required pipeline steps completed successfully\n", .{});
        } else {
            try writer.print("❌ Some required pipeline steps failed\n", .{});
        }
        
        try writer.print("\n", .{});
    }
};

/// Verbose logging system for step-by-step execution tracking
/// Provides numbered steps and detailed progress information
pub const VerboseLogger = struct {
    enabled: bool,
    current_step: u32,
    indent_level: u8,
    start_time: i64,
    logger: *log_mod.Logger,
    precision_monitor: PrecisionMonitor,
    allocator: std.mem.Allocator,
    step_id: StepID,
    step_mutex: std.Thread.Mutex, // For thread-safe step ID incrementation
    /// Pipeline step registry for comprehensive tracking (TASK-VL-007)
    step_registry: StepRegistry,
    
    const Self = @This();
    
    /// Initialize the verbose logger with optional precision tracking
    pub fn init(allocator: std.mem.Allocator, enabled: bool, track_precision: bool) Self {
        return .{
            .enabled = enabled,
            .current_step = 0,
            .indent_level = 0,
            .start_time = @intCast(std.time.milliTimestamp()),
            .logger = log_mod.getLogger(),
            .precision_monitor = PrecisionMonitor.init(allocator, track_precision),
            .allocator = allocator,
            .step_id = .{ .major = 0, .minor = 0, .micro = 0 },
            .step_mutex = std.Thread.Mutex{},
            .step_registry = StepRegistry.init(allocator),
        };
    }
    
    /// Deinitialize and clean up resources
    pub fn deinit(self: *Self) void {
        // Clean up all allocated error strings before deinitializing
        self.step_registry.cleanupErrorStrings();
        self.precision_monitor.deinit();
        self.step_registry.deinit();
    }
    
    /// Start a major section
    pub fn startSection(self: *Self, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) return;
        
        self.current_step += 1;
        const indent = self.getIndent();
        self.logger.info("{s}[STEP {:0>3}] " ++ format, .{indent, self.current_step} ++ args);
        self.indent_level += 1;
    }
    
    /// End a major section
    pub fn endSection(self: *Self, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) return;
        
        if (self.indent_level > 0) self.indent_level -= 1;
        const indent = self.getIndent();
        const elapsed = std.time.milliTimestamp() - self.start_time;
        self.logger.info("{s}[COMPLETE] " ++ format ++ " ({}ms total)", .{indent} ++ args ++ .{elapsed});
    }
    
    /// Log a detailed step
    pub fn step(self: *Self, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) return;
        
        self.current_step += 1;
        const indent = self.getIndent();
        self.logger.debug("{s}[{:0>3}] " ++ format, .{indent, self.current_step} ++ args);
    }
    
    /// Log data details
    pub fn data(self: *Self, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) return;
        
        const indent = self.getIndent();
        self.logger.trace("{s}      " ++ format, .{indent} ++ args);
    }
    
    /// Log timing information
    pub fn timing(self: *Self, operation: []const u8, duration_ns: u64) void {
        if (!self.enabled) return;
        
        const indent = self.getIndent();
        const us = @as(f64, @floatFromInt(duration_ns)) / 1000.0;
        const ms = us / 1000.0;
        
        if (ms > 1.0) {
            self.logger.debug("{s}[TIMING] {s}: {d:.2}ms", .{ indent, operation, ms });
        } else {
            self.logger.debug("{s}[TIMING] {s}: {d:.2}μs", .{ indent, operation, us });
        }
    }
    
    /// Log memory usage
    pub fn memory(self: *Self, operation: []const u8, bytes: usize) void {
        if (!self.enabled) return;
        
        const indent = self.getIndent();
        if (bytes > 1024 * 1024) {
            const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
            self.logger.debug("{s}[MEMORY] {s}: {d:.2}MB", .{ indent, operation, mb });
        } else if (bytes > 1024) {
            const kb = @as(f64, @floatFromInt(bytes)) / 1024.0;
            self.logger.debug("{s}[MEMORY] {s}: {d:.2}KB", .{ indent, operation, kb });
        } else {
            self.logger.debug("{s}[MEMORY] {s}: {} bytes", .{ indent, operation, bytes });
        }
    }
    
    /// Log error with context
    pub fn errorContext(self: *Self, err: anyerror, context: []const u8) void {
        if (!self.enabled) return;
        
        const indent = self.getIndent();
        self.logger.err("{s}[ERROR at step {}] {}: {}", .{ indent, self.current_step, context, err });
    }
    
    /// Log warning
    pub fn warning(self: *Self, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) return;
        
        const indent = self.getIndent();
        self.logger.warn("{s}[WARNING] " ++ format, .{indent} ++ args);
    }
    
    /// Get current indentation string
    fn getIndent(self: *const Self) []const u8 {
        const spaces = "                    "; // 20 spaces max
        const level = @min(self.indent_level * 2, 20);
        return spaces[0..level];
    }
    
    /// Start a major pipeline phase (increments major step)
    /// Thread-safe step ID incrementation
    pub fn startMajorPhase(self: *Self, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) return;
        
        self.step_mutex.lock();
        defer self.step_mutex.unlock();
        
        self.step_id.next(.major);
        var buf: [32]u8 = undefined;
        const step_str = self.step_id.format(&buf) catch "[???]";
        
        const indent = self.getIndent();
        self.logger.info("{s}{s} " ++ format, .{indent, step_str} ++ args);
        self.indent_level += 1;
    }
    
    /// Start a minor step within a phase (increments minor step)
    pub fn startMinorStep(self: *Self, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) return;
        
        self.step_mutex.lock();
        defer self.step_mutex.unlock();
        
        self.step_id.next(.minor);
        var buf: [32]u8 = undefined;
        const step_str = self.step_id.format(&buf) catch "[???]";
        
        const indent = self.getIndent();
        self.logger.debug("{s}{s} " ++ format, .{indent, step_str} ++ args);
        self.indent_level += 1;
    }
    
    /// Log a micro step (detailed operation)
    pub fn microStep(self: *Self, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) return;
        
        self.step_mutex.lock();
        defer self.step_mutex.unlock();
        
        self.step_id.next(.micro);
        var buf: [32]u8 = undefined;
        const step_str = self.step_id.format(&buf) catch "[???]";
        
        const indent = self.getIndent();
        self.logger.trace("{s}{s} " ++ format, .{indent, step_str} ++ args);
    }
    
    /// End a section (major or minor) and decrease indent
    pub fn endSectionWithId(self: *Self, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) return;
        
        if (self.indent_level > 0) self.indent_level -= 1;
        
        self.step_mutex.lock();
        const current_id = self.step_id.clone();
        self.step_mutex.unlock();
        
        var buf: [32]u8 = undefined;
        const step_str = current_id.format(&buf) catch "[???]";
        
        const indent = self.getIndent();
        const elapsed = std.time.milliTimestamp() - self.start_time;
        self.logger.info("{s}{s} [COMPLETE] " ++ format ++ " ({}ms total)", .{indent, step_str} ++ args ++ .{elapsed});
    }
    
    /// Get a copy of the current step ID (thread-safe)
    pub fn getCurrentStepId(self: *Self) StepID {
        self.step_mutex.lock();
        defer self.step_mutex.unlock();
        return self.step_id.clone();
    }
    
    /// Reset step ID to [000.000.000] (useful for testing)
    pub fn resetStepId(self: *Self) void {
        self.step_mutex.lock();
        defer self.step_mutex.unlock();
        self.step_id.reset();
    }
    
    /// Log with custom step ID format (without incrementing)
    pub fn logWithStepId(self: *Self, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) return;
        
        self.step_mutex.lock();
        const current_id = self.step_id.clone();
        self.step_mutex.unlock();
        
        var buf: [32]u8 = undefined;
        const step_str = current_id.format(&buf) catch "[???]";
        
        const indent = self.getIndent();
        self.logger.debug("{s}{s} " ++ format, .{indent, step_str} ++ args);
    }
    
    /// Report precision warnings with enhanced formatting
    /// Implements TASK-VL-004 warning output per VERBOSE_LOGGING_TASK_LIST.md lines 167-197
    pub fn reportPrecisionWarnings(self: *const Self) void {
        // Show precision warnings if precision tracking is enabled, regardless of verbose logging
        if (!self.precision_monitor.enabled or self.precision_monitor.warnings.items.len == 0) return;
        
        // Group warnings by operation type
        var op_groups = containers.StrMap(containers.List(PrecisionMonitor.PrecisionWarning)).init(self.allocator);
        defer {
            var it = op_groups.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit();
            }
            op_groups.deinit();
        }
        
        // Group warnings
        for (self.precision_monitor.warnings.items) |precision_warning| {
            const result = op_groups.getOrPut(precision_warning.operation) catch continue;
            if (!result.found_existing) {
                result.value_ptr.* = containers.List(PrecisionMonitor.PrecisionWarning).init(self.allocator);
            }
            result.value_ptr.append(precision_warning) catch continue;
        }
        
        // Report summary
        self.logger.warn("", .{}); // Empty line for visibility
        self.logger.warn("╔═══════════════════════════════════════════════════════════════════╗", .{});
        self.logger.warn("║             PRECISION LOSS DETECTED - TIMING CORRUPTION           ║", .{});
        self.logger.warn("╚═══════════════════════════════════════════════════════════════════╝", .{});
        self.logger.warn("", .{});
        self.logger.warn("⚠️  The following precision losses may cause MusicXML timing errors", .{});
        self.logger.warn("   such as incorrect measure durations or corrupt note positions.", .{});
        self.logger.warn("", .{});
        
        var total_loss: f64 = 0.0;
        var max_loss: f64 = 0.0;
        var critical_count: usize = 0;
        
        // Report by operation type
        var it = op_groups.iterator();
        while (it.next()) |entry| {
            const operation = entry.key_ptr.*;
            const warnings = entry.value_ptr.*;
            
            self.logger.warn("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", .{});
            self.logger.warn("Operation: {s} ({} occurrences)", .{ operation, warnings.items.len });
            self.logger.warn("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", .{});
            
            // Show up to 3 examples per operation type
            const examples_to_show = @min(warnings.items.len, 3);
            for (warnings.items[0..examples_to_show], 0..) |warn, idx| {
                // Format timestamp
                const timestamp_s = @as(f64, @floatFromInt(warn.timestamp_ns)) / 1_000_000_000.0;
                
                self.logger.warn("  Example {}:", .{idx + 1});
                self.logger.warn("    📍 Location: {s} in {s}() at line {}", .{
                    warn.location.file,
                    warn.location.function,
                    warn.location.line,
                });
                self.logger.warn("    ⏱️  Time: {d:.3}s into conversion", .{timestamp_s});
                self.logger.warn("    📊 Values:", .{});
                self.logger.warn("       Input:    {d:.10}", .{warn.input});
                self.logger.warn("       Expected: {d:.10}", .{warn.expected});
                self.logger.warn("       Actual:   {d:.10}", .{warn.actual});
                self.logger.warn("       Loss:     {d:.6}% ({s})", .{
                    warn.loss_percent,
                    if (warn.loss_percent > 1.0) "CRITICAL" else if (warn.loss_percent > 0.1) "HIGH" else "LOW",
                });
                
                // Add specific guidance based on the values
                if (std.mem.eql(u8, operation, "convertTicksToDivisions")) {
                    const fraction_input = self.formatAsFraction(warn.input) catch "?";
                    defer if (!std.mem.eql(u8, fraction_input, "?")) self.allocator.free(fraction_input);
                    
                    const fraction_expected = self.formatAsFraction(warn.expected) catch "?";
                    defer if (!std.mem.eql(u8, fraction_expected, "?")) self.allocator.free(fraction_expected);
                    
                    const fraction_actual = self.formatAsFraction(warn.actual) catch "?";
                    defer if (!std.mem.eql(u8, fraction_actual, "?")) self.allocator.free(fraction_actual);
                    
                    self.logger.warn("    💡 Fraction representation:", .{});
                    self.logger.warn("       Input:    {s}", .{fraction_input});
                    self.logger.warn("       Expected: {s}", .{fraction_expected});
                    self.logger.warn("       Actual:   {s}", .{fraction_actual});
                    
                    if (warn.loss_percent > 0.1) {
                        self.logger.warn("    ⚠️  This precision loss may cause the '129/256 Expected: 65/128' error", .{});
                    }
                }
                
                self.logger.warn("", .{});
                
                // Track statistics
                total_loss += warn.loss_percent;
                max_loss = @max(max_loss, warn.loss_percent);
                if (warn.loss_percent > 1.0) critical_count += 1;
            }
            
            if (warnings.items.len > examples_to_show) {
                self.logger.warn("    ... and {} more instances", .{warnings.items.len - examples_to_show});
                self.logger.warn("", .{});
            }
        }
        
        // Summary statistics
        self.logger.warn("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", .{});
        self.logger.warn("SUMMARY", .{});
        self.logger.warn("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", .{});
        self.logger.warn("  Total warnings:     {}", .{self.precision_monitor.warnings.items.len});
        self.logger.warn("  Critical warnings:  {} (> 1% loss)", .{critical_count});
        self.logger.warn("  Maximum loss:       {d:.6}%", .{max_loss});
        self.logger.warn("  Average loss:       {d:.6}%", .{
            if (self.precision_monitor.warnings.items.len > 0)
                total_loss / @as(f64, @floatFromInt(self.precision_monitor.warnings.items.len))
            else
                0.0,
        });
        self.logger.warn("", .{});
        
        // Recommendations
        if (critical_count > 0) {
            self.logger.warn("🔴 CRITICAL: Precision losses detected that will likely corrupt MusicXML output!", .{});
            self.logger.warn("   Recommendation: Review the conversion ratios and consider using higher precision", .{});
            self.logger.warn("   divisions or adjusting the MIDI PPQ to MusicXML divisions mapping.", .{});
        } else if (max_loss > 0.1) {
            self.logger.warn("🟡 WARNING: Minor precision losses detected that may affect timing accuracy.", .{});
            self.logger.warn("   The output should be playable but may have subtle timing differences.", .{});
        } else {
            self.logger.warn("🟢 INFO: Minimal precision loss detected, output should be accurate.", .{});
        }
        self.logger.warn("", .{});
    }
    
    /// Helper to format a float as a fraction for better readability
    fn formatAsFraction(self: *const Self, value: f64) ![]const u8 {
        // Common musical fractions to check
        const common_fractions = [_]struct { num: f64, den: f64, tolerance: f64 }{
            .{ .num = 1, .den = 2, .tolerance = 0.0001 },   // 1/2
            .{ .num = 1, .den = 4, .tolerance = 0.0001 },   // 1/4
            .{ .num = 1, .den = 8, .tolerance = 0.0001 },   // 1/8
            .{ .num = 1, .den = 16, .tolerance = 0.0001 },  // 1/16
            .{ .num = 1, .den = 32, .tolerance = 0.0001 },  // 1/32
            .{ .num = 3, .den = 4, .tolerance = 0.0001 },   // 3/4
            .{ .num = 3, .den = 8, .tolerance = 0.0001 },   // 3/8
            .{ .num = 5, .den = 8, .tolerance = 0.0001 },   // 5/8
            .{ .num = 7, .den = 8, .tolerance = 0.0001 },   // 7/8
            .{ .num = 65, .den = 128, .tolerance = 0.0001 }, // From the error
            .{ .num = 129, .den = 256, .tolerance = 0.0001 }, // From the error
        };
        
        // Check against common fractions
        for (common_fractions) |frac| {
            const frac_value = frac.num / frac.den;
            if (@abs(value - frac_value) < frac.tolerance) {
                return std.fmt.allocPrint(self.allocator, "{d:.0}/{d:.0} ({d:.10})", .{ frac.num, frac.den, value });
            }
        }
        
        // For other values, try to find a reasonable fraction representation
        // This is a simple continued fraction approximation
        const max_denominator: u32 = 1000;
        var best_num: u32 = 0;
        var best_den: u32 = 1;
        var best_error: f64 = @abs(value);
        
        var den: u32 = 1;
        while (den <= max_denominator) : (den += 1) {
            const num = @as(u32, @intFromFloat(@round(value * @as(f64, @floatFromInt(den)))));
            const approx = @as(f64, @floatFromInt(num)) / @as(f64, @floatFromInt(den));
            const approx_error = @abs(value - approx);
            
            if (approx_error < best_error) {
                best_error = approx_error;
                best_num = num;
                best_den = den;
                
                // If we found an exact match (within floating point precision), stop
                if (approx_error < 1e-10) break;
            }
        }
        
        if (best_error < 0.001) {
            return std.fmt.allocPrint(self.allocator, "{}/{} ({d:.10})", .{ best_num, best_den, value });
        } else {
            return std.fmt.allocPrint(self.allocator, "{d:.10}", .{value});
        }
    }
    
    /// Create a scoped logger for subsystems
    pub fn scoped(self: *Self, name: []const u8) ScopedVerboseLogger {
        self.step_mutex.lock();
        const current_id = self.step_id.clone();
        self.step_mutex.unlock();
        
        return .{
            .parent = self,
            .name = name,
            .start_step = self.current_step,
            .start_step_id = current_id,
        };
    }
    
    /// Log a pipeline step with automatic registry tracking (TASK-VL-007)
    /// This is the primary method for tracking pipeline execution completeness
    pub fn pipelineStep(self: *Self, pipeline_step: PipelineSteps, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) {
            // Even when verbose logging is disabled, still track step execution for verification
            self.step_registry.markExecuted(pipeline_step);
            return;
        }
        
        // Mark step as executed in registry
        self.step_registry.markExecuted(pipeline_step);
        
        // Format the step ID and log with description
        var buf: [32]u8 = undefined;
        const step_str = pipeline_step.format(&buf) catch "[???.???.???]";
        
        const indent = self.getIndent();
        self.logger.info("{s}{s} {s}", .{ indent, step_str, pipeline_step.getDescription() });
        
        // Also log the custom format message if provided
        if (format.len > 0) {
            self.logger.debug("{s}      " ++ format, .{indent} ++ args);
        }
    }
    
    /// Log a pipeline step with timing information (TASK-VL-007)
    pub fn pipelineStepWithTiming(self: *Self, pipeline_step: PipelineSteps, duration_ns: u64, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) {
            // Even when verbose logging is disabled, still track step execution for verification
            self.step_registry.markExecutedWithTiming(pipeline_step, duration_ns);
            return;
        }
        
        // Mark step as executed with timing in registry
        self.step_registry.markExecutedWithTiming(pipeline_step, duration_ns);
        
        // Format the step ID and log with description and timing
        var buf: [32]u8 = undefined;
        const step_str = pipeline_step.format(&buf) catch "[???.???.???]";
        
        const indent = self.getIndent();
        const ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
        
        if (ms > 1.0) {
            self.logger.info("{s}{s} {s} ({d:.2}ms)", .{ indent, step_str, pipeline_step.getDescription(), ms });
        } else {
            const us = @as(f64, @floatFromInt(duration_ns)) / 1_000.0;
            self.logger.info("{s}{s} {s} ({d:.2}μs)", .{ indent, step_str, pipeline_step.getDescription(), us });
        }
        
        // Also log the custom format message if provided
        if (format.len > 0) {
            self.logger.debug("{s}      " ++ format, .{indent} ++ args);
        }
    }
    
    /// Mark a pipeline step as failed (TASK-VL-007)
    pub fn pipelineStepFailed(self: *Self, pipeline_step: PipelineSteps, error_msg: []const u8, comptime format: []const u8, args: anytype) void {
        // Always track failed steps regardless of verbose mode
        self.step_registry.markFailed(pipeline_step, error_msg);
        
        if (!self.enabled) return;
        
        // Format the step ID and log failure
        var buf: [32]u8 = undefined;
        const step_str = pipeline_step.format(&buf) catch "[???.???.???]";
        
        const indent = self.getIndent();
        self.logger.err("{s}{s} [FAILED] {s}: {s}", .{ indent, step_str, pipeline_step.getDescription(), error_msg });
        
        // Also log the custom format message if provided
        if (format.len > 0) {
            self.logger.debug("{s}      " ++ format, .{indent} ++ args);
        }
    }
    
    /// Check if a pipeline step was executed
    pub fn wasStepExecuted(self: *const Self, pipeline_step: PipelineSteps) bool {
        return self.step_registry.wasExecuted(pipeline_step);
    }
    
    /// Verify that all required pipeline steps were executed
    pub fn verifyPipelineCompletion(self: *const Self) !void {
        try self.step_registry.verifyAllRequiredExecuted();
    }
    
    /// Generate a comprehensive pipeline execution report
    /// This shows which steps were executed, failed, and provides timing statistics
    pub fn generatePipelineReport(self: *const Self) void {
        if (!self.enabled) return;
        
        // Use a buffer writer to capture the report
        var buffer: [8192]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const temp_allocator = fba.allocator();
        
        var string = containers.List(u8).init(temp_allocator);
        defer string.deinit();
        
        self.step_registry.generateReport(string.writer()) catch {
            self.logger.err("Failed to generate pipeline execution report", .{});
            return;
        };
        
        // Log the report line by line to integrate with the existing logging system
        const report = string.items;
        var lines = std.mem.splitSequence(u8, report, "\n");
        while (lines.next()) |line| {
            if (line.len > 0) {
                self.logger.info("{s}", .{line});
            } else {
                self.logger.info("", .{});
            }
        }
    }
    
    /// Get pipeline execution statistics
    pub fn getPipelineStats(self: *const Self) StepRegistry.ExecutionStats {
        return self.step_registry.getExecutionStats();
    }
};

/// Scoped verbose logger for subsystems
pub const ScopedVerboseLogger = struct {
    parent: *VerboseLogger,
    name: []const u8,
    start_step: u32,
    start_step_id: StepID,
    
    const Self = @This();
    
    pub fn step(self: *const Self, comptime format: []const u8, args: anytype) void {
        if (!self.parent.enabled) return;
        
        self.parent.current_step += 1;
        const indent = self.parent.getIndent();
        self.parent.logger.debug("{s}[{:0>3}] [{s}] " ++ format, .{ indent, self.parent.current_step, self.name } ++ args);
    }
    
    /// Log a minor step with hierarchical ID
    pub fn minorStep(self: *const Self, comptime format: []const u8, args: anytype) void {
        if (!self.parent.enabled) return;
        
        self.parent.step_mutex.lock();
        defer self.parent.step_mutex.unlock();
        
        self.parent.step_id.next(.minor);
        var buf: [32]u8 = undefined;
        const step_str = self.parent.step_id.format(&buf) catch "[???]";
        
        const indent = self.parent.getIndent();
        self.parent.logger.debug("{s}{s} [{s}] " ++ format, .{ indent, step_str, self.name } ++ args);
    }
    
    /// Log a micro step with hierarchical ID
    pub fn microStep(self: *const Self, comptime format: []const u8, args: anytype) void {
        if (!self.parent.enabled) return;
        
        self.parent.step_mutex.lock();
        defer self.parent.step_mutex.unlock();
        
        self.parent.step_id.next(.micro);
        var buf: [32]u8 = undefined;
        const step_str = self.parent.step_id.format(&buf) catch "[???]";
        
        const indent = self.parent.getIndent();
        self.parent.logger.trace("{s}{s} [{s}] " ++ format, .{ indent, step_str, self.name } ++ args);
    }
    
    pub fn data(self: *const Self, comptime format: []const u8, args: anytype) void {
        self.parent.data(format, args);
    }
    
    pub fn timing(self: *const Self, operation: []const u8, duration_ns: u64) void {
        const full_op = std.fmt.allocPrint(
            std.heap.page_allocator, 
            "{s}.{s}", 
            .{ self.name, operation }
        ) catch operation;
        defer if (full_op.ptr != operation.ptr) std.heap.page_allocator.free(full_op);
        
        self.parent.timing(full_op, duration_ns);
    }
    
    pub fn done(self: *const Self) void {
        if (!self.parent.enabled) return;
        
        const steps_used = self.parent.current_step - self.start_step;
        self.parent.logger.debug("{s}[{s}] Completed ({} steps)", .{ 
            self.parent.getIndent(), 
            self.name, 
            steps_used 
        });
    }
};

/// Configuration options for verbose logger initialization
pub const VerboseLoggerConfig = struct {
    enabled: bool = false,
    track_precision: bool = false,
    allocator: std.mem.Allocator = std.heap.page_allocator,
};

/// Global verbose logger instance
var global_verbose_logger: ?VerboseLogger = null;

/// Initialize global verbose logger with configuration
pub fn initGlobalVerboseLogger(config: VerboseLoggerConfig) void {
    // Clean up existing logger if any
    if (global_verbose_logger) |*logger| {
        logger.deinit();
    }
    
    global_verbose_logger = VerboseLogger.init(
        config.allocator,
        config.enabled,
        config.track_precision,
    );
}

/// Initialize global verbose logger (legacy compatibility)
pub fn initGlobalVerboseLoggerSimple(enabled: bool) void {
    initGlobalVerboseLogger(.{
        .enabled = enabled,
        .track_precision = false,
        .allocator = std.heap.page_allocator,
    });
}

/// Deinitialize global verbose logger
pub fn deinitGlobalVerboseLogger() void {
    if (global_verbose_logger) |*logger| {
        logger.deinit();
        global_verbose_logger = null;
    }
}

/// Get global verbose logger
pub fn getVerboseLogger() *VerboseLogger {
    if (global_verbose_logger == null) {
        global_verbose_logger = VerboseLogger.init(
            std.heap.page_allocator,
            false,
            false,
        );
    }
    return &global_verbose_logger.?;
}

// Convenience macros for common operations
pub const STEP_INIT = "Initialization";
pub const STEP_PARSE_ARGS = "Parse command-line arguments";
pub const STEP_READ_FILE = "Read MIDI file";
pub const STEP_PARSE_MIDI = "Parse MIDI structure";
pub const STEP_CONVERT_TIMING = "Convert timing information";
pub const STEP_DETECT_MEASURES = "Detect measure boundaries";
pub const STEP_EDUCATIONAL = "Educational feature processing";
pub const STEP_GENERATE_XML = "Generate MusicXML";
pub const STEP_CREATE_MXL = "Create MXL archive";
pub const STEP_FINALIZE = "Finalize output";

test "VerboseLogger basic functionality" {
    var vlogger = VerboseLogger.init(std.testing.allocator, true, false);
    defer vlogger.deinit();
    
    vlogger.startSection("Main conversion process", .{});
    vlogger.step("Reading input file", .{});
    vlogger.data("File size: {} bytes", .{1024});
    vlogger.timing("File read", 1500000); // 1.5ms
    vlogger.memory("MIDI data", 1024);
    
    const scoped = vlogger.scoped("MIDI Parser");
    scoped.step("Parsing header", .{});
    scoped.step("Parsing tracks", .{});
    scoped.timing("Parse", 500000); // 0.5ms
    scoped.done();
    
    vlogger.endSection("Conversion complete", .{});
    
    try std.testing.expect(vlogger.current_step > 0);
}

test "PrecisionMonitor basic functionality" {
    var monitor = PrecisionMonitor.init(std.testing.allocator, true);
    defer monitor.deinit();
    
    // Test exact operation tracking
    monitor.trackExactOperation(
        "test_exact",
        1.234,
        1.234,
        .{ .file = "test.zig", .function = "testFunc", .line = 42 },
    );
    try std.testing.expectEqual(@as(usize, 0), monitor.getWarningCount());
    
    // Test operation with precision loss
    monitor.trackExactOperation(
        "test_loss",
        1.234,
        1.235,
        .{ .file = "test.zig", .function = "testFunc", .line = 43 },
    );
    try std.testing.expectEqual(@as(usize, 1), monitor.getWarningCount());
    
    // Test threshold
    monitor.setThreshold(0.1); // 10% threshold
    monitor.trackOperation(
        "test_threshold",
        100.0,
        95.0,
        1.0, // expected_precision = 1.0 means output should equal input
        .{ .file = "test.zig", .function = "testFunc", .line = 44 },
    );
    // 5% loss is below 10% threshold, so no new warning
    try std.testing.expectEqual(@as(usize, 1), monitor.getWarningCount());
    
    // Clear warnings
    monitor.clearWarnings();
    try std.testing.expectEqual(@as(usize, 0), monitor.getWarningCount());
}

test "VerboseLogger with precision tracking" {
    var vlogger = VerboseLogger.init(std.testing.allocator, true, true);
    defer vlogger.deinit();
    
    // Track some precision loss
    vlogger.precision_monitor.trackExactOperation(
        "division_conversion",
        129.0/256.0,
        65.0/128.0,
        .{ .file = "test.zig", .function = "testConversion", .line = 100 },
    );
    
    // Should have a warning
    try std.testing.expect(vlogger.precision_monitor.getWarningCount() > 0);
    
    // Report warnings (output will go to test logs)
    vlogger.reportPrecisionWarnings();
}

test "StepID basic functionality" {
    var step_id = StepID{ .major = 0, .minor = 0, .micro = 0 };
    
    // Test initial state
    try std.testing.expectEqual(@as(u16, 0), step_id.major);
    try std.testing.expectEqual(@as(u16, 0), step_id.minor);
    try std.testing.expectEqual(@as(u16, 0), step_id.micro);
    
    // Test major increment
    step_id.next(.major);
    try std.testing.expectEqual(@as(u16, 1), step_id.major);
    try std.testing.expectEqual(@as(u16, 0), step_id.minor);
    try std.testing.expectEqual(@as(u16, 0), step_id.micro);
    
    // Add some minor steps
    step_id.next(.minor);
    step_id.next(.minor);
    try std.testing.expectEqual(@as(u16, 1), step_id.major);
    try std.testing.expectEqual(@as(u16, 2), step_id.minor);
    try std.testing.expectEqual(@as(u16, 0), step_id.micro);
    
    // Add micro steps
    step_id.next(.micro);
    step_id.next(.micro);
    step_id.next(.micro);
    try std.testing.expectEqual(@as(u16, 1), step_id.major);
    try std.testing.expectEqual(@as(u16, 2), step_id.minor);
    try std.testing.expectEqual(@as(u16, 3), step_id.micro);
    
    // Major increment should reset minor and micro
    step_id.next(.major);
    try std.testing.expectEqual(@as(u16, 2), step_id.major);
    try std.testing.expectEqual(@as(u16, 0), step_id.minor);
    try std.testing.expectEqual(@as(u16, 0), step_id.micro);
    
    // Test formatting
    var buf: [32]u8 = undefined;
    const formatted = try step_id.format(&buf);
    try std.testing.expectEqualStrings("[002.000.000]", formatted);
    
    // Test with non-zero values
    step_id.major = 123;
    step_id.minor = 45;
    step_id.micro = 678;
    const formatted2 = try step_id.format(&buf);
    try std.testing.expectEqualStrings("[123.045.678]", formatted2);
    
    // Test reset
    step_id.reset();
    try std.testing.expectEqual(@as(u16, 0), step_id.major);
    try std.testing.expectEqual(@as(u16, 0), step_id.minor);
    try std.testing.expectEqual(@as(u16, 0), step_id.micro);
    
    // Test clone
    step_id.major = 5;
    step_id.minor = 10;
    step_id.micro = 15;
    const cloned = step_id.clone();
    try std.testing.expect(step_id.equals(cloned));
    
    // Test total step count
    const total = step_id.getTotalStepCount();
    try std.testing.expectEqual(@as(u32, 5010015), total);
}

test "VerboseLogger with hierarchical step tracking" {
    var vlogger = VerboseLogger.init(std.testing.allocator, true, false);
    defer vlogger.deinit();
    
    // Test major phase
    vlogger.startMajorPhase("Starting MIDI parsing", .{});
    var current_id = vlogger.getCurrentStepId();
    try std.testing.expectEqual(@as(u16, 1), current_id.major);
    try std.testing.expectEqual(@as(u16, 0), current_id.minor);
    try std.testing.expectEqual(@as(u16, 0), current_id.micro);
    
    // Test minor steps
    vlogger.startMinorStep("Reading MIDI header", .{});
    current_id = vlogger.getCurrentStepId();
    try std.testing.expectEqual(@as(u16, 1), current_id.major);
    try std.testing.expectEqual(@as(u16, 1), current_id.minor);
    try std.testing.expectEqual(@as(u16, 0), current_id.micro);
    
    // Test micro steps
    vlogger.microStep("Parsing format type", .{});
    vlogger.microStep("Parsing track count", .{});
    vlogger.microStep("Parsing division", .{});
    current_id = vlogger.getCurrentStepId();
    try std.testing.expectEqual(@as(u16, 1), current_id.major);
    try std.testing.expectEqual(@as(u16, 1), current_id.minor);
    try std.testing.expectEqual(@as(u16, 3), current_id.micro);
    
    // End section and start new major phase
    vlogger.endSectionWithId("MIDI header parsed", .{});
    vlogger.startMajorPhase("Starting educational processing", .{});
    current_id = vlogger.getCurrentStepId();
    try std.testing.expectEqual(@as(u16, 2), current_id.major);
    try std.testing.expectEqual(@as(u16, 0), current_id.minor);
    try std.testing.expectEqual(@as(u16, 0), current_id.micro);
    
    // Test scoped logger
    const scoped = vlogger.scoped("TupletDetector");
    scoped.minorStep("Analyzing note groups", .{});
    scoped.microStep("Checking triplet pattern", .{});
    
    current_id = vlogger.getCurrentStepId();
    try std.testing.expectEqual(@as(u16, 2), current_id.major);
    try std.testing.expectEqual(@as(u16, 1), current_id.minor);
    try std.testing.expectEqual(@as(u16, 1), current_id.micro);
    
    // Test reset
    vlogger.resetStepId();
    current_id = vlogger.getCurrentStepId();
    try std.testing.expectEqual(@as(u16, 0), current_id.major);
    try std.testing.expectEqual(@as(u16, 0), current_id.minor);
    try std.testing.expectEqual(@as(u16, 0), current_id.micro);
}

test "PipelineSteps enum functionality" {
    // Test phase extraction
    try std.testing.expectEqual(@as(u16, 1), PipelineSteps.INIT_START.getPhase());
    try std.testing.expectEqual(@as(u16, 2), PipelineSteps.FILE_READ_START.getPhase());
    try std.testing.expectEqual(@as(u16, 7), PipelineSteps.EDU_START.getPhase());
    
    // Test section extraction
    try std.testing.expectEqual(@as(u16, 0), PipelineSteps.INIT_START.getSection());
    try std.testing.expectEqual(@as(u16, 1), PipelineSteps.INIT_PARSE_ARGS.getSection());
    try std.testing.expectEqual(@as(u16, 10), PipelineSteps.EDU_TUPLET_DETECTION_START.getSection());
    
    // Test step extraction
    try std.testing.expectEqual(@as(u16, 0), PipelineSteps.INIT_START.getStep());
    try std.testing.expectEqual(@as(u16, 1), PipelineSteps.EDU_TUPLET_ANALYSIS.getStep());
    try std.testing.expectEqual(@as(u16, 4), PipelineSteps.EDU_TUPLET_METADATA_ASSIGNMENT.getStep());
    
    // Test formatting
    var buf: [32]u8 = undefined;
    const formatted = try PipelineSteps.INIT_START.format(&buf);
    try std.testing.expectEqualStrings("[001.000.000]", formatted);
    
    const formatted2 = try PipelineSteps.EDU_TUPLET_ANALYSIS.format(&buf);
    try std.testing.expectEqualStrings("[007.010.001]", formatted2);
    
    // Test descriptions
    const desc = PipelineSteps.INIT_START.getDescription();
    try std.testing.expect(std.mem.indexOf(u8, desc, "Initialize") != null);
    
    const edu_desc = PipelineSteps.EDU_TUPLET_DETECTION_START.getDescription();
    try std.testing.expect(std.mem.indexOf(u8, edu_desc, "tuplet") != null);
}

test "StepRegistry basic functionality" {
    var registry = StepRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Test step marking
    try std.testing.expect(!registry.wasExecuted(.INIT_START));
    registry.markExecuted(.INIT_START);
    try std.testing.expect(registry.wasExecuted(.INIT_START));
    
    // Test step marking with timing
    registry.markExecutedWithTiming(.INIT_PARSE_ARGS, 1_500_000); // 1.5ms
    try std.testing.expect(registry.wasExecuted(.INIT_PARSE_ARGS));
    
    const execution = registry.getStepExecution(.INIT_PARSE_ARGS);
    try std.testing.expect(execution != null);
    try std.testing.expectEqual(@as(u64, 1_500_000), execution.?.duration_ns);
    
    // Test failed step marking
    registry.markFailed(.FILE_OPEN, "File not found");
    try std.testing.expect(!registry.wasExecuted(.FILE_OPEN));
    
    const failed_execution = registry.getStepExecution(.FILE_OPEN);
    try std.testing.expect(failed_execution != null);
    try std.testing.expect(!failed_execution.?.executed);
    try std.testing.expect(failed_execution.?.error_info != null);
    
    // Test statistics
    const stats = registry.getExecutionStats();
    try std.testing.expectEqual(@as(u32, 2), stats.executed_count);
    try std.testing.expectEqual(@as(u32, 1), stats.failed_count);
    try std.testing.expect(stats.total_execution_time_ns >= 1_500_000);
}

test "StepRegistry required step validation" {
    var registry = StepRegistry.init(std.testing.allocator);
    defer registry.deinit();
    
    // Mark only some required steps
    registry.markExecuted(.INIT_START);
    registry.markExecuted(.INIT_PARSE_ARGS);
    registry.markExecuted(.FILE_READ_START);
    
    // Should fail because not all required steps are marked
    try std.testing.expectError(error.RequiredStepNotTracked, registry.verifyAllRequiredExecuted());
    
    // Mark all required steps
    const required_steps = [_]PipelineSteps{
        .INIT_START,
        .INIT_PARSE_ARGS,
        .INIT_SETUP_LOGGING,
        .FILE_READ_START,
        .FILE_OPEN,
        .FILE_READ_CONTENT,
        .MIDI_PARSE_START,
        .MIDI_PARSE_HEADER,
        .MIDI_PARSE_TRACKS,
        .MIDI_CREATE_CONTAINER,
        .TIMING_START,
        .TIMING_CONVERT_TO_TIMED_NOTES,
        .MXL_START,
        .MXL_GENERATOR_INIT,
        .MXL_NOTE_GENERATION,
        .MXL_ARCHIVE_START,
        .MXL_ADD_MUSICXML_FILE,
        .MXL_FINALIZE_ARCHIVE,
        .FINAL_SUCCESS,
    };
    
    for (required_steps) |step| {
        registry.markExecuted(step);
    }
    
    // Should now pass
    try registry.verifyAllRequiredExecuted();
    
    const stats = registry.getExecutionStats();
    try std.testing.expect(stats.allRequiredExecuted());
}

test "VerboseLogger pipeline step integration" {
    var vlogger = VerboseLogger.init(std.testing.allocator, true, false);
    defer vlogger.deinit();
    
    // Test pipeline step logging
    vlogger.pipelineStep(.INIT_START, "", .{});
    try std.testing.expect(vlogger.wasStepExecuted(.INIT_START));
    
    // Test pipeline step with timing
    vlogger.pipelineStepWithTiming(.INIT_PARSE_ARGS, 2_000_000, "Parsed {} arguments", .{3});
    try std.testing.expect(vlogger.wasStepExecuted(.INIT_PARSE_ARGS));
    
    // Test failed step
    vlogger.pipelineStepFailed(.FILE_OPEN, "Permission denied", "File: {s}", .{"test.mid"});
    try std.testing.expect(!vlogger.wasStepExecuted(.FILE_OPEN));
    
    // Test statistics
    const stats = vlogger.getPipelineStats();
    try std.testing.expectEqual(@as(u32, 2), stats.executed_count);
    try std.testing.expectEqual(@as(u32, 1), stats.failed_count);
    try std.testing.expect(stats.total_execution_time_ns >= 2_000_000);
    
    // Test pipeline report generation (just ensure it doesn't crash)
    vlogger.generatePipelineReport();
}

test "VerboseLogger pipeline step tracking when disabled" {
    var vlogger = VerboseLogger.init(std.testing.allocator, false, false);
    defer vlogger.deinit();
    
    // Even when verbose logging is disabled, step tracking should still work
    vlogger.pipelineStep(.INIT_START, "", .{});
    try std.testing.expect(vlogger.wasStepExecuted(.INIT_START));
    
    vlogger.pipelineStepWithTiming(.INIT_PARSE_ARGS, 1_000_000, "", .{});
    try std.testing.expect(vlogger.wasStepExecuted(.INIT_PARSE_ARGS));
    
    vlogger.pipelineStepFailed(.FILE_OPEN, "Error", "", .{});
    try std.testing.expect(!vlogger.wasStepExecuted(.FILE_OPEN));
    
    const stats = vlogger.getPipelineStats();
    try std.testing.expectEqual(@as(u32, 2), stats.executed_count);
    try std.testing.expectEqual(@as(u32, 1), stats.failed_count);
}

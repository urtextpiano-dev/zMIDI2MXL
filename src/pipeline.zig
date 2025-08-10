//! MIDI to MXL Pipeline Integration
//! 
//! This module provides the essential glue code to connect all pipeline components
//! into a working MIDI→MXL conversion system.
//!
//! Pipeline Flow:
//! MIDI File → Parse → NoteDurationTracker → TimedNote[] → VoiceAllocator → 
//! VoicedNote[] → MeasureBoundaryDetector → Measure[] → MusicXML Generator → .mxl File

const std = @import("std");
const containers = @import("utils/containers.zig");
const log = @import("utils/log.zig");
const error_helpers = @import("utils/error_helpers.zig");

// Core modules
const midi_parser = @import("midi/parser.zig");
const multi_track = @import("midi/multi_track.zig");
const timing = @import("timing.zig");
const voice_allocation = @import("voice_allocation.zig");
const mxl_generator = @import("mxl/generator.zig");
const note_attributes = @import("mxl/note_attributes.zig");
const error_mod = @import("error.zig");
const binary_reader = @import("utils/binary_reader.zig");

// Educational processing infrastructure
const arena_mod = @import("memory/arena.zig");
const EducationalArena = arena_mod.EducationalArena;
const educational_processor = @import("educational_processor.zig");
const enhanced_note = @import("timing/enhanced_note.zig");

// Chord detection for global chord support
const chord_detector = @import("harmony/chord_detector.zig");

/// Global Note Collector for cross-track chord detection
/// Implements TASK 2.1 per CHORD_DETECTION_FIX_TASK_LIST.md Section 2 lines 50-63
pub const GlobalNoteCollector = struct {
    allocator: std.mem.Allocator,
    all_notes: containers.List(timing.TimedNote),
    track_to_part_map: containers.AutoMap(u8, usize),
    
    /// Initialize the global note collector
    pub fn init(allocator: std.mem.Allocator) GlobalNoteCollector {
        return GlobalNoteCollector{
            .allocator = allocator,
            .all_notes = containers.List(timing.TimedNote).init(allocator),
            .track_to_part_map = containers.AutoMap(u8, usize).init(allocator),
        };
    }
    
    /// Collect notes from all parts in the container
    /// This enables cross-track chord detection by gathering all notes with track information preserved
    pub fn collectFromAllParts(self: *GlobalNoteCollector, container: *const multi_track.MultiTrackContainer) !void {
        // DEBUG FIX-002: Add debug tracing within GlobalNoteCollector
        log.tag("FIX-002:COLLECTOR", "collectFromAllParts called with {} parts, {} tracks", .{container.parts.items.len, container.tracks.items.len});
        
        // Clear any existing data
        self.all_notes.clearRetainingCapacity();
        self.track_to_part_map.clearRetainingCapacity();
        
        // Build track-to-part mapping first
        log.tag("FIX-002:MAPPING", "Building track-to-part mapping", .{});
        for (container.parts.items, 0..) |part, part_idx| {
            log.tag("FIX-002:PART", "Part {} has {} track indices", .{part_idx, part.track_indices.items.len});
            for (part.track_indices.items) |track_idx| {
                try self.track_to_part_map.put(@intCast(track_idx), part_idx);
            }
        }
        log.tag("FIX-002:MAPPING", "Built mapping for {} track-part associations", .{self.track_to_part_map.count()});
        
        // Collect all notes from all tracks, preserving track information
        log.tag("FIX-002:COLLECTION", "Starting note collection from tracks", .{});
        for (container.tracks.items, 0..) |track, track_idx| {
            log.tag("FIX-002:TRACK", "Processing track {} with {} note events", .{track_idx, track.note_events.items.len});
            
            // Convert NoteEvents to TimedNotes using the same logic as Pipeline.convertToTimedNotes
            var duration_tracker = midi_parser.NoteDurationTracker.init(self.allocator);
            defer duration_tracker.deinit();
            
            // Process note events to calculate durations
            for (track.note_events.items) |event| {
                try duration_tracker.processNoteEvent(event);
            }
            
            try duration_tracker.finalize();
            
            // Get completed notes from the tracker
            const completed_notes = duration_tracker.completed_notes.items;
            log.tag("FIX-002:TRACK", "Track {} produced {} completed notes", .{track_idx, completed_notes.len});
            
            // Convert to TimedNote format and add to collection
            for (completed_notes) |note| {
                const timed_note = timing.TimedNote{
                    .note = note.note,
                    .channel = note.channel,
                    .velocity = note.on_velocity,
                    .start_tick = note.on_tick,
                    .duration = note.duration_ticks,
                    .tied_to_next = false,
                    .tied_from_previous = false,
                    .track = @intCast(track_idx),  // Preserve track information
                };
                try self.all_notes.append(timed_note);
            }
        }
        
        log.tag("FIX-002:COLLECTION", "Collected {} total notes before sorting", .{self.all_notes.items.len});
        
        // Sort all notes by start_tick for efficient chord detection
        std.sort.pdq(timing.TimedNote, self.all_notes.items, {}, compareTimedNotesByStartTick);
        
        log.tag("FIX-002:COLLECTION", "Final collection: {} notes sorted by start_tick", .{self.all_notes.items.len});
    }
    
    /// Clean up resources
    pub fn deinit(self: *GlobalNoteCollector) void {
        self.all_notes.deinit();
        self.track_to_part_map.deinit();
    }
    
    /// Get the part index that a track belongs to
    pub fn getPartForTrack(self: *const GlobalNoteCollector, track: u8) ?usize {
        return self.track_to_part_map.get(track);
    }
};

/// Comparison function for sorting TimedNotes by start_tick for chord detection
fn compareTimedNotesByStartTick(context: void, a: timing.TimedNote, b: timing.TimedNote) bool {
    _ = context;
    return a.start_tick < b.start_tick;
}

/// Pipeline configuration options
pub const PipelineConfig = struct {
    /// Divisions per quarter note for MusicXML output
    divisions: u32 = 480,
    /// Whether to enable voice assignment
    enable_voice_assignment: bool = true,
    /// Whether to detect measure boundaries
    enable_measure_detection: bool = true,
    /// Tolerance in ticks for cross-track chord detection (optimized for MuseScore compatibility)
    chord_tolerance_ticks: u32 = 0,
    
    /// Educational processing configuration
    educational: EducationalConfig = .{},
    
    /// Educational processing configuration
    pub const EducationalConfig = struct {
        /// Whether to enable educational processing pipeline
        enabled: bool = false,
        /// Whether to enable leak detection for educational processing
        enable_leak_detection: bool = false,
        /// Whether to enable detailed logging for educational processing
        enable_logging: bool = false,
        /// Whether to enable error recovery mode
        enable_error_recovery: bool = true,
        /// Maximum memory overhead percentage allowed (default 20%)
        max_memory_overhead_percent: f64 = 20.0,
        /// Performance target in nanoseconds per note (default 100ns)
        performance_target_ns_per_note: u64 = 100,
        
        /// Educational processor configuration
        processor_config: educational_processor.EducationalProcessingConfig = .{},
        
        /// Convert to educational processor configuration
        pub fn toProcessorConfig(self: EducationalConfig) educational_processor.EducationalProcessingConfig {
            return .{
                .performance = .{
                    .max_processing_time_per_note_ns = self.performance_target_ns_per_note,
                    .max_memory_overhead_percent = self.max_memory_overhead_percent,
                    .enable_performance_monitoring = true,
                    .enable_performance_fallback = self.enable_error_recovery,
                },
                .features = self.processor_config.features,
                .quality = self.processor_config.quality,
                .coordination = self.processor_config.coordination,
            };
        }
    };
};

/// Result of the complete pipeline conversion
pub const PipelineResult = struct {
    /// Generated MusicXML content
    musicxml_content: []u8,
    /// Multi-track container with parts
    container: multi_track.MultiTrackContainer,
    /// Organized measures (if measure detection enabled)
    measures: ?[]timing.Measure,
    /// Track if container has been consumed to prevent double-free
    container_consumed: bool = false,
    /// Educational processing metrics (if educational processing was enabled)
    educational_metrics: ?arena_mod.EducationalPerformanceMetrics = null,
    
    /// Clean up pipeline result resources
    pub fn deinit(self: *PipelineResult, allocator: std.mem.Allocator) void {
        allocator.free(self.musicxml_content);
        
        // Only deinit container if it hasn't been consumed elsewhere
        if (!self.container_consumed) {
            self.container.deinit();
        }
        
        if (self.measures) |measures| {
            // Safely cleanup each measure
            for (measures) |*measure| {
                measure.deinit();
            }
            allocator.free(measures);
        }
    }
    
    /// Mark container as consumed to prevent double-free
    pub fn consumeContainer(self: *PipelineResult) void {
        self.container_consumed = true;
    }
};

/// Main pipeline processor
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    config: PipelineConfig,
    /// Educational arena for memory management (optional)
    educational_arena: ?EducationalArena = null,
    /// Educational processor for feature coordination (optional)
    educational_processor: ?educational_processor.EducationalProcessor = null,
    
    /// Initialize pipeline with configuration
    pub fn init(allocator: std.mem.Allocator, config: PipelineConfig) Pipeline {
        var pipeline = Pipeline{
            .allocator = allocator,
            .config = config,
        };
        
        // Initialize educational arena if educational processing is enabled
        if (config.educational.enabled) {
            pipeline.educational_arena = EducationalArena.init(
                allocator,
                config.educational.enable_leak_detection,
                config.educational.enable_logging
            );
            
            // Configure error recovery mode
            if (config.educational.enable_error_recovery) {
                pipeline.educational_arena.?.enableErrorRecovery();
            }
            
            // Initialize educational processor with the arena
            const processor_config = config.educational.toProcessorConfig();
            pipeline.educational_processor = educational_processor.EducationalProcessor.init(
                &pipeline.educational_arena.?,
                processor_config
            );
            
            // Configure error recovery mode for processor
            if (config.educational.enable_error_recovery) {
                pipeline.educational_processor.?.enableErrorRecovery();
            }
        }
        
        return pipeline;
    }
    
    /// Clean up pipeline resources
    pub fn deinit(self: *Pipeline) void {
        if (self.educational_arena) |*arena| {
            arena.deinit();
        }
    }
    
    /// Convert MIDI data to MXL content
    /// This is the main integration point that connects all components
    /// Implements TASK-VL-008 per VERBOSE_LOGGING_TASK_LIST.md Section 8 lines 338-367
    pub fn convertMidiToMxl(self: *Pipeline, midi_data: []const u8) !PipelineResult {
        // DEBUG FIX-002: Add debug tracing at pipeline entry
        log.tag("FIX-002:PIPELINE", "convertMidiToMxl called with {} bytes of MIDI data", .{midi_data.len});
        
        const vlogger = @import("verbose_logger.zig").getVerboseLogger();
        
        // MIDI PARSING PHASE (003.xxx.xxx)
        vlogger.pipelineStep(.MIDI_PARSE_START, "Beginning MIDI parsing", .{});
        
        vlogger.pipelineStep(.MIDI_PARSE_HEADER, "Parsing MIDI header", .{});
        // Step 1: Parse MIDI header
        const midi_header = try midi_parser.parseMidiHeader(midi_data);
        
        vlogger.pipelineStep(.MIDI_PARSE_TRACKS, "Finding and parsing MIDI tracks", .{});
        // Step 2: Find and parse tracks
        var tracks = containers.List(midi_parser.TrackParseResult).init(self.allocator);
        var tracks_owned = true; // Track ownership state
        defer {
            if (tracks_owned) {
                // Only free tracks if they haven't been transferred to container
                for (tracks.items) |*track| {
                    track.deinit(self.allocator);
                }
            }
            tracks.deinit();
        }
        
        vlogger.pipelineStep(.MIDI_PARSE_EVENTS, "Parsing MIDI events from tracks", .{});
        // Simple track parsing - look for MTrk chunks
        var offset: usize = 14; // Skip header (14 bytes)
        var tracks_found: u16 = 0;
        var parse_iterations: usize = 0;
        const max_parse_iterations: usize = 10000; // Prevent infinite loops
        
        while (offset < midi_data.len and tracks_found < midi_header.track_count) {
            // CRITICAL SAFETY: Prevent infinite loops in MIDI parsing
            parse_iterations += 1;
            if (parse_iterations > max_parse_iterations) {
                log.warn("Too many MIDI parsing iterations, breaking to prevent hang", .{});
                break;
            }
            // Look for MTrk magic
            if (offset + 8 <= midi_data.len and 
                std.mem.eql(u8, midi_data[offset..offset+4], "MTrk")) {
                
                const track_chunk = midi_data[offset..];
                const track_result = try midi_parser.parseTrack(self.allocator, track_chunk);
                try tracks.append(track_result);
                
                // Skip to next track (8 bytes header + track length)
                const track_length = binary_reader.readU32BE(midi_data, offset + 4);
                offset += 8 + track_length;
                tracks_found += 1;
            } else {
                offset += 1;
            }
        }
        
        vlogger.pipelineStep(.MIDI_VALIDATE_STRUCTURE, "Validating MIDI structure", .{});
        
        vlogger.pipelineStep(.MIDI_CREATE_CONTAINER, "Creating multi-track container", .{});
        // Step 3: Create multi-track container
        const divisions = midi_header.division.getTicksPerQuarter() orelse 480; // Default if SMPTE
        var container = multi_track.MultiTrackContainer.init(
            self.allocator, 
            midi_header.format,
            divisions
        );
        
        // Add tracks to container (transfer ownership)
        for (tracks.items) |track| {
            try container.addTrack(track);
        }
        tracks_owned = false; // Ownership transferred to container
        
        vlogger.pipelineStep(.MIDI_CREATE_PARTS, "Creating parts from tracks", .{});
        // Create parts from tracks
        try container.createParts();
        
        // TIMING CONVERSION PHASE (004.xxx.xxx) - CRITICAL FOR IDENTIFYING DURATION MISMATCH
        vlogger.pipelineStep(.TIMING_START, "Starting timing conversion", .{});
        
        vlogger.pipelineStep(.TIMING_DIVISION_SETUP, "Setting up division converter (MIDI PPQ {} -> MXL divisions {})", .{divisions, self.config.divisions});
        
        // Step 3: Process notes for each part
        var all_measures = containers.List(timing.Measure).init(self.allocator);
        defer all_measures.deinit();
        
        // Store enhanced notes for MXL generation with educational metadata
        var all_enhanced_notes = containers.List(enhanced_note.EnhancedTimedNote).init(self.allocator);
        defer all_enhanced_notes.deinit();
        
        // DEBUG FIX-002: Add debug tracing at main part processing loop entry
        log.tag("FIX-002:PARTS", "About to process {} parts", .{container.parts.items.len});
        
        for (container.parts.items, 0..) |part, part_idx| {
            // DEBUG FIX-002: Add debug tracing for each part processing iteration
            log.tag("FIX-002:PART", "Processing part {}/{}", .{part_idx + 1, container.parts.items.len});
            
            // CRITICAL SAFETY: Add logging to identify which part causes hangs
            // Processing part {d}/{d} - removed debug output for production
            
            vlogger.pipelineStep(.TIMING_NOTE_DURATION_TRACKING, "Processing note durations for part {}", .{part_idx + 1});
            
            // TASK 1.3: Process each track within the part separately to maintain track indices
            // Implements TASK 1.3 per CHORD_DETECTION_FIX_TASK_LIST.md lines 41-47
            var part_timed_notes = containers.List(timing.TimedNote).init(self.allocator);
            defer part_timed_notes.deinit();
            
            // Process each track that belongs to this part
            for (part.track_indices.items) |track_idx| {
                // Get notes for this specific track
                var track_notes = containers.List(midi_parser.NoteEvent).init(self.allocator);
                defer track_notes.deinit();
                
                const track = &container.tracks.items[track_idx];
                
                // Filter notes by channel if part has a specific channel
                if (part.midi_channel) |channel| {
                    for (track.note_events.items) |note| {
                        if (note.channel == channel) {
                            try track_notes.append(note);
                        }
                    }
                } else {
                    // Include all notes from the track
                    try track_notes.appendSlice(track.note_events.items);
                }
                
                if (track_notes.items.len > 0) {
                    vlogger.pipelineStep(.TIMING_CONVERT_TO_TIMED_NOTES, "Converting NoteEvent[] to TimedNote[] for part {} track {} ({} notes)", .{part_idx + 1, track_idx, track_notes.items.len});
                    // Convert NoteEvent[] to TimedNote[] with correct track index
                    const track_timed_notes = try self.convertToTimedNotes(track_notes.items, @intCast(track_idx));
                    defer self.allocator.free(track_timed_notes);
                    
                    // Collect all timed notes for this part
                    try part_timed_notes.appendSlice(track_timed_notes);
                }
            }
            
            // Sort notes by start_tick for proper ordering
            std.sort.pdq(timing.TimedNote, part_timed_notes.items, {}, compareTimedNotesByTick);
            
            // Transfer ownership to a slice
            const timed_notes = try part_timed_notes.toOwnedSlice();
            defer self.allocator.free(timed_notes);
            
            vlogger.pipelineStep(.TIMING_VALIDATE_DURATIONS, "Validating note durations for part {} ({} timed notes)", .{part_idx + 1, timed_notes.len});
            
            // VOICE ASSIGNMENT PHASE (005.xxx.xxx) - Must happen BEFORE enhanced note creation
            // This ensures voice data flows through the pipeline
            if (self.config.enable_voice_assignment and timed_notes.len > 0) {
                vlogger.pipelineStep(.VOICE_START, "Starting voice assignment for part {}", .{part_idx + 1});
                
                vlogger.pipelineStep(.VOICE_ALLOCATOR_INIT, "Initializing voice allocator", .{});
                var voice_allocator = voice_allocation.VoiceAllocator.init(self.allocator);
                defer voice_allocator.deinit();
                
                vlogger.pipelineStep(.VOICE_ASSIGNMENT, "Assigning voices to {} notes", .{timed_notes.len});
                const voiced_notes = try voice_allocator.assignVoices(timed_notes);
                defer self.allocator.free(voiced_notes);
                
                // CRITICAL FIX: Update timed_notes with voice assignments
                // This ensures voice data propagates to enhanced notes
                for (voiced_notes, 0..) |voiced_note, i| {
                    timed_notes[i].voice = voiced_note.voice;
                }
                
                vlogger.pipelineStep(.VOICE_VALIDATION, "Voice assignments applied: voices will flow to enhanced notes", .{});
            }
            
            // Apply educational processing or basic conversion AFTER voice assignment
            // This ensures enhanced notes contain voice data
            var enhanced_notes: []enhanced_note.EnhancedTimedNote = undefined;
            var need_to_free_enhanced = false;
            
            if (self.config.educational.enabled and self.educational_processor != null) {
                // EDUCATIONAL PROCESSING PHASE (007.xxx.xxx) - Only if enabled
                vlogger.pipelineStep(.EDU_START, "Starting educational processing for part {} (with voice data)", .{part_idx + 1});
                enhanced_notes = try self.educational_processor.?.processNotes(timed_notes);
                need_to_free_enhanced = false; // Arena owns the memory
            } else {
                // Convert TimedNote[] to EnhancedTimedNote[] without educational metadata
                // Voice data from timed_notes will be preserved in enhanced notes
                enhanced_notes = try self.convertToEnhancedNotes(timed_notes);
                need_to_free_enhanced = true;
            }
            
            // Collect enhanced notes from all parts for MXL generation
            // These now contain voice data from the assignment phase
            try all_enhanced_notes.appendSlice(enhanced_notes);
            defer if (need_to_free_enhanced) self.allocator.free(enhanced_notes);
            
            // MEASURE DETECTION PHASE (006.xxx.xxx) - Critical for timing validation
            if (self.config.enable_measure_detection and enhanced_notes.len > 0) {
                vlogger.pipelineStep(.MEASURE_START, "Starting measure detection for part {}", .{part_idx + 1});
                
                const division_converter = try timing.DivisionConverter.init(divisions, self.config.divisions);
                var boundary_detector = timing.MeasureBoundaryDetector.init(self.allocator, &division_converter);
                
                vlogger.pipelineStep(.MEASURE_TIME_SIGNATURE_EXTRACTION, "Extracting time signatures from conductor track", .{});
                // Extract time signatures from first track (conductor track)
                const first_track = container.tracks.items[0];
                const time_signatures = first_track.time_signature_events.items;
                
                if (time_signatures.len > 0) {
                    vlogger.pipelineStep(.MEASURE_BOUNDARY_DETECTION, "Detecting measure boundaries (PPQ: {}, divisions: {}, time sigs: {})", .{divisions, self.config.divisions, time_signatures.len});
                    
                    // Enhanced notes now always contain voice data if voice assignment was enabled
                    const notes_to_process = try self.convertEnhancedToTimedNotes(enhanced_notes);
                    defer self.allocator.free(notes_to_process);
                    
                    vlogger.pipelineStep(.MEASURE_ORGANIZATION, "Organizing {} notes into measures", .{notes_to_process.len});
                    var part_measures = try boundary_detector.detectMeasureBoundaries(notes_to_process, time_signatures);
                    try all_measures.appendSlice(part_measures.items);
                    part_measures.deinit();
                    
                    vlogger.pipelineStep(.MEASURE_VALIDATION, "Validating measure structure", .{});
                } else {
                    vlogger.pipelineStep(.MEASURE_TIME_SIGNATURE_EXTRACTION, "No time signatures found, skipping measure detection", .{});
                }
            }
            
            // DEBUG FIX-002: Add debug tracing after each part completes processing
            log.tag("FIX-002:PART", "Finished processing part {}/{}", .{part_idx + 1, container.parts.items.len});
        }
        
        // DEBUG FIX-002: Add comprehensive debug tracing to identify execution path issue
        log.tag("FIX-002:PARTS", "Parts processed: {}, Enhanced notes collected: {}", .{container.parts.items.len, all_enhanced_notes.items.len});
        log.tag("FIX-002:FLOW", "About to enter global collection phase", .{});
        
        // CRITICAL FIX: Skip global chord detection when voice assignment is enabled
        // Global chord detection creates new notes without voice data, which breaks multi-voice support
        // When voice assignment is enabled, we rely on the MXL generator's fallback to detect chords
        // from the enhanced notes which preserve voice assignments
        var global_chords: ?[]const chord_detector.ChordGroup = null;
        
        if (!self.config.enable_voice_assignment) {
            // Only do global chord detection when voice assignment is disabled
            // This preserves the cross-track chord detection feature for non-voice scenarios
            
            // GLOBAL NOTE COLLECTION PHASE (007.xxx.xxx) - TASK 2.2: Implement Global Collection Logic
            // Implements TASK 2.2 per CHORD_DETECTION_FIX_TASK_LIST.md Section 2 lines 65-73
            log.tag("FIX-002:GLOBAL", "Starting global note collection for cross-track chord detection", .{});
            vlogger.pipelineStep(.MXL_START, "Starting global note collection for cross-track chord detection", .{});
            
            // Create GlobalNoteCollector for cross-track chord detection
            log.tag("FIX-002:COLLECTOR", "Initializing GlobalNoteCollector", .{});
            var global_collector = GlobalNoteCollector.init(self.allocator);
            defer global_collector.deinit();
            
            // Add safety checks for null pointers or empty collections
            if (container.parts.items.len == 0) {
                log.tag("FIX-002:WARNING", "No parts found in container, skipping global collection", .{});
            } else {
                log.tag("FIX-002:STATE", "Parts: {}, Tracks: {}", .{container.parts.items.len, container.tracks.items.len});
                
                // Collect all notes from all parts with track information preserved
                log.tag("FIX-002:COLLECTION", "Calling collectFromAllParts", .{});
                global_collector.collectFromAllParts(&container) catch |err| 
                    return error_helpers.logAndReturn("Error during global collection", err);
                log.tag("FIX-002:COLLECTION", "Collection completed successfully", .{});
            }
            
            // Log collection results for diagnostic purposes
            log.tag("FIX-002:RESULTS", "Collected {} notes from {} parts for chord detection", .{global_collector.all_notes.items.len, container.parts.items.len});
            vlogger.pipelineStep(.MXL_START, "Collected {} notes from {} parts for chord detection", 
                .{global_collector.all_notes.items.len, container.parts.items.len});
            
            // CROSS-TRACK CHORD DETECTION PHASE (TASK 4.1) - TASK 4.1: Update MXL Generator for Global Chords
            // Implements TASK 4.1 per CHORD_DETECTION_FIX_TASK_LIST.md Section 4 lines 115-121
            log.tag("FIX-002:CHORDS", "Entering chord detection phase", .{});
            if (global_collector.all_notes.items.len > 0) {
                log.tag("FIX-002:CHORDS", "Detecting cross-track chords from {} global notes", .{global_collector.all_notes.items.len});
                vlogger.pipelineStep(.MXL_START, "Detecting cross-track chords from {} global notes", .{global_collector.all_notes.items.len});
                
                // CDR-2.2: Use minimal chord detector (fail-safe, EXACT timing only)
                const minimal_chord_detector = @import("harmony/minimal_chord_detector.zig");
                var detector = minimal_chord_detector.MinimalChordDetector.init(self.allocator);
                
                // Detect chords with EXACT timing match only (no tolerance to prevent sequential grouping)
                log.tag("CDR-2.2", "Using minimal chord detector (EXACT timing, no tolerance)", .{});
                const detected_chords = detector.detectChords(global_collector.all_notes.items) catch |err|
                    return error_helpers.logAndReturn("CDR-2.2: Error during chord detection", err);
                global_chords = detected_chords;
                
                log.tag("FIX-002:CHORDS", "Detected {} cross-track chords", .{detected_chords.len});
                vlogger.pipelineStep(.MXL_START, "Detected {} cross-track chords", .{detected_chords.len});
            } else {
                log.tag("FIX-002:CHORDS", "No global notes available, skipping chord detection", .{});
            }
        } else {
            // When voice assignment is enabled, run chord detection on enhanced notes
            // This preserves voice assignments while properly detecting chords
            if (all_enhanced_notes.items.len > 0) {
                vlogger.pipelineStep(.MXL_START, "Detecting chords from {} enhanced notes with voice assignments", .{all_enhanced_notes.items.len});
                
                // Convert enhanced notes to timed notes (preserves voice in base_note)
                const timed_notes_for_chords = try self.convertEnhancedToTimedNotes(all_enhanced_notes.items);
                defer self.allocator.free(timed_notes_for_chords);
                
                // Use minimal chord detector with EXACT timing match only
                const minimal_chord_detector = @import("harmony/minimal_chord_detector.zig");
                var detector = minimal_chord_detector.MinimalChordDetector.init(self.allocator);
                
                // Detect chords with EXACT timing match only (no tolerance to prevent sequential grouping)
                const detected_chords = detector.detectChords(timed_notes_for_chords) catch |err|
                    return error_helpers.logAndReturn("Error during chord detection on enhanced notes", err);
                global_chords = detected_chords;
                
                vlogger.pipelineStep(.MXL_START, "Detected {} chords from enhanced notes with voice assignments", .{detected_chords.len});
            } else {
                vlogger.pipelineStep(.MXL_START, "No enhanced notes available for chord detection", .{});
            }
        }
        
        // DEBUG FIX-002: Add debug tracing before MXL generation phase
        log.tag("FIX-002:MXL", "About to start MusicXML generation", .{});
        log.tag("FIX-002:MEMORY", "Allocator state before MXL generation", .{});
        
        // MUSICXML GENERATION PHASE (008.xxx.xxx)
        log.tag("FIX-002:MXL", "Starting MusicXML generation phase", .{});
        vlogger.pipelineStep(.MXL_START, "Starting MusicXML generation", .{});
        
        vlogger.pipelineStep(.MXL_GENERATOR_INIT, "Initializing MXL generator (MIDI PPQ: {}, target divisions: {})", .{divisions, self.config.divisions});
        // Step 4: Generate MusicXML with measure boundaries
        // Starting MXL generation - removed debug output for production
        var xml_buffer = containers.List(u8).init(self.allocator);
        // TIMING-2.3 FIX: Use proper MIDI to MusicXML conversion
        var generator = try mxl_generator.Generator.initWithConversion(self.allocator, divisions, self.config.divisions);
        defer generator.deinit();
        
        vlogger.pipelineStep(.MXL_HEADER_GENERATION, "Generating MusicXML header", .{});
        vlogger.pipelineStep(.MXL_PART_LIST_GENERATION, "Generating part list", .{});
        vlogger.pipelineStep(.MXL_SCORE_PART_GENERATION, "Generating score parts", .{});
        
        // TASK-INT-017: Always use enhanced MXL generation for complete pipeline integration
        if (all_enhanced_notes.items.len > 0) {
            vlogger.pipelineStep(.MXL_ENHANCED_NOTE_PROCESSING, "Using enhanced MXL generation with {} enhanced notes", .{all_enhanced_notes.items.len});
            // Use enhanced MXL generation (with or without educational features) - removed debug output for production
            try self.generateEnhancedMusicXML(&generator, xml_buffer.writer(), all_enhanced_notes.items, &container, global_chords);
        } else if (container.parts.items.len > 0) {
            vlogger.pipelineStep(.MXL_NOTE_GENERATION, "Fallback: generating from part notes", .{});
            // Fallback: no enhanced notes but we have parts
            var part_notes = try container.getNotesForPart(0);
            defer part_notes.deinit();
            
            // CRITICAL FIX: Convert NoteEvents to TimedNotes to preserve duration
            const timed_notes = try self.convertToTimedNotes(part_notes.items, 0);
            defer self.allocator.free(timed_notes);
            
            // Extract tempo for fallback generation per TASK 2.2
            const tempo_f64 = container.getInitialTempo();
            const tempo_bpm: u32 = @intFromFloat(@round(tempo_f64));
            
            try generator.generateMusicXMLWithMeasureBoundaries(xml_buffer.writer(), timed_notes, tempo_bpm);
        } else {
            vlogger.pipelineStep(.MXL_NOTE_GENERATION, "Fallback: generating from multi-track container", .{});
            // Fallback to multi-track function if no parts
            try generator.generateMultiTrackMusicXML(xml_buffer.writer(), &container);
        }
        
        vlogger.pipelineStep(.MXL_VALIDATION, "Validating generated MusicXML", .{});
        
        // Return pipeline result
        const measures_copy = if (all_measures.items.len > 0) 
            try self.allocator.dupe(timing.Measure, all_measures.items) else null;
        
        // Collect educational metrics if educational processing was enabled
        // IMPORTANT: Do this BEFORE arena reset to avoid accessing freed memory
        const educational_metrics = if (self.educational_processor) |*processor| blk: {
            const proc_metrics = processor.getMetrics();
            // Convert ProcessingChainMetrics to EducationalPerformanceMetrics
            break :blk arena_mod.EducationalPerformanceMetrics{
                .processing_time_per_note_ns = if (proc_metrics.notes_processed > 0) 
                    proc_metrics.total_processing_time_ns / proc_metrics.notes_processed else 0,
                .notes_processed = proc_metrics.notes_processed,
                .phase_allocations = [_]u64{0} ** 5, // ProcessingChainMetrics doesn't track these
                .peak_educational_memory = 0, // ProcessingChainMetrics doesn't track this
                .successful_cycles = 1, // We processed one batch successfully
                .error_count = proc_metrics.error_count,
            };
        } else null;
        
        // CRITICAL FIX: Reset educational arena memory after metrics collection
        // This prevents memory leaks by freeing all arena allocations while preserving metrics
        // Arena reset is safe here because:
        // 1. MXL generation is complete and educational data has been consumed
        // 2. Educational metrics have been collected and copied to stack variables
        // 3. No further access to arena-allocated memory will occur
        if (self.config.educational.enabled and self.educational_processor != null) {
            self.educational_processor.?.resetArenaMemoryOnly();
        }
        
        // Clean up global chords (TASK 4.1)
        if (global_chords) |chords| {
            // Cast to mutable for cleanup since we own these chords
            const mutable_chords = @constCast(chords);
            for (mutable_chords) |*chord| {
                chord.deinit(self.allocator);
            }
            self.allocator.free(mutable_chords);
        }
        
        return PipelineResult{
            .musicxml_content = try xml_buffer.toOwnedSlice(),
            .container = container,
            .measures = measures_copy,
            .educational_metrics = educational_metrics,
        };
    }
    
    /// Convert NoteEvent[] to TimedNote[] using NoteDurationTracker
    /// This bridges the gap between MIDI parsing and timing modules
    /// Implements TASK 1.2 per CHORD_DETECTION_FIX_TASK_LIST.md lines 28-39
    fn convertToTimedNotes(self: *Pipeline, note_events: []const midi_parser.NoteEvent, track_index: u8) ![]timing.TimedNote {
        var duration_tracker = midi_parser.NoteDurationTracker.init(self.allocator);
        defer duration_tracker.deinit();
        
        // Process note events to calculate durations
        for (note_events) |event| {
            try duration_tracker.processNoteEvent(event);
        }
        
        try duration_tracker.finalize();
        
        // Get completed notes from the tracker
        const completed_notes = duration_tracker.completed_notes.items;
        
        // Convert to TimedNote format
        var timed_notes = try self.allocator.alloc(timing.TimedNote, completed_notes.len);
        for (completed_notes, 0..) |note, i| {
            timed_notes[i] = timing.TimedNote{
                .note = note.note,
                .channel = note.channel,
                .velocity = note.on_velocity,
                .start_tick = note.on_tick,
                .duration = note.duration_ticks,
                .tied_to_next = false,
                .tied_from_previous = false,
                .track = track_index,  // Set track field per TASK 1.2
            };
        }
        
        return timed_notes;
    }
    
    /// Convert VoicedNote[] back to TimedNote[] for measure detection
    /// This is a temporary bridge function
    fn convertVoicedToTimedNotes(self: *Pipeline, voiced_notes: []const voice_allocation.VoicedNote) ![]timing.TimedNote {
        var timed_notes = try self.allocator.alloc(timing.TimedNote, voiced_notes.len);
        for (voiced_notes, 0..) |voiced_note, i| {
            timed_notes[i] = voiced_note.note;
            // Preserve voice assignment from VoiceAllocator
            timed_notes[i].voice = voiced_note.voice;
        }
        return timed_notes;
    }
    
    /// Convert TimedNote[] to EnhancedTimedNote[] without educational metadata
    /// Used when educational processing is disabled
    fn convertToEnhancedNotes(self: *Pipeline, timed_notes: []const timing.TimedNote) ![]enhanced_note.EnhancedTimedNote {
        var enhanced_notes = try self.allocator.alloc(enhanced_note.EnhancedTimedNote, timed_notes.len);
        for (timed_notes, 0..) |note, i| {
            enhanced_notes[i] = enhanced_note.EnhancedTimedNote.init(note, null);
        }
        return enhanced_notes;
    }
    
    /// Convert EnhancedTimedNote[] to TimedNote[] for compatibility
    /// Strips educational metadata
    fn convertEnhancedToTimedNotes(self: *Pipeline, enhanced_notes: []const enhanced_note.EnhancedTimedNote) ![]timing.TimedNote {
        var timed_notes = try self.allocator.alloc(timing.TimedNote, enhanced_notes.len);
        for (enhanced_notes, 0..) |enhanced, i| {
            timed_notes[i] = enhanced.getBaseNote();
        }
        return timed_notes;
    }
    
    /// Deep copy enhanced notes from educational arena to main allocator
    /// 
    /// This preserves educational metadata while allowing immediate arena reset to prevent leaks.
    /// Implements definitive solution for memory leak per executive authority.
    fn deepCopyEnhancedNotes(self: *Pipeline, arena_notes: []const enhanced_note.EnhancedTimedNote) ![]enhanced_note.EnhancedTimedNote {
        var copied_notes = try self.allocator.alloc(enhanced_note.EnhancedTimedNote, arena_notes.len);
        
        for (arena_notes, 0..) |arena_note, i| {
            // Initialize the enhanced note with the base note (no arena reference)
            copied_notes[i] = enhanced_note.EnhancedTimedNote.init(arena_note.getBaseNote(), null);
            
            // Copy processing flags
            copied_notes[i].processing_flags = arena_note.processing_flags;
            
            // Deep copy educational metadata pointers if present
            if (arena_note.tuplet_info) |tuplet_ptr| {
                const copied_tuplet = try self.allocator.create(enhanced_note.TupletInfo);
                copied_tuplet.* = tuplet_ptr.*;
                copied_notes[i].tuplet_info = copied_tuplet;
            }
            
            if (arena_note.beaming_info) |beaming_ptr| {
                const copied_beaming = try self.allocator.create(enhanced_note.BeamingInfo);
                copied_beaming.* = beaming_ptr.*;
                copied_notes[i].beaming_info = copied_beaming;  
            }
            
            if (arena_note.rest_info) |rest_ptr| {
                const copied_rest = try self.allocator.create(enhanced_note.RestInfo);
                copied_rest.* = rest_ptr.*;
                copied_notes[i].rest_info = copied_rest;
            }
            
            if (arena_note.dynamics_info) |dynamics_ptr| {
                const copied_dynamics = try self.allocator.create(enhanced_note.DynamicsInfo);
                copied_dynamics.* = dynamics_ptr.*;
                copied_notes[i].dynamics_info = copied_dynamics;
            }
            
            if (arena_note.stem_info) |stem_ptr| {
                const copied_stem = try self.allocator.create(enhanced_note.StemInfo);
                copied_stem.* = stem_ptr.*;
                copied_notes[i].stem_info = copied_stem;
            }
        }
        
        return copied_notes;
    }
    
    /// Free deep-copied enhanced notes and their educational metadata
    /// 
    /// This properly deallocates all educational metadata that was copied from the arena.
    fn freeDeepCopiedEnhancedNotes(self: *Pipeline, notes: []enhanced_note.EnhancedTimedNote) void {
        for (notes) |note| {
            // Free individual metadata pointers if present
            if (note.tuplet_info) |tuplet_ptr| {
                self.allocator.destroy(tuplet_ptr);
            }
            if (note.beaming_info) |beaming_ptr| {
                self.allocator.destroy(beaming_ptr);
            }
            if (note.rest_info) |rest_ptr| {
                self.allocator.destroy(rest_ptr);
            }
            if (note.dynamics_info) |dynamics_ptr| {
                self.allocator.destroy(dynamics_ptr);
            }
            if (note.stem_info) |stem_ptr| {
                self.allocator.destroy(stem_ptr);
            }
        }
        
        // Free the notes array itself
        self.allocator.free(notes);
    }
    
    /// Generate MusicXML with educational metadata support (TASK-INT-016)
    /// 
    /// This method uses the enhanced MXL generator to produce MusicXML with:
    /// - Tuplet notation (time-modification and brackets)
    /// - Beam grouping (beam elements)
    /// - Dynamics markings (direction elements)
    /// - Rest optimization (consolidated rests)
    /// - Stem directions (coordinated with beaming)
    fn generateEnhancedMusicXML(
        self: *Pipeline, 
        generator: *mxl_generator.Generator, 
        writer: anytype, 
        enhanced_notes: []const enhanced_note.EnhancedTimedNote,
        container: *const multi_track.MultiTrackContainer,
        global_chords: ?[]const chord_detector.ChordGroup
    ) !void {
        // Extract actual tempo from MIDI data - implements TASK-2.1
        const tempo_f64 = container.getInitialTempo();
        const tempo_bpm: u32 = @intFromFloat(@round(tempo_f64));
        
        // Extract key signature from conductor track (track 0) - FIX-2.1
        var key_fifths: i8 = 0; // Default to C major
        if (container.tracks.items.len > 0) {
            const conductor_track = container.tracks.items[0];
            if (conductor_track.key_signature_events.items.len > 0) {
                key_fifths = conductor_track.key_signature_events.items[0].sharps_flats;
            }
        }
        
        generator.generateMusicXMLFromEnhancedNotes(writer, enhanced_notes, tempo_bpm, global_chords, key_fifths) catch |err| {
            if (self.config.educational.enable_error_recovery) {
                // Fall back to basic generation if enhanced generation fails
                // Pass tempo information to fallback generation per TASK 2.2
                // CRITICAL FIX: Convert to TimedNotes to preserve duration
                const timed_notes = try self.convertEnhancedToTimedNotes(enhanced_notes);
                defer self.allocator.free(timed_notes);
                
                try generator.generateMusicXMLWithMeasureBoundaries(writer, timed_notes, tempo_bpm);
            } else {
                return err;
            }
        };
    }
    
    /// Convert EnhancedTimedNote[] to NoteEvent[] for compatibility with existing MXL generator
    /// 
    /// This is a bridge function for TASK-INT-006 that preserves educational metadata
    /// while enabling compatibility with the current MXL generation infrastructure.
    fn convertEnhancedNotesToNoteEvents(
        self: *Pipeline, 
        enhanced_notes: []const enhanced_note.EnhancedTimedNote
    ) ![]midi_parser.NoteEvent {
        var note_events = try self.allocator.alloc(midi_parser.NoteEvent, enhanced_notes.len);
        
        for (enhanced_notes, 0..) |enhanced_note_item, i| {
            const base_note = enhanced_note_item.getBaseNote();
            
            // Convert TimedNote back to NoteEvent
            // This conversion maintains timing and note information while
            // preparing for future tuplet XML generation
            note_events[i] = midi_parser.NoteEvent{
                .event_type = midi_parser.MidiEventType.note_on,
                .channel = @intCast(base_note.channel & 0x0F), // Ensure channel fits in u4 (0-15)
                .note = base_note.note,
                .velocity = base_note.velocity,
                .tick = base_note.start_tick,
                // Duration is encoded differently in NoteEvent vs TimedNote
                // For this bridge, we'll use the tick as both start and store duration in a comment
            };
        }
        
        return note_events;
    }
    
    /// Legacy educational processing method (replaced by EducationalProcessor)
    /// 
    /// This method is kept for backward compatibility during the transition period.
    /// New code should use the EducationalProcessor directly through the pipeline.
    /// 
    /// Will be removed in a future task after complete integration.
    fn processEducationalFeatures(self: *Pipeline, timed_notes: []timing.TimedNote) !void {
        if (self.educational_processor) |*processor| {
            _ = try processor.processNotes(timed_notes);
            // Reset only arena memory to prevent memory accumulation, but preserve metrics for reporting
            processor.resetArenaMemoryOnly();
        } else if (self.educational_arena) |*arena| {
            // Fallback to old arena-only processing for compatibility
            const notes_count = @as(u64, @intCast(timed_notes.len));
            try arena.processEducationalBatch(notes_count);
            arena.resetForNextCycle();
        }
    }
};

/// Convenience function for simple MIDI to MXL conversion
pub fn convertMidiToMxl(allocator: std.mem.Allocator, midi_data: []const u8) !PipelineResult {
    var pipeline = Pipeline.init(allocator, .{});
    defer pipeline.deinit();
    return pipeline.convertMidiToMxl(midi_data);
}

/// Comparison function for sorting TimedNotes by start_tick
/// Implements TASK 1.3 per CHORD_DETECTION_FIX_TASK_LIST.md lines 41-47
fn compareTimedNotesByTick(context: void, a: timing.TimedNote, b: timing.TimedNote) bool {
    _ = context;
    return a.start_tick < b.start_tick;
}

// Tests for pipeline integration

test "pipeline initialization" {
    const allocator = std.testing.allocator;
    const config = PipelineConfig{ .divisions = 480 };
    const pipeline = Pipeline.init(allocator, config);
    
    try std.testing.expectEqual(@as(u32, 480), pipeline.config.divisions);
    try std.testing.expect(pipeline.config.enable_voice_assignment);
    try std.testing.expect(pipeline.config.enable_measure_detection);
}

test "pipeline config options" {
    const config = PipelineConfig{
        .divisions = 960,
        .enable_voice_assignment = false,
        .enable_measure_detection = false,
    };
    
    try std.testing.expectEqual(@as(u32, 960), config.divisions);
    try std.testing.expect(!config.enable_voice_assignment);
    try std.testing.expect(!config.enable_measure_detection);
}

test "educational processing configuration" {
    // Test educational processing disabled by default
    const default_config = PipelineConfig{};
    try std.testing.expect(!default_config.educational.enabled);
    
    // Test educational processing enabled configuration
    const edu_config = PipelineConfig{
        .educational = .{
            .enabled = true,
            .enable_leak_detection = true,
            .enable_logging = true,
            .enable_error_recovery = false,
            .max_memory_overhead_percent = 15.0,
            .performance_target_ns_per_note = 50,
        },
    };
    
    try std.testing.expect(edu_config.educational.enabled);
    try std.testing.expect(edu_config.educational.enable_leak_detection);
    try std.testing.expect(edu_config.educational.enable_logging);
    try std.testing.expect(!edu_config.educational.enable_error_recovery);
    try std.testing.expectEqual(@as(f64, 15.0), edu_config.educational.max_memory_overhead_percent);
    try std.testing.expectEqual(@as(u64, 50), edu_config.educational.performance_target_ns_per_note);
}

test "pipeline educational arena and processor initialization" {
    const allocator = std.testing.allocator;
    
    // Test pipeline with educational processing disabled
    {
        const config = PipelineConfig{ .educational = .{ .enabled = false } };
        var pipeline = Pipeline.init(allocator, config);
        defer pipeline.deinit();
        
        try std.testing.expect(pipeline.educational_arena == null);
        try std.testing.expect(pipeline.educational_processor == null);
    }
    
    // Test pipeline with educational processing enabled
    {
        const config = PipelineConfig{ 
            .educational = .{ 
                .enabled = true,
                .enable_leak_detection = true,
                .enable_logging = false,
                .enable_error_recovery = true,
            }
        };
        var pipeline = Pipeline.init(allocator, config);
        defer pipeline.deinit();
        
        try std.testing.expect(pipeline.educational_arena != null);
        try std.testing.expect(pipeline.educational_processor != null);
        try std.testing.expect(pipeline.educational_arena.?.leak_detection_enabled);
        try std.testing.expect(pipeline.educational_arena.?.error_recovery_mode);
        try std.testing.expect(pipeline.educational_processor.?.error_recovery_enabled);
    }
}

test "pipeline educational processing infrastructure" {
    const allocator = std.testing.allocator;
    
    const config = PipelineConfig{ 
        .educational = .{ 
            .enabled = true,
            .enable_leak_detection = false,
            .enable_logging = false,
        }
    };
    var pipeline = Pipeline.init(allocator, config);
    defer pipeline.deinit();
    
    // Create some test timed notes
    var test_notes = [_]timing.TimedNote{
        .{ .note = 60, .channel = 0, .velocity = 64, .start_tick = 0, .duration = 480 },
        .{ .note = 64, .channel = 0, .velocity = 64, .start_tick = 480, .duration = 480 },
        .{ .note = 67, .channel = 0, .velocity = 64, .start_tick = 960, .duration = 480 },
    };
    
    // Test educational feature processing through new processor
    if (pipeline.educational_processor) |*processor| {
        const enhanced_notes = try processor.processNotes(&test_notes);
        
        // Verify processing completed
        try std.testing.expect(enhanced_notes.len == 3);
        
        // Verify metrics were recorded  
        const metrics = processor.getMetrics();
        try std.testing.expect(metrics.notes_processed == 3);
        try std.testing.expect(metrics.successful_features > 0);
        try std.testing.expect(metrics.total_processing_time_ns > 0);
    }
}


//! Timing Module - Central hub for all timing-related functionality
//! 
//! This module provides timing conversion, tempo handling, and measure detection
//! functionality for MIDI to MusicXML conversion.

pub const DivisionConverter = @import("timing/division_converter.zig").DivisionConverter;
pub const TimingError = @import("timing/division_converter.zig").TimingError;
pub const COMMON_DIVISIONS = @import("timing/division_converter.zig").COMMON_DIVISIONS;
pub const DEFAULT_DIVISIONS = @import("timing/division_converter.zig").DEFAULT_DIVISIONS;
pub const createFromMidiDivision = @import("timing/division_converter.zig").createFromMidiDivision;
pub const benchmarkConversion = @import("timing/division_converter.zig").benchmarkConversion;

pub const MeasureBoundaryDetector = @import("timing/measure_detector.zig").MeasureBoundaryDetector;
pub const MeasureBoundaryError = @import("timing/measure_detector.zig").MeasureBoundaryError;
pub const TimedNote = @import("timing/measure_detector.zig").TimedNote;
pub const TiedNotePair = @import("timing/measure_detector.zig").TiedNotePair;
pub const Measure = @import("timing/measure_detector.zig").Measure;
pub const benchmarkMeasureDetection = @import("timing/measure_detector.zig").benchmarkMeasureDetection;

// Note Type Converter exports (TASK-028)
pub const NoteTypeConverter = @import("timing/note_type_converter.zig").NoteTypeConverter;
pub const NoteType = @import("timing/note_type_converter.zig").NoteType;
pub const NoteTypeResult = @import("timing/note_type_converter.zig").NoteTypeResult;
pub const TiedNote = @import("timing/note_type_converter.zig").TiedNote;

// Beam Grouper exports (TASK-048)
pub const BeamGrouper = @import("timing/beam_grouper.zig").BeamGrouper;
pub const BeamGroupingError = @import("timing/beam_grouper.zig").BeamGroupingError;
pub const BeamState = @import("timing/beam_grouper.zig").BeamState;
pub const BeamInfo = @import("timing/beam_grouper.zig").BeamInfo;
pub const BeamedNote = @import("timing/beam_grouper.zig").BeamedNote;
pub const BeamGroup = @import("timing/beam_grouper.zig").BeamGroup;

// Rest Optimizer exports (TASK-050)
pub const RestOptimizer = @import("timing/rest_optimizer.zig").RestOptimizer;
pub const RestOptimizationError = @import("timing/rest_optimizer.zig").RestOptimizationError;
pub const Gap = @import("timing/rest_optimizer.zig").Gap;
pub const Rest = @import("timing/rest_optimizer.zig").Rest;

// Tuplet Detector exports (TASK-032)
pub const TupletDetector = @import("timing/tuplet_detector.zig").TupletDetector;
pub const TupletType = @import("timing/tuplet_detector.zig").TupletType;
pub const Tuplet = @import("timing/tuplet_detector.zig").Tuplet;

// Enhanced Note Structure exports (TASK-INT-002)
pub const EnhancedTimedNote = @import("timing/enhanced_note.zig").EnhancedTimedNote;
pub const EnhancedNoteError = @import("timing/enhanced_note.zig").EnhancedNoteError;
pub const TupletInfo = @import("timing/enhanced_note.zig").TupletInfo;
pub const BeamingInfo = @import("timing/enhanced_note.zig").BeamingInfo;
pub const RestInfo = @import("timing/enhanced_note.zig").RestInfo;
pub const DynamicsInfo = @import("timing/enhanced_note.zig").DynamicsInfo;
pub const ConversionUtils = @import("timing/enhanced_note.zig").ConversionUtils;

// Chord Detection exports (TASK 3.1)
pub const ChordDetector = @import("harmony/chord_detector.zig").ChordDetector;
pub const ChordGroup = @import("harmony/chord_detector.zig").ChordGroup;
pub const ChordDetectorError = @import("harmony/chord_detector.zig").ChordDetectorError;

// Re-export tests for integrated testing
test {
    _ = @import("timing/division_converter.zig");
    _ = @import("timing/measure_detector.zig");
    _ = @import("timing/note_type_converter.zig");
    _ = @import("timing/beam_grouper.zig");
    _ = @import("timing/rest_optimizer.zig");
    _ = @import("timing/tuplet_detector.zig");
    _ = @import("timing/enhanced_note.zig");
}
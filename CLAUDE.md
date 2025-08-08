# ZMIDI2MXL - High-Performance MIDI to MusicXML Converter

**Purpose**: Blazingly fast MIDI (.mid) to compressed MusicXML (.mxl) format converter  
**Technology**: Zig 0.14+ for zero-overhead performance, MusicXML 4.0 DTD compliance  
**Core Mission**: Pure format conversion with 100% accuracy AND maximum speed  

## CRITICAL ISSUES (Fix First)

1. **Voice Assignment Pipeline Bug** (`src/pipeline.zig:429-458`)
   - Voices assigned but not propagated to output MusicXML
   - Only voices 1,5 appear instead of expected 1,2,5,6,7,8

2. **Sequential Notes Incorrectly Grouped as Chords**
   - CrossTrackChordDetector causes wrong groupings
   - Use MinimalChordDetector with tolerance=0

3. **Missing MusicXML Backup Elements**
   - Multi-voice notation structure incomplete

## ESSENTIAL COMMANDS

```bash
# Build and test
zig build
zig build test

# Convert MIDI to MXL
zig build run -- input.mid output.mxl

# Critical debugging tests
zig build test-voice-preservation    # Voice assignment validation
zig build test-chord-regression      # Chord detection validation  
zig build test-regression           # Full regression prevention

# Disable notation processing if unstable
zig build run -- input.mid output.mxl --no-notation
```

## ARCHITECTURE OVERVIEW

```
MIDI (.mid) → VLQ Parser → Multi-Track → Timing System → Voice Assignment 
→ Chord Detection → Notation Processing → MusicXML → ZIP Archive → MXL
```

### Key Components
- **`src/pipeline.zig`**: Main conversion pipeline (HAS CRITICAL BUG)
- **`src/midi/parser.zig`**: MIDI parsing, VLQ decoding (<10ns target)
- **`src/voice_allocation.zig`**: Multi-voice separation (BUGGY)
- **`src/mxl/generator.zig`**: MusicXML generation
- **`src/timing/`**: Note duration, measure detection, notation features

### Performance Requirements
- **Conversion Speed**: Optimize for fastest possible MIDI→MXL transformation
- **Duration Accuracy**: 100% precision (non-negotiable)
- **VLQ Parsing**: <10ns per decode target
- **Memory**: Zero allocations in hot paths, proper cleanup with `defer`
- **PPQ Conversion**: Normalize all inputs to 480 divisions per quarter note
- **Throughput Goal**: Process 10MB MIDI file in <100ms

## VALIDATION PROTOCOL

**Reference Standard**: Compare output against MuseScore-generated MusicXML files

```bash
# Extract and validate MusicXML from MXL output
python3 xml_evidence_extractor.py output.mxl
# Must validate against MusicXML 4.0 DTD
```

## CODE CONVENTIONS

```zig
// Error handling with logging
const result = operation() catch |err| {
    logger.err("Operation failed: {}", .{err});
    return err;
};

// Memory management  
var arena = ArenaAllocator.init(allocator, false);
defer arena.deinit();
```

- **Naming**: snake_case files, camelCase functions, PascalCase types
- **Memory**: Always use `defer` for cleanup
- **Tests**: Embedded unit tests + `/test/` integration tests

## KNOWN LIMITATIONS

- **Time Signature**: 4/4 only
- **Voice Mapping**: Piano-focused (treble: voices 1,2 / bass: voices 5,6,7,8)  
- **File Size**: 10MB MIDI input limit
- **MusicXML Version**: 4.0 DTD compliance required

## CRITICAL NOTES

- **Notation Processing** = proper music notation elements (beams, tuplets, rests) for MusicXML compliance
- **This is a FORMAT CONVERTER**: No educational/pedagogical features - pure MIDI→MusicXML transformation
- **Dual Priority**: 100% accuracy WITH maximum performance (both are non-negotiable)
- **Test everything**: Run full regression tests before any changes
- **Fix bugs first**: Don't add features until critical issues resolved
- **Performance mindset**: Every microsecond counts in the conversion pipeline
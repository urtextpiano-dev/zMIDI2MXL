# Hot Path Allowlist for zMIDI2MXL

## Critical Performance Functions - DO NOT TOUCH WITHOUT A/B TESTING

### 🔴 RED (Absolutely Critical - No Modifications Allowed)
1. **`src/midi/parser.zig:parseVlq`** - Core VLQ parsing, <10ns target
2. **`src/midi/parser.zig:parseVlqFast`** - Optimized VLQ path
3. **`src/midi/parser.zig:parseNextEvent`** - Inner event loop
4. **`src/pipeline.zig:convertMidiToMxl` (inner loop)** - Main conversion hot path

### 🟡 YELLOW (Performance Sensitive - Careful Modifications Only)
1. **`src/midi/parser.zig:parseTrackEvents`** - Track parsing loop
2. **`src/midi/parser.zig:processNoteEvent`** - Note processing
3. **`src/mxl/generator.zig:generateNoteElement`** - MusicXML generation
4. **`src/mxl/zip_writer.zig:calculateCrc32`** - CRC calculation
5. **`src/harmony/minimal_chord_detector.zig:detectChords`** - Chord detection
6. **`src/timing/measure_detector.zig` (all)** - Timing critical

### 🟢 GREEN (Safe to Refactor with Standard Validation)
1. **`src/educational_processor.zig`** - Educational features
2. **`src/log.zig`** - Logging infrastructure
3. **`src/error.zig`** - Error handling
4. **Test files** - All test/*.zig files
5. **`src/interpreter/*`** - Interpreter modules (non-critical)

## Performance Requirements
- **VLQ Parsing**: <10ns per decode
- **Full Conversion**: <100ms for 10MB MIDI
- **Memory**: Zero allocations in RED functions
- **Throughput**: >10MB/s sustained

## Validation Protocol for Modifications
### RED Zone:
- NO modifications without explicit performance improvement proof
- Requires assembly output comparison
- Requires ≥20 benchmark runs showing improvement

### YELLOW Zone:
- Modifications allowed with A/B testing
- Must show ≤1% performance regression (median)
- Requires ≥10 benchmark runs

### GREEN Zone:
- Standard refactoring allowed
- Must pass all tests
- Performance regression ≤5% acceptable

## Benchmarking Requirements
- Use **median** (not mean) of timings
- Minimum 5 warmup runs
- Minimum 20 measured runs for RED zone
- Minimum 10 measured runs for YELLOW zone
- CPU frequency pinned if possible
- Run on idle machine
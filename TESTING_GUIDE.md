# zMIDI2MXL Testing Guide

## Overview
This guide outlines the comprehensive testing strategy for validating the zMIDI2MXL converter against reference implementations like MuseScore.

## Quick Start

### 1. Basic Conversion Test
```bash
# Build the project
zig build

# Convert a MIDI file
zig-out\bin\zmidi2mxl.exe Sweden_Minecraft.mid sweden_output.mxl --verbose

# Validate the output
python test_validator.py
```

### 2. Comparison with MuseScore

To compare your output with MuseScore:

1. **Generate MuseScore Reference:**
   - Open `Sweden_Minecraft.mid` in MuseScore
   - File → Export → Uncompressed MusicXML (.musicxml)
   - Save as `sweden_musescore.musicxml` in the project directory

2. **Run Comparison:**
   ```bash
   python test_validator.py
   ```

## Testing Components

### 1. **Python Validator (`test_validator.py`)**
- Extracts MusicXML from MXL files
- Validates XML structure
- Compares musical elements between outputs
- Generates accuracy scores
- Creates detailed JSON reports

**Key Metrics Validated:**
- Note count and pitch accuracy
- Duration preservation
- Voice assignment correctness
- Measure structure
- Part organization
- Chord detection

### 2. **Zig Integration Tests (`tests/integration_test.zig`)**
```bash
# Run Zig tests
zig build test
```

Tests:
- Full pipeline conversion
- Chord detection accuracy
- Performance benchmarks
- Memory usage validation

### 3. **Manual Validation Checklist**

When testing a new MIDI file:

- [ ] **Conversion Success**: File converts without errors
- [ ] **Valid MusicXML**: Output validates against MusicXML 4.0 DTD
- [ ] **Note Accuracy**: All notes present with correct pitches
- [ ] **Timing Preservation**: Durations and rhythms maintained
- [ ] **Voice Separation**: Multi-voice parts correctly separated
- [ ] **Chord Detection**: Simultaneous notes grouped as chords
- [ ] **Measure Structure**: Bar lines placed correctly
- [ ] **Performance**: Conversion completes in <100ms for 10MB files

## Performance Benchmarks

### Current Performance (Sweden_Minecraft.mid)
- **File Size**: 1,877 bytes
- **Conversion Time**: ~14ms
- **Notes Processed**: 271
- **Time per Note**: ~4.3μs
- **Output Size**: 82,833 bytes (MusicXML)

### Target Metrics
- **VLQ Parsing**: <10ns per decode
- **Note Processing**: <100ns per note
- **Total Conversion**: <100ms for 10MB MIDI
- **Memory Overhead**: <20% above input size

## Debugging Options

### Verbose Mode
```bash
zmidi2mxl.exe input.mid output.mxl --verbose
```
Shows detailed pipeline execution with timing for each phase.

### Chord Tolerance
```bash
zmidi2mxl.exe input.mid output.mxl --chord-tolerance 10
```
Adjusts timing window for chord detection (in ticks).

### Disable Educational Processing
```bash
zmidi2mxl.exe input.mid output.mxl --no-educational
```
Skips advanced notation processing for faster conversion.

## Common Issues & Solutions

### 1. Integer Overflow in Chord Detector
**Fixed in**: `src/harmony/minimal_chord_detector.zig:135`
- Changed `u4` to `u8` for track index to prevent overflow

### 2. Voice Assignment Not Propagating
**Issue**: Voices assigned but not appearing in output
**Solution**: Check `src/pipeline.zig:429-458` for voice propagation

### 3. Sequential Notes Grouped as Chords
**Solution**: Use `--chord-tolerance 0` for exact timing

## Validation Report Format

The `test_validator.py` generates a JSON report with:
```json
{
  "validation": {
    "our_output": "VALID",
    "reference": "VALID"
  },
  "comparison": {
    "note_count": {"ours": 271, "reference": 271, "match": true},
    "measure_count": {"ours": 65, "reference": 65, "match": true},
    "differences": []
  },
  "accuracy": 1.0,
  "metrics": {
    "total_notes": 271,
    "unique_voices": 7,
    "chord_notes": 34
  }
}
```

## Continuous Integration

Add to your CI/CD pipeline:
```yaml
test:
  script:
    - zig build
    - zig build test
    - python test_validator.py
  artifacts:
    paths:
      - validation_report.json
```

## Next Steps

1. **Expand Test Suite**: Add more MIDI files with various complexities
2. **Automate Reference Generation**: Script MuseScore CLI for reference creation
3. **Performance Regression Tests**: Track conversion speed over time
4. **DTD Validation**: Add strict MusicXML 4.0 DTD validation
5. **Visual Diff Tool**: Create side-by-side MusicXML comparison viewer

## Contact

For issues or improvements to the testing framework, please update this guide or create an issue in the repository.
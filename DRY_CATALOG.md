# DRY Helper Catalog

## Purpose
This catalog documents all approved DRY helpers with their exact signatures, zones, and usage examples. Only helpers that have passed all acceptance gates are listed here.

## Helper Inventory

### 1. `writeIntElement` (GREEN/YELLOW)
**Location**: `src/mxl/xml_helpers.zig` (public)  
**Signature**: `pub fn writeIntElement(xml_writer: *XmlWriter, comptime tag: []const u8, value: anytype) !void`  
**Zone**: GREEN for most uses, YELLOW when used in generator.zig:generateNoteElement  
**Purpose**: Eliminates 3-line integer formatting pattern for XML elements  
**Example**:
```zig
// Before (3 lines)
var buf: [32]u8 = undefined;
const str = try std.fmt.bufPrint(&buf, "{d}", .{duration});
try xml_writer.writeElement("duration", str, null);

// After (1 line)
try xmlh.writeIntElement(xml_writer, "duration", duration);
```
**Impact**: -2 lines per use, 22 uses across 3 files = -44 lines total
**Note**: Moved to shared module to avoid circular dependencies

### 2. `writePitchElement` (GREEN)
**Location**: `src/mxl/generator.zig` (file-private)  
**Signature**: `fn writePitchElement(xml_writer: *XmlWriter, pitch: Pitch) !void`  
**Zone**: GREEN - Safe for all pitch element generation  
**Purpose**: Pure emitter for already-computed Pitch structs  
**Example**:
```zig
// Before (10+ lines)
const pitch = midiToPitch(note);  // KEEP THIS
try xml_writer.startElement("pitch", null);
try xml_writer.writeElement("step", pitch.step, null);
if (pitch.alter != 0) {
    var alter_buf: [8]u8 = undefined;
    const alter_str = try std.fmt.bufPrint(&alter_buf, "{d}", .{pitch.alter});
    try xml_writer.writeElement("alter", alter_str, null);
}
// ... octave handling ...

// After (2 lines)
const pitch = midiToPitch(note);  // KEEP THIS - DON'T MOVE INTO HELPER
try writePitchElement(xml_writer, pitch);
```
**Impact**: -8 lines per use, 4 uses = -32 lines total

### 3. `withArena` (GREEN)
**Location**: `src/utils/helpers.zig` (public)  
**Signature**: `pub fn withArena(comptime func: anytype, parent: std.mem.Allocator, args: anytype) !void`  
**Zone**: GREEN - NEVER use in hot paths or arena tests  
**Purpose**: Arena allocator management for non-critical code  
**Example**:
```zig
// Use only for non-hot, non-test-arena code
try withArena(processDataWithArena, allocator, .{data});
```
**Impact**: -2 lines per use (init + defer)  
**WARNING**: Do NOT use in tests that test arena functionality

### 4. `readU32BE` (GREEN)
**Location**: `src/utils/helpers.zig` (public)  
**Signature**: `pub fn readU32BE(reader: anytype) !u32`  
**Zone**: GREEN - For stream-based reading only  
**Purpose**: Big-endian u32 reading from streams  
**Note**: NOT CURRENTLY USED - pattern mismatch with slice-based reads

### 5. `readU16BE` (GREEN)
**Location**: `src/utils/helpers.zig` (public)  
**Signature**: `pub fn readU16BE(reader: anytype) !u16`  
**Zone**: GREEN - For stream-based reading only  
**Purpose**: Big-endian u16 reading from streams  
**Note**: NOT CURRENTLY USED - pattern mismatch with slice-based reads

## Zone Definitions

- **RED**: Hot paths - NO modifications without proof of improvement
  - `parseVlq`, `parseVlqFast`, `parseNextEvent`, inner conversion loops
- **YELLOW**: Performance sensitive - modifications require ±1% benchmark proof
  - Track parsing, note processing, some XML generation
- **GREEN**: Safe to refactor with standard validation
  - Educational processor, logging, error handling, test code

## Validation Requirements

Every helper must pass ALL gates before inclusion:
1. **Scope**: Only touches designated file:line ranges
2. **Semantics**: Pure DRY - no behavior change
3. **Performance**: Within ±1% for GREEN/YELLOW, faster for RED
4. **Complexity**: Net LOC down, callsites clearer
5. **Determinism**: MXL output byte-identical

## Usage Guidelines

1. **Default to file-private**: Only make public if 2+ files need it
2. **No allocations in hot paths**: Keep helpers zero-cost
3. **No semantic coupling**: Helpers should be pure transformers
4. **Stack buffers for literals**: Use comptime sizes when possible
5. **Document zones**: Always specify if helper is RED/YELLOW/GREEN

## Rejected Patterns

The following were considered but rejected:
- **ManagedList**: Wrapper types add no value
- **DeferChain**: Zig lacks capturing closures
- **Generic error logger**: Type inference issues
- **Arena test helpers**: Would mask allocation bugs
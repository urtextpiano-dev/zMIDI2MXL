# Cross-Machine Determinism Verification

## Purpose
Ensure MXL output is byte-identical across different machines and platforms.

## Requirements
- Same Zig version (0.14.0)
- Same source code commit
- Same input MIDI files

## Test Protocol

### Machine 1 (Windows)
```bash
# Build with STORE compression for absolute determinism
zig build -Doptimize=ReleaseFast
zig-out\bin\zmidi2mxl.exe Sweden_Minecraft.mid test_windows.mxl

# Generate hash
certutil -hashfile test_windows.mxl SHA256 > windows_hash.txt
```

### Machine 2 (Linux)
```bash
# Build with STORE compression for absolute determinism
zig build -Doptimize=ReleaseFast
./zig-out/bin/zmidi2mxl Sweden_Minecraft.mid test_linux.mxl

# Generate hash
sha256sum test_linux.mxl > linux_hash.txt
```

### Verification
1. Compare SHA256 hashes - must be identical
2. Binary diff the MXL files - must be identical
3. Extract and compare MusicXML content - must be identical

## Using STORE Compression for Determinism

To use STORE (no compression) for absolute cross-machine determinism:

```zig
// In main.zig, when creating ZipWriter:
var zip_writer = mxl.ZipWriter.initWithStrategy(
    allocator, 
    output_file.writer().any(),
    .store  // Use STORE for determinism
);
```

## Expected Results
- Hashes: Identical SHA256
- File size: Identical byte count
- Binary content: Identical bytes
- ZIP structure: Identical entries in same order

## Troubleshooting

### If hashes differ:
1. Check Zig version: `zig version`
2. Check git commit: `git rev-parse HEAD`
3. Use STORE compression instead of DEFLATE
4. Verify fixed timestamps in zip_writer.zig
5. Check file entry ordering is sorted

### Known Issues:
- DEFLATE compression may vary slightly between zlib versions
- Use STORE compression for absolute determinism
- Ensure all timestamps are fixed (2024-01-01 12:00:00)
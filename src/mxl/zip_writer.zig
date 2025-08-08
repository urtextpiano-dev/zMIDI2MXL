const std = @import("std");

// Implements TASK-010 per MXL_Architecture_Reference.md Section 7 lines 923-1070
// ZIP Archive Generator for MXL format with DEFLATE compression

// Local error for compression and ZIP validation
const ZipError = error{
    CompressionFailed,
    InvalidFilename,
    FilenameTooLong,
    FileTooLarge,
    OffsetOverflow,
};

/// ZIP format constants
const ZIP_LOCAL_FILE_HEADER_SIGNATURE: u32 = 0x04034b50; // "PK\x03\x04"
const ZIP_CENTRAL_DIR_HEADER_SIGNATURE: u32 = 0x02014b50; // "PK\x01\x02"
const ZIP_END_OF_CENTRAL_DIR_SIGNATURE: u32 = 0x06054b50; // "PK\x05\x06"

/// Compression methods
const COMPRESSION_METHOD_STORE: u16 = 0;
const COMPRESSION_METHOD_DEFLATE: u16 = 8;

/// ZIP version needed to extract
const ZIP_VERSION_NEEDED: u16 = 20; // 2.0 - supports DEFLATE

/// General purpose bit flags
const FLAG_UTF8_ENCODING: u16 = 0x0800; // Bit 11 - UTF-8 filename encoding

/// CRC-32 polynomial for ZIP
const CRC32_POLYNOMIAL: u32 = 0xEDB88320;

/// Entry information for central directory
const ZipEntry = struct {
    filename: []const u8,
    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
    offset: u32,
    compression_method: u16,
    mod_time: u16,
    mod_date: u16,
};

/// ZIP writer for creating MXL archives
pub const ZipWriter = struct {
    allocator: std.mem.Allocator,
    writer: std.io.AnyWriter,
    entries: std.ArrayList(ZipEntry),
    current_offset: u32,
    crc_table: [256]u32,

    /// Initialize a new ZIP writer
    pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter) ZipWriter {
        var self = ZipWriter{
            .allocator = allocator,
            .writer = writer,
            .entries = std.ArrayList(ZipEntry).init(allocator),
            .current_offset = 0,
            .crc_table = undefined,
        };
        self.initCrcTable();
        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *ZipWriter) void {
        self.entries.deinit();
    }

    /// Initialize CRC-32 lookup table
    fn initCrcTable(self: *ZipWriter) void {
        for (0..256) |i| {
            var crc: u32 = @intCast(i);
            for (0..8) |_| {
                if (crc & 1 != 0) {
                    crc = (crc >> 1) ^ CRC32_POLYNOMIAL;
                } else {
                    crc >>= 1;
                }
            }
            self.crc_table[i] = crc;
        }
    }

    /// Calculate CRC-32 checksum
    /// Implements TASK-010 per MXL_Architecture_Reference.md Section 7.2 lines 951-967
    pub fn calculateCrc32(self: *const ZipWriter, data: []const u8) u32 {
        var crc: u32 = 0xFFFFFFFF;
        
        for (data) |byte| {
            const table_idx = @as(u8, @truncate(crc ^ byte));
            crc = (crc >> 8) ^ self.crc_table[table_idx];
        }
        
        return crc ^ 0xFFFFFFFF;
    }

    /// Add a file to the ZIP archive
    /// Implements TASK-010 per MXL_Architecture_Reference.md Section 7.4 lines 996-1022
    pub fn addFile(
        self: *ZipWriter,
        filename: []const u8,
        data: []const u8,
        compress: bool,
    ) !void {
        // Validate inputs to prevent corruption
        if (filename.len == 0) return error.InvalidFilename;
        if (filename.len > 65535) return error.FilenameTooLong;
        if (data.len > std.math.maxInt(u32)) return error.FileTooLarge;
        // For simplicity, use a fixed date/time for now
        // This can be enhanced later to use actual timestamps
        // Date: 2024-01-01, Time: 12:00:00
        const mod_date: u16 = ((2024 - 1980) << 9) | (1 << 5) | 1;  // Year 2024, Month 1, Day 1
        const mod_time: u16 = (12 << 11) | (0 << 5) | 0;  // Hour 12, Minute 0, Second 0

        const entry_offset = self.current_offset;
        
        // Compress data if requested
        var compressed_data: []u8 = undefined;
        var should_free = false;
        const compression_method = if (compress and filename.len > 0 and !std.mem.eql(u8, filename, "mimetype")) blk: {
            compressed_data = try self.compressDeflate(data);
            should_free = true;
            break :blk COMPRESSION_METHOD_DEFLATE;
        } else blk: {
            compressed_data = @constCast(data);
            break :blk COMPRESSION_METHOD_STORE;
        };
        defer if (should_free) self.allocator.free(compressed_data);

        // Calculate CRC-32 of uncompressed data
        const crc32 = self.calculateCrc32(data);

        // Write local file header
        try self.writeLocalFileHeader(
            filename,
            crc32,
            @intCast(compressed_data.len),
            @intCast(data.len),
            compression_method,
            mod_time,
            mod_date,
        );

        // Write file data
        try self.writer.writeAll(compressed_data);
        
        // CRITICAL FIX: Update offset tracking after writing file data
        // Implements TASK-010 per MXL_Architecture_Reference.md Section 7.4 lines 996-1022
        // This prevents ZIP corruption from incorrect offset calculations
        const new_offset = self.current_offset + @as(u32, @intCast(compressed_data.len));
        if (new_offset < self.current_offset) return ZipError.OffsetOverflow; // Detect overflow
        self.current_offset = new_offset;

        // Store entry info for central directory
        try self.entries.append(.{
            .filename = try self.allocator.dupe(u8, filename),
            .crc32 = crc32,
            .compressed_size = @intCast(compressed_data.len),
            .uncompressed_size = @intCast(data.len),
            .offset = entry_offset,
            .compression_method = compression_method,
            .mod_time = mod_time,
            .mod_date = mod_date,
        });
    }

    /// Write local file header
    fn writeLocalFileHeader(
        self: *ZipWriter,
        filename: []const u8,
        crc32: u32,
        compressed_size: u32,
        uncompressed_size: u32,
        compression_method: u16,
        mod_time: u16,
        mod_date: u16,
    ) !void {
        // Signature
        try self.writer.writeInt(u32, ZIP_LOCAL_FILE_HEADER_SIGNATURE, .little);
        self.current_offset += 4;

        // Version needed to extract
        try self.writer.writeInt(u16, ZIP_VERSION_NEEDED, .little);
        self.current_offset += 2;

        // General purpose bit flag (UTF-8 encoding)
        try self.writer.writeInt(u16, FLAG_UTF8_ENCODING, .little);
        self.current_offset += 2;

        // Compression method
        try self.writer.writeInt(u16, compression_method, .little);
        self.current_offset += 2;

        // Last mod file time
        try self.writer.writeInt(u16, mod_time, .little);
        self.current_offset += 2;

        // Last mod file date
        try self.writer.writeInt(u16, mod_date, .little);
        self.current_offset += 2;

        // CRC-32
        try self.writer.writeInt(u32, crc32, .little);
        self.current_offset += 4;

        // Compressed size
        try self.writer.writeInt(u32, compressed_size, .little);
        self.current_offset += 4;

        // Uncompressed size
        try self.writer.writeInt(u32, uncompressed_size, .little);
        self.current_offset += 4;

        // File name length
        try self.writer.writeInt(u16, @intCast(filename.len), .little);
        self.current_offset += 2;

        // Extra field length
        try self.writer.writeInt(u16, 0, .little);
        self.current_offset += 2;

        // File name
        try self.writer.writeAll(filename);
        self.current_offset += @intCast(filename.len);
    }

    /// Compress data using DEFLATE
    /// Implements TASK-010 per MXL_Architecture_Reference.md Section 7.3 lines 970-986
    fn compressDeflate(self: *ZipWriter, data: []const u8) ![]u8 {
        var compressed = std.ArrayList(u8).init(self.allocator);
        defer compressed.deinit();

        // Use zlib compression
        var stream = try std.compress.zlib.compressor(compressed.writer(), .{});
        try stream.writer().writeAll(data);
        try stream.finish();

        // Extract raw DEFLATE data (skip zlib header and checksum)
        const zlib_data = compressed.items;
        if (zlib_data.len < 6) return ZipError.CompressionFailed;
        
        // Skip 2-byte header and 4-byte Adler32 checksum at the end
        const deflate_data = try self.allocator.alloc(u8, zlib_data.len - 6);
        @memcpy(deflate_data, zlib_data[2..zlib_data.len - 4]);
        
        return deflate_data;
    }

    /// Finalize the ZIP archive by writing central directory
    /// Implements TASK-010 per MXL_Architecture_Reference.md Section 7.4 lines 1023-1039
    pub fn finalize(self: *ZipWriter) !void {
        const central_dir_offset = self.current_offset;

        // Write central directory headers
        for (self.entries.items) |entry| {
            try self.writeCentralDirectoryHeader(entry);
        }

        const central_dir_size = self.current_offset - central_dir_offset;

        // Write end of central directory record
        try self.writeEndOfCentralDirectory(
            @intCast(self.entries.items.len),
            central_dir_size,
            central_dir_offset,
        );

        // Free allocated filenames
        for (self.entries.items) |entry| {
            self.allocator.free(entry.filename);
        }
    }

    /// Write central directory header
    fn writeCentralDirectoryHeader(self: *ZipWriter, entry: ZipEntry) !void {
        // Signature
        try self.writer.writeInt(u32, ZIP_CENTRAL_DIR_HEADER_SIGNATURE, .little);
        self.current_offset += 4;

        // Version made by (2.0)
        try self.writer.writeInt(u16, ZIP_VERSION_NEEDED, .little);
        self.current_offset += 2;

        // Version needed to extract
        try self.writer.writeInt(u16, ZIP_VERSION_NEEDED, .little);
        self.current_offset += 2;

        // General purpose bit flag
        try self.writer.writeInt(u16, FLAG_UTF8_ENCODING, .little);
        self.current_offset += 2;

        // Compression method
        try self.writer.writeInt(u16, entry.compression_method, .little);
        self.current_offset += 2;

        // Last mod file time
        try self.writer.writeInt(u16, entry.mod_time, .little);
        self.current_offset += 2;

        // Last mod file date  
        try self.writer.writeInt(u16, entry.mod_date, .little);
        self.current_offset += 2;

        // CRC-32
        try self.writer.writeInt(u32, entry.crc32, .little);
        self.current_offset += 4;

        // Compressed size
        try self.writer.writeInt(u32, entry.compressed_size, .little);
        self.current_offset += 4;

        // Uncompressed size
        try self.writer.writeInt(u32, entry.uncompressed_size, .little);
        self.current_offset += 4;

        // File name length
        try self.writer.writeInt(u16, @intCast(entry.filename.len), .little);
        self.current_offset += 2;

        // Extra field length
        try self.writer.writeInt(u16, 0, .little);
        self.current_offset += 2;

        // File comment length
        try self.writer.writeInt(u16, 0, .little);
        self.current_offset += 2;

        // Disk number start
        try self.writer.writeInt(u16, 0, .little);
        self.current_offset += 2;

        // Internal file attributes
        try self.writer.writeInt(u16, 0, .little);
        self.current_offset += 2;

        // External file attributes
        try self.writer.writeInt(u32, 0, .little);
        self.current_offset += 4;

        // Relative offset of local header
        try self.writer.writeInt(u32, entry.offset, .little);
        self.current_offset += 4;

        // File name
        try self.writer.writeAll(entry.filename);
        self.current_offset += @intCast(entry.filename.len);
    }

    /// Write end of central directory record
    fn writeEndOfCentralDirectory(
        self: *ZipWriter,
        num_entries: u16,
        central_dir_size: u32,
        central_dir_offset: u32,
    ) !void {
        // Signature
        try self.writer.writeInt(u32, ZIP_END_OF_CENTRAL_DIR_SIGNATURE, .little);

        // Number of this disk
        try self.writer.writeInt(u16, 0, .little);

        // Number of disk with start of central directory
        try self.writer.writeInt(u16, 0, .little);

        // Total number of entries on this disk
        try self.writer.writeInt(u16, num_entries, .little);

        // Total number of entries
        try self.writer.writeInt(u16, num_entries, .little);

        // Size of central directory
        try self.writer.writeInt(u32, central_dir_size, .little);

        // Offset of start of central directory
        try self.writer.writeInt(u32, central_dir_offset, .little);

        // ZIP file comment length
        try self.writer.writeInt(u16, 0, .little);
    }
};

/// Helper to create container.xml content
pub fn createContainerXml(allocator: std.mem.Allocator, musicxml_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<container>
        \\  <rootfiles>
        \\    <rootfile full-path="{s}" media-type="application/vnd.recordare.musicxml+xml"/>
        \\  </rootfiles>
        \\</container>
        \\
    ,
        .{musicxml_path},
    );
}

// Tests

test "CRC-32 calculation" {
    var writer = ZipWriter.init(std.testing.allocator, std.io.null_writer.any());
    defer writer.deinit();

    // Test with known values
    const test_data = "The quick brown fox jumps over the lazy dog";
    const crc = writer.calculateCrc32(test_data);
    
    // This is the known CRC-32 for this string
    try std.testing.expectEqual(@as(u32, 0x414FA339), crc);
}

test "create simple ZIP file" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = ZipWriter.init(std.testing.allocator, buffer.writer().any());
    defer writer.deinit();

    // Add a test file
    try writer.addFile("test.txt", "Hello, World!", false);
    try writer.finalize();

    // Verify ZIP structure
    const data = buffer.items;
    
    // Check local file header signature
    const sig = std.mem.readInt(u32, data[0..4], .little);
    try std.testing.expectEqual(ZIP_LOCAL_FILE_HEADER_SIGNATURE, sig);

    // Check that end of central directory exists
    const eocd_sig = std.mem.readInt(u32, data[data.len - 22 .. data.len - 18][0..4], .little);
    try std.testing.expectEqual(ZIP_END_OF_CENTRAL_DIR_SIGNATURE, eocd_sig);
}

test "create MXL with container.xml" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = ZipWriter.init(std.testing.allocator, buffer.writer().any());
    defer writer.deinit();

    // Add container.xml
    const container_content = try createContainerXml(std.testing.allocator, "score.xml");
    defer std.testing.allocator.free(container_content);
    
    try writer.addFile("META-INF/container.xml", container_content, true);
    
    // Add a dummy score
    try writer.addFile("score.xml", "<score-partwise version=\"4.0\"/>", true);
    
    try writer.finalize();

    // Basic validation
    try std.testing.expect(buffer.items.len > 0);
}

test "compression performance" {
    // Test that compression meets performance target (20MB/s)
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = ZipWriter.init(std.testing.allocator, buffer.writer().any());
    defer writer.deinit();

    // Create 1MB of test data
    const size = 1024 * 1024;
    const test_data = try std.testing.allocator.alloc(u8, size);
    defer std.testing.allocator.free(test_data);
    
    // Fill with compressible pattern
    for (test_data, 0..) |*byte, i| {
        byte.* = @truncate(i % 256);
    }

    const start = std.time.nanoTimestamp();
    try writer.addFile("test.dat", test_data, true);
    const end = std.time.nanoTimestamp();

    const elapsed_ns = @as(u64, @intCast(end - start));
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
    const mb_per_s = 1.0 / elapsed_s;

    std.debug.print("Compression performance: {d:.2} MB/s\n", .{mb_per_s});
    
    // Should meet 20MB/s target
    try std.testing.expect(mb_per_s >= 20.0);
    
    // Clean up the entry to avoid leak
    try writer.finalize();
}

test "ZIP file ordering" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = ZipWriter.init(std.testing.allocator, buffer.writer().any());
    defer writer.deinit();

    // Add files in MXL-required order
    try writer.addFile("mimetype", "application/vnd.recordare.musicxml", false);
    try writer.addFile("META-INF/container.xml", "<container/>", true);
    try writer.addFile("score.xml", "<score/>", true);
    
    try writer.finalize();

    // Verify mimetype is first and uncompressed
    const data = buffer.items;
    
    // Skip to filename in first local header (at offset 30)
    const first_filename = data[30..30 + 8];
    try std.testing.expectEqualStrings("mimetype", first_filename);
    
    // Check compression method (at offset 8 in local header)
    const compression_method = std.mem.readInt(u16, data[8..10], .little);
    try std.testing.expectEqual(COMPRESSION_METHOD_STORE, compression_method);
}
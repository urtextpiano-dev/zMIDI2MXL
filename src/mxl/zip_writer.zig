const std = @import("std");
const containers = @import("../utils/containers.zig");
const log = @import("../utils/log.zig");
const xml_mod = @import("xml_writer.zig");

// Implements TASK-010 per MXL_Architecture_Reference.md Section 7 lines 923-1070
// ZIP Archive Generator for MXL format with DEFLATE compression

// Local error set for input/size/offset validation
const ZipError = error{
    CompressionFailed,
    InvalidFilename,
    FilenameTooLong,
    FileTooLarge,
    OffsetOverflow,
    InvalidUtf8,
};

/// ZIP format constants
const ZIP_LOCAL_FILE_HEADER_SIGNATURE: u32 = 0x0403_4b50; // "PK\x03\x04"
const ZIP_CENTRAL_DIR_HEADER_SIGNATURE: u32 = 0x0201_4b50; // "PK\x01\x02"
const ZIP_END_OF_CENTRAL_DIR_SIGNATURE: u32 = 0x0605_4b50; // "PK\x05\x06"

/// Compression methods
const COMPRESSION_METHOD_STORE: u16 = 0;
const COMPRESSION_METHOD_DEFLATE: u16 = 8;

/// ZIP version needed to extract
const ZIP_VERSION_NEEDED: u16 = 20; // 2.0 - supports DEFLATE

/// General purpose bit flags
const FLAG_UTF8_ENCODING: u16 = 0x0800; // Bit 11 - UTF-8 filename encoding

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
    entries: containers.List(ZipEntry),
    current_offset: u32,

    /// Initialize a new ZIP writer
    pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter) ZipWriter {
        return .{
            .allocator = allocator,
            .writer = writer,
            .entries = containers.List(ZipEntry).init(allocator),
            .current_offset = 0,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *ZipWriter) void {
        self.entries.deinit();
    }

    /// Calculate CRC-32 checksum (IEEE) — stdlib, clear and correct
    /// Implements TASK-010 per MXL_Architecture_Reference.md Section 7.2 lines 951-967
    pub fn calculateCrc32(self: *const ZipWriter, data: []const u8) u32 {
        _ = self;
        var h = std.hash.crc.Crc32.init();
        h.update(data);
        return h.final();
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
        if (filename.len == 0) return ZipError.InvalidFilename;
        if (filename.len > 65535) return ZipError.FilenameTooLong;
        // Validate filename is UTF-8 since we set FLAG_UTF8_ENCODING
        if (std.unicode.Utf8View.init(filename)) |_| {} else |_| {
            return ZipError.InvalidUtf8;
        }
        if (data.len > std.math.maxInt(u32)) return ZipError.FileTooLarge;

        // Fixed timestamp (can be improved later)
        const mod_date: u16 = ((2024 - 1980) << 9) | (1 << 5) | 1; // 2024-01-01
        const mod_time: u16 = (12 << 11) | (0 << 5) | 0; // 12:00:00

        const entry_offset = self.current_offset;

        // Compress data if requested (and not the "mimetype" special case)
        var compressed_data: []u8 = undefined;
        var must_free = false;
        const compression_method: u16 = if (compress and !std.mem.eql(u8, filename, "mimetype")) blk: {
            compressed_data = try self.compressDeflate(data);
            must_free = true;
            break :blk COMPRESSION_METHOD_DEFLATE;
        } else blk: {
            compressed_data = @constCast(data);
            break :blk COMPRESSION_METHOD_STORE;
        };
        defer if (must_free) self.allocator.free(compressed_data);

        // CRC-32 of *uncompressed* data
        const crc32 = self.calculateCrc32(data);

        // Local file header
        try self.writeLocalFileHeader(
            filename,
            crc32,
            @intCast(compressed_data.len),
            @intCast(data.len),
            compression_method,
            mod_time,
            mod_date,
        );

        // File data
        try self.writeBytes(compressed_data);

        // Store entry for central directory
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
        try self.wU32(ZIP_LOCAL_FILE_HEADER_SIGNATURE);
        try self.wU16(ZIP_VERSION_NEEDED);
        try self.wU16(FLAG_UTF8_ENCODING); // UTF-8 filenames
        try self.wU16(compression_method);
        try self.wU16(mod_time);
        try self.wU16(mod_date);
        try self.wU32(crc32);
        try self.wU32(compressed_size);
        try self.wU32(uncompressed_size);
        try self.wU16(@intCast(filename.len)); // file name length
        try self.wU16(0); // extra field length
        try self.writeBytes(filename); // file name
    }

    /// Compress data using DEFLATE (raw) by stripping zlib wrapper
    /// Implements TASK-010 per MXL_Architecture_Reference.md Section 7.3 lines 970-986
    fn compressDeflate(self: *ZipWriter, data: []const u8) ![]u8 {
        var compressed = containers.List(u8).init(self.allocator);
        defer compressed.deinit();

        var stream = try std.compress.zlib.compressor(compressed.writer(), .{});
        try stream.writer().writeAll(data);
        try stream.finish();

        const z = compressed.items;
        if (z.len < 6) return ZipError.CompressionFailed;

        // Strip zlib 2-byte header and 4-byte Adler32 trailer → raw deflate
        const out = try self.allocator.alloc(u8, z.len - 6);
        @memcpy(out, z[2 .. z.len - 4]);
        return out;
    }

    /// Finalize the ZIP archive by writing central directory
    /// Implements TASK-010 per MXL_Architecture_Reference.md Section 7.4 lines 1023-1039
    pub fn finalize(self: *ZipWriter) !void {
        const central_dir_offset = self.current_offset;

        // Central directory headers
        for (self.entries.items) |entry| {
            try self.writeCentralDirectoryHeader(entry);
        }

        const central_dir_size: u32 = self.current_offset - central_dir_offset;

        // End of central directory record
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
        try self.wU32(ZIP_CENTRAL_DIR_HEADER_SIGNATURE);
        try self.wU16(ZIP_VERSION_NEEDED); // version made by (keep 2.0)
        try self.wU16(ZIP_VERSION_NEEDED); // version needed to extract
        try self.wU16(FLAG_UTF8_ENCODING);
        try self.wU16(entry.compression_method);
        try self.wU16(entry.mod_time);
        try self.wU16(entry.mod_date);
        try self.wU32(entry.crc32);
        try self.wU32(entry.compressed_size);
        try self.wU32(entry.uncompressed_size);
        try self.wU16(@intCast(entry.filename.len)); // file name length
        try self.wU16(0); // extra field length
        try self.wU16(0); // file comment length
        try self.wU16(0); // disk number start
        try self.wU16(0); // internal file attrs
        try self.wU32(0); // external file attrs
        try self.wU32(entry.offset); // relative offset of local header
        try self.writeBytes(entry.filename); // file name
    }

    /// Write end of central directory record
    fn writeEndOfCentralDirectory(
        self: *ZipWriter,
        num_entries: u16,
        central_dir_size: u32,
        central_dir_offset: u32,
    ) !void {
        try self.wU32(ZIP_END_OF_CENTRAL_DIR_SIGNATURE);
        try self.wU16(0); // number of this disk
        try self.wU16(0); // disk with start of central dir
        try self.wU16(num_entries); // total entries on this disk
        try self.wU16(num_entries); // total entries
        try self.wU32(central_dir_size); // size of central directory
        try self.wU32(central_dir_offset); // offset of start of central directory
        try self.wU16(0); // zip file comment length
    }

    // ----------------
    // Private helpers
    // ----------------

    inline fn bump(self: *ZipWriter, add: u32) !void {
        const new = self.current_offset + add;
        if (new < self.current_offset) return ZipError.OffsetOverflow;
        self.current_offset = new;
    }

    inline fn wU16(self: *ZipWriter, v: u16) !void {
        try self.writer.writeInt(u16, v, .little);
        try self.bump(2);
    }

    inline fn wU32(self: *ZipWriter, v: u32) !void {
        try self.writer.writeInt(u32, v, .little);
        try self.bump(4);
    }

    inline fn writeBytes(self: *ZipWriter, bytes: []const u8) !void {
        try self.writer.writeAll(bytes);
        try self.bump(@intCast(bytes.len));
    }
};

/// Helper to create META-INF/container.xml content for MXL (OCF)
pub fn createContainerXml(allocator: std.mem.Allocator, musicxml_path: []const u8) ![]u8 {
    _ = std.unicode.Utf8View.init(musicxml_path) catch return error.InvalidUtf8;

    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();

    var xml = xml_mod.XmlWriter.init(allocator, buf.writer().any());
    defer xml.deinit();

    try xml.writeDeclaration();
    try xml.startElement("container", &[_]xml_mod.Attribute{
        .{ .name = "version", .value = "1.0" },
        .{ .name = "xmlns", .value = "urn:oasis:names:tc:opendocument:xmlns:container" },
    });

    try xml.startElement("rootfiles", null);
    try xml.writeEmptyElement("rootfile", &[_]xml_mod.Attribute{
        .{ .name = "full-path", .value = musicxml_path },
        .{ .name = "media-type", .value = "application/vnd.recordare.musicxml+xml" },
    });
    try xml.endElement(); // rootfiles
    try xml.endElement(); // container

    return buf.toOwnedSlice();
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
    var buffer = containers.List(u8).init(std.testing.allocator);
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
    var buffer = containers.List(u8).init(std.testing.allocator);
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
    var buffer = containers.List(u8).init(std.testing.allocator);
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

    log.debug("Compression performance: {d:.2} MB/s", .{mb_per_s});

    // Should meet 20MB/s target
    try std.testing.expect(mb_per_s >= 20.0);

    // Clean up the entry to avoid leak
    try writer.finalize();
}

test "ZIP file ordering" {
    var buffer = containers.List(u8).init(std.testing.allocator);
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
    const first_filename = data[30 .. 30 + 8];
    try std.testing.expectEqualStrings("mimetype", first_filename);

    // Check compression method (at offset 8 in local header)
    const compression_method = std.mem.readInt(u16, data[8..10], .little);
    try std.testing.expectEqual(COMPRESSION_METHOD_STORE, compression_method);
}

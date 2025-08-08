const std = @import("std");

// Implements TASK-002 per MIDI_Architecture_Reference.md Section 10.1 lines 1213-1244
// Custom error types for the MIDI to MXL converter

// Error severity levels matching the specification
pub const ErrorSeverity = enum(u8) {
    info = 0,     // Informational, continue processing
    warning = 1,  // Potentially problematic, but recoverable
    err = 2,      // Serious issue, may affect output (avoiding 'error' keyword)
    fatal = 3,    // Cannot continue processing
};

// Core error types for MIDI parsing
pub const MidiError = error{
    // File structure errors
    InvalidMagicNumber,
    InvalidHeaderLength,
    InvalidChunkType,
    IncompleteHeader,
    IncompleteData,
    UnexpectedEndOfFile,
    
    // Event parsing errors
    InvalidStatusByte,
    InvalidVlqEncoding,
    MissingRunningStatus,
    InvalidEventData,
    TruncatedSysEx,
    
    // Musical semantic errors
    OrphanedNoteOff,
    InvalidTempo,
    InvalidTimeSignature,
    InvalidKeySignature,
    
    // Track errors
    MissingEndOfTrack,
    InvalidTrackLength,
    TrackDataMismatch,
};

// Error types for MusicXML generation
pub const MxlError = error{
    InvalidXmlStructure,
    InvalidNoteType,
    InvalidDivisionValue,
    CompressionFailed,
    InvalidZipStructure,
};

// General converter errors
pub const ConverterError = error{
    OutOfMemory,
    FileNotFound,
    PermissionDenied,
    InvalidArgument,
    ConversionFailed,
};

// Combined error set for the entire application
pub const Error = MidiError || MxlError || ConverterError || std.fs.File.WriteError || std.fs.File.OpenError;

// Error context information for better debugging
pub const ErrorContext = struct {
    severity: ErrorSeverity,
    message: []const u8,
    file_position: ?u64 = null,
    track_number: ?u32 = null,
    tick_position: ?u32 = null,
    
    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("[{s}] {s}", .{ @tagName(self.severity), self.message });
        
        if (self.file_position) |pos| {
            try writer.print(" at byte 0x{X}", .{pos});
        }
        
        if (self.track_number) |track| {
            try writer.print(" in track {d}", .{track});
        }
        
        if (self.tick_position) |tick| {
            try writer.print(" at tick {d}", .{tick});
        }
    }
};

// Error handler for managing errors during processing
pub const ErrorHandler = struct {
    errors: std.ArrayList(ErrorContext),
    strict_mode: bool,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, strict: bool) ErrorHandler {
        return .{
            .errors = std.ArrayList(ErrorContext).init(allocator),
            .strict_mode = strict,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ErrorHandler) void {
        self.errors.deinit();
    }
    
    // Handle an error according to its severity
    pub fn handleError(
        self: *ErrorHandler,
        severity: ErrorSeverity,
        message: []const u8,
        context: struct {
            file_position: ?u64 = null,
            track_number: ?u32 = null,
            tick_position: ?u32 = null,
        },
    ) !void {
        const err_context = ErrorContext{
            .severity = severity,
            .message = message,
            .file_position = context.file_position,
            .track_number = context.track_number,
            .tick_position = context.tick_position,
        };
        
        try self.errors.append(err_context);
        
        // In strict mode, throw on errors
        if (self.strict_mode and @intFromEnum(severity) >= @intFromEnum(ErrorSeverity.err)) {
            return MidiError.InvalidEventData;
        }
        
        // Always throw on fatal errors
        if (severity == .fatal) {
            return MidiError.UnexpectedEndOfFile;
        }
    }
    
    // Get count of errors by severity
    pub fn getErrorCount(self: *const ErrorHandler, severity: ErrorSeverity) usize {
        var count: usize = 0;
        for (self.errors.items) |err| {
            if (err.severity == severity) {
                count += 1;
            }
        }
        return count;
    }
    
    // Check if there are any serious errors
    pub fn hasErrors(self: *const ErrorHandler) bool {
        for (self.errors.items) |err| {
            if (@intFromEnum(err.severity) >= @intFromEnum(ErrorSeverity.err)) {
                return true;
            }
        }
        return false;
    }
    
    // Clear all recorded errors
    pub fn clear(self: *ErrorHandler) void {
        self.errors.clearRetainingCapacity();
    }
};

// Tests for error handling
test "ErrorHandler basic functionality" {
    var handler = ErrorHandler.init(std.testing.allocator, false);
    defer handler.deinit();
    
    // Test adding different severity levels
    try handler.handleError(.info, "Test info message", .{});
    try handler.handleError(.warning, "Test warning", .{ .file_position = 100 });
    
    try std.testing.expectEqual(@as(usize, 1), handler.getErrorCount(.info));
    try std.testing.expectEqual(@as(usize, 1), handler.getErrorCount(.warning));
    try std.testing.expectEqual(false, handler.hasErrors());
}

test "ErrorHandler strict mode" {
    var handler = ErrorHandler.init(std.testing.allocator, true);
    defer handler.deinit();
    
    // In strict mode, errors should throw
    try handler.handleError(.warning, "Test warning", .{});
    
    // This should throw an error
    const result = handler.handleError(.err, "Test error", .{});
    try std.testing.expectError(MidiError.InvalidEventData, result);
}

test "ErrorContext formatting" {
    const context = ErrorContext{
        .severity = .warning,
        .message = "Invalid note velocity",
        .file_position = 0x1234,
        .track_number = 2,
        .tick_position = 96,
    };
    
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    
    try std.fmt.format(stream.writer(), "{any}", .{context});
    
    const expected = "[warning] Invalid note velocity at byte 0x1234 in track 2 at tick 96";
    try std.testing.expectEqualStrings(expected, stream.getWritten());
}
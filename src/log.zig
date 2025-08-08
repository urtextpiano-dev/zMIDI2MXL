const std = @import("std");

// Implements TASK-002 per MIDI_Architecture_Reference.md Section 10.2 lines 1246-1264
// Basic logging infrastructure for the MIDI to MXL converter

// Log levels matching the specification
pub const LogLevel = enum(u8) {
    trace = 0,  // Byte-level operations
    debug = 1,  // Event parsing details
    info = 2,   // High-level operations
    warn = 3,   // Recoverable issues
    err = 4,    // Serious problems
    
    pub fn fromString(str: []const u8) ?LogLevel {
        if (std.mem.eql(u8, str, "trace")) return .trace;
        if (std.mem.eql(u8, str, "debug")) return .debug;
        if (std.mem.eql(u8, str, "info")) return .info;
        if (std.mem.eql(u8, str, "warn")) return .warn;
        if (std.mem.eql(u8, str, "err")) return .err;
        return null;
    }
};

// Logger configuration
pub const LogConfig = struct {
    level: LogLevel = .info,
    show_timestamp: bool = true,
    show_location: bool = true,
    writer: std.io.AnyWriter = std.io.getStdErr().writer().any(),
};

// Main logger structure
pub const Logger = struct {
    config: LogConfig,
    mutex: std.Thread.Mutex,
    
    pub fn init(config: LogConfig) Logger {
        return .{
            .config = config,
            .mutex = std.Thread.Mutex{},
        };
    }
    
    // Check if a log level is enabled
    pub fn isEnabled(self: *const Logger, level: LogLevel) bool {
        return @intFromEnum(level) >= @intFromEnum(self.config.level);
    }
    
    // Core logging function
    pub fn log(
        self: *Logger,
        level: LogLevel,
        comptime format: []const u8,
        args: anytype,
    ) void {
        if (!self.isEnabled(level)) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Build the log message
        if (self.config.show_timestamp) {
            const timestamp = std.time.milliTimestamp();
            self.config.writer.print("[{d}] ", .{timestamp}) catch return;
        }
        
        // Log level
        const level_str = switch (level) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO ",
            .warn => "WARN ",
            .err => "ERROR",
        };
        self.config.writer.print("[{s}] ", .{level_str}) catch return;
        
        // Actual message
        self.config.writer.print(format, args) catch return;
        self.config.writer.writeAll("\n") catch return;
    }
    
    // Convenience methods for each log level
    pub fn trace(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.trace, format, args);
    }
    
    pub fn debug(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.debug, format, args);
    }
    
    pub fn info(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.info, format, args);
    }
    
    pub fn warn(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.warn, format, args);
    }
    
    pub fn err(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.err, format, args);
    }
    
    // Log an event with location information
    pub fn logEvent(
        self: *Logger,
        level: LogLevel,
        track: ?u32,
        tick: ?u32,
        comptime format: []const u8,
        args: anytype,
    ) void {
        if (!self.isEnabled(level)) return;
        
        // Build location string if enabled
        if (self.config.show_location and (track != null or tick != null)) {
            var location_buf: [64]u8 = undefined;
            var stream = std.io.fixedBufferStream(&location_buf);
            const writer = stream.writer();
            
            writer.writeAll("Track ") catch return;
            if (track) |t| {
                writer.print("{d}", .{t}) catch return;
            } else {
                writer.writeAll("?") catch return;
            }
            
            writer.writeAll(" @ tick ") catch return;
            if (tick) |t| {
                writer.print("{d}", .{t}) catch return;
            } else {
                writer.writeAll("?") catch return;
            }
            
            const location = stream.getWritten();
            
            // Build the full message and log it in one call to avoid deadlock
            self.mutex.lock();
            defer self.mutex.unlock();
            
            // Build the log message with location prefix
            if (self.config.show_timestamp) {
                const timestamp = std.time.milliTimestamp();
                self.config.writer.print("[{d}] ", .{timestamp}) catch return;
            }
            
            // Log level
            const level_str = switch (level) {
                .trace => "TRACE",
                .debug => "DEBUG",
                .info => "INFO ",
                .warn => "WARN ",
                .err => "ERROR",
            };
            self.config.writer.print("[{s}] [{s}] ", .{ level_str, location }) catch return;
            
            // Actual message
            self.config.writer.print(format, args) catch return;
            self.config.writer.writeAll("\n") catch return;
        } else {
            self.log(level, format, args);
        }
    }
};

// Global logger instance
var global_logger: ?Logger = null;
var global_mutex = std.Thread.Mutex{};

// Initialize the global logger
pub fn initGlobalLogger(config: LogConfig) void {
    global_mutex.lock();
    defer global_mutex.unlock();
    
    global_logger = Logger.init(config);
}

// Get the global logger
pub fn getLogger() *Logger {
    global_mutex.lock();
    defer global_mutex.unlock();
    
    if (global_logger == null) {
        global_logger = Logger.init(.{});
    }
    
    return &global_logger.?;
}

// Tests for logging functionality
test "LogLevel parsing" {
    try std.testing.expectEqual(LogLevel.trace, LogLevel.fromString("trace").?);
    try std.testing.expectEqual(LogLevel.debug, LogLevel.fromString("debug").?);
    try std.testing.expectEqual(LogLevel.info, LogLevel.fromString("info").?);
    try std.testing.expectEqual(LogLevel.warn, LogLevel.fromString("warn").?);
    try std.testing.expectEqual(LogLevel.err, LogLevel.fromString("err").?);
    try std.testing.expectEqual(@as(?LogLevel, null), LogLevel.fromString("invalid"));
}

test "Logger level filtering" {
    var logger = Logger.init(.{ .level = .warn });
    
    try std.testing.expect(!logger.isEnabled(.trace));
    try std.testing.expect(!logger.isEnabled(.debug));
    try std.testing.expect(!logger.isEnabled(.info));
    try std.testing.expect(logger.isEnabled(.warn));
    try std.testing.expect(logger.isEnabled(.err));
}

test "Logger basic functionality" {
    // Create a test buffer to capture output
    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    
    var logger = Logger.init(.{
        .level = .debug,
        .show_timestamp = false,
        .show_location = true,
        .writer = stream.writer().any(),
    });
    
    // Test different log levels
    logger.trace("This should not appear", .{});
    logger.debug("Debug message: {d}", .{42});
    logger.info("Info message", .{});
    logger.warn("Warning: {s}", .{"test warning"});
    logger.err("Error occurred", .{});
    
    const output = stream.getWritten();
    
    // Verify output contains expected messages
    try std.testing.expect(std.mem.indexOf(u8, output, "This should not appear") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[DEBUG] Debug message: 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[INFO ] Info message") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[WARN ] Warning: test warning") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[ERROR] Error occurred") != null);
}

test "Logger event logging" {
    var buffer: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    
    var logger = Logger.init(.{
        .level = .debug,
        .show_timestamp = false,
        .show_location = true,
        .writer = stream.writer().any(),
    });
    
    logger.logEvent(.debug, 2, 96, "Note On C4", .{});
    
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "[Track 2 @ tick 96] Note On C4") != null);
}
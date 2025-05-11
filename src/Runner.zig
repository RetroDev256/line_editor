// FUTURE UNDO STRATEGY:
// mark the "start" and "stop" of a command,
// store the atoms of what has occured in a large buffer similar to the string interning in LineBuffer.zig

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const File = std.fs.File;
const LineBuffer = @import("LineBuffer.zig");
const Range = @import("Range.zig");
const misc = @import("misc.zig");

// TODO: change the type of cmd_in and cmd_out when writergate gets here :)

cmd_in: File,
cmd_out: ?File,
file_out: ?[]const u8,
line: usize,
buffer: LineBuffer,

pub fn init(
    gpa: Allocator,
    cmd_in: File,
    cmd_out: ?File,
    file_in: ?[]const u8,
    file_out: ?[]const u8,
) !@This() {
    const buffer: LineBuffer = blk: {
        if (file_in) |path| {
            const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
            defer file.close();
            break :blk try .initReader(gpa, file.reader());
        } else {
            break :blk .empty;
        }
    };

    return .{
        .cmd_in = cmd_in,
        .cmd_out = cmd_out,
        .line = 0,
        .file_out = file_out orelse file_in,
        .buffer = buffer,
    };
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    self.buffer.deinit(gpa);
    self.* = undefined;
}

fn writeAll(self: @This(), bytes: []const u8) !void {
    if (self.cmd_out) |output| {
        try output.writeAll(bytes);
    }
}

fn printLineNumber(self: @This(), line: usize) !void {
    const max_line = std.math.maxInt(usize);
    const buf_len = 1 + std.math.log10(max_line);
    var buf: [buf_len]u8 = undefined;

    const line_count = self.buffer.lines.items.len;
    const width = misc.usizeFmt(line_count + 1, &buf).len;

    if (line == self.line) {
        try self.writeAll("^");
    } else {
        try self.writeAll(" ");
    }

    if (line_count > 0 and line == line_count - 1) {
        const padding = width - 1;
        for (0..padding) |_| try self.writeAll(" ");
        try self.writeAll("$ ");
    } else {
        const line_str = misc.usizeFmt(line + 1, &buf);
        const padding = width - line_str.len;
        for (0..padding) |_| try self.writeAll(" ");
        try self.writeAll(line_str);
        try self.writeAll(" ");
    }
}

const Input = struct {
    hit_eof: bool,
    text: []const u8,
};

// helper function to get user input
fn readInput(self: @This(), gpa: Allocator) !Input {
    var cmd: ArrayListUnmanaged(u8) = .empty;
    defer cmd.deinit(gpa);
    const cmd_w = cmd.writer(gpa);
    const reader = self.cmd_in.reader();
    // Read one line into memory; Determine if we have hit EOF
    const hit_eof = eof: {
        if (reader.streamUntilDelimiter(cmd_w, '\n', null)) {
            break :eof false;
        } else |err| switch (err) {
            error.EndOfStream => break :eof true,
            // We have hit a different error, bubble it up
            else => return err,
        }
    };
    const text = try cmd.toOwnedSlice(gpa);
    return .{ .hit_eof = hit_eof, .text = text };
}

// command mode dispatch
pub fn run(self: *@This(), gpa: Allocator) !void {
    loop: while (true) {
        // display command prompt, get input
        try self.writeAll("+ ");
        const user_input = try self.readInput(gpa);
        const cmd = user_input.text;
        defer gpa.free(cmd);

        // split up the command string into parts
        const range_end = Range.prefixLength(cmd);
        const range_str = cmd[0..range_end];
        const cmd_str = cmd[range_end..];

        switch (cmd_str.len) {
            0 => try self.lineCommand(range_str),
            1 => switch (cmd_str[0]) {
                // TODO: once we have undo/redo again,
                // implement dirty state checking here.
                'q' => break :loop,
                'p' => try self.printCommand(range_str),
                'w' => try self.writeCommand(range_str, &.{}),
                '.' => try self.insertCommand(gpa, range_str, &.{}),
                'd' => try self.deleteCommand(range_str),
                else => return error.Malformed,
            },
            else => switch (cmd_str[0]) {
                'w' => try self.writeCommand(range_str, cmd_str[1..]),
                '.' => try self.insertCommand(gpa, range_str, cmd_str[1..]),
                else => return error.Malformed,
            },
        }

        // we have reached EOF of the command input, exit
        if (user_input.hit_eof) break :loop;
    }
}

// sets the current line
fn lineCommand(self: *@This(), range_str: []const u8) !void {
    const range, _ = try Range.parse(range_str, .{
        .line = self.line,
        .length = self.buffer.lines.items.len,
        .default = .initSingle(self.line),
    });
    if (range.len() != 1) return error.InvalidLineCommand;
    self.line = range.start;
}

// Print numbered lines
fn printCommand(self: *@This(), range_str: []const u8) !void {
    // Parse the range
    const range, _ = try Range.parse(range_str, .{
        .line = self.line,
        .length = self.buffer.lines.items.len,
        .default = .initSingle(self.line),
    });
    // Print the range
    for (range.start..range.end) |idx| {
        // TODO: bounds checking
        if (self.buffer.get(idx)) |line| {
            try self.printLineNumber(idx);
            try self.writeAll(line);
            try self.writeAll("\n");
        } else {
            break;
        }
    }
    // Update the current line
    self.line = @min(range.end, self.buffer.lines.items.len);
}

// Writes the range to the specified (or last specified) file name.
// If the last line is last line in the buffer, no newline is appended.
fn writeCommand(
    self: *@This(),
    range_str: []const u8,
    data_str: []const u8,
) !void {
    // Parse the range
    const buffer_length = self.buffer.lines.items.len;
    const range, _ = try Range.parse(range_str, .{
        .line = self.line,
        .length = buffer_length,
        .default = .init(0, buffer_length),
    });

    const file_name = switch (data_str.len) {
        0 => self.file_out orelse return error.FileNameNotSet,
        else => data_str,
    };
    // TODO: create a separate file then atomic rename in place to
    // avoid situations where you save the file but it fails halfway through
    // losing all of your data - kinda like what vscode does
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    try self.buffer.save(file.writer(), range);
}

// Without command data, we are in a loop for inserting data.
// If the "A,B" or "A;B" syntax is used, the loop is broken after the range.
// With command data, we insert the line through the entire range.
// Sets the current line to after the current range
fn insertCommand(
    self: *@This(),
    gpa: Allocator,
    range_str: []const u8,
    data_str: []const u8,
) !void {
    // Parse the range
    const range, const range_type = try Range.parse(range_str, .{
        .line = self.line,
        .length = self.buffer.lines.items.len,
        .default = .initSingle(self.line),
    });

    // TODO: check and handle out of bounds?

    if (data_str.len == 0) {
        var line: usize = range.start;
        insert: while (true) : (line += 1) {
            // for "A,B" and "A;B" type loops, break on completion of the range
            if (range_type == .end_bound or range_type == .length_bound) {
                if (line == range.end) break :insert;
            }
            // get user input
            try self.printLineNumber(line);
            const input = try self.readInput(gpa);
            defer gpa.free(input.text);
            // Loop escaped by inputting a single period
            if (misc.eql(".", input.text)) break :insert;
            // insert the line
            try self.buffer.insert(gpa, line, input.text);
            // Loop escaped if EOF is reached
            if (input.hit_eof) break :insert;
        }
        self.line = line;
    } else {
        // one-shot mode duplicates the string line over the entire range
        self.line = range.end;
        for (range.start..range.end) |_| {
            try self.buffer.insert(gpa, range.start, data_str);
        }
    }
}

// Deletes lines specified in the range.
// Sets current line to first index deleted
fn deleteCommand(self: *@This(), range_str: []const u8) !void {
    // Parse the range
    const range, _ = try Range.parse(range_str, .{
        .line = self.line,
        .length = self.buffer.lines.items.len,
        .default = .initSingle(self.line),
    });

    self.line = range.start;
    self.buffer.removeRange(range);
}

// TODO: testing

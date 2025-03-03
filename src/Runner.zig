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

const Editor = struct {
    line: usize,
    file_out: ?[]const u8,
    buffer: LineBuffer,

    pub fn init(gpa: Allocator, file_in: ?[]const u8, file_out: ?[]const u8) !Editor {
        return .{
            .line = 0,
            .file_out = file_out orelse file_in,
            .buffer = if (file_in) |name| try .init(gpa, name) else .empty,
        };
    }

    pub fn deinit(self: *Editor, gpa: Allocator) void {
        self.buffer.deinit(gpa);
        self.* = undefined;
    }
};

// TODO: change the type of cmd_in and cmd_out when writergate gets here :)
cmd_in: File,
cmd_out: ?File,
state: Editor,

pub fn init(
    gpa: Allocator,
    cmd_in: File,
    cmd_out: ?File,
    file_in: ?[]const u8,
    file_out: ?[]const u8,
) !@This() {
    return .{
        .cmd_in = cmd_in,
        .cmd_out = cmd_out,
        .state = try .init(gpa, file_in, file_out),
    };
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    self.state.deinit(gpa);
    self.* = undefined;
}

// helper function to print if we can
fn print(self: @This(), comptime format: []const u8, args: anytype) !void {
    if (self.cmd_out) |output| {
        try output.writer().print(format, args);
    }
}

// helper function to print a line number
// TODO: pad the number so that it will match up with the
// linebuffer length, instead of being fixed to 6 digits
fn printLineNumber(self: @This(), line: usize) !void {
    try self.print("{: >6} ", .{line + 1});
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
        try self.print("+ ", .{});
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
        .line = self.state.line,
        .length = self.state.buffer.lines.items.len,
        .default = .initSingle(self.state.line),
    });
    if (range.len() != 1) return error.InvalidLineCommand;
    self.state.line = range.start;
}

// Print numbered lines - sets the current line to after the range
fn printCommand(self: *@This(), range_str: []const u8) !void {
    // Parse the range
    const range, _ = try Range.parse(range_str, .{
        .line = self.state.line,
        .length = self.state.buffer.lines.items.len,
        .default = .initSingle(self.state.line),
    });
    // Print the range
    for (range.start..range.end) |idx| {
        // TODO: bounds checking
        if (self.state.buffer.get(idx)) |line| {
            try self.printLineNumber(idx);
            try self.print("{s}\n", .{line});
        } else {
            break;
        }
    }
    // Update the current state
    self.state.line = range.end;
}

// Writes the range to the specified (or last specified) file name.
// If the last line is last line in the buffer, no newline is appended.
fn writeCommand(
    self: *@This(),
    range_str: []const u8,
    data_str: []const u8,
) !void {
    // Parse the range
    const buffer_length = self.state.buffer.lines.items.len;
    const range, _ = try Range.parse(range_str, .{
        .line = self.state.line,
        .length = buffer_length,
        .default = .init(0, buffer_length),
    });

    const file_name = switch (data_str.len) {
        0 => self.state.file_out orelse return error.FileNameNotSet,
        else => data_str,
    };
    try self.state.buffer.save(file_name, range);
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
        .line = self.state.line,
        .length = self.state.buffer.lines.items.len,
        .default = .initSingle(self.state.line),
    });

    // TODO: check and handle out of bounds?

    if (data_str.len == 0) {
        self.state.line = range.start;
        insert: while (true) : (self.state.line += 1) {
            // for "A,B" and "A;B" type loops, break on completion of the range
            if (range_type == .end_bound or range_type == .length_bound) {
                if (self.state.line == range.end) break :insert;
            }
            // get user input
            try self.printLineNumber(self.state.line);
            const input = try self.readInput(gpa);
            defer gpa.free(input.text);
            // Loop escaped by inputting a single period
            if (misc.eql(".", input.text)) break :insert;
            // insert the line
            try self.state.buffer.insert(gpa, self.state.line, input.text);
            // Loop escaped if EOF is reached
            if (input.hit_eof) break :insert;
        }
    } else {
        // one-shot mode duplicates the string line over the entire range
        self.state.line = range.end;
        for (range.start..range.end) |line| {
            try self.state.buffer.insert(gpa, line, data_str);
        }
    }
}

// Deletes lines specified in the range.
// Sets current line to first index deleted
fn deleteCommand(self: *@This(), range_str: []const u8) !void {
    // Parse the range
    const range, _ = try Range.parse(range_str, .{
        .line = self.state.line,
        .length = self.state.buffer.lines.items.len,
        .default = .initSingle(self.state.line),
    });

    self.state.line = range.start;
    self.state.buffer.removeRange(range);
}

// TODO: testing

const Self = @This();

const std = @import("std");
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const Parser = @import("Parser.zig");
const Command = Parser.Command;
const LineBuffer = @import("LineBuffer.zig");
const Index = @import("index.zig").Index;
const BoundedRange = @import("BoundedRange.zig");
const Range = @import("Range.zig");

alloc: Allocator,
cmd_in: File,
cmd_out: ?File,
file_out: ?[]const u8,
buffer: LineBuffer,
mode: enum { command, insert } = .command,
line: Index = .{ .specific = 0 },
should_exit: bool = false,

pub fn init(
    alloc: Allocator,
    cmd_in: File,
    cmd_out: ?File,
    file_in: ?[]const u8,
    file_out: ?[]const u8,
) !Self {
    var self: Self = .{
        .alloc = alloc,
        .cmd_in = cmd_in,
        .cmd_out = cmd_out,
        .file_out = file_out orelse file_in,
        .buffer = LineBuffer.init(alloc),
    };
    if (file_in) |file_name| {
        try self.buffer.appendFile(file_name);
    }
    return self;
}

pub fn deinit(self: *Self) void {
    self.buffer.deinit();
}

pub fn run(self: *Self) !void {
    const reader = self.cmd_in.reader();
    const cmd_max = std.math.maxInt(usize);
    while (!self.should_exit) {
        switch (self.mode) {
            .command => try self.printCommandPrompt(),
            .insert => try self.printLineNumber(self.line),
        }
        const source_maybe = try reader.readUntilDelimiterOrEofAlloc(self.alloc, '\n', cmd_max);
        if (source_maybe) |source| {
            defer self.alloc.free(source);
            const trimmed_source = std.mem.trim(u8, source, "\n\r");
            switch (self.mode) {
                .command => self.runCommand(trimmed_source) catch |err| try self.handle(err),
                // gosh, insert mode is so much easier to parse
                .insert => if (std.mem.eql(u8, ".", trimmed_source)) {
                    self.mode = .command;
                } else {
                    self.buffer.insertLine(self.line, trimmed_source) catch |err| {
                        try self.handle(err);
                    };
                    self.line = self.line.add(1);
                },
            }
        } else {
            self.should_exit = true;
        }
    }
}

fn handle(self: *const Self, err: anyerror) !void {
    const err_string = switch (err) {
        error.ReversedRange => "range must be ascending",
        error.IndexZero => "no zero indexes allowed",
        error.IndexOutOfBounds => "index out of bounds",
        error.MalformedCommand => "malformed command",
        error.EmptyBuffer => "the buffer is empty",
        error.NoOutputSpecified => "no output filename specified",
        error.InvalidNumber => "unable to parse number",
        else => return err,
    };
    try self.printToCmdOut("Error: {s}\n", .{err_string});
}

fn printToCmdOut(self: *const Self, comptime format: []const u8, args: anytype) !void {
    if (self.cmd_out) |output| {
        try output.writer().print(format, args);
    }
}

fn printLineNumber(self: *const Self, line: Index) !void {
    switch (line) {
        .specific => |index| try self.printToCmdOut("{: >8} ", .{index + 1}),
        .infinity => try self.printToCmdOut(" " ** 7 ++ "$ ", .{}),
    }
}

fn printCommandPrompt(self: *const Self) !void {
    if (self.cmd_out) |output| {
        try output.writeAll("+ ");
    }
}

fn runCommand(self: *Self, source: []const u8) !void {
    const parsed_command = try Parser.parse(self.alloc, source);
    if (parsed_command) |command| switch (command) {
        .quit => self.runQuit(),
        .help => try self.runHelp(),
        .delete => try self.runDelete(),
        .delete_line => |data| try self.runDeleteLine(data),
        .delete_range => |data| try self.runDeleteRange(data),
        .print => try self.runPrint(),
        .print_line => |data| try self.runPrintLine(data),
        .print_range => |data| try self.runPrintRange(data),
        .write_default => try self.runWriteDefault(),
        .write_default_line => |data| try self.runWriteDefaultLine(data),
        .write_default_range => |data| try self.runWriteDefaultRange(data),
        .write_quit_default => {
            try self.runWriteDefault();
            self.should_exit = true;
        },
        .write_quit_default_line => |data| {
            try self.runWriteDefaultLine(data);
            self.should_exit = true;
        },
        .write_quit_default_range => |data| {
            try self.runWriteDefaultRange(data);
            self.should_exit = true;
        },
        .write => |data| {
            self.file_out = data;
            try self.runWriteDefault();
        },
        .write_line => |data| {
            self.file_out = data.file_out;
            try self.runWriteDefaultLine(data.source);
        },
        .write_range => |data| {
            self.file_out = data.file_out;
            try self.runWriteDefaultRange(data.source);
        },
        .write_quit => |data| {
            self.file_out = data;
            try self.runWriteDefault();
            self.should_exit = true;
        },
        .write_quit_line => |data| {
            self.file_out = data.file_out;
            try self.runWriteDefaultLine(data.source);
            self.should_exit = true;
        },
        .write_quit_range => |data| {
            self.file_out = data.file_out;
            try self.runWriteDefaultRange(data.source);
            self.should_exit = true;
        },
        .insert_mode => {
            self.mode = .insert;
        },
        .insert_mode_line => |data| {
            self.line = data;
            self.mode = .insert;
        },
        .insert_text => |data| {
            try self.buffer.insertLine(self.line, data);
        },
        .insert_text_line => |data| {
            try self.buffer.insertLine(data.dest, data.text);
        },
        .sub => |data| try self.runSub(data),
        .sub_line => |data| try self.runSubLine(data),
        .sub_range => |data| try self.runSubRange(data),
        .move => |data| try self.runMove(data),
        .move_line => |data| try self.runMoveLine(data),
        .move_range => |data| try self.runMoveRange(data),
        .line => |data| try self.runLine(data),
    };
    // as we can append after the buffer, clamp it with 1 element slack
    self.line = try self.line.clamp(self.buffer.length() + 1);
}

fn runQuit(self: *Self) void {
    self.should_exit = true;
}

fn runHelp(self: *Self) !void {
    try self.printToCmdOut(
        \\- - - Definitions - - -
        \\  MODE                  COMMAND or INSERT (swap using .)
        \\  LINE                  the current line number
        \\  FILE                  the current output file name
        \\  INDEX                 can be line number, or $ (last line)
        \\  RANGE:                (can be either of the following formats -)
        \\  [X]                   line number X (INDEX)
        \\  [A?],[B?]             lines [INDEX A (oror 0), INDEX B (oror $)]
        \\- - - INSERT Mode - - -
        \\  .                     MODE<-COMMAND
        \\  .[STRING]             inserts STRING at LINE, LINE<-LINE + 1
        \\- - - COMMAND Mode - - -
        \\  [INDEX?]              LINE<-INDEX (or LINE)
        \\  [INDEX?].             LINE<-INDEX (or LINE), MODE<-INSERT
        \\  [INDEX?].[NEW]        LINE<-INDEX (or LINE), inserts NEW at LINE
        \\  [RANGE?]p             prints RANGE (or LINE)
        \\  [RANGE?]d             deletes RANGE (or LINE)
        \\  [RANGE?]s/[OLD]/[NEW] replaces all OLD to NEW in RANGE (or LINE)
        \\  [RANGE?]m[INDEX]      moves RANGE (or LINE) to INDEX
        \\  [RANGE?]w[NAME?]      FILE<-NAME (or FILE), saves RANGE (or all) to FILE
        \\  [RANGE?]wq[NAME?]     same as w varient, but also quits the program
        \\  q                     exits
        \\  h                     displays this text
        \\
    , .{});
}

fn runDelete(self: *Self) !void {
    try self.buffer.deleteLine(self.line);
}

fn runDeleteLine(self: *Self, line: Index) !void {
    try self.buffer.deleteLine(line);
}

fn runDeleteRange(self: *Self, range: Range) !void {
    try self.buffer.deleteRange(range);
}

fn runPrint(self: *Self) !void {
    // print up to 16 lines by default
    const range = Range.fromIndex(self.line, 16);
    const clamped_range = try range.clamp(self.buffer.length());
    const lines = try self.buffer.getRange(clamped_range);
    const resolved = try clamped_range.toBounded(try self.buffer.lastIndex());
    for (lines, 0..) |line, offset| {
        const line_number = .{ .specific = resolved.start + offset };
        try self.printLineNumber(line_number);
        try self.printToCmdOut("{s}\n", .{line});
    }
}

fn runPrintLine(self: *Self, source: Index) !void {
    const line = try self.buffer.getLine(source);
    try self.printLineNumber(self.line);
    try self.printToCmdOut("{s}\n", .{line});
}

fn runPrintRange(self: *Self, source: Range) !void {
    const lines = try self.buffer.getRange(source);
    const resolved = try source.toBounded(try self.buffer.lastIndex());
    for (lines, 0..) |line, offset| {
        const line_number = .{ .specific = resolved.start + offset };
        try self.printLineNumber(line_number);
        try self.printToCmdOut("{s}\n", .{line});
    }
}

fn runWriteDefault(self: *Self) !void {
    if (self.file_out) |file_name| {
        try self.buffer.save(file_name);
    } else return error.NoOutputSpecified;
}

fn runWriteDefaultLine(self: *Self, source: Index) !void {
    if (self.file_out) |file_name| {
        try self.buffer.saveLine(file_name, source);
    } else return error.NoOutputSpecified;
}

fn runWriteDefaultRange(self: *Self, source: Range) !void {
    if (self.file_out) |file_name| {
        try self.buffer.saveRange(file_name, source);
    } else return error.NoOutputSpecified;
}

fn replace(self: *Self, line: []const u8, before: []const u8, after: []const u8) !?[]const u8 {
    var new_line = std.ArrayListUnmanaged(u8){};
    defer new_line.deinit(self.alloc);

    var dirty: bool = false;
    var idx: usize = 0;
    while (idx < line.len) {
        if (std.mem.startsWith(u8, line[idx..], before)) {
            dirty = true;
            try new_line.appendSlice(self.alloc, after);
            idx += before.len;
        } else {
            try new_line.append(self.alloc, line[idx]);
            idx += 1;
        }
    }

    if (dirty) {
        return try new_line.toOwnedSlice(self.alloc);
    } else return null;
}

fn runSub(self: *Self, data: Parser.Sub) !void {
    const line = try self.buffer.getLine(self.line);
    if (try self.replace(line, data.before, data.after)) |modified_line| {
        defer self.alloc.free(modified_line);
        try self.buffer.deleteLine(self.line);
        try self.buffer.insertLine(self.line, modified_line);
    }
}

fn runSubLine(self: *Self, data: Parser.SubLine) !void {
    const line = try self.buffer.getLine(data.dest);
    if (try self.replace(line, data.before, data.after)) |modified_line| {
        defer self.alloc.free(modified_line);
        try self.buffer.deleteLine(data.dest);
        try self.buffer.insertLine(data.dest, modified_line);
    }
}

fn runSubRange(self: *Self, data: Parser.SubRange) !void {
    const lines = try self.buffer.getRange(data.dest);
    const resolved = try data.dest.toBounded(try self.buffer.lastIndex());
    for (lines, 0..) |line, offset| {
        const line_number = .{ .specific = resolved.start + offset };
        if (try self.replace(line, data.before, data.after)) |modified_line| {
            defer self.alloc.free(modified_line);
            try self.buffer.deleteLine(line_number);
            try self.buffer.insertLine(line_number, modified_line);
        }
    }
}

fn runMove(self: *Self, dest: Index) !void {
    try self.buffer.moveLine(self.line, dest);
}

fn runMoveLine(self: *Self, data: Parser.MoveLine) !void {
    try self.buffer.moveLine(data.source, data.dest);
}

fn runMoveRange(self: *Self, data: Parser.MoveRange) !void {
    try self.buffer.moveRange(data.source, data.dest);
}

fn runLine(self: *Self, line: Index) !void {
    self.line = line;
}

test {
    _ = &std.testing.refAllDecls(@This());
}

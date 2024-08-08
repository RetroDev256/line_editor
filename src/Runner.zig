// todo:

// add "copy" command:
// [RANGE?/INDEX?]c[INDEX]
// copies the lines in RANGE to INDEX

// improve "substitute" command: (probably minimal regex)
// so we can prefix and postfix lines (begin and end)
// so we can match some (or many) characters
// nothing too complicated

// combine things, reduce function count

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
const commands = @import("commands.zig");

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

pub fn printToCmdOut(self: *const Self, comptime format: []const u8, args: anytype) !void {
    if (self.cmd_out) |output| {
        try output.writer().print(format, args);
    }
}

pub fn printLineNumber(self: *const Self, line: Index) !void {
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

fn runCommand(self: *Self, source: []const u8) !void {
    const parsed_command = try Parser.parse(self.alloc, source);
    if (parsed_command) |command| switch (command) {
        .quit => self.should_exit = true,
        .line => |line| self.line = line,
        .help => try commands.help.run(self),
        .delete => try commands.delete.run(self),
        .delete_line => |data| try commands.delete.runLine(self, data),
        .delete_range => |data| try commands.delete.runRange(self, data),
        .print => try commands.print.run(self),
        .print_line => |data| try commands.print.runLine(self, data),
        .print_range => |data| try commands.print.runRange(self, data),
        .write => |data| try commands.write.run(self, data),
        .write_line => |data| try commands.write.runLine(self, data),
        .write_range => |data| try commands.write.runRange(self, data),
        .write_default => try commands.write.runDefault(self),
        .write_default_line => |data| try commands.write.runDefaultLine(self, data),
        .write_default_range => |data| try commands.write.runDefaultRange(self, data),
        .write_quit => |data| try commands.write_quit.run(self, data),
        .write_quit_line => |data| try commands.write_quit.runLine(self, data),
        .write_quit_range => |data| try commands.write_quit.runRange(self, data),
        .write_quit_default => try commands.write_quit.runDefault(self),
        .write_quit_default_line => |data| try commands.write_quit.runDefaultLine(self, data),
        .write_quit_default_range => |data| try commands.write_quit.runDefaultRange(self, data),
        .insert_mode => try commands.insert.runMode(self),
        .insert_mode_line => |data| try commands.insert.runModeLine(self, data),
        .insert_text => |data| try commands.insert.runText(self, data),
        .insert_text_line => |data| try commands.insert.runTextLine(self, data),
        .sub => |data| try commands.substitute.run(self, data),
        .sub_line => |data| try commands.substitute.runLine(self, data),
        .sub_range => |data| try commands.substitute.runRange(self, data),
        .move => |data| try commands.move.run(self, data),
        .move_line => |data| try commands.move.runLine(self, data),
        .move_range => |data| try commands.move.runRange(self, data),
    };
    // as we can append after the buffer, clamp it with 1 element slack
    self.line = try self.line.clamp(self.buffer.length() + 1);
}

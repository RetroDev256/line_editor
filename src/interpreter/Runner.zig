// add "copy" command:
// [RANGE?/INDEX?]c[INDEX]
// copies the lines in RANGE to INDEX

const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const File = std.fs.File;
const LineBuffer = @import("LineBuffer.zig");
const Index = @import("selection.zig").Index;
const Parser = @import("Parser.zig");
const commands = @import("commands.zig");
const io = @import("io.zig");

pub const Mode = enum { command, insert };

alloc: Allocator,
cmd_in: AnyReader,
cmd_out: ?AnyWriter,
file_out: ?[]const u8,
buffer: LineBuffer,
mode: Mode = .command,
line: Index = .{ .specific = 0 },
should_exit: bool = false,

pub fn init(
    alloc: Allocator,
    cmd_in: AnyReader,
    cmd_out: ?AnyWriter,
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
    const cmd_max = std.math.maxInt(usize);
    while (!self.should_exit) {
        switch (self.mode) {
            .command => try io.printCommandPrompt(self.cmd_out),
            .insert => try io.printLineNumber(self.cmd_out, self.line),
        }
        const source_maybe = try self.cmd_in.readUntilDelimiterOrEofAlloc(self.alloc, '\n', cmd_max);
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
        error.Malformed => "malformed command",
        error.IndexZero => "no zero indexes allowed",
        error.NoOutputSpecified => "no output filename specified",
        error.IndexOutOfBounds => "index out of bounds",
        error.EmptyBuffer => "the buffer is empty",
        error.InvalidNumber => "unable to parse number",
        error.MoveOutOfBounds => "move creates gap in file",
        error.ReversedRange => "range must be ascending",
        else => return err,
    };
    try io.printToCmdOut(self.cmd_out, "Error: {s}\n", .{err_string});
}

fn runCommand(self: *Self, source: []const u8) !void {
    const parsed_command = try Parser.parse(self.alloc, source);
    if (parsed_command) |command| switch (command) {
        .quit => |quit| try quit.run(&self.should_exit),
        .help => |help| try help.run(self.cmd_out),
        .delete => |delete| try delete.run(&self.buffer, self.line),
        .print => |print| try print.run(self.buffer, self.line, self.cmd_out),
        .write => |write| try write.run(&self.buffer, &self.file_out, &self.should_exit),
        .insert => |insert| try insert.run(&self.buffer, &self.mode, &self.line),
        .substitute => |substitute| try substitute.run(self.alloc, &self.buffer, self.line),
        .move => |move| try move.run(self.line, &self.buffer),
        .copy => |copy| try copy.run(self.line, &self.buffer),
        .line => |line| try line.run(&self.line),
    };
    // as we can append after the buffer, clamp it with 1 element slack
    self.line = try self.line.clamp(self.buffer.length() + 1);
}

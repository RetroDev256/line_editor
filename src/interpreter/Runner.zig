const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const LineBuffer = @import("LineBuffer.zig");
const Parser = @import("Parser.zig");
const commands = @import("commands.zig");
const io = @import("io.zig");

pub const Mode = enum { command, insert };

alloc: Allocator,
file_out: ?[]const u8,
buffer: LineBuffer,
mode: Mode = .command,
line: usize = 0,
should_exit: bool = false,

pub fn init(
    alloc: Allocator,
    file_in: ?[]const u8,
    file_out: ?[]const u8,
) !Self {
    var self: Self = .{
        .alloc = alloc,
        .file_out = file_out orelse file_in,
        .buffer = LineBuffer.init(alloc),
    };
    if (file_in) |file_name| {
        try self.buffer.load(file_name);
    }
    return self;
}

pub fn deinit(self: *Self) void {
    self.buffer.deinit();
}

pub fn run(self: *Self, reader: anytype, writer: anytype) !void {
    const cmd_max = std.math.maxInt(usize);
    while (!self.should_exit) {
        switch (self.mode) {
            .command => try io.printCommandPrompt(writer),
            .insert => try io.printLineNumber(writer, self.line, self.buffer.length()),
        }
        const source_maybe = try reader.readUntilDelimiterOrEofAlloc(self.alloc, '\n', cmd_max);
        if (source_maybe) |source| {
            defer self.alloc.free(source);
            const trimmed_source = std.mem.trim(u8, source, "\n\r");
            switch (self.mode) {
                .command => self.runCommand(writer, trimmed_source) catch |err| {
                    try handle(writer, err);
                },
                // gosh, insert mode is so much easier to parse
                .insert => if (std.mem.eql(u8, ".", trimmed_source)) {
                    self.mode = .command;
                } else {
                    self.buffer.insert(self.line, &.{trimmed_source}) catch |err| {
                        try handle(writer, err);
                    };
                    self.line += 1;
                },
            }
        } else {
            self.should_exit = true;
        }
    }
}

fn handle(writer: anytype, err: anyerror) !void {
    const err_string = switch (err) {
        error.Malformed => "malformed command",
        error.IndexZero => "no zero indexes allowed",
        error.NoOutputSpecified => "no output filename specified",
        else => return err,
    };
    try io.printToCmdOut(writer, "Error: {s}\n", .{err_string});
}

fn runCommand(self: *Self, writer: anytype, source: []const u8) !void {
    const saturated_length = self.buffer.length() -| 1;
    const parsed_command = try Parser.parse(self.alloc, source, saturated_length);
    if (parsed_command) |command| switch (command) {
        .quit => |quit| try quit.run(&self.should_exit),
        .help => |help| try help.run(writer),
        .delete => |delete| try delete.run(&self.buffer, self.line),
        .print => |print| try print.run(self.buffer, self.line, writer),
        .write => |write| try write.run(&self.buffer, &self.file_out, &self.should_exit),
        .insert => |insert| try insert.run(&self.buffer, &self.mode, &self.line),
        .substitute => |substitute| try substitute.run(self.alloc, &self.buffer, self.line),
        .move => |move| try move.run(self.line, &self.buffer),
        .copy => |copy| try copy.run(self.line, &self.buffer),
        .line => |line| try line.run(&self.line),
    };
}

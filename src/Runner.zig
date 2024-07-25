const std = @import("std");
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const mvzr = @import("mvzr");
const parser = @import("parser.zig");
const LineBuffer = @import("LineBuffer.zig");

alloc: Allocator,
cmd_in: File,
cmd_out: ?File,
file_out: ?[]const u8,

mode: enum { command, edit } = .command,
line: usize = 0,
buffer: LineBuffer = .{},

const Runner = @This();

pub fn runOnce(alloc: Allocator, cmd_in: File, cmd_out: ?File, file_in: ?[]const u8, file_out: ?[]const u8) !void {
    var self: Runner = try init(alloc, cmd_in, cmd_out, file_in, file_out);
    defer self.deinit();
    try self.run();
}

pub fn init(alloc: Allocator, cmd_in: File, cmd_out: ?File, file_in: ?[]const u8, file_out: ?[]const u8) !Runner {
    var self: Runner = .{ .alloc = alloc, .cmd_in = cmd_in, .cmd_out = cmd_out, .file_out = file_out };
    if (file_in) |file_name| {
        try self.buffer.appendFile(self.alloc, file_name);
    }
    return self;
}

pub fn deinit(self: *Runner) void {
    self.buffer.deinit(self.alloc);
}

pub fn run(self: *Runner) !void {
    const reader = self.cmd_in.reader();
    const cmd_max = std.math.maxInt(usize);
    while (true) {
        switch (self.mode) {
            .command => try self.printCommandPrompt(),
            .edit => try self.printLineNumber(self.line),
        }
        const source_maybe = try reader.readUntilDelimiterOrEofAlloc(self.alloc, '\n', cmd_max);
        const source = if (source_maybe) |source| source else break;
        defer self.alloc.free(source);

        switch (self.mode) {
            .command => {
                const cmd = parser.parse(source);
                const maybe_err: anyerror!void = switch (cmd) {
                    .none => {},
                    .delete => |delete| self.runDelete(delete),
                    .insert => |insert| self.runInsert(insert),
                    .line => |line| self.runLine(line),
                    .print => |print| self.runPrint(print),
                    .substitution => |substitution| self.runSubstitution(substitution),
                    .write => |write| self.runWrite(write),
                    .write_quit => |write_quit| {
                        self.runWrite(write_quit) catch |err| try self.handleError(err);
                        return;
                    },
                    .quit => return,
                };
                if (maybe_err) |_| {} else |err| try self.handleError(err);
            },
            // gosh, edit mode is so much easier to parse
            .edit => if (std.mem.eql(u8, ".", source)) {
                self.mode = .command;
            } else {
                try self.buffer.insertLine(self.alloc, self.line, source);
                self.line += 1;
            },
        }
    }
}

fn printToCmdOut(self: *const Runner, comptime format: []const u8, args: anytype) !void {
    if (self.cmd_out) |output| {
        try output.writer().print(format, args);
    }
}

fn printLineNumber(self: *const Runner, line: usize) !void {
    try self.printToCmdOut("    {: >8} ", .{line});
}

fn printCommandPrompt(self: *const Runner) !void {
    try self.printToCmdOut("+ ", .{});
}

fn handleError(self: *const Runner, err: anyerror) !void {
    const string = switch (err) {
        error.NoOutputSpecified => "no output filename specified",
        error.InvalidRange => "range has negative length",
        error.InvalidRegex => "failed to compile regex",
        error.IndexOutOfBounds => "index falls outside of file",
        else => return err,
    };
    try self.printToCmdOut("Error: {s}\n", .{string});
}

fn runInsert(self: *Runner, insert: parser.Insert) !void {
    const line = if (insert.line) |l| try self.positionToIndex(l) else self.line;
    if (insert.text) |line_text| {
        self.buffer.deleteLines(.{ line, line });
        try self.buffer.insertLine(self.alloc, line, line_text);
        self.line = line + 1;
    } else {
        self.mode = .edit;
        self.line = line;
    }
}

fn runLine(self: *Runner, line: parser.Number) !void {
    self.line = try self.positionToIndex(line);
}

fn runDelete(self: *Runner, delete: parser.Delete) !void {
    const bounds = try self.resolveRange(delete.range);
    self.line = bounds[0];
    self.buffer.deleteLines(bounds);
}

fn runPrint(self: *Runner, print: parser.Print) !void {
    const bounds = try self.resolveRange(print.range);
    const lines = self.buffer.getLines(bounds);
    self.line = bounds[0] + lines.len;
    for (lines, 0..) |line, offset| {
        const line_number = bounds[0] + offset;
        try self.printLineNumber(line_number);
        try self.printToCmdOut("{s}\n", .{line});
    }
}

fn runSubstitution(self: *Runner, substitution: parser.Substitution) !void {
    const regex = mvzr.compile(substitution.pattern) orelse return error.InvalidRegex;
    const bounds = try self.resolveRange(substitution.range);
    self.line = bounds[0];
    const lines = self.buffer.getLines(bounds);
    var replacements: usize = 0;
    for (0..lines.len) |line_offset| {
        const line_number = bounds[0] + line_offset;
        while (true) {
            if (substitution.count) |max_lines| {
                if (max_lines == .specific) {
                    if (replacements >= max_lines.specific) return;
                }
            }
            const line = self.buffer.lines.items[line_number];
            if (regex.match(line)) |match| {
                replacements += 1;
                const changed = try std.fmt.allocPrint(self.alloc, "{s}{s}{s}", .{
                    line[0..match.start], substitution.replacement, line[match.end..],
                });
                defer self.alloc.free(changed);
                self.buffer.deleteLines(.{ line_number, line_number + 1 });
                try self.buffer.insertLine(self.alloc, line_number, changed);
            } else break;
        }
    }
}

fn runWrite(self: *Runner, write: parser.Write) !void {
    if (write.file_out) |new_out| self.file_out = new_out;
    if (self.file_out) |file_name| {
        // specifically for saving files, we want to default to
        // saving the entire file, not just one line if we don't
        // specify a line.
        const default_range = write.range orelse parser.Range{
            .start = .{ .specific = 0 },
            .end = .infinity,
        };
        const range = try self.resolveRange(default_range);
        try self.buffer.save(file_name, range);
    } else return error.NoOutputSpecified;
}

fn positionToIndex(self: *const Runner, index: parser.Number) !usize {
    return switch (index) {
        .specific => |s_pos| {
            if (s_pos >= self.buffer.lines.items.len) {
                return error.IndexOutOfBounds;
            }
            return s_pos;
        },
        .infinity => self.buffer.lines.items.len - 1,
    };
}

fn resolveRange(self: *const Runner, range: ?parser.Range) !struct { usize, usize } {
    if (range) |r| {
        const start = try self.positionToIndex(r.start orelse .{
            .specific = 0,
        });
        const end = try self.positionToIndex(r.end orelse .{
            .specific = self.buffer.lines.items.len - 1,
        });
        if (end < start) return error.InvalidRange;
        return .{ start, end + 1 };
    }
    return .{ self.line, self.line + 1 };
}

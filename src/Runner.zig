const std = @import("std");
const File = std.fs.File;
const Allocator = std.mem.Allocator;

// bundling this with the program instead of using the package manager
// because it was using std.log.err, really annoying
const mvzr = @import("mvzr.zig");

const parser = @import("parser.zig");
const LineBuffer = @import("LineBuffer.zig");

const Number = @import("range.zig").Number;
const BoundedRange = @import("range.zig").BoundedRange;
const Range = @import("range.zig").Range;

alloc: Allocator,
cmd_in: File,
cmd_out: ?File,
file_out: ?[]const u8,

mode: enum { command, edit } = .command,
line: usize = 0,
buffer: LineBuffer,

const Runner = @This();

pub fn runOnce(alloc: Allocator, cmd_in: File, cmd_out: ?File, file_in: ?[]const u8, file_out: ?[]const u8) !void {
    var self: Runner = try init(alloc, cmd_in, cmd_out, file_in, file_out);
    defer self.deinit();
    try self.run();
}

pub fn init(alloc: Allocator, cmd_in: File, cmd_out: ?File, file_in: ?[]const u8, file_out: ?[]const u8) !Runner {
    var self: Runner = .{
        .alloc = alloc,
        .cmd_in = cmd_in,
        .cmd_out = cmd_out,
        .file_out = file_out,
        .buffer = LineBuffer.init(alloc),
    };
    if (file_in) |file_name| {
        try self.buffer.appendFile(file_name);
    }
    return self;
}

pub fn deinit(self: *Runner) void {
    self.buffer.deinit();
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

        const trimmed_source = std.mem.trim(u8, source, " \n\t\r");

        switch (self.mode) {
            .command => {
                const command = parser.parse(trimmed_source) catch |err| blk: {
                    try self.handleError(err);
                    break :blk .blank; // if there is an error in parsing, no command by default
                };
                const should_exit = self.switchCommands(command) catch |err| blk: {
                    try self.handleError(err);
                    break :blk false; // if there is an error in running, don't exit by default
                };
                if (should_exit) return;
            },
            // gosh, edit mode is so much easier to parse
            .edit => if (std.mem.eql(u8, ".", trimmed_source)) {
                self.mode = .command;
            } else {
                try self.buffer.insertLine(self.line, trimmed_source);
                self.line += 1;
            },
        }
    }
}

fn switchCommands(self: *Runner, command: parser.Command) !bool {
    var should_exit: bool = false;
    switch (command) {
        .blank => {},
        .none => return error.CommandNotRecognized,
        .delete => |delete| try self.runDelete(delete),
        .insert => |insert| try self.runInsert(insert),
        .line => |line| self.runLine(line),
        .print => |print| try self.runPrint(print),
        .substitution => |substitution| try self.runSubstitution(substitution),
        .write => |write| try self.runWrite(write),
        .write_quit => |write_quit| {
            try self.runWrite(write_quit);
            should_exit = true;
        },
        .quit => should_exit = true,
        .help => try self.runHelp(),
    }
    return should_exit;
}

fn printToCmdOut(self: *const Runner, comptime format: []const u8, args: anytype) !void {
    if (self.cmd_out) |output| {
        try output.writer().print(format, args);
    }
}

fn printLineNumber(self: *const Runner, line: usize) !void {
    // the first line number is really 1, for the user
    try self.printToCmdOut("{: >8} ", .{line + 1});
}

fn printCommandPrompt(self: *const Runner) !void {
    try self.printToCmdOut("+ ", .{});
}

fn handleError(self: *const Runner, err: anyerror) !void {
    const string = switch (err) {
        // from the parser
        error.OneBasedIndexIsZero => "index cannot be zero",
        error.RangeStartIsZero => "range start index cannot be zero",
        error.RangeEndIsZero => "range end index cannot be zero",
        // from the write or write & save commands
        error.NoOutputSpecified => "no output filename specified",
        // from the substitution command
        error.InvalidRegex => "failed to compile regex",
        // from LineBuffer
        error.InvalidRange => "range has negative length",
        error.RangeOutOfBounds => "range falls outside of file",
        error.IndexOutOfBounds => "index is out of bounds",
        // not too problematic
        error.CommandNotRecognized => "command not recognized",
        else => return err,
    };
    try self.printToCmdOut("Error: {s}\n", .{string});
}

fn runHelp(self: *Runner) !void {
    try self.printToCmdOut(
        \\Welcome to the simple line editor.
        \\    You are currently on line {}, out of {} lines total.
        \\
        \\  Internal Memory:
        \\MODE                     COMMAND or EDIT (swap using .)
        \\LINE                     the current line number
        \\FILE                     the current output file name
        \\
        \\  Basic Types:
        \\NUMBER                   any sequence of base-10 digits
        \\STRING                   any sequence of bytes
        \\REGEX                    / deliminated regular expression
        \\INDEX:
        \\    NUMBER               line NUMBER
        \\    $                    the last line
        \\RANGE:
        \\    INDEX                the range spanning [INDEX, INDEX]
        \\    INDEX,               the range spanning [INDEX, the last line]
        \\    ,INDEX               the range spanning [0, INDEX]
        \\    A,B                  the range spanning [A (INDEX), B (INDEX)]
        \\
        \\Commands (for EDIT MODE):
        \\    .                    MODE <- COMMAND
        \\    [STRING]             inserts STRING at LINE, LINE <- LINE + 1
        \\
        \\Commands (for COMMAND MODE):
        \\    d                    deletes 1 line at LINE
        \\    [RANGE]d             deletes all lines in RANGE
        \\    .                    MODE <- EDIT
        \\    [INDEX].             LINE <- INDEX, MODE <- EDIT
        \\    .[STRING]            inserts STRING at LINE
        \\    [INDEX].[STRING]     LINE <- INDEX, inserts STRING at LINE
        \\    [INDEX]              LINE <- INDEX
        \\    p                    prints 16 lines at LINE
        \\    [RANGE]p             prints all lines in RANGE
        \\    s/[OLD]/[NEW]        replaces all OLD (REGEX) for NEW on LINE
        \\    [RANGE]s/[OLD]/[NEW] replaces all OLD (REGEX) for NEW in RANGE
        \\    w                    saves all lines to FILE
        \\    [RANGE]w             saves all lines in RANGE to FILE
        \\    w [NAME]             FILE <- NAME, saves all lines to FILE
        \\    [RANGE]w [NAME]      FILE <- NAME, saves all lines in RANGE to FILE
        \\    wq                   saves all lines to FILE, exits
        \\    [RANGE]wq            saves all lines in RANGE to FILE, exits
        \\    wq [NAME]            FILE <- NAME, saves all lines to FILE, exits
        \\    [RANGE]wq [NAME]     FILE <- NAME, saves all lines in RANGE to FILE, exits
        \\    q                    exits
        \\    h                    displays this text
        \\
    ,
        .{ self.line + 1, self.buffer.length() },
    );
}

fn runInsert(self: *Runner, insert: parser.Insert) !void {
    if (insert.line) |line| self.runLine(line);
    if (insert.text) |line_text| {
        try self.buffer.insertLine(self.line, line_text);
        self.line += 1;
    } else {
        self.mode = .edit;
    }
}

fn runLine(self: *Runner, line: Number) void {
    // the one exception - if there are no lines, we don't need to
    // be within the range of all the lines. We can be at line 0.
    self.line = line.toIndex(self.buffer.length()) orelse 0;
}

fn runDelete(self: *Runner, range: ?Range) !void {
    // no range? only one line.
    const default = BoundedRange.fromIndex(self.line, 1);
    const bounds = self.resolveRange(default, range);
    self.line = bounds.start;
    try self.buffer.deleteLines(bounds);
}

fn runPrint(self: *Runner, range: ?Range) !void {
    // by default print 16 lines (if we can), completely arbitrary
    const default = BoundedRange.fromIndex(self.line, 16);
    const bounds = self.resolveRange(default, range);
    const lines = try self.buffer.getLines(bounds);
    self.line = bounds.start + lines.len;
    for (lines, 0..) |line, offset| {
        const line_number = bounds.start + offset;
        try self.printLineNumber(line_number);
        try self.printToCmdOut("{s}\n", .{line});
    }
}

fn runSubstitution(self: *Runner, substitution: parser.Substitution) !void {
    const regex = mvzr.compile(substitution.pattern) orelse return error.InvalidRegex;
    // if no range was specified, replace only on the current line
    const default = BoundedRange.fromIndex(self.line, 1);
    const bounds = self.resolveRange(default, substitution.range);
    self.line = bounds.start;
    const lines = try self.buffer.getLines(bounds);
    for (0..lines.len) |line_offset| {
        const line_number = bounds.start + line_offset;
        while (true) {
            const line = self.buffer.lines.items[line_number];
            if (regex.match(line)) |match| {
                const changed = try std.fmt.allocPrint(self.alloc, "{s}{s}{s}", .{
                    line[0..match.start], substitution.replacement, line[match.end..],
                });
                defer self.alloc.free(changed);
                try self.buffer.deleteLines(BoundedRange.fromIndex(line_number, 1));
                try self.buffer.insertLine(line_number, changed);
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
        const default = BoundedRange.complete(self.buffer.length());
        const range = self.resolveRange(default, write.range);
        try self.buffer.save(file_name, range);
    } else return error.NoOutputSpecified;
}

fn resolveRange(self: *const Runner, default: BoundedRange, range: ?Range) BoundedRange {
    if (range) |resolved| {
        return resolved.toBounded(self.buffer.length());
    } else return default.clamp(self.buffer.length());
}

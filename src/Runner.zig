const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayListUnmanaged;
const File = std.fs.File;
const TermSize = @import("TermSize.zig");
const LineBuffer = @import("LineBuffer.zig");
const Undo = @import("Undo.zig");
const Change = Undo.Change;
const Range = @import("Range.zig");
const Lines = @import("Lines.zig");
const misc = @import("misc.zig");
const regex = @import("regex.zig");

const Editor = struct {
    attempted_exit: bool,
    dirty: bool,
    line: usize,
    file_out: ?[]const u8,
    buffer: LineBuffer,
    undo: Undo,

    pub fn init(alloc: Allocator, file_in: ?[]const u8, file_out: ?[]const u8) !Editor {
        return .{
            .attempted_exit = false,
            .dirty = false,
            .line = 0,
            .file_out = file_out,
            .buffer = try .init(alloc, file_in),
            .undo = .empty,
        };
    }

    pub fn deinit(self: *Editor, alloc: Allocator) void {
        self.buffer.deinit(alloc);
        self.undo.deinit(alloc);
        self.* = undefined;
    }
};

alloc: Allocator,
cmd_in: File,
cmd_out: ?File,
state: Editor,

pub fn init(
    alloc: Allocator,
    cmd_in: File,
    cmd_out: ?File,
    file_in: ?[]const u8,
    file_out: ?[]const u8,
) !@This() {
    const state: Editor = try .init(alloc, file_in, file_out);
    return .{ .alloc = alloc, .cmd_in = cmd_in, .cmd_out = cmd_out, .state = state };
}

pub fn deinit(self: *@This()) void {
    self.state.deinit(self.alloc);
    self.* = undefined;
}

// executes the runner, handling all errors
pub fn run(self: *Self) !void {
    while (true) {
        if (self.handlingLoop()) |_| break else |err| {
            const err_string = switch (err) {
                error.Malformed => "Malformed command",
                error.InvalidRange => "Invalid range",
                error.OutOfBounds => "Line out of bounds",
                error.OutOfMemory => "Out of memory",
                error.NoLastIndex => "Empty buffer - No last line",
                error.FilenameNotSet => "Output file not set",
                error.NoMoreUndoSteps => "No more undo steps",
                error.NoMoreRedoSteps => "No more redo steps",
                error.NumberTooLarge => "Number too large",
                error.ExitWithoutSave => "File may not be saved",
                else => return err,
            };
            try self.print("Error: {s}\n", .{err_string});
        }
    }
}

// helper function to print if we can
fn print(self: Self, comptime format: []const u8, args: anytype) !void {
    if (self.cmd_out) |output| {
        try output.writer().print(format, args);
    }
}

// helper function to print a line number
fn printLineNumber(self: Self, line: usize) !void {
    try self.print("{: >6} ", .{line + 1});
}

const InputResult = struct {
    reached_eof: bool,
    text: []const u8,
};

// helper function to get user input
fn input(self: Self) !InputResult {
    var cmd: List(u8) = .empty;
    defer cmd.deinit(self.alloc);
    const cmd_w = cmd.writer(self.alloc);
    // read user result, break on "enter"
    const result = self.cmd_in.reader().streamUntilDelimiter(cmd_w, '\n', null);
    result catch |err| switch (err) {
        error.EndOfStream => {
            const text = try cmd.toOwnedSlice(self.alloc);
            return .{ .reached_eof = true, .text = text };
        },
        else => return err,
    };
    const text = try cmd.toOwnedSlice(self.alloc);
    return .{ .reached_eof = false, .text = text };
}

// command mode dispatch
fn handlingLoop(self: *Self) !void {
    loop: while (true) {
        // display command prompt, get input
        try self.print("+ ", .{});
        const user_input = try self.input();
        const cmd = user_input.text;
        defer self.alloc.free(cmd);
        // set up the change list for an undo step
        var step: List(Change) = .empty;
        defer {
            for (step.items) |change| {
                change.deinit(self.alloc);
            }
            step.deinit(self.alloc);
        }
        // locate the "range" section of the command
        const range_end = Range.parseableEnd(cmd);
        const range_str = cmd[0..range_end];
        const cmd_str = cmd[range_end..];
        if (cmd_str.len == 1 and cmd_str[0] == 'q') { // quit
            if (self.state.dirty and !self.state.attempted_exit) {
                self.state.attempted_exit = true;
                return error.ExitWithoutSave;
            } else break :loop;
        } else {
            self.state.attempted_exit = false;
            switch (cmd_str.len) {
                0 => try self.lineCommand(range_str),
                else => {
                    const data_str = cmd_str[1..];
                    switch (cmd_str[0]) {
                        // commands which don't modify the buffer
                        'p' => try self.printCommand(range_str, data_str), // print
                        'w' => try self.writeCommand(range_str, data_str), // write
                        // commands which modify the buffer
                        '.' => try self.insertCommand(&step, range_str, data_str), // insert
                        'd' => try self.deleteCommand(&step, range_str, data_str), // delete
                        's' => try self.substituteCommand(&step, range_str, data_str), // substitute
                        'm' => try self.moveCommand(&step, range_str, data_str), // move
                        'c' => try self.copyCommand(&step, range_str, data_str), // copy
                        'x' => try self.replaceCommand(&step, range_str, data_str), // change
                        // undo/redo (will probably modify the buffer)
                        'u' => try self.undoCommand(range_str, data_str), // undo
                        'r' => try self.redoCommand(range_str, data_str), // redo
                        else => return error.Malformed,
                    }
                },
            }
        }
        // apply the change to the buffer, make an undo step
        if (step.items.len > 0) self.state.dirty = true;
        try self.state.undo.apply(self.alloc, step.items, &self.state.buffer);
        // we have reached EOF of the command input, exit
        if (user_input.reached_eof) break :loop;
    }
}

// sets the current line
fn lineCommand(self: *Self, range_str: []const u8) !void {
    const default: Range = .init(self.state.line, 1);
    const line_count = self.state.buffer.length();
    const range: Range = try .parse(range_str, self.state.line, line_count, default);
    if (range.length > 1) {
        return error.Malformed;
    } else if (range.length == 1) {
        self.state.line = range.start;
    }
}

// prints 16 lines at current line by default - updates current line to after last printed
fn printCommand(
    self: *Self,
    range_str: []const u8,
    data_str: []const u8,
) !void {
    // by default, fill the screen with lines we print
    const line_count = blk: {
        const cmd_out_file = self.cmd_out orelse return; // can't print otherwise
        const term_size: ?TermSize = try .size(cmd_out_file);
        if (term_size) |size| {
            break :blk @max(8, size.height -| 1);
        } else {
            break :blk 16;
        }
    };
    const default: Range = .init(self.state.line, @intCast(line_count));
    const length = self.state.buffer.length();
    const range: Range = try .parse(range_str, self.state.line, length, default);
    if (self.state.buffer.get(range)) |lines| {
        self.state.line += lines.text.len;
        for (lines.text, range.start..) |text, line| {
            // allow the user to add a regexp afterward to print out matching lines
            if (try regex.match(data_str, text)) |_| {
                try self.printLineNumber(line);
                try self.print("{s}\n", .{text});
            }
        }
    }
}

// writes the range to the specified (or last specified) file name
// if the last line printed is the last line in the buffer, no newline
// is appended to the output file.
fn writeCommand(
    self: *Self,
    range_str: []const u8,
    data_str: []const u8,
) !void {
    const file_name = switch (data_str.len) {
        0 => if (self.state.file_out) |name| blk: {
            break :blk name;
        } else return error.FilenameNotSet,
        else => data_str,
    };
    const len = self.state.buffer.length();
    const entire_file: Range = .init(0, len);
    const range: Range = try .parse(range_str, self.state.line, len, entire_file);
    try self.state.buffer.save(file_name, range);
    self.state.dirty = false;
}

// without command data, drops into insert mode at the specified line
// command is special - $ doesn't refer to the last line, but right after
fn insertCommand(
    self: *Self,
    step: *List(Change),
    range_str: []const u8,
    data_str: []const u8,
) !void {
    const default: Range = .init(self.state.line, 1);
    // allow us to insert right after the buffer - using $
    const insert_len = self.state.buffer.length() + 1;
    const range: Range = try .parse(range_str, self.state.line, insert_len, default);
    if (range.start > self.state.buffer.length()) {
        // don't write out-of-bounds, resize to write at wherever
        try step.append(self.alloc, .{ .resize = range.start });
    }
    if (range.length != 1) return error.Malformed;
    switch (data_str.len) {
        0 => {
            self.state.line = range.start;
            // infinite mode is escaped only by inputting a single period
            insert_inf: while (true) {
                // get user input
                try self.printLineNumber(self.state.line);
                const user_input = try self.input();
                const text = user_input.text;
                defer self.alloc.free(text);
                if (text.len == 1 and text[0] == '.') break :insert_inf;
                // insert the line
                const lines: Lines = .init((&text)[0..1], self.state.line);
                const owned = try lines.dupe(self.alloc);
                errdefer owned.deinit(self.alloc);
                try step.append(self.alloc, .{ .insert = owned });
                self.state.line += 1;
                // reached EOF
                if (user_input.reached_eof) break :insert_inf;
            }
        },
        else => { // one-shot mode
            const lines: Lines = .init((&data_str)[0..1], range.start);
            const owned = try lines.dupe(self.alloc);
            errdefer owned.deinit(self.alloc);
            try step.append(self.alloc, .{ .insert = owned });
            self.state.line = range.end();
        },
    }
}

// deletes lines specified in the range. Sets current line to first index deleted
fn deleteCommand(
    self: *Self,
    step: *List(Change),
    range_str: []const u8,
    data_str: []const u8,
) !void {
    const default: Range = .init(self.state.line, 1);
    const length = self.state.buffer.length();
    const range: Range = try .parse(range_str, self.state.line, length, default);
    self.state.line = range.start;
    if (self.state.buffer.get(range)) |lines| {
        // allow the user to add regexp afterward to delete matching lines
        for (0..lines.text.len) |offset| {
            // delete in reverse order so our indexes won't be messed up
            const rev_offset = lines.text.len - (offset + 1);
            const text = lines.text[rev_offset];
            const line: Range = .init(lines.start + rev_offset, 1);
            if (try regex.match(data_str, text)) |_| {
                try step.append(self.alloc, .{ .delete = line });
            }
        }
    }
}

// substitute text with other text - range defaults to entire file
// data_str is [regexp]/[replacement], escape with \
fn substituteCommand(
    self: *Self,
    step: *List(Change),
    range_str: []const u8,
    data_str: []const u8,
) !void {
    const length = self.state.buffer.length();
    const default: Range = .init(0, length);
    const range: Range = try .parse(range_str, self.state.line, length, default);
    const rep_strs = misc.parseReplaceStrings(data_str) orelse return error.Malformed;
    if (self.state.buffer.get(range)) |lines| {
        for (lines.text, lines.start..) |text, line| {
            var fresh_text: List(u8) = .empty;
            defer fresh_text.deinit(self.alloc);

            // substitutes all rep_strs.regexp matches in
            // each line in range with rep_strs.replacement
            var start: usize = 0;
            loop: while (start < text.len) {
                const match = regex.match(rep_strs.regexp, text[start..]) catch {
                    return error.Malformed;
                } orelse break :loop;
                // append the part it skipped over
                try fresh_text.appendSlice(self.alloc, text[start..][0..match.start]);
                // append the replacement text instead of the match
                try fresh_text.appendSlice(self.alloc, rep_strs.replacement);
                start = @max(start + 1, match.end());
            }
            // append the rest
            try fresh_text.appendSlice(self.alloc, text[@min(text.len, start)..]);

            // if there has been no change don't replace the line
            if (start > 0) {
                const replace: Lines = Lines.init((&fresh_text.items)[0..1], line);
                const owned = try replace.dupe(self.alloc);
                errdefer owned.deinit(self.alloc);
                try step.append(self.alloc, .{ .replace = owned });
            }
        }
    }
}

// move one range of text to another location (defined by data_str)
fn moveCommand(
    self: *Self,
    step: *List(Change),
    range_str: []const u8,
    data_str: []const u8,
) !void {
    const line_count = self.state.buffer.length();
    // plus one, because we can move to right after the other text (using $)
    const move_dest_maybe = try Range.parseLine(data_str, self.state.line, line_count + 1);
    const move_dest = move_dest_maybe orelse return error.Malformed;
    if (move_dest > line_count) {
        // don't move out-of-bounds, resize to move wherever
        try step.append(self.alloc, .{ .resize = move_dest });
    }
    const default: Range = .init(self.state.line, 1);
    const range: Range = try .parse(range_str, self.state.line, line_count, default);
    const move_text = self.state.buffer.get(range) orelse return error.OutOfBounds;
    var owned = try move_text.dupe(self.alloc);
    errdefer owned.deinit(self.alloc);
    try step.append(self.alloc, .{ .delete = move_text.range() });
    // insert at the correct location (deleting shifts further items)
    if (move_dest > move_text.start) {
        owned.start = move_dest - move_text.text.len;
    } else {
        owned.start = move_dest;
    }
    try step.append(self.alloc, .{ .insert = owned });
}

// copy one range of text to another location (defined by data_str)
fn copyCommand(
    self: *Self,
    step: *List(Change),
    range_str: []const u8,
    data_str: []const u8,
) !void {
    const line_count = self.state.buffer.length();
    // plus one, because we can copy to right after the other text (using $)
    const copy_dest_maybe = try Range.parseLine(data_str, self.state.line, line_count + 1);
    const copy_dest = copy_dest_maybe orelse return error.Malformed;
    if (copy_dest > line_count) {
        // don't copy out-of-bounds, resize to copy wherever
        try step.append(self.alloc, .{ .resize = copy_dest });
    }
    const default: Range = .init(self.state.line, 1);
    const range: Range = try .parse(range_str, self.state.line, line_count, default);
    const copy_text = self.state.buffer.get(range) orelse return error.OutOfBounds;
    var owned = try copy_text.dupe(self.alloc);
    owned.start = copy_dest;
    errdefer owned.deinit(self.alloc);
    try step.append(self.alloc, .{ .insert = owned });
}

// replaces lines with user input (if data_str.len == 0), or an edit prompt
fn replaceCommand(
    self: *Self,
    step: *List(Change),
    range_str: []const u8,
    data_str: []const u8,
) !void {
    const default: Range = .init(self.state.line, 1);
    const length = self.state.buffer.length();
    const range: Range = try .parse(range_str, self.state.line, length, default);
    self.state.line = range.start;
    switch (data_str.len) {
        // finite mode is escaped only by replacing the entire range
        0 => replace_finite: for (range.start..range.end()) |line| {
            // get user input
            try self.printLineNumber(self.state.line);
            const user_input = try self.input();
            const text = user_input.text;
            defer self.alloc.free(text);
            // insert the line
            const lines: Lines = .init((&text)[0..1], line);
            const owned = try lines.dupe(self.alloc);
            errdefer owned.deinit(self.alloc);
            try step.append(self.alloc, .{ .replace = owned });
            // exit if we had hit EOF
            if (user_input.reached_eof) break :replace_finite;
        },
        // replace the entire range with data_str
        else => for (range.start..range.end()) |line| {
            const lines: Lines = .init((&data_str)[0..1], line);
            const owned = try lines.dupe(self.alloc);
            errdefer owned.deinit(self.alloc);
            try step.append(self.alloc, .{ .replace = owned });
        },
    }
}

// revert the previous edit to the buffer
fn undoCommand(
    self: *Self,
    range_str: []const u8,
    data_str: []const u8,
) !void {
    if (range_str.len > 0) return error.Malformed;
    const times = if (data_str.len > 0) try misc.parseUsize(data_str) else 1;
    for (0..times) |_| {
        try self.state.undo.undo(self.alloc, &self.state.buffer);
    }
}

// redo the previous edit to the buffer - "previous edits" are discarded on buffer edit
fn redoCommand(
    self: *Self,
    range_str: []const u8,
    data_str: []const u8,
) !void {
    if (range_str.len > 0) return error.Malformed;
    const times = if (data_str.len > 0) try misc.parseUsize(data_str) else 1;
    for (0..times) |_| {
        try self.state.undo.redo(self.alloc, &self.state.buffer);
    }
}

// testing

test "basically the entire thing" {
    const alloc = std.testing.allocator;
    const expected = @embedFile("testing/expected");
    const script = try std.fs.cwd().openFile("src/testing/script", .{});
    defer script.close();
    const initial = "src/testing/initial";
    var runner = try init(alloc, script, null, initial, null);
    defer runner.deinit();
    try runner.run();
    try LineBuffer.expectEqual(&runner.state.buffer, expected);
    // when we get a clean build, delete our helpful "actual" output
    try std.fs.cwd().deleteFile("src/testing/actual");
}

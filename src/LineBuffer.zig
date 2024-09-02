const Self = @This();

const std = @import("std");
const List = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const Range = @import("Range.zig");
const Lines = @import("Lines.zig");

lines: List([]const u8),

pub const empty: Self = .{ .lines = .empty };

// init/deinit

pub fn init(alloc: Allocator, file_name: ?[]const u8) !Self {
    var self: Self = .empty;
    if (file_name) |name| {
        // in the case of loading an empty file, create a new file
        const file = try std.fs.cwd().createFile(name, .{ .read = true, .truncate = false });
        defer file.close();
        const reader = file.reader();
        // read the file in line-by-line, making sure to capture any last newline
        var line_text: List(u8) = .empty;
        defer line_text.deinit(alloc);
        const writer = line_text.writer(alloc);
        while (true) {
            // re-use the allocated memory for each consecutive line
            defer line_text.clearRetainingCapacity();
            const result = reader.streamUntilDelimiter(writer, '\n', null);
            // insert the loaded line at the end of the file
            const text = (&line_text.items)[0..1];
            const line: Lines = .init(text, self.length());
            try self.insert(alloc, line);
            // we have only finished once we have hit EOF
            result catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
        }
    }
    return self;
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    for (self.lines.items) |line| alloc.free(line);
    self.lines.deinit(alloc);
    self.* = undefined;
}

// constant operations

pub fn get(self: Self, range: Range) ?Lines {
    const end = @min(range.end, self.length());
    if (range.start >= end) return null;
    const text = self.lines.items[range.start..end];
    return .init(text, range.start);
}

pub fn length(self: Self) usize {
    return self.lines.items.len;
}

pub fn save(self: Self, file_name: []const u8, range: Range) !void {
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    if (self.get(range)) |lines| {
        for (lines.text, lines.start..) |line, index| {
            try file.writeAll(line);
            if (index + 1 != self.length()) {
                try file.writeAll("\n");
            }
        }
    }
}

// editing operations

pub fn replace(self: *Self, alloc: Allocator, lines: Lines) !void {
    const range = lines.range();
    if (range.end >= self.length()) return error.OutOfBounds;
    const new_lines = try lines.dupe(alloc);
    defer alloc.free(new_lines.text); // just free the array (we own the lines)
    const old_lines = self.lines.items[range.start..range.end];
    for (old_lines, new_lines.text) |*old, new| {
        alloc.free(old.*);
        old.* = new;
    }
}

pub fn insert(self: *Self, alloc: Allocator, lines: Lines) !void {
    if (self.length() < lines.start) return error.OutOfBounds;
    try self.lines.ensureUnusedCapacity(alloc, lines.text.len);
    const new_lines = try lines.dupe(alloc);
    defer alloc.free(new_lines.text); // just free the array (we own the lines)
    for (new_lines.text, new_lines.start..) |owned, idx| {
        self.lines.insertAssumeCapacity(idx, owned);
    }
}

pub fn delete(self: *Self, alloc: Allocator, range: Range) void {
    if (self.get(range)) |lines| {
        for (lines.text) |line| {
            alloc.free(line);
        }
        self.lines.replaceRangeAssumeCapacity(lines.start, lines.text.len, &.{});
    }
}

pub fn resize(self: *Self, alloc: Allocator, len: usize) !void {
    if (len > self.length()) {
        const added_amount = len - self.length();
        try self.lines.appendNTimes(alloc, &.{}, added_amount);
    } else if (len < self.length()) {
        const start = self.length() - len;
        const range: Range = .initLen(start, len);
        if (self.get(range)) |to_remove| {
            for (to_remove.text) |line| {
                alloc.free(line);
            }
            self.lines.shrinkRetainingCapacity(len);
        }
    }
}

// testing

pub fn expectEqual(buffer: *const Self, lines: []const u8) !void {
    if (!@import("builtin").is_test) return error.ExpectedTestBuild;
    var buf: [256]u8 = undefined;
    var stream_out = std.io.fixedBufferStream(&buf);
    var stream_in = std.io.fixedBufferStream(lines);
    const read_in = stream_in.reader();
    const line_writer = stream_out.writer();
    for (buffer.lines.items, 0..) |actual, line| {
        defer stream_out.pos = 0;
        const stream_res = read_in.streamUntilDelimiter(line_writer, '\n', null);
        if (line + 1 == buffer.lines.items.len) {
            try std.testing.expectError(error.EndOfStream, stream_res);
        } else {
            try stream_res;
        }
        const expected = stream_out.buffer[0..stream_out.pos];
        try std.testing.expectEqualSlices(u8, expected, actual);
    }
}

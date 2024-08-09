const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Range = @import("Range.zig");

alloc: Allocator,
lines: std.ArrayListUnmanaged([]const u8) = .{},

pub fn init(alloc: Allocator) Self {
    return .{ .alloc = alloc };
}

pub fn deinit(self: *Self) void {
    for (self.lines.items) |line| self.alloc.free(line);
    self.lines.deinit(self.alloc);
}

pub fn length(self: Self) usize {
    return self.lines.items.len;
}

pub fn get(self: Self, range: Range) ?[]const []const u8 {
    const clamped = range.clamp(self.length());
    return self.lines.items[clamped.start..clamped.end];
}

pub fn save(self: Self, file_name: []const u8, range: Range) !void {
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    if (self.get(range)) |lines| {
        for (lines, 0..) |line, index| {
            try file.writeAll(line);
            if (index + 1 != self.length()) {
                try file.writeAll("\n");
            }
        }
    }
}

pub fn resize(self: *Self, new_length: usize) !void {
    if (new_length > self.length()) {
        const new_lines = new_length - self.length();
        try self.lines.appendNTimes(self.alloc, &.{}, new_lines);
    }
}

pub fn replace(self: *Self, range: Range, text: []const []const u8) !void {
    try self.delete(range);
    try self.insert(range.start, text);
}

// TODO: adjust for undo/redo
pub fn insert(self: *Self, dest: usize, text: []const []const u8) !void {
    try self.resize(dest);
    const clamped = @min(dest, self.length());
    for (text, clamped..) |line_text, index| {
        const owned = try self.alloc.dupe(u8, line_text);
        try self.lines.insert(self.alloc, index, owned);
    }
}

// TODO: adjust for undo/redo
pub fn move(self: *Self, source: Range, dest: usize) !void {
    const clamped = source.clamp(self.length());
    if (self.get(clamped)) |lines_to_move| {
        // this buffer holds the lines we are planning to move
        var moved = std.ArrayListUnmanaged([]const u8){};
        defer moved.deinit(self.alloc);
        try moved.appendSlice(self.alloc, lines_to_move);
        // remove the lines, pad the buffer so we aren't out-of-bounds
        self.lines.replaceRangeAssumeCapacity(clamped.start, clamped.length(), &.{});
        try self.resize(dest);
        try self.lines.insertSlice(self.alloc, dest, moved.items);
    }
}

// TODO: adjust for undo/redo
pub fn copy(self: *Self, source: Range, dest: usize) !void {
    const clamped = source.clamp(self.length());
    if (self.get(clamped)) |lines_to_copy| {
        // this buffer holds the lines we are planning to copy
        var copied = std.ArrayListUnmanaged([]const u8){};
        defer copied.deinit(self.alloc);
        try copied.appendSlice(self.alloc, lines_to_copy);
        // pad the buffer so we can copy without hitting out-of-bounds
        try self.resize(dest);
        // duplicate the copied lines to prevent double-free
        for (copied.items) |*line| line.* = try self.alloc.dupe(u8, line.*);
        try self.lines.insertSlice(self.alloc, dest, copied.items);
    }
}

// TODO: adjust for undo/redo
pub fn delete(self: *Self, range: Range) !void {
    if (self.get(range)) |lines| {
        if (lines.len == 0) return;
        for (lines) |line| self.alloc.free(line);
        self.lines.replaceRangeAssumeCapacity(range.start, lines.len, &.{});
    }
}

// TODO: adjust for undo/redo tree
pub fn load(self: *Self, file_name: []const u8) !void {
    // remove previous lines
    for (self.lines.items) |line| self.alloc.free(line);
    self.lines.clearRetainingCapacity();
    // in the case of loading an empty file, create a new file
    const file = try std.fs.cwd().createFile(
        file_name,
        .{ .read = true, .truncate = false },
    );
    defer file.close();
    // read the file in line-by-line, making sure to capture any last newline
    var line = std.ArrayListUnmanaged(u8){};
    defer line.deinit(self.alloc);
    var hit_eof: bool = false;
    while (!hit_eof) {
        // re-use the allocated memory for each consecutive line, freeing when we are done
        defer line.clearRetainingCapacity();
        const result = file.reader().streamUntilDelimiter(line.writer(self.alloc), '\n', null);
        // don't immediately exit with we hit EOF, but do prepare to exit
        result catch |err| switch (err) {
            error.EndOfStream => hit_eof = true,
            else => return err,
        };
        // insert the loaded line at the end of the file
        try self.insert(self.length(), &.{line.items});
    }
}

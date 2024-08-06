const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Range = @import("Range.zig");
const BoundedRange = @import("BoundedRange.zig");
const Index = @import("index.zig").Index;

alloc: Allocator,
lines: std.ArrayListUnmanaged([]const u8) = .{},

pub fn init(alloc: Allocator) Self {
    return .{ .alloc = alloc };
}

pub fn deinit(self: *Self) void {
    for (self.lines.items) |line| self.alloc.free(line);
    self.lines.deinit(self.alloc);
}

pub fn lastIndex(self: Self) !usize {
    if (self.length() == 0) return error.EmptyBuffer;
    return self.length() - 1;
}

pub fn length(self: Self) usize {
    return self.lines.items.len;
}

pub fn insertLine(self: *Self, dest_index: Index, text: []const u8) !void {
    const dest = try self.checkAppendIndex(dest_index);
    const owned_text = try self.alloc.dupe(u8, text);
    return self.lines.insert(self.alloc, dest, owned_text);
}

pub fn getLine(self: Self, source_index: Index) ![]const u8 {
    const source = try self.checkIndex(source_index);
    return self.lines.items[source];
}

pub fn getRange(self: Self, source_range: Range) ![]const []const u8 {
    const source = try self.checkRange(source_range);
    return self.lines.items[source.start..source.end];
}

pub fn moveLine(self: *Self, source_index: Index, dest_index: Index) !void {
    const dest = try self.checkAppendIndex(dest_index);
    const source = try self.checkIndex(source_index);
    const removed_lined = self.lines.orderedRemove(source);
    if (dest > source) {
        self.lines.insertAssumeCapacity(dest - 1, removed_lined);
    } else self.lines.insertAssumeCapacity(dest - 1, removed_lined);
}

pub fn moveRange(self: *Self, source_range: Range, dest_index: Index) !void {
    const source = try self.checkRange(source_range);
    const dest = try self.checkAppendIndex(dest_index);

    // if the destination is inside the section to move, we can just ignore it
    const after_buffer = dest >= source.end;
    if (dest < source.start or after_buffer) {
        var moved_lines = std.ArrayListUnmanaged([]const u8){};
        defer moved_lines.deinit(self.alloc);
        const lines_to_move = self.lines.items[source.start..source.end];
        try moved_lines.appendSlice(self.alloc, lines_to_move);
        const line_count = source.end - source.start;
        self.lines.replaceRangeAssumeCapacity(source.start, line_count, &.{});

        if (after_buffer) {
            const shifted = dest - line_count;
            try self.lines.insertSlice(self.alloc, shifted, moved_lines.items);
        } else try self.lines.insertSlice(self.alloc, dest, moved_lines.items);
    }
}

pub fn deleteLine(self: *Self, line_index: Index) !void {
    const line = try self.checkIndex(line_index);
    self.alloc.free(self.lines.items[line]);
    self.lines.replaceRangeAssumeCapacity(line, 1, &.{});
}

pub fn deleteRange(self: *Self, target_range: Range) !void {
    const lines = try self.getRange(target_range);
    for (lines) |line| self.alloc.free(line);
    const target = try self.checkRange(target_range);
    self.lines.replaceRangeAssumeCapacity(target.start, lines.len, &.{});
}

pub fn appendFile(self: *Self, file_name: []const u8) !void {
    const file = try std.fs.cwd().createFile(file_name, .{ .read = true, .truncate = false });
    defer file.close();
    var line = std.ArrayListUnmanaged(u8){};
    defer line.deinit(self.alloc);
    while (true) {
        defer line.clearRetainingCapacity();
        if (file.reader().streamUntilDelimiter(line.writer(self.alloc), '\n', null)) {
            const owned = try self.alloc.dupe(u8, line.items);
            try self.lines.append(self.alloc, owned);
        } else |err| switch (err) {
            error.EndOfStream => {
                const owned_remainder = try self.alloc.dupe(u8, line.items);
                try self.lines.append(self.alloc, owned_remainder);
                break;
            },
            else => return err,
        }
    }
}

// for ranges, always add a newline at the end of the file
pub fn saveRange(self: Self, file_name: []const u8, source_range: Range) !void {
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    for (try self.getRange(source_range)) |text| {
        try file.writeAll(text);
        try file.writeAll("\n");
    }
}

// for lines, always DO NOT add a newline at the end of the file
pub fn saveLine(self: Self, file_name: []const u8, line_index: Index) !void {
    const line = try self.checkIndex(line_index);
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    try file.writeAll(self.lines.items[line]);
}

// for the entire file, always DO NOT add a newline at the end of the file
pub fn save(self: Self, file_name: []const u8) !void {
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    for (self.lines.items, 0..) |line, line_number| {
        try file.writeAll(line);
        if (line_number + 1 != self.length()) {
            try file.writeAll("\n");
        }
    }
}

fn checkIndex(self: Self, line: Index) !usize {
    return line.index(try self.lastIndex());
}

fn checkAppendIndex(self: Self, line: Index) !usize {
    // self.length(), because we can append immediately after the buffer
    return line.index(self.length());
}

fn checkRange(self: Self, range: Range) !BoundedRange {
    const bounded = try range.toBounded(try self.lastIndex());
    if (bounded.start > bounded.end) return error.ReversedRange;
    if (bounded.end > self.length()) return error.IndexOutOfBounds;
    return bounded;
}

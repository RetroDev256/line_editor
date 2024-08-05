const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

alloc: Allocator,
lines: std.ArrayListUnmanaged([]const u8) = .{},

/// 'start' is inclusive, 'end' is not inclusive
const BoundedRange = @import("range.zig").BoundedRange;

pub fn init(alloc: Allocator) Self {
    return .{ .alloc = alloc };
}

pub fn deinit(self: *@This()) void {
    for (self.lines.items) |line| self.alloc.free(line);
    self.lines.deinit(self.alloc);
}

pub fn insertLine(self: *@This(), line_number: usize, text: []const u8) !void {
    // we don't check >= because we can insert after the buffer
    if (line_number > self.length()) return error.IndexOutOfBounds;
    const owned_text = try self.alloc.dupe(u8, text);
    return self.lines.insert(self.alloc, line_number, owned_text);
}

pub fn lastIndex(self: @This()) ?usize {
    if (self.length() == 0) return null;
    return self.lines.items.len - 1;
}

pub fn length(self: @This()) usize {
    return self.lines.items.len;
}

pub fn getLines(self: @This(), range: BoundedRange) ![]const []const u8 {
    try range.check(self.length());
    return self.lines.items[range.start..range.end];
}

pub fn moveLines(self: *@This(), range: BoundedRange, line_number: usize) !void {
    // we don't check >= because we can insert after the buffer
    if (line_number > self.length()) return error.IndexOutOfBounds;
    try range.check(self.length());

    // if the destination is inside the section to move, we can just ignore it
    const after_buffer = line_number >= range.end;
    if (line_number < range.start or after_buffer) {
        var moved_lines = std.ArrayListUnmanaged([]const u8){};
        defer moved_lines.deinit(self.alloc);

        const lines_to_move = self.lines.items[range.start..range.end];
        try moved_lines.appendSlice(self.alloc, lines_to_move);

        const line_count = range.end - range.start;
        self.lines.replaceRangeAssumeCapacity(range.start, line_count, &.{});

        if (after_buffer) {
            const shifted = line_number - line_count + 1;
            try self.lines.insertSlice(self.alloc, shifted, moved_lines.items);
        } else {
            try self.lines.insertSlice(self.alloc, line_number, moved_lines.items);
        }
    }
}

pub fn deleteLines(self: *@This(), range: BoundedRange) !void {
    try range.check(self.length());
    for (self.lines.items[range.start..range.end]) |line| self.alloc.free(line);
    self.lines.replaceRangeAssumeCapacity(range.start, range.end - range.start, &.{});
}

pub fn appendFile(self: *@This(), file_name: []const u8) !void {
    const file = try std.fs.cwd().createFile(file_name, .{ .read = true, .truncate = false });
    defer file.close();
    const max_bytes = std.math.maxInt(usize);
    while (try file.reader().readUntilDelimiterOrEofAlloc(self.alloc, '\n', max_bytes)) |text| {
        const owned = try self.alloc.dupe(u8, text);
        try self.lines.append(self.alloc, owned);
    }
}

// todo: fix ending in newline
pub fn save(self: @This(), file_name: []const u8, range: BoundedRange) !void {
    try range.check(self.length());
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    for (try self.getLines(range), 0..) |text, line| {
        try file.writeAll(text);
        const line_number = line + range.start;
        // don't put a newline on the last line
        if (line_number != self.lastIndex()) {
            try file.writeAll("\n");
        }
    }
}

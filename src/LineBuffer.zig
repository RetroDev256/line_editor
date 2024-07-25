const std = @import("std");
const Allocator = std.mem.Allocator;

lines: std.ArrayListUnmanaged([]const u8) = .{},
memory: std.ArrayListUnmanaged([]const u8) = .{},

/// 'start' is inclusive, 'end' is not inclusive
const BoundedRange = @import("range.zig").BoundedRange;

pub fn deinit(self: *@This(), alloc: Allocator) void {
    for (self.memory.items) |line| alloc.free(line);
    self.lines.clearAndFree(alloc);
    self.memory.clearAndFree(alloc);
}

pub fn insertLine(self: *@This(), alloc: Allocator, line_number: usize, text: []const u8) !void {
    // + 1 because we can insert at the end of the file
    if (line_number > self.lastIndex() + 1) return error.IndexOutOfBounds;
    const owned_text = try self.store(alloc, text);
    return self.lines.insert(alloc, line_number, owned_text);
}

pub fn lastIndex(self: @This()) usize {
    return self.lines.items.len -| 1;
}

pub fn getLines(self: @This(), range: BoundedRange) ![]const []const u8 {
    try range.check(self.lastIndex());
    return self.lines.items[range.start..range.end];
}

pub fn deleteLines(self: *@This(), range: BoundedRange) !void {
    try range.check(self.lastIndex());
    self.lines.replaceRangeAssumeCapacity(range.start, range.end - range.start, &.{});
}

pub fn appendFile(self: *@This(), alloc: Allocator, file_name: []const u8) !void {
    const file = try std.fs.cwd().createFile(file_name, .{ .read = true, .truncate = false });
    defer file.close();
    const max_bytes = std.math.maxInt(usize);
    while (try file.reader().readUntilDelimiterOrEofAlloc(alloc, '\n', max_bytes)) |text| {
        const stored = try self.storeOwned(alloc, text);
        try self.lines.append(alloc, stored);
    }
}

pub fn save(self: @This(), file_name: []const u8, range: BoundedRange) !void {
    try range.check(self.lastIndex());
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

fn store(self: *@This(), alloc: Allocator, text: []const u8) ![]const u8 {
    const owned = try alloc.dupe(u8, text);
    return self.storeOwned(alloc, owned);
}

fn storeOwned(self: *@This(), alloc: Allocator, owned: []const u8) ![]const u8 {
    try self.memory.append(alloc, owned);
    return self.memory.getLast();
}

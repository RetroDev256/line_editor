const std = @import("std");
const Allocator = std.mem.Allocator;

lines: std.ArrayListUnmanaged([]const u8) = .{},
memory: std.ArrayListUnmanaged([]const u8) = .{},

pub fn deinit(self: *@This(), alloc: Allocator) void {
    for (self.memory.items) |line| alloc.free(line);
    self.lines.clearAndFree(alloc);
    self.memory.clearAndFree(alloc);
}

pub fn insertLine(self: *@This(), alloc: Allocator, line_number: usize, text: []const u8) !void {
    const owned_text = try self.store(alloc, text);
    return self.lines.insert(alloc, line_number, owned_text);
}

pub fn getLines(self: @This(), range: struct { usize, usize }) []const []const u8 {
    const actual_count = @min(range[1] -| range[0], self.lines.items.len -| range[0]);
    return self.lines.items[range[0]..][0..actual_count];
}

pub fn deleteLines(self: *@This(), range: struct { usize, usize }) void {
    const actual_count = @min(range[1] -| range[0], self.lines.items.len -| range[0]);
    self.lines.replaceRangeAssumeCapacity(range[0], actual_count, &.{});
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

pub fn save(self: @This(), file_name: []const u8, range: ?struct { usize, usize }) !void {
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    var line_offset: usize = 0;
    const real_lines_to_write = blk: {
        if (range) |r| {
            line_offset = r[0];
            break :blk self.getLines(r);
        } else {
            line_offset = 0;
            break :blk self.lines.items;
        }
    };
    for (real_lines_to_write, 0..) |text, line| {
        try file.writeAll(text);
        const line_number = line + line_offset;
        if (line_number < self.lines.items.len -| 1) try file.writeAll("\n");
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

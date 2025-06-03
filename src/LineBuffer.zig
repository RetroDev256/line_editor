const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Range = @import("Range.zig");
const InternPool = @import("InternPool.zig");

// All of the lines are owned by the pool
lines: std.ArrayListUnmanaged([]const u8),
pool: InternPool,

pub fn init(gpa: Allocator, file_path: ?[]const u8) !@This() {
    var self: @This() = .{ .lines = .empty, .pool = .init(gpa) };
    errdefer self.deinit(gpa);

    if (file_path) |path| load_file: {
        const file_open = std.fs.cwd().openFile(path, .{});
        const file = file_open catch |err| switch (err) {
            error.FileNotFound => break :load_file,
            else => return err,
        };
        defer file.close();

        var br = std.io.bufferedReader(file.reader());
        const reader = br.reader();

        var bytes: std.ArrayListUnmanaged(u8) = .empty;
        defer bytes.deinit(gpa);

        while (true) {
            const hit_eof = while (true) {
                var byte: u8 = undefined;
                const read = try reader.read(@ptrCast(&byte));
                if (read == 0) break true;
                if (byte == '\n') break false;
                try bytes.append(gpa, byte);
            };

            const line = try self.pool.add(bytes.items);
            bytes.clearRetainingCapacity();
            try self.lines.append(gpa, line);

            if (hit_eof) break;
        }
    }

    return self;
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    self.lines.deinit(gpa);
    self.pool.deinit();
    self.* = undefined;
}

// Save a range of lines to a file.
pub fn save(self: *@This(), file_name: []const u8, range: Range) !void {
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();

    var bw = std.io.bufferedWriter(file.writer());
    const writer = bw.writer();

    for (range.start..range.end) |line_no| {
        try writer.writeAll(self.lines.items[line_no]);
        if (line_no + 1 != range.end) {
            try writer.writeAll("\n");
        }
    }

    try bw.flush();
}

// Retrieve a line by line number
pub fn get(self: @This(), index: usize) ?[]const u8 {
    if (index > self.lines.items.len) return null;
    return self.lines.items[index];
}

// Insert some text at a certain line number.
pub fn insert(self: *@This(), gpa: Allocator, index: usize, text: []const u8) !void {
    const line = try self.pool.add(text);
    try self.lines.insert(gpa, index, line);
}

// Remove a range of lines
pub fn removeRange(self: *@This(), range: Range) void {
    const line_count = self.lines.items.len;
    for (range.end..line_count, range.start..) |src, dest| {
        self.lines.items[dest] = self.lines.items[src];
    }
    self.lines.items.len -= range.len();
}

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

test "memory management and stuff" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        generalWorkload,
        .{},
    );
}

fn generalWorkload(gpa: Allocator) !void {
    var stream = std.io.fixedBufferStream(
        \\This is the original file content -
        \\testing allocation and stuff for the
        \\LineBuffer.
        \\
    );

    var self: @This() = try .initReader(gpa, stream.reader());
    defer self.deinit(gpa);

    const lines: []const []const u8 = &.{
        "this line is unique",
        "this line also unique",
        "this line is not unique",
        "this line is not unique",
        "this line is different",
        "this line is not unique",
        "this is the last line",
    };

    for (lines, 0..) |line, idx| {
        try self.insert(gpa, idx, line);
    }

    for (0..lines.len) |index| {
        try expectEqualSlices(u8, lines[index], self.get(index) orelse unreachable);
    }

    // include extra because we have more lines when we read the file
    try expectEqual(lines.len + 4, self.lines.items.len);

    for (0..lines.len + 4) |_| {
        self.removeRange(gpa, .init(0, 1));
    }

    try expectEqual(0, self.lines.items.len);
}

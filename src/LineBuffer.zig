const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Range = @import("Range.zig");

// indexing "lines" returns an index to "pool"
// "pool" stores the content of each "line"
// TODO: see if we need to have these strings reference-counted,
// which would be really easy to do as we could have it be the stored
// value for self.pool
lines: std.ArrayListUnmanaged(usize),
pool: std.StringArrayHashMapUnmanaged(void),

pub const empty: @This() = .{
    .lines = .empty,
    .pool = .empty,
};

pub fn initFile(gpa: Allocator, path: []const u8) !@This() {
    var self: @This() = .empty;
    errdefer self.deinit(gpa);

    // Create a new file if there is none, otherwise load current file
    const file = try std.fs.cwd().createFile(path, .{
        .read = true,
        .truncate = false,
    });
    defer file.close();

    var bytes: std.ArrayListUnmanaged(u8) = .empty;
    // In the case of errors with append or toOwnedSlice
    errdefer bytes.deinit(gpa);

    outer: while (true) {
        // Each loop we grab what's in bytes as an owned slice
        assert(bytes.items.len == 0);

        // TODO: benchmark that new thing I was doing with astgen
        // Read bytes until we encounter EOF or the delimiter
        const hit_eof = inner: while (true) {
            var byte: [1]u8 = undefined;
            const amt_read = try file.read(byte[0..]);
            if (amt_read == 0) break :inner true;
            if (byte[0] == '\n') break :inner false;
            try bytes.append(gpa, byte[0]);
        };

        // Add the string to the pool, reference it in "lines"
        const line = try bytes.toOwnedSlice(gpa);
        errdefer gpa.free(line);
        const gop = try self.pool.getOrPut(gpa, line);
        // Free lines that are never added to the pool
        if (gop.found_existing) gpa.free(line);
        // cleaning up self.pool in the case of self.lines.append failing
        // is already taken care of by errdeffering self.deinit(gpa).
        try self.lines.append(gpa, gop.index);

        if (hit_eof) break :outer;
    }

    return self;
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    for (self.pool.keys()) |line| {
        gpa.free(line);
    }
    self.pool.deinit(gpa);
    self.lines.deinit(gpa);
    self.* = undefined;
}

// Save a range of lines to a file.
pub fn save(self: *@This(), file_name: []const u8, range: Range) !void {
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();

    const lines_to_save = self.lines.items[range.start..range.end];
    for (lines_to_save, 0..) |line_index, offset| {
        try file.writeAll(self.pool.keys()[line_index]);
        if (offset + 1 != lines_to_save.len) {
            try file.writeAll("\n");
        }
    }
}

// Retrieve a line by line number
pub fn get(self: @This(), index: usize) ?[]const u8 {
    if (index > self.lines.items.len) return null;
    return self.pool.keys()[self.lines.items[index]];
}

// Insert some text at a certain line number.
pub fn insert(self: *@This(), gpa: Allocator, index: usize, text: []const u8) !void {
    const line = try gpa.dupe(u8, text);
    errdefer gpa.free(line);
    const gop = try self.pool.getOrPut(gpa, line);
    errdefer if (!gop.found_existing) {
        _ = self.pool.pop() orelse unreachable;
    };
    try self.lines.insert(gpa, index, gop.index);
    // Free lines that are never added to the pool
    // This is one good case for okdefer :(
    if (gop.found_existing) gpa.free(line);
}

// Remove a range of lines
pub fn removeRange(self: *@This(), range: Range) void {
    const source = self.lines.items[range.end..];
    const dest = self.lines.items[range.start..];
    for (dest[0..source.len], source) |*d, s| {
        d.* = s;
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
    try std.fs.cwd().deleteFile("temp_testing.txt");
}

fn generalWorkload(gpa: Allocator) !void {
    var self: @This() = try .initFile(gpa, "temp_testing.txt");
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

    // include one extra because we have an empty line when we read the file
    try expectEqual(lines.len + 1, self.lines.items.len);

    // the pool should be deduplicated (plus the empty file line)
    try expectEqual(5 + 1, self.pool.count());

    for (0..lines.len + 1) |_| {
        self.removeRange(.init(0, 1));
    }

    try expectEqual(0, self.lines.items.len);
}

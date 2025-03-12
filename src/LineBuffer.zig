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

pub fn init(gpa: Allocator, file_name: []const u8) !@This() {
    var self: @This() = .empty;
    errdefer self.deinit(gpa);

    // Create a new file if there is none, otherwise load current file
    const file = try std.fs.cwd().createFile(file_name, .{
        .read = true,
        .truncate = false,
    });
    defer file.close();

    var bytes: std.ArrayListUnmanaged(u8) = .empty;
    // After the loop, bytes should be empty
    defer assert(bytes.capacity == 0);
    // In the case of an error with toOwnedSlice
    errdefer bytes.deinit(gpa);

    while (true) {
        // Each loop we grab what's in bytes as an owned slice
        assert(bytes.items.len == 0);

        // TODO: benchmark that new thing I was doing with astgen
        // Read bytes until we encounter EOF or the delimiter
        const hit_eof = while (true) {
            var byte: [1]u8 = undefined;
            const amt_read = try file.read(byte[0..]);
            if (amt_read == 0) break true;
            if (byte[0] == '\n') break false;
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

        if (hit_eof) break;
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

// TODO: std.testing.checkAllAllocationFailures

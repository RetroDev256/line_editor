const std = @import("std");
const assert = std.debug.assert;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const Range = @import("Range.zig");

const Slot = struct {
    // [start, end)
    start: usize,
    end: usize,

    fn init(start: usize, end: usize) Slot {
        assert(end >= start);
        return .{ .start = start, .end = end };
    }
};

// "lines" index into "pool",
// "pool" is just concatenated strings
lines: ArrayListUnmanaged(Slot),
pool: ArrayListUnmanaged(u8),

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
    const reader = file.reader();

    var read_start: usize = 0;
    read_file: while (true) {
        // Trigger the ArrayList's superlinear growth for reading
        // The "start + 1" will never overflow, due to "start"
        // always being less than the superlinear growth factor
        try self.pool.ensureTotalCapacity(gpa, read_start + 1);

        // Read all that we can into the allocated memory
        self.pool.expandToCapacity();
        const dest_slice = self.pool.items[read_start..];
        const bytes_read = try reader.readAll(dest_slice);
        read_start += bytes_read;

        // Check if we have finished reading; trim to fit
        if (bytes_read != dest_slice.len) {
            self.pool.shrinkRetainingCapacity(read_start);
            break :read_file;
        }
    }

    // TODO: check that it correctly reads in an extra line for the newline
    var idx: usize = 0;
    while (idx < self.pool.items.len) {
        const start = idx;
        scan: while (idx < self.pool.items.len) {
            if (self.pool.items[idx] == '\n') {
                const line: Slot = .init(start, idx - start);
                try self.lines.append(gpa, line);
                idx += 1; // skip the '\n' for next elements
                break :scan;
            }
            idx += 1;
        }
    }

    return self;
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    self.lines.deinit(gpa);
    self.pool.deinit(gpa);
    self.* = undefined;
}

// Save a range of lines to a file.
pub fn save(self: *@This(), file_name: []const u8, range: Range) !void {
    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    for (self.lines.items[range.start..range.end], 0..) |line, idx| {
        try file.writeAll(self.pool.items[line.start..line.end]);
        if (idx + 1 != self.lines.items.len) {
            try file.writeAll("\n");
        }
    }
}

// Retrieve a line by line number
pub fn get(self: @This(), index: usize) ?[]const u8 {
    if (index >= self.lines.items.len) return null;
    const lookup = self.lines.items[index];
    return self.pool.items[lookup.start..lookup.end];
}

// Insert a new line at a certain line number.
pub fn insert(self: *@This(), gpa: Allocator, index: usize, line: []const u8) !void {
    const old_len = self.pool.items.len;
    try self.pool.appendSlice(gpa, line);
    errdefer self.lines.items.len = old_len;
    const interned: Slot = .init(old_len, old_len + line.len);
    try self.lines.insert(gpa, index, interned);
}

// Insert multiple lines at a certain line number
pub fn insertMany(
    self: *@This(),
    gpa: Allocator,
    index: usize,
    count: usize,
    line: []const u8,
) !void {
    const old_len = self.pool.items.len;
    try self.pool.appendSlice(gpa, line);
    errdefer self.lines.items.len = old_len;
    const dest = try self.lines.addManyAt(gpa, index, count);
    @memset(dest, .init(old_len, old_len + line.len));
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

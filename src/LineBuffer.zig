const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const Range = @import("Range.zig");

// "lines" index into "pool",
// "pool" is just concatenated strings
lines: ArrayListUnmanaged(Range),
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
                const line: Range = .init(start, idx - start);
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

// Insert a new line at a certain line number.
pub fn insert(self: *@This(), gpa: Allocator, index: usize, line: []const u8) !void {
    const old_length = self.pool.items.len;
    try self.pool.appendSlice(gpa, line);
    errdefer self.pool.items.len = old_length;
    try self.lines.insert(gpa, index, .init(old_length, line.len));
}

// Change the number of lines; either removing or appending blanks.
pub fn resize(self: *@This(), gpa: Allocator, len: usize) !void {
    if (len > self.lines) {
        const added = len - self.lines.items.len;
        try self.lines.appendNTimes(gpa, .init(0, 0), added);
    } else {
        self.removeRange(.init(self.lines.items.len, len));
    }
}

// Remove a range of lines
pub fn removeRange(self: *@This(), range: Range) void {
    for (range.start..range.end) |idx| {
        // While not guarunteed, the underlying data is likely in order.
        const rev_idx = self.lines.items.len - (idx + 1);
        self.remove(rev_idx);
    }
}

// Remove a line
pub fn remove(self: *@This(), index: usize) void {
    // 1. See if we can swap the data in the pool with something closer
    // to the pool end - if we can, it becomes the new empty index.
    var slot = self.lines.items[index];
    for (index..self.lines.items.len) |idx| {
        const rev_idx = self.lines.items.len - (idx + 1);
        const candidate = self.lines.items[rev_idx];
        if (candidate.len() == slot.len()) {
            @memcpy(
                self.pool.items[slot.start..slot.end],
                self.pool.items[candidate.start..candidate.end],
            );
            slot = candidate;
            break;
        }
    }
    // 2. Take the empty index, and move all the memory to fill the gap.
    // TODO: replace with @memmove when it is added to zig
    const shift = slot.len();
    const new_len = self.pool.items.len - shift;
    const dest = self.pool.items[slot.start..new_len];
    const source = self.pool.items[slot.end..];
    for (dest, source) |*d, s| d.* = s;
    // Line pointers are invalidated here, so update them.
    for (self.lines.items) |*line| {
        if (line.start >= slot.end) {
            line.start -= shift;
            line.end -= shift;
        }
    }
    // 3. Change the size of the pool
    self.pool.items.len = new_len;
}

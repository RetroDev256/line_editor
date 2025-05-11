//! Reference counted, owned, and interned strings

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const LineHeader = struct { ref: usize, len: usize };
const Line = [*]align(@alignOf(LineHeader)) u8;

pool: std.StringHashMapUnmanaged(Line),

// Construct new empty string intern pool
pub const empty: @This() = .{ .pool = .empty };

// Free all memory allocated by the intern pool. Additionally, ensure
// all memory allocated by the pool in it's lifetime is also freed.
pub fn deinit(self: *@This(), gpa: Allocator) void {
    var iter = self.pool.valueIterator();
    while (iter.next()) |line| {
        const header: *const LineHeader = @ptrCast(line.*);
        assert(header.ref != 0);

        const len = @sizeOf(LineHeader) + header.len;
        gpa.free(line.*[0..len]);
    }

    self.pool.deinit(gpa);
    self.* = undefined;
}

// Add a string to the intern pool, returning a stable pointer to the string.
// The pointer will last as far as the string is not removed with `remove()`.
pub fn add(self: *@This(), gpa: Allocator, str: []const u8) ![]const u8 {
    if (self.pool.get(str)) |line| {
        // Get the header & data
        const header: *LineHeader = @ptrCast(line);
        assert(header.ref != 0);

        // Update reference counter
        header.ref += 1;

        // Return stable pointer
        assert(header.len == str.len);
        return line[@sizeOf(LineHeader)..][0..str.len];
    }

    // Allocate memory for the Line
    const len = @sizeOf(LineHeader) + str.len;
    const bytes = try gpa.alignedAlloc(u8, .of(LineHeader), len);
    errdefer gpa.free(bytes);

    // Write the header & string
    const header: *LineHeader = @ptrCast(bytes.ptr);
    header.* = .{ .ref = 1, .len = str.len };
    const line_string = bytes[@sizeOf(LineHeader)..];
    @memcpy(line_string, str);

    // Add to the pool & return the stable pointer to the string.
    // !!! IMPORTANT !!! - The pool does not store it's own keys,
    // so we must give the pool the stable pointer to the string.
    try self.pool.putNoClobber(gpa, line_string, bytes.ptr);
    return line_string;
}

// Removes a string from the intern pool. It decrements a reference
// counter to ensure that duplicate strings will still be allocated.
// This function asserts that the string exists in the intern pool.
pub fn remove(self: *@This(), gpa: Allocator, str: []const u8) void {
    const line = self.pool.get(str) orelse unreachable;

    // Get the header & data
    const header: *LineHeader = @ptrCast(line);
    assert(header.ref != 0);

    // Update reference counter
    header.ref -= 1;

    // Free the string if there are no more references
    if (header.ref == 0) {
        assert(header.len == str.len);
        const len = @sizeOf(LineHeader) + header.len;
        assert(self.pool.remove(str));
        gpa.free(line[0..len]);
    }
}

test "Intern Pool" {
    const gpa = std.testing.allocator;

    var intern_pool: @This() = .empty;
    defer intern_pool.deinit(gpa);

    // Inserting elements
    const a = try intern_pool.add(gpa, "x");
    const b = try intern_pool.add(gpa, "y");
    const c = try intern_pool.add(gpa, "z");
    const d = try intern_pool.add(gpa, "z");
    const e = try intern_pool.add(gpa, "y");

    try std.testing.expectEqualSlices(u8, "x", a);
    try std.testing.expectEqualSlices(u8, "y", b);
    try std.testing.expectEqualSlices(u8, "z", c);
    try std.testing.expectEqualSlices(u8, "z", d);
    try std.testing.expectEqualSlices(u8, "y", e);

    try std.testing.expectEqual(b.ptr, e.ptr);
    try std.testing.expectEqual(c.ptr, d.ptr);

    try std.testing.expectEqual(intern_pool.pool.size, 3);

    // Removing elements
    intern_pool.remove(gpa, "y");
    intern_pool.remove(gpa, "z");
    try std.testing.expectEqual(intern_pool.pool.size, 3);

    intern_pool.remove(gpa, "y");
    try std.testing.expectEqual(intern_pool.pool.size, 2);

    intern_pool.remove(gpa, "z");
    try std.testing.expectEqual(intern_pool.pool.size, 1);

    intern_pool.remove(gpa, "x");
    try std.testing.expectEqual(intern_pool.pool.size, 0);
}

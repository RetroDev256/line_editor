//! Reference counted, owned, and interned strings

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

map: std.StringHashMapUnmanaged(usize),

// Construct new empty string intern pool
pub const empty: @This() = .{ .map = .empty };

// Free memory allocated by the intern pool.
// Ensure all strings have already been freed.
pub fn deinit(self: *@This(), gpa: Allocator) void {
    assert(self.map.size == 0);
    self.map.deinit(gpa);
    self.* = undefined;
}

// Add a string to the intern pool, returning a stable pointer to the string.
// The pointer will last as far as the string is not removed with `remove()`.
pub fn add(self: *@This(), gpa: Allocator, str: []const u8) ![]const u8 {
    if (self.map.getEntry(str)) |entry| {
        // Update & return pre-existing
        entry.value_ptr.* += 1;
        return entry.key_ptr.*;
    }

    // Allocate memory for the string
    const entry_str = try gpa.dupe(u8, str);
    errdefer gpa.free(entry_str);

    // Add the entry to our map, use the owned string
    try self.map.putNoClobber(gpa, entry_str, 1);

    // Return the stable pointer
    return entry_str;
}

// Reduces the reference count of a string in the intern pool, and
// frees the string if it is unreferenced. Asserts that it exists.
pub fn remove(self: *@This(), gpa: Allocator, str: []const u8) void {
    const entry = self.map.getEntry(str) orelse unreachable;

    // Update reference counter
    entry.value_ptr.* -= 1;

    // Remove unreferenced strings
    if (entry.value_ptr.* == 0) {
        gpa.free(entry.key_ptr.*);
        self.map.removeByPtr(entry.key_ptr);
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

    try std.testing.expectEqual(intern_pool.map.size, 3);

    // Removing elements
    intern_pool.remove(gpa, "y");
    intern_pool.remove(gpa, "z");
    try std.testing.expectEqual(intern_pool.map.size, 3);

    intern_pool.remove(gpa, "y");
    try std.testing.expectEqual(intern_pool.map.size, 2);

    intern_pool.remove(gpa, "z");
    try std.testing.expectEqual(intern_pool.map.size, 1);

    intern_pool.remove(gpa, "x");
    try std.testing.expectEqual(intern_pool.map.size, 0);
}

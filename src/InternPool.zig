//! Owned & interned strings

const std = @import("std");
const Allocator = std.mem.Allocator;

arena: std.heap.ArenaAllocator,
map: std.StringHashMapUnmanaged(void),

// Construct new empty string intern pool
pub fn init(gpa: Allocator) @This() {
    return .{ .arena = .init(gpa), .map = .empty };
}

// Free all memory allocated by the intern pool.
pub fn deinit(self: *@This()) void {
    defer self.* = undefined;
    self.map.deinit(self.arena.child_allocator);
    self.arena.deinit();
}

// Add a string to the intern pool, returning a stable pointer to the string.
// The pointer will last as far as the string is not removed with `remove()`.
pub fn add(self: *@This(), str: []const u8) ![]const u8 {
    // Return pre-existing
    if (self.map.getKey(str)) |entry| return entry;

    // Allocate memory for our string
    const arena = self.arena.allocator();
    const entry = try arena.dupe(u8, str);
    errdefer arena.free(entry);

    // Add the entry to our map, use the owned string
    try self.map.putNoClobber(self.arena.child_allocator, entry, void{});

    // Return the stable pointer
    return entry;
}

test "Intern Pool" {
    const gpa = std.testing.allocator;
    var pool: @This() = .empty;
    defer pool.deinit(gpa);

    // Inserting elements
    const a = try pool.add(gpa, "x");
    const b = try pool.add(gpa, "y");
    const c = try pool.add(gpa, "z");
    const d = try pool.add(gpa, "z");
    const e = try pool.add(gpa, "y");

    try std.testing.expectEqualSlices(u8, "x", a);
    try std.testing.expectEqualSlices(u8, "y", b);
    try std.testing.expectEqualSlices(u8, "z", c);
    try std.testing.expectEqualSlices(u8, "z", d);
    try std.testing.expectEqualSlices(u8, "y", e);

    try std.testing.expectEqual(b.ptr, e.ptr);
    try std.testing.expectEqual(c.ptr, d.ptr);

    try std.testing.expectEqual(pool.map.size, 3);
    try std.testing.expectEqualSlices(u8, "xyz", pool.bytes.items);
}

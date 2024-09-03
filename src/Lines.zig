//! This type represents an immutable segment of LineBuffer
//! It is used to track edits and fetch text ranges

const std = @import("std");
const Allocator = std.mem.Allocator;
const Range = @import("Range.zig");

const Self = @This();

text: []const []const u8,
start: usize,

pub fn init(text: []const []const u8, start: usize) Self {
    return .{ .text = text, .start = start };
}

pub fn range(self: Self) Range {
    return .init(self.start, self.text.len);
}

pub fn dupe(self: Self, alloc: Allocator) !Self {
    // clone the list itself
    const text = try alloc.alloc([]const u8, self.text.len);
    errdefer alloc.free(text);
    // clone each line - in case of error, clean up allocated
    for (text, self.text, 0..) |*new, old, i| {
        new.* = try alloc.dupe(u8, old);
        errdefer for (0..i) |line| {
            alloc.free(text[line]);
        };
    }
    return .{ .text = text, .start = self.start };
}

// only use on Lines allocated by `dupe`
pub fn deinit(self: Self, alloc: Allocator) void {
    for (self.text) |line| {
        alloc.free(line);
    }
    alloc.free(self.text);
}

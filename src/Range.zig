const Self = @This();

const std = @import("std");
const BoundedRange = @import("BoundedRange.zig");
const Index = @import("index.zig").Index;

/// 'start' is inclusive, 'end' is also inclusive
start: ?Index,
end: ?Index,

pub fn fromIndex(index: Index, count: usize) Self {
    return .{ .start = index, .end = index.add(count) };
}
pub fn toBounded(self: Self, last_index: usize) !BoundedRange {
    const complete = BoundedRange.complete(last_index + 1);
    return .{
        .start = if (self.start) |s| try s.index(last_index) else complete.start,
        .end = if (self.end) |e| try e.index(last_index) + 1 else complete.end,
    };
}
pub fn clamp(self: Self, length: usize) !Self {
    return Self{
        .start = if (self.start) |start| try start.clamp(length) else null,
        .end = if (self.end) |end| try end.clamp(length) else null,
    };
}

test {
    _ = &std.testing.refAllDecls(@This());
}

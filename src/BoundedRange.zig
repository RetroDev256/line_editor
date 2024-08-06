const Self = @This();

const std = @import("std");

start: usize,
end: usize,

pub fn complete(length: usize) Self {
    return .{ .start = 0, .end = length };
}

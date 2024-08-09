//! more concrete representation of a selection - resolved to a range
const Self = @This();

/// inclusive
start: usize,
/// exclusive
end: usize,

// length of the range
pub fn length(self: Self) usize {
    return self.end - self.start;
}

// a range of length one, from an index
pub fn single(index: usize) Self {
    return .{ .start = index, .end = index + 1 };
}

// complete range spanning 0 to length
pub fn complete(bound: usize) Self {
    return .{ .start = 0, .end = bound };
}

// force the range within an exclusive upper bound
pub fn clamp(self: Self, bound: usize) Self {
    return .{
        .start = @min(self.start, bound),
        .end = @min(self.end, bound),
    };
}

/// used for both line numbers and counts
pub const Number = union(enum) {
    specific: usize, // 123...
    infinity, // $

    pub fn toIndex(self: Number, last_index: usize) usize {
        return switch (self) {
            .specific => |line_number| line_number,
            .infinity => last_index,
        };
    }

    // used for converting between 0 indexed and 1 indexed array indexing
    pub fn dec(self: Number) !Number {
        return switch (self) {
            .specific => |line_number| blk: {
                if (line_number == 0) {
                    return error.NumberUnderflow;
                } else break :blk .{ .specific = line_number - 1 };
            },
            .infinity => .infinity,
        };
    }
};

pub const BoundedRange = struct {
    start: usize,
    end: usize,

    pub fn complete(length: usize) @This() {
        return .{ .start = 0, .end = length };
    }
    pub fn fromIndex(index: usize, count: usize) @This() {
        return .{ .start = index, .end = index + count };
    }
    pub fn clamp(self: @This(), length: usize) @This() {
        return .{
            .start = @min(self.start, length),
            .end = @min(self.end, length),
        };
    }
    pub fn check(self: @This(), length: usize) !void {
        if (self.start >= length or self.end > length) return error.RangeOutOfBounds;
        if (self.start > self.end) return error.InvalidRange;
    }
};

/// 'start' is inclusive, 'end' is also inclusive
pub const Range = struct {
    start: ?Number,
    end: ?Number,

    pub fn toBounded(self: Range, last_index: usize) BoundedRange {
        const complete = BoundedRange.complete(last_index + 1);
        return .{
            .start = if (self.start) |s| s.toIndex(last_index) else complete.start,
            .end = if (self.end) |s| s.toIndex(last_index) + 1 else complete.end,
        };
    }
};

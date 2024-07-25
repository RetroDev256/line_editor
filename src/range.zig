/// used for both line numbers and counts
pub const Number = union(enum) {
    specific: usize, // 123...
    infinity, // $

    pub fn toIndex(self: Number, end_of_file: usize) usize {
        return switch (self) {
            .specific => |line_number| line_number,
            .infinity => end_of_file,
        };
    }

    // used for converting between 0 based and 1 based array indexing
    pub fn dec(self: Number) Number {
        return switch (self) {
            .specific => |line_number| .{ .specific = line_number -| 1 },
            .infinity => .infinity,
        };
    }
};

pub const BoundedRange = struct {
    start: usize,
    end: usize,

    pub fn fromIndex(index: usize) @This() {
        return .{ .start = index, .end = index + 1 };
    }

    pub fn clamp(self: @This(), max_index: usize) @This() {
        return .{
            .start = @min(self.start, max_index + 1),
            .end = @min(self.end, max_index + 1),
        };
    }

    pub fn check(self: @This(), max: usize) !void {
        if (self.start > max or self.end > max + 1) return error.RangeOutOfBounds;
        if (self.start > self.end) return error.InvalidRange;
    }
};

/// 'start' is inclusive, 'end' is not inclusive
pub const Range = struct {
    start: ?Number,
    end: ?Number,

    pub fn toIndexes(self: Range, extremities: BoundedRange, end_of_file: usize) BoundedRange {
        return .{
            .start = if (self.start) |s| s.toIndex(end_of_file) else extremities.start,
            .end = if (self.end) |s| s.toIndex(end_of_file) else extremities.end + 1,
        };
    }
};

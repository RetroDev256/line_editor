/// used for both line numbers and counts
pub const Number = union(enum) {
    specific: usize, // 123...
    infinity, // $

    pub fn toIndex(self: Number, length: usize) ?usize {
        return switch (self) {
            .specific => |line_number| line_number,
            .infinity => if (length == 0) null else length - 1,
        };
    }

    // used for converting between 0 based and 1 based array indexing
    pub fn dec(self: Number) Number {
        return switch (self) {
            // we only use this on already incremented numbers, in the
            // exclusive range domain, so this won't overflow
            .specific => |line_number| .{ .specific = line_number - 1 },
            .infinity => .infinity,
        };
    }
    // used for converting between exclusive and inclusive ranges
    pub fn inc(self: Number) Number {
        return switch (self) {
            .specific => |line_number| .{ .specific = line_number + 1 },
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
    pub fn fromIndex(index: usize, distance: usize) @This() {
        return .{ .start = index, .end = index + distance };
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

/// 'start' is inclusive, 'end' is not inclusive
pub const Range = struct {
    start: ?Number,
    end: ?Number,

    pub fn toBounded(self: Range, length: usize) BoundedRange {
        if (length == 0) {
            return BoundedRange.complete(0);
        } else {
            const complete = BoundedRange.complete(length);
            // unwrapping the optionals is guarunteed safe
            // because we checked that the length was not 0
            return .{
                .start = if (self.start) |s| blk: {
                    break :blk s.toIndex(length - 1).?;
                } else complete.start,
                .end = if (self.end) |s| blk: {
                    break :blk s.toIndex(length).?;
                } else complete.end,
            };
        }
    }
};

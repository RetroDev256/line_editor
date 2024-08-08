/// This type distinguishes different line indexing modes of different commands
/// Some commands may behave differently based on whether a range, index, or none
/// is provided.
pub const Selection = union(enum) {
    unspecified,
    line: Index,
    range: Range,
};

/// more concrete representation of a selection having been resolved to a range
pub const BoundedRange = struct {
    /// inclusive
    start: usize,
    /// exclusive
    end: usize,

    // a complete range covering
    pub fn complete(length: usize) BoundedRange {
        return .{ .start = 0, .end = length };
    }
};

/// flexible representation of a range, where the user may have left indicies vague
pub const Range = struct {
    /// inclusive
    start: ?Index,
    /// inclusive
    end: ?Index,

    pub fn fromIndex(index: Index, count: usize) Range {
        return .{ .start = index, .end = index.add(count) };
    }
    pub fn toBounded(self: Range, last_index: usize) !BoundedRange {
        const complete: BoundedRange = .{ .start = 0, .end = last_index + 1 };
        return .{
            .start = if (self.start) |s| try s.index(last_index) else complete.start,
            .end = if (self.end) |e| try e.index(last_index) + 1 else complete.end,
        };
    }
    pub fn clamp(self: Range, length: usize) !Range {
        return Range{
            .start = if (self.start) |start| try start.clamp(length) else null,
            .end = if (self.end) |end| try end.clamp(length) else null,
        };
    }
};

pub const Index = union(enum) {
    specific: usize, // 123...
    infinity, // $

    pub fn index(self: Index, last_index: usize) !usize {
        return switch (self) {
            .specific => |line| blk: {
                if (line <= last_index) {
                    break :blk line;
                } else return error.IndexOutOfBounds;
            },
            .infinity => last_index,
        };
    }

    pub fn add(self: Index, count: usize) Index {
        return switch (self) {
            .specific => |line| .{ .specific = line + count },
            .infinity => .infinity,
        };
    }

    pub fn clamp(self: Index, length: usize) !Index {
        if (length == 0) return error.ClampedIntoNothing;
        return switch (self) {
            .specific => |line| .{ .specific = @min(line, length - 1) },
            .infinity => .infinity,
        };
    }
};

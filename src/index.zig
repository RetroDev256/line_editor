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

    // used for converting between 0 indexed and 1 indexed array indexing
    pub fn decrement(self: Index) !Index {
        return switch (self) {
            .specific => |line| blk: {
                if (line == 0) {
                    return error.IndexOutOfBounds;
                } else break :blk .{ .specific = line - 1 };
            },
            .infinity => .infinity,
        };
    }
};

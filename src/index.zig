const std = @import("std");

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

test {
    _ = &std.testing.refAllDecls(@This());
}

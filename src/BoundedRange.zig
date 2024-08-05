const Self = @This();

start: usize,
end: usize,

pub fn complete(length: usize) Self {
    return .{ .start = 0, .end = length };
}

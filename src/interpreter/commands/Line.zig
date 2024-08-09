const Self = @This();

const Selection = @import("../selection.zig").Selection;

// Command data

line: usize,

// Parser implementation

pub fn parse(sel: Selection) !Self {
    return switch (sel) {
        .line => |line| .{ .line = line },
        else => error.Malformed,
    };
}

// Runner implementation

pub fn run(self: Self, current_line: *usize) !void {
    current_line.* = self.line;
}

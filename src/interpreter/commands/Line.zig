const Self = @This();

const Selection = @import("../selection.zig").Selection;
const Index = @import("../selection.zig").Index;

// Command data

line: Index,

// Parser implementation

pub fn parse(sel: Selection) !Self {
    switch (sel) {
        .unspecified => return error.Malformed,
        .line => |line| return .{ .line = line },
        .range => return error.Malformed,
    }
}

// Runner implementation

pub fn run(self: Self, current_line: *Index) !void {
    current_line.* = self.line;
}

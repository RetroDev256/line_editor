const Self = @This();

const LineBuffer = @import("../LineBuffer.zig");
const Selection = @import("../selection.zig").Selection;
const Range = @import("../Range.zig");

// Command data

sel: Selection,

// Parser implementation

pub fn parse(sel: Selection) !Self {
    return .{ .sel = sel };
}

// Runner implementation

pub fn run(self: Self, buffer: *LineBuffer, current_line: usize) !void {
    const source = self.sel.resolve(Range.single(current_line));
    try buffer.delete(source);
}

const Self = @This();

const Parser = @import("../Parser.zig");
const LineBuffer = @import("../LineBuffer.zig");
const Selection = @import("../selection.zig").Selection;
const Range = @import("../Range.zig");

// Command data

sel: Selection,
dest: usize,

// Parser implementation

pub fn parse(sel: Selection, token_data: []const u8, last_index: usize) !Self {
    const dest = Parser.parseIndex(token_data, last_index) catch return error.Malformed;
    return .{ .sel = sel, .dest = dest };
}

// Runner implementation

pub fn run(self: Self, current_line: usize, buffer: *LineBuffer) !void {
    const source = self.sel.resolve(Range.single(current_line));
    try buffer.move(source, self.dest);
}

const Self = @This();

const Parser = @import("../Parser.zig");
const LineBuffer = @import("../LineBuffer.zig");
const Selection = @import("../selection.zig").Selection;
const Index = @import("../selection.zig").Index;

// Command data

sel: Selection,
dest: Index,

// Parser implementation

pub fn parse(sel: Selection, token_data: []const u8) !Self {
    const dest = Parser.parseIndex(token_data) catch return error.Malformed;
    return .{ .sel = sel, .dest = dest };
}

// Runner implementation

pub fn run(self: Self, current_line: Index, buffer: *LineBuffer) !void {
    switch (self.sel) {
        .unspecified => try buffer.copyLine(current_line, self.dest),
        .line => |line| try buffer.copyLine(line, self.dest),
        .range => |range| try buffer.copyRange(range, self.dest),
    }
}

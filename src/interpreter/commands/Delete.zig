const Self = @This();

const LineBuffer = @import("../LineBuffer.zig");
const Selection = @import("../selection.zig").Selection;
const Index = @import("../selection.zig").Index;

// Command data

sel: Selection,

// Parser implementation

pub fn parse(sel: Selection) !Self {
    return .{ .sel = sel };
}

// Runner implementation

pub fn run(self: Self, buffer: *LineBuffer, current_line: Index) !void {
    switch (self.sel) {
        .unspecified => try buffer.deleteLine(current_line),
        .line => |line| try buffer.deleteLine(line),
        .range => |range| try buffer.deleteRange(range),
    }
}

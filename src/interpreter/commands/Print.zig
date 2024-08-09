const Self = @This();

const std = @import("std");
const LineBuffer = @import("../LineBuffer.zig");
const io = @import("../io.zig");
const Selection = @import("../selection.zig").Selection;
const Range = @import("../Range.zig");

// Command data

sel: Selection,

// Parser implementation

pub fn parse(sel: Selection) !Self {
    return .{ .sel = sel };
}

// Runner implementation

pub fn run(self: Self, buffer: LineBuffer, current_line: usize, writer: anytype) !void {
    const range = switch (self.sel) {
        .unspecified => Range{ .start = current_line, .end = current_line + 16 },
        .line => |line| Range.single(line),
        .range => |range| range,
    };
    try runRange(buffer, writer, range);
}

// Internal functions

pub fn runRange(buffer: LineBuffer, writer: anytype, range: Range) !void {
    const clamped = range.clamp(buffer.length());
    if (buffer.get(clamped)) |lines| {
        for (lines, clamped.start..) |text, line| {
            try io.printLineNumber(writer, line, buffer.length());
            try io.printToCmdOut(writer, "{s}\n", .{text});
        }
    }
}

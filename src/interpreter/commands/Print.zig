const Self = @This();

const std = @import("std");
const AnyWriter = std.io.AnyWriter;
const LineBuffer = @import("../LineBuffer.zig");
const io = @import("../io.zig");
const Selection = @import("../selection.zig").Selection;
const Index = @import("../selection.zig").Index;
const Range = @import("../selection.zig").Range;

// Command data

sel: Selection,

// Parser implementation

pub fn parse(sel: Selection) !Self {
    return .{ .sel = sel };
}

// Runner implementation

pub fn run(self: Self, buffer: LineBuffer, current_line: Index, writer: ?AnyWriter) !void {
    switch (self.sel) {
        .unspecified => {
            // print 16 lines if a selection is not specified
            const range = Range.fromIndex(current_line, 16);
            const clamped = try range.clamp(buffer.length());
            try runRange(buffer, writer, clamped);
        },
        .line => |line| try runLine(buffer, writer, line),
        .range => |range| try runRange(buffer, writer, range),
    }
}

// Internal functions

pub fn runLine(buffer: LineBuffer, writer: ?AnyWriter, line_number: Index) !void {
    const line = try buffer.getLine(line_number);
    try io.printLineNumber(writer, line_number);
    try io.printToCmdOut(writer, "{s}\n", .{line});
}

pub fn runRange(buffer: LineBuffer, writer: ?AnyWriter, range: Range) !void {
    const lines = try range.toBounded(try buffer.lastIndex());
    for (0..lines.end - lines.start) |offset| {
        const line_number = .{ .specific = lines.start + offset };
        try runLine(buffer, writer, line_number);
    }
}

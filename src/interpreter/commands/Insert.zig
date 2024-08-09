const Self = @This();

const LineBuffer = @import("../LineBuffer.zig");
const Selection = @import("../selection.zig").Selection;
const Mode = @import("../Runner.zig").Mode;

// Command data

sel: Selection,
insert_mode: bool,
text: []const u8,

// Parser implementation

pub fn parse(sel: Selection, token_data: []const u8) !Self {
    if (token_data.len == 0) { // [SELECTION?].
        return .{
            .sel = sel,
            .insert_mode = true,
            .text = &.{},
        };
    } else { // [SELECTION?].STRING
        return .{
            .sel = sel,
            .insert_mode = false,
            .text = token_data,
        };
    }
}

// Runner implementation

pub fn run(self: Self, buffer: *LineBuffer, current_mode: *Mode, current_line: *usize) !void {
    switch (self.sel) {
        .unspecified => {},
        .line => |line| current_line.* = line,
        .range => return error.Malformed,
    }
    if (self.insert_mode) {
        current_mode.* = .insert;
    } else {
        try buffer.insert(current_line.*, &.{self.text});
        current_line.* += 1;
    }
}

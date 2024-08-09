const Self = @This();

const LineBuffer = @import("../LineBuffer.zig");
const Selection = @import("../selection.zig").Selection;
const Range = @import("../Range.zig");

// Command data

/// the range of lines to save to a file; in the case of unspecified, the whole file is saved
sel: Selection,
/// signals to the runner that the program should also exit
quit: bool,
/// null means the run function will attempt to save to the current file name
file_out: ?[]const u8,

// Parser implementation

// `w file.txt` `w` `wq` `wq file.txt`
pub fn parse(sel: Selection, token_data: []const u8) !Self {
    return switch (token_data.len) {
        0 => .{ // w
            .sel = sel,
            .quit = false,
            .file_out = null,
        },
        1 => switch (token_data[0]) {
            'q' => .{ // wq
                .sel = sel,
                .quit = true,
                .file_out = null,
            },
            else => error.Malformed, // wX (garbage)
        },
        else => switch (token_data[0]) {
            'q' => switch (token_data[1]) {
                ' ' => if (token_data.len > 2) blk: { // wq FILE
                    break :blk .{
                        .sel = sel,
                        .quit = true,
                        .file_out = token_data[2..],
                    };
                } else error.Malformed, // "wq " (garbage)
                else => error.Malformed, // wqX... (garbage)
            },
            ' ' => .{ // w FILE
                .sel = sel,
                .quit = false,
                .file_out = token_data[1..],
            },
            else => error.Malformed, // wX... (garbage)
        },
    };
}

// Runner implementation

pub fn run(self: Self, buffer: *LineBuffer, file: *?[]const u8, exit: *bool) !void {
    if (self.file_out) |file_out| {
        file.* = file_out;
    }
    const file_name = file.* orelse return error.NoOutputSpecified;
    switch (self.sel) {
        .unspecified => try buffer.save(file_name, Range.complete(buffer.length())),
        .line => |line| try buffer.save(file_name, Range.single(line)),
        .range => |range| try buffer.save(file_name, range),
    }
    exit.* = exit.* or self.quit;
}

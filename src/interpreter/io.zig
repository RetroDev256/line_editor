const std = @import("std");
const AnyWriter = std.io.AnyWriter;
const Index = @import("selection.zig").Index;

pub fn printToCmdOut(writer: ?AnyWriter, comptime format: []const u8, args: anytype) !void {
    if (writer) |output| {
        try output.print(format, args);
    }
}

pub fn printLineNumber(writer: ?AnyWriter, line: Index) !void {
    switch (line) {
        .specific => |index| try printToCmdOut(writer, "{: >8} ", .{index + 1}),
        .infinity => try printToCmdOut(writer, " " ** 7 ++ "$ ", .{}),
    }
}

pub fn printCommandPrompt(writer: ?AnyWriter) !void {
    if (writer) |output| {
        try output.writeAll("+ ");
    }
}

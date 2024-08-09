const std = @import("std");

pub fn printToCmdOut(writer: anytype, comptime format: []const u8, args: anytype) !void {
    if (writer) |output| {
        try output.print(format, args);
    }
}

pub fn printCommandPrompt(writer: anytype) !void {
    if (writer) |output| {
        try output.writeAll("+ ");
    }
}

pub fn printLineNumber(writer: anytype, line: usize, length: usize) !void {
    if (line + 1 == length) {
        try printToCmdOut(writer, " " ** 7 ++ "$ ", .{});
    } else try printToCmdOut(writer, "{: >8} ", .{line + 1});
}

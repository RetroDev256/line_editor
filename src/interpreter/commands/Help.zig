const Self = @This();

const std = @import("std");
const AnyWriter = std.io.AnyWriter;
const io = @import("../io.zig");
const Selection = @import("../selection.zig").Selection;

// Parser implementation

pub fn parse(selection: Selection) !Self {
    if (selection != .unspecified) return error.Malformed;
    return .{};
}

// Runner implementation

pub fn run(_: Self, writer: ?AnyWriter) !void {
    try io.printToCmdOut(writer,
        \\- - - Definitions - - -
        \\  MODE                  COMMAND or INSERT (swap using .)
        \\  LINE                  the current line number
        \\  FILE                  the current output file name
        \\  INDEX                 can be line number, or $ (last line)
        \\  RANGE:                (can be either of the following formats -)
        \\  [X]                   line number X (INDEX)
        \\  [A?],[B?]             lines [INDEX A (oror 0), INDEX B (oror $)]
        \\- - - INSERT Mode - - -
        \\  .                     MODE<-COMMAND
        \\  .[STRING]             inserts STRING at LINE, LINE<-LINE + 1
        \\- - - COMMAND Mode - - -
        \\  [INDEX?]              LINE <- INDEX (or LINE)
        \\  [INDEX?].             LINE <- INDEX (or LINE), MODE<-INSERT
        \\  [INDEX?].[NEW]        LINE <- INDEX (or LINE), inserts NEW at LINE, LINE += 1
        \\  [RANGE?]p             prints RANGE (or LINE)
        \\  [RANGE?]d             deletes RANGE (or LINE)
        \\  [RANGE?]s/[OLD]/[NEW] replaces all OLD to NEW in RANGE (or LINE)
        \\  [RANGE?]m[INDEX]      moves RANGE (or LINE) to INDEX
        \\  [RANGE?]c[INDEX]      copies RANGE (or LINE) to INDEX
        \\  [RANGE?]w [NAME?]     FILE <- NAME (or FILE), saves RANGE (or all) to FILE
        \\  [RANGE?]wq [NAME?]    same as w varient, but also quits the program
        \\  q                     exits
        \\  h                     displays this text
        \\
    , .{});
}

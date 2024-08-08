const Self = @This();

const std = @import("std");
const Selection = @import("../selection.zig").Selection;

// Parser implementation

pub fn parse(selection: Selection) !Self {
    if (selection != .unspecified) return error.Malformed;
    return .{};
}

// Runner implementation

pub fn run(_: Self, exit: *bool) !void {
    exit.* = true;
}

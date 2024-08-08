const Self = @This();

// TODO: add minimal regex again
// so we can prefix and postfix lines (begin and end)
// so we can match some (or many) characters
// nothing too complicated

const std = @import("std");
const Allocator = std.mem.Allocator;
const LineBuffer = @import("../LineBuffer.zig");
const Selection = @import("../selection.zig").Selection;
const Index = @import("../selection.zig").Index;

// Command data

/// target range to be matched & replaced
sel: Selection,
/// regex (dumb for now) - not allowed to contain /
before: []const u8,
/// any string tbh
after: []const u8,

// Parser implementation

pub fn parse(sel: Selection, token_data: []const u8) !Self {
    const first = find(token_data, 1, '/') catch return error.Malformed;
    const second = find(token_data, 2, '/') catch return error.Malformed;
    return .{
        .sel = sel,
        .before = token_data[first + 1 .. second],
        .after = token_data[second + 1 ..],
    };
}

// Runner implementation

pub fn run(self: Self, alloc: Allocator, buffer: *LineBuffer, current_line: Index) !void {
    switch (self.sel) {
        .unspecified => try self.runLine(alloc, buffer, current_line),
        .line => |line_number| try self.runLine(alloc, buffer, line_number),
        .range => try self.runRange(alloc, buffer),
    }
}

// Internal functions

fn find(source: []const u8, number: usize, needle: u8) !usize {
    if (number == 0) return error.InvalidNumber;
    var count: usize = 0;
    for (source, 0..) |byte, index| {
        if (byte == needle) {
            count += 1;
            if (count == number) {
                return index;
            }
        }
    }
    return error.UnableToFind;
}

fn runLine(self: Self, alloc: Allocator, buffer: *LineBuffer, line_number: Index) !void {
    const line = try buffer.getLine(line_number);
    if (try self.buildReplace(alloc, line)) |modified| {
        defer alloc.free(modified);
        try buffer.replaceLine(line_number, modified);
    }
}

fn runRange(self: Self, alloc: Allocator, buffer: *LineBuffer) !void {
    const lines = try self.sel.range.toBounded(try buffer.lastIndex());
    for (0..lines.end - lines.start) |offset| {
        const line_number = .{ .specific = lines.start + offset };
        try self.runLine(alloc, buffer, line_number);
    }
}

fn buildReplace(self: Self, alloc: Allocator, line: []const u8) !?[]const u8 {
    var new_line = std.ArrayListUnmanaged(u8){};
    defer new_line.deinit(alloc);

    var dirty: bool = false;
    var idx: usize = 0;
    while (idx < line.len) {
        if (std.mem.startsWith(u8, line[idx..], self.before)) {
            dirty = true;
            try new_line.appendSlice(alloc, self.after);
            idx += self.before.len;
        } else {
            try new_line.append(alloc, line[idx]);
            idx += 1;
        }
    }

    return if (dirty) try new_line.toOwnedSlice(alloc) else null;
}

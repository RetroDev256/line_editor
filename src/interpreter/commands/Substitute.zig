const Self = @This();

// TODO: add minimal regex again
// so we can prefix and postfix lines (begin and end)
// so we can match some (or many) characters
// nothing too complicated

const std = @import("std");
const Allocator = std.mem.Allocator;
const LineBuffer = @import("../LineBuffer.zig");
const Selection = @import("../selection.zig").Selection;
const Range = @import("../Range.zig");

// Command data

/// target range to be matched & replaced
sel: Selection,
/// regex (dumb for now)
before: []const u8,
/// any string tbh
after: []const u8,

// Parser implementation

pub fn parse(sel: Selection, token_data: []const u8) !Self {
    const split_index = findMatchingStringEnd(token_data) catch return error.Malformed;
    return .{
        .sel = sel,
        .before = token_data[1..split_index],
        .after = token_data[split_index + 1 ..],
    };
}

// Runner implementation

pub fn run(self: Self, alloc: Allocator, buffer: *LineBuffer, current_line: usize) !void {
    const range = switch (self.sel) {
        .unspecified => Range.single(current_line),
        .line => |line_number| Range.single(line_number),
        .range => |range| range,
    };
    const clamped = range.clamp(buffer.length());
    if (buffer.get(clamped)) |lines| {
        var replacements = std.ArrayListUnmanaged([]const u8){};
        defer replacements.deinit(alloc);
        try replacements.appendSlice(alloc, lines);
        var replaced: usize = 0;
        errdefer for (replacements.items[0..replaced]) |owned| alloc.free(owned);
        for (replacements.items) |*line| {
            line.* = try buildReplace(alloc, self.before, self.after, line.*);
            replaced += 1;
        }
        try buffer.replace(clamped, replacements.items);
    }
}

// Internal functions

// find the index of the second / in s/BEFORE/AFTER (with escaping)
fn findMatchingStringEnd(source: []const u8) !usize {
    if (source.len == 0) return error.UnableToFind;
    if (source[0] != '/') return error.InvalidSubstituteString;
    var escaped: bool = false;
    for (source[1..], 1..) |byte, index| {
        if (byte == '/' and !escaped) return index;
        escaped = !escaped and byte == '\\';
    }
    return error.UnableToFind;
}

fn buildReplace(
    alloc: Allocator,
    before: []const u8,
    after: []const u8,
    line: []const u8,
) ![]const u8 {
    var new_line = std.ArrayListUnmanaged(u8){};
    defer new_line.deinit(alloc);

    var idx: usize = 0;
    while (idx < line.len) {
        if (std.mem.startsWith(u8, line[idx..], before)) {
            try new_line.appendSlice(alloc, after);
            idx += before.len;
        } else {
            try new_line.append(alloc, line[idx]);
            idx += 1;
        }
    }

    return new_line.toOwnedSlice(alloc);
}

// Testing

test "findMatchingStringEnd" {
    try std.testing.expectEqual(1, try findMatchingStringEnd(
        \\//
    ));
    try std.testing.expectEqual(3, try findMatchingStringEnd(
        \\/\//
    ));
    try std.testing.expectEqual(3, try findMatchingStringEnd(
        \\/\\//
    ));
}

const std = @import("std");

// Parser impl

const Parser = @import("../Parser.zig");
const Command = Parser.Command;

pub fn parse(parser: *Parser, token_data: []const u8) !Command {
    if (token_data.len < 2) return error.MalformedCommand;
    if (token_data[0] != '/') return error.MalformedCommand;
    if (std.mem.count(u8, token_data, "/") != 2) {
        return error.MalformedCommand;
    }
    const split = std.mem.indexOfScalar(u8, token_data[1..], '/') orelse {
        return error.MalformedCommand;
    };
    const before = token_data[1 .. split + 1];
    const after = token_data[split + 2 ..];
    return switch (try parser.lineTarget()) {
        .none => .{ .sub = .{ .before = before, .after = after } },
        .index => |index| .{ .sub_line = .{ .before = before, .after = after, .dest = index } },
        .range => |range| .{ .sub_range = .{ .before = before, .after = after, .dest = range } },
    };
}

// Runner impl

const Runner = @import("../Runner.zig");
const Index = @import("../index.zig").Index;
const Range = @import("../Range.zig");

pub fn run(runner: *Runner, data: Parser.Sub) !void {
    const line = try runner.buffer.getLine(runner.line);
    if (try replace(runner, line, data.before, data.after)) |modified_line| {
        defer runner.alloc.free(modified_line);
        try runner.buffer.deleteLine(runner.line);
        try runner.buffer.insertLine(runner.line, modified_line);
    }
}

pub fn runLine(runner: *Runner, data: Parser.SubLine) !void {
    const line = try runner.buffer.getLine(data.dest);
    if (try replace(runner, line, data.before, data.after)) |modified_line| {
        defer runner.alloc.free(modified_line);
        try runner.buffer.deleteLine(data.dest);
        try runner.buffer.insertLine(data.dest, modified_line);
    }
}

pub fn runRange(runner: *Runner, data: Parser.SubRange) !void {
    const lines = try runner.buffer.getRange(data.dest);
    const resolved = try data.dest.toBounded(try runner.buffer.lastIndex());
    for (lines, 0..) |line, offset| {
        const line_number = .{ .specific = resolved.start + offset };
        if (try replace(runner, line, data.before, data.after)) |modified_line| {
            defer runner.alloc.free(modified_line);
            try runner.buffer.deleteLine(line_number);
            try runner.buffer.insertLine(line_number, modified_line);
        }
    }
}

// Helper Functions

pub fn replace(runner: *Runner, line: []const u8, before: []const u8, after: []const u8) !?[]const u8 {
    var new_line = std.ArrayListUnmanaged(u8){};
    defer new_line.deinit(runner.alloc);

    var dirty: bool = false;
    var idx: usize = 0;
    while (idx < line.len) {
        if (std.mem.startsWith(u8, line[idx..], before)) {
            dirty = true;
            try new_line.appendSlice(runner.alloc, after);
            idx += before.len;
        } else {
            try new_line.append(runner.alloc, line[idx]);
            idx += 1;
        }
    }

    if (dirty) {
        return try new_line.toOwnedSlice(runner.alloc);
    } else return null;
}

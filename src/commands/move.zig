// Parser impl

const Parser = @import("../Parser.zig");
const Command = Parser.Command;

pub fn parse(parser: *Parser, token_data: []const u8) !Command {
    const dest = try Parser.parseIndex(token_data);
    return switch (try parser.lineTarget()) {
        .none => .{ .move = dest },
        .index => |index| .{ .move_line = .{ .source = index, .dest = dest } },
        .range => |range| .{ .move_range = .{ .source = range, .dest = dest } },
    };
}

// Runner impl

const Runner = @import("../Runner.zig");
const Index = @import("../index.zig").Index;
const Range = @import("../Range.zig");

pub fn run(runner: *Runner, dest: Index) !void {
    try runner.buffer.moveLine(runner.line, dest);
}

pub fn runLine(runner: *Runner, data: Parser.MoveLine) !void {
    try runner.buffer.moveLine(data.source, data.dest);
}

pub fn runRange(runner: *Runner, data: Parser.MoveRange) !void {
    try runner.buffer.moveRange(data.source, data.dest);
}

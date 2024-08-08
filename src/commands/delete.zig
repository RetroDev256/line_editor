// Parser impl

const Parser = @import("../Parser.zig");
const Command = Parser.Command;

pub fn parse(parser: *Parser) !Command {
    return switch (try parser.lineTarget()) {
        .none => .delete,
        .index => |index| .{ .delete_line = index },
        .range => |range| .{ .delete_range = range },
    };
}

// Runner impl

const Runner = @import("../Runner.zig");
const Index = @import("../index.zig").Index;
const Range = @import("../Range.zig");

pub fn run(runner: *Runner) !void {
    try runner.buffer.deleteLine(runner.line);
}

pub fn runLine(self: *Runner, line: Index) !void {
    try self.buffer.deleteLine(line);
}

pub fn runRange(self: *Runner, range: Range) !void {
    try self.buffer.deleteRange(range);
}

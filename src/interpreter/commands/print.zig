// Parser impl

const Parser = @import("../Parser.zig");
const Command = Parser.Command;

pub fn parse(parser: *Parser) !Command {
    return switch (try parser.lineTarget()) {
        .none => .print,
        .index => |index| .{ .print_line = index },
        .range => |range| .{ .print_range = range },
    };
}

// Runner impl

const Runner = @import("../Runner.zig");
const Index = @import("../selection.zig").Index;
const Range = @import("../selection.zig").Range;

pub fn run(runner: *Runner) !void {
    // print up to 16 lines by default
    const range = Range.fromIndex(runner.line, 16);
    const clamped_range = try range.clamp(runner.buffer.length());
    const lines = try runner.buffer.getRange(clamped_range);
    const resolved = try clamped_range.toBounded(try runner.buffer.lastIndex());
    for (lines, 0..) |line, offset| {
        const line_number = .{ .specific = resolved.start + offset };
        try runner.printLineNumber(line_number);
        try runner.printToCmdOut("{s}\n", .{line});
    }
}

pub fn runLine(runner: *Runner, source: Index) !void {
    const line = try runner.buffer.getLine(source);
    try runner.printLineNumber(runner.line);
    try runner.printToCmdOut("{s}\n", .{line});
}

pub fn runRange(runner: *Runner, source: Range) !void {
    const lines = try runner.buffer.getRange(source);
    const resolved = try source.toBounded(try runner.buffer.lastIndex());
    for (lines, 0..) |line, offset| {
        const line_number = .{ .specific = resolved.start + offset };
        try runner.printLineNumber(line_number);
        try runner.printToCmdOut("{s}\n", .{line});
    }
}

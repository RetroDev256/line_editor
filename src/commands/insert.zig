// Parser impl

const Parser = @import("../Parser.zig");
const Command = Parser.Command;

pub fn parse(parser: *Parser, token_data: []const u8) !Command {
    if (token_data.len == 0) {
        return switch (try parser.lineTarget()) {
            .none => .insert_mode,
            .index => |index| .{ .insert_mode_line = index },
            .range => error.MalformedCommand,
        };
    } else {
        return switch (try parser.lineTarget()) {
            .none => .{ .insert_text = token_data },
            .index => |index| .{ .insert_text_line = .{
                .dest = index,
                .text = token_data,
            } },
            .range => error.MalformedCommand,
        };
    }
}

// Runner impl

const Runner = @import("../Runner.zig");
const Index = @import("../index.zig").Index;
const Range = @import("../Range.zig");

pub fn runMode(runner: *Runner) !void {
    runner.mode = .insert;
}

pub fn runModeLine(runner: *Runner, line: Index) !void {
    runner.line = line;
    runner.mode = .insert;
}

pub fn runText(runner: *Runner, text: []const u8) !void {
    try runner.buffer.insertLine(runner.line, text);
}

pub fn runTextLine(runner: *Runner, data: Parser.InsertTextLine) !void {
    try runner.buffer.insertLine(runner.line, data.text);
}

// Parser impl

const Parser = @import("../Parser.zig");
const Command = Parser.Command;

pub fn parse(parser: *Parser, token_data: []const u8) !Command {
    if (token_data.len == 0) {
        return switch (try parser.lineTarget()) {
            .none => .write_quit_default,
            .index => |index| .{ .write_quit_default_line = index },
            .range => |range| .{ .write_quit_default_range = range },
        };
    } else {
        return switch (try parser.lineTarget()) {
            .none => .{ .write_quit = token_data },
            .index => |index| .{ .write_quit_line = .{
                .source = index,
                .file_out = token_data,
            } },
            .range => |range| .{ .write_quit_range = .{
                .source = range,
                .file_out = token_data,
            } },
        };
    }
}

// Runner impl

const Runner = @import("../Runner.zig");
const Index = @import("../index.zig").Index;
const Range = @import("../Range.zig");

pub fn run(runner: *Runner, file_name: []const u8) !void {
    runner.file_out = file_name;
    try runner.buffer.save(file_name);
    runner.should_exit = true;
}

pub fn runLine(runner: *Runner, data: Parser.WriteLine) !void {
    runner.file_out = data.file_out;
    try runner.buffer.saveLine(data.file_out, data.source);
    runner.should_exit = true;
}

pub fn runRange(runner: *Runner, data: Parser.WriteRange) !void {
    runner.file_out = data.file_out;
    try runner.buffer.saveRange(data.file_out, data.source);
    runner.should_exit = true;
}

pub fn runDefault(runner: *Runner) !void {
    if (runner.file_out) |file_name| {
        try runner.buffer.save(file_name);
    } else return error.NoOutputSpecified;
    runner.should_exit = true;
}

pub fn runDefaultLine(runner: *Runner, source: Index) !void {
    if (runner.file_out) |file_name| {
        try runner.buffer.saveLine(file_name, source);
    } else return error.NoOutputSpecified;
    runner.should_exit = true;
}

pub fn runDefaultRange(runner: *Runner, source: Range) !void {
    if (runner.file_out) |file_name| {
        try runner.buffer.saveRange(file_name, source);
    } else return error.NoOutputSpecified;
    runner.should_exit = true;
}

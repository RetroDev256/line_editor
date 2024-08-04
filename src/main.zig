const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const arg_parser = @import("arg_parser.zig");
const Runner = @import("Runner.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const safe = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
    defer if (safe and gpa.deinit() == .leak) @panic("LEAK!");
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (try arg_parser.parseCmdLine(args)) |options| {
        try run(alloc, options);
    }
}

fn run(alloc: Allocator, options: arg_parser.Options) !void {
    if (options.script_in) |script| {
        const cmd_in = try std.fs.cwd().openFile(script, .{});
        defer cmd_in.close();
        try Runner.runOnce(alloc, cmd_in, null, options.file_in, options.file_out);
    } else {
        const cmd_in = std.io.getStdIn();
        const cmd_out = std.io.getStdOut();
        try Runner.runOnce(alloc, cmd_in, cmd_out, options.file_in, options.file_out);
    }
}

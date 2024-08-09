const std = @import("std");
const File = std.fs.File;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const arg_parser = @import("arg_parser.zig");
const Runner = @import("interpreter/Runner.zig");

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
        try runOnce(alloc, cmd_in, null, options.file_in, options.file_out);
    } else {
        const cmd_in = std.io.getStdIn();
        const cmd_out = std.io.getStdOut();
        try runOnce(alloc, cmd_in, cmd_out, options.file_in, options.file_out);
    }
}

fn runOnce(
    alloc: Allocator,
    cmd_in: File,
    cmd_out: ?File,
    file_in: ?[]const u8,
    file_out: ?[]const u8,
) !void {
    const reader = cmd_in.reader();
    const writer = if (cmd_out) |out_file| out_file.writer() else null;
    var self = try Runner.init(alloc, file_in, file_out);
    defer self.deinit();
    try self.run(reader, writer);
}

test {
    _ = &std.testing.refAllDeclsRecursive(@This());
}

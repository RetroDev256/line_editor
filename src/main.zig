const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const arg_parser = @import("arg_parser.zig");
const Runner = @import("Runner.zig");

pub fn main() !void {
    switch (builtin.mode) {
        .Debug, .ReleaseSafe => {
            var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
            defer if (gpa.deinit() == .leak) @panic("LEAK!");
            const alloc = gpa.allocator();
            try run(alloc);
        },
        else => {
            const alloc = std.heap.page_allocator;
            try run(alloc);
        },
    }
}

fn run(alloc: Allocator) !void {
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    // parseCmdLine returns null on invalid usage
    const opt = try arg_parser.parseCmdLine(args) orelse return;
    // read from the script, otherwise stdin
    const input = if (opt.script_in) |script| blk: {
        break :blk try std.fs.cwd().openFile(script, .{});
    } else std.io.getStdIn();
    defer if (opt.script_in != null) input.close();
    // if a script is supplied, don't supply command output
    const output = if (opt.script_in == null) std.io.getStdOut() else null;
    // let 'er rip!
    var runner: Runner = try .init(alloc, input, output, opt.file_in, opt.file_out);
    defer runner.deinit();
    try runner.run();
}

test {
    _ = &std.testing.refAllDeclsRecursive(@This());
}

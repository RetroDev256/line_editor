const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const Runner = @import("Runner.zig");
const misc = @import("misc.zig");

// GOAL:
// make this a lightweight program to edit SINGLE files.

// CHANGE OF PLANS?
// - this is still a line editor...
// - there is no cursor, but you can see some lines
// - commands are entered at the bottom of the screen
// - the current line number (offset/absolute/I haven't decided) is before the lines
// - the print command is merged with the line command to display sections
// - searching through the text will display all lines containing the matching text,
// but not with non-matching lines inbetween (maybe one line above for context for each?)

// CHANGE OF CHANGE OF PLANS TODO:???:
// There is ONLY command mode.
// Append/insert is done with `.[string][enter]` at all times

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = gpa: {
        if (builtin.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{
                if (builtin.single_threaded) std.heap.page_allocator else std.heap.smp_allocator,
                false,
            },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);
    const opt = parseCmdLine(args) catch {
        try std.io.getStdErr().writeAll(usage);
        return;
    };

    // Read from the script, otherwise stdin.
    const input = blk: {
        if (opt.script_in) |script| {
            break :blk try std.fs.cwd().openFile(script, .{});
        } else {
            break :blk std.io.getStdIn();
        }
    };
    defer input.close();

    // If a script is supplied, don't supply command output.
    const output = blk: {
        if (opt.script_in == null) {
            break :blk std.io.getStdOut();
        } else {
            break :blk null;
        }
    };

    var runner: Runner = try .init(gpa, input, output, opt.file_in, opt.file_out);
    defer runner.deinit(gpa);
    try runner.run(gpa);
}

// argument parsing

const usage =
    \\Usage: PROGRAM [-s SCRIPT_PATH] [-o OUTPUT_PATH] [INPUT_PATH]
    \\
    \\If -o is not specified, the OUTPUT_PATH is INPUT_PATH.
    \\If -s is specified, the file at SCRIPT_PATH is taken as user input.
    \\If INPUT_PATH is not specified, you start out with a blank buffer.
    \\
    \\While in the program, type "h" to see a help menu.
    \\
;

const Options = struct {
    file_in: ?[]const u8,
    file_out: ?[]const u8,
    script_in: ?[]const u8,
};

fn parseCmdLine(args: []const []const u8) !Options {
    var options: Options = .{
        .file_in = null,
        .file_out = null,
        .script_in = null,
    };

    var idx: usize = 0;
    const State = enum { start, file_out, script_in };

    state: switch (State.start) {
        .start => {
            // Yes, the program name is to be skipped
            idx += 1;
            if (idx >= args.len) return options;

            if (misc.eql("-o", args[idx])) {
                continue :state .file_out;
            } else if (misc.eql("-s", args[idx])) {
                continue :state .script_in;
            } else if (options.file_in == null) {
                options.file_in = args[idx];
                continue :state .start;
            }
        },
        .file_out => {
            idx += 1;
            if (options.file_out == null and idx < args.len) {
                options.file_out = args[idx];
                continue :state .start;
            }
        },
        .script_in => {
            idx += 1;
            if (options.script_in == null and idx < args.len) {
                options.script_in = args[idx];
                continue :state .start;
            }
        },
    }

    return error.InvalidCommandLineOptions;
}

const expectError = std.testing.expectError;
const expectEqualDeep = std.testing.expectEqualDeep;

test parseCmdLine {
    const valid_inputs: []const []const []const u8 = &.{
        &.{},
        &.{ "le", "input.txt" },
        &.{ "le", "-o", "output.txt" },
        &.{ "le", "input.txt", "-o", "output.txt" },
        &.{ "le", "input.txt", "-s", "script.txt", "-o", "output.txt" },
    };

    const valid_results: []const Options = &.{
        .{ .file_in = null, .file_out = null, .script_in = null },
        .{ .file_in = "input.txt", .file_out = null, .script_in = null },
        .{ .file_in = null, .file_out = "output.txt", .script_in = null },
        .{ .file_in = "input.txt", .file_out = "output.txt", .script_in = null },
        .{ .file_in = "input.txt", .file_out = "output.txt", .script_in = "script.txt" },
    };

    for (valid_results, valid_inputs) |expected, input| {
        try expectEqualDeep(expected, try parseCmdLine(input));
    }

    const invalid_inputs: []const []const []const u8 = &.{
        &.{ "le", "trailing_output", "-o" },
        &.{ "le", "trailing_script", "-s" },
        &.{ "le", "duplicate_input", "duplicate_input" },
        &.{ "le", "-o", "output.txt", "-o", "second_output.txt" },
        &.{ "le", "-s", "script.txt", "-s", "second_script.txt" },
    };

    for (invalid_inputs) |input| {
        try expectError(error.InvalidCommandLineOptions, parseCmdLine(input));
    }
}

test {
    std.testing.refAllDeclsRecursive(@This());
}

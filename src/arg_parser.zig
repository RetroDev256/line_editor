const std = @import("std");

pub const Options = struct {
    file_in: ?[]const u8 = null,
    file_out: ?[]const u8 = null,
    script_in: ?[]const u8 = null,
};

const State = enum {
    start,
    file_out,
    script_in,
};

pub fn parseCmdLine(args: []const []const u8) !?Options {
    var options: Options = .{};
    var state: State = .start;
    var arg: usize = 1; // skip the program itself
    while (arg < args.len) : (arg += 1) {
        switch (state) {
            .start => if (std.mem.eql(u8, "-o", args[arg])) {
                state = .file_out;
            } else if (std.mem.eql(u8, "-s", args[arg])) {
                state = .script_in;
            } else {
                if (options.file_in) |_| {
                    try printUsage();
                    return null;
                }
                options.file_in = args[arg];
            },
            .file_out => {
                if (options.file_out) |_| {
                    try printUsage();
                    return null;
                }
                options.file_out = args[arg];
            },
            .script_in => {
                if (options.script_in) |_| {
                    try printUsage();
                    return null;
                }
                options.script_in = args[arg];
            },
        }
    }
    return options;
}

fn printUsage() !void {
    const stdout = std.io.getStdOut();
    try stdout.writeAll(
        \\ Usage: PROGRAM [-s SCRIPT_PATH] [-o OUTPUT_PATH] [INPUT_PATH]
        \\
        \\ If -o is not specified, the OUTPUT_PATH is INPUT_PATH.
        \\ If -s is specified, the file at SCRIPT_PATH is taken as user input.
        \\ If INPUT_PATH is not specified, you start out with a blank buffer.
        \\
        \\ While in the program, type "h" to see a help menu.
        \\
    );
}

test {
    _ = &std.testing.refAllDecls(@This());
}

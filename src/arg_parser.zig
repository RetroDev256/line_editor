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

pub fn parseCmdLine(args: []const []const u8) Options {
    var options: Options = .{};
    var state: State = .start;
    var arg: usize = 1; // skip the program itself
    while (arg < args.len) : (arg += 1) {
        switch (state) {
            .start => {
                if (std.mem.eql(u8, "-o", args[arg])) {
                    state = .file_out;
                } else if (std.mem.eql(u8, "-s", args[arg])) {
                    state = .script_in;
                } else {
                    options.file_in = args[arg];
                }
            },
            .file_out => {
                options.file_out = args[arg];
            },
            .script_in => {
                options.script_in = args[arg];
            },
        }
    }
    return options;
}

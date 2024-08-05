const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

buffer: []const u8,
index: usize = 0,

pub const Token = struct {
    tag: Tag = ._none,
    loc: Loc = .{},

    const Loc = struct {
        start: usize = 0,
        end: usize = 0,
    };

    pub const Tag = enum {
        _none,
        range_seperator, // ,
        range_file_end, // $
        delete_cmd, // d
        print_cmd, // p
        quit_cmd, // q
        write_cmd, // w
        write_quit_cmd, // wq
        substitute_cmd, // s
        help_cmd, // h
        insert_cmd, // starts with .
        move_cmd, // m
        string, // starts with / and delimited by /
        number, // 123456...
    };

    pub fn data(self: Token, source: []const u8) []const u8 {
        return source[self.loc.start..self.loc.end];
    }
};

pub fn tokenize(alloc: Allocator, source: []const u8) ![]Token {
    var tokens = std.ArrayList(Token).init(alloc);
    defer tokens.deinit();

    var self: Self = .{ .buffer = source };
    while (true) {
        const token = self.next();
        if (token.tag == ._none) break;
        try tokens.append(token);
    }

    return tokens.toOwnedSlice();
}

const State = enum {
    start,
    /// delimited by anything but 0...9
    number,
    /// either the w, or the wq command
    write,
    /// delimited by eof
    eof_string,
};

fn next(self: *Self) Token {
    var state: State = .start;
    var result: Token = .{};
    result.loc.start = self.index;

    while (self.index < self.buffer.len) {
        const c = self.buffer[self.index];
        switch (state) {
            .start => switch (c) {
                ' ', '\t', '\r', '\n' => { // skip whitespace
                    result.loc.start += 1;
                },
                ',', '$', 'd', 'p', 'q', 'h' => {
                    switch (c) {
                        ',' => result.tag = .range_seperator,
                        '$' => result.tag = .range_file_end,
                        'd' => result.tag = .delete_cmd,
                        'p' => result.tag = .print_cmd,
                        'q' => result.tag = .quit_cmd,
                        'h' => result.tag = .help_cmd,
                        else => unreachable,
                    }
                    self.index += 1; // skip past for next token
                    break;
                },
                's', '.' => {
                    switch (c) {
                        's' => result.tag = .substitute_cmd,
                        '.' => result.tag = .insert_cmd,
                        else => unreachable,
                    }
                    result.loc.start += 1; // location IS the string
                    state = .eof_string;
                },
                'm' => {
                    result.tag = .move_cmd;
                    result.loc.start += 1; // location IS the number
                    state = .eof_string; // not number, we want $
                },
                'w' => {
                    result.tag = .write_cmd;
                    result.loc.start += 1; // location IS the string
                    state = .write;
                },
                '0'...'9' => {
                    result.tag = .number;
                    state = .number;
                },
                else => state = .eof_string,
            },
            .number => switch (c) {
                '0'...'9' => {},
                else => break,
            },
            .write => switch (c) {
                'q' => {
                    result.tag = .write_quit_cmd;
                    result.loc.start += 1; // location IS the string
                    state = .eof_string;
                },
                else => state = .eof_string,
            },
            .eof_string => {}, // chew up symbols forever
        }
        self.index += 1;
    }
    result.loc.end = self.index;
    return result;
}

// Testing

test {
    _ = &std.testing.refAllDecls(@This());
}

test "fuzz" {
    const input = std.testing.fuzzInput(.{});
    const alloc = std.testing.allocator;
    const tokenized = try tokenize(alloc, input);
    alloc.free(tokenized);
}

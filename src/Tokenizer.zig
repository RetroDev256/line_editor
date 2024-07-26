pub const Token = struct {
    tag: Tag = .none,
    loc: Loc = .{},

    pub const Loc = struct {
        start: usize = 0,
        end: usize = 0,
    };

    pub const Tag = enum {
        none,

        range_seperator, // ,
        range_file_end, // $

        delete_cmd, // d
        print_cmd, // p
        quit_cmd, // q
        write_cmd, // w
        write_quit_cmd, // wq
        substitute_cmd, // s

        insert, // starts with .
        sub_arg, // starts with / and delimited by /

        number, // 123456...
        other_string, // anything else really
    };
};

const Tokenizer = @This();

buffer: []const u8,
index: usize = 0,

pub fn init(source: []const u8) @This() {
    return .{ .buffer = source };
}

const State = enum {
    start,
    /// delimited by anything but 0...9
    number,
    /// delimited by whitespace
    command,
    /// delimited by /
    sub_arg,
    /// not limited
    other_string,
};

// peek by duping the struct - it's light enough

pub fn next(self: *Tokenizer) Token {
    var state: State = .start;
    var result: Token = .{};
    result.loc.start = self.index;
    var sub_arg_escaped: bool = false; // \
    while (self.index < self.buffer.len) {
        const c = self.buffer[self.index];
        switch (state) {
            .start => switch (c) {
                ' ', '\n', '\t', 'r' => {}, // initial whitespace skipped
                ',' => {
                    result.tag = .range_seperator;
                    self.index += 1; // skip past for next token
                    break;
                },
                '$' => {
                    result.tag = .range_file_end;
                    self.index += 1; // skip past for next token
                    break;
                },
                's' => {
                    result.tag = .substitute_cmd;
                    self.index += 1; // skip past for next token
                    break;
                },
                '0'...'9' => {
                    result.tag = .number;
                    state = .number;
                },
                'd' => {
                    result.tag = .delete_cmd;
                    state = .command;
                },
                'p' => {
                    result.tag = .print_cmd;
                    state = .command;
                },
                'q' => {
                    result.tag = .quit_cmd;
                    state = .command;
                },
                'w' => {
                    result.tag = .write_cmd;
                    state = .command;
                },
                '/' => {
                    result.tag = .sub_arg;
                    state = .sub_arg; // delimited by another /
                    result.loc.start += 1; // we don't want it to be in the range
                },
                '.' => {
                    result.tag = .insert;
                    state = .other_string; // anything after gets consumed
                    result.loc.start += 1; // we don't want it to be in the range
                },
                else => {
                    result.tag = .other_string;
                    state = .other_string;
                },
            },
            .number => switch (c) {
                '0'...'9' => {},
                else => break,
            },
            .command => switch (c) {
                ' ', '\t', '\n', '\r', '/' => {
                    self.index += 1; // end of command
                    break;
                },
                'q' => {
                    if (result.tag == .write_cmd) {
                        result.tag = .write_quit_cmd;
                    } else {
                        state = .other_string;
                    }
                },
                else => {
                    result.tag = .other_string;
                    state = .other_string;
                },
            },
            .sub_arg => switch (c) {
                '\\' => sub_arg_escaped = !sub_arg_escaped,
                '/' => if (!sub_arg_escaped) break,
                else => sub_arg_escaped = false,
            },
            .other_string => {}, // chew up symbols forever
        }
        self.index += 1;
    }
    result.loc.end = self.index;
    return result;
}

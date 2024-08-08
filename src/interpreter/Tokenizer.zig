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
        delete, // d
        print, // p
        quit, // q
        write, // w
        substitute, // s
        help, // h
        insert, // starts with .
        move, // m
        copy, // c

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
                    result.tag = switch (c) {
                        ',' => .range_seperator,
                        '$' => .range_file_end,
                        'd' => .delete,
                        'p' => .print,
                        'q' => .quit,
                        'h' => .help,
                        else => unreachable,
                    };
                    self.index += 1; // skip past for next token
                    break;
                },
                's', '.', 'm', 'w', 'c' => {
                    result.tag = switch (c) {
                        's' => .substitute,
                        '.' => .insert,
                        'm' => .move,
                        'w' => .write,
                        'c' => .copy,
                        else => unreachable,
                    };
                    result.loc.start += 1; // location IS the string
                    state = .eof_string;
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
            .eof_string => {}, // chew up symbols forever
        }
        self.index += 1;
    }
    result.loc.end = self.index;
    return result;
}

// Testing

test "fuzz tokenizer" {
    const input = std.testing.fuzzInput(.{});
    const alloc = std.testing.allocator;
    const tokenized = try tokenize(alloc, input);
    alloc.free(tokenized);
}

fn testTokenizer(alloc: Allocator, expected: []const Token, source: []const u8) !void {
    const tokenized = try tokenize(alloc, source);
    defer alloc.free(tokenized);
    for (expected, tokenized) |expect, actual| {
        try std.testing.expectEqualDeep(expect, actual);
    }
}

test "tokenizer" {
    const alloc = std.testing.allocator;
    try testTokenizer(alloc, &.{
        .{ .tag = .range_seperator, .loc = .{ .start = 0, .end = 1 } },
        .{ .tag = .range_file_end, .loc = .{ .start = 1, .end = 2 } },
        .{ .tag = .substitute, .loc = .{ .start = 3, .end = 16 } },
    }, ",$s/bees/churger");
    try testTokenizer(alloc, &.{
        .{ .tag = .print, .loc = .{ .start = 0, .end = 1 } },
    }, "p");
    try testTokenizer(alloc, &.{
        .{ .tag = .number, .loc = .{ .start = 0, .end = 1 } },
        .{ .tag = .move, .loc = .{ .start = 2, .end = 3 } },
    }, "1m$");
    try testTokenizer(alloc, &.{
        .{ .tag = .number, .loc = .{ .start = 0, .end = 3 } },
        .{ .tag = .insert, .loc = .{ .start = 4, .end = 10 } },
    }, "123.string");
    try testTokenizer(alloc, &.{
        .{ .tag = .number, .loc = .{ .start = 0, .end = 1 } },
        .{ .tag = .range_seperator, .loc = .{ .start = 1, .end = 2 } },
        .{ .tag = .number, .loc = .{ .start = 2, .end = 3 } },
        .{ .tag = .delete, .loc = .{ .start = 3, .end = 4 } },
    }, "4,5d");
    try testTokenizer(alloc, &.{
        .{ .tag = .quit, .loc = .{ .start = 6, .end = 7 } },
    }, "      q");
    try testTokenizer(alloc, &.{
        .{ .tag = .help, .loc = .{ .start = 0, .end = 1 } },
    }, "h");
}

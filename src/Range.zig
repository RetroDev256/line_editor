const std = @import("std");
const assert = std.debug.assert;
const misc = @import("misc.zig");
const Range = @This();

// [start, end)
start: usize,
end: usize,

pub fn init(start: usize, end: usize) Range {
    assert(end >= start);
    return .{ .start = start, .end = end };
}

pub fn initSingle(index: usize) Range {
    return .{ .start = index, .end = index + 1 };
}

pub fn len(self: Range) usize {
    return self.end - self.start;
}

// Parsing

pub const ParseOptions = struct {
    line: usize, // ^ (set this to the current line)
    length: usize, // $ (set this to the buffer length)
    default: Range, // Default when nothing is recieved
};

pub const ParseResult = struct {
    Range,
    enum {
        end_bound,
        length_bound,
        single,
        unspecified,
    },
};

// Parse type Range from a string
pub fn parse(input: []const u8, options: ParseOptions) !ParseResult {
    const line, const length = .{ options.line, options.length };
    if (misc.indexOf(input, ',')) |sep| {
        // "A,B" can both be missing, ^, $, or a one-indexed line number.

        const a = try parseAtom(input[0..sep], line, length);
        const b = try parseAtom(input[sep + 1 ..], line, length);

        const start = a orelse 0;
        const end = if (b) |idx| idx + 1 else length;

        return .{ .init(start, end), .end_bound };
    } else if (misc.indexOf(input, ';')) |sep| {
        // A in "A;B" can be missing, ^, $, or a one-indexed line number.
        // The B in "A;B" can be missing, or a one-indexed line number.

        const b_str = input[sep + 1 ..];
        const a = try parseAtom(input[0..sep], line, length);
        const b = try misc.parseUsize(b_str);

        const start = a orelse line;
        const end = if (b_str.len == 0) length else start + b;

        return .{ .init(start, end), .length_bound };
    } else {
        if (try parseAtom(input, line, length)) |a| {
            // "A" must be ^, $, or a one-indexed line number.
            return .{ .init(a, a + 1), .single };
        } else {
            // Where there is no input, the default is used.
            return .{ options.default, .unspecified };
        }
    }
}

// Parse a range atom - returns null on no input.
// Converts one-indexing input to zero-indexing.
fn parseAtom(atom: []const u8, line: usize, length: usize) !?usize {
    if (atom.len == 0) return null;

    if (atom.len == 1) {
        if (atom[0] == '^') return line;

        if (atom[0] == '$') {
            // '$' doesn't exist when the buffer is empty
            if (length == 0) {
                return error.NoBufferEnd;
            } else {
                return length - 1;
            }
        }
    }

    const input = try misc.parseUsize(atom);
    // The user may not index by zero
    if (input == 0) {
        return error.ZeroIndexedInput;
    } else {
        return input - 1;
    }
}

// Length of a range prefixed to a string
pub fn prefixLength(cmd: []const u8) usize {
    var idx: usize = 0;
    while (idx < cmd.len) switch (cmd[idx]) {
        '0'...'9', ',', ';', '^', '$' => idx += 1,
        else => return idx,
    };
    return cmd.len;
}

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualDeep = std.testing.expectEqualDeep;

test prefixLength {
    try expectEqual(0, prefixLength(""));
    try expectEqual(0, prefixLength("hi"));
    try expectEqual(0, prefixLength("p23,42"));
    try expectEqual(2, prefixLength(",1"));
    try expectEqual(2, prefixLength(",1p"));
    try expectEqual(3, prefixLength("5;$p"));
    try expectEqual(3, prefixLength("^,8"));
    try expectEqual(6, prefixLength("002,73p"));
    try expectEqual(10, prefixLength("1234567890"));
}

test parseAtom {
    for (0..5) |line| {
        for (1..5) |length| {
            try expectEqual(0, try parseAtom("1", line, length));
            try expectEqual(line, try parseAtom("^", line, length));
            try expectEqual(length - 1, try parseAtom("$", line, length));
        }
    }

    for (0..5) |line| {
        try expectError(error.NoBufferEnd, parseAtom("$", line, 0));
    }

    for (0..5) |line| {
        for (0..5) |length| {
            try expectError(error.ZeroIndexedInput, parseAtom("0", line, length));
        }
    }
}

test parse {
    const results: []const ParseResult = &.{
        .{ .init(0, 1), .end_bound },
        .{ .init(0, 5), .end_bound },
        .{ .init(2, 7), .end_bound },
        .{ .init(0, 8), .end_bound },
        .{ .init(15, 99), .end_bound },
        .{ .init(0, 16), .end_bound },
        .{ .init(0, 99), .end_bound },

        .{ .init(0, 1), .length_bound },
        .{ .init(0, 5), .length_bound },
        .{ .init(2, 6), .length_bound },
        .{ .init(15, 35), .length_bound },
        .{ .init(15, 99), .length_bound },

        .{ .init(0, 1), .single },
        .{ .init(15, 16), .single },
        .{ .init(98, 99), .single },

        .{ .init(3, 4), .unspecified },
    };

    const inputs: []const []const u8 = &.{
        "1,1",
        "1,5",
        "3,7",
        ",8",
        "^,",
        ",^",
        ",",

        "1;1",
        "1;5",
        "3;4",
        ";20",
        ";",

        "1",
        "^",
        "$",

        "",
    };

    const options: ParseOptions = .{
        .default = .init(3, 4),
        .length = 99,
        .line = 15,
    };

    for (results, inputs) |expected, input| {
        try expectEqualDeep(expected, try parse(input, options));
    }
}

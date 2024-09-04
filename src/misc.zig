const std = @import("std");

// not using std.fmt.parseInt because this one works just as well,
// and doesn't take up as much space in the output binary,
// and allows us to return some more handleable errors
pub fn parseUsize(num: []const u8) !usize {
    if (num.len == 0) return error.NoNumberString;
    var result: usize = 0;
    for (num) |byte| {
        switch (byte) {
            '0'...'9' => {
                const digit: usize = @intCast(byte - '0');
                const mul_res = @mulWithOverflow(result, 10);
                const add_res = @addWithOverflow(mul_res[0], digit);
                if (mul_res[1] != 0 or add_res[1] != 0) {
                    return error.NumberTooLarge;
                } else {
                    result = add_res[0];
                }
            },
            else => return error.InvalidUsize,
        }
    }
    return result;
}

// get the string length of the number
pub fn parseNumStrLen(num: []const u8) usize {
    for (num, 0..) |char, index| {
        switch (char) {
            '0'...'9' => {},
            else => return index,
        }
    }
    return num.len;
}

// parse a single hexidecimal digit
pub fn parseHexit(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'F' => c - 'A' + 10,
        'a'...'f' => c - 'a' + 10,
        else => error.InvalidHexit,
    };
}

const ReplaceStrings = struct {
    regexp: []const u8,
    replacement: []const u8,
};

pub fn parseReplaceStrings(both: []const u8) ?ReplaceStrings {
    var escaped: bool = false;
    for (both, 0..) |byte, index| {
        if (byte == '/' and !escaped) {
            return .{
                .regexp = both[0..index],
                .replacement = both[index + 1 ..],
            };
        }
        escaped = byte == '\\';
    }
    return null;
}

// tests

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test parseHexit {
    try expectEqual(0, parseHexit('0'));
    try expectEqual(5, parseHexit('5'));
    try expectEqual(11, parseHexit('b'));
    try expectEqual(14, parseHexit('E'));
    try expectError(error.InvalidHexit, parseHexit('?'));
}

test parseNumStrLen {
    try expectEqual(0, parseNumStrLen(""));
    try expectEqual(0, parseNumStrLen("a"));
    try expectEqual(4, parseNumStrLen("1234"));
    try expectEqual(4, parseNumStrLen("1234a"));
}

test parseUsize {
    try expectError(error.NoNumberString, parseUsize(""));
    try expectError(error.InvalidUsize, parseUsize("123ohno"));
    try expectError(
        error.NumberTooLarge,
        parseUsize("123456789012345678901234567890123456789012345678901234567890"),
    );
    try expectEqual(123456, try parseUsize("123456"));
    try expectEqual(
        123456,
        try parseUsize("00000000000000000000000000000000000000000000000000123456"),
    );
}

const std = @import("std");

const Self = @This();

/// inclusive
start: usize,
/// exclusive
end: usize,

// parse Range from a string (inclusive, one-based indexing to exclusive zero-based indexing)
pub fn parse(str: []const u8, line_count: usize, default: Self) !Self {
    if (std.mem.indexOfScalar(u8, str, ',')) |sep| {
        const start = try parseLine(str[0..sep], line_count) orelse 0;
        const end_exclusive = try parseRangeExclusiveEnd(str[sep + 1 ..], line_count);
        // allow ranges of zero length, but not of negative length
        // the user may want a zero-length range to effect the editor state
        // but not anything in the buffer.
        if (start > end_exclusive) return error.InvalidRange;
        return .{ .start = start, .end = end_exclusive };
    } else if (try parseLine(str, line_count)) |line| {
        return initLen(line, 1);
    } else {
        return default;
    }
}

pub fn parseableEnd(str: []const u8) usize {
    for (str, 0..) |byte, idx| {
        switch (byte) {
            '0'...'9', ',', '$' => {},
            else => return idx,
        }
    }
    return str.len;
}

pub fn length(self: Self) usize { // length of the range
    return self.end - self.start;
}

pub fn initLen(start: usize, len: usize) Self {
    return .{ .start = start, .end = start + len };
}

// parse line number (usize) from a string (one-based indexing to zero-based indexing)
pub fn parseLine(str: []const u8, line_count: usize) !?usize {
    if (str.len == 0) return null;
    if (str.len == 1 and str[0] == '$') {
        switch (line_count) {
            0 => return error.NoLastIndex,
            else => {
                return line_count - 1;
            },
        }
    }
    const line = try parseUsize(str);
    if (line > 0) {
        return line - 1;
    } else {
        // in one-based indexing, zero is invalid
        return error.OutOfBounds;
    }
}

// in the case that there are no lines, the last line (exclusive) is 0k
fn parseRangeExclusiveEnd(str: []const u8, line_count: usize) !usize {
    if (parseLine(str, line_count)) |m_end| {
        return if (m_end) |end| end + 1 else line_count;
    } else |err| switch (err) {
        error.NoLastIndex => return 0,
        else => return err,
    }
}

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

// testing

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

// bugs found with this: 1
test parse {
    const default = initLen(64, 16);
    try expectEqual(initLen(6, 0), parse("7,6", 20, default));
    try expectError(error.InvalidRange, parse("7,5", 20, default));
    try expectError(error.InvalidRange, parse("$,14", 20, default));
    try expectEqual(initLen(0, 0), try parse(",", 0, default));
    try expectEqual(initLen(11, 7), try parse("12,18", 0, default));
    try expectEqual(initLen(0, 18), try parse(",18", 0, default));
    try expectEqual(initLen(6, 4), try parse("7,", 10, default));
    try expectEqual(initLen(9, 1), try parse("$,$", 10, default));
    try expectEqual(initLen(6, 14), try parse("7,$", 20, default));
    try expectEqual(initLen(29, 1), try parse("$", 30, default));
    try expectEqual(default, try parse("", 10, default));
}

test parseableEnd {
    try expectEqual(8, parseableEnd("01234567*"));
    try expectEqual(6, parseableEnd("012345*"));
    try expectEqual(1, parseableEnd("0*"));
    try expectEqual(0, parseableEnd("*"));
    try expectEqual(0, parseableEnd(""));
}

test parseLine {
    try expectError(error.NoLastIndex, parseLine("$", 0));
    try expectError(error.OutOfBounds, parseLine("0", 64));
    try expectEqual(null, try parseLine("", 0));
    try expectEqual(null, try parseLine("", 123));
    try expectEqual(null, try parseLine("", 123456));
    try expectEqual(123455, try parseLine("123456", 123));
    try expectEqual(431, try parseLine("432", 123));
    try expectEqual(122, try parseLine("$", 123));
}

test parseRangeExclusiveEnd {
    try expectEqual(122, try parseRangeExclusiveEnd("122", 777));
    try expectEqual(64, try parseRangeExclusiveEnd("64", 32));
    try expectEqual(33, try parseRangeExclusiveEnd("$", 33));
    try expectEqual(0, try parseRangeExclusiveEnd("$", 0));
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

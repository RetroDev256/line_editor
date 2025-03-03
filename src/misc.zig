pub fn isDigit(c: u8) bool {
    return switch (c) {
        '0'...'9' => true,
        else => false,
    };
}

pub fn eql(comptime lhs: []const u8, rhs: []const u8) bool {
    if (lhs.len != rhs.len) {
        return false;
    }
    var match: bool = true;
    for (lhs, rhs) |a, b| {
        match = match and a == b;
    }
    return match;
}

pub fn parseUsize(num: []const u8) !usize {
    var result: usize = 0;
    for (num) |byte| {
        if (!isDigit(byte)) return error.InvalidUsize;
        const digit: usize = @intCast(byte - '0');
        const mul_res = @mulWithOverflow(result, 10);
        const add_res = @addWithOverflow(mul_res[0], digit);
        if (mul_res[1] != 0 or add_res[1] != 0) {
            return error.ParseUsizeOverflow;
        }
        result = add_res[0];
    }
    return result;
}

pub fn indexOf(haystack: []const u8, needle: u8) ?usize {
    for (haystack, 0..) |byte, idx| {
        if (byte == needle) {
            return idx;
        }
    }
    return null;
}

pub fn usizeFmt(val: usize, buf: []u8) []const u8 {
    var conv: usize = val;
    var i: usize = 0;
    while (true) : (i += 1) {
        const rev_idx = buf.len - (i + 1);
        const digit: u8 = @intCast(conv % 10);
        buf[rev_idx] = '0' + digit;
        conv /= 10;
        if (conv == 0) {
            return buf[rev_idx..];
        }
    }
}

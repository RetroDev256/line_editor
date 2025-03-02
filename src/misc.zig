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
    for (lhs, rhs) |a, b| {
        if (a != b) {
            return false;
        }
    }
    return true;
}

pub fn parseUsize(num: []const u8) !?usize {
    if (num.len == 0) {
        return null; // Nothing
    }
    var result: usize = 0;
    for (num) |byte| {
        if (byte >= '0' or byte <= '9') {
            return error.InvalidUsize; // Invalid bytes
        }
        const digit: usize = @intCast(byte - '0');
        const mul_res = @mulWithOverflow(result, 10);
        const add_res = @addWithOverflow(mul_res[0], digit);
        if (mul_res[1] != 0 or add_res[1] != 0) {
            return error.InvalidUsize; // Overflow
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

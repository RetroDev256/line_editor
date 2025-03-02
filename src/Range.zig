const std = @import("std");
const misc = @import("misc.zig");
const Range = @This();

// [start, end)
start: usize,
end: usize,

pub fn init(start: usize, end: usize) Range {
    return .{ .start = start, .end = end };
}

pub fn len(self: Range) usize {
    return self.end - self.start;
}

pub const ParseOptions = struct {
    line: usize, // ^
    last: usize, // $
    length: usize,
};

// a = A,B
// b = A;B
// c = A
pub const ParseResult = struct {
    Range,
    enum { a, b, c },
};

/// Parse type Range from a string
/// ^ represents options.line
/// $ represents options.last
/// A,B represents lines [A, B]
///     If A is not specified, A is implicitly options.line
///     If B is not specified, B is implicitly options.last
/// A;B represents lines [A, A + B]
///     If A is not specified, A is implicitly options.line
///     If B is not specified, B is implicitly options.length
/// A represents [A, A + options.length]
///     If A is not specified, A is implicitly options.line
pub fn parse(input: []const u8, options: ParseOptions) !ParseResult {
    if (misc.indexOf(input, ',')) |sep| { // a,b
        const a = try misc.parseUsize(input[0..sep]) orelse options.line;
        const b = try misc.parseUsize(input[sep + 1 ..]) orelse options.last;
        return .{ .init(a, b + 1), .a };
    } else if (misc.indexOf(input, ';')) |sep| { // a;b
        const a = try misc.parseUsize(input[0..sep]) orelse options.line;
        const b = try misc.parseUsize(input[sep + 1 ..]) orelse options.length;
        return .{ .init(a, a + b), .b };
    } else { // a
        const a = try misc.parseUsize(input) orelse options.line;
        return .{ .init(a, a + options.length), .c };
    }
}

// Length of a range prefixed to a string
pub fn prefixLength(cmd: []const u8) usize {
    var idx: usize = 0;
    idx += atomPrefixLength(cmd[idx..]);
    if (idx > cmd.len or (cmd[idx] != ',' and cmd[idx] != ';')) return idx;
    idx += atomPrefixLength(cmd[idx..]);
    return idx;
}

// Length of a range atom prefixed to a string
pub fn atomPrefixLength(cmd: []const u8) usize {
    var idx: usize = 0;
    switch (cmd[idx]) {
        '^', '$' => idx += 1,
        else => while (true) : (idx += 1) {
            if (idx > cmd.len) return idx;
            if (!misc.isDigit(cmd[idx])) break;
        },
    }
    return idx;
}

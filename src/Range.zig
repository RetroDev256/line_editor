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

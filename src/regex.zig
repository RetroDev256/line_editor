const std = @import("std");
const misc = @import("misc.zig");
const Range = @import("Range.zig");

// TODO:
// (stuff) matches the regexp stuff
// [atom_a-atom_b...] matches any atom inclusive in atom_a-atom_b, or ...
// [atom_aatom_batom_c...] matches any atom_a, atom_b, atom_c...

// This regex matching function has the following features:

// c matches any literal character c
// . matches any single character
// ^ matches the beginning of the input string
// $ matches the end of the input string
// * matches zero or more occurrences of the previous character
// + matches one or more occurrences of the previous character
// ? matches zero or one occurences of the previous character
// \ matches the following symbol literally, except:
// \t matches tab
// \c matches control codes
// \p matches printable characters
// \s matches whitespace
// \l matches lowercase
// \u matches uppercase
// \a matches alphabetic
// \n matches alphanumeric
// \w matches words (alphanumeric + '_')
// \h matches hex digits
// \d matches decimal digits

// deals with ^ and initial position of the match in text
pub fn match(regexp: []const u8, text: []const u8) !?Range {
    if (regexp.len == 0) {
        return .{ .start = 0, .length = 0 };
    } else if (regexp[0] == '^') {
        if (try matchHere(regexp[1..], text)) |length| {
            return .{ .start = 0, .length = length };
        }
    } else for (0..text.len + 1) |index| {
        if (try matchHere(regexp, text[index..])) |length| {
            return .{ .start = index, .length = length };
        }
    }
    return null;
}

const AtomError = error{ NoAtom, InvalidHexit };

const Atom = union(enum) {
    literal: u8, // \xdd, or otherwise
    any, // .
    tab, // \t
    control, // \c
    print, // \p
    white, // \s
    lower, // \l
    upper, // \u
    alpha, // \a
    alphanum, // \n
    word, // \w
    hex, // \h
    digit, // \d

    pub fn init(regexp: []const u8) AtomError!struct { Atom, usize } {
        if (regexp.len > 0) {
            if (regexp[0] == '.') return .{ .any, 1 };
            if (regexp[0] == '\\' and regexp.len > 1) {
                switch (regexp[1]) {
                    't' => return .{ .tab, 2 },
                    'a' => return .{ .alpha, 2 },
                    'n' => return .{ .alphanum, 2 },
                    'w' => return .{ .word, 2 },
                    'c' => return .{ .control, 2 },
                    'd' => return .{ .digit, 2 },
                    'h' => return .{ .hex, 2 },
                    'l' => return .{ .lower, 2 },
                    'p' => return .{ .print, 2 },
                    'u' => return .{ .upper, 2 },
                    's' => return .{ .white, 2 },
                    'x' => if (regexp.len > 3) {
                        const low = try misc.parseHexit(regexp[3]);
                        const high = try misc.parseHexit(regexp[2]);
                        const atom = .{ .literal = high * 16 + low };
                        return .{ atom, 4 };
                    },
                    else => {
                        const atom = .{ .literal = regexp[1] };
                        return .{ atom, 2 };
                    },
                }
            }
            const atom = .{ .literal = regexp[0] };
            return .{ atom, 1 };
        }
        return error.NoAtom;
    }
    pub fn match(atom: Atom, c: u8) bool {
        return switch (atom) {
            .literal => |lit| c == lit,
            .any => true,
            .tab => c == '\t',
            .control => switch (c) {
                0x00...0x1F, 0x7F => true,
                else => false,
            },
            .print => switch (c) {
                0x20...0x7E => true,
                else => false,
            },
            .white => switch (c) {
                ' ', '\t', '\n', '\r', 0x0B, 0x0C => true,
                else => false,
            },
            .lower => switch (c) {
                'a'...'z' => true,
                else => false,
            },
            .upper => switch (c) {
                'A'...'Z' => true,
                else => false,
            },
            .alpha => switch (c) {
                'A'...'Z', 'a'...'z' => true,
                else => false,
            },
            .alphanum => switch (c) {
                '0'...'9', 'A'...'Z', 'a'...'z' => true,
                else => false,
            },
            .word => switch (c) {
                '0'...'9', 'A'...'Z', 'a'...'z', '_' => true,
                else => false,
            },
            .hex => switch (c) {
                '0'...'9', 'A'...'F', 'a'...'f' => true,
                else => false,
            },
            .digit => switch (c) {
                '0'...'9' => true,
                else => false,
            },
        };
    }
};

// main recursive nest
fn matchHere(regexp: []const u8, text: []const u8) AtomError!?usize {
    if (regexp.len == 0) return 0;
    // from now on regexp.len >= 1
    const atom, const atom_len = try Atom.init(regexp);
    if (regexp[atom_len..].len > 0) {
        switch (regexp[atom_len]) {
            '?' => return try matchMany(regexp[atom_len + 1 ..], text, atom, 0, 1),
            '+' => return try matchMany(regexp[atom_len + 1 ..], text, atom, 1, null),
            '*' => return try matchMany(regexp[atom_len + 1 ..], text, atom, 0, null),
            else => {},
            // TODO
            //if (regexp[1] == '{') {
            //    const rep_a_len = misc.parseNumStrLen(regexp[2..]);
            //    const rep_a_str = regexp[2..][0..rep_a_len];
            //    const rep_a = try misc.parseUsize(rep_a_str);
            //},
        }
    } else if (regexp[0] == '$') { // regexp.len == 1
        if (text.len == 0) {
            return 0;
        } else {
            return null;
        }
    }
    return try matchMany(regexp[atom_len..], text, atom, 1, 1);
}

fn matchMany(regexp: []const u8, text: []const u8, atom: Atom, min: usize, maybe_max: ?usize) !?usize {
    // not possible to match the minimum number of times
    if (min > text.len) return null;
    // make sure we match the minimum number of times
    for (0..min) |offset| {
        if (!atom.match(text[offset])) {
            return null;
        }
    }
    // greedy-seek maximum possible matches
    const var_text = text[min..];
    const true_limit = blk: {
        if (maybe_max) |max| {
            break :blk @min(var_text.len, max - min);
        } else {
            break :blk var_text.len;
        }
    };
    const limit = blk: {
        for (0..true_limit) |index| {
            if (!atom.match(var_text[index])) {
                break :blk index;
            }
        }
        break :blk true_limit;
    };
    // back-track attempt matching
    for (0..limit + 1) |rev_idx| {
        const index = limit - rev_idx;
        if (try matchHere(regexp, var_text[index..])) |length| {
            return min + index + length;
        }
    }
    return null;
}

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "regex implementation" {
    // Literal Character Matching
    try expectEqual(Range.init(0, 1), try match("a", "a"));
    try expectEqual(null, try match("b", "a"));

    // Dot (.) Matching Any Single Character
    try expectEqual(Range.init(0, 1), try match(".", "a"));
    try expectEqual(Range.init(0, 1), try match(".", "1"));
    try expectEqual(null, try match(".", ""));

    // Caret (^) Matching the Beginning of the Input String
    try expectEqual(Range.init(0, 1), try match("^a", "abc"));
    try expectEqual(null, try match("^b", "abc"));

    // Dollar Sign ($) Matching the End of the Input String
    try expectEqual(Range.init(2, 1), try match("a$", "cba"));
    try expectEqual(null, try match("b$", "cba"));

    // Star (*) Matching Zero or More Occurrences of the Previous Character
    try expectEqual(Range.init(0, 3), try match("a*", "aaa"));
    try expectEqual(Range.init(0, 0), try match("a*", "b"));
    try expectEqual(Range.init(0, 0), try match("a*", ""));

    // Plus (+) Matching One or More Occurrences of the Previous Character
    try expectEqual(Range.init(0, 3), try match("a+", "aaa"));
    try expectEqual(null, try match("a+", "b"));
    try expectEqual(null, try match("a+", ""));

    // Question Mark (?) Matching Zero or One Occurrences of the Previous Character
    try expectEqual(Range.init(0, 1), try match("a?", "a"));
    try expectEqual(Range.init(0, 0), try match("a?", "b"));
    try expectEqual(Range.init(0, 0), try match("a?", ""));
    try expectEqual(null, try match("dc?a", "dba"));

    // Escape Sequences
    try expectEqual(Range.init(0, 1), try match("\\\\", "\\"));
    try expectEqual(Range.init(0, 1), try match("\\t", "\t"));
    try expectEqual(null, try match("\\t", "a"));

    // Control Character (\c)
    try expectEqual(Range.init(0, 1), try match("\\c", "\x1F"));
    try expectEqual(null, try match("\\c", "A"));

    // Whitespace (\s)
    try expectEqual(Range.init(0, 1), try match("\\s", " "));
    try expectEqual(Range.init(0, 1), try match("\\s", "\t"));
    try expectEqual(null, try match("\\s", "A"));

    // Digit (\d)
    try expectEqual(Range.init(0, 1), try match("\\d", "1"));
    try expectEqual(null, try match("\\d", "a"));

    // Word (\w)
    try expectEqual(Range.init(0, 1), try match("\\w", "A"));
    try expectEqual(Range.init(0, 1), try match("\\w", "1"));
    try expectEqual(Range.init(0, 1), try match("\\w", "_"));
    try expectEqual(null, try match("\\w", "$"));

    // Hexadecimal Matching
    try expectEqual(Range.init(0, 1), try match("\\x41", "A"));
    try expectEqual(null, try match("\\x41", "B"));
    try expectError(error.InvalidHexit, match("\\xG1", "A")); // Invalid Hex

    // Complex Patterns
    try expectEqual(Range.init(0, 5), try match("a*b", "aaaab"));
    try expectEqual(Range.init(0, 1), try match("a*b", "b"));
    try expectEqual(Range.init(0, 8), try match(".*", "anything"));
    try expectEqual(Range.init(0, 0), try match(".*", ""));

    // Start and End Anchors
    try expectEqual(Range.init(0, 1), try match("^a$", "a"));
    try expectEqual(null, try match("^a$", "b"));
    try expectEqual(Range.init(0, 3), try match("^abc$", "abc"));
    try expectEqual(null, try match("^abc$", "abcd"));
    try expectEqual(null, try match("^abc$", "zabc"));

    // Escaped Characters in Complex Patterns
    try expectEqual(Range.init(0, 3), try match("\\.\\*\\?", ".*?"));
    try expectEqual(Range.init(0, 4), try match("\\^\\$\\+\\*", "^$+*"));

    // Escaped Metacharacters
    try expectEqual(Range.init(0, 1), try match("\\^", "^"));
    try expectEqual(Range.init(0, 1), try match("\\$", "$"));
    try expectEqual(Range.init(0, 1), try match("\\*", "*"));
    try expectEqual(Range.init(0, 1), try match("\\+", "+"));
    try expectEqual(Range.init(0, 1), try match("\\?", "?"));

    // Matching Empty String
    try expectEqual(Range.init(0, 0), try match("", "anything"));
    try expectEqual(Range.init(0, 0), try match("^$", ""));

    // Test with Multiple Matches
    try expectEqual(Range.init(0, 2), try match("a+b", "ab"));
    try expectEqual(Range.init(0, 4), try match("a+b", "aaab"));
    try expectEqual(null, try match("a+b", "b"));

    // Boundary Conditions
    try expectEqual(Range.init(0, 3), try match("^abc$", "abc"));
    try expectEqual(null, try match("^abc$", "ab"));
    try expectEqual(null, try match("^abc$", "abcd"));
}

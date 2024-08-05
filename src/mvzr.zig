const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const XXX = false;
const one: u64 = 1;
pub const MAX_REGEX_OPS = 64;

pub const MAX_CHAR_SETS = 8;
const RegexType = enum(u5) {
    unused,
    begin,
    end,
    left,
    right,
    word_break,
    not_word_break,
    alt,
    optional,
    star,
    plus,
    lazy_optional,
    lazy_star,
    lazy_plus,
    eager_optional,
    eager_star,
    eager_plus,
    some,
    up_to,
    eager_up_to,
    dot,
    char,
    class,
    not_class,
    digit,
    not_digit,
    alpha,
    not_alpha,
    whitespace,
    not_whitespace,
};
pub const RegOp = union(RegexType) {
    unused: void,
    begin: void,
    end: void,
    left: void,
    right: void,
    word_break: void,
    not_word_break: void,
    alt: void,
    optional: void,
    star: void,
    plus: void,
    lazy_optional: void,
    lazy_star: void,
    lazy_plus: void,
    eager_optional: void,
    eager_star: void,
    eager_plus: void,
    some: u8,
    up_to: u8,
    eager_up_to: u8,
    dot: void,
    char: u8,
    class: u8,
    not_class: u8,
    digit: void,
    not_digit: void,
    alpha: void,
    not_alpha: void,
    whitespace: void,
    not_whitespace: void,
};
pub const CharSet = struct {
    low: u64 = 0,
    hi: u64 = 0,
};
const OpMatch = struct {
    j: []const RegOp,
    i: usize,
};
const Regex: type = SizedRegex(MAX_REGEX_OPS, MAX_CHAR_SETS);
pub fn SizedRegex(ops: comptime_int, char_sets: comptime_int) type {
    return struct {
        patt: [ops]RegOp = [1]RegOp{.{ .unused = {} }} ** ops,
        sets: [char_sets]CharSet = [1]CharSet{.{ .low = 0, .hi = 0 }} ** char_sets,
        const SizedRegexT = @This();
        pub fn compile(patt: []const u8) ?SizedRegexT {
            return compileRegex(SizedRegexT, patt);
        }
        pub fn match(regex: *const SizedRegexT, haystack: []const u8) ?Match {
            if (haystack.len == 0) return null;
            const maybe_matched = regex.matchInternal(haystack);
            if (maybe_matched) |m| {
                const m1 = m[0];
                const m2 = m[1];
                return Match{
                    .slice = haystack[m1..m2],
                    .start = m1,
                    .end = m2,
                };
            } else {
                return null;
            }
        }
        pub fn isMatch(regex: *const SizedRegexT, haystack: []const u8) bool {
            const maybe_matched = regex.matchInternal(haystack);
            if (maybe_matched) |_| {
                return true;
            } else {
                return false;
            }
        }

        pub fn toOwnedRegex(regex: *const SizedRegexT, allocator: std.mem.Allocator) !*const SizedRegexT {
            const heap_regex = try allocator.create(SizedRegexT);
            heap_regex.* = regex.*;
            return heap_regex;
        }

        pub fn iterator(regex: *const SizedRegexT, haystack: []const u8) RegexIterator {
            return RegexIterator{
                .regex = regex,
                .haystack = haystack,
            };
        }
        pub const RegexIterator = struct {
            regex: *const SizedRegexT,
            idx: usize = 0,
            haystack: []const u8,
            pub fn next(iter: *RegexIterator) ?Match {
                const maybe_match = iter.regex.match(iter.haystack[iter.idx..]);
                if (maybe_match) |m| {
                    const m_start = m.start + iter.idx;
                    const m_end = m.end + iter.idx;
                    iter.idx += m.end;
                    return Match{
                        .slice = m.slice,
                        .start = m_start,
                        .end = m_end,
                    };
                } else {
                    return null;
                }
            }
        };
        fn matchInternal(regex: *const SizedRegexT, haystack: []const u8) ?struct { usize, usize } {
            const end = regex.findPatternEnd();
            const patt = regex.patt[0..end];
            switch (patt[0]) {
                .begin => {
                    const matched = matchOuterPattern(patt[1..], &regex.sets, haystack, 0);
                    if (matched) |m| {
                        return .{ 0, m.i };
                    } else return null;
                },
                else => {
                    var matchlen: usize = 0;
                    while (matchlen < haystack.len) : (matchlen += 1) {
                        const matched = matchOuterPattern(patt, &regex.sets, haystack, matchlen);
                        if (matched) |m| {
                            return .{ matchlen, m.i };
                        }
                    }
                    return null;
                },
            }
        }
        fn findPatternEnd(regex: *const SizedRegexT) usize {
            const patt = regex.patt;
            for (0..patt.len) |i| {
                if (patt[i] == .unused) {
                    return i;
                }
            }
            return patt.len;
        }
    };
}

pub const Match = struct {
    slice: []const u8,
    start: usize,
    end: usize,

    pub fn toOwnedMatch(matched: Match, allocator: std.mem.Allocator) !Match {
        const new_slice = try allocator.dupe(u8, matched.slice);
        return Match{
            .slice = new_slice,
            .start = matched.start,
            .end = matched.end,
        };
    }
    pub fn deinit(matched: Match, allocator: std.mem.Allocator) void {
        allocator.free(matched.slice);
    }
    pub fn format(
        matched: Match,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("[{d}..{d}]: \"{}\"", .{
            matched.start,
            matched.end,
            std.zig.fmtEscapes(matched.slice),
        });
    }
};
pub fn match(haystack: []const u8, pattern: []const u8) ?Match {
    const maybe_regex = compile(pattern);
    if (maybe_regex) |regex| {
        return regex.match(haystack);
    } else {
        return null;
    }
}

fn matchOuterPattern(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) ?OpMatch {
    if (findAlt(patt, 0)) |_| {
        var remaining_patt = patt;
        while (true) {
            const this_match = matchAlt(remaining_patt, sets, haystack, i);
            if (this_match) |m1| {
                return OpMatch{ .i = m1.i, .j = patt[0..0] };
            } else {
                const maybe_next = maybeAlt(remaining_patt);
                if (maybe_next) |next_patt| {
                    remaining_patt = remaining_patt[next_patt.len + 1 ..];
                } else {
                    return null;
                }
            }
        }
    } else {
        return matchPattern(patt, sets, haystack, i);
    }
}
fn matchPattern(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i_in: usize) ?OpMatch {
    var i: usize = i_in;
    var this_patt = patt;
    dispatch: while (this_patt.len != 0) {
        if (i == haystack.len) {
            switch (this_patt[0]) {
                .word_break, .not_word_break => {},
                .optional,
                .star,
                .lazy_optional,
                .lazy_star,
                .eager_optional,
                .eager_star,
                .up_to,
                .eager_up_to,
                .end,
                => {
                    this_patt = nextPattern(this_patt);
                    continue :dispatch;
                },
                .left => {
                    if (groupAcceptsEmpty(this_patt)) {
                        this_patt = nextPattern(this_patt);
                        continue :dispatch;
                    } else {
                        return null;
                    }
                },
                .begin, .plus, .lazy_plus, .eager_plus, .some, .dot, .class, .not_class, .digit, .not_digit, .alpha, .not_alpha, .whitespace, .not_whitespace, .char => return null,
                .right, .alt, .unused => unreachable,
            }
        }
        const maybe_match = switch (this_patt[0]) {
            .dot,
            .class,
            .not_class,
            .digit,
            .not_digit,
            .alpha,
            .not_alpha,
            .whitespace,
            .not_whitespace,
            .char,
            => matchOne(this_patt, sets, haystack, i),
            .optional => matchOptional(this_patt[1..], sets, haystack, i),
            .star => matchStar(this_patt[1..], sets, haystack, i),
            .plus => matchPlus(this_patt[1..], sets, haystack, i),
            .lazy_optional => matchLazyOptional(this_patt[1..], sets, haystack, i),
            .lazy_star => matchLazyStar(this_patt[1..], sets, haystack, i),
            .lazy_plus => matchLazyPlus(this_patt[1..], sets, haystack, i),
            .eager_optional => matchEagerOptional(this_patt[1..], sets, haystack, i),
            .eager_star => matchEagerStar(this_patt[1..], sets, haystack, i),
            .eager_plus => matchEagerPlus(this_patt[1..], sets, haystack, i),
            .some => matchSome(this_patt, sets, haystack, i),
            .up_to => matchUpTo(this_patt, sets, haystack, i),
            .eager_up_to => matchEagerUpTo(this_patt, sets, haystack, i),
            .left => matchGroup(this_patt, sets, haystack, i),
            .word_break => matchWordBreak(this_patt, sets, haystack, i),
            .not_word_break => matchNotWordBreak(this_patt, sets, haystack, i),
            .end => {
                if (i + 1 == haystack.len and haystack[i] == '\n') {
                    return OpMatch{ .i = i + 1, .j = patt[0..0] };
                } else if (i + 2 == haystack.len and haystack[i] == '\r' and haystack[i + 1] == '\n') {
                    return OpMatch{ .i = i + 2, .j = patt[0..0] };
                }
                return null;
            },
            .unused, .alt, .right, .begin => unreachable,
        };
        if (maybe_match) |m| {
            this_patt = m.j;
            i = m.i;
            assert(!(i > haystack.len));
        } else {
            return null;
        }
    }
    if (this_patt.len == 0)
        return OpMatch{ .i = i, .j = this_patt }
    else
        return null;
}
const ascii = std.ascii;
inline fn isWordChar(c: u8) bool {
    return ascii.isAlphanumeric(c) or c == '_';
}
fn matchOne(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) ?OpMatch {
    if (matchOneByte(patt[0], sets, haystack[i])) {
        return OpMatch{ .i = 1 + i, .j = patt[1..] };
    } else {
        return null;
    }
}
fn matchOneByte(op: RegOp, sets: []const CharSet, c: u8) bool {
    return switch (op) {
        .dot => true,
        .class => |c_off| matchClass(sets[c_off], c),
        .not_class => |c_off| !matchClass(sets[c_off], c),
        .digit => ascii.isDigit(c),
        .not_digit => !ascii.isDigit(c),
        .alpha => isWordChar(c),
        .not_alpha => !isWordChar(c),
        .whitespace => ascii.isWhitespace(c),
        .not_whitespace => !ascii.isWhitespace(c),
        .char => |ch| (c == ch),
        else => unreachable,
    };
}
fn matchStar(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i_in: usize) OpMatch {
    var i = i_in;
    const this_patt = thisPattern(patt);
    while (matchPattern(this_patt, sets, haystack, i)) |m| {
        i = m.i;
        assert(!(i > haystack.len));

        if (i == haystack.len or i == i_in) break;
    }
    const next_patt = nextPattern(patt);
    if (next_patt.len == 0) {
        return OpMatch{ .i = i, .j = next_patt };
    }
    if (i == haystack.len) {
        if (next_patt[0] == .end) {
            return OpMatch{ .i = i, .j = next_patt };
        } else {
            i -= 1;
        }
    }
    const maybe_next = matchPattern(next_patt, sets, haystack, i);
    if (maybe_next) |m2| {
        return m2;
    }

    i = if (i == i_in) i_in else (i - 1);
    while (true) {
        const try_next = matchPattern(next_patt, sets, haystack, i);
        if (try_next) |m2| {
            if (matchPattern(this_patt, sets, haystack, i)) |_| {
                return m2;
            }
        }
        if (i == i_in) break;
        i -= 1;
    }
    return OpMatch{ .i = i_in, .j = nextPattern(next_patt) };
}
fn matchPlus(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) ?OpMatch {
    const this_patt = thisPattern(patt);
    const first_m = matchPattern(this_patt, sets, haystack, i);
    if (first_m == null) return null;
    const m1 = first_m.?;

    if (m1.i == haystack.len) return OpMatch{ .i = m1.i, .j = nextPattern(patt) };
    const m2 = matchStar(patt, sets, haystack, m1.i);

    if (m2.i == m1.i) {
        return OpMatch{ .i = m1.i, .j = nextPattern(patt) };
    } else {
        return m2;
    }
}
fn matchOptional(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i_in: usize) ?OpMatch {
    const this_patt = thisPattern(patt);
    const maybe_m = matchPattern(this_patt, sets, haystack, i_in);
    if (maybe_m) |m1| {
        const next_patt = nextPattern(patt);
        var i = m1.i;
        if (next_patt.len != 0) {
            if (i == haystack.len and next_patt[0] != .end) {
                i = i_in;
            }
            const maybe_next = matchPattern(next_patt, sets, haystack, i);
            if (maybe_next) |m2| {
                return m2;
            } else {
                return matchPattern(next_patt, sets, haystack, i_in);
            }
        } else {
            return m1;
        }
    } else {
        return OpMatch{ .i = i_in, .j = nextPattern(patt) };
    }
}
fn matchEagerOptional(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) OpMatch {
    const this_patt = thisPattern(patt);
    const maybe_m = matchPattern(this_patt, sets, haystack, i);
    if (maybe_m) |m| {
        return OpMatch{ .i = m.i, .j = nextPattern(patt) };
    } else {
        return OpMatch{ .i = i, .j = nextPattern(patt) };
    }
}
fn matchLazyStar(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i_in: usize) OpMatch {
    const this_patt = thisPattern(patt);
    const next_patt = nextPattern(patt);

    var match_first = if (next_patt.len != 0)
        matchPattern(next_patt, sets, haystack, i_in)
    else
        null;
    if (match_first) |m| {
        return m;
    }
    var i: usize = i_in;

    match_first = matchPattern(this_patt, sets, haystack, i);
    if (match_first) |m| {
        i = m.i;
    }

    while (true) {
        if (i == haystack.len)
            return OpMatch{ .i = i, .j = next_patt };

        const match_theirs = matchPattern(next_patt, sets, haystack, i);
        if (match_theirs) |m1| {
            return m1;
        } else {
            const match_ours = matchPattern(this_patt, sets, haystack, i);
            if (match_ours) |m2| {
                i = m2.i;
            } else {
                return OpMatch{ .i = i, .j = next_patt };
            }
        }
    }
}
fn matchLazyPlus(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) ?OpMatch {
    const this_patt = thisPattern(patt);
    const first_m = matchPattern(this_patt, sets, haystack, i);
    if (first_m == null) return null;
    const m1 = first_m.?;
    if (m1.i == haystack.len) return OpMatch{ .i = m1.i, .j = nextPattern(patt) };
    const m2 = matchLazyStar(patt, sets, haystack, m1.i);

    return m2;
}
fn matchLazyOptional(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) ?OpMatch {
    const maybe_match = matchPattern(nextPattern(patt), sets, haystack, i);
    if (maybe_match) |m| {
        return m;
    }
    return matchEagerOptional(patt, sets, haystack, i);
}
fn matchEagerPlus(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) ?OpMatch {
    const this_patt = thisPattern(patt);
    const first_m = matchPattern(this_patt, sets, haystack, i);
    if (first_m == null) return null;
    const m1 = first_m.?;
    if (m1.i == haystack.len) return OpMatch{ .i = m1.i, .j = nextPattern(patt) };
    const m2 = matchEagerStar(patt, sets, haystack, m1.i);
    return m2;
}
fn matchEagerStar(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i_in: usize) OpMatch {
    const this_patt = thisPattern(patt);
    var i = i_in;
    while (matchPattern(this_patt, sets, haystack, i)) |m| {
        i = m.i;
        assert(!(i > haystack.len));
        if (i == haystack.len) break;
    }
    return OpMatch{ .i = i, .j = nextPattern(patt) };
}
fn matchSome(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i_in: usize) ?OpMatch {
    var count = patt[0].some;
    var i = i_in;
    const this_patt = if (patt[1] == .up_to or patt[1] == .eager_up_to or patt[1] == .star)
        thisPattern(patt[2..])
    else
        thisPattern(patt[1..]);
    while (count > 0) : (count -= 1) {
        const matched = matchPattern(this_patt, sets, haystack, i);
        if (matched) |m| {
            i = m.i;
        } else {
            return null;
        }
    }
    if (patt[1] == .eager_up_to or patt[1] == .up_to or patt[1] == .star) {
        return OpMatch{ .i = i, .j = patt[1..] };
    } else {
        return OpMatch{ .i = i, .j = nextPattern(patt) };
    }
}
fn matchUpTo(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) OpMatch {
    const more_match = matchUpToInner(patt[1..], sets, haystack, i, patt[0].up_to);
    if (more_match) |m|
        return m
    else
        return OpMatch{ .i = i, .j = nextPattern(patt) };
}
fn matchUpToInner(
    patt: []const RegOp,
    sets: []const CharSet,
    haystack: []const u8,
    i_in: usize,
    count: usize,
) ?OpMatch {
    if (count == 1) {
        const opt = matchOptional(patt, sets, haystack, i_in);

        return opt;
    }
    const this_patt = thisPattern(patt);
    const maybe_m = matchPattern(this_patt, sets, haystack, i_in);
    if (maybe_m) |m1| {
        const next_patt = nextPattern(patt);
        var i = m1.i;
        var maybe_next: ?OpMatch = null;
        if (next_patt.len != 0) {
            if (i == haystack.len and next_patt[0] != .end) {
                i = i_in;
            }
            maybe_next = matchPattern(next_patt, sets, haystack, i);
            if (maybe_next) |m2| {
                if (m2.i == haystack.len) {
                    return m2;
                }
            }
        }
        const maybe_rest = matchUpToInner(patt, sets, haystack, m1.i, count - 1);
        if (maybe_rest) |m3| {
            return m3;
        }

        if (maybe_next) |m2| {
            return m2;
        } else {
            return null;
        }
    } else {
        return null;
    }
}
fn matchEagerUpTo(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i_in: usize) OpMatch {
    const this_patt = thisPattern(patt[1..]);
    const first_match = matchPattern(this_patt, sets, haystack, i_in);
    if (first_match == null) return OpMatch{ .i = 0, .j = nextPattern(patt) };

    var latest_match: OpMatch = first_match.?;
    var count = patt[0].eager_up_to - 1;
    while (count > 0) : (count -= 1) {
        const next_match = matchPattern(this_patt, sets, haystack, latest_match.i);
        if (next_match) |m| {
            latest_match = m;
        } else {
            break;
        }
    }
    return OpMatch{ .i = latest_match.i, .j = nextPattern(patt) };
}
fn matchGroup(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) ?OpMatch {
    const inner_patt = sliceGroup(patt);

    if (inner_patt.len == 0) {
        return OpMatch{ .i = i, .j = nextPattern(patt) };
    }

    const next_patt = nextPattern(patt);

    if (!hasAlt(patt)) {
        const maybe_match = matchPattern(inner_patt, sets, haystack, i);
        if (maybe_match) |m| {
            return OpMatch{ .i = m.i, .j = next_patt };
        } else {
            return null;
        }
    }

    if (next_patt.len == 0) {
        const our_match = matchAlt(inner_patt, sets, haystack, i);
        if (our_match) |m| {
            return OpMatch{ .i = m.i, .j = next_patt };
        }
    }
    var remaining_patt = inner_patt;
    while (remaining_patt.len != 0) {
        const this_match = matchAlt(remaining_patt, sets, haystack, i);
        if (this_match) |m1| {
            const next_match = matchPattern(next_patt, sets, haystack, m1.i);
            if (next_match) |m2| {
                return m2;
            } else {
                remaining_patt = m1.j;
            }
        } else {
            return null;
        }
    }
    return null;
}
fn matchWordBreak(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) ?OpMatch {
    if (i == haystack.len) {
        if (isWordChar(haystack[i - 1])) {
            return OpMatch{ .i = i, .j = nextPattern(patt) };
        } else {
            return null;
        }
    }
    const this_is_word = isWordChar(haystack[i]);
    if (i == 0) {
        if (this_is_word) {
            return OpMatch{ .i = i, .j = nextPattern(patt) };
        } else {
            return null;
        }
    }
    const was_word = isWordChar(haystack[i - 1]);

    if (!was_word and this_is_word) {
        return OpMatch{ .i = i, .j = nextPattern(patt) };
    } else if (was_word and !this_is_word) {
        return OpMatch{ .i = i, .j = patt[1..] };
    } else {
        return null;
    }

    _ = sets;
}
fn matchNotWordBreak(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) ?OpMatch {
    const wb = matchWordBreak(patt, sets, haystack, i);
    if (wb) |_| {
        return null;
    } else {
        return OpMatch{ .i = i, .j = patt[1..] };
    }
}
fn matchAlt(patt: []const RegOp, sets: []const CharSet, haystack: []const u8, i: usize) ?OpMatch {
    const maybe_first = maybeAlt(patt);
    if (maybe_first) |first_patt| {
        const one_m = matchPattern(first_patt, sets, haystack, i);
        if (one_m) |m1| {
            return OpMatch{ .i = m1.i, .j = patt[first_patt.len + 1 ..] };
        } else {
            return matchAlt(patt[first_patt.len + 1 ..], sets, haystack, i);
        }
    } else {
        return matchPattern(patt, sets, haystack, i);
    }
}
fn matchClass(set: CharSet, c: u8) bool {
    switch (c) {
        0...63 => {
            const cut_c: u6 = @truncate(c);
            return (set.low | (one << cut_c)) == set.low;
        },
        64...127 => {
            const cut_c: u6 = @truncate(c);
            return (set.hi | (one << cut_c)) == set.hi;
        },
        else => return false,
    }
}
fn nextPatternForSome(patt: []const RegOp) usize {
    switch (patt[0]) {
        .left => return findRight(patt, 0) + 1,
        .star,
        .optional,
        .plus,
        .lazy_star,
        .lazy_optional,
        .lazy_plus,
        .eager_star,
        .eager_plus,
        .eager_optional,
        .up_to,
        => return 1 + nextPatternForSome(patt[1..]),
        .some => {
            if (patt[1] == .star or patt[1] == .up_to) {
                return 2 + nextPatternForSome(patt[2..]);
            } else {
                return 1 + nextPatternForSome(patt[1..]);
            }
        },
        .unused => return 0,
        else => return 1,
    }
}
fn nextPattern(patt: []const RegOp) []const RegOp {
    switch (patt[0]) {
        .unused, .begin => @panic("Internal error, .unused or .begin encountered"),
        .right => @panic("Internal error, encountered .right"),
        .left => return patternAfterGroup(patt),
        .alt,
        .optional,
        .star,
        .plus,
        .lazy_optional,
        .lazy_star,
        .lazy_plus,
        .eager_optional,
        .eager_star,
        .eager_plus,
        .some,
        .up_to,
        .eager_up_to,
        => return nextPattern(patt[1..]),
        .word_break,
        .not_word_break,
        .end,
        .dot,
        .char,
        .class,
        .not_class,
        .digit,
        .not_digit,
        .alpha,
        .not_alpha,
        .whitespace,
        .not_whitespace,
        => return patt[1..],
    }
}
fn patternAfterGroup(patt: []const RegOp) []const RegOp {
    assert(patt[0] == .left);
    var j: usize = 1;
    var pump: usize = 0;
    while (true) : (j += 1) {
        switch (patt[j]) {
            .right => {
                if (pump == 0) {
                    return patt[j + 1 ..];
                } else {
                    pump -= 1;
                }
            },
            .left => pump += 1,
            else => {},
        }
    }
    unreachable;
}
fn thisPattern(patt: []const RegOp) []const RegOp {
    switch (patt[0]) {
        .left => return thisGroup(patt),

        .some => return patt[0..nextPatternForSome(patt)],
        else => return patt[0..1],
    }
}
fn thisGroup(patt: []const RegOp) []const RegOp {
    assert(patt[0] == .left);
    var j: usize = 1;
    var pump: usize = 0;
    while (true) : (j += 1) {
        switch (patt[j]) {
            .right => {
                if (pump == 0) {
                    return patt[0 .. j + 1];
                } else {
                    pump -= 1;
                }
            },
            .left => pump += 1,
            else => {},
        }
    }
    unreachable;
}
fn patternAcceptsEmpty(patt: []const RegOp) bool {
    switch (patt[0]) {
        .optional,
        .star,
        .lazy_optional,
        .lazy_star,
        .eager_optional,
        .eager_star,
        .up_to,
        .end,
        => return true,
        .left => {
            if (groupAcceptsEmpty(patt)) {
                return true;
            } else {
                return false;
            }
        },
        else => return false,
    }
}
fn groupAcceptsEmpty(patt: []const RegOp) bool {
    if (!hasAlt(patt)) {
        const inner = sliceGroup(patt);
        if (inner.len == 0) {
            return true;
        } else return patternAcceptsEmpty(inner);
    }
    var inner_patt = sliceGroup(patt);
    while (true) {
        const maybe_this_patt = maybeAlt(inner_patt);
        if (maybe_this_patt) |this_patt| {
            if (this_patt.len == 0) return true;
            if (patternAcceptsEmpty(this_patt)) {
                return true;
            } else {
                inner_patt = inner_patt[this_patt.len + 1 ..];
                if (inner_patt.len == 0) return true;
            }
        } else {
            return (patternAcceptsEmpty(inner_patt));
        }
    }
    unreachable;
}
fn findPatternEnd(regex: *const Regex) usize {
    const patt = regex.patt;
    for (0..patt.len) |i| {
        if (patt[i] == .unused) {
            return i;
        }
    }
    return patt.len;
}
fn maybeAlt(patt: []const RegOp) ?[]const RegOp {
    const alt_at = findAlt(patt, 0);
    if (alt_at) |at| {
        return patt[0..at];
    } else return null;
}
fn hasAlt(patt: []const RegOp) bool {
    assert(patt[0] == .left);
    var pump: usize = 0;
    var j: usize = 1;
    while (j < patt.len - 1) : (j += 1) {
        switch (patt[j]) {
            .left => pump += 1,
            .right => {
                if (pump == 0)
                    return true
                else
                    pump -= 1;
            },
            .alt => {
                if (pump == 0) return true;
            },
            else => {},
        }
    }
    return false;
}
fn sliceGroup(patt: []const RegOp) []const RegOp {
    assert(patt[0] == .left);
    var j: usize = 1;
    var pump: usize = 0;
    while (true) : (j += 1) {
        switch (patt[j]) {
            .right => {
                if (pump == 0) {
                    return patt[1..j];
                } else {
                    pump -= 1;
                }
            },
            .left => pump += 1,
            else => {},
        }
    }
    unreachable;
}
fn pattEnd(patt: []const RegOp) usize {
    var j: usize = 0;
    while (j < patt.len and patt[j] != .unused) : (j += 1) {}
    return j;
}
fn countAlt(patt: []const RegOp) usize {
    var pump: usize = 0;
    var alts: usize = 0;
    for (patt) |op| {
        switch (op) {
            .left => {
                pump += 1;
            },
            .right => {
                pump -= 1;
            },
            .alt => {
                if (pump == 0) {
                    alts += 1;
                }
            },
            else => {},
        }
    }
    return alts;
}
fn findAlt(patt: []const RegOp, j_in: usize) ?usize {
    var j = j_in;
    var pump: usize = 0;
    while (j < patt.len) : (j += 1) {
        switch (patt[j]) {
            .left => pump += 1,
            .right => pump -= 1,
            .alt => {
                if (pump == 0) return j;
            },
            else => {},
        }
    }
    return null;
}
fn findRight(patt: []const RegOp, j_in: usize) usize {
    var j = j_in;
    var pump: usize = 0;
    while (j < patt.len) : (j += 1) {
        if (patt[j] == .right and pump == 0)
            return j
        else
            continue;
        if (patt[j] == .left) pump += 1;
    }
    unreachable;
}

pub fn resourcesNeeded(comptime in: []const u8) struct { comptime_int, comptime_int } {
    const maybe_out = compileRegex(SizedRegex(4096, 257), in);
    var max_s: usize = 0;
    if (maybe_out) |out| {
        for (&out.patt, 0..) |op, i| {
            switch (op) {
                .class, .not_class => |s_off| {
                    max_s = @max(max_s, s_off);
                },
                .unused => {
                    return .{ i, max_s + 1 };
                },
                else => {},
            }
        }
    } else {
        return .{ 0, 0 };
    }
    return .{ 0, 0 };
}
fn prefixModifier(patt: []RegOp, j: usize, op: RegOp) bool {
    if (j == 0 or patt[j] == .begin) return false;
    var find_j = j - 1;

    switch (patt[find_j]) {
        .right => {
            find_j = beforePriorLeft(patt, find_j);
        },
        else => {},
    }

    if (find_j > 0) {
        switch (patt[find_j - 1]) {
            .alt,
            .plus,
            .lazy_optional,
            .lazy_star,
            .lazy_plus,
            .eager_optional,
            .eager_star,
            .eager_plus,
            .optional,
            => {
                return false;
            },
            .some => {
                if (op != .optional) {
                    return false;
                } else {
                    find_j -= 1;
                }
            },
            .star => {
                if (op != .some) {
                    return false;
                }
            },
            .up_to => {
                if (op == .optional) {
                    find_j -= 1;
                    if (find_j > 0 and patt[find_j - 1] == .some) {
                        find_j -= 1;
                    }
                } else if (op != .some) {
                    return false;
                }
            },
            else => {},
        }
    }
    var move_op = patt[find_j];
    if (op == .some and find_j > 0) {
        const prev_op = patt[find_j - 1];
        switch (prev_op) {
            .up_to, .eager_up_to, .star, .optional => {
                find_j -= 1;
                move_op = prev_op;
            },
            else => {},
        }
    }
    patt[find_j] = op;
    find_j += 1;
    while (move_op != .unused) : (find_j += 1) {
        const temp_op = patt[find_j];
        patt[find_j] = move_op;
        move_op = temp_op;
    }
    return true;
}
fn beforePriorLeft(patt: []RegOp, j: usize) usize {
    std.debug.assert(patt[j] == .right);
    var find_j = j - 1;
    var pump: usize = 0;
    while (find_j != 0) : (find_j -= 1) {
        switch (patt[find_j]) {
            .right => {
                pump += 1;
            },
            .left => {
                if (pump == 0)
                    break
                else
                    pump -= 1;
            },
            else => {},
        }
    }
    if (patt[find_j] != .left) @panic("throw here");
    return find_j;
}
inline fn countDigits(in: []const u8) usize {
    var i: usize = 0;
    while (i < in.len and ascii.isDigit(in[i])) : (i += 1) {}
    return i;
}
fn parseByte(in: []const u8) !struct { usize, u8 } {
    const d1 = countDigits(in);
    if (d1 == 0 or d1 >= 4) return error.BadString;
    const c1 = std.fmt.parseInt(u16, in[0..d1], 10) catch {
        return error.BadString;
    };
    if (c1 > 255) {
        return error.BadString;
    }
    return .{ d1, @intCast(c1) };
}
fn parseHex(in: []const u8) !u8 {
    var out_buf: [1]u8 = undefined;
    const b = try std.fmt.hexToBytes(&out_buf, in[0..2]);
    return b[0];
}
fn findSetIndex(sets: []const CharSet, set: CharSet, s: usize) u8 {
    const trunc_s: u8 = @truncate(s);
    var idx: u8 = 0;
    while (idx < trunc_s) : (idx += 1) {
        if (sets[idx].low == set.low and sets[idx].hi == set.hi) {
            return idx;
        }
    }
    return trunc_s;
}
pub fn compile(in: []const u8) ?Regex {
    return compileRegex(Regex, in);
}

fn compileRegex(RegexT: type, in: []const u8) ?RegexT {
    var out = RegexT{};
    var patt = &out.patt;
    const sets = &out.sets;

    var bad_string: bool = false;
    var i: usize = 0;
    var j: usize = 0;
    var s: u8 = 0;
    var pump: usize = 0;
    dispatch: while (i < in.len and j < patt.len) : ({
        j += 1;
        i += 1;
    }) {
        const c = in[i];
        switch (c) {
            '^' => {
                if (i != 0) {
                    bad_string = true;
                    break :dispatch;
                }
                patt[j] = RegOp{ .begin = {} };
            },
            '$' => {
                if (i + 1 < in.len) {
                    bad_string = true;
                    break :dispatch;
                }
                patt[j] = RegOp{ .end = {} };
            },
            '.' => {
                patt[j] = RegOp{ .dot = {} };
            },
            '*' => {
                if (i + 1 < in.len and in[i + 1] == '?') {
                    i += 1;
                    const ok = prefixModifier(patt, j, RegOp{ .lazy_star = {} });
                    if (!ok) {
                        bad_string = true;
                        break :dispatch;
                    }
                } else if (i + 1 < in.len and in[i + 1] == '+') {
                    i += 1;
                    const ok = prefixModifier(patt, j, RegOp{ .eager_star = {} });
                    if (!ok) {
                        bad_string = true;
                        break :dispatch;
                    }
                } else {
                    const ok = prefixModifier(patt, j, RegOp{ .star = {} });
                    if (!ok) {
                        bad_string = true;
                        break :dispatch;
                    }
                }
            },
            '?' => {
                if (i + 1 < in.len and in[i + 1] == '?') {
                    i += 1;
                    const ok = prefixModifier(patt, j, RegOp{ .lazy_optional = {} });
                    if (!ok) {
                        bad_string = true;
                        break :dispatch;
                    }
                } else if (i + 1 < in.len and in[i + 1] == '+') {
                    i += 1;
                    const ok = prefixModifier(patt, j, RegOp{ .eager_optional = {} });
                    if (!ok) {
                        bad_string = true;
                        break :dispatch;
                    }
                } else {
                    const ok = prefixModifier(patt, j, RegOp{ .optional = {} });
                    if (!ok) {
                        bad_string = true;
                        break :dispatch;
                    }
                }
            },
            '+' => {
                if (i + 1 < in.len and in[i + 1] == '?') {
                    i += 1;
                    const ok = prefixModifier(patt, j, RegOp{ .lazy_plus = {} });
                    if (!ok) {
                        bad_string = true;
                        break :dispatch;
                    }
                } else if (i + 1 < in.len and in[i + 1] == '+') {
                    i += 1;
                    const ok = prefixModifier(patt, j, RegOp{ .eager_plus = {} });
                    if (!ok) {
                        bad_string = true;
                        break :dispatch;
                    }
                } else {
                    const ok = prefixModifier(patt, j, RegOp{ .plus = {} });
                    if (!ok) {
                        bad_string = true;
                        break :dispatch;
                    }
                }
            },
            '{' => {
                i += 1;
                if (in[i] == ',') {
                    i += 1;
                    const d, const c1 = parseByte(in[i..]) catch {
                        bad_string = true;
                        break :dispatch;
                    };
                    i += d;
                    if (in[i] == '}') {
                        const ok = prefixModifier(patt, j, RegOp{ .up_to = c1 });
                        if (!ok) {
                            bad_string = true;
                            break :dispatch;
                        } else continue :dispatch;
                    } else {
                        bad_string = true;
                        break :dispatch;
                    }
                }
                const d1, const c1 = parseByte(in[i..]) catch {
                    patt[j] = RegOp{ .char = '}' };
                    continue :dispatch;
                };
                i += d1;
                if (in[i] == ',') {
                    i += 1;
                    if (in[i] == '}') {
                        var ok = prefixModifier(patt, j, RegOp{ .star = {} });
                        if (!ok) {
                            bad_string = true;
                            break :dispatch;
                        }
                        j += 1;
                        ok = prefixModifier(patt, j, RegOp{ .some = c1 });
                        if (!ok) {
                            bad_string = true;
                            break :dispatch;
                        }
                        continue :dispatch;
                    }
                    const d2, const c2 = parseByte(in[i..]) catch {
                        bad_string = true;
                        break :dispatch;
                    };
                    i += d2;
                    if (in[i] != '}') {
                        bad_string = true;
                        break :dispatch;
                    }
                    if (c1 > c2) {
                        bad_string = true;
                        break :dispatch;
                    }
                    const c_rest = c2 - c1;
                    if (i + 1 < in.len and in[i + 1] == '+') {
                        const ok = prefixModifier(patt, j, RegOp{ .eager_up_to = c_rest });
                        if (!ok) {
                            bad_string = true;
                            break :dispatch;
                        }
                        i += 1;
                    } else {
                        const ok = prefixModifier(patt, j, RegOp{ .up_to = c_rest });
                        if (!ok) {
                            bad_string = true;
                            break :dispatch;
                        }
                    }
                    j += 1;
                    const ok = prefixModifier(patt, j, RegOp{ .some = c1 });
                    if (!ok) {
                        bad_string = true;
                        break :dispatch;
                    }
                } else if (in[i] == '}') {
                    const ok = prefixModifier(patt, j, RegOp{ .some = c1 });
                    if (!ok) {
                        bad_string = true;
                        break :dispatch;
                    }
                }
            },
            '|' => {
                patt[j] = RegOp{ .alt = {} };
            },
            '(' => {
                pump += 1;
                patt[j] = RegOp{ .left = {} };
            },
            ')' => {
                if (pump == 0) {
                    bad_string = true;
                    break :dispatch;
                }
                pump -= 1;
                patt[j] = RegOp{ .right = {} };
            },
            '\\' => {
                if (i + 1 == in.len) {
                    bad_string = true;
                    break :dispatch;
                } else {
                    i += 1;

                    switch (in[i]) {
                        'd' => {
                            patt[j] = RegOp{ .digit = {} };
                        },
                        'D' => {
                            patt[j] = RegOp{ .not_digit = {} };
                        },
                        'w' => {
                            patt[j] = RegOp{ .alpha = {} };
                        },
                        'W' => {
                            patt[j] = RegOp{ .not_alpha = {} };
                        },
                        's' => {
                            patt[j] = RegOp{ .whitespace = {} };
                        },
                        'S' => {
                            patt[j] = RegOp{ .not_whitespace = {} };
                        },
                        'b', 'B' => |ch| {
                            if (j > 0 and (patt[j - 1] == .word_break or patt[j - 1] == .not_word_break)) {
                                bad_string = true;
                                break :dispatch;
                            }
                            if (ch == 'b') {
                                patt[j] = RegOp{ .word_break = {} };
                            } else {
                                patt[j] = RegOp{ .not_word_break = {} };
                            }
                        },

                        'r', 'n', 't' => {
                            patt[j] = RegOp{ .char = valueFor(in[i..]).? };
                        },

                        'x' => {
                            i += 1;
                            const b = parseHex(in[i..]) catch {
                                bad_string = true;
                                break :dispatch;
                            };
                            i += 1;
                            patt[j] = RegOp{ .char = b };
                        },
                        else => |ch| {
                            patt[j] = RegOp{ .char = ch };
                        },
                    }
                }
            },
            '[' => {
                i, s = parseCharSet(in, patt, sets, j, i, s) catch {
                    bad_string = true;
                    break :dispatch;
                };
            },
            else => |ch| {
                patt[j] = RegOp{ .char = ch };
            },
        }
    }
    if (j == patt.len and i < in.len) {
        return null;
    }
    if (pump != 0) {
        return null;
    }
    if (bad_string) {
        const tail = switch (i) {
            0 => "st",
            1 => "nd",
            2 => "rd",
            else => "th",
        };
        _ = tail;
        return null;
    }
    return out;
}
const BadString = error.BadString;
const d_MASK: u64 = 0x03ff000000000000;
const w_HI_MASK: u64 = 0x07fffffe87fffffe;
const w_LOW_MASK = d_MASK;
const s_MASK: u64 = 0x0000000100003e00;
const ALL_MASK: u64 = ~@as(u64, 0);
fn valueFor(in: []const u8) ?u8 {
    switch (in[0]) {
        't' => return '\t',
        'n' => return '\n',
        'r' => return '\r',
        'w', 'W', 's', 'S', 'd', 'D' => return null,
        'x' => {
            if (in.len >= 3) {
                return parseHex(in[1..4]) catch return null;
            } else {
                return 'x';
            }
        },
        128...255 => return null,
        else => return in[0],
    }
}
fn parseCharSet(in: []const u8, patt: []RegOp, sets: []CharSet, j: usize, i_in: usize, s_in: u8) !struct { usize, u8 } {
    var i = i_in;
    var s = s_in;
    var low: u64 = 0;
    var hi: u64 = 0;
    const this_kind: RegexType = which: {
        if (i + 1 < in.len and in[i + 1] == '^') {
            i += 1;
            break :which .not_class;
        } else break :which .class;
    };
    i += 1;
    while (i < in.len and in[i] != ']') : (i += 1) {
        const c1 = which: {
            if (in[i] == '\\') {
                const may_b = valueFor(in[i + 1 ..]);
                if (may_b) |b| {
                    if (in[i + 1] == 'x') {
                        i += 3;
                    } else {
                        i += 1;
                    }
                    break :which b;
                } else {
                    break :which in[1];
                }
            } else {
                break :which in[i];
            }
        };
        if (i + 1 < in.len and in[i + 1] != '-') {
            switch (c1) {
                0...63 => {
                    const cut_c: u6 = @truncate(c1);
                    low |= one << cut_c;
                },
                64...91, 93...127 => {
                    const cut_c: u6 = @truncate(c1);
                    hi |= one << cut_c;
                },
                '\\' => {
                    if (i + 1 < in.len) {
                        i += 1;
                        const c2 = in[i];
                        switch (c2) {
                            0...63 => {
                                const cut_c: u6 = @truncate(c2);
                                low |= one << cut_c;
                            },
                            'w' => {
                                low |= w_LOW_MASK;
                                hi |= w_HI_MASK;
                            },
                            'W' => {
                                low |= ~w_LOW_MASK;
                                hi |= ~w_HI_MASK;
                            },
                            's' => {
                                low |= s_MASK;
                            },
                            'S' => {
                                low |= ~s_MASK;
                                hi |= ~ALL_MASK;
                            },
                            'd' => {
                                low |= d_MASK;
                            },
                            'D' => {
                                low |= ~d_MASK;
                                hi |= ALL_MASK;
                            },
                            'n' => {
                                low |= one << '\n';
                            },
                            't' => {
                                low |= one << '\t';
                            },
                            'r' => {
                                low |= one << '\r';
                            },
                            'x' => {
                                i += 1;
                                const b = parseHex(in[i..]) catch return BadString;
                                if (b > 127) {
                                    return BadString;
                                }
                                i += 1;
                                const b_trunc: u6 = @truncate(b);
                                switch (b) {
                                    0...63 => low |= one << b_trunc,
                                    64...127 => hi |= one << b_trunc,
                                    else => unreachable,
                                }
                            },
                            128...255 => {
                                return BadString;
                            },
                            else => {
                                const cut_c: u6 = @truncate(c2);
                                hi |= one << cut_c;
                            },
                        }
                    }
                },
                else => {
                    return BadString;
                },
            }
        } else {
            if (i + 2 < in.len and in[i + 2] != ']') {
                const c_end = which: {
                    if (in[i + 2] != '\\') {
                        i += 1;
                        break :which in[i + 1];
                    } else if (i + 3 < in.len) {
                        const may_b = valueFor(in[i + 2 ..]);
                        if (may_b) |b| {
                            if (in[i + 2] == 'x') {
                                i += 4;
                            } else {
                                i += 2;
                            }
                            break :which b;
                        } else {
                            i += 1;
                            break :which in[i + 1];
                        }
                    } else {
                        break :which '\\';
                    }
                };
                if (c1 <= c_end) {
                    for (c1..c_end + 1) |c_range| {
                        switch (c_range) {
                            0...63 => {
                                const cut_c: u6 = @truncate(c_range);
                                low |= one << cut_c;
                            },
                            64...127 => {
                                const cut_c: u6 = @truncate(c_range);
                                hi |= one << cut_c;
                            },
                            else => {
                                return BadString;
                            },
                        }
                    }
                } else {
                    return BadString;
                }
            } else {
                const c_trunc: u6 = @truncate(c1);
                switch (c1) {
                    0...63 => low |= one << c_trunc,
                    64...127 => hi |= one << c_trunc,
                    128...255 => return BadString,
                }
            }
        }
    }
    if (i == in.len or in[i] != ']') {
        return BadString;
    }
    const set = CharSet{ .low = low, .hi = hi };
    const this_s = findSetIndex(sets, set, s);
    if (this_s >= sets.len) {
        return BadString;
    }
    sets[this_s] = set;
    if (this_s == s) {
        if (s == 255) {
            return BadString;
        }
        s += 1;
    }
    if (this_kind == .class) {
        patt[j] = RegOp{ .class = this_s };
    } else if (this_kind == .not_class) {
        patt[j] = RegOp{ .not_class = this_s };
    } else unreachable;
    return .{ i, s };
}
const testing = std.testing;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
fn printPattern(patt: []const RegOp) void {
    _ = printPatternInternal(patt);
}
fn printRegex(regex: anytype) void {
    const patt = regex.patt;
    const set_max = printPatternInternal(&patt);
    if (set_max) |max| {
        for (0..max + 1) |i| {
            std.debug.print("set {d}: ", .{i});
            printCharSet(regex.sets[i]) catch unreachable;
        }
    }
}
fn printRegexString(in: []const u8) void {
    const reggie = compile(in);
    if (reggie) |RRRRRR| {
        printRegex(&RRRRRR);
    }
}
fn printPatternInternal(patt: []const RegOp) ?u8 {
    var j: usize = 0;
    var set_max: ?u8 = null;
    std.debug.print("[", .{});
    while (j < patt.len and patt[j] != .unused) : (j += 1) {
        switch (patt[j]) {
            .char,
            => |op| {
                std.debug.print("{s} {u}", .{ @tagName(patt[j]), op });
            },
            .some,
            .up_to,
            => |op| {
                std.debug.print("{s} {d}", .{ @tagName(patt[j]), op });
            },
            .class,
            .not_class,
            => |op| {
                if (set_max) |max| {
                    set_max = @max(max, op);
                } else {
                    set_max = op;
                }
                std.debug.print("{s} {d}", .{ @tagName(patt[j]), op });
            },
            else => {
                std.debug.print("{s}", .{@tagName(patt[j])});
            },
        }
        if (j + 1 < patt.len and patt[j + 1] != .unused) {
            std.debug.print(", ", .{});
        }
    }
    std.debug.print("]\n", .{});
    return set_max;
}
fn printCharSet(set: CharSet) !void {
    const allocator = std.testing.allocator;
    var set_str = try std.ArrayList(u8).initCapacity(allocator, @popCount(set.low) + @popCount(set.hi) + 1);
    defer set_str.deinit();
    if (@popCount(set.low) != 0) {
        for (0..64) |i| {
            const c: u6 = @intCast(i);
            if ((set.low | (one << c)) == set.low) {
                try set_str.append(@as(u8, c));
            }
        }
    }
    if (@popCount(set.hi) != 0) {
        try set_str.append(' ');
        for (0..64) |i| {
            const c: u6 = @intCast(i);
            if ((set.hi | (one << c)) == set.hi) {
                const ch = @as(u8, c) | 0b0100_0000;
                try set_str.append(ch);
            }
        }
    }
    std.debug.print("{s}\n", .{set_str.items});
}
fn testMatchAll(needle: []const u8, haystack: []const u8) !void {
    const maybe_regex = compile(needle);
    if (maybe_regex) |regex| {
        const maybe_match = regex.match(haystack);
        if (maybe_match) |m| {
            try expectEqual(0, m.start);
            try expectEqual(haystack.len, m.end);
        } else {
            try expect(false);
        }
    } else {
        try expect(false);
    }
}
fn testMatchEnd(needle: []const u8, haystack: []const u8) !void {
    const maybe_regex = compile(needle);
    if (maybe_regex) |regex| {
        const maybe_match = regex.match(haystack);
        if (maybe_match) |m| {
            try expectEqual(haystack.len, m.end);
        } else {
            try expect(false);
        }
    } else {
        try expect(false);
    }
}
fn testMatchAllP(needle: []const u8, haystack: []const u8) !void {
    const maybe_regex = compile(needle);
    if (maybe_regex) |regex| {
        printRegex(&regex);
    }
    try testMatchAll(needle, haystack);
}
fn testMatchSlice(needle: []const u8, haystack: []const u8, slice: []const u8) !void {
    const maybe_regex = compile(needle);
    if (maybe_regex) |regex| {
        const maybe_match = regex.match(haystack);
        if (maybe_match) |m| {
            try expectEqualStrings(slice, m.slice);
        } else {
            try expect(false);
        }
    } else {
        try expect(false);
    }
}
fn testFail(needle: []const u8, haystack: []const u8) !void {
    const maybe_regex = compile(needle);
    if (maybe_regex) |regex| {
        try expectEqual(null, regex.match(haystack));
    } else {
        try expect(false);
    }
}
fn downStackRegex(RegexT: type, regex: RegexT, allocator: std.mem.Allocator) !*const RegexT {
    const heap_regex = try regex.toOwnedRegex(allocator);
    return heap_regex;
}
fn downStackMatch(matched: Match, allocator: std.mem.Allocator) !Match {
    const heap_match = try matched.toOwnedMatch(allocator);
    return heap_match;
}
fn testOwnedRegex(needle: []const u8, haystack: []const u8) !void {
    const allocator = std.testing.allocator;
    const maybe_regex = compile(needle);
    if (maybe_regex) |regex| {
        const heap_regex = try downStackRegex(Regex, regex, allocator);
        defer allocator.destroy(heap_regex);
        const maybe_match = heap_regex.match(haystack);
        if (maybe_match) |m| {
            const matched = try downStackMatch(m, allocator);
            defer matched.deinit(allocator);
            try expectEqualStrings(haystack, matched.slice);
        } else try expect(false);
    } else {
        try expect(false);
    }
}
test "match some things" {
    try testMatchAll("abc", "abc");
    try testMatchAll("[a-z]", "d");
    try testMatchAll("\\W\\w", "!a");
    try testMatchAll("\\w+", "abdcdFG");
    try testMatchAll("a*b+", "aaaaabbbbbbbb");
    try testMatchAll("a?b*", "abbbbb");
    try testMatchAll("a?b*", "bbbbbb");
    try testMatchAll("a*", "aaaaa");
    try testFail("a+", "b");
    try testMatchAll("a?", "a");
    try testMatchAll("^\\w*?abc", "qqqqabc");

    try testFail("^\\w*?abcd", "qqqqabc");
    try testMatchAll("^a*?abc", "abc");
    try testMatchAll("^1??abc", "abc");
    try testMatchAll("^1??abc", "1abc");
    try testMatchAll("^1??1abc", "1abc");
    try testMatchAll("[^abc]+", "defgh");
    try testMatchAll("^1??1abc$", "1abc");
    try testFail("^1??1abc$", "1abccc");
    try testMatchAll("foo|bar|baz", "foo");
    try testMatchAll("foo|bar|baz", "bar");
    try testMatchAll("foo|bar|baz", "baz");
    try testMatchAll("foo|bar|baz|quux+", "quuxxxxx");
    try testMatchAll("foo|bar|baz|bux|quux|quuux|quuuux", "quuuux");
    try testMatchAll("foo|bar|(baz|bux|quux|quuux)|quuuux", "quuuux");
    try testMatchAll("(abc)+d", "abcabcabcd");
    try testMatchAll("\t\n\r\xff\xff", "\t\n\r\xff\xff");
    try testMatchAll("[\t\r\n]+", "\t\t\r\r\n\t\n\r");
    try testMatchAll("[fd\\x03\\x04]+", "f\x03d\x04dfd\x03");
    try testMatchAll("a+b", "ab");
    try testMatchAll("a*aaa", "aaaaaaaaaaaaaa");
    try testMatchAll("\\w+foo", "abcdefoo");
    try testFail("\\w+foo", "foo");
    try testMatchAll("\\w*foo", "foo");
    try testFail("a++a", "aaaaaaaa");
    try testFail("a*+a", "aaaaaaaa");
    try testMatchAll("(aaa)?aaa", "aaa");
    try testFail("(aaa)?+aaa", "aaa");
    try testMatchAll("ab?", "ab");
    try testMatchAll("ab?", "a");
    try testMatchAll("^a{3,6}a", "aaaaaa");
    try testMatchAll("^a{3,4}", "aaaa");
    try testMatchAll("^a{3,5}", "aaaaa");
    try testMatchAll("^a{3,5}", "aaa");
    try testMatchAll("\\w{3,5}bc", "abbbc");
    try testMatchAll("\\w{3,5}", "abb");
    try testMatchAll("!{,3}", "!!!");
    try testMatchAll("abc(def(ghi)jkl)mno", "abcdefghijklmno");
    try testMatchAll("abc(def(ghi?)jkl)mno", "abcdefghijklmno");
    try testMatchAll("abc(def(ghi)?jkl)mno", "abcdefjklmno");
    try testMatchAll("abc(def(ghi?)jkl)mno", "abcdefghjklmno");
    try testFail("abc(def(ghi?)jkl)mno", "abcdefjklmno");
    try testMatchAll("abc(def((ghi)?)jkl)mno", "abcdefjklmno");
    try testMatchAll("(abc){5}?", "abcabcabcabcabc");
    try testMatchAll("(abc){3,5}?", "abcabcabcabcabc");
    try testMatchAll("^\\w+?$", "glebarg");
    try testMatchAll("[A-Za-z]+$", "Pabcex");
    try testMatchAll("^[^\n]+$", "a single line");
    try testFail("^[^\n]+$", "several \n lines");

    try testFail("[]+", "abc");
    try testFail("[]", "a");
    try testMatchAll("abc()d", "abcd");
    try testMatchAll("abc(|||)d", "abcd");

    try testMatchAll("(a*?)*aa", "aaa");
    try testMatchAll("(){0,1}q$", "q");
    try testMatchAll("(){1,2}q$", "q");
    try testMatchAll("(abc){3,5}?$", "abcabcabcabcabc");
    try testMatchAll("()+q$", "q");
    try testMatchAll("^(q*)*$", "qqqq");
    try testMatchEnd("[bc]*(cd)+", "cbcdcd");

    try testMatchAll("^[a-f0-9]{32}", "0800fc577294c34e0b28ad2839435945");
    try testMatchAll("ab+c|de+f", "abbbc");
    try testMatchAll("ab+c|de+f", "deeeef");
    try testFail("^ab+c|de+f", "abdef");
    try testMatchAll("employ(er|ee|ment|ing|able)", "employee");
    try testMatchAll("employ(er|ee|ment|ing|able)", "employer");
    try testMatchAll("employ(er|ee|ment|ing|able)", "employment");
    try testMatchAll("employ(er|ee|ment|ing|able)", "employable");
    try testMatchAll("employ(er|ee|ment|ing|able)", "employing");
    try testMatchAll("employ(|er|ee|ment|ing|able)", "employ");
    try testMatchAll("employ(|er|ee|ment|ing|able)$", "employee");

    try testMatchAll("\\$\\.\\(\\)\\*\\+\\?\\[\\\\]\\^\\{\\|\\}", "$.()*+?[\\]^{|}");
    try testMatchAll("[\\x41-\\x5a]+", "ABCDEFGHIJKLMNOPQRSTUVWXYZ");

    const test_escapes =
        \\\$\.\(\)\*\+\?\[\\]\^\{\|\}
    ;
    try testMatchAll(test_escapes, "$.()*+?[\\]^{|}");

    try testMatchAll("[^\\Wf]+", "YyIcMy9Z");
    try testFail("[^\\Wf]+$", "YyIcMy9Zf");
    try testMatchAll("[\\x48-\\x4c$]+", "HIJ$KL");
    try testMatchAll("[^^]+", "abXdea!@#$!%$#$%$&$");
    try testFail("^[^^]+", "^abXdea!@#$!%$#$%$&$");

    try testMatchAll("To the Bitter End$", "To the Bitter End\n");
    try testMatchAll(
        "William Gates Jr. Sucks.$",
        "William Gates Jr. Sucks.\r\n",
    );

    try testMatchAll("(fob)*boba$", "fobboba");
    try testFail("^(fob)*boba$", "fobfobfoboba");
    try testMatchSlice("(fob)*boba", "fobfobfoboba", "boba");

    try testMatchAll("\\bsnap\\b", "snap");
    try testMatchAll("\\bsnap\\b!", "snap!");
    try testMatchAll("\\b4\\b", "4");
    try testMatchSlice("\\bword\\b", "an isolated word ", "word");
    try testFail("\\bword\\b", "password");
    try testFail("\\bword\\b", "wordpress");
    try testMatchAll("out\\Brage\\Bous", "outrageous");
    try testMatchSlice("\\Brage\\B", "outrageous", "rage");
    try testFail("\\Brage\\B", "rage within the machine");
    try testMatchAll("a{3,5}+a", "aaaaaa");
    try testFail("(a[bc]){3,5}+ac", "abacabacac");
    try testMatchAll("(a[bc]){3,5}ac", "abacabacac");
    try testMatchAll("[0-9]{4}", "1951");
    try testMatchAll("(0[1-9]|1[012])[\\/](0[1-9]|[12][0-9]|3[01])[\\/][0-9]{4}", "10/12/1951");
    try testMatchAll("[\\x09]", "\t");

    try testMatchAll("^[a-zA-Z0-9_!#$%&.-]+@([a-zA-Z0-9.-])+$", "myname.myfirst_name@gmail.com");
    try testFail("(a+a+)+b", "a" ** 2048);

    try testFail("(a+?a+?)+?b", "a" ** 2048);

    try testFail("^(.*?,){254}P", "12345," ** 255);
}
test "workshop" {}
test "heap allocated regex and match" {
    try testOwnedRegex("abcde", "abcde");
    try testOwnedRegex("^[a-f0-9]{32}", "0800fc577294c34e0b28ad2839435945");
}
test "badblood" {}
test "Get the char sets you asked for" {
    const test_patt = "(0[1-9]|1[012])[\\/](0[1-9]|[12][0-9]|3[01])[\\/][0-9]{4}";
    const j, const s = resourcesNeeded(test_patt);
    try expectEqual(6, s);
    const ProperSize = SizedRegex(j, s);
    const haystack = "10/12/1951";
    const bigger_regex = ProperSize.compile(test_patt);
    if (bigger_regex) |reggie| {
        const match1 = reggie.match(haystack);
        if (match1) |m1| {
            try expectEqual(haystack.len, m1.end);
        } else {
            try expect(false);
        }
    } else {
        try expect(false);
    }
}
test "iteration" {
    const foo_str = "foobarbazfoo";
    var r_iter = compile("foo|bar|baz").?.iterator(foo_str);
    var matched = r_iter.next().?;
    try expectEqualStrings("foo", matched.slice);
    try expectEqualStrings("foo", foo_str[matched.start..matched.end]);
    matched = r_iter.next().?;
    try expectEqualStrings("bar", matched.slice);
    try expectEqualStrings("bar", foo_str[matched.start..matched.end]);
    matched = r_iter.next().?;
    try expectEqualStrings("baz", matched.slice);
    try expectEqualStrings("baz", foo_str[matched.start..matched.end]);
    matched = r_iter.next().?;
    try expectEqualStrings("foo", matched.slice);
    try expectEqualStrings("foo", foo_str[matched.start..matched.end]);
    try expectEqual(null, r_iter.next());
}
test "comptime regex" {
    const comp_regex = comptime compile("foo+").?;
    const run_match = comp_regex.match("foofoofoo");
    try expect(run_match != null);
    const comptime_match = comptime comp_regex.match("foofoofoo");
    try expect(comptime_match != null);
}

const std = @import("std");

// TODO: make this pile of junk return ranges, and not just a bool

// c matches any literal character c
// . matches any single character
// ^ matches the beginning of the input string
// $ matches the end of the input string
// * matches zero or more occurrences of the previous character
// + matches one or more occurrences of the previous character
// ? matches zero or one occurences of the previous character
// \ escapes the following symbol, which is matched literally

// deals with ^ and initial position of the match in text
pub fn match(regexp: []const u8, text: []const u8) bool {
    if (regexp.len == 0) {
        return true;
    } else if (regexp[0] == '^') {
        return matchHere(regexp[1..], text);
    } else for (0..text.len + 1) |index| {
        if (matchHere(regexp, text[index..])) {
            return true;
        }
    }
    return false;
}

// main recursive nest - ordered priority matching at the current location
// deals with escaping, switching between iterators (*, +, ?), matching the end
// and matching literal symbols
fn matchHere(regexp: []const u8, text: []const u8) bool {
    if (regexp.len == 0) {
        return true;
    }
    if (regexp[0] == '\\') {
        if (text.len > 0 and regexp.len > 1) {
            if (text[0] == regexp[1]) {
                return matchHere(regexp[2..], text[1..]);
            }
        }
        return false;
    }
    if (regexp.len > 1) {
        if (regexp[1] == '*') {
            return matchStar(regexp[2..], text, regexp[0]);
        }
        if (regexp[1] == '+') {
            return matchPlus(regexp[2..], text, regexp[0]);
        }
        if (regexp[1] == '?') {
            return matchQuestionMark(regexp[2..], text, regexp[0]);
        }
    }
    if (text.len == 0) {
        return regexp.len == 1 and regexp[0] == '$';
    }
    return matchOnce(regexp[1..], text, regexp[0]);
}

// deals with every possible "zero or more" match, then passes back to
// matchHere to continue matching the rest of the regexp
fn matchStar(regexp: []const u8, text: []const u8, c: u8) bool {
    const limit = blk: {
        if (c != '.') for (0..text.len) |index| {
            if (text[index] != c) {
                break :blk index;
            }
        };
        break :blk text.len;
    };
    for (0..limit + 1) |rev_idx| {
        const index = limit - rev_idx;
        if (matchHere(regexp, text[index..])) {
            return true;
        }
    }
    return false;
}

// ensures that at least one match was made, then passes to matchStar
// to continue to match "zero or more" additional, then back to the regexp
fn matchPlus(regexp: []const u8, text: []const u8, c: u8) bool {
    if (text.len == 0) return false;
    if (c != '.' and text[0] != c) return false;
    return matchStar(regexp, text[1..], c);
}

// ensures that one or none matches were made, then passes
// back to matchStar to continuematching the rest of the regexp
fn matchQuestionMark(regexp: []const u8, text: []const u8, c: u8) bool {
    if (matchOnce(regexp, text, c)) {
        return true;
    }
    return matchHere(regexp, text);
}

// matches a literal exactly once, passes back to matchHere to
// continue matching the rest of the regexp
fn matchOnce(regexp: []const u8, text: []const u8, c: u8) bool {
    if (text.len > 0) {
        if (c == '.' or c == text[0]) {
            return matchHere(regexp, text[1..]);
        }
    }
    return false;
}

const expectEqual = std.testing.expectEqual;

test match {
    try expectEqual(true, match("", ""));
    try expectEqual(true, match(".*", ""));
    try expectEqual(true, match("a?b", "b"));
    try expectEqual(true, match("\\.", "."));
    try expectEqual(true, match("a?b", "ab"));
    try expectEqual(true, match("a?bc", "bc"));
    try expectEqual(true, match("a+b", "aab"));
    try expectEqual(true, match("a?bc", "abc"));
    try expectEqual(true, match("a*b", "xyzb"));
    try expectEqual(true, match("a+b", "aaab"));
    try expectEqual(true, match("1\\+1", "1+1"));
    try expectEqual(true, match("a*b", "xaaab"));
    try expectEqual(true, match("1+2", "11112"));
    try expectEqual(true, match("^abc$", "abc"));
    try expectEqual(true, match("a\\.b", "a.b"));
    try expectEqual(true, match("a+bc", "aaabc"));
    try expectEqual(true, match("a*b", "xcaacb"));
    try expectEqual(true, match("", "not empty"));
    try expectEqual(true, match("a.c", "xa1c yz"));
    try expectEqual(true, match("^abc", "abcxyz"));
    try expectEqual(true, match("xyz$", "abcxyz"));
    try expectEqual(true, match(".*", "anything"));
    try expectEqual(true, match("abc", "xyzabcxyz"));
    try expectEqual(true, match("ab.*cd", "abxyzcd"));
    try expectEqual(true, match("^a.*z$", "alphabetz"));
    try expectEqual(true, match("hello\\ world", "hello world"));

    try expectEqual(false, match("a+b", "b"));
    try expectEqual(false, match("\\.", "a"));
    try expectEqual(false, match("a\\.b", "ab"));
    try expectEqual(false, match("1\\+1", "11"));
    try expectEqual(false, match("^a?b", "aab"));
    try expectEqual(false, match("a+bc", "aab"));
    try expectEqual(false, match("^abc$", "abcz"));
    try expectEqual(false, match("ca?bc", "caabc"));
    try expectEqual(false, match("xyz$", "xyzabc"));
    try expectEqual(false, match("abc", "xyzabxyz"));
    try expectEqual(false, match("a.c", "xa  c yz"));
    try expectEqual(false, match("^abc", "zabcxyz"));
    try expectEqual(false, match("^abc$", "abczabc"));
    try expectEqual(false, match("^a.*z$", "alphabet"));
    try expectEqual(false, match("ab.*cd", "xyzabxyzd"));
    try expectEqual(false, match("hello\\ world", "helloworld"));
}

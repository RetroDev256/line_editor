const std = @import("std");

const Tokenizer = @import("Tokenizer.zig");

const BoundedRange = @import("range.zig").BoundedRange;
const Number = @import("range.zig").Number;
const Range = @import("range.zig").Range;

pub const Insert = struct {
    line: ?Number,
    text: ?[]const u8,
};
pub const Substitution = struct {
    range: ?Range,
    pattern: []const u8,
    replacement: []const u8,
};
pub const Write = struct {
    range: ?Range,
    file_out: ?[]const u8,
};

pub const Command = union(enum) {
    none,
    blank,
    quit,
    delete: ?Range,
    print: ?Range,
    write: Write,
    write_quit: Write,
    insert: Insert,
    substitution: Substitution,
    line: Number,
};

const State = enum {
    start,
    range,
    lagging_text,
    substitute,
};

// updates the tokenizer if the expected token is a match,
// returns the token.
fn eat(tokenizer: *Tokenizer, expected: Tokenizer.Token.Tag) ?Tokenizer.Token {
    var toker = tokenizer.*; // copy for peeking
    const token = toker.next();
    if (token.tag == expected) {
        tokenizer.* = toker; // update the tokenizer
        return token;
    }
    return null;
}

// parser functions that don't parse complete commands
// update the tokenizer as necessary

// sub_arg or other_string
fn parseString(tokenizer: *Tokenizer) ?[]const u8 {
    if (eat(tokenizer, .sub_arg)) |token| {
        return tokenizer.buffer[token.loc.start..token.loc.end];
    } else if (eat(tokenizer, .other_string)) |token| {
        return tokenizer.buffer[token.loc.start..token.loc.end];
    } else return null;
}
// 123..., or $ for infinity
fn parseNumber(tokenizer: *Tokenizer) ?Number {
    var toker = tokenizer.*; // copy for peeking
    const peek_a = toker.next();
    switch (peek_a.tag) {
        .number => {
            const num_str = tokenizer.buffer[peek_a.loc.start..peek_a.loc.end];
            if (std.fmt.parseInt(usize, num_str, 10)) |number| {
                tokenizer.* = toker; // update the tokenizer
                return .{ .specific = number };
            } else |_| {}
        },
        else => if (std.mem.eql(u8, tokenizer.buffer[peek_a.loc.start..peek_a.loc.end], "$")) {
            tokenizer.* = toker; // update the tokenizer
            return .infinity;
        },
    }
    return null;
}
// use for when you expect an index, not a number
// the difference is that this changes the number so that
// we can index in a 0 indexed array, while the user interface
// makes things seem like they are indexed from 1
fn parseIndex(tokenizer: *Tokenizer) ?Number {
    if (parseNumber(tokenizer)) |number| {
        return number.dec();
    } else return null;
}
// NUM? SEP NUM?, or NUM
fn parseRange(tokenizer: *Tokenizer) ?Range {
    var toker_a = tokenizer.*; // copy for peeking
    const first = parseIndex(&toker_a);
    var toker_b = toker_a; // copy for peeking
    const seperator = toker_b.next().tag;
    const second = parseIndex(&toker_b);
    if (seperator == .range_seperator) { // NUM? SEP NUM?
        tokenizer.* = toker_b; // update the tokenizer
        // for converting between exclusive and inclusive ranges
        return Range{ .start = first, .end = if (second) |idx| idx.inc() else second };
    } else if (first) |index| { // NUM
        tokenizer.* = toker_a; // rollback to just after first number
        // for converting between exclusive and inclusive ranges
        return Range{ .start = index, .end = index.inc() };
    }
    return null;
}

// QUIT EOF
fn parseQuitCmd(source: []const u8) ?Command {
    var toker = Tokenizer.init(source);
    if (toker.next().tag == .quit_cmd) {
        if (toker.next().tag == .none) {
            return .quit;
        }
    }
    return null;
}
// RANGE? DELETE/PRINT EOF
fn parseDeleteOrPrintCmd(source: []const u8) ?Command {
    var toker = Tokenizer.init(source);
    const range = parseRange(&toker);
    if (eat(&toker, .print_cmd)) |_| {
        if (eat(&toker, .none)) |_| return Command{ .print = range };
    } else if (eat(&toker, .delete_cmd)) |_| {
        if (eat(&toker, .none)) |_| return Command{ .delete = range };
    }
    return null;
}
// RANGE? WRITE/WRITEQUIT STRING? EOF
fn parseWriteorWriteQuitCmd(source: []const u8) ?Command {
    var toker = Tokenizer.init(source);
    const range = parseRange(&toker);
    const command = toker.next();
    const file_out = parseString(&toker);
    if (toker.next().tag == .none) {
        return switch (command.tag) {
            .write_cmd => Command{ .write = .{ .range = range, .file_out = file_out } },
            .write_quit_cmd => Command{ .write_quit = .{ .range = range, .file_out = file_out } },
            else => null, // sadge
        };
    }
    return null;
}
// NUMBER? INSERT EOF
fn parseInsertCmd(source: []const u8) ?Command {
    var toker = Tokenizer.init(source);
    const line = parseIndex(&toker);
    const insert_tok = toker.next();
    if (insert_tok.tag == .insert) {
        const text = toker.buffer[insert_tok.loc.start..insert_tok.loc.end];
        if (toker.next().tag == .none) {
            if (text.len > 0) {
                return Command{ .insert = .{ .line = line, .text = text } };
            } else {
                return Command{ .insert = .{ .line = line, .text = null } };
            }
        }
    }
    return null;
}
// RANGE? SUB STRING STRING NUMBER?
fn parseSubstitutionCmd(source: []const u8) ?Command {
    var toker = Tokenizer.init(source);
    const range = parseRange(&toker);
    if (toker.next().tag == .substitute_cmd) {
        if (parseString(&toker)) |pattern| {
            if (parseString(&toker)) |replacement| {
                return Command{ .substitution = .{
                    .range = range,
                    .pattern = pattern,
                    .replacement = replacement,
                } };
            }
        }
    }
    return null;
}
// NUM EOF
fn parseLineCmd(source: []const u8) ?Command {
    var toker = Tokenizer.init(source);
    if (parseIndex(&toker)) |line_number| { // NUM
        if (toker.next().tag == .none) { // EOF
            return Command{ .line = line_number };
        }
    }
    return null;
}
// EOF
fn parseBlank(source: []const u8) ?Command {
    var toker = Tokenizer.init(source);
    if (eat(&toker, .none)) |_| return .blank;
    return null;
}

pub fn parse(source: []const u8) Command {
    if (parseQuitCmd(source)) |command| return command;
    if (parseDeleteOrPrintCmd(source)) |command| return command;
    if (parseWriteorWriteQuitCmd(source)) |command| return command;
    if (parseInsertCmd(source)) |command| return command;
    if (parseSubstitutionCmd(source)) |command| return command;
    if (parseLineCmd(source)) |command| return command;
    if (parseBlank(source)) |command| return command;
    return .none;
}

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
    help,
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

// parser functions update the tokenizer if they match what they are parsing

// sub_arg or other_string
fn parseString(tokenizer: *Tokenizer) ?[]const u8 {
    if (tokenizer.eat(.sub_arg)) |token| {
        return tokenizer.buffer[token.loc.start..token.loc.end];
    } else if (tokenizer.eat(.other_string)) |token| {
        return tokenizer.buffer[token.loc.start..token.loc.end];
    } else return null;
}
// 123..., or $ for infinity
fn parseNumber(tokenizer: *Tokenizer) ?Number {
    // operate on a copy of tokenizer - don't know if we can parse what we get
    var toker = tokenizer.*;
    if (toker.eat(.number)) |token| {
        const num_str = toker.buffer[token.loc.start..token.loc.end];
        if (std.fmt.parseInt(usize, num_str, 10)) |number| {
            tokenizer.* = toker; // update the tokenizer
            return .{ .specific = number };
        } else |_| {}
    } else if (tokenizer.eat(.range_file_end)) |_| { // no chance of parse failure
        return .infinity;
    }
    return null;
}
// use for when you expect an index, not a number
// the difference is that this changes the number so that
// we can index in a 0 indexed array, while the user interface
// makes things seem like they are indexed from 1
fn parseIndex(tokenizer: *Tokenizer) !?Number {
    if (parseNumber(tokenizer)) |number| {
        return number.dec() catch |err| switch (err) {
            error.NumberUnderflow => return error.OneBasedIndexIsZero,
        };
    } else return null;
}
// NUM? SEP NUM?, or NUM
fn parseRange(tokenizer: *Tokenizer) !?Range {
    const first = parseIndex(tokenizer) catch |err| switch (err) {
        error.OneBasedIndexIsZero => return error.RangeStartIsZero,
    };
    if (tokenizer.eat(.range_seperator)) |_| {
        const second = parseIndex(tokenizer) catch |err| switch (err) {
            error.OneBasedIndexIsZero => return error.RangeEndIsZero,
        };
        return .{ .start = first, .end = second };
    } else if (first) |index| {
        return .{ .start = index, .end = index };
    }
    return null;
}

// QUIT EOF
fn parseQuitOrHelpCmd(source: []const u8) ?Command {
    var toker = Tokenizer.init(source);
    if (toker.eatMany(.{ .quit_cmd, .none })) |_| {
        return .quit;
    } else if (toker.eatMany(.{ .help_cmd, .none })) |_| {
        return .help;
    } else return null;
}
// RANGE? DELETE/PRINT EOF
fn parseDeleteOrPrintCmd(source: []const u8) !?Command {
    var toker = Tokenizer.init(source);
    const range = try parseRange(&toker);
    if (toker.eatMany(.{ .print_cmd, .none })) |_| {
        return Command{ .print = range };
    } else if (toker.eatMany(.{ .delete_cmd, .none })) |_| {
        return Command{ .delete = range };
    } else return null;
}
// RANGE? WRITE/WRITEQUIT STRING? EOF
fn parseWriteorWriteQuitCmd(source: []const u8) !?Command {
    var toker = Tokenizer.init(source);
    const range = try parseRange(&toker);
    if (toker.eat(.write_cmd)) |_| {
        const file_out = parseString(&toker);
        return Command{ .write = .{ .range = range, .file_out = file_out } };
    } else if (toker.eat(.write_quit_cmd)) |_| {
        const file_out = parseString(&toker);
        return Command{ .write_quit = .{ .range = range, .file_out = file_out } };
    }
    return null;
}
// NUMBER? INSERT EOF
fn parseInsertCmd(source: []const u8) !?Command {
    var toker = Tokenizer.init(source);
    const line = try parseIndex(&toker);
    if (toker.eatMany(.{ .insert, .none })) |insert_tokens| {
        const insert = insert_tokens[0];
        const text = toker.buffer[insert.loc.start..insert.loc.end];
        if (text.len > 0) {
            return Command{ .insert = .{ .line = line, .text = text } };
        } else return Command{ .insert = .{ .line = line, .text = null } };
    } else return null;
}
// RANGE? SUB STRING STRING NUMBER?
fn parseSubstitutionCmd(source: []const u8) !?Command {
    var toker = Tokenizer.init(source);
    const range = try parseRange(&toker);
    if (toker.eat(.substitute_cmd)) |_| {
        if (parseString(&toker)) |pattern| {
            if (parseString(&toker)) |replacement| {
                if (toker.eat(.none)) |_| {
                    return Command{ .substitution = .{
                        .range = range,
                        .pattern = pattern,
                        .replacement = replacement,
                    } };
                }
            }
        }
    }
    return null;
}
// NUM EOF
fn parseLineCmd(source: []const u8) !?Command {
    var toker = Tokenizer.init(source);
    if (try parseIndex(&toker)) |line_number| { // NUM
        if (toker.eat(.none)) |_| { // EOF
            return Command{ .line = line_number };
        }
    }
    return null;
}
// EOF
fn parseBlank(source: []const u8) ?Command {
    var toker = Tokenizer.init(source);
    if (toker.eat(.none)) |_| {
        return .blank;
    }
    return null;
}

pub fn parse(source: []const u8) !Command {
    if (parseQuitOrHelpCmd(source)) |command| return command;
    if (try parseDeleteOrPrintCmd(source)) |command| return command;
    if (try parseWriteorWriteQuitCmd(source)) |command| return command;
    if (try parseInsertCmd(source)) |command| return command;
    if (try parseSubstitutionCmd(source)) |command| return command;
    if (try parseLineCmd(source)) |command| return command;
    if (parseBlank(source)) |command| return command;
    return .none;
}

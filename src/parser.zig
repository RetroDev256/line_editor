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
pub const Move = struct {
    range: ?Range,
    line: Number,
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
    move: Move,
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
fn parseString(toker: *Tokenizer) ?[]const u8 {
    if (toker.eat(.sub_arg)) |token| {
        return toker.buffer[token.loc.start..token.loc.end];
    } else if (toker.eat(.other_string)) |token| {
        return toker.buffer[token.loc.start..token.loc.end];
    } else return null;
}
// 123..., or $ for infinity
fn parseNumber(toker: *Tokenizer) ?Number {
    // operate on a copy of tokenizer - don't know if we can parse what we get
    var toker_copy = toker.*;
    if (toker_copy.eat(.number)) |token| {
        const num_str = toker_copy.buffer[token.loc.start..token.loc.end];
        if (std.fmt.parseInt(usize, num_str, 10)) |number| {
            toker.* = toker_copy; // update the tokenizer
            return .{ .specific = number };
        } else |_| {}
    } else if (toker.eat(.range_file_end)) |_| { // no chance of parse failure
        return .infinity;
    }
    return null;
}
// use for when you expect an index, not a number
// the difference is that this changes the number so that
// we can index in a 0 indexed array, while the user interface
// makes things seem like they are indexed from 1
fn parseIndex(toker: *Tokenizer) !?Number {
    if (parseNumber(toker)) |number| {
        return number.dec() catch |err| switch (err) {
            error.NumberUnderflow => return error.OneBasedIndexIsZero,
        };
    } else return null;
}
// NUM? SEP NUM?, or NUM
fn parseRange(toker: *Tokenizer) !?Range {
    const first = parseIndex(toker) catch |err| switch (err) {
        error.OneBasedIndexIsZero => return error.RangeStartIsZero,
    };
    if (toker.eat(.range_seperator)) |_| {
        const second = parseIndex(toker) catch |err| switch (err) {
            error.OneBasedIndexIsZero => return error.RangeEndIsZero,
        };
        return .{ .start = first, .end = second };
    } else if (first) |index| {
        return .{ .start = index, .end = index };
    }
    return null;
}

// QUIT EOF
fn parseQuitOrHelpCmd(toker: *Tokenizer) ?Command {
    if (toker.eatMany(.{ .quit_cmd, .none })) |_| {
        return .quit;
    } else if (toker.eatMany(.{ .help_cmd, .none })) |_| {
        return .help;
    } else return null;
}
// RANGE? DELETE/PRINT EOF
fn parseDeleteOrPrintCmd(toker: *Tokenizer) !?Command {
    var toker_copy = toker.*;
    const range = try parseRange(&toker_copy);
    if (toker_copy.eatMany(.{ .print_cmd, .none })) |_| {
        toker.* = toker_copy;
        return Command{ .print = range };
    } else if (toker_copy.eatMany(.{ .delete_cmd, .none })) |_| {
        toker.* = toker_copy;
        return Command{ .delete = range };
    } else return null;
}
// RANGE? WRITE/WRITEQUIT STRING? EOF
fn parseWriteorWriteQuitCmd(toker: *Tokenizer) !?Command {
    var toker_copy = toker.*;
    const range = try parseRange(&toker_copy);
    if (toker_copy.eat(.write_cmd)) |_| {
        const file_out = parseString(&toker_copy);
        toker.* = toker_copy;
        return Command{ .write = .{ .range = range, .file_out = file_out } };
    } else if (toker_copy.eat(.write_quit_cmd)) |_| {
        const file_out = parseString(&toker_copy);
        toker.* = toker_copy;
        return Command{ .write_quit = .{ .range = range, .file_out = file_out } };
    }
    return null;
}
// NUMBER? INSERT EOF
fn parseInsertCmd(toker: *Tokenizer) !?Command {
    var toker_copy = toker.*;
    const line = try parseIndex(&toker_copy);
    if (toker_copy.eatMany(.{ .insert_cmd, .none })) |insert_tokens| {
        const insert = insert_tokens[0];
        const text = toker_copy.buffer[insert.loc.start..insert.loc.end];
        if (text.len > 0) {
            toker.* = toker_copy;
            return Command{ .insert = .{ .line = line, .text = text } };
        } else {
            toker.* = toker_copy;
            return Command{ .insert = .{ .line = line, .text = null } };
        }
    } else return null;
}
// RANGE? SUB STRING STRING NUMBER?
fn parseSubstitutionCmd(toker: *Tokenizer) !?Command {
    var toker_copy = toker.*;
    const range = try parseRange(&toker_copy);
    if (toker_copy.eat(.substitute_cmd)) |_| {
        if (parseString(&toker_copy)) |pattern| {
            if (parseString(&toker_copy)) |replacement| {
                if (toker_copy.eat(.none)) |_| {
                    toker.* = toker_copy;
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
// RANGE? MOVE INDEX
fn parseMoveCmd(toker: *Tokenizer) !?Command {
    var toker_copy = toker.*;
    const range = try parseRange(&toker_copy);
    if (toker_copy.eat(.move_cmd)) |_| {
        if (try parseIndex(&toker_copy)) |index| {
            toker.* = toker_copy;
            return Command{ .move = .{ .range = range, .line = index } };
        }
    }
    return null;
}
// NUM EOF
fn parseLineCmd(toker: *Tokenizer) !?Command {
    var toker_copy = toker.*;
    if (try parseIndex(&toker_copy)) |line_number| { // NUM
        if (toker_copy.eat(.none)) |_| { // EOF
            toker.* = toker_copy;
            return Command{ .line = line_number };
        }
    }
    return null;
}
// EOF
fn parseBlank(toker: *Tokenizer) ?Command {
    if (toker.eat(.none)) |_| {
        return .blank;
    } else return null;
}

pub fn parse(source: []const u8) !Command {
    var toker = Tokenizer.init(source);
    if (parseQuitOrHelpCmd(&toker)) |command| return command;
    if (try parseDeleteOrPrintCmd(&toker)) |command| return command;
    if (try parseWriteorWriteQuitCmd(&toker)) |command| return command;
    if (try parseInsertCmd(&toker)) |command| return command;
    if (try parseSubstitutionCmd(&toker)) |command| return command;
    if (try parseMoveCmd(&toker)) |command| return command;
    if (try parseLineCmd(&toker)) |command| return command;
    if (parseBlank(&toker)) |command| return command;
    return .none;
}

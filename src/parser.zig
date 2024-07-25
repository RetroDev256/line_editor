const std = @import("std");

const Tokenizer = @import("Tokenizer.zig");

pub const Number = union(enum) {
    specific: usize, // 123...
    infinity, // $
};
pub const Range = struct {
    start: ?Number,
    end: ?Number,
};
pub const Insert = struct {
    line: ?Number,
    text: ?[]const u8,
};
pub const Substitution = struct {
    range: ?Range,
    pattern: []const u8,
    replacement: []const u8,
    count: ?Number,
};
pub const Write = struct {
    range: ?Range,
    file_out: ?[]const u8,
};
pub const Delete = struct { range: ?Range };
pub const Print = struct { range: ?Range };

pub const Command = union(enum) {
    none,
    quit, // check

    delete: Delete, // done
    print: Print, // done

    write: Write, // done
    write_quit: Write, // done

    insert: Insert,
    substitution: Substitution,

    line: Number, // check
};

const State = enum {
    start,
    range,
    lagging_text,
    substitute,
};

// parser functions that don't parse complete commands
// update the tokenizer as necessary

// sub_arg or other_string
fn parseString(tokenizer: *Tokenizer) ?[]const u8 {
    var toker_a = tokenizer.*; // copy for peeking
    const peek_a = toker_a.next();
    if (peek_a.tag == .sub_arg or peek_a.tag == .other_string) {
        tokenizer.* = toker_a;
        return tokenizer.buffer[peek_a.loc.start..peek_a.loc.end];
    }
    return null;
}
// 123..., or $ for infinity
fn parseNumber(tokenizer: *Tokenizer) ?Number {
    var toker_a = tokenizer.*; // copy for peeking
    const peek_a = toker_a.next();
    switch (peek_a.tag) {
        .number => {
            const num_str = tokenizer.buffer[peek_a.loc.start..peek_a.loc.end];
            if (std.fmt.parseInt(usize, num_str, 10)) |number| {
                tokenizer.* = toker_a; // update the tokenizer
                return .{ .specific = number };
            } else |_| {}
        },
        .range_file_end => {
            tokenizer.* = toker_a; // update the tokenizer
            return .infinity;
        },
        .sub_arg => { // for the substitution command
            const sub_num_str = tokenizer.buffer[peek_a.loc.start..peek_a.loc.end];
            if (std.mem.eql(u8, sub_num_str, "$")) {
                tokenizer.* = toker_a; // update the tokenizer
                return .infinity;
            } else {
                if (std.fmt.parseInt(usize, sub_num_str, 10)) |number| {
                    tokenizer.* = toker_a; // update the tokenizer
                    return .{ .specific = number };
                } else |_| {}
            }
        },
        else => {},
    }
    return null;
}
// NUM? SEP NUM?, or NUM
fn parseRange(tokenizer: *Tokenizer) ?Range {
    var toker_a = tokenizer.*; // copy for peeking
    const first_num = parseNumber(&toker_a);
    if (first_num) |_| { // NUM SEP NUM, NUM SEP, NUM
        const second_num = blk: {
            var toker_b = toker_a;
            if (toker_b.next().tag == .range_seperator) {
                toker_a = toker_b;
                break :blk parseNumber(&toker_a);
            }
            break :blk first_num; // only a first number means range of 1
        };
        tokenizer.* = toker_a;
        return Range{ .start = first_num, .end = second_num };
    } else if (toker_a.next().tag == .range_seperator) { // SEP NUM, or suspend
        const second_num = parseNumber(&toker_a);
        tokenizer.* = toker_a;
        return Range{ .start = first_num, .end = second_num };
    }
    return null;
}

// QUIT EOF
fn parseQuitCmd(tokenizer: Tokenizer) ?void {
    var toker_a = tokenizer; // copy for peeking
    if (toker_a.next().tag == .quit_cmd) {
        if (toker_a.next().tag == .none) {
            return;
        }
    }
    return null;
}
// RANGE? DELETE EOF
fn parseDeleteCmd(tokenizer: Tokenizer) ?Delete {
    var toker_a = tokenizer; // copy for peeking
    const range = parseRange(&toker_a);
    if (toker_a.next().tag == .delete_cmd) {
        if (toker_a.next().tag == .none) {
            return .{ .range = range };
        }
    }
    return null;
}
// RANGE? PRINT EOF
fn parsePrintCmd(tokenizer: Tokenizer) ?Print {
    var toker_a = tokenizer; // copy for peeking
    const range = parseRange(&toker_a);
    if (toker_a.next().tag == .print_cmd) {
        if (toker_a.next().tag == .none) {
            return .{ .range = range };
        }
    }
    return null;
}
// RANGE? WRITE STRING? EOF
fn parseWriteCmd(tokenizer: Tokenizer) ?Write {
    var toker_a = tokenizer; // copy for peeking
    const range = parseRange(&toker_a);
    if (toker_a.next().tag == .write_cmd) {
        const file_out = parseString(&toker_a);
        if (toker_a.next().tag == .none) {
            return .{ .range = range, .file_out = file_out };
        }
    }
    return null;
}
// RANGE? WRITEQUIT STRING? EOF
fn parseWriteQuitCmd(tokenizer: Tokenizer) ?Write {
    var toker_a = tokenizer; // copy for peeking
    const range = parseRange(&toker_a);
    if (toker_a.next().tag == .write_quit_cmd) {
        const file_out = parseString(&toker_a);
        if (toker_a.next().tag == .none) {
            return .{ .range = range, .file_out = file_out };
        }
    }
    return null;
}
// NUMBER? INSERT EOF
fn parseInsertCmd(tokenizer: Tokenizer) ?Insert {
    var toker_a = tokenizer;
    const line = parseNumber(&toker_a);
    const next_tok = toker_a.next();
    if (next_tok.tag == .insert) {
        const text = toker_a.buffer[next_tok.loc.start..next_tok.loc.end];
        if (toker_a.next().tag == .none) {
            return .{
                .line = line,
                .text = if (text.len == 0) null else text,
            };
        }
    }
    return null;
}
// RANGE? SUB STRING STRING NUMBER?
fn parseSubstitutionCmd(tokenizer: Tokenizer) ?Substitution {
    var toker_a = tokenizer;
    const range = parseRange(&toker_a);
    if (toker_a.next().tag == .substitute_cmd) {
        if (parseString(&toker_a)) |pattern| {
            if (parseString(&toker_a)) |replacement| {
                const count = parseNumber(&toker_a);
                return .{
                    .range = range,
                    .pattern = pattern,
                    .replacement = replacement,
                    .count = count,
                };
            }
        }
    }
    return null;
}
// NUM EOF
fn parseLineCmd(tokenizer: Tokenizer) ?Number {
    var toker_a = tokenizer; // copy for peeking
    if (parseNumber(&toker_a)) |line_number| { // NUM
        if (toker_a.next().tag == .none) { // EOF
            return line_number;
        }
    }
    return null;
}

pub fn parse(source: []const u8) Command {
    const tokenizer = Tokenizer.init(source);
    if (parseQuitCmd(tokenizer)) |quit| {
        return .{ .quit = quit };
    } else if (parseDeleteCmd(tokenizer)) |delete| {
        return .{ .delete = delete };
    } else if (parsePrintCmd(tokenizer)) |print| {
        return .{ .print = print };
    } else if (parseWriteCmd(tokenizer)) |write| {
        return .{ .write = write };
    } else if (parseWriteQuitCmd(tokenizer)) |write_quit| {
        return .{ .write_quit = write_quit };
    } else if (parseInsertCmd(tokenizer)) |insert| {
        return .{ .insert = insert };
    } else if (parseSubstitutionCmd(tokenizer)) |substitution| {
        return .{ .substitution = substitution };
    } else if (parseLineCmd(tokenizer)) |line| {
        return .{ .line = line };
    }
    return .none;
}

const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("Tokenizer.zig");
const Selection = @import("selection.zig").Selection;
const commands = @import("commands.zig");

alloc: Allocator,
source: []const u8,
tokens: []const Tokenizer.Token,
// used to resolve indexes which are specified to be at the end
last_index: usize,

// state of parsing the 'Selection' type
starting_index: ?usize = null,
has_range_seperator: bool = false,
ending_index: ?usize = null,

// TODO: seperate the selection from the command type
pub const Command = union(enum) {
    quit: commands.Quit,
    help: commands.Help,
    delete: commands.Delete,
    print: commands.Print,
    write: commands.Write,
    insert: commands.Insert,
    substitute: commands.Substitute,
    move: commands.Move,
    copy: commands.Copy,
    line: commands.Line,
};

pub fn parse(alloc: Allocator, source: []const u8, last_index: usize) !?Command {
    const tokens = try Tokenizer.tokenize(alloc, source);
    var self: Self = .{
        .alloc = alloc,
        .source = source,
        .tokens = tokens,
        .last_index = last_index,
    };
    defer self.alloc.free(self.tokens);
    return self.parseCommand();
}

pub fn parseSelection(self: *Self) !Selection {
    if (self.has_range_seperator) {
        return .{
            .range = .{
                .start = self.starting_index orelse 0,
                .end = self.ending_index orelse self.last_index + 1, // exclusive vs inclusive
            },
        };
    } else if (self.ending_index) |_| {
        return error.Malformed;
    } else if (self.starting_index) |index| {
        return .{ .line = index };
    } else {
        return .unspecified;
    }
}

fn updateRange(self: *Self, value: usize) !void {
    if (self.has_range_seperator) {
        if (self.ending_index == null) {
            self.ending_index = value + 1; // exclusive vs inclusive
        } else return error.Malformed;
    } else {
        if (self.starting_index == null) {
            self.starting_index = value;
        } else return error.Malformed;
    }
}

pub fn parseIndex(num_str: []const u8, last_index: usize) !usize {
    if (num_str.len == 1) {
        if (num_str[0] == '$') {
            return last_index;
        }
    }
    const parsed = std.fmt.parseInt(usize, num_str, 10);
    const number = parsed catch return error.Malformed;
    if (number == 0) return error.IndexZero;
    return number - 1; // 0 based indexing
}

fn parseCommand(self: *Self) !?Command {
    var token_idx: usize = 0;
    while (token_idx < self.tokens.len) : (token_idx += 1) {
        const token = self.tokens[token_idx];
        switch (token.tag) {
            .number => {
                const num_str = token.data(self.source);
                const index = try parseIndex(num_str, self.last_index);
                try self.updateRange(index);
            },
            .range_file_end => try self.updateRange(self.last_index),
            .range_seperator => {
                if (self.has_range_seperator or self.ending_index != null) {
                    return error.Malformed;
                } else self.has_range_seperator = true;
            },
            ._none => unreachable, // tokenizer filters this out
            else => {
                if (token_idx != self.tokens.len - 1) {
                    return error.Malformed;
                }
                const selection = try self.parseSelection();
                const token_data = token.data(self.source);
                return switch (token.tag) {
                    .substitute => .{
                        .substitute = try commands.Substitute.parse(selection, token_data),
                    },
                    .write => .{
                        .write = try commands.Write.parse(selection, token_data),
                    },
                    .insert => .{
                        .insert = try commands.Insert.parse(selection, token_data),
                    },
                    .move => .{
                        .move = try commands.Move.parse(selection, token_data, self.last_index),
                    },
                    .copy => .{
                        .copy = try commands.Copy.parse(selection, token_data, self.last_index),
                    },
                    .delete => .{
                        .delete = try commands.Delete.parse(selection),
                    },
                    .print => .{
                        .print = try commands.Print.parse(selection),
                    },
                    .help => .{
                        .help = try commands.Help.parse(selection),
                    },
                    .quit => .{
                        .quit = try commands.Quit.parse(selection),
                    },
                    // filtered out earlier
                    else => unreachable,
                };
            },
        }
    }
    if (self.source.len == 0) return null;
    const selection = try self.parseSelection();
    return .{
        .line = try commands.Line.parse(selection),
    };
}

// Testing

fn handle(err: anyerror) !void {
    switch (err) {
        error.IndexZero => {},
        error.Malformed => {},
        else => return err,
    }
}

test "fuzz parser" {
    const input = std.testing.fuzzInput(.{});
    const alloc = std.testing.allocator;
    const parsed = parse(alloc, input, 0) catch |err| return handle(err);
    _ = parsed;
}

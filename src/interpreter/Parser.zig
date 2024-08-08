const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("Tokenizer.zig");
const Selection = @import("selection.zig").Selection;
const Index = @import("selection.zig").Index;
const commands = @import("commands.zig");

alloc: Allocator,
source: []const u8,
tokens: []const Tokenizer.Token,

// state of parsing the 'Selection' type
starting_index: ?Index = null,
has_range_seperator: bool = false,
ending_index: ?Index = null,

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

pub fn parse(alloc: Allocator, source: []const u8) !?Command {
    var self: Self = .{
        .alloc = alloc,
        .source = source,
        .tokens = try Tokenizer.tokenize(alloc, source),
    };
    defer self.alloc.free(self.tokens);
    return self.parseCommand();
}

pub fn parseIndex(num_str: []const u8) !Index {
    if (num_str.len == 1) {
        if (num_str[0] == '$') {
            return .infinity;
        }
    }
    const parsed = std.fmt.parseInt(usize, num_str, 10);
    const number = parsed catch return error.InvalidNumber;
    if (number == 0) return error.IndexZero; // would underflow
    return Index{ .specific = number - 1 }; // 0 based indexing
}

pub fn parseSelection(self: *Self) !Selection {
    if (self.has_range_seperator) {
        return .{ .range = .{
            .start = self.starting_index,
            .end = self.ending_index,
        } };
    } else {
        if (self.ending_index != null) {
            return error.Malformed;
        } else {
            if (self.starting_index) |index| {
                return .{ .line = index };
            } else return .unspecified;
        }
    }
}

fn updateRange(self: *Self, value: Index) !void {
    if (self.has_range_seperator) {
        if (self.ending_index == null) {
            self.ending_index = value;
        } else return error.Malformed;
    } else {
        if (self.starting_index == null) {
            self.starting_index = value;
        } else return error.Malformed;
    }
}

fn parseCommand(self: *Self) !?Command {
    var token_idx: usize = 0;
    while (token_idx < self.tokens.len) : (token_idx += 1) {
        const token = self.tokens[token_idx];
        switch (token.tag) {
            .number => {
                const num_str = token.data(self.source);
                const index = try parseIndex(num_str);
                try self.updateRange(index);
            },
            .range_file_end => try self.updateRange(.infinity),
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
                        .move = try commands.Move.parse(selection, token_data),
                    },
                    .copy => .{
                        .copy = try commands.Copy.parse(selection, token_data),
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
    return switch (err) {
        error.Malformed => {},
        else => err,
    };
}

test "fuzz parser" {
    const input = std.testing.fuzzInput(.{});
    const alloc = std.testing.allocator;
    const parsed = parse(alloc, input) catch |err| return handle(err);
    _ = parsed;
}

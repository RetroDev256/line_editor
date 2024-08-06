const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("Tokenizer.zig");
const Index = @import("index.zig").Index;
const Range = @import("Range.zig");

alloc: Allocator,
source: []const u8,
tokens: []const Tokenizer.Token,
starting_index: ?Index = null,
has_range_seperator: bool = false,
ending_index: ?Index = null,

pub const InsertTextLine = struct { dest: Index, text: []const u8 };
pub const Sub = struct { before: []const u8, after: []const u8 };
pub const SubLine = struct { dest: Index, before: []const u8, after: []const u8 };
pub const SubRange = struct { dest: Range, before: []const u8, after: []const u8 };
pub const WriteLine = struct { source: Index, file_out: []const u8 };
pub const WriteRange = struct { source: Range, file_out: []const u8 };
pub const MoveLine = struct { source: Index, dest: Index };
pub const MoveRange = struct { source: Range, dest: Index };

pub const Command = union(enum) {
    quit,
    help,
    delete,
    delete_line: Index,
    delete_range: Range,
    print,
    print_line: Index,
    print_range: Range,
    write_default,
    write_default_line: Index,
    write_default_range: Range,
    write_quit_default,
    write_quit_default_line: Index,
    write_quit_default_range: Range,
    write: []const u8,
    write_line: WriteLine,
    write_range: WriteRange,
    write_quit: []const u8,
    write_quit_line: WriteLine,
    write_quit_range: WriteRange,
    insert_mode,
    insert_mode_line: Index,
    insert_text: []const u8,
    insert_text_line: InsertTextLine,
    sub: Sub,
    sub_line: SubLine,
    sub_range: SubRange,
    move: Index,
    move_line: MoveLine,
    move_range: MoveRange,
    line: Index,
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

fn parseIndex(num_str: []const u8) !Index {
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

fn substituteCmd(self: *Self, token_data: []const u8) !Command {
    if (token_data.len < 2) return error.MalformedCommand;
    if (token_data[0] != '/') return error.MalformedCommand;
    if (std.mem.count(u8, token_data, "/") != 2) {
        return error.MalformedCommand;
    }
    const split = std.mem.indexOfScalar(u8, token_data[1..], '/') orelse {
        return error.MalformedCommand;
    };
    const before = token_data[1 .. split + 1];
    const after = token_data[split + 2 ..];
    return switch (try self.lineTarget()) {
        .none => .{ .sub = .{ .before = before, .after = after } },
        .index => |index| .{ .sub_line = .{ .before = before, .after = after, .dest = index } },
        .range => |range| .{ .sub_range = .{ .before = before, .after = after, .dest = range } },
    };
}

fn insertCmd(self: *Self, token_data: []const u8) !Command {
    if (token_data.len == 0) {
        return switch (try self.lineTarget()) {
            .none => .insert_mode,
            .index => |index| .{ .insert_mode_line = index },
            .range => error.MalformedCommand,
        };
    } else {
        return switch (try self.lineTarget()) {
            .none => .{ .insert_text = token_data },
            .index => |index| .{ .insert_text_line = .{
                .dest = index,
                .text = token_data,
            } },
            .range => error.MalformedCommand,
        };
    }
}

fn writeCmd(self: *Self, token_data: []const u8) !Command {
    if (token_data.len == 0) {
        return switch (try self.lineTarget()) {
            .none => .write_default,
            .index => |index| .{ .write_default_line = index },
            .range => |range| .{ .write_default_range = range },
        };
    } else {
        return switch (try self.lineTarget()) {
            .none => .{ .write = token_data },
            .index => |index| .{ .write_line = .{
                .source = index,
                .file_out = token_data,
            } },
            .range => |range| .{ .write_range = .{
                .source = range,
                .file_out = token_data,
            } },
        };
    }
}

fn writeQuitCmd(self: *Self, token_data: []const u8) !Command {
    if (token_data.len == 0) {
        return switch (try self.lineTarget()) {
            .none => .write_quit_default,
            .index => |index| .{ .write_quit_default_line = index },
            .range => |range| .{ .write_quit_default_range = range },
        };
    } else {
        return switch (try self.lineTarget()) {
            .none => .{ .write_quit = token_data },
            .index => |index| .{ .write_quit_line = .{
                .source = index,
                .file_out = token_data,
            } },
            .range => |range| .{ .write_quit_range = .{
                .source = range,
                .file_out = token_data,
            } },
        };
    }
}

fn moveCmd(self: *Self, token_data: []const u8) !Command {
    std.debug.print("moveCmd: {any}\n", .{token_data});
    const dest = try parseIndex(token_data);
    return switch (try self.lineTarget()) {
        .none => .{ .move = dest },
        .index => |index| .{ .move_line = .{ .source = index, .dest = dest } },
        .range => |range| .{ .move_range = .{ .source = range, .dest = dest } },
    };
}

fn printCmd(self: *Self) !Command {
    return switch (try self.lineTarget()) {
        .none => .print,
        .index => |index| .{ .print_line = index },
        .range => |range| .{ .print_range = range },
    };
}

fn deleteCmd(self: *Self) !Command {
    return switch (try self.lineTarget()) {
        .none => .delete,
        .index => |index| .{ .delete_line = index },
        .range => |range| .{ .delete_range = range },
    };
}

fn quitCmd(self: *Self) !Command {
    if (self.starting_index != null) return error.MalformedCommand;
    if (self.has_range_seperator) return error.MalformedCommand;
    if (self.ending_index != null) return error.MalformedCommand;
    return .quit;
}

fn helpCmd(self: *Self) !Command {
    if (self.starting_index != null) return error.MalformedCommand;
    if (self.has_range_seperator) return error.MalformedCommand;
    if (self.ending_index != null) return error.MalformedCommand;
    return .help;
}

const LineTarget = union(enum) { none, index: Index, range: Range };

fn lineTarget(self: *Self) !LineTarget {
    if (self.has_range_seperator) {
        return .{ .range = .{
            .start = self.starting_index,
            .end = self.ending_index,
        } };
    } else {
        if (self.ending_index != null) {
            return error.MalformedCommand;
        } else {
            if (self.starting_index) |index| {
                return .{ .index = index };
            } else return .none;
        }
    }
}

fn updateRange(self: *Self, value: Index) !void {
    if (self.has_range_seperator) {
        if (self.ending_index == null) {
            self.ending_index = value;
        } else return error.MalformedCommand;
    } else {
        if (self.starting_index == null) {
            self.starting_index = value;
        } else return error.MalformedCommand;
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
                    return error.MalformedCommand;
                } else self.has_range_seperator = true;
            },
            ._none => unreachable, // tokenizer filters this out
            else => {
                if (token_idx != self.tokens.len - 1) {
                    return error.MalformedCommand;
                }
                const token_data = token.data(self.source);
                switch (token.tag) {
                    .substitute_cmd => return try self.substituteCmd(token_data),
                    .write_quit_cmd => return try self.writeQuitCmd(token_data),
                    .insert_cmd => return try self.insertCmd(token_data),
                    .write_cmd => return try self.writeCmd(token_data),
                    .move_cmd => return try self.moveCmd(token_data),
                    .delete_cmd => return try self.deleteCmd(),
                    .print_cmd => return try self.printCmd(),
                    .quit_cmd => return try self.quitCmd(),
                    .help_cmd => return try self.helpCmd(),
                    // shouldn't lead in a command
                    .string => return error.MalformedCommand,
                    // filtered out earlier
                    .number => unreachable,
                    .range_file_end => unreachable,
                    .range_seperator => unreachable,
                    ._none => unreachable,
                }
            },
        }
    }
    if (self.has_range_seperator) return error.MalformedCommand;
    if (self.ending_index != null) return error.MalformedCommand;
    if (self.starting_index) |index| {
        return .{ .line = index };
    } else {
        if (self.source.len != 0) return error.MalformedCommand;
        return null;
    }
}

fn handle(err: anyerror) !void {
    return switch (err) {
        error.ReversedRange => {},
        error.IndexZero => {},
        error.IndexOutOfBounds => {},
        error.MalformedCommand => {},
        error.EmptyBuffer => {},
        error.NoOutputSpecified => {},
        error.InvalidNumber => {},
        else => err,
    };
}

test "fuzz parser" {
    const input = std.testing.fuzzInput(.{});
    const alloc = std.testing.allocator;
    const parsed = parse(alloc, input) catch |err| return handle(err);
    _ = parsed;
}

//! This represents a list of changes made to the LineBuffer
//! Commands wishing to edit the LineBuffer must use this

const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const LineBuffer = @import("LineBuffer.zig");
const Lines = @import("Lines.zig");
const Range = @import("Range.zig");
const List = std.ArrayListUnmanaged;

pub const Change = union(enum) {
    replace: Lines,
    insert: Lines,
    delete: Range,
    resize: usize,

    // performs the change and returns the reverse of the change
    pub fn apply(self: Change, alloc: Allocator, buffer: *LineBuffer) !Change {
        switch (self) {
            .replace => |new| {
                const old = buffer.get(new.range()) orelse {
                    return error.OutOfBounds;
                };
                const owned = try old.dupe(alloc);
                errdefer owned.deinit(alloc);
                try buffer.replace(alloc, new);
                return .{ .replace = owned };
            },
            .insert => |new| {
                try buffer.insert(alloc, new);
                return .{ .delete = new.range() };
            },
            .delete => |new| {
                if (buffer.get(new)) |old| {
                    const owned = try old.dupe(alloc);
                    errdefer owned.deinit(alloc);
                    buffer.delete(alloc, old.range());
                    return .{ .insert = owned };
                } else {
                    return .{ .insert = Lines.init(&.{}, 0) };
                }
            },
            .resize => |new| {
                const old = buffer.length();
                try buffer.resize(alloc, new);
                return .{ .resize = old };
            },
        }
    }

    pub fn deinit(self: Change, alloc: Allocator) void {
        switch (self) {
            .replace, .insert => |lines| lines.deinit(alloc),
            .delete, .resize => {},
        }
    }
};

// multiple Changes to a LineBuffer may constitute one undo/redo step
undos: List([]const Change) = .{},
redos: List([]const Change) = .{},

pub fn deinit(self: *Self, alloc: Allocator) void {
    freeStepList(alloc, self.undos);
    self.undos.deinit(alloc);
    freeStepList(alloc, self.redos);
    self.redos.deinit(alloc);
    self.* = undefined;
}

// add some new changes (one step) - clears the "redo" stack
pub fn apply(self: *Self, alloc: Allocator, step: []const Change, buffer: *LineBuffer) !void {
    if (step.len == 0) return; // nothing to be done
    try applyInner(alloc, &self.undos, step, buffer);
    freeStepList(alloc, self.redos);
    self.redos.clearAndFree(alloc);
}

// undo one step
pub fn undo(self: *Self, alloc: Allocator, buffer: *LineBuffer) !void {
    if (self.undos.popOrNull()) |step| {
        defer freeChangeList(alloc, step);
        try applyInner(alloc, &self.redos, step, buffer);
    } else {
        return error.NoMoreUndoSteps;
    }
}

// redo one step
pub fn redo(self: *Self, alloc: Allocator, buffer: *LineBuffer) !void {
    if (self.redos.popOrNull()) |step| {
        defer freeChangeList(alloc, step);
        try applyInner(alloc, &self.undos, step, buffer);
    } else {
        return error.NoMoreRedoSteps;
    }
}

// applies multiple changes (one step) and appends them to the destination
// list in the reverse order that they were applied
fn applyInner(
    alloc: Allocator,
    dest: *List([]const Change),
    step: []const Change,
    buffer: *LineBuffer,
) !void {
    const rev_step = try alloc.alloc(Change, step.len);
    errdefer alloc.free(rev_step);
    // clone each change - in case of error, clean up allocated
    // insert the changes in reverse order
    var i: usize = 0;
    errdefer for (0..i) |line| {
        const rev_idx = rev_step.len - (line + 1);
        rev_step[rev_idx].deinit(alloc);
    };
    while (i < step.len) : (i += 1) {
        const rev_idx = rev_step.len - (i + 1);
        rev_step[rev_idx] = try step[i].apply(alloc, buffer);
    }
    try dest.append(alloc, rev_step);
}

fn freeChangeList(alloc: Allocator, list: []const Change) void {
    for (list) |change| {
        change.deinit(alloc);
    }
    alloc.free(list);
}

fn freeStepList(alloc: Allocator, list: List([]const Change)) void {
    for (list.items) |step| {
        freeChangeList(alloc, step);
    }
}

// testing

test "undo and redo" {
    const alloc = std.testing.allocator;
    var buffer = try LineBuffer.init(alloc, null);
    defer buffer.deinit(alloc);

    var undos: Self = .{};
    defer undos.deinit(alloc);

    const steps: []const []const Change = &.{
        &.{.{ .insert = Lines.init(&.{"Hello, World!"}, 0) }},
        &.{.{ .insert = Lines.init(&.{"This is Line 2"}, 1) }},
        &.{.{ .insert = Lines.init(&.{"This is Line 1"}, 0) }},
        &.{.{ .replace = Lines.init(&.{"Goodbye, World!"}, 1) }},
        &.{.{ .delete = Range.initLen(1, 1) }},
        &.{.{ .insert = Lines.init(&.{
            "This is Line 3",
            "This is Line 4",
            "This is Line 5",
        }, 2) }},
        &.{.{ .replace = Lines.init(&.{
            "Line 3 is redacted",
            "Line 4 is redacted",
        }, 2) }},
        &.{.{ .delete = Range.initLen(1, 3) }},
        &.{.{ .resize = 5 }},
    };

    const results: []const []const u8 = &.{
        &.{},
        \\Hello, World!
        ,
        \\Hello, World!
        \\This is Line 2
        ,
        \\This is Line 1
        \\Hello, World!
        \\This is Line 2
        ,
        \\This is Line 1
        \\Goodbye, World!
        \\This is Line 2
        ,
        \\This is Line 1
        \\This is Line 2
        ,
        \\This is Line 1
        \\This is Line 2
        \\This is Line 3
        \\This is Line 4
        \\This is Line 5
        ,
        \\This is Line 1
        \\This is Line 2
        \\Line 3 is redacted
        \\Line 4 is redacted
        \\This is Line 5
        ,
        \\This is Line 1
        \\This is Line 5
        ,
        \\This is Line 1
        \\This is Line 5
        \\
        \\
        \\
    };

    // apply
    try LineBuffer.expectEqual(&buffer, results[0]);
    for (steps, results[1..]) |step, expected| {
        try undos.apply(alloc, step, &buffer);
        try LineBuffer.expectEqual(&buffer, expected);
    }

    // undo
    for (0..steps.len) |step| {
        try undos.undo(alloc, &buffer);
        const actual = results[steps.len - (step + 1)];
        try LineBuffer.expectEqual(&buffer, actual);
    }
    const undo_res = undos.undo(alloc, &buffer);
    try std.testing.expectError(error.NoMoreUndoSteps, undo_res);

    // redo
    for (results[1..]) |expected| {
        try undos.redo(alloc, &buffer);
        try LineBuffer.expectEqual(&buffer, expected);
    }
    const redo_res = undos.redo(alloc, &buffer);
    try std.testing.expectError(error.NoMoreRedoSteps, redo_res);
}

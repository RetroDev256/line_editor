const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const Runner = @import("Runner.zig");
const misc = @import("misc.zig");
const InternPool = @import("InternPool.zig");

// GOAL:
// make this a lightweight program to edit SINGLE files.

// CHANGE OF PLANS?
// - this is still a line editor...
// - there is no cursor, but you can see some lines
// - commands are entered at the bottom of the screen
// - the current line number (offset/absolute/I haven't decided) is before the lines
// - the print command is merged with the line command to display sections
// - searching through the text will display all lines containing the matching text,
// but not with non-matching lines inbetween (maybe one line above for context for each?)

// CHANGE OF CHANGE OF PLANS TODO:???:
// There is ONLY command mode.
// Append/insert is done with `.[string][enter]` at all times

// Change of plans 2.0:ko
// p -> print lines
// n -> number lines
// a -> enter append mode
// i -> enter insert mode
// d -> delete line
// c[string] -> change line to string
// s/before/after/FLAGS -> replace before with after, according to POSIX
// .[string] -> insert string before line
// w[path] -> save lines to path
// # -> comment
// q -> exit

// change of plans 3.0:
// p -> print numbered lines
// .[string] ->
//     - enter EDIT mode if string == "", which is exited by '.'
//     - this command APPENDS in both EDIT mode and COMMAND mode
//     index 0 means to "place at start"
// d -> delete line(s)
// w[path] -> save lines to path
// #[equation] -> solve math equation
// s/before/after/FLAGS -> replace ALL before with after, according to POSIX
// q -> exit
// TODO: more according to ED

pub fn main() !void {
    const gpa = std.heap.page_allocator; //smp_allocator;
    const file = try parseArgs(gpa);
    defer if (file) |f| gpa.free(f);
    var pool: InternPool = .empty;
    defer pool.deinit(gpa);

    var runner: Runner = try .init(gpa, &pool, file);
    defer runner.deinit(gpa, &pool);
    try runner.run(gpa, &pool);
}

fn parseArgs(gpa: Allocator) !?[]const u8 {
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    switch (args.len) {
        0 => unreachable,
        1 => return null,
        2 => return try gpa.dupe(u8, args[1]),
        else => {
            std.debug.print("Usage: {s} [FILE]\n", .{args[0]});
            std.process.exit(1);
        },
    }
}

test {
    std.testing.refAllDeclsRecursive(@This());
}

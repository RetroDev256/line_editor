//! This type distinguishes different line indexing modes of different commands
//! Some commands may behave differently based on whether a range, index, or none
//! is provided.

const Range = @import("Range.zig");

pub const Selection = union(enum) {
    unspecified,
    line: usize,
    range: Range,

    // convert any representation to a range; when unspecified, use the default
    pub fn resolve(self: Selection, default: Range) Range {
        return switch (self) {
            .unspecified => default,
            .line => |line| Range.single(line),
            .range => |range| range,
        };
    }
};

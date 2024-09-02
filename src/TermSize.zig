const Self = @This();

const std = @import("std");
const builtin = @import("builtin");

width: u16,
height: u16,

pub fn size(file: std.fs.File) !?Self {
    switch (builtin.os.tag) {
        .linux, .macos => {
            var win_size: std.posix.winsize = undefined;
            const ioctl_result = std.posix.system.ioctl(
                file.handle,
                std.posix.T.IOCGWINSZ,
                @intFromPtr(&win_size),
            );
            switch (std.posix.errno(ioctl_result)) {
                .SUCCESS => return Self{
                    .width = win_size.col,
                    .height = win_size.row,
                },
                else => return error.IoctlError,
            }
        },
        .windows => {
            var buf: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
            const buf_info_result = std.os.windows.kernel32.GetConsoleScreenBufferInfo(file.handle, &buf);
            switch (buf_info_result) {
                std.os.windows.TRUE => {
                    const width = (buf.srWindow.Right + 1) - buf.srWindow.Left;
                    const height = (buf.srWindow.Bottom + 1) - buf.srWindow.Top;
                    return .{ .width = @intCast(width), .height = @intCast(height) };
                },
                else => return error.Unexpected,
            }
        },
        else => return null, // Unsupported operating system
    }
}

const std = @import("std");
const builtin = @import("builtin");

pub const Size = struct { width: u16, height: u16 };

pub const TerminalInfo = switch (builtin.os.tag) {
    .windows => std.os.windows.DWORD,
    else => std.posix.termios,
};

// Return the size of the terminal
pub const size = switch (builtin.os.tag) {
    .windows => sizeWindows,
    else => sizePosix,
};

// Disable echo, line buffering, and input processing
pub const enableRaw = switch (builtin.os.tag) {
    .windows => enableRawWindows,
    else => enableRawPosix,
};

// Restore the terminal mode with the return value of enableRaw
pub const disableRaw = switch (builtin.os.tag) {
    .windows => disableRawWindows,
    else => disableRawPosix,
};

// Set the terminal cursor position to the 0, 0 corner
pub const origin = switch (builtin.os.tag) {
    .windows => originWindows,
    else => originPosix,
};

fn sizeWindows() !Size {
    var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    const info_result = std.os.windows.kernel32.GetConsoleScreenBufferInfo(
        std.os.windows.STD_OUTPUT_HANDLE,
        &info,
    );
    if (info_result == std.os.windows.TRUE) {
        const window = info.srWindow;
        return .{
            .width = @intCast((window.Right + 1) - window.Left),
            .height = @intCast((window.Bottom + 1) - window.Top),
        };
    } else {
        return error.GetConsoleScreenBufferInfo;
    }
}

fn sizePosix() !Size {
    var winsize_info: std.posix.winsize = undefined;
    const ioctl_result = std.posix.system.ioctl(
        std.posix.STDOUT_FILENO,
        @intCast(std.posix.T.IOCGWINSZ),
        @intFromPtr(&winsize_info),
    );
    if (std.posix.errno(ioctl_result) == .SUCCESS) {
        return .{
            .width = winsize_info.col,
            .height = winsize_info.row,
        };
    } else {
        return error.IoctlFailure;
    }
}

fn enableRawWindows() !TerminalInfo {
    var mode: std.os.windows.DWORD = undefined;
    const get_result = std.os.windows.kernel32.GetConsoleMode(
        std.os.windows.STD_INPUT_HANDLE,
        &mode,
    );
    const original = mode;
    if (get_result != std.os.windows.TRUE) {
        return error.GetConsoleMode;
    }
    const set_result = std.os.windows.kernel32.SetConsoleMode(
        std.os.windows.STD_INPUT_HANDLE,
        mode & ~(0b100 | 0b10 | 0b1),
    );
    if (set_result != std.os.windows.TRUE) {
        return error.SetConsoleMode;
    }
    return original;
}

fn enableRawPosix() !TerminalInfo {
    const term_info = try std.posix.tcgetattr(std.posix.STDIN_FILENO);

    var changed_info = term_info;
    changed_info.lflag.ICANON = false;
    changed_info.lflag.ECHO = false;

    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, changed_info);

    return term_info;
}

fn disableRawWindows(mode: TerminalInfo) !void {
    const set_result = std.os.windows.kernel32.SetConsoleMode(
        std.os.windows.STD_INPUT_HANDLE,
        mode,
    );
    if (set_result != std.os.windows.TRUE) {
        return error.SetConsoleMode;
    }
}

fn disableRawPosix(info: TerminalInfo) !void {
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, info);
}

fn originWindows() !void {
    const set_result = std.os.windows.kernel32.SetConsoleCursorPosition(
        std.os.windows.STD_OUTPUT_HANDLE,
        .{ .X = 0, .Y = 0 },
    );
    if (set_result != std.os.windows.TRUE) {
        return error.SetConsoleCursorPosition;
    }
}

fn originPosix() !void {
    try std.io.getStdOut().writeAll("\x1B[H");
}

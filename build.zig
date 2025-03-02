const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const share = b.option(bool, "share", "Prepare for distribution");
    const strip = b.option(bool, "strip", "Strip debug info");

    if (share orelse false) {
        buildAll(b, optimize, strip);
    } else {
        buildNative(b, optimize, strip);
    }
}

const target_strs: []const []const u8 = &.{
    "aarch64_be-linux",  "aarch64-linux",   "aarch64-windows", "aarch64-macos",
    "armeb-linux",       "arm-linux",       "x86-linux",       "x86-windows",
    "mips64el-linux",    "mips64-linux",    "mipsel-linux",    "mips-linux",
    "powerpc64le-linux", "powerpc64-linux", "powerpc-linux",   "riscv32-linux",
    "riscv64-linux",     "wasm32-wasi",     "x86_64-linux",    "x86_64-windows",
    "x86_64-macos",
};

fn buildAll(b: *std.Build, optimize: std.builtin.OptimizeMode, strip: ?bool) void {
    // build each target and install them
    inline for (target_strs) |target_str| {
        const query = std.Build.parseTargetQuery(
            .{ .arch_os_abi = target_str },
        );

        const root_mod = b.addModule("le", .{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = b.resolveTargetQuery(query catch unreachable),
        });
        root_mod.strip = strip;
        root_mod.single_threaded = true;
        root_mod.omit_frame_pointer = true;

        // exe steps
        const exe = b.addExecutable(.{
            .name = "le_" ++ target_str,
            .root_module = root_mod,
        });
        exe.link_function_sections = true;
        exe.link_data_sections = true;
        b.installArtifact(exe);
    }
}

fn buildNative(b: *std.Build, optimize: std.builtin.OptimizeMode, strip: ?bool) void {
    const root_mod = b.addModule("le", .{
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = b.standardTargetOptions(.{}),
    });
    root_mod.strip = strip;
    root_mod.single_threaded = true;
    root_mod.omit_frame_pointer = true;

    // exe step
    const exe = b.addExecutable(.{ .name = "le", .root_module = root_mod });
    exe.link_function_sections = true;
    exe.link_data_sections = true;
    b.installArtifact(exe);

    // run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // test exe
    const exe_unit_tests = b.addTest(.{ .root_module = root_mod });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

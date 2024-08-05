const std = @import("std");

pub fn build(b: *std.Build) void {
    const package = b.option(bool, "package", "Package the project for distribution") orelse false;

    if (package) {
        buildAll(b);
    } else {
        buildNative(b);
    }
}

fn buildAll(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const test_step = b.step("test", "Run unit tests");
    for (target_strs) |target_str| {
        // build each target and install it
        const query = std.Build.parseTargetQuery(.{ .arch_os_abi = target_str });
        const package_target = b.resolveTargetQuery(query catch unreachable);
        const package_exe = b.addExecutable(.{
            .name = "line_editor",
            .root_source_file = b.path("src/main.zig"),
            .target = package_target,
            .optimize = optimize,
        });
        if (optimize == .ReleaseFast or optimize == .ReleaseSmall) optimizeMore(package_exe);
        const artifact = b.addInstallArtifact(package_exe, .{ .dest_sub_path = target_str });
        b.getInstallStep().dependOn(&artifact.step);

        // test each target
        const exe_unit_tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .target = package_target,
            .optimize = optimize,
        });
        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}

fn buildNative(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // exe step
    const exe = b.addExecutable(.{
        .name = "line_editor",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (optimize == .ReleaseFast or optimize == .ReleaseSmall) {
        optimizeMore(exe);
    }
    b.installArtifact(exe);

    // run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // test exe
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

const target_strs: []const []const u8 = &.{
    "aarch64_be-linux-gnu",    "aarch64_be-linux-musl", "aarch64-linux-gnu",
    "aarch64-linux-musl",      "aarch64-windows-gnu",   "aarch64-macos-none",
    "armeb-linux-gnueabi",     "armeb-linux-gnueabihf", "armeb-linux-musleabi",
    "armeb-linux-musleabihf",  "arm-linux-gnueabi",     "arm-linux-gnueabihf",
    "arm-linux-musleabi",      "arm-linux-musleabihf",  "x86-linux-gnu",
    "x86-linux-musl",          "x86-windows-gnu",       "mips64el-linux-musl",
    "mips64-linux-gnuabi64",   "mips64-linux-musl",     "mipsel-linux-gnueabi",
    "mipsel-linux-gnueabihf",  "mipsel-linux-musl",     "mips-linux-gnueabi",
    "mips-linux-gnueabihf",    "mips-linux-musl",       "powerpc64le-linux-gnu",
    "powerpc64le-linux-musl",  "powerpc64-linux-musl",  "powerpc-linux-gnueabi",
    "powerpc-linux-gnueabihf", "powerpc-linux-musl",    "riscv32-linux-gnuilp32",
    "riscv32-linux-musl",      "riscv64-linux-gnu",     "riscv64-linux-musl",
    "sparc64-linux-gnu",       "wasm32-wasi-musl",      "x86_64-linux-gnu",
    "x86_64-linux-musl",       "x86_64-windows-gnu",    "x86_64-macos-none",
};

fn optimizeMore(artifact: *std.Build.Step.Compile) void {
    // some optimizations
    artifact.root_module.omit_frame_pointer = true;
    artifact.root_module.strip = true;
    artifact.dead_strip_dylibs = true;
    artifact.root_module.error_tracing = false;
    artifact.root_module.link_libc = false;
    artifact.root_module.link_libcpp = false;
    artifact.root_module.single_threaded = true;
    artifact.root_module.unwind_tables = false;
    artifact.formatted_panics = false;
}

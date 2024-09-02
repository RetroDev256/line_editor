const std = @import("std");

pub fn build(b: *std.Build) void {
    const package = b.option(bool, "share", "Package the project for distribution") orelse false;
    const release = b.option(bool, "small", "Turn on release flags and build things tiny") orelse false;

    const optimize = switch (release) {
        true => .ReleaseSmall,
        false => b.standardOptimizeOption(.{}),
    };

    if (package) {
        buildAll(b, optimize);
    } else {
        buildNative(b, optimize);
    }
}

fn buildAll(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const test_step = b.step("test", "Run unit tests");
    for (target_strs) |target_str| {
        // build each target and install it
        const query = std.Build.parseTargetQuery(.{ .arch_os_abi = target_str });
        const package_target = b.resolveTargetQuery(query catch unreachable);
        const package_exe = b.addExecutable(.{
            .name = "le",
            .root_source_file = b.path("src/main.zig"),
            .target = package_target,
            .optimize = optimize,
        });
        if (optimize == .ReleaseFast or optimize == .ReleaseSmall) {
            // toggle compiler options
            standardOptimize(package_exe);
        }
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

const target_strs: []const []const u8 = &.{
    "aarch64_be-linux",  "aarch64-linux",   "aarch64-windows", "aarch64-macos",
    "armeb-linux",       "arm-linux",       "x86-linux",       "x86-windows",
    "mips64el-linux",    "mips64-linux",    "mipsel-linux",    "mips-linux",
    "powerpc64le-linux", "powerpc64-linux", "powerpc-linux",   "riscv32-linux",
    "riscv64-linux",     "wasm32-wasi",     "x86_64-linux",    "x86_64-windows",
    "x86_64-macos",
};

fn buildNative(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const target = b.standardTargetOptions(.{});

    // exe step
    const exe = b.addExecutable(.{
        .name = "le",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (optimize == .ReleaseFast or optimize == .ReleaseSmall) {
        standardOptimize(exe);
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

fn standardOptimize(exe: *std.Build.Step.Compile) void {
    // general stuff
    exe.root_module.strip = true;
    exe.root_module.single_threaded = true;
    // garbage collect stuff
    exe.link_function_sections = true;
    exe.link_data_sections = true;
}

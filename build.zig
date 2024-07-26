const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // exe step
    const exe = b.addExecutable(.{
        .name = "line_editor",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // some optimizations
    if (optimize == .ReleaseFast or optimize == .ReleaseSmall) {
        exe.root_module.omit_frame_pointer = true;
        exe.root_module.strip = true;
        exe.dead_strip_dylibs = true;

        exe.root_module.error_tracing = false;
        exe.root_module.link_libc = false;
        exe.root_module.link_libcpp = false;
        exe.root_module.red_zone = false;
        exe.root_module.sanitize_c = false;
        exe.root_module.sanitize_thread = false;
        exe.root_module.single_threaded = true;
        exe.root_module.stack_check = false;
        exe.root_module.stack_protector = false;
        exe.root_module.unwind_tables = false;
        exe.formatted_panics = false;
    }

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

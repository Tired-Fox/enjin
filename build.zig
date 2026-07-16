const std = @import("std");

pub fn build(b: *std.Build) !void {
    var target = b.standardTargetOptions(.{});

    // Ensure that aarch64 is built with msvc as that is what is required for wgpu_native
    if (target.result.os.tag == .windows and target.result.cpu.arch == .aarch64) {
        target.result.abi = .msvc;
    }

    const optimize = b.standardOptimizeOption(.{});

    // ----- Dependencies -----

    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });

    const wgpu_native = b.dependency("wgpu_native_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("enjin", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "enjin",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "enjin", .module = mod },
                .{ .name = "zglfw", .module = zglfw.module("root") },
                .{ .name = "wgpu", .module = wgpu_native.module("wgpu") },
            },
        }),
    });

    // IMPORTANT:
    //      If there are link errors about duplicate symbols try this
    //
    // if (target.result.os.tag == .windows and target.result.abi == .msvc) {
    //     exe.bundle_compiler_rt = false;
    //     exe.bundle_ubsan_rt = false;
    // }

    if (target.result.os.tag != .emscripten) {
        exe.root_module.linkLibrary(zglfw.artifact("glfw"));
    }

    switch (target.result.os.tag) {
        .macos => {
            // https://github.com/spencrc/hello-triangle-zig-wgpu/blob/main/build.zig#L26
            exe.root_module.addCSourceFile(.{
                .file = b.path("lib/meta_layer.m"),
                .language = .objective_c
            });
            exe.root_module.linkFramework("QuartzCore", .{});
            exe.root_module.linkFramework("Metal", .{});
        },
        else => {}
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

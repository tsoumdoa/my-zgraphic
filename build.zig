const std = @import("std");
const ResolvedTarget = std.Build.ResolvedTarget;
const Step = std.Build.Step;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    for ([_]struct { name: []const u8 }{
        .{ .name = "wgpu-triangle" },
        .{ .name = "wgpu-square" },
    }) |example| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("src/{s}/main.zig", .{example.name})),
            .target = target,
            .optimize = optimize,
        });

        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = exe_mod,
        });

        addDeps(exe, b, target);

        const run_cmd = b.addRunArtifact(exe);

        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step(b.fmt("run-{s}", .{example.name}), b.fmt("Run {s}", .{example.name}));
        run_step.dependOn(&run_cmd.step);
    }
}

inline fn addDeps(exe: *Step.Compile, b: *std.Build, target: ResolvedTarget) void {

    //add zglfw
    const zglfw = b.dependency("zglfw", .{});
    exe.root_module.addImport("zglfw", zglfw.module("root"));

    // add zgpu
    @import("zgpu").addLibraryPathsTo(exe);
    const zgpu = b.dependency("zgpu", .{});
    exe.root_module.addImport("zgpu", zgpu.module("root"));

    // add zpool
    const zpool = b.dependency("zpool", .{});
    exe.root_module.addImport("zpool", zpool.module("root"));

    // add zgui
    const zgui = b.dependency("zgui", .{
        .shared = false,
        .with_implot = true,
        .backend = .glfw_wgpu,
    });
    exe.root_module.addImport("zgui", zgui.module("root"));

    // add zmath
    const zmath = b.dependency("zmath", .{});
    exe.root_module.addImport("zmath", zmath.module("root"));

    // custom utils + helper functions
    const funcsModule = b.addModule("funcs", .{
        .root_source_file = .{ .src_path = .{
            .owner = b,
            .sub_path = "src/funcs//utils.zig",
        } },
    });
    funcsModule.addImport("zgpu", zgpu.module("root"));
    exe.root_module.addImport("utils", funcsModule);

    // link libs
    if (target.result.os.tag != .emscripten) {
        exe.linkLibrary(zglfw.artifact("glfw"));
        exe.linkLibrary(zgpu.artifact("zdawn"));
        exe.linkLibrary(zgui.artifact("imgui"));
    }
    b.installArtifact(exe);
    b.installFile("public/Roboto-Medium.ttf", "bin/resource/Roboto-Medium.ttf");
}

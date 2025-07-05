const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const DemoState = @import("./demo-state.zig").DemoState;

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_impl.allocator();

    // Change current working directory to where the executable is located.
    {
        var buffer: [1024]u8 = undefined;
        const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        std.posix.chdir(path) catch {};
    }

    // init window etc
    try zglfw.init();
    defer zglfw.terminate();
    zglfw.windowHint(.client_api, .no_api);

    const window = try zglfw.createWindow(900, 600, "wgpu-triangle", null);
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    // init demo
    var demo = try DemoState.init(gpa, window);
    defer demo.deinit();

    //init zgui
    zgui.init(gpa);
    defer zgui.deinit();
    _ = zgui.io.addFontFromFile("../../public/" ++ "Roboto-Medium.ttf", math.floor(16.0 * scale_factor));

    zgui.backend.init(
        window,
        demo.gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );
    defer zgui.backend.deinit();


    // main loop
    while (!window.shouldClose()) {
        zglfw.pollEvents();

        demo.update();
        demo.draw();

        window.swapBuffers();
    }
}

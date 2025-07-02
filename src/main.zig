const std = @import("std");
const glfw = @import("zglfw");

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    const window = try glfw.createWindow(900, 600, "zig-gamedev: minimal_glfw_gl", null);
    defer glfw.destroyWindow(window);


    // setup your graphics context here

    while (!window.shouldClose()) {
        glfw.pollEvents();

        // render your things here
        
        window.swapBuffers();
    }
}

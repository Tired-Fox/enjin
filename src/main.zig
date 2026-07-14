const std = @import("std");
const Io = std.Io;

const enjin = @import("enjin");
const glfw = @import("zglfw");

const wgpu = @import("wgpu");

pub fn main(_: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.client_api, .no_api);

    const window = try glfw.Window.create(600, 600, "Enjin", null, null);
    defer window.destroy();

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        glfw.pollEvents();
    }
}

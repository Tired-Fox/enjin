const glfw = @import("zglfw");

pub const Window = @import("platform/window.zig");

pub fn init() !void {
    try glfw.init();
    glfw.windowHint(.client_api, .no_api);
}

pub fn deinit() void {
    glfw.terminate();
}

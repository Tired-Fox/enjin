const std = @import("std");
const glfw = @import("zglfw");

const _input = @import("../core/input.zig");

pub const Resize = struct { width: u32, height: u32 };

arena: std.heap.ArenaAllocator,
window: *glfw.Window,
// Is there another way to get resize event from gflw.FramebufferSizeCallback?
resized: *?Resize = undefined,

pub fn getResized(self: *const @This()) ?Resize {
    const value = self.resized.*;
    self.resized.* = null;
    return value;
}

pub fn shouldClose(self: *const @This()) bool {
    return self.window.shouldClose();
}

pub fn getKey(self: *const @This(), key: glfw.Key) glfw.Action {
    return self.window.getKey(key);
}

pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, title: [:0]const u8) !@This() {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();

    const r = try alloc.create(?Resize);
    errdefer alloc.destroy(r);
    r.* = null;

    const window = try glfw.Window.create(@bitCast(width), @bitCast(height), title, null, null);
    window.setUserPointer(@ptrCast(r));

    _ = window.setFramebufferSizeCallback(&@This().resize);
    _ = window.setKeyCallback(&_input._onKey);
    _ = window.setMouseButtonCallback(&_input._onMouseButton);
    _ = window.setCursorPosCallback(&_input._onCursorPosCallback);
    _ = window.setScrollCallback(&_input._onScrollCallback);
    _ = window.setFocusCallback(&_input._onWindowFocusCallback);

    return .{
        .arena = arena,
        .window = window,
        .resized = r,
    };
}

pub fn deinit(self: *const @This()) void {
    self.window.destroy();
    self.arena.deinit();
}

fn resize(window: *glfw.Window, width: i32, height: i32) callconv(.c) void {
    const ctx = window.getUserPointer(?Resize).?;
    ctx.* = .{ .width = @intCast(width), .height = @intCast(height) };
}

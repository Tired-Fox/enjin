const std = @import("std");
const builtin = @import("builtin");

pub const input = @import("input.zig");
pub const Window = @import("window.zig");

const glfw = @import("zglfw");
const wgpu = @import("wgpu");

const Util = switch (builtin.target.os.tag) {
    .macos => struct {
        pub extern fn setupMetalLayer(ns_window: *anyopaque) ?*anyopaque;
    },
    .windows => struct {
        extern "kernel32" fn GetModuleHandleA(
            lpModuleName: ?[*:0]const u8,
        ) callconv(.winapi) ?std.os.windows.HINSTANCE;
    },
    else => struct {},
};

pub fn createSurface(instance: *wgpu.Instance, window: *glfw.Window) !*wgpu.Surface {
    switch (builtin.target.os.tag) {
        .windows => {
            const hwnd = glfw.getWin32Window(window) orelse return error.BackendUnavailable;
            const hmodule = Util.GetModuleHandleA(null) orelse return error.BackendUnavailable;

            const surface_desc = wgpu.surfaceDescriptorFromWindowsHWND(.{
                .hwnd = hwnd,
                .hinstance = hmodule,
            });

            return instance.createSurface(&surface_desc).?;
        },
        .linux => return switch (glfw.getPlatform()) {
            .x11 => {
                const display = glfw.getX11Display() orelse return error.BackendUnavailable;
                const x11_window = glfw.getX11Window(window);

                const surface_desc = wgpu.surfaceDescriptorFromXlibWindow(.{
                    .display = display,
                    .window = x11_window,
                });

                return instance.createSurface(&surface_desc).?;
            },
            .wayland => {
                const display = glfw.getWaylandDisplay() orelse return error.BackendUnavailable;
                const wl_window = glfw.getWaylandWindow(window) orelse return error.BackendUnavailable;

                const surface_desc = wgpu.surfaceDescriptorFromWaylandSurface(.{
                    .display = display,
                    .window = wl_window,
                });

                return instance.createSurface(&surface_desc).?;
            },
            else => return error.PlatformUnsupported,
        },
        .macos => {
            // https://github.com/spencrc/hello-triangle-zig-wgpu/blob/main/src/glfw_wgpu.zig#L43
            const ns_window = glfw.getCocoaWindow(window) orelse return error.BackendUnavailable;
            const metal_layer = Util.setupMetalLayer(ns_window) orelse return error.BackendUnavailable;

            const surface_desc = wgpu.surfaceDescriptorFromMetalLayer(.{ .layer = metal_layer });

            return instance.createSurface(&surface_desc).?;
        },
        else => return error.PlatformUnsupported,
    }
}

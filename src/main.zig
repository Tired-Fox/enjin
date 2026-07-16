const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const enjin = @import("enjin");
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

pub fn main(init: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.client_api, .no_api);

    const window = try glfw.Window.create(640, 480, "Enjin", null, null);
    defer window.destroy();

    const instance = wgpu.Instance.create(null).?;
    defer instance.release();

    const surface = try createSurface(instance, window);
    defer surface.release();
    defer surface.unconfigure();

    const adapter_request = instance.requestAdapterSync(
        &wgpu.RequestAdapterOptions{
            .next_in_chain = null,
            .compatible_surface = surface,
        },
        init.io,
        Io.Duration.fromMilliseconds(0),
    );
    var adapter = switch (adapter_request.status) {
        .success => adapter_request.adapter.?,
        else => return error.NoAdapter,
    };
    defer adapter.release();

    const device_desc: wgpu.DeviceDescriptor = .{
        .required_feature_count = 0,
        .required_limits = null,
    };

    const device_request = adapter.requestDeviceSync(
        instance,
        &device_desc,
        init.io,
        Io.Duration.fromNanoseconds(0),
    );
    const device = switch (device_request.status) {
        .success => device_request.device.?,
        else => return error.NoDevice,
    };
    defer device.release();

    const queue = device.getQueue().?;
    defer queue.release();

    var capabilities: wgpu.SurfaceCapabilities = undefined;
    _ = surface.getCapabilities(adapter, &capabilities);
    const surface_format = capabilities.formats[0];

    surface.configure(&wgpu.SurfaceConfiguration{ .next_in_chain = null, .width = 640, .height = 480, .format = surface_format, .view_format_count = 0, .device = device, .present_mode = .fifo, .alpha_mode = .auto });

    // init pipeline
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{ .code = @embedFile("triangle.wgsl") })).?;
    defer shader_module.release();

    const color_targets = &[_]wgpu.ColorTargetState{
        wgpu.ColorTargetState{
            .format = surface_format,
            .blend = &wgpu.BlendState{
                .color = wgpu.BlendComponent{
                    .operation = .add,
                    .src_factor = .src_alpha,
                    .dst_factor = .one_minus_src_alpha,
                },
                .alpha = wgpu.BlendComponent{
                    .operation = .add,
                    .src_factor = .zero,
                    .dst_factor = .one,
                },
            },
        },
    };

    const pipeline = device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = .{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
        },
        .primitive = wgpu.PrimitiveState{},
        .fragment = &wgpu.FragmentState{ .module = shader_module, .entry_point = wgpu.StringView.fromSlice("fs_main"), .target_count = color_targets.len, .targets = color_targets.ptr },
        .multisample = wgpu.MultisampleState{},
    }).?;
    defer pipeline.release();

    // Main loop
    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        glfw.pollEvents();

        var surface_texture: wgpu.SurfaceTexture = undefined;
        var target_view: *wgpu.TextureView = target_view: {
            surface.getCurrentTexture(&surface_texture);
            if (surface_texture.status != .success_optimal) {
                break :target_view null;
            }

            const texture = surface_texture.texture.?;
            const view_desc: wgpu.TextureViewDescriptor = .{
                .format = texture.getFormat(),
                .dimension = .@"2d",
                .base_mip_level = 0,
                .mip_level_count = 1,
                .base_array_layer = 0,
                .array_layer_count = 1,
                .aspect = .all,
            };

            break :target_view texture.createView(&view_desc);
        } orelse continue;
        defer target_view.release();

        const encoder = device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{}).?;
        defer encoder.release();

        const color_attachments = &[_]wgpu.ColorAttachment{
            wgpu.ColorAttachment{
                .view = target_view,
                .resolve_target = null,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = wgpu.Color{ .r = 0.9, .g = 0.1, .b = 0.2, .a = 1.0 },
            },
        };

        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .color_attachment_count = color_attachments.len,
            .color_attachments = color_attachments.ptr,
        }).?;

        render_pass.setPipeline(pipeline);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();
        render_pass.release();

        const cmd = encoder.finish(&wgpu.CommandBufferDescriptor{}).?;
        defer cmd.release();

        queue.submit(&[_]*wgpu.CommandBuffer{cmd});
        _ = surface.present();
        _ = device.poll(false, &0);
    }
}

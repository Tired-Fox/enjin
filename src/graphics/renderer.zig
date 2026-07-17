const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const wgpu = @import("wgpu");
const glfw = @import("zglfw");
const stbi = @import("zstbi");

const Image = stbi.Image;

const Surface = @import("surface.zig");
const Texture = @import("texture.zig");
const Shader = @import("shader.zig");
const Mesh = @import("mesh.zig");

const _root = @import("../root.zig");
const Window = _root.platform.Window;

io: Io,

instance: *wgpu.Instance,

initialized: bool = false,
adapter: *wgpu.Adapter = undefined,
device: *wgpu.Device = undefined,
queue: *wgpu.Queue = undefined,

// pipeline
// vertex buffer
// index buffer

pub fn init(io: Io) @This() {
    return .{
        .io = io,
        .instance = wgpu.Instance.create(null).?,
    };
}

pub fn createSurface(self: *@This(), window: *const Window) !Surface {
    const surface = try createWgpuSurface(self.instance, window.window);

    if (!self.initialized) {
        try self.requestAdapter(surface);
    }

    var capabilities: wgpu.SurfaceCapabilities = undefined;
    _ = surface.getCapabilities(self.adapter, &capabilities);

    const dim = window.window.getSize();

    const configuration: wgpu.SurfaceConfiguration = .{
        .next_in_chain = null,
        .width = @intCast(dim[0]),
        .height = @intCast(dim[1]),
        .format = capabilities.formats[0],
        .view_format_count = 0,
        .device = self.device,
        .present_mode = .fifo,
        .alpha_mode = .auto,
    };
    surface.configure(&configuration);

    return .{
        .surface = surface,
        .capabilities = capabilities,
        .configuration = configuration,
    };
}

pub fn createShader(
    self: *const @This(),
    allocator: std.mem.Allocator,
    code: []const u8,
    vs_entry: []const u8,
    fs_entry: []const u8,
    options: Shader.Options,
) !Shader {
    if (!self.initialized) return error.NoSurfacesInitialized;

    const module = self.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = code,
    })) orelse return error.InvalidShaderModule;
    errdefer module.release();

    const v = try allocator.alloc(u8, vs_entry.len);
    errdefer allocator.free(v);
    @memcpy(v, vs_entry);

    const f = try allocator.alloc(u8, fs_entry.len);
    @memcpy(f, fs_entry);

    return .{
        .module = module,
        .options = options,
        .vs_entry = v,
        .fs_entry = f,
    };
}

pub fn createPipeline(
    self: *const @This(),
    format: wgpu.TextureFormat,
    shader: *const Shader,
    layout: ?*wgpu.PipelineLayout,
    label: ?[]const u8,
) !*wgpu.RenderPipeline {
    const color_targets = &[_]wgpu.ColorTargetState{
        .{
            .format = format,
            .blend = if (shader.options.blend) |blend| &blend else null,
        },
    };

    return self.device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .label = if (label) |l| .fromSlice(l) else .{},
        .layout = layout,
        .vertex = .{
            .module = shader.module,
            .entry_point = .fromSlice(shader.vs_entry),
            .buffers = &.{ Mesh.Vertex.vertex_layout() },
            .buffer_count = 1
        },
        .primitive = shader.options.primitive,
        .fragment = &.{
            .module = shader.module,
            .entry_point = .fromSlice(shader.fs_entry),
            .target_count = color_targets.len,
            .targets = color_targets.ptr,
        },
        .multisample = shader.options.multisample,
        .depth_stencil = if (shader.options.depth_stencil) |depth| &depth else null
    }) orelse return error.InvalidPipeline;
}

pub fn createMesh(self: *const @This(), vertices: []const Mesh.Vertex, indices: []const u32) !Mesh {
    return Mesh.init(self.device, self.queue, vertices, indices);
}

pub fn createTextureFromFile(self: *const @This(), kind: Texture.Kind, pathname: [:0]const u8) !Texture {
    const img_info = stbi.Image.info(pathname);
    var img = try stbi.Image.loadFromFile(pathname, img_info.num_components);
    defer img.deinit();

    std.debug.print("{d} {d} {d} {d}\n", .{ img.width, img.height, img.num_components, img.bytes_per_component });

    return Texture.init(self.device, self.queue, kind, .{
        .height = img.height,
        .width = img.width,
        .bytes_per_pixel = 4,
        .data = img.data,
    });
}

fn requestAdapter(self: *@This(), surface: *wgpu.Surface) !void {
    const adapter_request = self.instance.requestAdapterSync(
        &.{
            .next_in_chain = null,
            .compatible_surface = surface,
        },
        self.io,
        .zero,
    );
    var adapter = switch (adapter_request.status) {
        .success => adapter_request.adapter.?,
        else => return error.NoAdapter,
    };
    errdefer adapter.release();

    const device_desc: wgpu.DeviceDescriptor = .{
        .required_feature_count = 0,
        .required_limits = null,
    };

    const device_request = adapter.requestDeviceSync(
        self.instance,
        &device_desc,
        self.io,
        .zero,
    );
    var device = switch (device_request.status) {
        .success => device_request.device.?,
        else => return error.NoDevice,
    };
    errdefer device.release();

    const queue = device.getQueue().?;
    errdefer queue.release();

    if (self.initialized) {
        self.queue.release();
        self.device.release();
        self.adapter.release();
    }

    self.initialized = true;
    self.adapter = adapter;
    self.device = device;
    self.queue = queue;
}

pub fn deinit(self: *const @This()) void {
    self.queue.release();
    self.device.release();
    self.adapter.release();
    self.instance.release();
}

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

fn createWgpuSurface(instance: *wgpu.Instance, window: *glfw.Window) !*wgpu.Surface {
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

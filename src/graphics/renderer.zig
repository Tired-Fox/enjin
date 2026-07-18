const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const wgpu = @import("wgpu");
const glfw = @import("zglfw");
const stbi = @import("zstbi");

const Image = stbi.Image;

const ResourceManager = @import("resource_manager.zig");
const Handle = ResourceManager.Handle;

const Surface = @import("surface.zig");
const Pipeline = @import("pipeline.zig");
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

resources: ResourceManager,

pub fn init(io: Io, allocator: std.mem.Allocator) @This() {
    return .{
        .io = io,
        .resources = ResourceManager.init(io, allocator),
        .instance = wgpu.Instance.create(null).?,
    };
}

pub fn deinit(self: *@This()) void {
    self.resources.deinit();
    self.queue.release();
    self.device.release();
    self.adapter.release();
    self.instance.release();
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

pub fn getOrLoadShader(
    self: *@This(),
    pathname: []const u8,
    bind_groups: []const []const wgpu.BindGroupLayoutEntry,
) !Handle {
    if (!self.initialized) return error.NoSurfacesInitialized;

    const handle = ResourceManager.getShaderHandle(pathname);
    if (self.resources.getShader(handle) != null) return handle;
    _ = try self.resources.loadShader(self, pathname, bind_groups);

    return handle;
}

pub fn getShader(
    self: *const @This(),
    handle: Handle
) ?*const Shader {
    return self.resources.getShader(handle);
}

pub fn getShaderBindGroupLayout(
    self: *const @This(),
    handle: Handle,
    index: usize,
) !*wgpu.BindGroupLayout {
    if (self.resources.shader_to_bind_group_layouts.get(handle)) |layouts| {
        const handles = layouts.keys();
        if (index >= handles.len) return error.OutOfBounds;
        if (self.resources.bind_group_layouts.get(handles[index])) |layout| {
            return layout;
        }
    }

    return error.OutOfBounds;
}

pub fn getOrLoadBindGroup(self: *@This(), shader: Handle, index: usize, entries: []const wgpu.BindGroupEntry) !Handle {
    const key = ResourceManager.getBindGroupHandle(shader, index, entries);
    if (self.resources.getBindGroup(key) != null) return key;
    _ = try self.resources.loadBindGroup(self.device, shader, index, entries);
    return key;
}

pub fn getBindGroup(self: *@This(), handle: Handle) ?*wgpu.BindGroup {
    return self.resources.getBindGroup(handle);
}

/// Note: Shader must have already be created as it will not
/// be loaded in this function
pub fn getOrLoadPipeline(
    self: *@This(),
    shader_handle: Handle,
    options: Pipeline.Options,
) !Handle {
    if (!self.initialized) return error.NoSurfacesInitialized;

    const shader = self.resources.getShader(shader_handle) orelse return error.ShaderNotLoaded;
    const handle = ResourceManager.getPipelineHandle(shader_handle, options);

    if (self.resources.getPipeline(handle) != null) return handle;
    _ = try self.resources.loadPipeline(self, shader_handle, shader, options);

    return handle;
}

pub fn getPipeline(
    self: *const @This(),
    handle: Handle
) ?*const Pipeline {
    return self.resources.getPipeline(handle);
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

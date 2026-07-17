const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const glfw = @import("zglfw");
const wgpu = @import("wgpu");

const enjin = @import("enjin");
const input = enjin.input;
const Window = enjin.Window;

pub const Surface = struct {
    surface: *wgpu.Surface,
    configuration: wgpu.SurfaceConfiguration,
    capabilities: wgpu.SurfaceCapabilities,

    pub fn release(self: @This()) void {
        self.surface.unconfigure();
        self.surface.release();
    }

    pub fn resize(self: *@This(), width: u32, height: u32) void {
        self.configuration.width = width;
        self.configuration.height = height;
        self.surface.configure(&self.configuration);
    }

    pub fn format(self: *const @This()) wgpu.TextureFormat {
        return self.capabilities.formats[0];
    }

    pub fn present(self: *const @This()) wgpu.Status {
        return self.surface.present();
    }

    pub fn getCurrentTexture(self: *const @This()) ?*wgpu.Texture {
        var texture: wgpu.SurfaceTexture = undefined;
        self.surface.getCurrentTexture(&texture);
        if (texture.status != .success_optimal) {
            return null;
        }
        return texture.texture.?;
    }

    pub fn getCurrentTextureView(self: *const @This(), descriptor: wgpu.TextureViewDescriptor) ?*wgpu.TextureView {
        const texture = self.getCurrentTexture() orelse return null;
        return texture.createView(&.{
            .format = texture.getFormat(),
            .label = descriptor.label,
            .dimension = descriptor.dimension,
            .base_mip_level = descriptor.base_mip_level,
            .mip_level_count = descriptor.mip_level_count,
            .base_array_layer = descriptor.base_array_layer,
            .array_layer_count = descriptor.array_layer_count,
            .aspect = descriptor.aspect,
            .usage = descriptor.usage,
        });
    }
};

pub const Renderer = struct {
    io: Io,

    instance: *wgpu.Instance,

    initialized: bool = false,
    adapter: *wgpu.Adapter = undefined,
    device: *wgpu.Device = undefined,
    queue: *wgpu.Queue = undefined,

    // pipeline
    // vertex buffer
    // index buffer

    pub fn init(io: Io) !@This() {
        try glfw.init();
        glfw.windowHint(.client_api, .no_api);

        return .{
            .io = io,
            .instance = wgpu.Instance.create(null).?,
        };
    }

    pub fn createSurface(self: *@This(), window: *const Window) !Surface {
        const surface = try enjin.createSurface(self.instance, window.window);

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

        const f = allocator.alloc(u8, fs_entry.len);
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
            .layout = shader.options.layout,
            .vertex = .{
                .module = shader.module,
                .entry_point = .fromSlice(shader.vs_entry),
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

        glfw.terminate();
    }
};

pub const Shader = struct {
    module: *wgpu.ShaderModule,
    vs_entry: []const u8,
    fs_entry: []const u8,
    options: Options,

    // TODO: Split this based on the settings that differ
    // between pipeline variants. Anything that is shared
    // stays here and the differences are used to cache + key
    // unique pipelines.
    pub const Options = struct {
        layout: ?*wgpu.PipelineLayout = null,
        blend: ?wgpu.BlendState = null,
        depth_stencil: ?wgpu.DepthStencilState = null,
        primitive: wgpu.PrimitiveState = .{},
        multisample: wgpu.MultisampleState = .{},
    };

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        self.module.release();
        allocator.free(self.vs_entry);
        allocator.free(self.fs_entry);
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    // Prints to stderr, unbuffered, ignoring potential errors.
    var renderer = try Renderer.init(init.io);
    defer renderer.deinit();

    const window = try Window.init(init.arena.allocator(), 640, 480, "Enjin");
    defer window.deinit();

    var surface = try renderer.createSurface(&window);
    defer surface.release();

    // Per wgsl shader / graph
    const shader = try renderer.createShader(
        allocator,
        // Any wgsl source content as a string
        @embedFile("triangle.wgsl"),
        // function annotated with @vertex which is the entry for the vertex shader
        "vs_main",
        // function annotated with @fragment which is the entry for the fragment shader
        "fs_main",
        .{
            .blend = .{
                .color = .{
                    .operation = .add,
                    .src_factor = .src_alpha,
                    .dst_factor = .one_minus_src_alpha,
                },
                .alpha = .{
                    .operation = .add,
                    .src_factor = .zero,
                    .dst_factor = .one,
                },
            },
        }
    );
    defer shader.deinit();

    // Per TextureFormat variant SDR / HDR
    //
    // Can lazy build as the output format is needed
    const pipeline = try renderer.createPipeline(surface.format(), &shader, null);
    defer pipeline.release();

    // TODO: Caching system for shader and pipelines and lazy build + cache piplines based on current output format
    // and SDR vs. HDR

    while (!window.shouldClose() and !(input.getKeyDown(.escape) and input.hasModifier(.shift))) {
        input.poll();

        // OnUpdate
        if (window.getResized()) |resize| {
            surface.resize(resize.width, resize.height);
        }

        const texture_view = surface.getCurrentTextureView(.{
            .dimension = .@"2d",
            .mip_level_count = 1,
            .array_layer_count = 1,
        }) orelse continue;
        defer texture_view.release();

        const encoder = renderer.device.createCommandEncoder(&.{}).?;
        defer encoder.release();

        const color_attachments = &[_]wgpu.ColorAttachment{
            .{
                .view = texture_view,
                .resolve_target = null,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
            },
        };

        const render_pass = encoder.beginRenderPass(&.{
            .color_attachment_count = color_attachments.len,
            .color_attachments = color_attachments.ptr,
        }).?;

        render_pass.setPipeline(pipeline);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();
        render_pass.release();

        const cmd = encoder.finish(&.{}).?;
        defer cmd.release();

        renderer.queue.submit(&.{cmd});
        _ = surface.present();

        _ = renderer.device.poll(false, &0);
    }
}

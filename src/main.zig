const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const glfw = @import("zglfw");
const wgpu = @import("wgpu");
const stbi = @import("zstbi");

const enjin = @import("enjin");
const input = enjin.core.input;
const platform = enjin.platform;
const gfx = enjin.gfx;

const Window = platform.Window;
const Renderer = gfx.Renderer;
const Mesh = gfx.Mesh;
const Texture = gfx.Texture;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    stbi.init(io, allocator);
    defer stbi.deinit();

    try platform.init();
    defer platform.deinit();

    // Stores state like adapter, device, queue, and instance for wgpu
    var renderer = Renderer.init(io);
    defer renderer.deinit();

    // Is there a way to get rid of this allocation?
    // The window state is allocated so it can edited by a resize callback
    // to get the resize event.
    const window = try Window.init(allocator, 640, 480, "Enjin");
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
        },
    );
    defer shader.deinit(allocator);

    const texture = try renderer.createTextureFromFile(.albedo, "cat-in-the-hat-bonk.png");
    defer texture.deinit();

    const texture_view = texture.texture.createView(&wgpu.TextureViewDescriptor{ .label = .fromSlice("Default Texture View") }) orelse return error.NoTextureView;
    defer texture_view.release();

    const sampler = renderer.device.createSampler(&wgpu.SamplerDescriptor{
        .label = .fromSlice("Linear Clamp"),
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_filter = .linear,
    }) orelse return error.NoSampler;
    defer sampler.release();


    const bind_layout = renderer.device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
        .label = .fromSlice("Albedo Texture Bind Group Layout"),
        .entry_count = 2,
        .entries = &.{ .{
            .binding = 0,
            .visibility = wgpu.ShaderStages.fragment,
            .sampler = .{ .type = .filtering },
        }, .{ .binding = 1, .visibility = wgpu.ShaderStages.fragment, .texture = .{
            .sample_type = .float,
            .view_dimension = .@"2d",
            .multisampled = @intFromBool(false),
        } } },
    }) orelse return error.NoBindGroupLayout;
    defer bind_layout.release();

    const pipeline_layout = renderer.device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
        .label = .fromSlice("Default Pipeline Layout"),
        .bind_group_layout_count = 1,
        .bind_group_layouts = &.{bind_layout},
        .immediate_size = 0,
    });

    // Per TextureFormat variant SDR / HDR
    //
    // Can lazy build as the output format is needed
    const pipeline = try renderer.createPipeline(surface.format(), &shader, pipeline_layout, "Default Pipeline");
    defer pipeline.release();

    const bind_group = renderer.device.createBindGroup(&wgpu.BindGroupDescriptor{
        .label = .fromSlice("Albedo Texture Bind Group"),
        .layout = bind_layout,
        .entry_count = 2,
        .entries = &.{
            wgpu.BindGroupEntry{ .binding = 0, .sampler = sampler },
            wgpu.BindGroupEntry{ .binding = 1, .texture_view = texture_view },
        },
    }) orelse return error.NoBindGroup;
    defer bind_group.release();


    const w: f32 = @floatFromInt(texture.width);
    const h: f32 = @floatFromInt(texture.height);
    const lower = ((w / 2) - (h / 2)) / w;
    const upper = ((w / 2) + (h / 2)) / w;

    const triangle_mesh = try renderer.createMesh(
        &.{
            .{
                .position = .{ -0.5, -0.5, 0.0, 1.0 },
                .uv = .{ lower, 1.0 },
                .color = .{ 1.0, 0.0, 0.0, 1.0 },
            },
            .{
                .position = .{ -0.5, 0.5, 0.0, 1.0 },
                .uv = .{ lower, 0.0 },
                .color = .{ 0.0, 1.0, 0.0, 1.0 },
            },
            .{
                .position = .{ 0.5, 0.5, 0.0, 1.0 },
                .uv = .{ upper, 0.0 },
                .color = .{ 0.0, 0.0, 1.0, 1.0 },
            },
            .{
                .position = .{ 0.5, -0.5, 0.0, 1.0 },
                .uv = .{ upper, 1.0 },
                .color = .{ 0.0, 0.0, 1.0, 1.0 },
            },
        },
        &.{ 0, 1, 2, 0, 2, 3 },
    );
    defer triangle_mesh.deinit();

    // TODO: Caching system for shader and pipelines and lazy build + cache piplines based on current output format
    // and SDR vs. HDR

    while (!window.shouldClose() and !(input.getKeyDown(.escape) and input.hasModifier(.shift))) {
        input.poll();

        // OnUpdate
        if (window.getResized()) |resize| {
            surface.resize(resize.width, resize.height);
        }

        const current_texture_view = surface.getCurrentTextureView(.{
            .dimension = .@"2d",
            .mip_level_count = 1,
            .array_layer_count = 1,
        }) orelse continue;
        defer current_texture_view.release();

        const encoder = renderer.device.createCommandEncoder(&.{}).?;
        defer encoder.release();

        const color_attachments = &[_]wgpu.ColorAttachment{
            .{
                .view = current_texture_view,
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
        render_pass.setBindGroup(0, bind_group, 0, null);
        render_pass.setVertexBuffer(0, triangle_mesh.vertex, 0, triangle_mesh.vertex_size);
        render_pass.setIndexBuffer(triangle_mesh.index, .uint32, 0, triangle_mesh.index_size);
        render_pass.drawIndexed(triangle_mesh.index_count, 1, 0, 0, 0);

        render_pass.end();
        render_pass.release();

        const cmd = encoder.finish(&.{}).?;
        defer cmd.release();

        renderer.queue.submit(&.{cmd});
        _ = surface.present();

        _ = renderer.device.poll(false, &0);
    }
}

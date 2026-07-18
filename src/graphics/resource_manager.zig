const std = @import("std");
const Io = std.Io;
const wgpu = @import("wgpu");

const Renderer = @import("renderer.zig");

const Shader = @import("shader.zig");
const Pipeline = @import("pipeline.zig");
const Texture = @import("texture.zig");
const Mesh = @import("mesh.zig");
const Material = @import("material.zig");

pub const Handle = u64;

io: Io,
arena: std.heap.ArenaAllocator,

shaders: std.AutoArrayHashMapUnmanaged(Handle, Shader) = .empty,
bind_group_layouts: std.AutoArrayHashMapUnmanaged(Handle, *wgpu.BindGroupLayout) = .empty,
shader_to_bind_group_layouts: std.AutoArrayHashMapUnmanaged(Handle, std.AutoArrayHashMapUnmanaged(Handle, void)) = .empty,

pipeline_layouts: std.AutoArrayHashMapUnmanaged(Handle, *wgpu.PipelineLayout) = .empty,
pipelines: std.AutoArrayHashMapUnmanaged(Handle, Pipeline) = .empty,

bind_groups: std.AutoArrayHashMapUnmanaged(Handle, *wgpu.BindGroup) = .empty,

samplers: std.AutoArrayHashMapUnmanaged(Handle, *wgpu.Sampler) = .empty,
textures: std.AutoArrayHashMapUnmanaged(Handle, Texture) = .empty,
meshes: std.AutoArrayHashMapUnmanaged(Handle, Mesh) = .empty,

materials: std.AutoArrayHashMapUnmanaged(Handle, Material) = .empty,

pub fn init(io: Io, allocator: std.mem.Allocator) @This() {
    return .{
        .io = io,
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
}

pub fn deinit(self: *@This()) void {
    defer self.arena.deinit();

    for (self.shaders.values()) |*shader| shader.deinit();
    for (self.bind_group_layouts.values()) |layout| layout.release();
    for (self.pipeline_layouts.values()) |layout| layout.release();
    for (self.pipelines.values()) |*pipeline| pipeline.deinit();
    for (self.bind_groups.values()) |bind_group| bind_group.release();
    for (self.samplers.values()) |sampler| sampler.release();
    for (self.textures.values()) |*texture| texture.deinit();
    for (self.meshes.values()) |*mesh| mesh.deinit();
    for (self.materials.values()) |*material| material.deinit();
}

pub fn getBindGroupLayoutHandle(entries: []const wgpu.BindGroupLayoutEntry) Handle {
    var hasher = std.hash.Wyhash.init(0);
    for (entries) |entry| std.hash.autoHash(&hasher, entry);
    return hasher.final();
}

pub fn loadBindGroupLayout(self: *@This(), device: *wgpu.Device, entries: []const wgpu.BindGroupLayoutEntry) !*wgpu.BindGroupLayout {
    const allocator = self.arena.allocator();
    const key = getBindGroupLayoutHandle(entries);

    const result = try self.bind_group_layouts.getOrPut(allocator, key);
    if (!result.found_existing) {
        errdefer _ = self.bind_group_layouts.swapRemove(key);

        result.value_ptr.* = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
            .entry_count = entries.len,
            .entries = entries.ptr,
        }) orelse return error.NoBindGroupLayout;
    }

    return result.value_ptr.*;
}

pub inline fn getBindGroupLayout(self: *@This(), handle: Handle) ?*wgpu.BindGroupLayout {
    return self.bind_group_layouts.get(handle);
}

pub inline fn getShaderHandle(pathname: []const u8) Handle {
    return std.hash.Wyhash.hash(0, pathname);
}

pub fn loadShader(
    self: *@This(),
    renderer: *const Renderer,
    pathname: []const u8,
    bind_groups: []const []const wgpu.BindGroupLayoutEntry,
) !*const Shader {
    const allocator = self.arena.allocator();

    const key = std.hash.Wyhash.hash(0, pathname);

    const result = try self.shaders.getOrPut(allocator, key);
    if (result.found_existing) return result.value_ptr;
    errdefer _ = self.shaders.swapRemove(key);

    // TODO: Resource manager should have state to lookup the shader in local dir
    // or in bundled asset packs in production/release
    const code = try Io.Dir.cwd().readFileAlloc(self.io, pathname, allocator, .unlimited);
    defer allocator.free(code);

    const module = renderer.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .label = pathname,
        .code = code,
    })) orelse return error.InvalidShaderModule;
    errdefer module.release();

    result.value_ptr.* = .{ .module = module };

    // Automatically add the BindGroupLayout's that are associated with the layout
    const mapping_result = try self.shader_to_bind_group_layouts.getOrPut(allocator, key);
    if (!mapping_result.found_existing) mapping_result.value_ptr.* = .empty;

    for (bind_groups) |bind_group| {
        const bind_key = getBindGroupLayoutHandle(bind_group);
        if (self.getBindGroupLayout(bind_key) == null)
            _ = try self.loadBindGroupLayout(renderer.device, bind_group);

        const entry_result = try mapping_result.value_ptr.*.getOrPut(allocator, bind_key);
        if (!entry_result.found_existing) entry_result.value_ptr.* = {};
    }

    return result.value_ptr;
}

pub fn getShaderBindGroupLayouts(self: *@This(), handle: Handle) ?[]const Handle {
    const handles = self.shader_to_bind_group_layouts.getPtr(handle);
    return if (handles) |h| h.keys() else null;
}

pub inline fn getShader(self: *const @This(), handle: Handle) ?*const Shader {
    return self.shaders.getPtr(handle);
}

pub fn getBindGroupHandle(shader: Handle, index: usize, entries: []const wgpu.BindGroupEntry) Handle {
    var hasher = std.hash.Wyhash.init(0);
    std.hash.autoHash(&hasher, shader);
    std.hash.autoHash(&hasher, index);
    for (entries) |entry| {
        std.hash.autoHash(&hasher, entry.binding);
        std.hash.autoHash(&hasher, entry.offset);
        std.hash.autoHash(&hasher, entry.size);
        // TODO: Cache with the actual value of buffer, sampler, and texture_view
        // This will be the handle instead of the pointer here
        std.hash.autoHash(&hasher, @intFromPtr(entry.buffer));
        std.hash.autoHash(&hasher, @intFromPtr(entry.sampler));
        std.hash.autoHash(&hasher, @intFromPtr(entry.texture_view));
    }
    return hasher.final();
}

pub fn loadBindGroup(
    self: *@This(),
    device: *wgpu.Device,
    shader: Handle,
    index: usize,
    entries: []const wgpu.BindGroupEntry,
) !*wgpu.BindGroup {
    const allocator = self.arena.allocator();

    const key = getBindGroupHandle(shader, index, entries);
    const result = try self.bind_groups.getOrPut(allocator, key);

    if (!result.found_existing) {
        errdefer _ = self.bind_groups.swapRemove(key);

        var layout_id: u64 = 0;
        if (self.shader_to_bind_group_layouts.get(shader)) |layouts| {
            const handles = layouts.keys();
            if (index >= handles.len) return error.OutOfBounds;
            layout_id = handles[index];
        } else {
            return error.OutOfBounds;
        }

        const layout = self.bind_group_layouts.get(layout_id) orelse return error.MissingBindGroupLayout;
        result.value_ptr.* = device.createBindGroup(&wgpu.BindGroupDescriptor{
            .layout = layout,
            .entry_count = entries.len,
            .entries = entries.ptr,
        }) orelse return error.NoBindGroup;
    }

    return result.value_ptr.*;
}

pub inline fn getBindGroup(self: *@This(), handle: Handle) ?*wgpu.BindGroup {
    return self.bind_groups.get(handle);
}

pub fn getPipelineLayoutHandle(bind_groups: []const Handle) Handle {
    var hasher = std.hash.Wyhash.init(0);
    for (bind_groups) |bind_group| std.hash.autoHash(&hasher, bind_group);
    return hasher.final();
}

pub fn loadPipelineLayout(self: *@This(), device: *wgpu.Device, handles: []const Handle) !*wgpu.PipelineLayout {
    const allocator = self.arena.allocator();

    const key = getPipelineLayoutHandle(handles);
    const result = try self.pipeline_layouts.getOrPut(allocator, key);

    if (!result.found_existing) {
        errdefer _ = self.pipeline_layouts.swapRemove(key);

        const bind_groups = try allocator.alloc(*wgpu.BindGroupLayout, handles.len);
        defer allocator.free(bind_groups);
        for (handles, 0..) |handle, i| {
            bind_groups[i] = self.getBindGroupLayout(handle) orelse return error.MissingBindGroupLayout;
        }

        result.value_ptr.* = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .bind_group_layout_count = bind_groups.len,
            .bind_group_layouts = bind_groups.ptr,
            .immediate_size = 0,
        }) orelse return error.NoPipelineLayout;
    }

    return result.value_ptr.*;
}

pub fn getPipelineLayout(self: *@This(), handle: Handle) ?*wgpu.PipelineLayout {
    return self.pipeline_layouts.get(handle);
}

pub fn getPipelineHandle(shader: Handle, options: Pipeline.Options) Handle {
    var hasher = std.hash.Wyhash.init(0);
    std.hash.autoHash(&hasher, shader);
    std.hash.autoHash(&hasher, options.blend);
    std.hash.autoHash(&hasher, options.primitive);
    std.hash.autoHash(&hasher, options.multisample);

    // Depth Stencil: Manual hashing required since floats cannot be auto hashed
    if (options.depth_stencil) |depth_stencil| {
        if (depth_stencil.next_in_chain) |nic| {
            std.hash.autoHash(&hasher, nic);
        }
        std.hash.autoHash(&hasher, depth_stencil.format);
        std.hash.autoHash(&hasher, depth_stencil.depth_write_enabled);
        std.hash.autoHash(&hasher, depth_stencil.depth_compare);
        std.hash.autoHash(&hasher, depth_stencil.stencil_front);
        std.hash.autoHash(&hasher, depth_stencil.stencil_back);
        std.hash.autoHash(&hasher, depth_stencil.stencil_read_mask);
        std.hash.autoHash(&hasher, depth_stencil.stencil_write_mask);
        std.hash.autoHash(&hasher, depth_stencil.depth_bias);

        hasher.update(std.mem.asBytes(&depth_stencil.depth_bias_clamp));
        hasher.update(std.mem.asBytes(&depth_stencil.depth_bias_clamp));
    }

    return hasher.final();
}

pub fn loadPipeline(
    self: *@This(),
    renderer: *const Renderer,
    shader_handle: Handle,
    shader: *const Shader,
    options: Pipeline.Options,
) !*const Pipeline {
    const allocator = self.arena.allocator();

    const key = getPipelineHandle(shader_handle, options);

    const result = try self.pipelines.getOrPut(allocator, key);
    if (!result.found_existing) {
        errdefer _ = self.shaders.swapRemove(key);

        var pipeline_layout: ?*wgpu.PipelineLayout = null;
        if (self.shader_to_bind_group_layouts.get(shader_handle)) |layouts| {
            const handles = layouts.keys();
            const pipeline_layout_key = getPipelineLayoutHandle(handles);

            if (self.getPipelineLayout(pipeline_layout_key)) |pl| pipeline_layout = pl;
            pipeline_layout = try self.loadPipelineLayout(renderer.device, handles);
        }

        const color_targets = &[_]wgpu.ColorTargetState{
            .{
                .format = options.format,
                .blend = if (options.blend) |blend| &blend else null,
            },
        };

        result.value_ptr.* = .{
            .render_pipeline = renderer.device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
                .label = if (options.label) |l| .fromSlice(l) else .{},
                .layout = pipeline_layout,
                .vertex = .{
                    .module = shader.module,
                    .entry_point = .fromSlice(options.vs_entry),
                    .buffers = &.{Mesh.Vertex.vertex_layout()},
                    .buffer_count = 1,
                },
                .primitive = options.primitive,
                .fragment = &.{
                    .module = shader.module,
                    .entry_point = .fromSlice(options.fs_entry),
                    .target_count = color_targets.len,
                    .targets = color_targets.ptr,
                },
                .multisample = options.multisample,
                .depth_stencil = if (options.depth_stencil) |depth| &depth else null,
            }) orelse return error.InvalidPipeline,
        };
    }

    return result.value_ptr;
}

pub inline fn getPipeline(self: *const @This(), handle: Handle) ?*const Pipeline {
    return self.pipelines.getPtr(handle);
}

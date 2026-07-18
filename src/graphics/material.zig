const std = @import("std");
const wgpu = @import("wgpu");


const TextureView = wgpu.TextureView;
const Color = wgpu.Color;

const ResourceManager = @import("resource_manager.zig");
const Handle = ResourceManager.Handle;

pub const RenderMode = enum {
    @"opaque",
    transparent,
};

pub const Smoothness = enum(u32) {
    metallic_alpha,
    albedo_alpha,
};

pub const Properties = extern struct {
    albedo: ?Color = null,
    metallic: f32 = 0.0,
    smoothness: f32 = 0.0,
    smoothness_source: Smoothness = .metallic_alpha,
    emission: bool = false,
    tiling: @Vector(2, f32) = .{ 1.0, 1.0 },
    offset: @Vector(2, f32) = .{ 0.0, 0.0 },
};

shader: Handle,
mode: RenderMode = .@"opaque",

samplers: []const Handle,

// Textures (wgpu::TextureView)
normal_map: ?Handle = null,
height_map: ?Handle = null,
occlusion: ?Handle = null,
detail_mask: ?Handle = null,

pub fn init() void {
    // TODO: Creating a material will:
    //  1. Create the shader resource
    //  2. Create the bind group + layout
    //  3. Create the textures + samplers
    //  4. Create the pipeline + layout
    //  5. Create the uniform buffer
}

pub fn deinit(self: *const @This()) void {
    _ = self;
    // TODO: free arrays of handles
}

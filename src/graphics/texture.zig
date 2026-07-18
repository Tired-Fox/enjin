//! WIP
//!
//! I am slowely collection my ideas and what data I want to be contained
//! within the texture
const std = @import("std");
const wgpu = @import("wgpu");
const stbi = @import("zstbi");

const _core = @import("../core.zig");
const Image = _core.Image;

pub const Kind = enum {
    albedo,
    normal,
    depth,
};

texture: *wgpu.Texture,
views: std.AutoArrayHashMapUnmanaged(wgpu.TextureViewDescriptor, *wgpu.TextureView) = .empty,

format: wgpu.TextureFormat,
width: u32,
height: u32,

pub fn init(device: *wgpu.Device, queue: *wgpu.Queue, kind: Kind, image: Image) !@This() {
    const wgpu_texture = device.createTexture(&wgpu.TextureDescriptor{
        .label = .fromSlice(@tagName(kind)),
        .usage = wgpu.TextureUsages.texture_binding | wgpu.TextureUsages.copy_dst,
        .dimension = .@"2d",
        .format = .rgba8_unorm_srgb,
        .sample_count = 1,
        .mip_level_count = 1,
        .size = .{ .width = image.width, .height = image.height, .depth_or_array_layers = 1 },
    }) orelse return error.NoTexture;

    queue.writeTexture(
        &wgpu.TexelCopyTextureInfo{
            .texture = wgpu_texture,
            .origin = .{ .x = 0, .y = 0, .z = 0 },
        }, 
        @ptrCast(image.data.ptr),
        @intCast(image.data.len),
        &wgpu.TexelCopyBufferLayout{
            .offset = 0,
            .bytes_per_row = image.width * 4,
            .rows_per_image = image.height,
        }, 
        &wgpu.Extent3D{
            .width = image.width,
            .height = image.height,
            .depth_or_array_layers = 1,
        },
    );

    return .{
        .texture = wgpu_texture,

        .width = image.width,
        .height = image.height,
        .format = .rgba8_unorm_srgb,
    };
}

pub fn getDimension(self: *const @This()) wgpu.TextureDimension {
    return self.texture.getDimension();
}

pub fn multisampled(self: *const @This()) bool {
    return self.texture.getSampleCount() > 1;
}

pub fn deinit(self: *const @This()) void {
    self.texture.release();
}

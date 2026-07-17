const std = @import("std");

const wgpu = @import("wgpu");
const glfw = @import("zglfw");

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

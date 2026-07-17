const std = @import("std");

const wgpu = @import("wgpu");

module: *wgpu.ShaderModule,
vs_entry: []const u8,
fs_entry: []const u8,
options: Options,

// TODO: Split this based on the settings that differ
// between pipeline variants. Anything that is shared
// stays here and the differences are used to cache + key
// unique pipelines.
pub const Options = struct {
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

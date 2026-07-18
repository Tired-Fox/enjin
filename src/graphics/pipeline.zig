const wgpu = @import("wgpu");

pub const Options = struct {
    vs_entry: []const u8,
    fs_entry: []const u8,

    label: ?[]const u8,
    format: wgpu.TextureFormat,
    blend: ?wgpu.BlendState = null,
    depth_stencil: ?wgpu.DepthStencilState = null,
    primitive: wgpu.PrimitiveState = .{},
    multisample: wgpu.MultisampleState = .{},
};

render_pipeline: *wgpu.RenderPipeline,

pub fn deinit(self: *const @This()) void {
    self.render_pipeline.release();
}

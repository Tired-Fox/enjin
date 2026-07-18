const std = @import("std");

const wgpu = @import("wgpu");
const Handle = @import("resource_manager.zig").Handle;

module: *wgpu.ShaderModule,

pub fn deinit(self: *const @This()) void {
    self.module.release();
}

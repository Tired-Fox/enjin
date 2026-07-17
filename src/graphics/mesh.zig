const zm = @import("zmath");
const wgpu = @import("wgpu");

pub const Vertex = extern struct {
    position: @Vector(4, f32) = .{ 0.0, 0.0, 0.0, 0.0 },
    normal: @Vector(4, f32) = .{ 0.0, 0.0, 0.0, 0.0 },
    tangent: @Vector(4, f32) = .{ 0.0, 0.0, 0.0, 0.0 },
    uv: @Vector(2, f32) = .{ 0.0, 0.0 },
    color: @Vector(4, f32) = .{ 0.0, 0.0, 0.0, 0.0 },

    const VERTEX_ATTRIBUTES: [5]wgpu.VertexAttribute = .{
        wgpu.VertexAttribute{ .format = .float32x4, .offset = 0, .shader_location = 0 },
        wgpu.VertexAttribute{ .format = .float32x4, .offset = @offsetOf(@This(), "normal"), .shader_location = 1 },
        wgpu.VertexAttribute{ .format = .float32x4, .offset = @offsetOf(@This(), "tangent"), .shader_location = 2 },
        wgpu.VertexAttribute{ .format = .float32x2, .offset = @offsetOf(@This(), "uv"), .shader_location = 3 },
        wgpu.VertexAttribute{ .format = .float32x4, .offset = @offsetOf(@This(), "color"), .shader_location = 4 },
    };

    pub fn vertex_layout() wgpu.VertexBufferLayout {
        return wgpu.VertexBufferLayout {
            .array_stride = @sizeOf(Vertex),
            .step_mode = wgpu.VertexStepMode.vertex,
            .attribute_count = VERTEX_ATTRIBUTES.len,
            .attributes = &VERTEX_ATTRIBUTES,
        };
    }
};

vertex: *wgpu.Buffer,
vertex_count: u32,
vertex_size: u64,
index: *wgpu.Buffer,
index_count: u32,
index_size: u64,

// TODO: Build from data types and from common shapes

pub fn init(device: *wgpu.Device, queue: *wgpu.Queue, vertices: []const Vertex, indices: []const u32) !@This() {
    const vertex_buffer = device.createBuffer(&wgpu.BufferDescriptor {
        .label = .fromSlice("triangle vertices"),
        .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
        .size = @sizeOf(Vertex) * vertices.len,
    }) orelse return error.NoVertexBuffer;
    errdefer vertex_buffer.release();
    // Queue mesh vertices upload
    queue.writeBuffer(vertex_buffer, 0, @ptrCast(vertices), @sizeOf(Vertex) * vertices.len);

    const index_buffer = device.createBuffer(&wgpu.BufferDescriptor {
        .label = .fromSlice("triangle indices"),
        .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
        .size = @sizeOf(u32) * indices.len,
    }) orelse return error.NoIndexBuffer;
    errdefer index_buffer.release();
    // Queue mesh indices upload
    queue.writeBuffer(index_buffer, 0, @ptrCast(indices), @sizeOf(u32) * indices.len);

    return .{
        .vertex = vertex_buffer,
        .vertex_count = @intCast(vertices.len),
        .vertex_size = @intCast(@sizeOf(Vertex) * vertices.len),
        .index = index_buffer,
        .index_count = @intCast(indices.len),
        .index_size = @intCast(@sizeOf(u32) * indices.len),
    };
}

pub fn deinit(self: *const @This()) void {
    self.vertex.release();
    self.index.release();
}

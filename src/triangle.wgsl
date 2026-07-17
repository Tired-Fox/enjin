@group(0) @binding(0) var samp: sampler;
@group(0) @binding(1) var tex : texture_2d<f32>;

struct Output {
    @builtin(position) position : vec4f,
    @location(0)       color    : vec4f,
    @location(1)       uv       : vec2f,
}

@vertex
fn vs_main(
    @location(0) position : vec4f,
    @location(3) uv       : vec2f,
    @location(4) color    : vec4f
) -> Output {
    var out : Output;

    out.position = position;
    out.uv = uv;
    out.color = color;

    return out;
}

@fragment
fn fs_main(
    @location(0) color: vec4f,
    @location(1) uv: vec2f
) -> @location(0) vec4f {
    // return color;
    return textureSample(tex, samp, uv);
}

# Notes

This is a collection of notes written while researching and developing this project.

## Shaders, Materials, Meshes

A shader describes how a surface should be rendered. A "Material" is an instance of the shader containing data like specific textures, roughness variable, bind groups, etc. Based on the format of the surface the shader will choose a pipeline that is compiled for that format. A mesh is purely geometry like vertex buffer, index buffer, and vertex layout.

A render component would have something like a mesh and a material. Where the Material is a specific instance of a shader containing variables, textures, and the data needed for the shader that isn't individual vertexes.

1. Material fetches grabs it's shader and has it fetch the required cached pipeline based on the render target
2. The pipeline + shader are given the textures, and other data from the mesh
3. The pipeline + shader are given the vertex + index buffers along with vertex layout from the mesh
4. The pipeline + shader are given any additional information like transform [*]
4. Render given the information

[*4] This could mean that an entity that can only be rendered if it has a "render" component and a "transform" component.

**Shader (Asset)**
  - Module
  - Entry Points
  - Default pipeline state
  - Pipeline Cache
    - _This can be in a higher state that contains the shaders_
    - Pipeline
        - Variant State
        - Format

**Material (Asset)**
  - Reference to shader
  - Reference to textures
  - Uniform Values
  - BindGroup
    - External data that is provided during render. Can be provided from other components but is required and defined here

**Mesh (Asset)**
  - Vertex Buffer
  - Index Buffer
  - Vertex Layout

**Render (Component)**
  - Mesh
  - Material
  - Transform <- input transform component

## Passes

1. Depth:
  - Shadow Pass: Shadow map per light source determining what depth can the light reach
2. Opaque:
  - Deferred Render (Defer lighting calc): Opaque mesh + material data
    - Depth test replacing pixels
  - Lighting: Blend lighting to deferred mesh + material data
3. Transparent:
  - Forward Rendered (Immediate lighting calc): Transparent objects blended together and blended onto deferred buffer
    - Depth test with opaque layer blended with transparent layer
4. UI

## Texture + View + Sampler

- A `texture` is the GPU memory of the loaded texture data
- A `view` is a window into that texture
    - Mip level
    - Array layer
    - Cube face
    - Atlas textures (subset of the texture like a cube map)
    - Color vs Depth
    - Compatible format reinterpretation
- A `sampler` specifies how the gpu should sample the view/texture
    - nearest or linear filtering
    - repeat or clamp
    - mipmap
    - anisotropic filtering
    - depth comparison

The gpu resource is the Texture, then the views are created as you need to access parts of the texture, then samplers are cached based on how the views are rendered.

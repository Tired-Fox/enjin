# Enjin

Zig based game enjin. This is a educational/research project created by `Tired-Fox`. This means that first priority is learning the layers, cross-platform support, rendering, along with all the other systems that go into a game engine.

In the effort to get a working game/project from a custom engine, existing libraries will be used where possible. This includes c/c++ libraries or c abi compatible projects. If a library/project does not exists that fits/fills a need/function then a new one will be created and shared for other users.

## Goal

**WIP: Goals may be added, deferred, or cancelled depending on research and exploration**

- [ ] Render a basic 2D shape
- [ ] Render a basic 2D shape with a uv texture
- [ ] Render a basic 2D shape with a uv texture and height map
- [ ] Render a basic 2D shape with a uv texture and height map and moving light
- [ ] Render a basic 3D shape with a static camera
- [ ] Render a basic 3D shape with a uv texture with a static camera
- [ ] Render a basic 3D shape with a uv texture and height map with a static camera
- [ ] Render a basic 3D shape with a uv texture and height map with a dynamic camera
- [ ] Render a basic skybox
- [ ] Render baked lighting
- [ ] Render dynamic lighting
- [ ] Render a basic scene with individual complex objects that react to baked and dynamic lighting and a dynamic camera

- [ ] Camera culling
- [ ] Z culling

## TODO

- [ ] Core (Cross-Platform): Platform Abstraction Layer (PAL)
    - [ ] Windowing
    - [ ] File I/O
    - [ ] Input
    - [ ] Image
- [ ] Engine
    - [ ] Renderer
    - [ ] Physics
    - [ ] Audio Mixer
    - [ ] Networking
    - [ ] Serialization
    - [ ] Entity Component System (ECS)
    - [ ] Scene Graph
    - [ ] UI
    - [ ] Editor

- [ ] Rendering
    - [ ] Objects (Mesh)
    - [ ] Lighting
    - [ ] 2D
    - [ ] 3D
    - [ ] Shaders
    - [ ] Position + Rotation + Scale
    - [ ] Camera(s)
- [ ] Events
    - [ ] Input
        - [ ] Keyboard + Mouse
        - [ ] Gamepad
    - [ ] Update
        - [ ] Delta Time

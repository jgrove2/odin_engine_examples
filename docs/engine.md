# Engine

The engine module (`engine/engine/engine.odin`) is a thin wrapper around [raylib](https://www.raylib.com/) that handles window creation, audio initialization, and the main loop lifecycle. It intentionally does very little — the goal is to isolate raylib-specific setup so game code can focus on ECS logic.

## Engine Struct

```odin
Engine :: struct {
    title:         cstring,
    screen_width:  i32,
    screen_height: i32,
    target_fps:    i32,
}
```

This struct captures the window/audio configuration. After `engine_create` is called, a module-level copy is stored internally so any code can retrieve it via `engine_get()` — no need to store the return value or query the ECS world.

## API

| Proc | Purpose |
|---|---|
| `engine_create(title, width, height, fps)` | Create the window, init audio, set target FPS. Stores the config internally for `engine_get`. |
| `engine_get()` | Return a `^Engine` pointer to the stored config. Use this anywhere you need screen dimensions or other engine settings. |
| `engine_shutdown()` | Close the audio device and window. Call via `defer` after `engine_create`. |
| `engine_should_close()` | Returns `true` when the user closes the window (wraps `rl.WindowShouldClose`). |

## Usage

```odin
main :: proc() {
    eng.engine_create("My Game", 800, 600, 60)
    defer eng.engine_shutdown()

    // ... ECS setup ...

    for !eng.engine_should_close() {
        dt := rl.GetFrameTime()

        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        ecs.system_runner_update(&runner, &world, dt)

        rl.EndDrawing()
    }
}
```

### Accessing Engine Config from Systems

Any system or proc that needs screen dimensions calls `engine_get()` instead of relying on file-scoped constants:

```odin
render_pause_overlay :: proc(w: ^ecs.World, dt: f32) {
    e := eng.engine_get()
    sw := e.screen_width
    sh := e.screen_height

    rl.DrawRectangle(0, 0, sw, sh, {0, 0, 0, 160})
    // ...
}
```

This keeps the ECS layer free of engine concerns — the `System_Proc` signature stays `proc(w: ^World, dt: f32)` and systems import the engine module directly when they need config values.

### The Main Loop Pattern

The main loop follows raylib's `BeginDrawing` / `EndDrawing` sandwich:

1. **Get frame delta** — `rl.GetFrameTime()` returns seconds since the last frame.
2. **Handle input** — Read key presses, update game state (currently done in `main`, planned to move into a `Pre_Update` input system).
3. **Begin drawing** — `rl.BeginDrawing()` starts the frame buffer.
4. **Clear** — `rl.ClearBackground(rl.BLACK)` fills the screen.
5. **Run systems** — `system_runner_update` executes all active systems in phase order. Render-phase systems issue draw calls during this step.
6. **End drawing** — `rl.EndDrawing()` flushes the frame buffer to the screen.

## Components Library

The engine also provides a set of reusable component definitions in `engine/components/`. These are not yet wired into built-in systems but exist as a starting point for future games:

| File | Components | Purpose |
|---|---|---|
| `transform.odin` | `Position`, `Velocity` | Basic 2D position and velocity vectors |
| `sprite.odin` | `Sprite` | Texture rendering with source rect, tint, scale, rotation |
| `camera.odin` | `Camera` | 2D camera with offset, target, zoom, rotation |
| `shapes/rect.odin` | `Rect_Renderer` | Colored rectangle for prototyping before sprites are ready |

These will become part of a built-in render pipeline (see [Roadmap](roadmap.md)) where the engine automatically renders entities with `Position + Sprite` or `Position + Rect_Renderer` without game code needing to write custom render systems.

## Further Reading

- [Overview](overview.md) — Repository structure and how imports work
- [Systems](systems.md) — How the System_Runner drives the main loop
- [Roadmap](roadmap.md) — Planned engine features and improvements

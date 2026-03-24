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

This struct captures the initial configuration. Currently, the returned value is not stored after creation — raylib maintains window state globally. See the [Roadmap](roadmap.md) for plans to make this a proper singleton accessible from systems.

## API

| Proc | Purpose |
|---|---|
| `engine_create(title, width, height, fps)` | Create the window, init audio, set target FPS. Returns an `Engine` value. |
| `engine_shutdown()` | Close the audio device and window. Call via `defer` after `engine_create`. |
| `engine_should_close()` | Returns `true` when the user closes the window (wraps `rl.WindowShouldClose`). |

## Usage

```odin
main :: proc() {
    _ = eng.engine_create("My Game", 800, 600, 60)
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

### The Main Loop Pattern

The main loop follows raylib's `BeginDrawing` / `EndDrawing` sandwich:

1. **Get frame delta** — `rl.GetFrameTime()` returns seconds since the last frame.
2. **Handle input** — Read key presses, update game state (currently done in `main`, planned to move into a `Pre_Update` input system).
3. **Begin drawing** — `rl.BeginDrawing()` starts the frame buffer.
4. **Clear** — `rl.ClearBackground(rl.BLACK)` fills the screen.
5. **Run systems** — `system_runner_update` executes all active systems in phase order. Render-phase systems issue draw calls during this step.
6. **End drawing** — `rl.EndDrawing()` flushes the frame buffer to the screen.

### Why `engine_create` Returns a Value That Gets Discarded

The `Engine` struct was designed to eventually hold live state (screen dimensions, FPS, etc.) accessible to systems. Right now, game code defines its own constants (`SCREEN_W`, `SCREEN_H`) and raylib maintains the actual window state globally. The plan is to store the `Engine` as a singleton component in the World so any system can query screen dimensions without depending on file-scoped constants.

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
- [Roadmap](roadmap.md) — Plans for the Engine singleton and built-in render pipeline

# Systems

Systems are where behavior lives. A system is a plain proc that receives the World and a delta-time value, queries for the components it cares about, and acts on them. The engine provides a `System_Runner` that organizes systems into ordered phases and executes them each frame.

## System Signature

Every system is a proc with this signature:

```odin
System_Proc :: #type proc(w: ^World, dt: f32)
```

A system receives the entire World (so it can query any component type) and the frame's delta time. Systems should not store state outside the World — all persistent state belongs in components on entities.

## System_Runner

The `System_Runner` holds a dynamic array of registered systems and executes them in phase order each frame (defined in `engine/ecs/systems.odin`):

```odin
System_Runner :: struct {
    systems: [dynamic]System,
}

System :: struct {
    name:    string,       // Human-readable name (for debugging/logging)
    process: System_Proc,  // The proc to call
    phase:   System_Phase, // When in the frame to call it
    active:  bool,         // Can be toggled at runtime
}
```

**Key procs:**

| Proc | Purpose |
|---|---|
| `system_runner_create()` | Allocate a new runner with an empty system list |
| `system_runner_destroy(&sr)` | Free the system list |
| `system_register(&sr, name, proc, phase)` | Register a system in a given phase |
| `system_set_active(&sr, name, active)` | Enable/disable a system by name at runtime |
| `system_runner_update(&sr, &w, dt)` | Execute all active systems in phase order |

## Phases

Systems are assigned to one of five phases. Each frame, `system_runner_update` iterates all phases in enum order, and within each phase executes systems in the order they were registered:

```
Pre_Update   →   Update   →   Post_Update   →   Render   →   Debug
```

| Phase | Intent | Example |
|---|---|---|
| `Pre_Update` | Input buffering, state transitions | Read keyboard input, detect game-over conditions |
| `Update` | Core game logic, simulation | Move the snake, check collisions, eat food |
| `Post_Update` | Post-simulation cleanup | Deferred entity destruction, collision resolution (unused currently) |
| `Render` | All draw calls | Draw grid, snake, food, HUD, overlays |
| `Debug` | Debug overlays and diagnostics | Entity count display, system timing (unused currently) |

Phase ordering is deterministic: if system A is registered before system B in the same phase, A always runs first. This makes it easy to reason about dependencies (e.g. input must be read before movement is computed).

## The `*_runner_init` Pattern

Rather than registering every system inline in `main`, each game module owns a `*_runner_init` proc that registers its own systems with the runner. This keeps registration co-located with the systems it registers:

```odin
// In snake.odin — knows about snake systems
snake_runner_init :: proc(runner: ^ecs.System_Runner) {
    ecs.system_register(runner, "snake_input",  snake_input,  .Pre_Update)
    ecs.system_register(runner, "snake_update", snake_update, .Update)
    ecs.system_register(runner, "render_snake", render_snake, .Render)
}
```

Then `main` just calls each init:

```odin
grid_runner_init(&runner)
game_state_runner_init(&runner)
snake_runner_init(&runner)
food_runner_init(&runner)
```

**Why this matters:** As the number of systems grows, a flat list of `system_register` calls in `main` becomes unmanageable. The `*_runner_init` pattern pushes registration responsibility to the module that owns the systems. Adding a new subsystem means creating a new file with its own `*_runner_init` and adding one line to `main`.

**Important:** The `runner` parameter is already a pointer (`^ecs.System_Runner`). Pass it directly to `system_register` — do not take its address with `&`. The address-of operator on a pointer parameter creates a double-pointer (`^^System_Runner`) which is the wrong type.

## System Registration Order and Render Layering

Within the `Render` phase, systems draw in registration order. This means the order of `*_runner_init` calls in `main` determines the visual layering:

```
grid_runner_init(&runner)         // 1. Background grid (drawn first, behind everything)
game_state_runner_init(&runner)   // 2. HUD text, pause/game-over overlays
snake_runner_init(&runner)        // 3. Snake body
food_runner_init(&runner)         // 4. Food (drawn last, on top)
```

If you need to change what draws on top of what, change the order of these calls.

## Toggling Systems at Runtime

Any system can be enabled or disabled by name:

```odin
ecs.system_set_active(&runner, "render_snake", false)  // stop drawing the snake
ecs.system_set_active(&runner, "render_snake", true)   // re-enable it
```

This is useful for debug toggles, conditional rendering, or disabling subsystems during certain game phases.

## Further Reading

- [ECS Architecture](ecs.md) — How entities, components, and the World work
- [Snake Game Walkthrough](snake_game.md) — Concrete example of systems in action
- [Roadmap](roadmap.md) — Planned system architecture improvements

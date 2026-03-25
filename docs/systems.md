# Systems

Systems are where behavior lives. A system is a plain proc that receives the World, the Event Bus, and a delta-time value, queries for the components it cares about, and acts on them. The engine provides a `System_Runner` that organizes systems into ordered phases and executes them each frame.

## System Signature

Every system is a proc with this signature:

```odin
System_Proc :: #type proc(w: ^World, bus: ^Event_Bus, dt: f32)
```

A system receives the entire World (so it can query any component type), the Event Bus (for posting and draining events), and the frame's delta time. Systems should not store state outside the World — all persistent state belongs in components on entities.

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
| `system_runner_update(&sr, &w, bus, dt)` | Execute all active systems in phase order |

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

## Compositor

The `Compositor` sits above individual `World + System_Runner` pairs and drives them all from a single update call (defined in `engine/ecs/compositor.odin`).

### Why It Exists

Without the compositor, `main` manually creates a `World`, a `System_Runner`, and calls `system_runner_update` directly. This works for a single world but becomes unwieldy when multiple independent worlds are needed (e.g. gameplay, UI, debug overlay). The compositor owns all world entries and updates them in order each frame.

### Structs

```odin
World_Entry :: struct {
    world:  World,
    runner: System_Runner,
    active: bool,
}

Compositor :: struct {
    worlds: [dynamic]^World_Entry,  // heap-allocated, pointer-stable
}
```

Each `World_Entry` is heap-allocated, so the `^World_Entry` pointer returned by `compositor_create_world` remains valid for the lifetime of the compositor regardless of how many worlds are added.

### Key Procs

| Proc | Purpose |
|---|---|
| `compositor_create()` | Allocate a new compositor with an empty worlds list |
| `compositor_destroy(&c)` | Destroy all world entries, free heap allocations, delete list |
| `compositor_create_world(&c)` | Heap-allocate a new `World_Entry`, return a stable `^World_Entry` pointer |
| `compositor_update(&c, dt)` | Call `system_runner_update` on every active entry |
| `compositor_set_active(entry, active)` | Toggle a world entry on or off |

### Usage

```odin
compositor := ecs.compositor_create()
defer ecs.compositor_destroy(&compositor)

gameplay := ecs.compositor_create_world(&compositor)

// Populate the world
ecs.world_spawn_with(&gameplay.world, Food{col = 5, row = 10})

// Register systems into the world's runner
snake_runner_init(&gameplay.runner)
food_runner_init(&gameplay.runner)

// In the main loop — one call drives all worlds
ecs.compositor_update(&compositor, dt)
```

The `*_runner_init` procs still take `^ecs.System_Runner` — the caller just passes `&gameplay.runner` instead of a standalone runner.

## Event Bus

The `Event_Bus` is a per-frame typed event system that decouples systems from each other. Instead of calling into another module directly (e.g. snake calling `food_relocate`), a system posts an event and another system drains it — neither needs to know about the other.

### Ownership

The `Compositor` owns the single `Event_Bus`. Each `World_Entry` holds a `bus: ^Event_Bus` back-pointer so the bus is automatically threaded through `system_runner_update` to every system proc.

### Structs

```odin
Event_Queue :: struct {
    data:       [dynamic]u8,   // Dense byte buffer of events
    event_size: int,
    count:      int,
}

Event_Bus :: struct {
    queues: map[typeid]Event_Queue,  // One queue per event type
}
```

Events are stored as raw bytes in a `[dynamic]u8` buffer — no per-event heap allocation. Each event type (identified by `typeid`) gets its own `Event_Queue`.

### Key Procs

| Proc | Purpose |
|---|---|
| `event_bus_create()` | Allocate a new empty bus |
| `event_bus_destroy(&bus)` | Free all queue buffers and the queue map |
| `event_post(&bus, event)` | Post one event of type `T`. Queue auto-created on first use |
| `event_drain(&bus, T) -> []T` | Return all events of type `T` as a typed slice, then clear the queue |
| `event_peek(&bus, T) -> []T` | Return all events of type `T` as a typed slice without consuming them |
| `event_bus_flush(&bus)` | Clear all queues. Called by compositor at end of frame |

### Lifecycle

1. **Update phase** — A system detects something and posts an event: `ecs.event_post(bus, Food_Eaten{col = 3, row = 5})`
2. **Post_Update phase** — A consuming system drains the events: `for &ev in ecs.event_drain(bus, Food_Eaten) { ... }`
3. **End of frame** — The compositor calls `event_bus_flush` after all worlds have updated, clearing every queue

Events live for exactly one frame. `event_drain` returns a typed slice and clears the queue after building the slice. `event_peek` returns the same kind of slice but leaves the queue intact for multiple readers.

The returned slice points directly into the queue's byte buffer. It is valid for the duration of the current system call but should not be stored past the current frame.

### Example: Decoupling Snake from Food

Before the event bus, `snake_update` called `food_relocate` directly — the snake module had to know about the food module's internals. With the event bus:

```odin
// In snake.odin — define the event
Food_Eaten :: struct { col, row: int }

// In snake_update — post instead of calling food_relocate
if food_ctx.found {
    c.gs.score += 1
    ecs.event_post(c.bus, Food_Eaten{col = new_col, row = new_row})
}

// In food.odin — new Post_Update system drains the event
food_update :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
    area := get_playable_area(w)
    if area == nil { return }
    for _ in ecs.event_drain(bus, Food_Eaten) {
        food_relocate(w, area)
    }
}
```

The snake module no longer imports or calls anything from the food module. The food module subscribes to `Food_Eaten` events and handles relocation on its own.

### Design Decisions

- **Per-frame only** — No event persistence across frames. This keeps the system simple and avoids stale-event bugs.
- **Drain vs peek** — `event_drain` is for single-consumer patterns (one system handles the event). `event_peek` is for broadcast patterns (multiple systems read the same event).
- **Lazy queue creation** — Queues are auto-created on first `event_post`, matching the lazy auto-registration pattern used elsewhere in the engine.
- **No per-event heap allocation** — Events are memcopied into a contiguous byte buffer, keeping cache locality and avoiding allocator pressure.

## Further Reading

- [ECS Architecture](ecs.md) — How entities, components, and the World work
- [Snake Game Walkthrough](snake_game.md) — Concrete example of systems in action
- [Roadmap](roadmap.md) — Planned system architecture improvements

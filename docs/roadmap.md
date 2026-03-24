# Roadmap

This document outlines planned improvements to the engine, organized into three phases. Each phase builds on the previous one. Items are ordered roughly by dependency — earlier items tend to unblock later ones.

---

## Phase 1 — Foundation Improvements

These changes improve the developer experience and remove friction from the current architecture. They are small in scope and low risk.

### Lazy Auto-Registration

**Pattern:** Auto-registration / lazy initialization

Currently, every component type must be registered with `world_register_component` before it can be used. Forgetting this causes a runtime assert. The fix is straightforward: `world_add_component` and `world_spawn_with` check whether the type is already registered and create the sparse set on first use if not.

This eliminates the manual registration block in `main` and means adding a new component type requires zero ceremony — just define the struct and spawn with it.

**References:** Bevy (Rust) auto-registers components on first insert. EnTT (C++) uses a similar lazy approach with its `registry.emplace`.

### Engine Singleton Component

**Pattern:** Singleton component

The `Engine` struct returned by `engine_create` is currently discarded. Screen dimensions are accessed via file-scoped constants (`SCREEN_W`, `SCREEN_H`), creating implicit coupling between files.

The plan is to store the `Engine` as a singleton component in the World (or make it accessible from the compositor). Any system that needs screen dimensions queries for it like any other component, eliminating the constants.

### Input Abstraction System

**Pattern:** Input action mapping

Currently, `rl.IsKeyPressed` calls are scattered across `main.odin` and `snake_input`. The plan is to create an `Input` singleton component updated by a dedicated `Pre_Update` system. This system reads raw raylib input once per frame and populates the `Input` struct with action states (e.g. `move_up`, `pause`, `restart`). Game systems read the `Input` component instead of calling raylib directly.

This decouples game logic from the input backend and makes it possible to remap keys, support gamepads, or replay input for testing — all without changing game systems.

**References:** Unity's Input System package, Godot's `InputMap`, "input abstraction layer game dev".

### World Compositor and Module-Scoped Worlds

**Pattern:** World compositor, SubApp (Bevy), isolated worlds (Unity DOTS)

The compositor is a layer above the ECS that manages multiple `World + System_Runner` pairs. Each major subsystem (gameplay, UI, debug overlay) owns its own world and is responsible for its own component registration and entity spawning. The compositor updates each world in order each frame and routes events between them.

This solves the registration pain point: instead of registering everything in `main`, each module exposes a `*_world_create()` proc that sets up its own world internally. `main` becomes:

```odin
compositor_add(&c, gameplay_world_create())
compositor_add(&c, ui_world_create())
```

Related systems that need to query each other (e.g. snake + food) stay in the same world. Only truly independent layers are split into separate worlds.

**References:** Bevy `SubApp`, Flecs worlds, Unity DOTS `World` class.

---

## Phase 2 — Engine Systems

These are core engine features that enable a wider range of games. They depend on the Phase 1 foundation being in place.

### Event Bus / Pub-Sub

**Pattern:** Event bus, observer pattern, pub-sub

A typed event queue owned by the compositor. Systems post events (`event_post(queue, Food_Eaten{col=3, row=5})`), and other systems drain them (`event_drain(queue, Food_Eaten, handler)`). Events are consumed within the same frame — no persistence.

The event bus enables cross-world communication (compositor routes events between worlds) and decouples systems within a world (snake posts `Food_Eaten`, food system subscribes and relocates — no direct function call between them).

Events use `typeid` as the discriminator, with inline byte storage to avoid per-event heap allocation.

**References:** "event bus pattern", "observer pattern game dev", Bevy `Events<T>`, Flecs observers.

### Scene Manager

**Pattern:** Scene stack, pushdown automaton, game state machine

A scene manager sits on top of the compositor and manages transitions between game states (main menu, gameplay, game over). Each scene is a set of worlds that the compositor activates or deactivates. Scene transitions can push (pause current, start new), pop (return to previous), or swap (replace current).

This replaces the current approach of encoding game state in a `Game_Phase` enum and conditionally skipping systems. Each phase becomes its own scene with its own world, making each one independently testable.

**References:** *Game Programming Patterns* — "State" chapter (gameprogrammingpatterns.com), "pushdown automaton game states", "scene manager pattern game dev".

### Built-In Render Pipeline

**Pattern:** Render system, sprite renderer

Engine-provided `Render` phase systems that automatically draw entities with known component combinations:

- `Position + Sprite` — textured quad rendering
- `Position + Rect_Renderer` — colored rectangle (prototyping)
- `Camera` — viewport transformation

Game code attaches these components to entities and gets rendering for free, without writing custom render systems. Custom render systems can still be added alongside the built-in ones for specialized effects.

The existing `engine/components/` structs (`Position`, `Velocity`, `Sprite`, `Camera`, `Rect_Renderer`) become the interface to this pipeline.

### Deferred Entity Commands

**Pattern:** Command buffer, deferred commands

Currently, entity spawn/kill during iteration is unsafe (modifying the world while iterating its sparse sets). The `kill_all` helper works around this by collecting entity IDs first, then killing after the query. A proper command buffer would let systems issue spawn/kill/add/remove commands during iteration, which are applied at a safe point (end of the current phase or during `Post_Update`).

```odin
// Inside a query callback:
ecs.commands_kill(cmd, entity)          // queued, not immediate
ecs.commands_spawn_with(cmd, Food{...}) // queued, not immediate

// After the phase:
ecs.commands_flush(cmd, &world)         // applied here
```

**References:** Bevy `Commands`, EnTT `registry.destroy` during iteration semantics, "ECS command buffer".

### Post_Update Collision Resolution

**Pattern:** Collision detection/resolution stage

The `Post_Update` phase is currently unused. It is the natural place for a collision detection and resolution stage that runs after all `Update` systems have moved entities. A collision system would:

1. Build a spatial index (grid-based for tile games, quadtree for continuous-space games).
2. Detect overlapping entity pairs.
3. Post collision events for game-specific handling.

This separates "detect" from "respond" — the engine detects collisions generically, game code subscribes to collision events and decides what happens (damage, bounce, pickup, etc.).

### Debug Phase Overlay

**Pattern:** Debug overlay, diagnostic HUD

A `Debug` phase system (currently unused) that renders diagnostics:

- Active entity count
- Component type counts
- Per-system execution time
- FPS graph
- Toggleable via a hotkey (e.g. F1)

This is cheap to build once the system infrastructure is in place and provides immediate value for performance tuning and debugging.

---

## Phase 3 — Content and Tools

These features are about building real game content efficiently. They depend on the event bus and render pipeline from Phase 2.

### LDtk / Tiled Level Loading

**Pattern:** Command pattern, deferred entity spawn, pub-sub level loading

Integration with [LDtk](https://ldtk.io/) or [Tiled](https://www.mapeditor.org/) level editors. A level loader reads the exported JSON, and for each tile/entity in the level data, posts an `Entity_Spawn` command or event. The ECS world subscribes and materializes them into entities with the appropriate components (`Position`, `Sprite`, collision tags, etc.).

The pub-sub approach means the level loader doesn't need to know about game-specific component types. It posts generic spawn events with key-value metadata; game-specific systems subscribe and interpret the metadata into concrete components.

This enables:
- Level design in a visual editor instead of code
- Hot-reloading levels during development
- Multiple levels loaded/unloaded via the scene manager

**References:** LDtk QuickType schema, Tiled TMX/JSON format, "ECS level loading", "command pattern entity spawn".

### Custom Save System

**Pattern:** ECS serialization, world snapshot

A save system that can serialize and deserialize the state of a World (or a subset of it). This involves:

1. **Component serialization** — Each registered component type needs a serialize/deserialize proc pair. Odin's reflection capabilities (`type_info_of`) can help automate this for simple structs.
2. **World snapshot** — Iterate all entities and their components, serialize them into a binary or JSON format.
3. **World restore** — Deserialize the snapshot, spawn entities, and attach components.

The save system hooks into the event bus: a `Save_Requested` event triggers serialization, a `Load_Requested` event triggers deserialization and world reconstruction.

Scoping is important — not everything should be saved (e.g. transient particle effects). A `Saveable` tag component marks entities that should be included in snapshots.

**References:** Bevy Scenes (ron format), Flecs REST API (JSON world snapshots), "ECS serialization", "component reflection Odin".

### Lighting System

**Pattern:** 2D deferred lighting, normal-mapped sprites, shadow casting

A 2D lighting system that adds atmosphere and visual depth. Approaches range from simple to complex:

1. **Ambient + point lights** — Render the scene to a texture, then blend a light map on top. Point lights are circles with falloff.
2. **Shadow casting** — Cast rays from light sources against occluder geometry (tile edges). Render lit/shadow regions. This uses raylib's shader support.
3. **Normal-mapped sprites** — Sprites include a normal map texture. The lighting system uses the normal map to compute per-pixel lighting direction, giving flat sprites a 3D appearance.

The lighting system would operate as a `Post_Update` or late `Render` phase system. Light sources are components (`Point_Light`, `Directional_Light`) attached to entities. The system queries for lights and shadow casters, builds the light map, and applies it.

**References:** "2D deferred lighting", "raylib shaders", "normal mapping sprites 2D", "shadow casting 2D raycasting".

### Animation System

**Pattern:** Sprite animation, state machine animator

An `Animator` component that drives spritesheet frame sequencing:

```odin
Animator :: struct {
    animations:    map[string]Animation,   // Named animation clips
    current:       string,                 // Active clip name
    frame_index:   int,
    frame_timer:   f32,
}

Animation :: struct {
    frames:    []rl.Rectangle,   // Source rects into the spritesheet
    fps:       f32,
    looping:   bool,
}
```

An `Update` phase system advances `frame_timer`, updates `frame_index`, and writes the current frame's source rect into the entity's `Sprite` component. Transitions between animations are triggered by game events or direct calls (`animator_play(e, "walk_right")`).

**References:** "sprite animation system ECS", "animation state machine game dev".

### Audio System

**Pattern:** Sound event bus, audio manager

Decouple audio playback from game logic via the event bus. Game systems post sound events (`play_sound(Sound_Event{id = .Eat_Food})`) and an audio system in the `Post_Update` phase handles playback using raylib's audio API.

This avoids scattering `rl.PlaySound` calls across game code and enables:
- Volume control and mixing
- Spatial audio (position-based panning)
- Sound pooling (limit simultaneous instances of the same sound)
- Music transitions between scenes

### Variadic Query

**Pattern:** Generic query, compile-time variadic

Replace the manually-written `world_query1`, `world_query2`, `world_query3` procs with a single generic query mechanism. This is a language-level challenge in Odin since variadic compile-time polymorphism has limits, but approaches include:

- A query builder that accumulates type IDs and returns an iterator
- Using Odin's `#type` and `any` to build a type-erased but safe query API

The goal is to support queries of arbitrary arity without writing a new proc for each count.

**References:** EnTT `view<A, B, C, ...>`, Flecs `ecs_query`, "variadic template ECS query".

---

## Reference Material

| Resource | Covers |
|---|---|
| [Game Programming Patterns](https://gameprogrammingpatterns.com/) — Bob Nystrom | State, Observer, Command, Game Loop (free online) |
| [EnTT](https://github.com/skypjack/entt) | Sparse set ECS reference, C++ |
| [Flecs](https://github.com/SanderMertens/flecs) | Multi-world, pipelines, phases, observers, C |
| [Bevy Engine](https://bevyengine.org/) | Modern ECS, SubApp, Commands, Events, Rust |
| [LDtk](https://ldtk.io/) | Level editor with ECS-friendly JSON export |
| [Catherine West — RustConf 2018](https://www.youtube.com/watch?v=aKLntZcp27M) | Generational arenas, ECS motivation |

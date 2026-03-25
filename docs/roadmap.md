# Roadmap

This document outlines planned improvements to the engine, organized into three phases. Each phase builds on the previous one. Items are ordered roughly by dependency — earlier items tend to unblock later ones.

---

## Phase 1 — Foundation Improvements

These changes improve the developer experience and remove friction from the current architecture. They are small in scope and low risk.

### ~~Lazy Auto-Registration~~ ✓ Completed

**Pattern:** Auto-registration / lazy initialization

`world_add_component` and `world_spawn_with` auto-register component types on first use. If the type's sparse set does not exist yet, it is created transparently. `world_register_component` remains available as an optional, idempotent explicit registration for cases where you want to guarantee the set exists before spawning.

### ~~Engine Singleton Component~~ ✓ Completed

**Pattern:** Module-level accessor

Rather than storing the `Engine` as a component in the ECS World (which would couple the ECS layer to engine concerns and complicate future multi-world scenarios), `engine_create` now stashes a copy of the `Engine` struct in a file-scoped variable. The new `engine_get()` proc returns a `^Engine` pointer that any system or game code can use to read screen dimensions and other config — no ECS query, no ownership inversion, no constant duplication.

### Input Abstraction System

**Pattern:** Input action mapping

Currently, `rl.IsKeyPressed` calls are scattered across `main.odin` and `snake_input`. The plan is to create an `Input` singleton component updated by a dedicated `Pre_Update` system. This system reads raw raylib input once per frame and populates the `Input` struct with action states (e.g. `move_up`, `pause`, `restart`). Game systems read the `Input` component instead of calling raylib directly.

This decouples game logic from the input backend and makes it possible to remap keys, support gamepads, or replay input for testing — all without changing game systems.

**References:** Unity's Input System package, Godot's `InputMap`, "input abstraction layer game dev".

### ~~World Compositor and Module-Scoped Worlds~~ ✓ Completed

**Pattern:** World compositor, SubApp (Bevy), isolated worlds (Unity DOTS)

The `Compositor` struct owns a list of heap-allocated `World_Entry` pointers (each bundling a `World + System_Runner + active` flag). `compositor_create_world` allocates a new entry and returns a stable `^World_Entry` pointer that the caller uses to populate the world and register systems. `compositor_update` drives all active entries each frame.

The snake game currently uses a single world entry. Multi-world splitting (gameplay, UI, debug) is deferred until after the Event Bus is implemented.

---

## Phase 2 — Engine Systems

These are core engine features that enable a wider range of games. They depend on the Phase 1 foundation being in place.

### ~~Event Bus / Pub-Sub~~ ✓ Completed

**Pattern:** Event bus, observer pattern, pub-sub

The `Event_Bus` is a typed, per-frame event queue owned by the `Compositor`. Systems post events with `event_post(bus, Food_Eaten{col=3, row=5})` and other systems consume them with `event_drain(bus, Food_Eaten, ctx, handler)` or peek without consuming via `event_peek`. Events use `typeid` as the discriminator with inline byte storage (no per-event heap allocation). The compositor flushes all queues at the end of each frame.

The `System_Proc` signature was updated from `proc(w: ^World, dt: f32)` to `proc(w: ^World, bus: ^Event_Bus, dt: f32)` so every system has access to the bus. The snake game's direct `food_relocate` call was replaced with a `Food_Eaten` event — `snake_update` (Update phase) posts the event and `food_update` (Post_Update phase) drains it, fully decoupling the snake and food modules.

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

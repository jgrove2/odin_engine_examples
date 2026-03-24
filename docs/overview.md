# Overview

## What This Is

A custom 2D game engine written in [Odin](https://odin-lang.org/) using [raylib](https://www.raylib.com/) as the graphics/audio backend. The engine provides an Entity Component System (ECS) core, a thin raylib wrapper, and a set of reusable component definitions. Games are built as standalone examples that import the engine as a library.

## Repository Structure

```
engine/                      # Reusable engine library
  ecs/                       # Entity Component System core
    entity.odin              #   Generational entity IDs + entity manager
    sparse_set.odin          #   Dense packed component storage
    world.odin               #   World: entity + component registry
    query.odin               #   Zero-allocation typed query helpers
    systems.odin             #   System_Runner, phases, registration
  engine/                    # Thin raylib wrapper
    engine.odin              #   Window/audio init, shutdown, main loop
  components/                # Reusable component definitions
    transform.odin           #   Position, Velocity
    sprite.odin              #   Sprite (texture, source rect, tint, etc.)
    camera.odin              #   Camera (offset, target, zoom, rotation)
    shapes/
      rect.odin              #   Rect_Renderer, create_rect helper

examples/                    # Standalone games and demos
  snake_game/                #   Full snake game using the ECS
  basic/                     #   Minimal window example
  hello/                     #   Console "Hello, World!" (no engine)

docs/                        # Documentation (you are here)
run.sh                       # Interactive script to build and run any example
ols.json                     # Odin Language Server configuration
```

## How Imports Work

The engine is exposed to examples via Odin's **collection** system. The `run.sh` script passes `-collection:engine=engine` to the compiler, which means:

- `import "engine:ecs"` resolves to `engine/ecs/`
- `import eng "engine:engine"` resolves to `engine/engine/`
- `import "engine:components"` resolves to `engine/components/`

The OLS language server config in `ols.json` mirrors this with its `collections` field so editor tooling understands the same paths.

## Running Examples

```bash
# Interactive menu — lists all examples and lets you pick one
./run.sh

# Or run directly with odin
odin run examples/snake_game -collection:engine=engine
```

## Design Principles

1. **Data-oriented** — Components are plain structs with no methods or inheritance. Behavior lives in systems (free procs), not in the data.

2. **Zero-allocation queries** — The typed query helpers (`world_query1`, `world_query2`, `world_query3`) iterate components in-place with no per-frame heap allocation. A `rawptr` context parameter is passed through to callbacks as a substitute for closures.

3. **Explicit phase ordering** — Systems are assigned to phases (`Pre_Update`, `Update`, `Post_Update`, `Render`, `Debug`). Within each phase, systems execute in registration order. This makes frame ordering deterministic and easy to reason about.

4. **Module-scoped registration** — Each game module (e.g. `snake.odin`, `food.odin`) owns a `*_runner_init` proc that registers its systems with the runner. The main file calls these init procs rather than listing every system registration inline.

## Further Reading

- [ECS Architecture](ecs.md) — Entities, Components, Sparse Sets, World, Queries
- [Systems](systems.md) — System_Runner, phases, the runner_init pattern
- [Engine](engine.md) — The raylib wrapper and main loop pattern
- [Snake Game Walkthrough](snake_game.md) — How the snake game uses the engine
- [Roadmap](roadmap.md) — Planned improvements and future systems

# Snake Game Walkthrough

This page walks through the snake game (`examples/snake_game/`) as a concrete example of how to build a game on the engine. It covers component design, system organization, singleton patterns, and the frame lifecycle.

## File Layout

```
examples/snake_game/
  main.odin             Entry point, ECS setup, main loop, restart logic
  playable_area.odin    Grid component + grid render system
  game_state.odin       Game phase tracking, HUD, pause/game-over overlays
  snake.odin            Snake component, input, movement, collision, rendering
  food.odin             Food component, spawn/relocate, rendering
```

Each file owns one logical subsystem: its component definition, its systems, and its `*_runner_init` proc. `main.odin` orchestrates setup and the game loop but contains no rendering or game logic systems.

## Components

The game defines four component types, each as a plain struct:

### Playable_Area (singleton)

```odin
Playable_Area :: struct {
    origin_x, origin_y: f32,   // Top-left pixel position of the grid
    rows, cols:         int,    // Grid dimensions in cells
    tile_size:          f32,    // Pixel size of each cell
}
```

Represents the centered game grid. Only one entity has this component. Created by `playable_area_init()` which computes the pixel origin to center the grid on screen.

### Game_State (singleton)

```odin
Game_State :: struct {
    score:      int,
    high_score: int,
    phase:      Game_Phase,   // Playing | Paused | Game_Over
}
```

Tracks score and the current game phase. Systems check `phase` to decide whether to process input, advance the snake, or show overlays.

### Snake

```odin
Snake :: struct {
    segments:         [dynamic]Snake_Segment,  // Head is segments[0]
    direction:        Direction,                // Current movement direction
    next_direction:   Direction,                // Buffered input (applied next tick)
    move_timer:       f32,                      // Accumulates dt between ticks
    move_interval:    f32,                      // Seconds per cell (speed)
    pending_tail:     Snake_Segment,            // Last popped tail (for tween)
    has_pending_tail: bool,
}
```

Each `Snake_Segment` stores both current and previous grid positions, enabling smooth per-frame tweening between discrete grid cells.

### Food

```odin
Food :: struct {
    col, row: int,
}
```

A grid cell position. When the snake head enters this cell, the food relocates and the score increments.

## Singleton Pattern

`Playable_Area` and `Game_State` are singletons — exactly one entity has each component. The game accesses them with helper procs that query for the component and return a pointer:

```odin
get_playable_area :: proc(w: ^ecs.World) -> ^Playable_Area {
    result: ^Playable_Area
    ecs.world_query1(w, Playable_Area, &result, proc(e: ecs.Entity, area: ^Playable_Area, ctx: rawptr) {
        (^(^Playable_Area))(ctx)^ = area
    })
    return result
}
```

This pattern works by passing a `^Playable_Area` pointer through the `ctx` rawptr. The callback writes the component pointer into it. Since there is only one entity with this component, the callback runs exactly once.

The same pattern is used for `get_game_state`.

## System Execution Order

Systems are registered via `*_runner_init` procs called in this order in `main`:

```odin
grid_runner_init(&runner)         // Registers: render_grid
game_state_runner_init(&runner)   // Registers: game_over_state, render_hud,
                                  //            render_pause_overlay, render_game_over
snake_runner_init(&runner)        // Registers: snake_input, snake_update, render_snake
food_runner_init(&runner)         // Registers: render_food
```

The resulting per-frame execution order, grouped by phase:

| Phase | System | File | What it does |
|---|---|---|---|
| `Pre_Update` | `game_over_state` | `game_state.odin` | Guard for game-over state logic |
| `Pre_Update` | `snake_input` | `snake.odin` | Buffer keyboard input into `next_direction` |
| `Update` | `snake_update` | `snake.odin` | Advance snake, check collisions, eat food |
| `Render` | `render_grid` | `playable_area.odin` | Draw background grid tiles |
| `Render` | `render_hud` | `game_state.odin` | Draw score and high score text |
| `Render` | `render_pause_overlay` | `game_state.odin` | Draw semi-transparent pause screen |
| `Render` | `render_game_over` | `game_state.odin` | Draw game-over overlay with final score |
| `Render` | `render_snake` | `snake.odin` | Draw snake segments with position tweening |
| `Render` | `render_food` | `food.odin` | Draw food as a red rectangle |

## Frame Lifecycle

Each frame:

1. **Delta time** — `rl.GetFrameTime()` captures frame duration.
2. **Input polling** (in `main` loop) — `P` toggles pause, `R` restarts after game over.
3. **Begin drawing** — `rl.BeginDrawing()` + `rl.ClearBackground(rl.BLACK)`.
4. **System runner update** — Runs all systems in phase order:
   - `Pre_Update`: Buffer input, check game-over conditions.
   - `Update`: `snake_update` accumulates `dt` into `move_timer`. When `move_timer >= move_interval`, the snake advances one cell. It checks wall collision, self collision, and food collision. On food collision, the snake grows and `food_relocate` moves the food.
   - `Render`: Draw everything in layer order (grid, HUD, overlays, snake, food).
5. **End drawing** — `rl.EndDrawing()` flushes to screen.

## Snake Movement and Tweening

The snake moves on a discrete grid at fixed intervals (`move_interval = 0.15s`). Between ticks, each segment is interpolated between its `prev_col/prev_row` and `col/row` positions:

```odin
t := snake.move_timer / snake.move_interval   // 0.0 to 1.0 within a tick

curr_x, curr_y := grid_to_screen(area, segment.col, segment.row)
prev_x, prev_y := grid_to_screen(area, segment.prev_col, segment.prev_row)
x := prev_x + (curr_x - prev_x) * t
y := prev_y + (curr_y - prev_y) * t
```

This gives smooth visual movement while keeping game logic on a clean grid. The `pending_tail` field preserves the last-popped tail segment for one tick so it can fade out smoothly rather than snapping away.

## Restart Flow

When the player presses `R` during `Game_Over`:

1. `game_restart` in `main.odin` is called.
2. High score is updated if the current score exceeds it.
3. Score is reset to 0, phase is set to `Playing`.
4. `kill_all(w, Snake)` and `kill_all(w, Food)` destroy all snake and food entities.
5. `snake_spawn` and `food_spawn` create fresh entities.

The `kill_all` helper queries for all entities with a given component, collects their IDs into a temporary buffer, then kills them after the query completes. This avoids modifying the world during iteration.

## Cross-System Communication

Systems communicate through shared components, not direct calls. For example:

- `snake_update` sets `gs.phase = .Game_Over` on collision — the game state system and overlay systems read this field on subsequent frames.
- `snake_update` calls `food_relocate` directly when food is eaten — this is a pragmatic choice since both operate on the same World. In the future, this could be replaced with an event (`Food_Eaten`) handled by the food system.
- `snake_input` writes to `snake.next_direction` — `snake_update` reads it on the next tick.

## Further Reading

- [ECS Architecture](ecs.md) — The underlying entity/component/query system
- [Systems](systems.md) — Phase ordering and the runner_init pattern
- [Roadmap](roadmap.md) — Planned improvements to the game and engine

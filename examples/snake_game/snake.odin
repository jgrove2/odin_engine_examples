package main

import "core:math/rand"
import "engine:ecs"
import rl "vendor:raylib"

// Event posted when the snake eats food. Consumed by food_update (Post_Update)
// to relocate the food entity.
Food_Eaten :: struct {
	col, row: int,
}

Direction :: enum {
	Up,
	Down,
	Left,
	Right,
}

Snake_Segment :: struct {
	col, row:           int, // current grid cell
	prev_col, prev_row: int, // grid cell before the last tick (for tweening)
}

Snake :: struct {
	segments:       [dynamic]Snake_Segment,
	direction:      Direction,
	next_direction: Direction, // buffered input, applied on the next tick
	move_timer:     f32, // accumulates dt between ticks
	move_interval:  f32, // seconds per cell
}

snake_runner_init :: proc(runner: ^ecs.System_Runner) {
	ecs.system_register(runner, "snake_input", snake_input, .Pre_Update)
	ecs.system_register(runner, "snake_update", snake_update, .Update)
	ecs.system_register(runner, "render_snake", render_snake, .Render)
}

// Spawns snake with three segments pointing upward at a random grid cell
snake_spawn :: proc(w: ^ecs.World, area: ^Playable_Area) {
	col := rand.int_max(area.cols)
	row := rand.int_max(area.rows - 2)
	segments := make([dynamic]Snake_Segment, 0, GRID_ROWS * GRID_COLS)
	// Head is topmost, body extends downward behind the direction of travel.
	// prev_* == current so t=0 draws in place on the first frame.
	append(&segments, Snake_Segment{col, row, col, row})
	append(&segments, Snake_Segment{col, row + 1, col, row + 1})
	append(&segments, Snake_Segment{col, row + 2, col, row + 2})
	ecs.world_spawn_with(
		w,
		Snake {
			segments = segments,
			direction = .Up,
			next_direction = .Up,
			move_timer = 0,
			move_interval = 0.15,
		},
	)
}

// Returns true if any Snake segment occupies the given cell
snake_occupies :: proc(w: ^ecs.World, col, row: int) -> bool {
	ctx := [3]int{col, row, 0}
	ecs.world_query1(w, Snake, &ctx, proc(e: ecs.Entity, snake: ^Snake, raw: rawptr) {
		c := (^[3]int)(raw)
		for seg in snake.segments {
			if seg.col == c[0] && seg.row == c[1] {
				c[2] = 1
				return
			}
		}
	})
	return ctx[2] == 1
}

// Pre_Update phase system — reads input and buffers the next direction
snake_input :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
	gs := get_game_state(w)
	if gs == nil || gs.phase != .Playing {return}

	new_dir: Direction
	got_input := false

	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) {
		new_dir = .Up
		got_input = true
	} else if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) {
		new_dir = .Down
		got_input = true
	} else if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.A) {
		new_dir = .Left
		got_input = true
	} else if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.D) {
		new_dir = .Right
		got_input = true
	}

	if !got_input {return}

	ecs.world_query1(
		w,
		Snake,
		&new_dir,
		proc(e: ecs.Entity, snake: ^Snake, raw: rawptr) {
			dir := (^Direction)(raw)^
			// Reject reversal — can't go directly opposite to current direction
			if dir == .Up && snake.direction == .Down {return}
			if dir == .Down && snake.direction == .Up {return}
			if dir == .Left && snake.direction == .Right {return}
			if dir == .Right && snake.direction == .Left {return}
			snake.next_direction = dir
		},
	)
}

// Update phase system — advances the snake one cell per tick
snake_update :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
	gs := get_game_state(w)
	if gs == nil || gs.phase != .Playing {return}

	area := get_playable_area(w)
	if area == nil {return}

	ctx := struct {
		w:    ^ecs.World,
		bus:  ^ecs.Event_Bus,
		area: ^Playable_Area,
		gs:   ^Game_State,
		dt:   f32,
	}{w, bus, area, gs, dt}

	ecs.world_query1(
		w,
		Snake,
		&ctx,
		proc(e: ecs.Entity, snake: ^Snake, raw: rawptr) {
			c := (^struct {
					w:    ^ecs.World,
					bus:  ^ecs.Event_Bus,
					area: ^Playable_Area,
					gs:   ^Game_State,
					dt:   f32,
				})(raw)

			snake.move_timer += c.dt
			if snake.move_timer < snake.move_interval {return}
			snake.move_timer -= snake.move_interval

			// Apply buffered direction
			snake.direction = snake.next_direction

			// Compute new head position
			head := snake.segments[0]
			new_col := head.col
			new_row := head.row
			switch snake.direction {
			case .Up:
				new_row -= 1
			case .Down:
				new_row += 1
			case .Left:
				new_col -= 1
			case .Right:
				new_col += 1
			}

			// Wall collision
			if new_col < 0 || new_col >= c.area.cols || new_row < 0 || new_row >= c.area.rows {
				c.gs.phase = .Game_Over
				return
			}

			// Self collision — exclude the tail segment (it vacates this tick)
			for i in 0 ..< len(snake.segments) - 1 {
				seg := snake.segments[i]
				if seg.col == new_col && seg.row == new_row {
					c.gs.phase = .Game_Over
					return
				}
			}

			// Food collision — check if any Food entity sits at the new head position
			food_ctx := struct {
				col, row: int,
				found:    bool,
			}{new_col, new_row, false}

			ecs.world_query1(c.w, Food, &food_ctx, proc(e: ecs.Entity, food: ^Food, raw: rawptr) {
				fc := (^struct {
						col, row: int,
						found:    bool,
					})(raw)
				if food.col == fc.col && food.row == fc.row {
					fc.found = true
				}
			})

			if food_ctx.found {
				// Eat: grow by duplicating the tail before shifting.
				// After the shift, this extra segment will tween from the
				// old tail position to the old second-to-last position,
				// making the snake one cell longer.
				tail := snake.segments[len(snake.segments) - 1]
				append(&snake.segments, tail)
			}

			// Chain-shift: each segment slides to where the one ahead of it was.
			// Walk from back to front so we don't overwrite values we still need.
			for i := len(snake.segments) - 1; i >= 1; i -= 1 {
				snake.segments[i].prev_col = snake.segments[i].col
				snake.segments[i].prev_row = snake.segments[i].row
				snake.segments[i].col = snake.segments[i - 1].col
				snake.segments[i].row = snake.segments[i - 1].row
			}

			// Advance the head
			snake.segments[0].prev_col = snake.segments[0].col
			snake.segments[0].prev_row = snake.segments[0].row
			snake.segments[0].col = new_col
			snake.segments[0].row = new_row

			if food_ctx.found {
				// Eat: post event for food relocation and score
				ecs.event_post(c.bus, Food_Eaten{col = new_col, row = new_row})
			}
		},
	)
}

// Render phase system — draws the snake with per-segment position tweening
render_snake :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
	area := get_playable_area(w)
	if area == nil {return}
	ctx := struct {
		area: ^Playable_Area,
		ts:   i32,
	}{area, i32(area.tile_size)}
	ecs.world_query1(
		w,
		Snake,
		&ctx,
		proc(e: ecs.Entity, snake: ^Snake, raw: rawptr) {
			c := (^struct {
					area: ^Playable_Area,
					ts:   i32,
				})(raw)

			t := snake.move_timer / snake.move_interval

			for segment, i in snake.segments {
				curr_x, curr_y := grid_to_screen(c.area, segment.col, segment.row)
				prev_x, prev_y := grid_to_screen(c.area, segment.prev_col, segment.prev_row)
				x := prev_x + (curr_x - prev_x) * t
				y := prev_y + (curr_y - prev_y) * t
				color := rl.GREEN
				rl.DrawRectangle(i32(x), i32(y), c.ts, c.ts, color)
			}
		},
	)
}

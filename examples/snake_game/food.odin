package main

import "core:math/rand"
import "engine:ecs"
import rl "vendor:raylib"

Food :: struct {
	col, row: int,
}

food_runner_init :: proc(runner: ^ecs.System_Runner) {
	ecs.system_register(runner, "food_update", food_update, .Post_Update)
	ecs.system_register(runner, "render_food", render_food_system, .Render)
}

// Spawns food at a random cell not occupied by other food or any snake segment
food_spawn :: proc(w: ^ecs.World, area: ^Playable_Area) {
	col, row: int
	for {
		col = rand.int_max(area.cols)
		row = rand.int_max(area.rows)
		if !food_position_occupied(w, col, row) && !snake_occupies(w, col, row) {break}
	}
	ecs.world_spawn_with(w, Food{col = col, row = row})
}

// Moves the existing food entity to a new random cell not occupied by the snake
food_relocate :: proc(w: ^ecs.World, area: ^Playable_Area) {
	col, row: int
	for {
		col = rand.int_max(area.cols)
		row = rand.int_max(area.rows)
		if !snake_occupies(w, col, row) {break}
	}
	ecs.world_query1(w, Food, &[2]int{col, row}, proc(e: ecs.Entity, food: ^Food, raw: rawptr) {
		pos := (^[2]int)(raw)
		food.col = pos[0]
		food.row = pos[1]
	})
}

// Post_Update phase system — drains Food_Eaten events and relocates the food entity.
// This decouples the snake (producer) from the food (consumer) via the event bus.
food_update :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
	area := get_playable_area(w)
	if area == nil {return}
	for _ in ecs.event_peek(bus, Food_Eaten) {
		food_relocate(w, area)
	}
}

// Returns true if any Food entity already occupies the given cell
food_position_occupied :: proc(w: ^ecs.World, col, row: int) -> bool {
	ctx := [3]int{col, row, 0} // [0]=col [1]=row [2]=result (0=false 1=true)
	ecs.world_query1(w, Food, &ctx, proc(e: ecs.Entity, food: ^Food, raw: rawptr) {
		c := (^[3]int)(raw)
		if food.col == c[0] && food.row == c[1] {c[2] = 1}
	})
	return ctx[2] == 1
}

// Render phase system — draws food as a red rect
render_food_system :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
	area := get_playable_area(w)
	if area == nil {return}
	ctx := struct {
		area: ^Playable_Area,
		ts:   i32,
	}{area, i32(area.tile_size)}
	ecs.world_query1(w, Food, &ctx, proc(e: ecs.Entity, food: ^Food, raw: rawptr) {
		c := (^struct {
				area: ^Playable_Area,
				ts:   i32,
			})(raw)
		x, y := grid_to_screen(c.area, food.col, food.row)
		rl.DrawRectangle(i32(x), i32(y), c.ts, c.ts, rl.RED)
	})
}

package main

import "engine:ecs"
import rl "vendor:raylib"

Playable_Area :: struct {
	origin_x:  f32,
	origin_y:  f32,
	rows:      int,
	cols:      int,
	tile_size: f32,
}

grid_runner_init :: proc(runner: ^ecs.System_Runner) {
	ecs.system_register(runner, "render_grid", render_grid_system, .Render)
}

// Convert a grid cell (col, row) to screen pixel position (top-left corner of the cell)
grid_to_screen :: proc(area: ^Playable_Area, col, row: int) -> (f32, f32) {
	return area.origin_x + f32(col) * area.tile_size, area.origin_y + f32(row) * area.tile_size
}

// Build a centered Playable_Area given screen dimensions
playable_area_init :: proc(
	screen_w, screen_h: f32,
	rows, cols: int,
	tile_size: f32,
) -> Playable_Area {
	grid_w := f32(cols) * tile_size
	grid_h := f32(rows) * tile_size
	return Playable_Area {
		origin_x = (screen_w - grid_w) / 2,
		origin_y = (screen_h - grid_h) / 2,
		rows = rows,
		cols = cols,
		tile_size = tile_size,
	}
}

// Returns a pointer to the single Playable_Area component in the world
get_playable_area :: proc(w: ^ecs.World) -> ^Playable_Area {
	result: ^Playable_Area
	ecs.world_query1(w, Playable_Area, &result, proc(e: ecs.Entity, area: ^Playable_Area, ctx: rawptr) {
		(^(^Playable_Area))(ctx)^ = area
	})
	return result
}

// Render phase system — draws the background grid tiles
render_grid_system :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
	ecs.world_query1(w, Playable_Area, nil, proc(e: ecs.Entity, area: ^Playable_Area, _: rawptr) {
		ts := i32(area.tile_size)
		for r in 0 ..< area.rows {
			for c in 0 ..< area.cols {
				x, y := grid_to_screen(area, c, r)
				rl.DrawRectangle(i32(x), i32(y), ts, ts, rl.DARKGRAY)
				rl.DrawRectangleLines(i32(x), i32(y), ts, ts, rl.BLACK)
			}
		}
	})
}

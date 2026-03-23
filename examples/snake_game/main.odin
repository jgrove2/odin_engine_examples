package main

import "engine:ecs"
import eng "engine:engine"
import rl "vendor:raylib"

SCREEN_W :: 800
SCREEN_H :: 600
GRID_ROWS :: 20
GRID_COLS :: 25
TILE_SIZE :: 20

// Kills all entities of a given component type
kill_all :: proc(w: ^ecs.World, $T: typeid) {
	to_kill := make([dynamic]ecs.Entity, 0, 4)
	defer delete(to_kill)
	ecs.world_query1(w, T, &to_kill, proc(e: ecs.Entity, _: ^T, raw: rawptr) {
		buf := (^[dynamic]ecs.Entity)(raw)
		append(buf, e)
	})
	for e in to_kill {
		ecs.world_kill(w, e)
	}
}

// Resets the game: updates high score, resets score/phase, respawns snake and food
game_restart :: proc(w: ^ecs.World) {
	gs := get_game_state(w)
	if gs == nil {return}

	if gs.score > gs.high_score {
		gs.high_score = gs.score
	}
	gs.score = 0
	gs.phase = .Playing

	area := get_playable_area(w)

	kill_all(w, Snake)
	kill_all(w, Food)

	snake_spawn(w, area)
	food_spawn(w, area)
}

main :: proc() {
	_ = eng.engine_create("Snake", SCREEN_W, SCREEN_H, 60)
	defer eng.engine_shutdown()

	// --- ECS setup ---
	world := ecs.world_create()
	defer ecs.world_destroy(&world)

	runner := ecs.system_runner_create()
	defer ecs.system_runner_destroy(&runner)

	// Register component types
	ecs.world_register_component(&world, Playable_Area)
	ecs.world_register_component(&world, Snake)
	ecs.world_register_component(&world, Food)
	ecs.world_register_component(&world, Game_State)

	// Spawn entities
	ecs.world_spawn_with(
		&world,
		playable_area_init(SCREEN_W, SCREEN_H, GRID_ROWS, GRID_COLS, TILE_SIZE),
	)
	ecs.world_spawn_with(&world, game_state_init())

	area := get_playable_area(&world)
	snake_spawn(&world, area)
	food_spawn(&world, area)

	// Register systems — phases run Pre_Update → Update → Post_Update → Render → Debug
	ecs.system_register(&runner, "snake_input", snake_input, .Pre_Update)
	ecs.system_register(&runner, "game_over_state", game_over_state, .Pre_Update)
	ecs.system_register(&runner, "snake_update", snake_update, .Update)
	ecs.system_register(&runner, "render_grid", render_grid_system, .Render)
	ecs.system_register(&runner, "render_snake", render_snake, .Render)
	ecs.system_register(&runner, "render_food", render_food_system, .Render)
	ecs.system_register(&runner, "render_hud", render_hud, .Render)
	ecs.system_register(&runner, "render_pause_overlay", render_pause_overlay, .Render)
	ecs.system_register(&runner, "render_game_over", render_game_over_overlay, .Render)

	// --- Main loop ---
	for !eng.engine_should_close() {
		dt := rl.GetFrameTime()

		// --- Input: pause / restart ---
		gs := get_game_state(&world)
		if gs != nil {
			if rl.IsKeyPressed(.P) {
				if gs.phase == .Playing {
					gs.phase = .Paused
				} else if gs.phase == .Paused {
					gs.phase = .Playing
				}
			}
			if rl.IsKeyPressed(.R) && gs.phase == .Game_Over {
				game_restart(&world)
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		ecs.system_runner_update(&runner, &world, dt)

		rl.EndDrawing()
	}
}

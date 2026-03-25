package main

import "engine:ecs"
import eng "engine:engine"
import rl "vendor:raylib"

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
	eng.engine_create("Snake", 800, 600, 60)
	defer eng.engine_shutdown()

	// --- Input bindings ---
	snake_input_init()

	// --- Compositor setup ---
	compositor := ecs.compositor_create()
	defer ecs.compositor_destroy(&compositor)

	gameplay := ecs.compositor_create_world(&compositor)

	// Spawn entities — component types are auto-registered on first use
	e := eng.engine_get()
	ecs.world_spawn_with(
		&gameplay.world,
		playable_area_init(f32(e.screen_width), f32(e.screen_height), GRID_ROWS, GRID_COLS, TILE_SIZE),
	)
	ecs.world_spawn_with(&gameplay.world, game_state_init())

	area := get_playable_area(&gameplay.world)
	snake_spawn(&gameplay.world, area)
	food_spawn(&gameplay.world, area)

	// Register systems — phases run Pre_Update → Update → Post_Update → Render → Debug
	grid_runner_init(&gameplay.runner)
	game_state_runner_init(&gameplay.runner)
	snake_runner_init(&gameplay.runner)
	food_runner_init(&gameplay.runner)

	// --- Main loop ---
	for !eng.engine_should_close() {
		dt := rl.GetFrameTime()

		// Update input state before anything else
		eng.input_map_update(eng.input_map_get())

		// --- Input: pause / restart ---
		gs := get_game_state(&gameplay.world)
		if gs != nil {
			if eng.input_pressed("pause") {
				if gs.phase == .Playing {
					gs.phase = .Paused
				} else if gs.phase == .Paused {
					gs.phase = .Playing
				}
			}
			if eng.input_pressed("restart") && gs.phase == .Game_Over {
				game_restart(&gameplay.world)
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		ecs.compositor_update(&compositor, dt)

		rl.EndDrawing()
	}
}

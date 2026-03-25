package main

import "core:fmt"
import "engine:ecs"
import eng "engine:engine"
import rl "vendor:raylib"

Game_Phase :: enum {
	Playing,
	Paused,
	Game_Over,
}

Game_State :: struct {
	score:      int,
	high_score: int,
	phase:      Game_Phase,
}

game_state_runner_init :: proc(runner: ^ecs.System_Runner) {
	ecs.system_register(runner, "game_over_state", game_over_state, .Pre_Update)
	ecs.system_register(runner, "game_state_update", game_state_update, .Post_Update)
	ecs.system_register(runner, "render_hud", render_hud, .Render)
	ecs.system_register(runner, "render_pause_overlay", render_pause_overlay, .Render)
	ecs.system_register(runner, "render_game_over", render_game_over_overlay, .Render)
}

game_state_init :: proc() -> Game_State {
	return Game_State{score = 0, high_score = 0, phase = .Playing}
}

// Returns a pointer to the single Game_State component in the world
get_game_state :: proc(w: ^ecs.World) -> ^Game_State {
	result: ^Game_State
	ecs.world_query1(w, Game_State, &result, proc(e: ecs.Entity, gs: ^Game_State, raw: rawptr) {
		(^(^Game_State))(raw)^ = gs
	})
	return result
}

game_over_state :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
	gs := get_game_state(w)
	if gs == nil || gs.phase != .Game_Over {return}
}

// Post_Update phase system — reacts to Food_Eaten events by incrementing score
game_state_update :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
	gs := get_game_state(w)
	if gs == nil {return}
	for _ in ecs.event_peek(bus, Food_Eaten) {
		gs.score += 1
	}
}

// Render phase system — draws score and high score above the grid
render_hud :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
	gs := get_game_state(w)
	if gs == nil {return}
	area := get_playable_area(w)
	if area == nil {return}

	hud_y := i32(area.origin_y) / 2 - 10

	score_text := fmt.ctprintf("Score: %d", gs.score)
	best_text := fmt.ctprintf("Best: %d", gs.high_score)

	rl.DrawText(score_text, i32(area.origin_x), hud_y, 20, rl.WHITE)

	best_width := rl.MeasureText(best_text, 20)
	rl.DrawText(
		best_text,
		i32(area.origin_x) + i32(area.cols) * i32(area.tile_size) - best_width,
		hud_y,
		20,
		rl.YELLOW,
	)
}

// Render phase system — draws a semi-transparent pause overlay
render_pause_overlay :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
	gs := get_game_state(w)
	if gs == nil || gs.phase != .Paused {return}

	e := eng.engine_get()
	sw := e.screen_width
	sh := e.screen_height

	rl.DrawRectangle(0, 0, sw, sh, {0, 0, 0, 160})

	title := cstring("PAUSED")
	subtitle := cstring("Press P to resume")

	title_w := rl.MeasureText(title, 48)
	subtitle_w := rl.MeasureText(subtitle, 20)

	rl.DrawText(title, sw / 2 - title_w / 2, sh / 2 - 36, 48, rl.WHITE)
	rl.DrawText(subtitle, sw / 2 - subtitle_w / 2, sh / 2 + 20, 20, rl.LIGHTGRAY)
}

// Render phase system — draws a game over overlay with final score
render_game_over_overlay :: proc(w: ^ecs.World, bus: ^ecs.Event_Bus, dt: f32) {
	gs := get_game_state(w)
	if gs == nil || gs.phase != .Game_Over {return}

	e := eng.engine_get()
	sw := e.screen_width
	sh := e.screen_height

	rl.DrawRectangle(0, 0, sw, sh, {0, 0, 0, 180})

	title := cstring("GAME OVER")
	score_text := fmt.ctprintf("Score: %d   Best: %d", gs.score, gs.high_score)
	restart := cstring("Press R to restart")

	title_w := rl.MeasureText(title, 56)
	score_w := rl.MeasureText(score_text, 22)
	restart_w := rl.MeasureText(restart, 20)

	rl.DrawText(title, sw / 2 - title_w / 2, sh / 2 - 56, 56, rl.RED)
	rl.DrawText(score_text, sw / 2 - score_w / 2, sh / 2 + 10, 22, rl.WHITE)
	rl.DrawText(restart, sw / 2 - restart_w / 2, sh / 2 + 46, 20, rl.LIGHTGRAY)
}

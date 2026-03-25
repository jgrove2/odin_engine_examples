package main

import eng "engine:engine"
import rl "vendor:raylib"

// Register all input action bindings for the snake game.
// Called once at startup after engine_create.
snake_input_init :: proc() {
	im := eng.input_map_get()
	eng.input_bind(im, "move_up", {.UP, .W})
	eng.input_bind(im, "move_down", {.DOWN, .S})
	eng.input_bind(im, "move_left", {.LEFT, .A})
	eng.input_bind(im, "move_right", {.RIGHT, .D})
	eng.input_bind(im, "pause", {.P})
	eng.input_bind(im, "restart", {.R})
}

package basic

import eng "engine:engine"
import rl "vendor:raylib"

main :: proc() {
	e := eng.engine_create("Basic Example", 800, 600, 60)
	defer eng.engine_shutdown()

	for !eng.engine_should_close() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)
		rl.DrawText("Hello, World!", 190, 200, 40, rl.BLACK)
		rl.EndDrawing()
	}
}

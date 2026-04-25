package main

import "vendor:raylib"
import "core:math"
import "core:fmt"

import "constants"
import "game"
import "systems"

// Window settings
WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 800
WINDOW_TITLE :: "Tower Defense - Odin + Raylib"

main :: proc() {
	// Initialize raylib
	raylib.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)
	defer raylib.CloseWindow()
	
	raylib.SetTargetFPS(constants.MAX_FPS)
	raylib.SetExitKey(.KEY_NULL) // Disable default exit key
	
	// Initialize random seed
	math.random_seed(f64(raylib.GetTime()))
	
	// Initialize game
	game.app_init()
	defer game.app_destroy()
	
	// Main game loop
	for !raylib.WindowShouldClose() {
		// Calculate delta time
		dt := raylib.GetFrameTime()
		game.app.delta_time = dt
		
		// Handle input
		systems.input_handle()
		
		// Update simulation (if playing)
		if game.app.state == .PLAYING {
			systems.simulation_update(dt)
		}
		
		// Render
		raylib.BeginDrawing()
		systems.render_game()
		raylib.EndDrawing()
	}
}

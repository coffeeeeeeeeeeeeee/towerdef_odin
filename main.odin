package main

import "vendor:raylib"
import "core:math"
import "core:math/rand"
import "core:fmt"

import "constants"
import "entities"
import "systems"

// Window settings
WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 600
WINDOW_TITLE :: "First Impact"

main :: proc() {
	// Initialize raylib
	raylib.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT})
	raylib.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)
	defer raylib.CloseWindow()
	
	raylib.SetTargetFPS(constants.MAX_FPS)
	raylib.SetExitKey(.KEY_NULL) // Disable default exit key
	
	// Initialize random seed
	rand.reset(u64(raylib.GetTime() * 1000))
	
	// Initialize game
	app_init()
	defer app_destroy()
	
	// Main game loop
	for !raylib.WindowShouldClose() {
		// Calculate delta time
		dt := raylib.GetFrameTime()
		app.delta_time = dt
		
		// Handle input
		systems.input_handle(&app)
		
		// Smooth zoom interpolation with easing (slow start, fast end)
		if app.zoom != app.target_zoom {
			// Calculate progress based on zoom difference
			total_diff := app.target_zoom - app.zoom
			if total_diff < 0 {
				total_diff = -total_diff
			}
			
			// Base speed factor
			speed := constants.ZOOM_SMOOTH_SPEED * dt
			
			// Apply easing to speed (slow start, fast end)
			// Normalize progress roughly from 0 to 1 based on remaining distance
			progress := 1.0 - (total_diff / (constants.ZOOM_MAX - constants.ZOOM_MIN))
			if progress < 0 {
				progress = 0
			}
			if progress > 1.0 {
				progress = 1.0
			}
			
			// Apply easing to speed
			eased_speed := speed * constants.ease_zoom(progress)
			
			// Apply zoom change
			if app.target_zoom > app.zoom {
				app.zoom += eased_speed * total_diff
				if app.zoom > app.target_zoom {
					app.zoom = app.target_zoom
				}
			} else {
				app.zoom -= eased_speed * total_diff
				if app.zoom < app.target_zoom {
					app.zoom = app.target_zoom
				}
			}
			
			// Snap to target when very close
			diff := app.zoom - app.target_zoom
			if diff < 0 {
				diff = -diff
			}
			if diff < 0.001 {
				app.zoom = app.target_zoom
			}
		}
		
		// Update simulation (if playing)
		if app.state == .PLAYING {
			systems.simulation_update(&app, dt)
		}
		
		// Render
		raylib.BeginDrawing()
		systems.render_game(&app)
		raylib.EndDrawing()
	}
}

// Initialize application
app_init :: proc() {
	// Calculate initial camera offset to center the grid
	grid_total_size := f32(constants.GRID_SIZE) * f32(constants.CELL_SIZE)
	screen_width := f32(WINDOW_WIDTH)
	screen_height := f32(WINDOW_HEIGHT)
	
	camera_offset_x := i32((screen_width - grid_total_size) / 2)
	camera_offset_y := i32((screen_height - grid_total_size) / 2)
	
	app = entities.App_State{
		state = .MENU,
		previous_state = .MENU,
		sim = entities.Simulation{
			towers = make([dynamic]entities.Tower),
			enemies = make([dynamic]entities.Enemy),
			projectiles = make([dynamic]entities.Projectile),
			explosions = make([dynamic]entities.Explosion),
			damage_numbers = make([dynamic]entities.Damage_Number),
			laser_beams = make([dynamic]entities.Laser_Beam),
			spawns = make([dynamic]entities.Spawn_Point),
			money = constants.DEFAULT_MONEY,
			health = constants.DEFAULT_HEALTH,
			wave_number = 1,
			speed = 1.0,
			paused = false,
			started = false,
			selected_build_tower = .EMPTY,
		},
		editor = entities.Editor{
			game_map = entities.map_init(),
			current_tool = .EMPTY,
			show_grid = true,
			show_paths = false,
			current_biome = .PLAIN,
			load_map_filename = {},
			load_map_active = false,
		},
		settings = entities.Settings{
			grid_size = constants.GRID_SIZE,
			cell_size = constants.CELL_SIZE,
			show_grid = true,
			show_fps = false,
		},
		zoom = 1.0,
		target_zoom = 1.0,
		camera_offset_x = camera_offset_x,
		camera_offset_y = camera_offset_y,
		selected_cell = {row = 0, col = 0, valid = false},
	}
	
	systems.simulation_reset(&app)
}

// Destroy application and free resources
app_destroy :: proc() {
	entities.map_destroy(&app.editor.game_map)
	systems.simulation_cleanup(&app)
}

// Global app instance using entities.App_State
app: entities.App_State

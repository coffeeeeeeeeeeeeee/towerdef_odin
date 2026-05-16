package main

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import "vendor:raylib"

import "constants"
import "entities"
import "systems"

// Window settings
WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 600
WINDOW_TITLE :: "First Impact"

main :: proc() {
	// Load settings first
	initial_settings := load_settings()

	// Initialize raylib using loaded settings
	config_flags := raylib.ConfigFlags{.WINDOW_RESIZABLE}
	if initial_settings.vsync {
		config_flags += {.VSYNC_HINT}
	}
	if initial_settings.antialiasing > 0 {
		config_flags += {.MSAA_4X_HINT}
	}

	raylib.SetConfigFlags(config_flags)
	raylib.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)
	defer raylib.CloseWindow()

	if initial_settings.fullscreen {
		monitor := raylib.GetCurrentMonitor()
		// Position window at monitor origin before toggling fullscreen
		monitor_pos := raylib.GetMonitorPosition(monitor)
		raylib.SetWindowPosition(i32(monitor_pos.x), i32(monitor_pos.y))
		raylib.SetWindowSize(raylib.GetMonitorWidth(monitor), raylib.GetMonitorHeight(monitor))
		raylib.SetWindowState({.WINDOW_UNDECORATED})
		raylib.ToggleFullscreen()
	} else if initial_settings.window_maximized {
		raylib.MaximizeWindow()
	}

	raylib.SetTargetFPS(constants.MAX_FPS)
	raylib.SetExitKey(.KEY_NULL) // Disable default exit key

	// Initialize random seed
	rand.reset(u64(raylib.GetTime() * 1000))

	// Initialize translations
	constants.init_translations()
	constants.set_language(initial_settings.language)

	// Initialize fonts
	constants.load_fonts()
	defer constants.unload_fonts()

	// Initialize audio system
	systems.audio_init()
	defer systems.audio_cleanup()

	// Set UI volume from settings (combined with master volume)
	systems.set_ui_volume(initial_settings.master_volume, initial_settings.ui_volume)

	// Initialize game
	app_init(initial_settings)
	defer {
		save_settings(app.settings)
		app_destroy()
	}

	// Main game loop
	for !raylib.WindowShouldClose() && !app.should_quit {
		// Calculate delta time
		dt := raylib.GetFrameTime()
		app.delta_time = dt

		// Handle input
		systems.input_handle(&app)

		// Handle window resize (including Maximized and Fullscreen)
		if raylib.IsWindowResized() {
			grid_total_size := f32(app.settings.grid_size) * f32(app.settings.cell_size) * app.target_zoom
			screen_width := f32(raylib.GetScreenWidth())
			screen_height := f32(raylib.GetScreenHeight())

			// Recenter the camera relative to the new dimensions
			app.target_camera_offset_x = i32((screen_width - grid_total_size) / 2)
			app.target_camera_offset_y = i32((screen_height - grid_total_size) / 2)

			// Snap instantly to avoid long glides when maximizing/fullscreening
			app.camera_offset_x = app.target_camera_offset_x
			app.camera_offset_y = app.target_camera_offset_y
		}

		// Handle window maximization state changes
		current_maximized := raylib.IsWindowMaximized()
		if current_maximized != app.settings.window_maximized {
			app.settings.window_maximized = current_maximized
			if current_maximized {
				systems.play_sound(.MAXIMIZE)
			} else {
				systems.play_sound(.MINIMIZE)
			}
		}

		// Smooth zoom and camera offset interpolation
		zoom_needs_update := app.zoom != app.target_zoom
		camera_needs_update :=
			app.camera_offset_x != app.target_camera_offset_x ||
			app.camera_offset_y != app.target_camera_offset_y

		if zoom_needs_update || camera_needs_update {
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
			if eased_speed > 1.0 {
				eased_speed = 1.0
			}

			// Smooth zoom
			if zoom_needs_update {
				app.zoom = app.zoom + (app.target_zoom - app.zoom) * eased_speed
				// Snap to target when very close
				diff := app.zoom - app.target_zoom
				if diff < 0 {
					diff = -diff
				}
				if diff < 0.001 {
					app.zoom = app.target_zoom
				}
			}

			// Smooth camera offset (same easing as zoom)
			if camera_needs_update {
				offset_x_diff := f32(app.target_camera_offset_x - app.camera_offset_x)
				offset_y_diff := f32(app.target_camera_offset_y - app.camera_offset_y)

				app.camera_offset_x = app.camera_offset_x + i32(offset_x_diff * eased_speed)
				app.camera_offset_y = app.camera_offset_y + i32(offset_y_diff * eased_speed)

				// Snap to target when very close
				x_diff := app.camera_offset_x - app.target_camera_offset_x
				y_diff := app.camera_offset_y - app.target_camera_offset_y
				if x_diff < 0 {
					x_diff = -x_diff
				}
				if y_diff < 0 {
					y_diff = -y_diff
				}
				if x_diff < 1 && y_diff < 1 {
					app.camera_offset_x = app.target_camera_offset_x
					app.camera_offset_y = app.target_camera_offset_y
				}
			}
		}

		// Update simulation (if playing)
		if app.state == .PLAYING {
			systems.simulation_update(&app, dt)
		}

		// Update toasts (always)
		entities.update_toasts(&app, dt)

		// Render
		raylib.BeginDrawing()
		systems.render_game(&app)
		raylib.EndDrawing()

		// Free all temp-allocator memory accumulated this frame.
		// fmt.ctprintf / strings.clone_to_cstring(s, context.temp_allocator) are
		// safe to use anywhere in the frame because their lifetime is exactly one frame.
		free_all(context.temp_allocator)
	}
}

// Initialize application
app_init :: proc(initial_settings: entities.Settings) {
	// Calculate initial camera offset to center the grid
	grid_total_size := f32(constants.GRID_SIZE) * f32(constants.CELL_SIZE)
	screen_width := f32(WINDOW_WIDTH)
	screen_height := f32(WINDOW_HEIGHT)

	camera_offset_x := i32((screen_width - grid_total_size) / 2)
	camera_offset_y := i32((screen_height - grid_total_size) / 2)

	app = entities.App_State {
		state = .MENU,
		previous_state = .MENU,
		toasts = make([dynamic]entities.Toast),
		sim = entities.Simulation {
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
		editor = entities.Editor {
			game_map = entities.map_init(),
			current_tool = .EMPTY,
			show_grid = true,
			show_paths = false,
			current_biome = .PLAIN,
			load_map_filename = {},
			load_map_active = false,
		},
		settings = initial_settings,
		zoom = 1.0,
		target_zoom = 1.0,
		camera_offset_x = camera_offset_x,
		camera_offset_y = camera_offset_y,
		target_camera_offset_x = camera_offset_x,
		target_camera_offset_y = camera_offset_y,
		selected_tower_r = -1,
		selected_tower_c = -1,
		selected_obstacle = {row = 0, col = 0, valid = false},
		selected_cell = {row = 0, col = 0, valid = false},
	}

	systems.simulation_reset(&app)
}

// Destroy application and free resources
app_destroy :: proc() {
	entities.map_destroy(&app.editor.game_map)
	systems.simulation_cleanup(&app)

	// Free editor dynamic data
	for f in app.editor.map_browser_files {
		delete(f)
	}
	delete(app.editor.map_browser_files)

	for &s in app.editor.undo_stack {
		entities.map_snapshot_destroy(&s)
	}
	delete(app.editor.undo_stack)

	for &s in app.editor.redo_stack {
		entities.map_snapshot_destroy(&s)
	}
	delete(app.editor.redo_stack)
}

// Global app instance using entities.App_State
app: entities.App_State

// Save settings to a JSON file
save_settings :: proc(settings: entities.Settings) {
	data, err := json.marshal(settings, {pretty = true})
	if err == nil {
		os.write_entire_file("settings.json", data)
		delete(data)
	}
}

// Load settings from a JSON file, or return defaults if it doesn't exist
load_settings :: proc() -> entities.Settings {
	settings := entities.Settings {
		grid_size           = constants.GRID_SIZE,
		cell_size           = constants.CELL_SIZE,
		show_grid           = true,
		show_fps            = false,
		language            = .ENGLISH,
		master_volume       = 1.0,
		ui_volume           = 1.0,
		fullscreen          = false,
		vsync               = true,
		antialiasing        = 2, // 4x default
		window_maximized    = false,
		show_damage_numbers = true,
		show_tower_range    = false,
		auto_start_wave     = true,
	}

	data, ok := os.read_entire_file_from_filename("settings.json")
	if ok {
		json.unmarshal(data, &settings)
		delete(data)
	}

	return settings
}

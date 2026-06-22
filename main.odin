package main

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
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

	// Load icon textures
	constants.load_icons()
	defer constants.unload_icons()
	entities.load_relic_icons()
	defer entities.unload_relic_icons()

	// Initialize UI shaders
	systems.card_grayscale_shader_init()
	defer systems.card_grayscale_shader_unload()

	// Initialize glow particle shader
	systems.glow_circle_shader_init()
	defer systems.glow_circle_shader_unload()

	// Initialize audio system
	systems.audio_init()
	defer systems.audio_cleanup()
	systems.music_init()
	defer systems.music_cleanup()

	// Load nebula background shader
	systems.nebula_init()
	defer systems.nebula_unload()

	// Load water blob shader
	systems.water_shader_init()
	defer systems.water_shader_unload()

	// Load cloud layer shader
	systems.cloud_shader_init()
	defer systems.cloud_shader_unload()

	// Load heightmap overlay shader (desniveles del terreno)
	systems.heightmap_shader_init()
	defer systems.heightmap_shader_unload()

	// Load grass overlay shader (Plain & Forest biomes)
	systems.grass_shader_init()
	defer systems.grass_shader_unload()

	// Set per-layer volumes from settings
	systems.set_volume(.UI,  initial_settings.master_volume * initial_settings.ui_volume)
	systems.set_volume(.SFX, initial_settings.master_volume * initial_settings.sfx_volume)
	systems.music_set_volume(initial_settings.master_volume * initial_settings.music_volume)

	// Initialize game
	app_init(initial_settings)
	// Load meta-progression save
	app.meta = entities.meta_load()
	defer {
		// Flush meta antes de cerrar — captura cualquier cambio pendiente que
		// no haya pasado por una transición de estado.
		entities.app_meta_flush(&app)
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

			systems.water_shader_resize()
		}

		// Handle window maximization state changes
		current_maximized := raylib.IsWindowMaximized()
		if current_maximized != app.settings.window_maximized {
			app.settings.window_maximized = current_maximized
			if current_maximized {
				systems.play_sound(.MAXIMIZE, .UI)
			} else {
				systems.play_sound(.MINIMIZE, .UI)
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

		// Update music stream (every frame)
		// muffled = PAUSED o shop abierto durante PLAYING
		music_muffled := app.state == .PAUSED ||
		                 (app.state == .PLAYING && app.sim.shop.active)
		systems.music_update(app.state, dt, music_muffled)

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

		// Persistir meta si quedó algo dirty este frame. Idempotente — barata
		// cuando no hay cambios. Garantiza que ningún cambio se pierda aunque
		// el jugador cierre la ventana inmediatamente.
		entities.app_meta_flush(&app)

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
		state          = .MENU,
		previous_state = .MENU,
		toasts         = make([dynamic]entities.Toast),
		editor = entities.Editor {
			game_map        = entities.map_init(),
			current_tool    = .EMPTY,
			show_grid       = true,
			show_paths      = false,
			current_biome   = .PLAIN,
			load_map_active = false,
			campaign_editor = entities.Campaign_Editor_State{ selected_node = -1 },
		},
		settings              = initial_settings,
		zoom                  = 1.0,
		target_zoom           = 1.0,
		camera_offset_x       = camera_offset_x,
		camera_offset_y       = camera_offset_y,
		target_camera_offset_x = camera_offset_x,
		target_camera_offset_y = camera_offset_y,
		selected_tower_r      = -1,
		selected_tower_c      = -1,
		current_campaign_node = -1,
	}

	// simulation_reset inicializa sim desde cero (dynamic arrays, seed, mazo, etc.)
	systems.simulation_reset(&app)
}

// Destroy application and free resources
app_destroy :: proc() {
	entities.map_destroy(&app.editor.game_map)
	systems.simulation_cleanup(&app)

	// Free editor dynamic data
	entities.map_file_entries_destroy(&app.editor.browser.entries)
	entities.map_destroy(&app.editor.browser.preview)
	if app.editor.browser.preview_tex_valid {
		raylib.UnloadRenderTexture(app.editor.browser.preview_tex)
	}

	for &s in app.editor.undo_stack {
		entities.map_snapshot_destroy(&s)
	}
	delete(app.editor.undo_stack)

	for &s in app.editor.redo_stack {
		entities.map_snapshot_destroy(&s)
	}
	delete(app.editor.redo_stack)

	// Toasts pendientes: cada uno tiene un message clonado en el heap
	for &t in app.toasts {
		delete(t.message)
	}
	delete(app.toasts)
}

// Global app instance using entities.App_State
app: entities.App_State

// ─────────────────────────────────────────────────────────────────────────────
// Persistencia de settings — formato binario fijo (settings.bin).
// settings.json se mantiene como fallback para migración: si el usuario tenía
// un settings.json de versión vieja, se lee y se convierte a .bin la próxima
// vez que se guarda. Después de la migración, .json puede borrarse manualmente.
// ─────────────────────────────────────────────────────────────────────────────

SETTINGS_BIN_VERSION  :: u32(2)
SETTINGS_BIN_PATH     :: "settings.bin"
SETTINGS_JSON_PATH    :: "settings.json"

Settings_File :: struct {
	version:  u32,
	_pad:     [4]u8,
	settings: entities.Settings,
	_trailing_pad: [64]u8,  // reserva para futuro
}

// Guarda settings al disco. Siempre escribe binario; el JSON queda obsoleto
// y puede borrarse a mano si lo deseas.
save_settings :: proc(settings: entities.Settings) {
	file := Settings_File{
		version  = SETTINGS_BIN_VERSION,
		settings = settings,
	}
	data := mem.ptr_to_bytes(&file)
	os.write_entire_file(SETTINGS_BIN_PATH, data)
}

// Carga settings con fallback chain: bin → json → defaults.
load_settings :: proc() -> entities.Settings {
	defaults := entities.Settings {
		grid_size           = constants.GRID_SIZE,
		cell_size           = constants.CELL_SIZE,
		show_grid           = true,
		show_fps            = false,
		language            = .ENGLISH,
		master_volume       = 1.0,
		ui_volume           = 1.0,
		sfx_volume          = 1.0,
		music_volume        = 1.0,
		fullscreen          = false,
		vsync               = true,
		antialiasing        = 2, // 4x default
		window_maximized    = false,
		show_damage_numbers = true,
		show_tower_range    = false,
		auto_start_wave     = true,
	}

	// 1. Try binary
	if data, ok := os.read_entire_file_from_filename(SETTINGS_BIN_PATH); ok {
		defer delete(data)
		if len(data) == size_of(Settings_File) {
			file := (cast(^Settings_File)raw_data(data))^
			if file.version == SETTINGS_BIN_VERSION {
				return file.settings
			}
			fmt.printfln("[load_settings] settings.bin version mismatch (%d vs %d), descartando",
				file.version, SETTINGS_BIN_VERSION)
		} else {
			fmt.printfln("[load_settings] settings.bin tamaño inválido (%d vs %d), descartando",
				len(data), size_of(Settings_File))
		}
	}

	// 2. Fall back to JSON for migration
	settings := defaults
	if data, ok := os.read_entire_file_from_filename(SETTINGS_JSON_PATH); ok {
		defer delete(data)
		if json.unmarshal(data, &settings) == nil {
			fmt.println("[load_settings] migrado desde settings.json — se guardará como .bin en el próximo save")
			return settings
		}
	}

	// 3. Defaults
	return defaults
}

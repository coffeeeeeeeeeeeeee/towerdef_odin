package systems

import "vendor:raylib"
import "../entities"
import "../constants"
import "core:fmt"

// Handle all input
input_handle :: proc(app: ^entities.App_State) {
	// No mover la cámara mientras el browser de mapas está abierto en el editor
	if !(app.state == .EDITOR && app.editor.show_map_browser) {
		input_handle_camera(app)
	}
	
	switch app.state {
	case .MENU:
		input_handle_menu(app)
	case .PLAYING:
		input_handle_playing(app)
	case .PAUSED:
		input_handle_paused(app)
	case .EDITOR:
		input_handle_editor(app)
	case .GAME_OVER:
		input_handle_game_over(app)
	case .SETTINGS:
		// Settings menu input is handled via render_button in render_settings_menu
		if raylib.IsKeyPressed(.ESCAPE) {
			entities.app_set_state(app, app.previous_state)
		}
	}
}

// Menu input
input_handle_menu :: proc(app: ^entities.App_State) {
	// Handled by render_button in rendering.odin
}

// Playing input
input_handle_playing :: proc(app: ^entities.App_State) {
	// Mouse position for grid selection
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	// Convert to grid coordinates using helper function
	grid_x, grid_y := screen_to_grid(app, mouse_x, mouse_y)
	
	app.mouse_x = grid_x
	app.mouse_y = grid_y
	
	// Update selected cell for reticle display
	if is_valid_grid_pos(app, grid_x, grid_y) {
		app.selected_cell.row = grid_y
		app.selected_cell.col = grid_x
		app.selected_cell.valid = true
	} else {
		app.selected_cell.valid = false
	}
	
	// Left click to place tower
	if raylib.IsMouseButtonPressed(.LEFT) {
		// Don't process grid clicks if mouse is over any UI panel or button
		if ui_is_click_blocked(mouse_x, mouse_y) {
			return
		}

		if is_valid_grid_pos(app, grid_x, grid_y) {
			// Check if clicking on a tower
			tile := app.editor.game_map.grid[grid_y][grid_x]
			obstacle := app.editor.game_map.obstacle_grid[grid_y][grid_x]

			#partial switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER, .TOWER_ICE, .TOWER_ENHANCE:
				// Select tower for upgrade
				select_tower_at(app, grid_y, grid_x)
				app.selected_obstacle.valid = false // Deselect obstacle
				play_sound(.SELECT, .UI)
			case:
				// Not a tower - check if it's an obstacle
				if obstacle == .OBSTACLE {
					// Select obstacle
					app.selected_obstacle.row = grid_y
					app.selected_obstacle.col = grid_x
					app.selected_obstacle.valid = true
					entities.app_deselect_tower(app) // Deselect tower
					play_sound(.SELECT, .UI)
				} else {
					// Deselect both tower and obstacle
					entities.app_deselect_tower(app)
					app.selected_obstacle.valid = false

					// Place selected card if one is selected
					if app.sim.selected_build_tower != .EMPTY {
						if app.sim.selected_build_tower == .OBSTACLE {
							// Colocar obstáculo — gratuito, ya se pagó en el shop
							is_forbidden := entities.map_is_path_corner_or_junction(&app.editor.game_map, grid_y, grid_x)
							if app.editor.game_map.obstacle_grid[grid_y][grid_x] == .EMPTY && !is_forbidden {
								app.editor.game_map.obstacle_grid[grid_y][grid_x] = .OBSTACLE
								entities.card_play(&app.sim, app.sim.selected_card_idx)
								app.sim.selected_build_tower = .EMPTY
								app.sim.selected_card_idx    = -1
								play_sound(.CLICK, .UI)
							}
						} else {
							// Colocar torre — gratuito, ya se pagó en el shop.
							// Se puede construir sobre árboles (ACCESSORY_TREE): el árbol se destruye.
							tower_type := tile_to_tower_type(app.sim.selected_build_tower)
							can_place  := (tile == .EMPTY || tile == .ACCESSORY_TREE) &&
							              app.editor.game_map.obstacle_grid[grid_y][grid_x] == .EMPTY
							if can_place {
								app.editor.game_map.grid[grid_y][grid_x] = app.sim.selected_build_tower
								tower := entities.tower_init(tower_type, grid_y, grid_x)
								selected_card := app.sim.hand[app.sim.selected_card_idx]
								for _ in 0 ..< selected_card.bonus_level {
									entities.tower_upgrade(&tower)
								}
								append(&app.sim.towers, tower)
								app.sim.towers_built += 1
								entities.card_play(&app.sim, app.sim.selected_card_idx)
								app.sim.selected_build_tower = .EMPTY
								app.sim.selected_card_idx    = -1
								play_sound(.CLICK, .UI)
							}
						}
					}
				}
			}
		}
	}
	
	// Right click to deselect or cancel
	if raylib.IsMouseButtonPressed(.RIGHT) {
		if app.sim.selected_build_tower != .EMPTY {
			app.sim.selected_build_tower = .EMPTY
			app.sim.selected_card_idx    = -1
		} else {
			entities.app_deselect_tower(app)
			app.selected_obstacle.valid = false
		}
	}
	
	// Keyboard shortcuts
	if raylib.IsKeyPressed(.ESCAPE) {
		simulation_set_pause(app, true)
		entities.app_set_state(app, .PAUSED)
	}
	
	if raylib.IsKeyPressed(.SPACE) {
		simulation_toggle_pause(app)
	}
	
	// Number keys for speed
	if raylib.IsKeyPressed(.ONE) {
		simulation_set_speed(app, 1.0)
	}
	if raylib.IsKeyPressed(.TWO) {
		simulation_set_speed(app, 2.0)
	}
}

// Paused input
input_handle_paused :: proc(app: ^entities.App_State) {
	// SPACE resumes the game
	if raylib.IsKeyPressed(.SPACE) {
		simulation_set_pause(app, false)
		entities.app_set_state(app, .PLAYING)
	}

	// ESCAPE goes back to main menu
	if raylib.IsKeyPressed(.ESCAPE) {
		simulation_set_pause(app, false)
		entities.app_set_state(app, .MENU)
	}

	// Right click to cancel selected build tower
	if raylib.IsMouseButtonPressed(.RIGHT) {
		if app.sim.selected_build_tower != .EMPTY {
			app.sim.selected_build_tower = .EMPTY
		} else {
			entities.app_deselect_tower(app)
			app.selected_obstacle.valid = false
		}
	}
}

// Editor input
input_handle_editor :: proc(app: ^entities.App_State) {
	// Shortcuts de teclado (siempre activos, sin importar posición del mouse)
	input_process_editor_shortcuts(app)

	// Reset paint flag whenever the left button is released, regardless of mouse position
	if raylib.IsMouseButtonReleased(.LEFT) {
		app.editor.is_painting = false
	}

	// Cuando el browser está abierto: manejar scroll/ESC y bloquear el resto del input
	if app.editor.show_map_browser {
		if raylib.IsKeyPressed(.ESCAPE) {
			app.editor.show_map_browser = false
		}
		wheel := raylib.GetMouseWheelMove()
		if wheel != 0 {
			app.editor.map_browser_scroll -= i32(wheel)
			if app.editor.map_browser_scroll < 0 {
				app.editor.map_browser_scroll = 0
			}
			max_scroll := i32(len(app.editor.map_browser_files)) - 8
			if max_scroll < 0 { max_scroll = 0 }
			if app.editor.map_browser_scroll > max_scroll {
				app.editor.map_browser_scroll = max_scroll
			}
		}
		return
	}

	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	// Convert to grid coordinates using helper function
	grid_x, grid_y := screen_to_grid(app, mouse_x, mouse_y)
	
	app.mouse_x = grid_x
	app.mouse_y = grid_y
	
	// Update selected cell for reticle display
	if is_valid_grid_pos(app, grid_x, grid_y) {
		app.selected_cell.row = grid_y
		app.selected_cell.col = grid_x
		app.selected_cell.valid = true
	} else {
		app.selected_cell.valid = false
	}
	
	// Bottom toolbars (build tools and menus)
	if mouse_y > raylib.GetScreenHeight() - 70 {
		return
	}
	
	// Check if valid grid position
	if !is_valid_grid_pos(app, grid_x, grid_y) {
		return
	}
	
	// Left click to place or erase (continuous with IsMouseButtonDown)
	if raylib.IsMouseButtonDown(.LEFT) {
		// Push undo snapshot only at the start of each paint stroke
		if !app.editor.is_painting {
			editor_push_undo(app)
			app.editor.is_painting = true
		}

		tool := app.editor.current_tool

		switch tool {
		case .EMPTY:
			// Erase
			editor_erase_cell(app, grid_y, grid_x)
		case .PATH, .SPAWN, .GOAL:
			// Place path elements
			app.editor.game_map.grid[grid_y][grid_x] = tool
		case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER, .TOWER_ICE, .TOWER_ENHANCE:
			// Place tower (only on empty cells)
			if app.editor.game_map.grid[grid_y][grid_x] == .EMPTY {
				app.editor.game_map.grid[grid_y][grid_x] = tool
			}
		case .OBSTACLE:
			// Place obstacle (in obstacle layer)
			app.editor.game_map.obstacle_grid[grid_y][grid_x] = .OBSTACLE
		case .ACCESSORY_TREE, .ACCESSORY_BLOCK:
			// Place accessories
			if app.editor.game_map.grid[grid_y][grid_x] == .EMPTY {
				app.editor.game_map.grid[grid_y][grid_x] = tool
			}
		}
	}

	// Right click to erase
	if raylib.IsMouseButtonPressed(.RIGHT) {
		editor_push_undo(app)
		editor_erase_cell(app, grid_y, grid_x)
	}
	
	// Keyboard shortcuts
	if raylib.IsKeyPressed(.ESCAPE) {
		entities.app_set_state(app, .MENU)
	}
	
	// Tool selection hotkeys
	if raylib.IsKeyPressed(.ONE) {
		app.editor.current_tool = .EMPTY
	}
	if raylib.IsKeyPressed(.TWO) {
		app.editor.current_tool = .PATH
	}
	if raylib.IsKeyPressed(.THREE) {
		app.editor.current_tool = .SPAWN
	}
	if raylib.IsKeyPressed(.FOUR) {
		app.editor.current_tool = .GOAL
	}
	if raylib.IsKeyPressed(.FIVE) {
		app.editor.current_tool = .TOWER_ARCHER
	}
	if raylib.IsKeyPressed(.SIX) {
		app.editor.current_tool = .TOWER_CANNON
	}
	if raylib.IsKeyPressed(.SEVEN) {
		app.editor.current_tool = .TOWER_SNIPER
	}
	if raylib.IsKeyPressed(.EIGHT) {
		app.editor.current_tool = .TOWER_MISSILE
	}
	if raylib.IsKeyPressed(.NINE) {
		app.editor.current_tool = .TOWER_LASER
	}
	if raylib.IsKeyPressed(.ZERO) {
		app.editor.current_tool = .OBSTACLE
	}
	
	// Grid toggle
	if raylib.IsKeyPressed(.G) {
		app.editor.show_grid = !app.editor.show_grid
		app.settings.show_grid = app.editor.show_grid
	}
}



// Editor erase cell
editor_erase_cell :: proc(app: ^entities.App_State, row, col: i32) {
	if row < 0 || row >= constants.GRID_SIZE || col < 0 || col >= constants.GRID_SIZE {
		return
	}
	
	// Remove from main grid
	app.editor.game_map.grid[row][col] = .EMPTY
	
	// Also remove from obstacle grid
	app.editor.game_map.obstacle_grid[row][col] = .EMPTY
	
	// Remove tile data — also free the cloned key string
	if existing_key, ok := entities.map_get_existing_key(&app.editor.game_map, row, col); ok {
		delete_key(&app.editor.game_map.tile_data, existing_key)
		delete(existing_key)
	}
}

// Game over input
input_handle_game_over :: proc(app: ^entities.App_State) {
	// Handled by render_button in rendering.odin
}

// Helper to check if grid position is valid (uses actual map dimensions)
is_valid_grid_pos :: proc(app: ^entities.App_State, x, y: i32) -> bool {
	return x >= 0 && x < app.editor.game_map.width && y >= 0 && y < app.editor.game_map.height
}

// Convert screen coordinates to grid coordinates (accounts for camera offset and zoom)
screen_to_grid :: proc(app: ^entities.App_State, screen_x, screen_y: i32) -> (grid_x, grid_y: i32) {
	cs := f32(app.settings.cell_size) * app.zoom
	grid_x = i32((f32(screen_x) - f32(app.camera_offset_x)) / cs)
	grid_y = i32((f32(screen_y) - f32(app.camera_offset_y)) / cs)
	return
}

// Select tower at position
select_tower_at :: proc(app: ^entities.App_State, row, col: i32) {
	for &tower in app.sim.towers {
		if tower.r == row && tower.c == col {
			entities.app_select_tower(app, row, col)
			return
		}
	}
	entities.app_deselect_tower(app)
}

// Get hovered cell info
input_get_hovered_cell :: proc(app: ^entities.App_State) -> (row, col: i32, valid: bool) {
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	// Convert to grid coordinates using helper function
	col, row = screen_to_grid(app, mouse_x, mouse_y)
	
	valid = is_valid_grid_pos(app, col, row)
	return
}

// Process editor shortcuts
input_process_editor_shortcuts :: proc(app: ^entities.App_State) {
	ctrl := raylib.IsKeyDown(.LEFT_CONTROL) || raylib.IsKeyDown(.RIGHT_CONTROL)
	shift := raylib.IsKeyDown(.LEFT_SHIFT) || raylib.IsKeyDown(.RIGHT_SHIFT)

	// Undo (Ctrl+Z)
	if ctrl && raylib.IsKeyPressed(.Z) && !shift {
		editor_undo(app)
	}

	// Redo (Ctrl+Y  or  Ctrl+Shift+Z)
	if ctrl && (raylib.IsKeyPressed(.Y) || (shift && raylib.IsKeyPressed(.Z))) {
		editor_redo(app)
	}

	// Limpiar mapa (Ctrl+C)
	if ctrl && raylib.IsKeyPressed(.C) {
		editor_push_undo(app)
		entities.map_clear(&app.editor.game_map)
		entities.add_toast(app, "Map cleared", .INFO, 2.0)
	}

	// Guardar mapa (Ctrl+S) → guarda como last_saved.map
	if ctrl && raylib.IsKeyPressed(.S) {
		if entities.map_save(&app.editor.game_map, "last_saved.map") {
			entities.add_toast(app, "Map saved! (Ctrl+S)", .SUCCESS, 2.0)
		} else {
			entities.add_toast(app, "Failed to save map", .ERROR, 3.0)
		}
	}

	// Cargar mapa (Ctrl+O) → carga last_saved.map
	if ctrl && raylib.IsKeyPressed(.O) {
		editor_push_undo(app)
		if entities.map_load(&app.editor.game_map, "last_saved.map") {
			app.editor.current_biome = app.editor.game_map.biome
			entities.add_toast(app, "Map loaded! (Ctrl+O)", .SUCCESS, 2.0)
		} else {
			// Roll back the undo push since nothing changed
			if len(app.editor.undo_stack) > 0 {
				last := len(app.editor.undo_stack) - 1
				snap := app.editor.undo_stack[last]
				ordered_remove(&app.editor.undo_stack, last)
				entities.map_snapshot_destroy(&snap)
			}
			entities.add_toast(app, "No quick save found", .WARNING, 3.0)
		}
	}

	// Abrir/cerrar browser de mapas (Ctrl+B)
	if ctrl && raylib.IsKeyPressed(.B) {
		if app.editor.show_map_browser {
			app.editor.show_map_browser = false
		} else {
			for f in app.editor.map_browser_files {
				delete(f)
			}
			delete(app.editor.map_browser_files)
			app.editor.map_browser_files = entities.map_list_saved()
			app.editor.map_browser_scroll = 0
			app.editor.show_map_browser = true
		}
	}
}

// ─── Undo / Redo ─────────────────────────────────────────────────────────────

// Push the current map state onto the undo stack and clear the redo stack.
// Call this BEFORE making any change to the map (once per logical operation).
editor_push_undo :: proc(app: ^entities.App_State) {
	snap := entities.map_snapshot_save(&app.editor.game_map)
	append(&app.editor.undo_stack, snap)

	// Enforce history limit: drop the oldest entry
	if len(app.editor.undo_stack) > constants.EDITOR_MAX_HISTORY {
		entities.map_snapshot_destroy(&app.editor.undo_stack[0])
		ordered_remove(&app.editor.undo_stack, 0)
	}

	// Any new action invalidates the redo history
	for &s in app.editor.redo_stack {
		entities.map_snapshot_destroy(&s)
	}
	clear(&app.editor.redo_stack)
}

// Undo: restore the previous state.
editor_undo :: proc(app: ^entities.App_State) {
	if len(app.editor.undo_stack) == 0 {
		entities.add_toast(app, "Nothing to undo", .WARNING, 1.5)
		return
	}
	// Push current state onto redo stack before restoring
	redo_snap := entities.map_snapshot_save(&app.editor.game_map)
	append(&app.editor.redo_stack, redo_snap)

	// Pop from undo stack
	last := len(app.editor.undo_stack) - 1
	snap := app.editor.undo_stack[last]
	ordered_remove(&app.editor.undo_stack, last)

	entities.map_snapshot_restore(&app.editor.game_map, &snap)
	entities.map_snapshot_destroy(&snap)
	app.editor.current_biome = app.editor.game_map.biome
	entities.add_toast(app, "Undo", .INFO, 0.8)
	play_sound(.TICK, .UI)
}

// Redo: reapply the next state.
editor_redo :: proc(app: ^entities.App_State) {
	if len(app.editor.redo_stack) == 0 {
		entities.add_toast(app, "Nothing to redo", .WARNING, 1.5)
		return
	}
	// Push current state onto undo stack before restoring
	undo_snap := entities.map_snapshot_save(&app.editor.game_map)
	append(&app.editor.undo_stack, undo_snap)

	// Pop from redo stack
	last := len(app.editor.redo_stack) - 1
	snap := app.editor.redo_stack[last]
	ordered_remove(&app.editor.redo_stack, last)

	entities.map_snapshot_restore(&app.editor.game_map, &snap)
	entities.map_snapshot_destroy(&snap)
	app.editor.current_biome = app.editor.game_map.biome
	entities.add_toast(app, "Redo", .INFO, 0.8)
	play_sound(.TICK, .UI)
}

// ─────────────────────────────────────────────────────────────────────────────

// Convert tile type to tower type
tile_to_tower_type :: proc(tile: constants.Tile) -> constants.Tower_Type {
	#partial switch tile {
	case .TOWER_ARCHER:
		return .ARCHER
	case .TOWER_CANNON:
		return .CANNON
	case .TOWER_SNIPER:
		return .SNIPER
	case .TOWER_MISSILE:
		return .MISSILE
	case .TOWER_LASER:
		return .LASER
	case .TOWER_ICE:
		return .ICE
	case .TOWER_ENHANCE:
		return .ENHANCE
	case:
		return .ARCHER  // Default
	}
}

// Handle camera controls (zoom and pan)
input_handle_camera :: proc(app: ^entities.App_State) {
	// Zoom with mouse wheel (centered on mouse, continuous smooth zoom)
	wheel_movement := raylib.GetMouseWheelMove()
	if wheel_movement != 0 {
		mouse_x := raylib.GetMouseX()
		mouse_y := raylib.GetMouseY()

		// Use the current (interpolated) zoom and the current camera offset so that
		// the anchor cell is computed in the world that is actually being rendered.
		// This avoids the mismatch between app.zoom and app.target_zoom during animation.
		cs_cur := f32(app.settings.cell_size) * app.zoom

		// World position under mouse (fractional grid coordinates)
		world_x := (f32(mouse_x) - f32(app.camera_offset_x)) / cs_cur
		world_y := (f32(mouse_y) - f32(app.camera_offset_y)) / cs_cur

		// Update target zoom
		app.target_zoom += wheel_movement * constants.ZOOM_SPEED
		if app.target_zoom < constants.ZOOM_MIN { app.target_zoom = constants.ZOOM_MIN }
		if app.target_zoom > constants.ZOOM_MAX { app.target_zoom = constants.ZOOM_MAX }

		// Compute new camera offset so the same world position stays under the mouse
		cs_new := f32(app.settings.cell_size) * app.target_zoom
		app.target_camera_offset_x = i32(f32(mouse_x) - world_x * cs_new)
		app.target_camera_offset_y = i32(f32(mouse_y) - world_y * cs_new)
	}
	
	// Pan with middle mouse button
	if raylib.IsMouseButtonDown(.MIDDLE) {
		mouse_delta := raylib.GetMouseDelta()
		app.camera_offset_x += i32(mouse_delta.x)
		app.camera_offset_y += i32(mouse_delta.y)
		// Also update target offsets so they stay in sync during panning
		app.target_camera_offset_x = app.camera_offset_x
		app.target_camera_offset_y = app.camera_offset_y
	}
}
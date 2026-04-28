package systems

import "vendor:raylib"
import "../entities"
import "../constants"
import "core:fmt"

// Handle all input
input_handle :: proc(app: ^entities.App_State) {
	// Handle camera controls (global)
	input_handle_camera(app)
	
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
			entities.app_set_state(app, .MENU)
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
	if is_valid_grid_pos(grid_x, grid_y) {
		app.selected_cell.row = grid_y
		app.selected_cell.col = grid_x
		app.selected_cell.valid = true
	} else {
		app.selected_cell.valid = false
	}
	
	// Left click to place tower
	if raylib.IsMouseButtonPressed(.LEFT) {
		// Don't process grid clicks if mouse is over tower control panel
		if is_mouse_over_tower_panel(app) {
			return
		}
		
		if is_valid_grid_pos(grid_x, grid_y) {
			// Check if clicking on a tower
			tile := app.editor.game_map.grid[grid_y][grid_x]
			_ = tile  // Use tile to avoid unused variable warning
			
			#partial switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
				// Select tower for upgrade
				select_tower_at(app, grid_y, grid_x)
			case .EMPTY:
				// Close tower panel if clicking on empty terrain
				app.selected_tower = nil
				
				// Place selected tower if one is selected
				if app.sim.selected_build_tower != .EMPTY {
					// Get tower spec for cost
					tower_type := tile_to_tower_type(app.sim.selected_build_tower)
					spec := constants.TOWER_SPECS[tower_type]
					
					if app.sim.money >= spec.cost {
						// Place the tower
						app.editor.game_map.grid[grid_y][grid_x] = app.sim.selected_build_tower
						app.sim.money -= spec.cost
						
						// Create tower entity
						tower := entities.tower_init(tower_type, grid_y, grid_x)
						append(&app.sim.towers, tower)
						
						// Deselect after placing
						app.sim.selected_build_tower = .EMPTY
					}
				}
			}
		}
	}
	
	// Right click to deselect or cancel
	if raylib.IsMouseButtonPressed(.RIGHT) {
		app.selected_tower = nil
	}
	
	// Keyboard shortcuts
	if raylib.IsKeyPressed(.ESCAPE) {
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
	if raylib.IsKeyPressed(.ESCAPE) || raylib.IsKeyPressed(.SPACE) {
		// State change handled by caller
	}
}

// Editor input
input_handle_editor :: proc(app: ^entities.App_State) {
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	// Convert to grid coordinates using helper function
	grid_x, grid_y := screen_to_grid(app, mouse_x, mouse_y)
	
	app.mouse_x = grid_x
	app.mouse_y = grid_y
	
	// Update selected cell for reticle display
	if is_valid_grid_pos(grid_x, grid_y) {
		app.selected_cell.row = grid_y
		app.selected_cell.col = grid_x
		app.selected_cell.valid = true
	} else {
		app.selected_cell.valid = false
	}
	
	// Sidebar toolbar click detection
	button_width := i32(80)
	button_height := i32(30)
	margin := i32(5)
	toolbar_width := button_width + margin * 2
	toolbar_height := i32(12) * (button_height + margin) + margin * 2
	toolbar_x := i32(20)
	toolbar_y := (raylib.GetScreenHeight() - toolbar_height) / 2
	
	// Check if clicked on sidebar toolbar
	if mouse_x >= toolbar_x && mouse_x <= toolbar_x + toolbar_width &&
	   mouse_y >= toolbar_y && mouse_y <= toolbar_y + toolbar_height {
		if raylib.IsMouseButtonPressed(.LEFT) {
			input_handle_toolbar_click(app, mouse_x, mouse_y, toolbar_x, toolbar_y, button_width, button_height, margin)
		}
		return
	}
	
	// Bottom toolbar
	if mouse_y > raylib.GetScreenHeight() - constants.UI_TOOLBAR_HEIGHT {
		// Clicked on bottom toolbar
		return
	}
	
	// Check if valid grid position
	if !is_valid_grid_pos(grid_x, grid_y) {
		return
	}
	
	// Left click to place or erase (continuous with IsMouseButtonDown)
	if raylib.IsMouseButtonDown(.LEFT) {
		tool := app.editor.current_tool
		
		switch tool {
		case .EMPTY:
			// Erase
			editor_erase_cell(app, grid_y, grid_x)
		case .PATH, .SPAWN, .GOAL:
			// Place path elements
			app.editor.game_map.grid[grid_y][grid_x] = tool
		case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
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

// Handle toolbar click
input_handle_toolbar_click :: proc(app: ^entities.App_State, mouse_x, mouse_y, toolbar_x, toolbar_y, button_width, button_height, margin: i32) {
	tools := []constants.Tile{
		.EMPTY,
		.PATH,
		.SPAWN,
		.GOAL,
		.TOWER_ARCHER,
		.TOWER_CANNON,
		.TOWER_SNIPER,
		.TOWER_MISSILE,
		.TOWER_LASER,
		.OBSTACLE,
		.ACCESSORY_TREE,
		.ACCESSORY_BLOCK,
	}
	
	for i in 0..<len(tools) {
		button_x := toolbar_x + margin
		button_y := toolbar_y + margin + i32(i) * (button_height + margin)
		
		// Check if clicked on this button
		if mouse_x >= button_x && mouse_x <= button_x + button_width &&
		   mouse_y >= button_y && mouse_y <= button_y + button_height {
			app.editor.current_tool = tools[i]
			return
		}
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
	
	// Remove tile data
	key := entities.map_get_tile_key(row, col)
	delete_key(&app.editor.game_map.tile_data, key)
}

// Game over input
input_handle_game_over :: proc(app: ^entities.App_State) {
	// Handled by render_button in rendering.odin
}

// Helper to check if grid position is valid
is_valid_grid_pos :: proc(x, y: i32) -> bool {
	return x >= 0 && x < constants.GRID_SIZE && y >= 0 && y < constants.GRID_SIZE
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
			app.selected_tower = &tower
			return
		}
	}
	app.selected_tower = nil
}

// Get hovered cell info
input_get_hovered_cell :: proc(app: ^entities.App_State) -> (row, col: i32, valid: bool) {
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	// Convert to grid coordinates using helper function
	col, row = screen_to_grid(app, mouse_x, mouse_y)
	
	valid = is_valid_grid_pos(col, row)
	return
}

// Process editor shortcuts
input_process_editor_shortcuts :: proc(app: ^entities.App_State) {
	// Clear map
	if raylib.IsKeyDown(.LEFT_CONTROL) && raylib.IsKeyPressed(.C) {
		entities.map_clear(&app.editor.game_map)
	}
	
	// Save map (placeholder)
	if raylib.IsKeyDown(.LEFT_CONTROL) && raylib.IsKeyPressed(.S) {
		// TODO: Implement save
	}
	
	// Load map (placeholder)
	if raylib.IsKeyDown(.LEFT_CONTROL) && raylib.IsKeyPressed(.O) {
		// TODO: Implement load
	}
}

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
		
		// Get grid cell under mouse before zoom using screen_to_grid
		grid_col, grid_row := screen_to_grid(app, mouse_x, mouse_y)
		
		// Calculate exact position within the cell (fractional part)
		cs_old := f32(app.settings.cell_size) * app.zoom
		cell_offset_x := (f32(mouse_x) - f32(app.camera_offset_x)) / cs_old - f32(grid_col)
		cell_offset_y := (f32(mouse_y) - f32(app.camera_offset_y)) / cs_old - f32(grid_row)
		
		// Update target zoom with continuous value
		app.target_zoom += wheel_movement * constants.ZOOM_SPEED
		
		// Clamp target zoom
		if app.target_zoom < constants.ZOOM_MIN {
			app.target_zoom = constants.ZOOM_MIN
		}
		if app.target_zoom > constants.ZOOM_MAX {
			app.target_zoom = constants.ZOOM_MAX
		}
		
		// Calculate new cell size with target zoom
		cs_new := f32(app.settings.cell_size) * app.target_zoom
		
		// Calculate target camera offset to keep the same grid cell + offset under mouse
		// mouse = offset + (grid + cell_offset) * cs_new
		// offset = mouse - (grid + cell_offset) * cs_new
		app.target_camera_offset_x = i32(f32(mouse_x) - (f32(grid_col) + cell_offset_x) * cs_new)
		app.target_camera_offset_y = i32(f32(mouse_y) - (f32(grid_row) + cell_offset_y) * cs_new)
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

package systems

import "vendor:raylib"
import "../constants"
import "../game"
import "../entities"

// Handle all input
input_handle :: proc() {
	switch game.app.state {
	case .MENU:
		input_handle_menu()
	case .PLAYING:
		input_handle_playing()
	case .PAUSED:
		input_handle_paused()
	case .EDITOR:
		input_handle_editor()
	case .GAME_OVER:
		input_handle_game_over()
	}
}

// Menu input
input_handle_menu :: proc() {
	// Handled by render_button in rendering.odin
}

// Playing input
input_handle_playing :: proc() {
	// Mouse position for grid selection
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	cs := f32(game.app.settings.cell_size)
	
	// Convert to grid coordinates
	grid_x := i32((f32(mouse_x) - f32(game.app.camera_offset_x)) / cs)
	grid_y := i32((f32(mouse_y) - f32(game.app.camera_offset_y)) / cs)
	
	game.app.mouse_x = grid_x
	game.app.mouse_y = grid_y
	
	// Left click to place tower
	if raylib.IsMouseButtonPressed(.LEFT) {
		if is_valid_grid_pos(grid_x, grid_y) {
			// Check if clicking on a tower
			tile := game.app.editor.map.grid[grid_y][grid_x]
			
			switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
				// Select tower for upgrade
				select_tower_at(grid_y, grid_x)
			case .EMPTY:
				// Open build menu or use default tower
				// For now, do nothing (would open a build menu)
			}
		}
	}
	
	// Right click to deselect or cancel
	if raylib.IsMouseButtonPressed(.RIGHT) {
		game.app.selected_tower = nil
	}
	
	// Keyboard shortcuts
	if raylib.IsKeyPressed(.ESCAPE) {
		game.app_set_state(.PAUSED)
	}
	
	if raylib.IsKeyPressed(.SPACE) {
		simulation_toggle_pause()
	}
	
	// Number keys for speed
	if raylib.IsKeyPressed(.ONE) {
		simulation_set_speed(1.0)
	}
	if raylib.IsKeyPressed(.TWO) {
		simulation_set_speed(2.0)
	}
}

// Paused input
input_handle_paused :: proc() {
	if raylib.IsKeyPressed(.ESCAPE) || raylib.IsKeyPressed(.SPACE) {
		game.app_set_state(.PLAYING)
	}
}

// Editor input
input_handle_editor :: proc() {
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	cs := f32(game.app.settings.cell_size)
	
	// Convert to grid coordinates
	grid_x := i32((f32(mouse_x) - f32(game.app.camera_offset_x)) / cs)
	grid_y := i32((f32(mouse_y) - f32(game.app.camera_offset_y)) / cs)
	
	game.app.mouse_x = grid_x
	game.app.mouse_y = grid_y
	
	// Toolbar click detection
	if mouse_y < 60 {
		// Clicked on top toolbar
		input_handle_toolbar_click(mouse_x)
		return
	}
	
	// Bottom toolbar
	if mouse_y > raylib.GetScreenHeight() - 60 {
		// Clicked on bottom toolbar
		return
	}
	
	// Check if valid grid position
	if !is_valid_grid_pos(grid_x, grid_y) {
		return
	}
	
	// Left click to place or erase
	if raylib.IsMouseButtonDown(.LEFT) {
		tool := game.app.editor.current_tool
		
		switch tool {
		case .EMPTY:
			// Erase
			editor_erase_cell(grid_y, grid_x)
		case .PATH, .SPAWN, .GOAL:
			// Place path elements
			game.app.editor.map.grid[grid_y][grid_x] = tool
		case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
			// Place tower (only on empty cells)
			if game.app.editor.map.grid[grid_y][grid_x] == .EMPTY {
				game.app.editor.map.grid[grid_y][grid_x] = tool
			}
		case .OBSTACLE:
			// Place obstacle (in obstacle layer)
			game.app.editor.map.obstacle_grid[grid_y][grid_x] = .OBSTACLE
		case .ACCESSORY_TREE, .ACCESSORY_BLOCK:
			// Place accessories
			if game.app.editor.map.grid[grid_y][grid_x] == .EMPTY {
				game.app.editor.map.grid[grid_y][grid_x] = tool
			}
		}
	}
	
	// Right click to erase
	if raylib.IsMouseButtonDown(.RIGHT) {
		editor_erase_cell(grid_y, grid_x)
	}
	
	// Keyboard shortcuts
	if raylib.IsKeyPressed(.ESCAPE) {
		game.app_set_state(.MENU)
	}
	
	// Tool selection hotkeys
	if raylib.IsKeyPressed(.ONE) {
		game.app.editor.current_tool = .EMPTY
	}
	if raylib.IsKeyPressed(.TWO) {
		game.app.editor.current_tool = .PATH
	}
	if raylib.IsKeyPressed(.THREE) {
		game.app.editor.current_tool = .SPAWN
	}
	if raylib.IsKeyPressed(.FOUR) {
		game.app.editor.current_tool = .GOAL
	}
	if raylib.IsKeyPressed(.FIVE) {
		game.app.editor.current_tool = .TOWER_ARCHER
	}
	if raylib.IsKeyPressed(.SIX) {
		game.app.editor.current_tool = .TOWER_CANNON
	}
	if raylib.IsKeyPressed(.SEVEN) {
		game.app.editor.current_tool = .TOWER_SNIPER
	}
	if raylib.IsKeyPressed(.EIGHT) {
		game.app.editor.current_tool = .TOWER_MISSILE
	}
	if raylib.IsKeyPressed(.NINE) {
		game.app.editor.current_tool = .TOWER_LASER
	}
	if raylib.IsKeyPressed(.ZERO) {
		game.app.editor.current_tool = .OBSTACLE
	}
	
	// Grid toggle
	if raylib.IsKeyPressed(.G) {
		game.app.editor.show_grid = !game.app.editor.show_grid
		game.app.settings.show_grid = game.app.editor.show_grid
	}
}

// Handle toolbar click
input_handle_toolbar_click :: proc(mouse_x: i32) {
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
	
	button_width := 80
	margin := 10
	
	for i in 0..<len(tools) {
		x_start := margin + i * (button_width + margin)
		x_end := x_start + button_width
		
		if mouse_x >= i32(x_start) && mouse_x <= i32(x_end) {
			game.app.editor.current_tool = tools[i]
			return
		}
	}
}

// Editor erase cell
editor_erase_cell :: proc(row, col: i32) {
	if row < 0 || row >= constants.GRID_SIZE || col < 0 || col >= constants.GRID_SIZE {
		return
	}
	
	// Remove from main grid
	tile := game.app.editor.map.grid[row][col]
	game.app.editor.map.grid[row][col] = .EMPTY
	
	// Also remove from obstacle grid
	game.app.editor.map.obstacle_grid[row][col] = .EMPTY
	
	// Remove tile data
	key := entities.map_get_tile_key(row, col)
	delete_key(&game.app.editor.map.tile_data, key)
}

// Game over input
input_handle_game_over :: proc() {
	// Handled by render_button in rendering.odin
}

// Helper to check if grid position is valid
is_valid_grid_pos :: proc(x, y: i32) -> bool {
	return x >= 0 && x < constants.GRID_SIZE && y >= 0 && y < constants.GRID_SIZE
}

// Select tower at position
select_tower_at :: proc(row, col: i32) {
	for &tower in game.app.sim.towers {
		if tower.r == row && tower.c == col {
			game.app.selected_tower = &tower
			return
		}
	}
	game.app.selected_tower = nil
}

// Get hovered cell info
input_get_hovered_cell :: proc() -> (row, col: i32, valid: bool) {
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	cs := f32(game.app.settings.cell_size)
	
	col = i32((f32(mouse_x) - f32(game.app.camera_offset_x)) / cs)
	row = i32((f32(mouse_y) - f32(game.app.camera_offset_y)) / cs)
	
	valid = is_valid_grid_pos(col, row)
	return
}

// Process editor shortcuts
input_process_editor_shortcuts :: proc() {
	// Clear map
	if raylib.IsKeyDown(.LEFT_CONTROL) && raylib.IsKeyPressed(.C) {
		entities.map_clear(&game.app.editor.map)
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

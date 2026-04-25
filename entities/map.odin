package entities

import "core:fmt"
import "../constants"

// Map/Grid structure
Map :: struct {
	// Main grid (towers, paths, spawn, goal)
	grid: [constants.GRID_SIZE][constants.GRID_SIZE]constants.Tile,
	
	// Obstacle grid (spikes, separate layer)
	obstacle_grid: [constants.GRID_SIZE][constants.GRID_SIZE]constants.Tile,
	
	// Biome
	biome: constants.Biome,
	
	// Seed for random generation
	seed: i32,
	
	// Tile data (for obstacle levels, etc.)
	tile_data: map[string]Tile_Data,
}

// Tile data for extra properties
tile_data :: struct {
	level: i32,
}

// Initialize map
map_init :: proc() -> Map {
	m := Map{
		biome = .PLAIN,
		seed = 0,
		tile_data = make(map[string]Tile_Data),
	}
	
	// Initialize grids to EMPTY
	for row in 0..<constants.GRID_SIZE {
		for col in 0..<constants.GRID_SIZE {
			m.grid[row][col] = .EMPTY
			m.obstacle_grid[row][col] = .EMPTY
		}
	}
	
	return m
}

// Destroy map and free resources
map_destroy :: proc(m: ^Map) {
	delete(m.tile_data)
}

// Get tile at position
map_get_tile :: proc(m: ^Map, row, col: i32) -> constants.Tile {
	if row < 0 || row >= constants.GRID_SIZE || col < 0 || col >= constants.GRID_SIZE {
		return .EMPTY
	}
	return m.grid[row][col]
}

// Set tile at position
map_set_tile :: proc(m: ^Map, row, col: i32, tile: constants.Tile) {
	if row < 0 || row >= constants.GRID_SIZE || col < 0 || col >= constants.GRID_SIZE {
		return
	}
	m.grid[row][col] = tile
}

// Get obstacle at position
map_get_obstacle :: proc(m: ^Map, row, col: i32) -> constants.Tile {
	if row < 0 || row >= constants.GRID_SIZE || col < 0 || col >= constants.GRID_SIZE {
		return .EMPTY
	}
	return m.obstacle_grid[row][col]
}

// Set obstacle at position
map_set_obstacle :: proc(m: ^Map, row, col: i32, tile: constants.Tile) {
	if row < 0 || row >= constants.GRID_SIZE || col < 0 || col >= constants.GRID_SIZE {
		return
	}
	m.obstacle_grid[row][col] = tile
}

// Get tile data key
map_get_tile_key :: proc(row, col: i32) -> string {
	return fmt.tprintf("%d,%d", row, col)
}

// Get obstacle level
map_get_obstacle_level :: proc(m: ^Map, row, col: i32) -> i32 {
	key := map_get_tile_key(row, col)
	if data, ok := m.tile_data[key]; ok {
		return data.level
	}
	return 1
}

// Set obstacle level
map_set_obstacle_level :: proc(m: ^Map, row, col: i32, level: i32) {
	key := map_get_tile_key(row, col)
	m.tile_data[key] = tile_data{level = level}
}

// Clear map (set all to EMPTY)
map_clear :: proc(m: ^Map) {
	for row in 0..<constants.GRID_SIZE {
		for col in 0..<constants.GRID_SIZE {
			m.grid[row][col] = .EMPTY
			m.obstacle_grid[row][col] = .EMPTY
		}
	}
	delete(m.tile_data)
	m.tile_data = make(map[string]Tile_Data)
}

// Check if tile is a path tile
map_is_path :: proc(m: ^Map, row, col: i32) -> bool {
	tile := map_get_tile(m, row, col)
	return tile == .PATH || tile == .SPAWN || tile == .GOAL
}

// Check if position has a tower
map_has_tower :: proc(m: ^Map, row, col: i32) -> bool {
	tile := map_get_tile(m, row, col)
	switch tile {
	case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
		return true
	}
	return false
}

// Find all spawn points
map_find_spawns :: proc(m: ^Map) -> [dynamic]Spawn_Point {
	spawns := make([dynamic]Spawn_Point)
	
	for row in 0..<constants.GRID_SIZE {
		for col in 0..<constants.GRID_SIZE {
			if m.grid[row][col] == .SPAWN {
				append(&spawns, Spawn_Point{r = row, c = col})
			}
		}
	}
	
	return spawns
}

// Find goal point
map_find_goal :: proc(m: ^Map) -> (i32, i32, bool) {
	for row in 0..<constants.GRID_SIZE {
		for col in 0..<constants.GRID_SIZE {
			if m.grid[row][col] == .GOAL {
				return row, col, true
			}
		}
	}
	return 0, 0, false
}

// Spawn point structure
Spawn_Point :: struct {
	r: i32,
	c: i32,
	path: [dynamic]Path_Node,
	enemies_to_spawn: i32,
	enemies_spawned: i32,
	wave_time: f32,
	next_spawn_delay: f32,
}

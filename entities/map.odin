package entities

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
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
	tile_data: map[string]constants.Tile_Data,
	
	// Grid dimensions (can be smaller than GRID_SIZE for smaller maps)
	width: i32,
	height: i32,
}

// Initialize map with optional grid dimensions
map_init :: proc(width: i32 = constants.GRID_SIZE, height: i32 = constants.GRID_SIZE) -> Map {
	m := Map{
		biome = constants.Biome.PLAIN,
		seed = 0,
		tile_data = make(map[string]constants.Tile_Data),
		width = width,
		height = height,
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
	if existing_key, ok := map_get_existing_key(m, row, col); ok {
		// Entry already exists: update value in place, reuse the stored key.
		// Do NOT delete the key — it is still referenced by the map.
		m.tile_data[existing_key] = constants.Tile_Data{level = level}
	} else {
		// No entry yet: clone the key so it outlives the temp allocator.
		key := strings.clone(map_get_tile_key(row, col))
		m.tile_data[key] = constants.Tile_Data{level = level}
	}
}

// Helper: returns the existing heap-allocated key for (row,col) if present.
map_get_existing_key :: proc(m: ^Map, row, col: i32) -> (key: string, found: bool) {
	temp_key := map_get_tile_key(row, col)
	for k in m.tile_data {
		if k == temp_key {
			return k, true
		}
	}
	return "", false
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
	m.tile_data = make(map[string]constants.Tile_Data)
}

// Check if tile is a path tile
// Find all spawn points
map_find_spawns :: proc(m: ^Map) -> [dynamic]Spawn_Point {
	spawns := make([dynamic]Spawn_Point)

	for row in 0..<m.height {
		for col in 0..<m.width {
			if m.grid[row][col] == .SPAWN {
				append(&spawns, Spawn_Point{r = i32(row), c = i32(col)})
			}
		}
	}

	return spawns
}

// Find goal point
map_find_goal :: proc(m: ^Map) -> (i32, i32, bool) {
	for row in 0..<m.height {
		for col in 0..<m.width {
			if m.grid[row][col] == .GOAL {
				return i32(row), i32(col), true
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

// BFS node for pathfinding
BFS_Node :: struct {
	r: i32,
	c: i32,
	parent_r: i32,
	parent_c: i32,
	has_parent: bool,
}

// Find path from start to goal using BFS
// Returns a dynamic array of Path_Node from start to goal (inclusive)
map_find_path_bfs :: proc(m: ^Map, start_r, start_c, goal_r, goal_c: i32, is_flying: bool) -> [dynamic]Path_Node {
	path := make([dynamic]Path_Node)
	
	// Check if start or goal is out of bounds (use actual map dimensions)
	if start_r < 0 || start_r >= m.height || start_c < 0 || start_c >= m.width {
		return path
	}
	if goal_r < 0 || goal_r >= m.height || goal_c < 0 || goal_c >= m.width {
		return path
	}
	
	// If start is goal, return just the start
	if start_r == goal_r && start_c == goal_c {
		append(&path, Path_Node{x = start_c, y = start_r})
		return path
	}
	
	// Directions: up, down, left, right
	dr := [4]i32{-1, 1, 0, 0}
	dc := [4]i32{0, 0, -1, 1}
	
	// Visited grid
	visited: [constants.GRID_SIZE][constants.GRID_SIZE]bool
	
	// Queue for BFS (using slice as queue)
	queue := make([dynamic]BFS_Node)
	defer delete(queue)
	
	// Parent tracking grid to reconstruct path (-1 means no parent)
	parent_r: [constants.GRID_SIZE][constants.GRID_SIZE]i32
	parent_c: [constants.GRID_SIZE][constants.GRID_SIZE]i32
	for i in 0..<constants.GRID_SIZE {
		for j in 0..<constants.GRID_SIZE {
			parent_r[i][j] = -1
			parent_c[i][j] = -1
		}
	}
	
	// Start node
	start_node := BFS_Node{r = start_r, c = start_c, parent_r = -1, parent_c = -1, has_parent = false}
	append(&queue, start_node)
	visited[start_r][start_c] = true
	
	// BFS
	found := false
	
	for len(queue) > 0 && !found {
		// Dequeue
		current := queue[0]
		ordered_remove(&queue, 0)
		
		// Check all neighbors
		for i in 0..<4 {
			nr := current.r + dr[i]
			nc := current.c + dc[i]
			
			// Check bounds (use actual map dimensions)
			if nr < 0 || nr >= m.height || nc < 0 || nc >= m.width {
				continue
			}
			
			// Skip if visited
			if visited[nr][nc] {
				continue
			}
			
			// Check if walkable
			tile := m.grid[nr][nc]
			is_walkable := false
			
			if is_flying {
				// Flying enemies can go over everything except map boundaries
				is_walkable = true
			} else {
				// Ground enemies can ONLY walk on: PATH, SPAWN, GOAL
				// Cannot walk on: EMPTY (grass), TOWER_*, OBSTACLE
				#partial switch tile {
				case .PATH, .SPAWN, .GOAL:
					is_walkable = true
				}
			}
			
			if !is_walkable {
				continue
			}
			
				// Mark as visited and store parent
			visited[nr][nc] = true
			parent_r[nr][nc] = current.r
			parent_c[nr][nc] = current.c
			
			// Check if we reached the goal
			if nr == goal_r && nc == goal_c {
				found = true
				break
			}
			
			// Enqueue for further exploration
			new_node := BFS_Node{r = nr, c = nc, parent_r = current.r, parent_c = current.c, has_parent = true}
			append(&queue, new_node)
		}
	}
	
	if !found {
		// No path found, return empty path
		return path
	}
	
	// Reconstruct path from goal to start using parent pointers
	// Build path from goal back to start, then reverse
	reverse_path := make([dynamic]Path_Node)
	defer delete(reverse_path)
	
	cr := goal_r
	cc := goal_c
	max_iterations := constants.GRID_SIZE * constants.GRID_SIZE
	iterations := 0
	
	for iterations < max_iterations {
		iterations += 1
		append(&reverse_path, Path_Node{x = cc, y = cr})
		// Stop when we reach the start
		if cr == start_r && cc == start_c {
			break
		}
		next_r := parent_r[cr][cc]
		next_c := parent_c[cr][cc]
		// Safety check: if parent is invalid, we've reached the start or an error occurred
		if next_r < 0 || next_c < 0 {
			break
		}
		cr = next_r
		cc = next_c
	}
	
	// Reverse the path (start -> goal)
	for i := len(reverse_path) - 1; i >= 0; i -= 1 {
		append(&path, reverse_path[i])
	}
	
	return path
}

// Save map to file
map_save :: proc(m: ^Map, filename: string) -> bool {
	// Create maps directory if it doesn't exist
	os.make_directory("maps")
	
	// Build file content using strings.Builder
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)
	
	// Header: FIRST_IMPACT_MAP
	// Data: version, width, height, biome, seed
	fmt.sbprint(&builder, "FIRST_IMPACT_MAP\n")
	fmt.sbprintf(&builder, "1\n")  // version
	fmt.sbprintf(&builder, "%d\n", m.width)  // width
	fmt.sbprintf(&builder, "%d\n", m.height)  // height
	fmt.sbprintf(&builder, "%d\n", m.biome)
	fmt.sbprintf(&builder, "%d\n", m.seed)
	
	// Write main grid (only up to width x height)
	for row in 0..<m.height {
		for col in 0..<m.width {
			fmt.sbprintf(&builder, "%d", m.grid[row][col])
			if col < m.width - 1 {
				strings.write_byte(&builder, ' ')
			}
		}
		strings.write_byte(&builder, '\n')
	}
	
	// Write obstacle grid (only up to width x height)
	for row in 0..<m.height {
		for col in 0..<m.width {
			fmt.sbprintf(&builder, "%d", m.obstacle_grid[row][col])
			if col < m.width - 1 {
				strings.write_byte(&builder, ' ')
			}
		}
		strings.write_byte(&builder, '\n')
	}
	
	// Write to file
	full_path := fmt.tprintf("maps/%s", filename)
	content := strings.to_string(builder)
	result := os.write_entire_file(full_path, transmute([]u8)content)
	
	return result
}

// Helper to parse integer from string
parse_i32 :: proc(s: string) -> i32 {
	val, ok := strconv.parse_int(s)
	if !ok {
		return 0
	}
	return i32(val)
}

// List all saved map files in the maps/ directory
map_list_saved :: proc() -> [dynamic]string {
	files := make([dynamic]string)

	fd, err := os.open("maps")
	if err != os.ERROR_NONE {
		return files
	}
	defer os.close(fd)

	fis, read_err := os.read_dir(fd, -1)
	if read_err != os.ERROR_NONE {
		return files
	}
	defer os.file_info_slice_delete(fis)

	for fi in fis {
		if !fi.is_dir && strings.has_suffix(fi.name, ".map") {
			append(&files, strings.clone(fi.name))
		}
	}

	return files
}

// ─── Snapshot (undo/redo) ────────────────────────────────────────────────────

// Full copy of a Map's state, used for undo/redo history.
Map_Snapshot :: struct {
	grid:          [constants.GRID_SIZE][constants.GRID_SIZE]constants.Tile,
	obstacle_grid: [constants.GRID_SIZE][constants.GRID_SIZE]constants.Tile,
	tile_data:     map[string]constants.Tile_Data,
	biome:         constants.Biome,
	width:         i32,
	height:        i32,
}

// Take a full snapshot of the current map state (deep copy).
map_snapshot_save :: proc(m: ^Map) -> Map_Snapshot {
	snap := Map_Snapshot{
		grid          = m.grid,
		obstacle_grid = m.obstacle_grid,
		biome         = m.biome,
		width         = m.width,
		height        = m.height,
		tile_data     = make(map[string]constants.Tile_Data),
	}
	for k, v in m.tile_data {
		snap.tile_data[strings.clone(k)] = v
	}
	return snap
}

// Restore map state from a snapshot (deep copy back into map).
map_snapshot_restore :: proc(m: ^Map, snap: ^Map_Snapshot) {
	m.grid          = snap.grid
	m.obstacle_grid = snap.obstacle_grid
	m.biome         = snap.biome
	m.width         = snap.width
	m.height        = snap.height
	delete(m.tile_data)
	m.tile_data = make(map[string]constants.Tile_Data)
	for k, v in snap.tile_data {
		m.tile_data[strings.clone(k)] = v
	}
}

// Free memory owned by a snapshot.
map_snapshot_destroy :: proc(snap: ^Map_Snapshot) {
	for k in snap.tile_data {
		delete(k)
	}
	delete(snap.tile_data)
}

// ─── File I/O ────────────────────────────────────────────────────────────────

// Load map from file
map_load :: proc(m: ^Map, filename: string) -> bool {
	full_path := fmt.tprintf("maps/%s", filename)
	data, ok := os.read_entire_file(full_path)
	if !ok {
		return false
	}
	defer delete(data)
	
	// Parse file content
	content := string(data)
	lines := strings.split_lines(content)
	defer delete(lines)
	
	if len(lines) < 6 {
		return false
	}
	
	// Check header
	header := strings.trim_space(lines[0])
	if header != "FIRST_IMPACT_MAP" {
		return false
	}
	
	// Format: version, width, height, biome, seed
	version := parse_i32(strings.trim_space(lines[1]))
	_ = version  // For future version handling
	
	// Read grid dimensions from file
	m.width = parse_i32(strings.trim_space(lines[2]))
	m.height = parse_i32(strings.trim_space(lines[3]))
	
	// Validate dimensions (must not exceed GRID_SIZE)
	if m.width > constants.GRID_SIZE || m.height > constants.GRID_SIZE ||
	   m.width <= 0 || m.height <= 0 {
		return false
	}
	
	biome_val := parse_i32(strings.trim_space(lines[4]))
	m.biome = constants.Biome(biome_val)
	m.seed = parse_i32(strings.trim_space(lines[5]))
	grid_start_idx := 6
	
	// Parse main grid (only up to width x height)
	for row in 0..<m.height {
		line_idx := grid_start_idx + int(row)
		if line_idx >= len(lines) {
			return false
		}
		
		parts := strings.split(strings.trim_space(lines[line_idx]), " ")
		defer delete(parts)
		
		for col in 0..<m.width {
			if i32(col) >= i32(len(parts)) {
				break
			}
			tile_val := parse_i32(parts[col])
			m.grid[row][col] = constants.Tile(tile_val)
		}
	}
	
	// Parse obstacle grid
	obstacle_start := grid_start_idx + int(m.height)
	for row in 0..<m.height {
		line_idx := obstacle_start + int(row)
		if line_idx >= len(lines) {
			return false
		}
		
		parts := strings.split(strings.trim_space(lines[line_idx]), " ")
		defer delete(parts)
		
		for col in 0..<m.width {
			if i32(col) >= i32(len(parts)) {
				break
			}
			tile_val := parse_i32(parts[col])
			m.obstacle_grid[row][col] = constants.Tile(tile_val)
		}
	}
	
	return true
}
package entities

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:time"
import raylib "vendor:raylib"
import "../constants"

// Map/Grid structure
Map :: struct {
	// Main grid (towers, paths, spawn, goal)
	grid: [constants.GRID_SIZE][constants.GRID_SIZE]constants.Tile,

	// Obstacle grid (spikes, separate layer)
	obstacle_grid: [constants.GRID_SIZE][constants.GRID_SIZE]constants.Tile,

	// Water layer — separate from main grid; rendered below paths
	water_grid: [constants.GRID_SIZE][constants.GRID_SIZE]bool,

	// Heightmap — valores en [0, 1] por celda, derivados de seed.
	// Solo se usa para el render del terreno (desniveles sutiles). No afecta gameplay.
	// Se regenera con map_regenerate_heightmap cuando cambia el seed.
	heightmap: [constants.GRID_SIZE][constants.GRID_SIZE]f32,

	// GPU heightmap — textura grayscale del heightmap, muestreada con bilinear
	// filtering por el shader para producir el gradient continuo.
	// dirty=true → necesita re-upload; valid=true → tex tiene datos GPU.
	heightmap_tex:       raylib.Texture2D,
	heightmap_tex_valid: bool,
	heightmap_tex_dirty: bool,

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

	// Heightmap inicial — depende del seed (que arranca en 0).
	map_regenerate_heightmap(&m)

	return m
}

// ─────────────────────────────────────────────────────────────────────────────
// Heightmap: noise procedural determinista por seed.
// Solo afecta el render del terreno (desniveles sutiles), no el gameplay.
// ─────────────────────────────────────────────────────────────────────────────

// Hash entero → f32 en [0, 1]. Determinista. Usado por value_noise.
_heightmap_hash2 :: proc(x, y: i32, seed: u64) -> f32 {
	h := u64(u32(x)) * 374761393 + u64(u32(y)) * 668265263 + seed
	h = (h ~ (h >> 13)) * 1274126177
	h = h ~ (h >> 16)
	return f32(h & 0x00FFFFFF) / f32(0x00FFFFFF)
}

// Value noise bilineal con suavizado smoothstep. Devuelve f32 en [0, 1].
_heightmap_value_noise :: proc(x, y: f32, seed: u64) -> f32 {
	xi := i32(math.floor(x))
	yi := i32(math.floor(y))
	xf := x - f32(xi)
	yf := y - f32(yi)
	// Smoothstep: 3t² − 2t³
	sx := xf * xf * (3 - 2 * xf)
	sy := yf * yf * (3 - 2 * yf)
	n00 := _heightmap_hash2(xi,     yi,     seed)
	n10 := _heightmap_hash2(xi + 1, yi,     seed)
	n01 := _heightmap_hash2(xi,     yi + 1, seed)
	n11 := _heightmap_hash2(xi + 1, yi + 1, seed)
	nx0 := n00 * (1 - sx) + n10 * sx
	nx1 := n01 * (1 - sx) + n11 * sx
	return nx0 * (1 - sy) + nx1 * sy
}

// Multi-octava fractal noise. Devuelve f32 en [0, 1].
_heightmap_fractal_noise :: proc(x, y: f32, seed: u64, octaves: int) -> f32 {
	total      := f32(0)
	amplitude  := f32(1)
	frequency  := f32(1)
	max_amp    := f32(0)
	for _ in 0 ..< octaves {
		total     += _heightmap_value_noise(x * frequency, y * frequency, seed) * amplitude
		max_amp   += amplitude
		amplitude *= 0.5
		frequency *= 2.0
	}
	return total / max_amp
}

// Regenera el heightmap entero a partir del seed actual del mapa.
// Llamar después de map_init, map_load, o cualquier mutación del seed.
// Marca la textura GPU como dirty para que el render la re-suba en el próximo frame.
map_regenerate_heightmap :: proc(m: ^Map) {
	seed_u64 := u64(u32(m.seed)) | (u64(u32(m.seed) ~ 0xA5A5A5A5) << 32)
	for row in 0 ..< constants.GRID_SIZE {
		for col in 0 ..< constants.GRID_SIZE {
			fx := f32(col) * constants.HEIGHTMAP_FREQUENCY
			fy := f32(row) * constants.HEIGHTMAP_FREQUENCY
			m.heightmap[row][col] = _heightmap_fractal_noise(fx, fy, seed_u64, constants.HEIGHTMAP_OCTAVES)
		}
	}
	m.heightmap_tex_dirty = true
}

// Sube el heightmap CPU al GPU como una textura grayscale GRID_SIZE×GRID_SIZE.
// El filtro bilinear hace que el shader vea valores interpolados entre celdas.
// Requiere un contexto OpenGL activo — sólo llamar desde el hilo de render.
// Resetea dirty=false; deja valid=true si tuvo éxito.
map_upload_heightmap_to_gpu :: proc(m: ^Map) {
	// Si ya había una textura cargada, descargar antes de re-subir.
	if m.heightmap_tex_valid {
		raylib.UnloadTexture(m.heightmap_tex)
		m.heightmap_tex_valid = false
	}

	// Cuantizar f32 → u8 para una textura grayscale.
	pixels: [constants.GRID_SIZE * constants.GRID_SIZE]u8
	for row in 0 ..< constants.GRID_SIZE {
		for col in 0 ..< constants.GRID_SIZE {
			v := m.heightmap[row][col]
			if v < 0 { v = 0 }
			if v > 1 { v = 1 }
			pixels[row * constants.GRID_SIZE + col] = u8(v * 255)
		}
	}

	img := raylib.Image{
		data    = raw_data(pixels[:]),
		width   = constants.GRID_SIZE,
		height  = constants.GRID_SIZE,
		mipmaps = 1,
		format  = .UNCOMPRESSED_GRAYSCALE,
	}
	tex := raylib.LoadTextureFromImage(img)
	// id == 0 → fallo al subir (típicamente sin contexto GL). Marcar inválido.
	if tex.id == 0 {
		m.heightmap_tex_valid = false
		m.heightmap_tex_dirty = true  // volver a intentar al próximo frame
		return
	}
	raylib.SetTextureFilter(tex, .BILINEAR)
	raylib.SetTextureWrap(tex, .CLAMP)

	m.heightmap_tex       = tex
	m.heightmap_tex_valid = true
	m.heightmap_tex_dirty = false
}

// Libera la textura GPU del heightmap (si la había).
map_unload_heightmap_gpu :: proc(m: ^Map) {
	if m.heightmap_tex_valid {
		raylib.UnloadTexture(m.heightmap_tex)
		m.heightmap_tex_valid = false
	}
}

// Destroy map and free resources
map_destroy :: proc(m: ^Map) {
	// Las keys de tile_data se clonaron al heap; hay que liberarlas antes del map.
	for k in m.tile_data {
		delete(k)
	}
	delete(m.tile_data)
	// Liberar la textura GPU del heightmap si fue subida.
	map_unload_heightmap_gpu(m)
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
			m.water_grid[row][col] = false
		}
	}
	// Liberar keys clonadas antes de tirar el map
	for k in m.tile_data {
		delete(k)
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

// Save map to file (delega en map_save_bin — siempre escribe binario).
// El parser de texto legacy se mantiene en map_load para abrir archivos viejos.
map_save :: proc(m: ^Map, filename: string) -> bool {
	return map_save_bin(m, filename)
}

// Mantenido como referencia/debugging. Si necesitás exportar a texto, llamá a
// `_map_save_text_legacy` explícitamente.
_map_save_text_legacy :: proc(m: ^Map, filename: string) -> bool {
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

	// Write water grid (1 = water, 0 = empty)
	for row in 0..<m.height {
		for col in 0..<m.width {
			fmt.sbprintf(&builder, "%d", 1 if m.water_grid[row][col] else 0)
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

// Entry for the split-panel map viewer (name + formatted modification date).
Map_File_Entry :: struct {
	name:     string,
	mod_date: string, // "YYYY-MM-DD"
}

// List map files with modification dates for the map viewer.
map_list_saved_entries :: proc() -> [dynamic]Map_File_Entry {
	entries := make([dynamic]Map_File_Entry)

	fd, err := os.open("maps")
	if err != os.ERROR_NONE { return entries }
	defer os.close(fd)

	fis, read_err := os.read_dir(fd, -1)
	if read_err != os.ERROR_NONE { return entries }
	defer os.file_info_slice_delete(fis)

	for fi in fis {
		if !fi.is_dir && strings.has_suffix(fi.name, ".map") {
			year, month, day := time.date(fi.modification_time)
			date_str := fmt.tprintf("%04d-%02d-%02d", year, int(month), day)
			append(&entries, Map_File_Entry{
				name     = strings.clone(fi.name),
				mod_date = strings.clone(date_str),
			})
		}
	}

	return entries
}

// Renombra un archivo de mapa en el directorio maps/.
// Devuelve true si el rename fue exitoso.
map_rename :: proc(old_name, new_name: string) -> bool {
	old_path := fmt.tprintf("maps/%s", old_name)
	new_path := fmt.tprintf("maps/%s", new_name)
	return os.rename(old_path, new_path) == os.ERROR_NONE
}

// Free all memory owned by a map_browser_entries slice.
map_file_entries_destroy :: proc(entries: ^[dynamic]Map_File_Entry) {
	for e in entries^ {
		delete(e.name)
		delete(e.mod_date)
	}
	delete(entries^)
}

// Devuelve true si la celda es una esquina o unión del camino.
// Esquina  = exactamente 2 vecinos de camino que NO son opuestos (arriba+derecha, etc.).
// Unión    = 3 o más vecinos de camino.
// Usado para bloquear la colocación de obstáculos en esas celdas.
map_is_path_corner_or_junction :: proc(m: ^Map, row, col: i32) -> bool {
	is_path_like :: proc(m: ^Map, r, c: i32) -> bool {
		if r < 0 || r >= constants.GRID_SIZE || c < 0 || c >= constants.GRID_SIZE { return false }
		t := m.grid[r][c]
		return t == .PATH || t == .SPAWN || t == .GOAL
	}
	// Solo aplica a celdas que forman parte del camino
	if !is_path_like(m, row, col) { return false }

	top    := is_path_like(m, row - 1, col)
	right  := is_path_like(m, row,     col + 1)
	bottom := is_path_like(m, row + 1, col)
	left   := is_path_like(m, row,     col - 1)

	count := (1 if top else 0) + (1 if right else 0) +
	         (1 if bottom else 0) + (1 if left else 0)

	if count >= 3 { return true } // unión

	if count == 2 {
		// Recto (arriba+abajo o izq+der) → NO es esquina
		straight := (top && bottom) || (left && right)
		return !straight
	}

	return false
}

// ─── Snapshot (undo/redo) ────────────────────────────────────────────────────

// Full copy of a Map's state, used for undo/redo history.
Map_Snapshot :: struct {
	grid:          [constants.GRID_SIZE][constants.GRID_SIZE]constants.Tile,
	obstacle_grid: [constants.GRID_SIZE][constants.GRID_SIZE]constants.Tile,
	water_grid:    [constants.GRID_SIZE][constants.GRID_SIZE]bool,
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
		water_grid    = m.water_grid,
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
	m.water_grid    = snap.water_grid
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

// ─────────────────────────────────────────────────────────────────────────────
// Map binary file format (.map binario, replaces .map texto).
// El loader detecta el formato leyendo los primeros 4 bytes:
//   "TDMB" → binario (Map_Bin_File)
//   "FIRS" → texto legacy (FIRST_IMPACT_MAP)
// Los saves nuevos siempre escriben binario.
//
// tile_data (un map[string]Tile_Data en memoria) se serializa como una grilla
// fija [GRID_SIZE][GRID_SIZE]i32 donde 0 = sin nivel. Esto evita strings de
// longitud variable en el archivo y mantiene todo fixed-size para
// mem.ptr_to_bytes directo.
// ─────────────────────────────────────────────────────────────────────────────

MAP_BIN_VERSION :: u32(1)
MAP_BIN_MAGIC   := [4]u8{'T', 'D', 'M', 'B'}

Map_Bin_File :: struct {
	magic:    [4]u8,
	version:  u32,
	width:    i32,
	height:   i32,
	biome:    i32,
	seed:     i32,
	_pad:     [16]u8,

	grid:          [constants.GRID_SIZE][constants.GRID_SIZE]constants.Tile,
	obstacle_grid: [constants.GRID_SIZE][constants.GRID_SIZE]constants.Tile,
	water_grid:    [constants.GRID_SIZE][constants.GRID_SIZE]bool,
	// tile_levels[r][c] = nivel; 0 = sin entry (default = 1 en runtime).
	tile_levels:   [constants.GRID_SIZE][constants.GRID_SIZE]i32,

	_trailing_pad: [64]u8,
}

// Guarda el mapa en formato binario. Reemplaza el texto previamente usado.
map_save_bin :: proc(m: ^Map, filename: string) -> bool {
	os.make_directory("maps")
	full_path := fmt.tprintf("maps/%s", filename)

	file := Map_Bin_File{
		magic   = MAP_BIN_MAGIC,
		version = MAP_BIN_VERSION,
		width   = m.width,
		height  = m.height,
		biome   = i32(m.biome),
		seed    = m.seed,
	}
	file.grid          = m.grid
	file.obstacle_grid = m.obstacle_grid
	file.water_grid    = m.water_grid

	// Codificar tile_data en la grilla fija.
	for k, v in m.tile_data {
		row, col, ok := _parse_tile_data_key(k)
		if !ok { continue }
		if row >= 0 && row < constants.GRID_SIZE && col >= 0 && col < constants.GRID_SIZE {
			file.tile_levels[row][col] = v.level
		}
	}

	data := mem.ptr_to_bytes(&file)
	return os.write_entire_file(full_path, data)
}

// Carga un mapa binario. Devuelve false si el archivo está corrupto.
map_load_bin :: proc(m: ^Map, data: []u8) -> bool {
	if len(data) != size_of(Map_Bin_File) { return false }
	file := (cast(^Map_Bin_File)raw_data(data))^
	if file.magic != MAP_BIN_MAGIC { return false }
	if file.version != MAP_BIN_VERSION { return false }
	if file.width  <= 0 || file.width  > constants.GRID_SIZE { return false }
	if file.height <= 0 || file.height > constants.GRID_SIZE { return false }

	// Limpiar estado previo del mapa.
	for k in m.tile_data { delete(k) }
	clear(&m.tile_data)
	m.grid          = file.grid
	m.obstacle_grid = file.obstacle_grid
	m.water_grid    = file.water_grid
	m.width         = file.width
	m.height        = file.height
	m.biome         = constants.Biome(file.biome)
	m.seed          = file.seed

	// Reconstruir tile_data desde la grilla.
	for r in 0 ..< constants.GRID_SIZE {
		for c in 0 ..< constants.GRID_SIZE {
			lvl := file.tile_levels[r][c]
			if lvl == 0 { continue }
			key := strings.clone(fmt.tprintf("%d,%d", r, c))
			m.tile_data[key] = constants.Tile_Data{level = lvl}
		}
	}

	// Heightmap derivado del seed cargado.
	map_regenerate_heightmap(m)
	return true
}

// Parsea una key "r,c" devuelta por map_get_tile_key. ok=false si malformada.
_parse_tile_data_key :: proc(k: string) -> (row, col: i32, ok: bool) {
	comma_idx := strings.index_byte(k, ',')
	if comma_idx <= 0 || comma_idx >= len(k) - 1 { return 0, 0, false }
	row_val, r_ok := strconv.parse_int(k[:comma_idx])
	col_val, c_ok := strconv.parse_int(k[comma_idx + 1:])
	if !r_ok || !c_ok { return 0, 0, false }
	return i32(row_val), i32(col_val), true
}

// Load map from file
map_load :: proc(m: ^Map, filename: string) -> bool {
	full_path := fmt.tprintf("maps/%s", filename)
	data, ok := os.read_entire_file(full_path)
	if !ok {
		return false
	}
	defer delete(data)

	// Detección de formato: los primeros 4 bytes distinguen binario (TDMB) de
	// texto legacy (FIRS de "FIRST_IMPACT_MAP").
	if len(data) >= 4 &&
	   data[0] == 'T' && data[1] == 'D' && data[2] == 'M' && data[3] == 'B' {
		return map_load_bin(m, data)
	}
	// Continúa al parser de texto legacy abajo.
	
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
	
	// Liberar tile_data anterior antes de cargar el nuevo mapa (sino quedan
	// niveles de obstáculos residuales del mapa previo y leak de keys clonadas).
	for k in m.tile_data {
		delete(k)
	}
	clear(&m.tile_data)

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

	// Limpiar los tres grids antes de cargar: evita datos residuales del mapa
	// anterior cuando los mapas tienen distinto tamaño o agua en distintas celdas.
	m.grid          = {}
	m.obstacle_grid = {}
	m.water_grid    = {}

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

	// Parse water grid (optional — older maps without it default to all false)
	water_start := obstacle_start + int(m.height)
	if water_start + int(m.height) <= len(lines) {
		for row in 0..<m.height {
			line_idx := water_start + int(row)
			parts := strings.split(strings.trim_space(lines[line_idx]), " ")
			defer delete(parts)
			for col in 0..<m.width {
				if i32(col) >= i32(len(parts)) { break }
				m.water_grid[row][col] = parse_i32(parts[col]) != 0
			}
		}
	}

	// Regenerar heightmap del terreno desde el seed cargado.
	map_regenerate_heightmap(m)

	return true
}
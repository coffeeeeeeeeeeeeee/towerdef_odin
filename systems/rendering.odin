package systems

import "core:math"
import "core:fmt"
import "core:strings"
import "vendor:raylib"
import "../entities"
import "../constants"

// Render the entire game
render_game :: proc(app: ^entities.App_State) {
	render_map(app)
	render_gameplay(app)
	render_ui(app)
}

// Render map (grid, paths, obstacles)
render_map :: proc(app: ^entities.App_State) {
	m := &app.editor.game_map
	cs := f32(app.settings.cell_size) * app.zoom
	gs := constants.GRID_SIZE
	
	// Background
	biome_colors := constants.BIOME_COLORS[m.biome]
	raylib.ClearBackground(biome_colors.bg)
	
	// Fill grid background
	total_size := f32(gs) * cs
	raylib.DrawRectangle(
		i32(app.camera_offset_x),
		i32(app.camera_offset_y),
		i32(total_size),
		i32(total_size),
		biome_colors.bg_grid,
	)
	
	// Draw paths
	render_paths(m, cs, i32(gs), app.camera_offset_x, app.camera_offset_y)
	
	// Draw gameplay tiles (towers, accessories)
	for row in 0..<gs {
		for col in 0..<gs {
			tile := m.grid[row][col]
			x := f32(col) * cs + f32(app.camera_offset_x)
			y := f32(row) * cs + f32(app.camera_offset_y)
			
			#partial switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
				// In game mode, find tower entity
				if app.state == .PLAYING || app.state == .PAUSED {
					for &tower in app.sim.towers {
						if tower.r == i32(row) && tower.c == i32(col) {
							render_tower(app, &tower, x, y, cs)
							break
						}
					}
				} else {
					// In editor, render tower directly from tile type
					tower_type := tile_to_tower_type(tile)
					draw_tower_tile(x, y, cs, tower_type, 0, false)
				}
				
			case .SPAWN:
				render_spawn(x, y, cs)
				
			case .GOAL:
				render_goal(x, y, cs)
				
			case .ACCESSORY_TREE:
				render_tree(x, y, cs, app.editor.game_map.biome, i32(row), i32(col))
				
			case .ACCESSORY_BLOCK:
				render_block(x, y, cs)
			}
		}
	}
	
	// Draw obstacles
	render_obstacles(m, cs, i32(gs), app.camera_offset_x, app.camera_offset_y)
	
	// Draw laser beams (on top of everything)
	if app.state == .PLAYING || (app.state == .PAUSED && app.previous_state == .PLAYING) {
		render_laser_beams(app, cs)
	}
	
	// Grid lines
	if app.settings.show_grid {
		render_grid_lines(app, cs, i32(gs))
	}
	
	// Draw reticle for selected cell (in editor and simulation modes)
	if app.selected_cell.valid && app.state == .EDITOR {
		sx := f32(app.selected_cell.col) * cs + f32(app.camera_offset_x)
		sy := f32(app.selected_cell.row) * cs + f32(app.camera_offset_y)
		render_reticle(sx, sy, cs, constants.TOWER_RETICLE_COLOR)
		
		// Draw tower ghost if a tower type is selected for building
		if app.sim.selected_build_tower != .EMPTY {
			// Convert tile to tower type
			tower_type := tile_to_tower_type(app.sim.selected_build_tower)
			draw_tower_tile(sx, sy, cs, tower_type, 0, true) // is_ghost = true
		}
	}
	
	// Draw reticle for selected tower in PLAYING/PAUSED modes
	if app.selected_tower != nil && (app.state == .PLAYING || app.state == .PAUSED) {
		sx := f32(app.selected_tower.c) * cs + f32(app.camera_offset_x)
		sy := f32(app.selected_tower.r) * cs + f32(app.camera_offset_y)
		render_reticle(sx, sy, cs, constants.TOWER_RETICLE_COLOR)
	}
	
	// Draw tower ghost in PLAYING/PAUSED modes when building
	if app.selected_cell.valid && (app.state == .PLAYING || app.state == .PAUSED) {
		if app.sim.selected_build_tower != .EMPTY {
			sx := f32(app.selected_cell.col) * cs + f32(app.camera_offset_x)
			sy := f32(app.selected_cell.row) * cs + f32(app.camera_offset_y)
			tower_type := tile_to_tower_type(app.sim.selected_build_tower)
			draw_tower_tile(sx, sy, cs, tower_type, 0, true) // is_ghost = true
		}
	}
}

// Render paths
render_paths :: proc(m: ^entities.Map, cs: f32, gs: i32, camera_offset_x, camera_offset_y: i32) {
	path_width := cs * constants.PATH_WIDTH_RATIO
	path_color := constants.BIOME_COLORS[m.biome].path
	
	is_path_like :: proc(m: ^entities.Map, row, col: i32) -> bool {
		if row < 0 || row >= constants.GRID_SIZE || col < 0 || col >= constants.GRID_SIZE {
			return false
		}
		tile := m.grid[row][col]
		return tile == .PATH || tile == .SPAWN || tile == .GOAL
	}
	
	for row in 0..<gs {
		for col in 0..<gs {
			tile := m.grid[row][col]
			if tile != .PATH && tile != .SPAWN && tile != .GOAL {
				continue
			}
			
			x := f32(col) * cs + f32(camera_offset_x)
			y := f32(row) * cs + f32(camera_offset_y)
			cx := x + cs / 2
			cy := y + cs / 2
			
			top := is_path_like(m, row - 1, col)
			right := is_path_like(m, row, col + 1)
			bottom := is_path_like(m, row + 1, col)
			left := is_path_like(m, row, col - 1)
			
			// Draw connections
			if top {
				raylib.DrawRectangle(
					i32(cx - path_width / 2),
					i32(y),
					i32(path_width),
					i32(cs / 2),
					path_color,
				)
			}
			if right {
				raylib.DrawRectangle(
					i32(cx),
					i32(cy - path_width / 2),
					i32(cs / 2),
					i32(path_width),
					path_color,
				)
			}
			if bottom {
				raylib.DrawRectangle(
					i32(cx - path_width / 2),
					i32(cy),
					i32(path_width),
					i32(cs / 2),
					path_color,
				)
			}
			if left {
				raylib.DrawRectangle(
					i32(x),
					i32(cy - path_width / 2),
					i32(cs / 2),
					i32(path_width),
					path_color,
				)
			}
			
			// Center circle
			is_spawn_or_goal := tile == .SPAWN || tile == .GOAL
			circle_radius := path_width / 2
			if is_spawn_or_goal {
				circle_radius = cs / 2
			}
			
			raylib.DrawCircle(
				i32(cx),
				i32(cy),
				circle_radius,
				path_color,
			)
		}
	}
}

// Render grid lines
render_grid_lines :: proc(app: ^entities.App_State, cs: f32, gs: i32) {
	for i in 0..=gs {
		x := i32(f32(i) * cs) + app.camera_offset_x
		y := i32(f32(i) * cs) + app.camera_offset_y
		
		// Vertical
		raylib.DrawLine(x, app.camera_offset_y, x, app.camera_offset_y + i32(f32(gs) * cs), constants.COLOR_GRID_LINE)
		
		// Horizontal
		raylib.DrawLine(app.camera_offset_x, y, app.camera_offset_x + i32(f32(gs) * cs), y, constants.COLOR_GRID_LINE)
	}
}

// Render tower upgrades (small dots) - arranged in rows of 5 above the tower
render_tower_upgrades :: proc(tower: ^entities.Tower, x, y, cs: f32) {
	dot_radius := cs * 0.08
	dot_spacing := cs * 0.20  // Horizontal spacing between dots (increased)
	row_spacing := cs * 0.18  // Vertical spacing between rows (increased)
	pips_per_row := 5
	
	// Calculate total number of pips
	total_pips := (tower.damage_level - 1) + (tower.rate_level - 1) + (tower.critical_level - 1)
	if total_pips <= 0 {
		return
	}
	
	// Start position - centered above the tower
	row_width := f32(pips_per_row) * dot_spacing
	start_x := x + cs / 2 - row_width / 2
	start_y := y - cs * 0.15  // Slightly above the tower
	
	pip_index := 0
	
	// Damage upgrades (red pips) - first
	for i in 0..<tower.damage_level - 1 {
		row := pip_index / pips_per_row
		col := pip_index % pips_per_row
		dot_x := start_x + f32(col) * dot_spacing
		dot_y := start_y - f32(row) * row_spacing
		raylib.DrawCircle(i32(dot_x), i32(dot_y), dot_radius, raylib.RED)
		pip_index += 1
	}
	
	// Rate upgrades (yellow pips) - second
	for i in 0..<tower.rate_level - 1 {
		row := pip_index / pips_per_row
		col := pip_index % pips_per_row
		dot_x := start_x + f32(col) * dot_spacing
		dot_y := start_y - f32(row) * row_spacing
		raylib.DrawCircle(i32(dot_x), i32(dot_y), dot_radius, raylib.YELLOW)
		pip_index += 1
	}
	
	// Critical upgrades (blue pips) - third
	for i in 0..<tower.critical_level - 1 {
		row := pip_index / pips_per_row
		col := pip_index % pips_per_row
		dot_x := start_x + f32(col) * dot_spacing
		dot_y := start_y - f32(row) * row_spacing
		raylib.DrawCircle(i32(dot_x), i32(dot_y), dot_radius, raylib.BLUE)
		pip_index += 1
	}
}

// Render spawn point
render_spawn :: proc(x, y, cs: f32) {
	// Draw spawn circle
	center_x := x + cs / 2
	center_y := y + cs / 2
	
	raylib.DrawCircle(i32(center_x), i32(center_y), cs * 0.4, constants.COLOR_SPAWN)
}

// Render goal
render_goal :: proc(x, y, cs: f32) {
	center_x := x + cs / 2
	center_y := y + cs / 2
	
	raylib.DrawCircle(i32(center_x), i32(center_y), cs * 0.4, constants.COLOR_GOAL)
}

// Simple hash function for pseudo-random numbers based on position
hash_position :: proc(row, col: i32) -> u32 {
	// FNV-1a inspired hash
	h: u32 = 2166136261
	h = (h ~ u32(row)) * 16777619
	h = (h ~ u32(col)) * 16777619
	return h
}

// Get random float between 0 and 1 from hash
hash_random :: proc(row, col: i32, offset: i32 = 0) -> f32 {
	h := hash_position(row + offset, col + offset * 31)
	return f32(h % 10000) / 10000.0
}

// Render tree accessory
render_tree :: proc(x, y: f32, cs: f32, biome: constants.Biome, row: i32 = 0, col: i32 = 0) {
	center_x := x + cs / 2
	center_y := y + cs / 2
	
	switch biome {
	case .PLAIN:
		// Round tree (plain) - top view: large green circle with slight variation
		seed := hash_position(row, col)
		size_var := f32(seed % 20) / 100.0  // 0.0 to 0.19 variation
		leaf_radius := cs * (0.30 + size_var)
		
		// Slight position offset for natural look
		offset_x := (f32(seed % 10) - 5.0) * cs * 0.02
		offset_y := (f32((seed / 10) % 10) - 5.0) * cs * 0.02
		
		// Leaves (large green circle)
		raylib.DrawCircle(i32(center_x + offset_x), i32(center_y + offset_y), f32(leaf_radius), constants.COLOR_TREE_LEAVES)
		
	case .FOREST:
		// Pine tree (forest) - hexagonal layers with rotation
		seed := hash_position(row, col)
		tree_colors := constants.BIOME_TREE_COLORS[.FOREST]
		
		// Base size variation per tree
		base_size := 0.32 + (f32(seed % 15) / 100.0)  // 0.32 to 0.46
		
		// Position jitter - each tree is slightly offset
		jitter_x := (f32(seed % 7) - 3.0) * cs * 0.015
		jitter_y := (f32((seed / 7) % 7) - 3.0) * cs * 0.015
		cx := center_x + jitter_x
		cy := center_y + jitter_y
		
		// Base rotation for this tree (varies by seed)
		base_rotation := f32(seed % 60)  // 0 to 59 degrees
		
		// Draw pine as concentric hexagons (layers of needles)
		layers := 4 + int(seed % 3)  // 4 to 6 layers
		
		// Needle layers - each hexagon slightly smaller, lighter, and rotated
		for i in 0..<layers {
			layer_ratio := 1.0 - (f32(i) * 0.18)
			radius := cs * base_size * layer_ratio
			
			// Choose color based on layer from biome colors
			color := tree_colors.layer_dark if i < layers / 3 else (tree_colors.layer_mid if i < 2 * layers / 3 else tree_colors.layer_light)
			if i == layers - 1 {
				color = tree_colors.layer_tip  // Lightest at top
			}
			
			// Each hexagon layer has slightly different rotation
			layer_rotation := base_rotation + f32(i * 15)  // Offset by 15 degrees per layer
			
			// Draw hexagon (6 sides)
			raylib.DrawPoly(
				raylib.Vector2{f32(cx), f32(cy)},
				6,  // hexagon
				radius,
				layer_rotation,
				color,
			)
		}
		
		// No trunk visible from top view in hexagon pine style
		
	case .DESERT:
		// Palm tree (desert) - top view: multiple stretched oval fronds radiating from center
		frond_count := 8
		inner_radius := cs * 0.15
		outer_radius := cs * 0.40
		frond_width := cs * 0.12
		
		// Draw radiating oval fronds
		for i in 0..<frond_count {
			angle := f32(i) * math.PI * 2.0 / f32(frond_count)
			
			// Calculate frond center position (between inner and outer radius)
			frond_center_dist := (inner_radius + outer_radius) * 0.5
			frond_cx := center_x + math.cos(angle) * frond_center_dist
			frond_cy := center_y + math.sin(angle) * frond_center_dist
			
			// Draw elongated oval frond
			raylib.DrawEllipse(
				i32(frond_cx), 
				i32(frond_cy), 
				f32(outer_radius - inner_radius) * 0.5,  // long axis
				f32(frond_width),  // short axis
				raylib.Color{34, 139, 34, 255}
			)
		}
		
		// Draw smaller inner fronds (darker green)
		for i in 0..<frond_count {
			angle := f32(i) * math.PI * 2.0 / f32(frond_count) + math.PI / f32(frond_count)
			frond_center_dist := inner_radius * 1.5
			frond_cx := center_x + math.cos(angle) * frond_center_dist
			frond_cy := center_y + math.sin(angle) * frond_center_dist
			
			raylib.DrawEllipse(
				i32(frond_cx), 
				i32(frond_cy), 
				f32(cs * 0.15),
				f32(cs * 0.08),
				raylib.Color{0, 100, 0, 255}
			)
		}
		
	case .MOUNTAIN:
		// Dead bush (mountain) - top view: branches radiating from center
		branch_length := cs * 0.25
		
		// Branches radiating from center
		for i in 0..<8 {
			angle := f32(i) * math.PI / 4
			end_x := center_x + math.cos(angle) * branch_length
			end_y := center_y + math.sin(angle) * branch_length
			raylib.DrawLine(i32(center_x), i32(center_y), i32(end_x), i32(end_y), raylib.Color{101, 67, 33, 255})
		}
	}
}

// Render block accessory
render_block :: proc(x, y, cs: f32) {
	raylib.DrawRectangleRounded(
		raylib.Rectangle{
			x + cs * 0.1,
			y + cs * 0.1,
			cs * 0.8,
			cs * 0.8,
		},
		0.1,
		4,
		constants.COLOR_BLOCK,
	)
	
	// Highlight
	raylib.DrawRectangle(
		i32(x + cs * 0.25),
		i32(y + cs * 0.25),
		i32(cs * 0.5),
		i32(cs * 0.5),
		constants.UI_EDITOR_HIGHLIGHT_COLOR
	)
}

// Render obstacles
render_obstacles :: proc(m: ^entities.Map, cs: f32, gs: i32, camera_offset_x, camera_offset_y: i32) {
	
	for row in 0..<gs {
		for col in 0..<gs {
			if m.obstacle_grid[row][col] == .OBSTACLE {
				x := f32(col) * cs + f32(camera_offset_x)
				y := f32(row) * cs + f32(camera_offset_y)
				
				// Draw spike/obstacle
				center_x := x + cs / 2
				center_y := y + cs / 2
				
				// Base
				raylib.DrawRectangle(
					i32(x + cs * 0.2),
					i32(y + cs * 0.6),
					i32(cs * 0.6),
					i32(cs * 0.3),
					constants.COLOR_OBSTACLE,
				)
				
				// Spike triangle
				p1 := raylib.Vector2{center_x, y + cs * 0.15}
				p2 := raylib.Vector2{x + cs * 0.2, y + cs * 0.7}
				p3 := raylib.Vector2{x + cs * 0.8, y + cs * 0.7}
				
				raylib.DrawTriangle(p1, p2, p3, constants.COLOR_OBSTACLE)
				
				// Level indicator
				level := entities.map_get_obstacle_level(m, row, col)
				if level > 1 {
					level_text := fmt.tprintf("%d", level)
					raylib.DrawText(
						strings.clone_to_cstring(level_text),
						i32(x + cs * 0.45),
						i32(y + cs * 0.4),
						i32(cs * 0.25),
						raylib.WHITE,
					)
				}
			}
		}
	}
}

// Render laser beams
render_laser_beams :: proc(app: ^entities.App_State, cs: f32) {
	sim := &app.sim
	
	for &beam in sim.laser_beams {
		alpha := beam.duration / beam.max_duration
		color := raylib.Color{
			255,
			68,
			68,
			u8(255 * alpha),
		}
		
		// Convert from grid coordinates to screen pixels
		start_screen_x := beam.start_x * cs + f32(app.camera_offset_x)
		start_screen_y := beam.start_y * cs + f32(app.camera_offset_y)
		end_screen_x := beam.end_x * cs + f32(app.camera_offset_x)
		end_screen_y := beam.end_y * cs + f32(app.camera_offset_y)
		
		raylib.DrawLineEx(
			raylib.Vector2{start_screen_x, start_screen_y},
			raylib.Vector2{end_screen_x, end_screen_y},
			3.0,
			color,
		)
	}
}

// Render gameplay elements (enemies, projectiles, effects)
render_gameplay :: proc(app: ^entities.App_State) {
	if app.state != .PLAYING && app.state != .PAUSED {
		return
	}
	
	cs := f32(app.settings.cell_size) * app.zoom
	
	// Render enemies
	render_enemies(app, cs)
	
	// Render enemy paths for debugging (if enabled)
	if app.editor.show_paths {
		render_enemy_paths(app, cs)
	}
	
	// Render projectiles
	render_projectiles(app, cs)
	
	// Render explosions
	render_explosions(app, cs)
	
	// Render damage numbers
	render_damage_numbers(app, cs)
}

// Render enemies
render_enemies :: proc(app: ^entities.App_State, cs: f32) {
	for &enemy in app.sim.enemies {
		x := enemy.x * cs + f32(app.camera_offset_x)
		y := enemy.y * cs + f32(app.camera_offset_y)
		
		// Enemy size reduced to 3/4 of original
		size := entities.enemy_get_size(&enemy) * cs
		color := entities.enemy_get_color(&enemy)
		
		// Shadow offset
		so := max(2, cs * 0.08)
		shadow_color := constants.ENEMY_SHADOW_COLOR
		
		// Draw enemy border (darkened version of body color, 2px thick)
		border_color := raylib.Color{
			u8(f32(color.r) * 0.6),
			u8(f32(color.g) * 0.6),
			u8(f32(color.b) * 0.6),
			color.a,
		}
		
		if enemy.is_flying {
			// Flying enemies are drawn as triangles (pointing up)
			center_x := x + cs / 2
			center_y := y + cs / 2
			
			// Triangle shadow (offset)
			v1_shadow := raylib.Vector2{center_x + so, center_y - size - 2 + so}  // Top
			v2_shadow := raylib.Vector2{center_x - size - 2 + so, center_y + size + 2 + so}  // Bottom left
			v3_shadow := raylib.Vector2{center_x + size + 2 + so, center_y + size + 2 + so}  // Bottom right
			raylib.DrawTriangle(v1_shadow, v2_shadow, v3_shadow, shadow_color)
			
			// Inner triangle (body)
			v1_body := raylib.Vector2{center_x, center_y - size}  // Top
			v2_body := raylib.Vector2{center_x - size, center_y + size}  // Bottom left
			v3_body := raylib.Vector2{center_x + size, center_y + size}  // Bottom right
			raylib.DrawTriangle(v1_body, v2_body, v3_body, color)
			
			// Triangle outline using DrawLine
			raylib.DrawLine(i32(v1_body.x), i32(v1_body.y), i32(v2_body.x), i32(v2_body.y), border_color)
			raylib.DrawLine(i32(v2_body.x), i32(v2_body.y), i32(v3_body.x), i32(v3_body.y), border_color)
			raylib.DrawLine(i32(v3_body.x), i32(v3_body.y), i32(v1_body.x), i32(v1_body.y), border_color)
		} else {
			// Ground enemies are drawn as circles
			center_x := x + cs / 2
			center_y := y + cs / 2
			
			// Circle shadow (offset)
			raylib.DrawCircle(i32(center_x + so), i32(center_y + so), size, shadow_color)
			
			// Circle body
			raylib.DrawCircle(i32(center_x), i32(center_y), size, color)
			
			// Circle outline using DrawCircleLines
			raylib.DrawCircleLines(i32(center_x), i32(center_y), size, border_color)
		}
		
		// Health bar - positioned higher up and slightly taller
		hp_percent := enemy.hp / enemy.max_hp
		hp_bar_width := cs * 0.6
		hp_bar_height := cs * 0.1
		hp_bar_x := x + cs / 2 - hp_bar_width / 2
		hp_bar_y := y - cs * 0.05
		
		raylib.DrawRectangle(
			i32(hp_bar_x),
			i32(hp_bar_y),
			i32(hp_bar_width),
			i32(hp_bar_height),
			raylib.DARKGRAY,
		)
		
		// Health bar fill
		if hp_percent > 0.01 {
			hp_color := raylib.GREEN
			if hp_percent < 0.3 {
				hp_color = raylib.Color{200, 50, 50, 255}  // Softer red
			} else if hp_percent < 0.6 {
				hp_color = raylib.YELLOW
			}
			
			// Ensure minimum width of 1 pixel to avoid artifacts
			fill_width := hp_bar_width * hp_percent
			if fill_width < 1.0 {
				fill_width = 1.0
			}
			
			raylib.DrawRectangle(
				i32(hp_bar_x),
				i32(hp_bar_y),
				i32(fill_width),
				i32(hp_bar_height),
				hp_color,
			)
		}
	}
}

// Render enemy paths for debugging
render_enemy_paths :: proc(app: ^entities.App_State, cs: f32) {
	// Draw paths from spawns
	for &spawn in app.sim.spawns {
		if len(spawn.path) < 2 {
			continue
		}
		
		// Draw lines between path nodes
		for i in 0..<len(spawn.path) - 1 {
			x1 := f32(spawn.path[i].x) * cs + f32(app.camera_offset_x) + cs / 2
			y1 := f32(spawn.path[i].y) * cs + f32(app.camera_offset_y) + cs / 2
			x2 := f32(spawn.path[i + 1].x) * cs + f32(app.camera_offset_x) + cs / 2
			y2 := f32(spawn.path[i + 1].y) * cs + f32(app.camera_offset_y) + cs / 2
			
			raylib.DrawLine(i32(x1), i32(y1), i32(x2), i32(y2), raylib.YELLOW)
		}
		
		// Draw dots at path nodes
		for node in spawn.path {
			x := f32(node.x) * cs + f32(app.camera_offset_x) + cs / 2
			y := f32(node.y) * cs + f32(app.camera_offset_y) + cs / 2
			raylib.DrawCircle(i32(x), i32(y), cs * 0.15, raylib.GOLD)
		}
	}
	
	// Draw paths for active enemies
	for &enemy in app.sim.enemies {
		if len(enemy.path) < 2 {
			continue
		}
		
		// Draw remaining path from current position
		start_idx := enemy.path_idx
		if start_idx < 0 {
			start_idx = 0
		}
		
		for i in start_idx..<i32(len(enemy.path) - 1) {
			x1 := f32(enemy.path[i].x) * cs + f32(app.camera_offset_x) + cs / 2
			y1 := f32(enemy.path[i].y) * cs + f32(app.camera_offset_y) + cs / 2
			x2 := f32(enemy.path[i + 1].x) * cs + f32(app.camera_offset_x) + cs / 2
			y2 := f32(enemy.path[i + 1].y) * cs + f32(app.camera_offset_y) + cs / 2
			
			raylib.DrawLine(i32(x1), i32(y1), i32(x2), i32(y2), raylib.Color{255, 255, 0, 128})
		}
	}
}

// Render projectiles
render_projectiles :: proc(app: ^entities.App_State, cs: f32) {
	for &proj in app.sim.projectiles {
		x := proj.x * cs + f32(app.camera_offset_x)
		y := proj.y * cs + f32(app.camera_offset_y)
		
		switch proj.type {
		case .ARCHER:
			// Arrow - small circle
			raylib.DrawCircle(i32(x + cs / 2), i32(y + cs / 2), cs * 0.1, raylib.BROWN)
		case .CANNON:
			// Cannonball - circle
			raylib.DrawCircle(i32(x + cs / 2), i32(y + cs / 2), cs * 0.15, raylib.BLACK)
		case .SNIPER:
			// Bullet - small circle
			raylib.DrawCircle(i32(x + cs / 2), i32(y + cs / 2), cs * 0.08, raylib.GREEN)
		case .MISSILE:
			// Missile - rotated body + pointed tip (matching JS)
			px := x + cs / 2
			py := y + cs / 2
			missile_len := cs * 0.3
			missile_thick := cs * 0.12
			angle := proj.angle
			
			// Body rectangle - rotated along trajectory
			cos_a := math.cos(angle)
			sin_a := math.sin(angle)
			
			body_rect := raylib.Rectangle{
				x = px,
				y = py,
				width = missile_len * 0.7,
				height = missile_thick,
			}
			body_origin := raylib.Vector2{missile_len * 0.7 / 2, missile_thick / 2}
			rotation_deg := angle * 180.0 / math.PI
			raylib.DrawRectanglePro(body_rect, body_origin, rotation_deg, constants.TOWER_MISSILE_POD)
			
			// Pointed tip triangle
			tip_dist := missile_len * 0.2
			tip_x := px + cos_a * tip_dist
			tip_y := py + sin_a * tip_dist
			
			// Triangle tip pointing in direction of movement
			tip_end_x := px + cos_a * (missile_len * 0.5)
			tip_end_y := py + sin_a * (missile_len * 0.5)
			
			// Perpendicular offset for triangle base
			perp_x := -sin_a * (missile_thick * 0.5)
			perp_y := cos_a * (missile_thick * 0.5)
			
			raylib.DrawTriangle(
				{tip_x + perp_x, tip_y + perp_y},
				{tip_end_x, tip_end_y},
				{tip_x - perp_x, tip_y - perp_y},
				raylib.Color{255, 59, 59, 255},  // MISSILE_WARHEAD red
			)
		case .LASER:
			// No projectile for laser
		}
	}
}

// Render explosions
render_explosions :: proc(app: ^entities.App_State, cs: f32) {
	for &explosion in app.sim.explosions {
		x := explosion.x * cs + f32(app.camera_offset_x)
		y := explosion.y * cs + f32(app.camera_offset_y)
		
		radius := explosion.radius * cs
		alpha := u8(255 * (explosion.life / explosion.max_life))
		
		color := raylib.Color{255, 100, 50, alpha}
		
		raylib.DrawCircle(i32(x + cs / 2), i32(y + cs / 2), radius, color)
	}
}

// Render damage numbers
render_damage_numbers :: proc(app: ^entities.App_State, cs: f32) {
	for &dn in app.sim.damage_numbers {
		x := dn.x * cs + f32(app.camera_offset_x)
		y := dn.y * cs + f32(app.camera_offset_y)
		
		alpha := u8(255 * dn.life)
		color := dn.color
		color.a = alpha
		
		damage_text := fmt.tprintf("%.0f", dn.value)
		font_size := cs * 0.4
		if dn.is_critical {
			font_size = cs * 0.5
		}
		
		raylib.DrawTextEx(constants.game_fonts.bold, strings.clone_to_cstring(damage_text), {x, y}, font_size, 0, color)
	}
}

// Render UI
render_ui :: proc(app: ^entities.App_State) {
	switch app.state {
	case .MENU:
		render_menu_ui(app)
	case .PLAYING:
		render_game_ui(app)
		render_tower_control_panel(app)
	case .PAUSED:
		render_pause_menu(app)
	case .EDITOR:
		render_editor_ui(app)
	case .GAME_OVER:
		render_game_over_ui(app)
	case .SETTINGS:
		render_settings_menu(app)
	}
	
	// FPS counter
	if app.settings.show_fps {
		fps_text := fmt.tprintf("FPS: %d", raylib.GetFPS())
		raylib.DrawText(strings.clone_to_cstring(fps_text), 10, 10, 20, raylib.WHITE)
	}
}

// Render menu UI
render_menu_ui :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()
	
	// Black background
	raylib.DrawRectangle(0, 0, screen_width, screen_height, raylib.BLACK)
	
	// Title (using bold font)
	title_text := constants.get_text(.MENU_TITLE)
	title_size := f32(screen_height) * 0.08
	title_width := f32(raylib.MeasureTextEx(constants.game_fonts.bold, strings.clone_to_cstring(title_text), title_size, 0).x)
	title_x := f32(screen_width) / 2 - title_width / 2
	raylib.DrawTextEx(constants.game_fonts.bold, strings.clone_to_cstring(title_text), {title_x, f32(screen_height) / 4}, title_size, 0, raylib.WHITE)
	
	// Buttons (using UI constants)
	menu_button_width := i32(constants.UI_BUTTON_WIDTH)
	menu_button_height := i32(constants.UI_BUTTON_HEIGHT)
	menu_button_x := screen_width / 2 - menu_button_width / 2
	
	// Play button
	play_button_y := screen_height / 2
	if render_button(constants.get_text(.MENU_BUTTON_PLAY), {f32(menu_button_x), f32(play_button_y), f32(menu_button_width), f32(menu_button_height)}) {
		entities.app_set_state(app, .PLAYING)
	}
	
	// Editor button
	editor_button_y := play_button_y + menu_button_height + 10
	if render_button(constants.get_text(.MENU_BUTTON_EDITOR), {f32(menu_button_x), f32(editor_button_y), f32(menu_button_width), f32(menu_button_height)}) {
		entities.app_set_state(app, .EDITOR)
	}
	
	// Settings button
	settings_button_y := editor_button_y + menu_button_height + 10
	if render_button(constants.get_text(.MENU_BUTTON_SETTINGS), {f32(menu_button_x), f32(settings_button_y), f32(menu_button_width), f32(menu_button_height)}) {
		entities.app_set_state(app, .SETTINGS)
	}
	
	// Exit button
	exit_button_y := settings_button_y + menu_button_height + 10
	if render_button(constants.get_text(.MENU_BUTTON_EXIT), {f32(menu_button_x), f32(exit_button_y), f32(menu_button_width), f32(menu_button_height)}) {
		app.should_quit = true
	}
}

// Render game UI (HUD)
render_game_ui :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()
	
	// Money
	font_size := f32(constants.UI_BUTTON_FONT_SIZE)
	money_label := constants.get_text(.UI_MONEY)
	money_text := fmt.tprintf("%s: %d", money_label, app.sim.money)
	money_width := raylib.MeasureTextEx(constants.game_fonts.regular, strings.clone_to_cstring(money_text), font_size, 0).x
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(money_text), {f32(10), f32(40)}, font_size, 0, raylib.GOLD)
	
	// Health
	health_label := constants.get_text(.UI_HEALTH)
	health_text := fmt.tprintf("%s: %d", health_label, app.sim.health)
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(health_text), {f32(10), f32(70)}, font_size, 0, raylib.GREEN)
	
	// Wave
	wave_label := constants.get_text(.UI_WAVE)
	wave_text := fmt.tprintf("%s: %d", wave_label, app.sim.wave_number)
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(wave_text), {f32(10), f32(100)}, font_size, 0, raylib.BLUE)
	
	// Enemies
	enemies_label := constants.get_text(.UI_ENEMIES)
	enemies_text := fmt.tprintf("%s: %d", enemies_label, len(app.sim.enemies))
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(enemies_text), {f32(10), f32(130)}, font_size, 0, raylib.RED)
	
	// Calculate button widths based on text
	button_y := i32(10)
	padding := i32(20)
	gap := i32(10)
	
	// Pause button text and width
	pause_text := constants.get_text(.UI_BUTTON_PAUSE)
	if app.sim.paused {
		pause_text = constants.get_text(.UI_BUTTON_RESUME)
	}
	pause_text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(pause_text), font_size, 0).x)
	pause_width := pause_text_width + padding
	
	// 1x button width
	speed1_text := "1x"
	speed1_text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(speed1_text), font_size, 0).x)
	speed1_width := speed1_text_width + padding
	
	// 2x button width
	speed2_text := "2x"
	speed2_text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(speed2_text), font_size, 0).x)
	speed2_width := speed2_text_width + padding
	
	// Calculate positions from right to left
	total_buttons_width := pause_width + speed1_width + speed2_width + gap * 2
	pause_x := screen_width - total_buttons_width
	speed1_x := pause_x + pause_width + gap
	speed2_x := speed1_x + speed1_width + gap
	
	// Pause button
	if render_button(pause_text, {f32(pause_x), f32(button_y), f32(pause_width), f32(constants.UI_BUTTON_HEIGHT)}) {
		simulation_toggle_pause(app)
	}
	
	// Speed buttons
	if render_button(speed1_text, {f32(speed1_x), f32(button_y), f32(speed1_width), f32(constants.UI_BUTTON_HEIGHT)}) {
		simulation_set_speed(app, 1.0)
	}
	if render_button(speed2_text, {f32(speed2_x), f32(button_y), f32(speed2_width), f32(constants.UI_BUTTON_HEIGHT)}) {
		simulation_set_speed(app, 2.0)
	}
	
	// Tower build buttons
	tower_types := []constants.Tile{.TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER}
	tower_names := []string{"Archer", "Cannon", "Sniper", "Missile", "Laser"}
	tower_costs := []i32{20, 40, 60, 50, 80}
	
	// Calculate total toolbar width to center it
	total_width := i32(len(tower_types)) * constants.UI_BUTTON_WIDTH + i32(len(tower_types) - 1) * 5
	start_x := (screen_width - total_width) / 2
	
	// Increased bottom margin because buttons are now taller (2 lines of text)
	bottom_margin := i32(40)
	
	for i := 0; i < len(tower_types); i += 1 {
		x := start_x + i32(i) * (constants.UI_BUTTON_WIDTH + 5)
		y := i32(screen_height - constants.UI_BUTTON_HEIGHT - bottom_margin)
		
		// Highlight selected tower
		is_selected := app.sim.selected_build_tower == tower_types[i]
		button_color := raylib.LIGHTGRAY
		if is_selected {
			button_color = raylib.GREEN
		}
		
		// Check if can afford
		can_afford := app.sim.money >= tower_costs[i]
		if !can_afford {
			button_color = raylib.DARKGRAY
		}
		
		// Format button text with name and cost
		button_text := fmt.tprintf("%s\n$%d", tower_names[i], tower_costs[i])
		
		// Use render_button_with_color for consistent UI (2 lines: name and cost)
		if render_button_with_color(button_text, {f32(x), f32(y), f32(constants.UI_BUTTON_WIDTH), f32(constants.UI_BUTTON_HEIGHT)}, button_color, 2) && can_afford {
			if is_selected {
				app.sim.selected_build_tower = .EMPTY  // Deselect
			} else {
				app.sim.selected_build_tower = tower_types[i]  // Select
			}
		}
	}
}

// Render editor UI
render_editor_ui :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()
	
	// Tool buttons
	tools := []struct {
		name: string,
		tile: constants.Tile,
	}{
		{"Empty", .EMPTY},
		{"Path", .PATH},
		{"Spawn", .SPAWN},
		{"Goal", .GOAL},
		{"Archer", .TOWER_ARCHER},
		{"Cannon", .TOWER_CANNON},
		{"Sniper", .TOWER_SNIPER},
		{"Missile", .TOWER_MISSILE},
		{"Laser", .TOWER_LASER},
		{"Obstacle", .OBSTACLE},
		{"Tree", .ACCESSORY_TREE},
		{"Block", .ACCESSORY_BLOCK},
	}
	
	button_width := i32(80)
	button_height := i32(30)
	margin := i32(5)
	
	// Calculate toolbar dimensions
	toolbar_width := button_width + margin * 2
	toolbar_height := i32(len(tools)) * (button_height + margin) + margin * 2
	
	// Position toolbar on left center
	toolbar_x := i32(20)
	toolbar_y := (screen_height - toolbar_height) / 2
	
	// Draw floating toolbar with rounded corners
	raylib.DrawRectangleRounded(
		raylib.Rectangle{f32(toolbar_x), f32(toolbar_y), f32(toolbar_width), f32(toolbar_height)},
		0.2, 8, raylib.Color{50, 50, 50, 230}
	)
	raylib.DrawRectangleRoundedLines(
		raylib.Rectangle{f32(toolbar_x), f32(toolbar_y), f32(toolbar_width), f32(toolbar_height)},
		0.2, 8, 2, raylib.WHITE
	)
	
	// Draw tool buttons in a column
	for tool, i in tools {
		x := toolbar_x + margin
		y := toolbar_y + margin + i32(i) * (button_height + margin)
		
		is_selected := app.editor.current_tool == tool.tile
		color := raylib.DARKGRAY
		if is_selected {
			color = raylib.BLUE
		}
		
		raylib.DrawRectangleRounded(
			raylib.Rectangle{f32(x), f32(y), f32(button_width), f32(button_height)},
			0.1, 4, color
		)
		raylib.DrawText(strings.clone_to_cstring(tool.name), x + 5, y + 10, 15, raylib.WHITE)
	}
	
	// Bottom toolbar
	raylib.DrawRectangle(0, raylib.GetScreenHeight() - constants.UI_TOOLBAR_HEIGHT, screen_width, constants.UI_TOOLBAR_HEIGHT, raylib.Color{50, 50, 50, 200})
	
	// Biome selector using render_select
	biome_names := []string{"Plain", "Forest", "Desert", "Mountain"}
	biome_index := i32(app.editor.current_biome)
	
	if render_select("biome", "Biome: ", biome_names, &biome_index, 10, raylib.GetScreenHeight() - constants.UI_TOOLBAR_HEIGHT + 4, i32(constants.UI_DROPDOWN_WIDTH), i32(constants.UI_DROPDOWN_HEIGHT), true) {
		app.editor.current_biome = constants.Biome(biome_index)
		app.editor.game_map.biome = constants.Biome(biome_index)
	}
	
	// Right-side buttons - laid out from right to left with consistent gap
	y_pos := raylib.GetScreenHeight() - constants.UI_TOOLBAR_HEIGHT + 4
	gap := i32(10)
	
	// Helper to calculate actual button width
	btn_w :: proc(text: string) -> i32 {
		text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text), f32(constants.UI_BUTTON_FONT_SIZE), 0).x)
		min_w := text_width + 20
		return min_w > constants.UI_BUTTON_WIDTH ? min_w : constants.UI_BUTTON_WIDTH
	}
	
	current_x := screen_width - 10 // right margin
	
	// Menu button (rightmost)
	w_menu := btn_w("Menu")
	current_x -= w_menu
	if render_button("Menu", {f32(current_x), f32(y_pos), f32(w_menu), f32(constants.UI_BUTTON_HEIGHT)}) {
		entities.app_set_state(app, .MENU)
	}
	
	// Test button
	current_x -= gap
	w_test := btn_w("Test Map")
	current_x -= w_test
	if render_button("Test Map", {f32(current_x), f32(y_pos), f32(w_test), f32(constants.UI_BUTTON_HEIGHT)}) {
		if simulation_init_from_editor(app) {
			entities.app_set_state(app, .PLAYING)
		}
	}
	
	// Quick Load button
	current_x -= gap
	w_load := btn_w("Quick Load")
	current_x -= w_load
	if render_button("Quick Load", {f32(current_x), f32(y_pos), f32(w_load), f32(constants.UI_BUTTON_HEIGHT)}) {
		if entities.map_load(&app.editor.game_map, "last_saved.map") {
			app.editor.current_biome = app.editor.game_map.biome
		}
	}
	
	// Save button
	current_x -= gap
	w_save := btn_w("Save Map")
	current_x -= w_save
	if render_button("Save Map", {f32(current_x), f32(y_pos), f32(w_save), f32(constants.UI_BUTTON_HEIGHT)}) {
		// Save with timestamp AND as last_saved.map for quick loading
		filename := fmt.tprintf("map_%d.map", i32(raylib.GetTime()))
		_ = entities.map_save(&app.editor.game_map, filename)
		_ = entities.map_save(&app.editor.game_map, "last_saved.map")
	}
}

// Render pause menu overlay
render_pause_menu :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()
	
	// Semi-transparent overlay
	raylib.DrawRectangle(0, 0, screen_width, screen_height, constants.UI_OVERLAY_COLOR)
	
	// Pause title
	title := constants.get_text(.PAUSE_TITLE)
	title_cstr := strings.clone_to_cstring(title)
	title_size := f32(40)
	title_width := raylib.MeasureTextEx(constants.game_fonts.bold, title_cstr, title_size, 0).x
	title_x := f32(screen_width) / 2 - title_width / 2
	title_y := f32(screen_height) / 3
	raylib.DrawTextEx(constants.game_fonts.bold, title_cstr, {title_x, title_y}, title_size, 0, raylib.WHITE)
	
	// Button dimensions
	button_width := i32(constants.UI_BUTTON_WIDTH)
	button_height := i32(constants.UI_BUTTON_HEIGHT)
	button_x := screen_width / 2 - button_width / 2
	
	// Resume button
	resume_y := screen_height / 2
	if render_button(constants.get_text(.PAUSE_RESUME), {f32(button_x), f32(resume_y), f32(button_width), f32(button_height)}) {
		simulation_set_pause(app, false)
		entities.app_set_state(app, .PLAYING)
	}
	
	// Settings button
	settings_y := resume_y + button_height + 20
	if render_button(constants.get_text(.MENU_BUTTON_SETTINGS), {f32(button_x), f32(settings_y), f32(button_width), f32(button_height)}) {
		entities.app_set_state(app, .SETTINGS)
	}
	
	// Main Menu button
	menu_y := settings_y + button_height + 20
	if render_button(constants.get_text(.PAUSE_MENU), {f32(button_x), f32(menu_y), f32(button_width), f32(button_height)}) {
		simulation_set_pause(app, false)
		entities.app_set_state(app, .MENU)
	}
}

// Render game over UI
render_game_over_ui :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()
	
	// Semi-transparent overlay
	raylib.DrawRectangle(0, 0, screen_width, screen_height, raylib.Color{0, 0, 0, 200})
	
	// Game Over text
	title := "GAME OVER"
	title_size := 60
	title_cstr := strings.clone_to_cstring(title)
	title_x := screen_width / 2 - raylib.MeasureText(title_cstr, i32(title_size)) / 2
	raylib.DrawText(title_cstr, title_x, screen_height / 3, i32(title_size), raylib.RED)
	
	// Wave survived
	wave_text := fmt.tprintf("You survived %d waves", app.sim.wave_number)
	wave_size := 30
	wave_cstr := strings.clone_to_cstring(wave_text)
	wave_x := screen_width / 2 - raylib.MeasureText(wave_cstr, i32(wave_size)) / 2
	raylib.DrawText(strings.clone_to_cstring(wave_text), wave_x, screen_height / 2, i32(wave_size), raylib.WHITE)
	
	// Menu button
	button_width :i32= constants.UI_BUTTON_WIDTH
	button_height :i32= constants.UI_BUTTON_HEIGHT
	button_x := screen_width / 2 - button_width / 2
	button_y := screen_height * 2 / 3
	
	if render_button("Main Menu", {f32(button_x), f32(button_y), f32(button_width), f32(button_height)}) {
		entities.app_set_state(app, .MENU)
	}
}

// Render settings menu
render_settings_menu :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()
	
	// Background
	raylib.DrawRectangle(0, 0, i32(screen_width), i32(screen_height), raylib.Color{20, 20, 30, 255})
	
	// Title
	title_text := constants.get_text(.SETTINGS_TITLE)
	title_size := f32(30)
	title_width := raylib.MeasureTextEx(constants.game_fonts.bold, strings.clone_to_cstring(title_text), title_size, 0)
	title_x := (f32(screen_width) - title_width.x) / 2
	raylib.DrawTextEx(constants.game_fonts.bold, strings.clone_to_cstring(title_text), {title_x, 50}, title_size, 0, raylib.WHITE)
	
	// Settings panel
	panel_x := i32(screen_width) / 2 - 200
	panel_y := i32(100)
	panel_width := i32(400)
	panel_height := i32(450)
	
	raylib.DrawRectangle(panel_x, panel_y, panel_width, panel_height, raylib.Color{40, 40, 50, 255})
	raylib.DrawRectangleLines(panel_x, panel_y, panel_width, panel_height, raylib.GRAY)
	
	// Setting items
	item_y := panel_y + 20
	item_height := i32(35)
	label_width := i32(150)
	
	// Master Volume
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(constants.get_text(.SETTINGS_VOLUME)), {f32(panel_x + 20), f32(item_y + 8)}, 20, 0, raylib.WHITE)
	volume_value := i32(app.settings.master_volume * 100)
	volume_text := fmt.tprintf("%d%%", volume_value)
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(volume_text), {f32(panel_x + panel_width - 80), f32(item_y + 8)}, 20, 0, raylib.WHITE)
	
	// Volume minus button
	if render_button("-", {f32(panel_x + label_width), f32(item_y), 30, f32(item_height)}) {
		if app.settings.master_volume > 0.0 {
			app.settings.master_volume -= 0.1
			if app.settings.master_volume < 0.0 {
				app.settings.master_volume = 0.0
			}
		}
	}
	
	// Volume plus button
	if render_button("+", {f32(panel_x + label_width + 35), f32(item_y), 30, f32(item_height)}) {
		if app.settings.master_volume < 1.0 {
			app.settings.master_volume += 0.1
			if app.settings.master_volume > 1.0 {
				app.settings.master_volume = 1.0
			}
		}
	}
	
	item_y += item_height + 15
	
	// Language selector
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(constants.get_text(.SETTINGS_LANGUAGE)), {f32(panel_x + 20), f32(item_y + 8)}, 20, 0, raylib.WHITE)
	lang_text := constants.get_text(.SETTINGS_LANGUAGE_ENGLISH)
	#partial switch app.settings.language {
	case .SPANISH: lang_text = constants.get_text(.SETTINGS_LANGUAGE_SPANISH)
	case .PORTUGUESE: lang_text = constants.get_text(.SETTINGS_LANGUAGE_PORTUGUESE)
	}
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(lang_text), {f32(panel_x + panel_width - 120), f32(item_y + 8)}, 20, 0, raylib.WHITE)
	
	// Language prev button
	if render_button("<", {f32(panel_x + label_width), f32(item_y), 40, f32(item_height)}) {
		switch app.settings.language {
		case .ENGLISH: app.settings.language = .PORTUGUESE
		case .SPANISH: app.settings.language = .ENGLISH
		case .PORTUGUESE: app.settings.language = .SPANISH
		}
		constants.set_language(app.settings.language)
	}
	
	// Language next button
	if render_button(">", {f32(panel_x + label_width + 45), f32(item_y), 40, f32(item_height)}) {
		switch app.settings.language {
		case .ENGLISH: app.settings.language = .SPANISH
		case .SPANISH: app.settings.language = .PORTUGUESE
		case .PORTUGUESE: app.settings.language = .ENGLISH
		}
		constants.set_language(app.settings.language)
	}
	
	item_y += item_height + 15
	
	// Anti-aliasing using render_select
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(constants.get_text(.SETTINGS_ANTIALIASING)), {f32(panel_x + 20), f32(item_y + 8)}, 20, 0, raylib.WHITE)
	
	aa_options := []string{"Off", "2x", "4x", "8x"}
	_ = render_select("antialiasing", "", aa_options, &app.settings.antialiasing, panel_x + panel_width - 120, item_y, 100, item_height, true)
	
	item_y += item_height + 15
	
	// Show Grid Toggle
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(constants.get_text(.SETTINGS_SHOW_GRID)), {f32(panel_x + 20), f32(item_y + 8)}, 20, 0, raylib.WHITE)
	grid_text := constants.get_text(.UI_ON) if app.settings.show_grid else constants.get_text(.UI_OFF)
	if render_button(grid_text, {f32(panel_x + panel_width - 100), f32(item_y), 80, f32(item_height)}) {
		app.settings.show_grid = !app.settings.show_grid
	}
	
	item_y += item_height + 15
	
	// Show Damage Numbers Toggle
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(constants.get_text(.SETTINGS_SHOW_DAMAGE_NUMBERS)), {f32(panel_x + 20), f32(item_y + 8)}, 20, 0, raylib.WHITE)
	dmg_text := constants.get_text(.UI_ON) if app.settings.show_damage_numbers else constants.get_text(.UI_OFF)
	if render_button(dmg_text, {f32(panel_x + panel_width - 100), f32(item_y), 80, f32(item_height)}) {
		app.settings.show_damage_numbers = !app.settings.show_damage_numbers
	}
	
	item_y += item_height + 15
	
	// Show Tower Range Toggle
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(constants.get_text(.SETTINGS_SHOW_TOWER_RANGE)), {f32(panel_x + 20), f32(item_y + 8)}, 20, 0, raylib.WHITE)
	range_text := constants.get_text(.UI_ON) if app.settings.show_tower_range else constants.get_text(.UI_OFF)
	if render_button(range_text, {f32(panel_x + panel_width - 100), f32(item_y), 80, f32(item_height)}) {
		app.settings.show_tower_range = !app.settings.show_tower_range
	}
	
	item_y += item_height + 15
	
	// Show FPS Toggle
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(constants.get_text(.SETTINGS_SHOW_FPS)), {f32(panel_x + 20), f32(item_y + 8)}, 20, 0, raylib.WHITE)
	fps_text := constants.get_text(.UI_ON) if app.settings.show_fps else constants.get_text(.UI_OFF)
	if render_button(fps_text, {f32(panel_x + panel_width - 100), f32(item_y), 80, f32(item_height)}) {
		app.settings.show_fps = !app.settings.show_fps
	}
	
	item_y += item_height + 15
	
	// Auto Start Wave Toggle
	raylib.DrawTextEx(constants.game_fonts.regular, strings.clone_to_cstring(constants.get_text(.SETTINGS_AUTO_WAVE)), {f32(panel_x + 20), f32(item_y + 8)}, 20, 0, raylib.WHITE)
	auto_text := constants.get_text(.UI_ON) if app.settings.auto_start_wave else constants.get_text(.UI_OFF)
	if render_button(auto_text, {f32(panel_x + panel_width - 100), f32(item_y), 80, f32(item_height)}) {
		app.settings.auto_start_wave = !app.settings.auto_start_wave
	}
	
	// Back button
	back_y := panel_y + panel_height + 20
	back_width := i32(150)
	back_x := (i32(screen_width) - back_width) / 2
	if render_button(constants.get_text(.SETTINGS_BACK_TO_MENU), {f32(back_x), f32(back_y), f32(back_width), 40}) {
		entities.app_set_state(app, .MENU)
	}
}

// Global UI state
ui_active_dropdown_id: string = ""

// Render a select dropdown (or dropup)
// Returns true if a new option was selected
render_select :: proc(id: string, prefix: string, options: []string, selected_index: ^i32, x, y, width, height: i32, dropup: bool = false) -> bool {
	font_size := f32(constants.UI_BUTTON_FONT_SIZE)
	
	// Find max width among all options to keep width stable
	max_text_width: f32 = 0
	for opt in options {
		t := fmt.tprintf("%s%s", prefix, opt)
		w := f32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(t), font_size, 0).x)
		if w > max_text_width {
			max_text_width = w
		}
	}
	
	actual_width := width
	min_width := i32(max_text_width) + 40 // padding + space for arrow
	if actual_width < min_width {
		actual_width = min_width
	}

	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	is_open := ui_active_dropdown_id == id
	
	hovered_main := mouse_x >= x && mouse_x <= x + actual_width &&
	                mouse_y >= y && mouse_y <= y + height
	
	color := constants.UI_BUTTON_COLOR
	if hovered_main || is_open {
		color = constants.UI_BUTTON_HOVER_COLOR
	}
	
	raylib.DrawRectangleRounded({f32(x + constants.UI_BUTTON_SHADOW_OFFSET), f32(y + constants.UI_BUTTON_SHADOW_OFFSET), f32(actual_width), f32(height)}, constants.UI_BUTTON_ROUNDNESS, 8, constants.UI_BUTTON_SHADOW_COLOR)
	raylib.DrawRectangleRounded({f32(x), f32(y), f32(actual_width), f32(height)}, constants.UI_BUTTON_ROUNDNESS, 8, color)
	
	// Text
	text := fmt.tprintf("%s%s", prefix, options[selected_index^])
	text_width := f32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text), font_size, 0).x)
	text_x := f32(x) + f32(actual_width) / 2 - text_width / 2
	text_y := f32(y) + f32(height) / 2 - font_size / 2
	raylib.DrawTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text), {text_x, text_y}, font_size, 0, constants.UI_TEXT_COLOR)
	
	// Draw arrow indicator
	arrow_x := f32(x + actual_width - 15)
	arrow_y := f32(y + height / 2)
	if is_open {
		if dropup {
			raylib.DrawTriangle({arrow_x - 5, arrow_y - 2}, {arrow_x + 5, arrow_y - 2}, {arrow_x, arrow_y + 3}, constants.UI_TEXT_COLOR)
		} else {
			raylib.DrawTriangle({arrow_x, arrow_y - 3}, {arrow_x + 5, arrow_y + 2}, {arrow_x - 5, arrow_y + 2}, constants.UI_TEXT_COLOR)
		}
	} else {
		if dropup {
			raylib.DrawTriangle({arrow_x, arrow_y - 3}, {arrow_x + 5, arrow_y + 2}, {arrow_x - 5, arrow_y + 2}, constants.UI_TEXT_COLOR)
		} else {
			raylib.DrawTriangle({arrow_x - 5, arrow_y - 2}, {arrow_x + 5, arrow_y - 2}, {arrow_x, arrow_y + 3}, constants.UI_TEXT_COLOR)
		}
	}
	
	changed := false
	
	if is_open {
		list_height := i32(len(options)) * height
		list_y := dropup ? y - list_height : y + height
		
		// Draw list background shadow
		raylib.DrawRectangle(x + constants.UI_BUTTON_SHADOW_OFFSET, list_y + constants.UI_BUTTON_SHADOW_OFFSET, actual_width, list_height, constants.UI_BUTTON_SHADOW_COLOR)
		
		for i := 0; i < len(options); i += 1 {
			item_y := dropup ? y - list_height + i32(i) * height : y + height + i32(i) * height
			
			hovered_item := mouse_x >= x && mouse_x <= x + actual_width && mouse_y >= item_y && mouse_y <= item_y + height
			
			item_color := constants.UI_BUTTON_COLOR
			if hovered_item {
				item_color = constants.UI_BUTTON_HOVER_COLOR
				if raylib.IsMouseButtonPressed(.LEFT) {
					selected_index^ = i32(i)
					changed = true
					ui_active_dropdown_id = "" // Close after selection
				}
			}
			
			// Highlight current selection
			if i32(i) == selected_index^ && !hovered_item {
				item_color = raylib.Color{60, 60, 60, 255}
			}
			
			raylib.DrawRectangle(x, item_y, actual_width, height, item_color)
			raylib.DrawRectangleLines(x, item_y, actual_width, height, constants.UI_BUTTON_SHADOW_COLOR)
			
			item_text := options[i]
			item_text_width := f32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(item_text), font_size, 0).x)
			item_text_x := f32(x) + f32(actual_width) / 2 - item_text_width / 2
			item_text_y := f32(item_y) + f32(height) / 2 - font_size / 2
			raylib.DrawTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(item_text), {item_text_x, item_text_y}, font_size, 0, constants.UI_TEXT_COLOR)
		}
		
		// Click outside to close
		if raylib.IsMouseButtonPressed(.LEFT) && !hovered_main {
			hovered_list := mouse_x >= x && mouse_x <= x + actual_width && mouse_y >= list_y && mouse_y <= list_y + list_height
			if !hovered_list {
				ui_active_dropdown_id = ""
			}
		}
	}
	
	// Click main button to toggle
	if hovered_main && raylib.IsMouseButtonPressed(.LEFT) {
		if is_open {
			ui_active_dropdown_id = ""
		} else {
			ui_active_dropdown_id = id
		}
	}
	
	return changed
}

// Render UI button
render_button_with_color :: proc(text: string, rect: raylib.Rectangle, base_color: raylib.Color, text_lines: i32 = 1) -> bool {
	x := i32(rect.x)
	y := i32(rect.y)
	width := i32(rect.width)
	height := i32(rect.height)
	
	actual_width := width
	actual_height := height
	
	font_size := f32(constants.UI_BUTTON_FONT_SIZE)
	line_spacing := font_size * 1.2
	
	// Calculate minimum height needed for the text (with padding)
	min_text_height := i32(f32(text_lines) * line_spacing + 16)  // 8px padding top/bottom
	if min_text_height > height {
		actual_height = min_text_height
	}
	
	text_width := raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text), font_size, 0).x
	if int(text_width) + 20 > int(width) {
		actual_width = i32(text_width) + 20
	}
	
	// Check hover
	mouse_pos := raylib.GetMousePosition()
	hovered := raylib.CheckCollisionPointRec(mouse_pos, {f32(x), f32(y), f32(actual_width), f32(actual_height)})
	
	// Determine button color based on hover state
	color := base_color
	if hovered {
		// Darken on hover
		color = raylib.Color{u8(f32(base_color.r) * 0.9), u8(f32(base_color.g) * 0.9), u8(f32(base_color.b) * 0.9), base_color.a}
		if raylib.IsMouseButtonDown(.LEFT) {
			color = raylib.Color{u8(f32(base_color.r) * 0.8), u8(f32(base_color.g) * 0.8), u8(f32(base_color.b) * 0.8), base_color.a}
		}
	}
	
	raylib.DrawRectangleRounded({f32(x + constants.UI_BUTTON_SHADOW_OFFSET), f32(y + constants.UI_BUTTON_SHADOW_OFFSET), f32(actual_width), f32(actual_height)}, constants.UI_BUTTON_ROUNDNESS, 8, constants.UI_BUTTON_SHADOW_COLOR)
	raylib.DrawRectangleRounded({f32(x), f32(y), f32(actual_width), f32(actual_height)}, constants.UI_BUTTON_ROUNDNESS, 8, color)
	
	// Text (centered) - calculate vertical position based on number of lines
	total_text_height := f32(text_lines) * line_spacing
	start_y := f32(y) + f32(actual_height) / 2 - total_text_height / 2
	
	// Split text by newlines and render each line centered
	lines := strings.split(text, "\n")
	defer delete(lines)
	
	for line, i in lines {
		line_width := raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(line), font_size, 0).x
		line_x := f32(x) + f32(actual_width) / 2 - line_width / 2
		line_y := start_y + f32(i) * line_spacing
		raylib.DrawTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(line), {line_x, line_y}, font_size, 0, constants.UI_TEXT_COLOR)
	}
	
	// Click check
	if hovered && raylib.IsMouseButtonPressed(.LEFT) {
		return true
	}
	
	return false
}

render_button :: proc(text: string, rect: raylib.Rectangle, text_lines: i32 = 1) -> bool {
	font_size := f32(constants.UI_BUTTON_FONT_SIZE)
	text_width := f32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text), font_size, 0).x)
	
	x := i32(rect.x)
	y := i32(rect.y)
	width := i32(rect.width)
	height := i32(rect.height)
	
	actual_width := width
	min_width := i32(text_width) + 20 // 10px padding on each side
	if actual_width < min_width {
		actual_width = min_width
	}

	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	hovered := mouse_x >= x && mouse_x <= x + actual_width &&
	           mouse_y >= y && mouse_y <= y + height
	
	if ui_active_dropdown_id != "" {
		hovered = false
	}
	
	color := constants.UI_BUTTON_COLOR
	if hovered {
		color = constants.UI_BUTTON_HOVER_COLOR
		if raylib.IsMouseButtonDown(.LEFT) {
			color = constants.UI_BUTTON_PRESSED_COLOR
		}
	}
	
	raylib.DrawRectangleRounded({f32(x + constants.UI_BUTTON_SHADOW_OFFSET), f32(y + constants.UI_BUTTON_SHADOW_OFFSET), f32(actual_width), f32(height)}, constants.UI_BUTTON_ROUNDNESS, 8, constants.UI_BUTTON_SHADOW_COLOR)
	raylib.DrawRectangleRounded({f32(x), f32(y), f32(actual_width), f32(height)}, constants.UI_BUTTON_ROUNDNESS, 8, color)
	
	// Text (centered) - handle multi-line text properly
	line_spacing := font_size * 1.2  // Approximate line spacing for multi-line text
	total_text_height := f32(text_lines) * line_spacing
	start_y := f32(y) + f32(height) / 2 - total_text_height / 2
	
	// Split text by newlines and render each line centered
	lines := strings.split(text, "\n")
	defer delete(lines)
	
	for line, i in lines {
		line_width := raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(line), font_size, 0).x
		line_x := f32(x) + f32(actual_width) / 2 - line_width / 2
		line_y := start_y + f32(i) * line_spacing
		raylib.DrawTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(line), {line_x, line_y}, font_size, 0, constants.UI_TEXT_COLOR)
	}
	
	// Click check
	if hovered && raylib.IsMouseButtonPressed(.LEFT) {
		return true
	}
	
	return false
}


// Check if mouse is over a rectangle
is_mouse_over_rect :: proc(rect: raylib.Rectangle) -> bool {
	mouse_pos := raylib.GetMousePosition()
	return raylib.CheckCollisionPointRec(mouse_pos, rect)
}

// Check if mouse is over tower control panel (to prevent grid clicks)
is_mouse_over_tower_panel :: proc(app: ^entities.App_State) -> bool {
	if app.selected_tower == nil {
		return false
	}
	
	panel_rect := raylib.Rectangle{
		x = f32(raylib.GetScreenWidth() - constants.UI_PANEL_WIDTH - constants.UI_PANEL_MARGIN),
		y = f32(constants.UI_PANEL_Y_POSITION),
		width = f32(constants.UI_PANEL_WIDTH),
		height = f32(constants.UI_PANEL_HEIGHT),
	}
	
	return is_mouse_over_rect(panel_rect)
}

// Unified tower drawing function (JS style) - works for both editor and simulation
// This is the main function that should be used everywhere
draw_tower_tile :: proc(x, y: f32, cs: f32, tower_type: constants.Tower_Type, angle: f32 = 0, is_ghost: bool = false) {
	cx := x + cs / 2
	cy := y + cs / 2
	base_w := cs * 0.8
	base_h := cs * 0.8
	bx := cx - base_w / 2
	by := cy - base_h / 2
	rad := max(2, cs * 0.15)
	shadow_offset := max(2, cs * 0.08)
	
	// Get colors based on tower type
	fill, stroke: raylib.Color
	switch tower_type {
	case .LASER:
		fill = constants.TOWER_LASER_BASE
		stroke = constants.TOWER_LASER_STROKE
	case .CANNON:
		fill = constants.TOWER_CANNON_BASE
		stroke = constants.TOWER_CANNON_STROKE
	case .MISSILE:
		fill = constants.TOWER_MISSILE_BASE
		stroke = constants.TOWER_MISSILE_STROKE
	case .SNIPER:
		fill = constants.TOWER_SNIPER_BASE
		stroke = constants.TOWER_SNIPER_STROKE
	case .ARCHER:
		fill = constants.TOWER_ARCHER_BASE
		stroke = constants.TOWER_ARCHER_STROKE
	}
	
	// Draw shadow (hard shadow offset to bottom-right like JS)
	if !is_ghost {
		raylib.DrawRectangleRounded(
			raylib.Rectangle{f32(bx + shadow_offset), f32(by + shadow_offset), f32(base_w), f32(base_h)},
			constants.TOWER_ROUNDED_CORNER, constants.TOWER_CORNER_SEGMENTS, constants.TOWER_SHADOW,
		)
	}
	
	// Draw base
	raylib.DrawRectangleRounded(
		raylib.Rectangle{f32(bx), f32(by), f32(base_w), f32(base_h)},
		constants.TOWER_ROUNDED_CORNER, constants.TOWER_CORNER_SEGMENTS, fill,
	)
	
	// Draw stroke
	raylib.DrawRectangleRoundedLines(
		raylib.Rectangle{f32(bx), f32(by), f32(base_w), f32(base_h)},
		constants.TOWER_ROUNDED_CORNER, constants.TOWER_CORNER_SEGMENTS, 2, stroke,
	)
	
	// Draw tower-specific components
	r := cs * 0.25
	so := cs * 0.03  // Shadow offset for components
	
	// Rotate for barrel orientation (pointing up by default like JS: angle + PI/2)
	rotation := angle + math.PI / 2
	
	// Draw tower components with shadows immediately after each component
	switch tower_type {
	case .LASER:
		// Barrel dimensions (matching JS: -cs*0.1, -cs*0.35, cs*0.2, cs*0.3)
		barrel_w := cs * 0.2
		barrel_h := cs * 0.3
		origin := raylib.Vector2{f32(barrel_w/2), f32(barrel_h)}  // Pivot at bottom of barrel (tower center)
		laser_rotation := rotation * 180.0 / math.PI
		
		// Barrel shadow - rotated using DrawRectanglePro with pivot at tower center
		barrel_rect := raylib.Rectangle{
			x = f32(cx + so),
			y = f32(cy + so),
			width = f32(barrel_w),
			height = f32(barrel_h),
		}
		raylib.DrawRectanglePro(barrel_rect, origin, laser_rotation, constants.TOWER_SHADOW)
		
		// Barrel - rotated using DrawRectanglePro with pivot at tower center
		barrel_rect = raylib.Rectangle{
			x = f32(cx),
			y = f32(cy),
			width = f32(barrel_w),
			height = f32(barrel_h),
		}
		raylib.DrawRectanglePro(barrel_rect, origin, laser_rotation, constants.TOWER_BARREL)
		
		// Circle shadow
		raylib.DrawCircle(i32(cx + so), i32(cy + so), r, constants.TOWER_SHADOW)
		// Circle body
		raylib.DrawCircle(i32(cx), i32(cy), r, constants.TOWER_LASER_CORE)
		// Inner white glow
		raylib.DrawCircle(i32(cx), i32(cy), r * 0.4, raylib.Color{255, 255, 255, 180})
		
	case .CANNON:
		// Barrel shadow - rotated using DrawRectanglePro with pivot at tower center
		barrel_w := cs * 0.16
		barrel_h := cs * 0.4
		barrel_rect := raylib.Rectangle{
			x = f32(cx + so),
			y = f32(cy + so),
			width = f32(barrel_w),
			height = f32(barrel_h),
		}
		origin := raylib.Vector2{f32(barrel_w/2), f32(barrel_h)}
		cannon_rotation := rotation * 180.0 / math.PI
		raylib.DrawRectanglePro(barrel_rect, origin, cannon_rotation, constants.TOWER_SHADOW)
		
		// Barrel - rotated using DrawRectanglePro with pivot at tower center
		barrel_rect = raylib.Rectangle{
			x = f32(cx),
			y = f32(cy),
			width = f32(barrel_w),
			height = f32(barrel_h),
		}
		raylib.DrawRectanglePro(barrel_rect, origin, cannon_rotation, constants.TOWER_BARREL)
		
		// Circle shadow
		raylib.DrawCircle(i32(cx + so), i32(cy + so), r * 0.8, constants.TOWER_SHADOW)
		// Circle body at center
		raylib.DrawCircle(i32(cx), i32(cy), r * 0.8, stroke)

	case .SNIPER:
		// Thin barrel shadow - rotated using DrawRectanglePro with pivot at tower center
		barrel_w := cs * 0.16
		barrel_h := cs * 0.45
		barrel_rect := raylib.Rectangle{
			x = f32(cx + so),
			y = f32(cy + so),
			width = f32(barrel_w),
			height = f32(barrel_h),
		}
		origin := raylib.Vector2{f32(barrel_w/2), f32(barrel_h)}
		sniper_rotation := rotation * 180.0 / math.PI
		raylib.DrawRectanglePro(barrel_rect, origin, sniper_rotation, constants.TOWER_SHADOW)
		
		// Thin barrel - rotated using DrawRectanglePro with pivot at tower center
		barrel_rect = raylib.Rectangle{
			x = f32(cx),
			y = f32(cy),
			width = f32(barrel_w),
			height = f32(barrel_h),
		}
		raylib.DrawRectanglePro(barrel_rect, origin, sniper_rotation, constants.TOWER_BARREL)
		
		// Circle shadow
		raylib.DrawCircle(i32(cx + so), i32(cy + so), r * 0.8, constants.TOWER_SHADOW)
		// Circle body
		raylib.DrawCircle(i32(cx), i32(cy), r * 0.8, stroke)
		
	case .MISSILE:
		pod_w := r * 0.8
		pod_h := r * 1.6
		pod_color := constants.TOWER_MISSILE_POD
		
		// Rotation in degrees for DrawRectanglePro (matching JS: angle + PI/2)
		missile_rotation_deg := rotation * 180.0 / math.PI
		
		// In JS, pods are drawn at (-r*1.4, -r*0.8) and (r*0.6, -r*0.8) in rotated space
		// We need to transform these local offsets to world positions using rotation
		
		// Left pod local offset: (-r*1.4, -r*0.8) relative to center, in rotated space
		left_local_x := -r * 1.4
		left_local_y := -r * 0.8
		// Right pod local offset: (r*0.6, -r*0.8) relative to center, in rotated space  
		right_local_x := r * 0.6
		right_local_y := -r * 0.8
		
		// Transform to world coordinates (rotate local offsets by the tower rotation)
		left_world_x := cx + left_local_x * math.cos(rotation) - left_local_y * math.sin(rotation)
		left_world_y := cy + left_local_x * math.sin(rotation) + left_local_y * math.cos(rotation)
		right_world_x := cx + right_local_x * math.cos(rotation) - right_local_y * math.sin(rotation)
		right_world_y := cy + right_local_x * math.sin(rotation) + right_local_y * math.cos(rotation)
		
		// Pod origin at top-left corner (0,0) since we position the rect at its world position
		pod_origin := raylib.Vector2{0, 0}
		
		// Left pod shadow
		raylib.DrawRectanglePro(
			raylib.Rectangle{f32(left_world_x + so), f32(left_world_y + so), pod_w, pod_h},
			pod_origin, missile_rotation_deg, constants.TOWER_SHADOW,
		)
		
		// Right pod shadow
		raylib.DrawRectanglePro(
			raylib.Rectangle{f32(right_world_x + so), f32(right_world_y + so), pod_w, pod_h},
			pod_origin, missile_rotation_deg, constants.TOWER_SHADOW,
		)
		
		// Left pod
		raylib.DrawRectanglePro(
			raylib.Rectangle{f32(left_world_x), f32(left_world_y), pod_w, pod_h},
			pod_origin, missile_rotation_deg, pod_color,
		)
		
		// Right pod
		raylib.DrawRectanglePro(
			raylib.Rectangle{f32(right_world_x), f32(right_world_y), pod_w, pod_h},
			pod_origin, missile_rotation_deg, pod_color,
		)
		
	case .ARCHER:
		// Crossbow-style barrel - rotated using DrawRectanglePro with pivot at tower center
		barrel_w := cs * 0.12
		barrel_h := cs * 0.4
		
		// Barrel shadow - positioned at tower center + offset, origin at bottom center
		barrel_rect := raylib.Rectangle{
			x = f32(cx + so),
			y = f32(cy + so),
			width = f32(barrel_w),
			height = f32(barrel_h),
		}
		origin := raylib.Vector2{f32(barrel_w/2), f32(barrel_h)}  // Pivot at bottom of barrel (tower center)
		archer_rotation := rotation * 180.0 / math.PI
		raylib.DrawRectanglePro(barrel_rect, origin, archer_rotation, constants.TOWER_SHADOW)
		
		// Barrel (main body) - positioned at tower center, origin at bottom center
		barrel_rect = raylib.Rectangle{
			x = f32(cx),
			y = f32(cy),
			width = f32(barrel_w),
			height = f32(barrel_h),
		}
		raylib.DrawRectanglePro(barrel_rect, origin, archer_rotation, constants.TOWER_ARCHER_WOOD)
	}
}

// Render tower for simulation (calls unified function with rotation)
render_tower :: proc(app: ^entities.App_State, tower: ^entities.Tower, x, y, cs: f32) {
	// Draw range outline first (so it appears behind the tower)
	spec := constants.TOWER_SPECS[tower.type]
	center_x := x + cs / 2
	center_y := y + cs / 2
	range_px := spec.range * cs
	
	// Draw range circle outline
	raylib.DrawCircleLines(i32(center_x), i32(center_y), range_px, constants.TOWER_RANGE_OUTLINE)
	
	// Draw tower
	draw_tower_tile(x, y, cs, tower.type, tower.angle, false)
	// Draw upgrade indicators on top
	render_tower_upgrades(tower, x, y, cs)
}

// Render reticle for selected cell (corner brackets style like JS)
render_reticle :: proc(x, y, cs: f32, color: raylib.Color) {
	reticle_size := cs * 0.7
	reticle_len := cs * 0.15
	corner_thickness := max(2, cs * 0.04)
	
	// Center position
	cx := x + cs / 2
	cy := y + cs / 2
	
	// Left side
	rx := cx - reticle_size / 2
	ry := cy - reticle_size / 2
	
	// Top-left corner (horizontal + vertical)
	raylib.DrawLineEx(raylib.Vector2{f32(rx), f32(ry)}, raylib.Vector2{f32(rx + reticle_len), f32(ry)}, f32(corner_thickness), color)
	raylib.DrawLineEx(raylib.Vector2{f32(rx), f32(ry)}, raylib.Vector2{f32(rx), f32(ry + reticle_len)}, f32(corner_thickness), color)
	
	// Top-right corner
	raylib.DrawLineEx(raylib.Vector2{f32(rx + reticle_size - reticle_len), f32(ry)}, raylib.Vector2{f32(rx + reticle_size), f32(ry)}, f32(corner_thickness), color)
	raylib.DrawLineEx(raylib.Vector2{f32(rx + reticle_size), f32(ry)}, raylib.Vector2{f32(rx + reticle_size), f32(ry + reticle_len)}, f32(corner_thickness), color)
	
	// Bottom-left corner
	raylib.DrawLineEx(raylib.Vector2{f32(rx), f32(ry + reticle_size - reticle_len)}, raylib.Vector2{f32(rx), f32(ry + reticle_size)}, f32(corner_thickness), color)
	raylib.DrawLineEx(raylib.Vector2{f32(rx), f32(ry + reticle_size)}, raylib.Vector2{f32(rx + reticle_len), f32(ry + reticle_size)}, f32(corner_thickness), color)
	
	// Bottom-right corner
	raylib.DrawLineEx(raylib.Vector2{f32(rx + reticle_size), f32(ry + reticle_size - reticle_len)}, raylib.Vector2{f32(rx + reticle_size), f32(ry + reticle_size)}, f32(corner_thickness), color)
	raylib.DrawLineEx(raylib.Vector2{f32(rx + reticle_size - reticle_len), f32(ry + reticle_size)}, raylib.Vector2{f32(rx + reticle_size), f32(ry + reticle_size)}, f32(corner_thickness), color)
}

// Tower control panel state
tower_panel_active: bool = false
tower_panel_strategy_active: i32 = 0  // 0 = FIRST, 1 = LAST, 2 = MAX_HP, 3 = MIN_HP

// Render tower control panel
render_tower_control_panel :: proc(app: ^entities.App_State) {
	// Only show if a tower is selected
	if app.selected_tower == nil {
		tower_panel_active = false
		return
	}
	
	tower := app.selected_tower
	
	// Panel dimensions
	panel_width: i32 = constants.UI_PANEL_WIDTH
	button_width := panel_width - 20
	button_height: i32 = 30
	spacing: i32 = 5
	section_spacing: i32 = 15
	
	// Calculate panel height dynamically (without title):
	// Tower info (25) + 3 upgrade buttons with spacing + exit button + section spacing + dropdown (40) + section spacing + sell button + padding
	// sell_y calculation: start_y(40) + 4*35 + 15 + 40 + 15 = 40 + 140 + 70 = 250, then +30 for button + 15 padding = constants.UI_PANEL_HEIGHT
	panel_height: i32 = constants.UI_PANEL_HEIGHT
	
	panel_x := raylib.GetScreenWidth() - panel_width - 10
	panel_y := i32(150)
	
	// Draw panel background
	raylib.DrawRectangle(panel_x, panel_y, panel_width, panel_height, raylib.RAYWHITE)
	
	// Tower info (at top, no title)
	type_name := ""
	switch tower.type {
	case .ARCHER: type_name = "Archer"
	case .CANNON: type_name = "Cannon"
	case .SNIPER: type_name = "Sniper"
	case .MISSILE: type_name = "Missile"
	case .LASER: type_name = "Laser"
	}
	
	info_text := fmt.tprintf("%s (%d)", type_name, tower.level)
	info_cstr := strings.clone_to_cstring(info_text)
	raylib.DrawTextEx(constants.game_fonts.bold, info_cstr, {f32(panel_x + 10), f32(panel_y + 10)}, 22, 0, constants.PANEL_TEXT_COLOR)
	
	// Button position calculations
	button_x := panel_x + 10
	start_y := panel_y + 40
	
	// Upgrade Damage button (position 0)
	damage_cost := constants.UPGRADE_COST_BASE + (tower.damage_level - 1) * constants.UPGRADE_COST_INCREMENTVEL
	damage_text := fmt.tprintf("Damage ($%d)", damage_cost)
	can_afford_damage := app.sim.money >= damage_cost
	
	if render_button(damage_text, {f32(button_x), f32(start_y), f32(button_width), f32(button_height)}) && can_afford_damage {
		entities.tower_upgrade_damage(tower)
		app.sim.money -= damage_cost
	}
	
	// Upgrade Speed button (position 1)
	speed_cost := constants.UPGRADE_COST_BASE + (tower.rate_level - 1) * constants.UPGRADE_COST_INCREMENTVEL
	speed_text := fmt.tprintf("Speed ($%d)", speed_cost)
	can_afford_speed := app.sim.money >= speed_cost
	
	if render_button(speed_text, {f32(button_x), f32(start_y + button_height + spacing), f32(button_width), f32(button_height)}) && can_afford_speed {
		entities.tower_upgrade_rate(tower)
		app.sim.money -= speed_cost
	}
	
	// Upgrade Critical button (position 2)
	crit_cost := constants.UPGRADE_COST_BASE + (tower.critical_level - 1) * constants.UPGRADE_COST_INCREMENTVEL
	crit_text := fmt.tprintf("Critical ($%d)", crit_cost)
	can_afford_crit := app.sim.money >= crit_cost
	
	if render_button(crit_text, {f32(button_x), f32(start_y + (button_height + spacing) * 2), f32(button_width), f32(button_height)}) && can_afford_crit {
		entities.tower_upgrade_critical(tower)
		app.sim.money -= crit_cost
	}
	
	// Exit button
	if render_button("Exit", {f32(button_x), f32(start_y + (button_height + spacing) * 3), f32(button_width), f32(button_height)}) {
		app.should_quit = true
	}
	
	// Strategy section with GuiComboBox (position 3)
	strategy_y := start_y + (button_height + spacing) * 4 + section_spacing
	
	// Strategy selector using render_select
	strategy_names := []string{"First", "Last", "Strong", "Weak"}
	strategy_index := i32(tower.target_strategy)
	
	if render_select("strategy", "Target: ", strategy_names, &strategy_index, button_x, i32(strategy_y), button_width, 30, true) {
		tower.target_strategy = constants.Target_Strategy(strategy_index)
	}
	
	// Delete/Sell button at the bottom (position 4, with extra spacing)
	refund := entities.tower_get_sell_refund(tower)
	delete_text := fmt.tprintf("Sell ($%d)", refund)
	sell_y := strategy_y + 40 + section_spacing
	
	if render_button(delete_text, {f32(button_x), f32(sell_y), f32(button_width), f32(button_height)}, 2) {
		simulation_remove_tower_at(app, tower.r, tower.c)
		return  // Tower removed, exit panel
	}
}

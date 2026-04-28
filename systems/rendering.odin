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
	render_paths(app, cs, i32(gs))
	
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
					render_tower_preview(x, y, cs, tower_type)
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
	render_obstacles(app, cs, i32(gs))
	
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
	}
	
	// Draw reticle for selected tower in PLAYING/PAUSED modes
	if app.selected_tower != nil && (app.state == .PLAYING || app.state == .PAUSED) {
		sx := f32(app.selected_tower.c) * cs + f32(app.camera_offset_x)
		sy := f32(app.selected_tower.r) * cs + f32(app.camera_offset_y)
		render_reticle(sx, sy, cs, constants.TOWER_RETICLE_COLOR)
	}
}

// Render paths
render_paths :: proc(app: ^entities.App_State, cs: f32, gs: i32) {
	m := &app.editor.game_map
	path_width := cs * 0.6
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
			
			x := f32(col) * cs + f32(app.camera_offset_x)
			y := f32(row) * cs + f32(app.camera_offset_y)
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

// Render tower upgrades (small dots)
render_tower_upgrades :: proc(tower: ^entities.Tower, x, y, cs: f32) {
	dot_radius := cs * 0.08
	dot_offset := cs * 0.15
	
	// Damage upgrades (red dots on top)
	for i in 0..<tower.damage_level - 1 {
		dot_x := x + cs * 0.2 + f32(i) * dot_offset
		dot_y := y + cs * 0.15
		raylib.DrawCircle(i32(dot_x), i32(dot_y), dot_radius, raylib.RED)
	}
	
	// Rate upgrades (yellow dots on bottom)
	for i in 0..<tower.rate_level - 1 {
		dot_x := x + cs * 0.2 + f32(i) * dot_offset
		dot_y := y + cs * 0.85
		raylib.DrawCircle(i32(dot_x), i32(dot_y), dot_radius, raylib.YELLOW)
	}
	
	// Critical upgrades (blue dots on left)
	for i in 0..<tower.critical_level - 1 {
		dot_x := x + cs * 0.15
		dot_y := y + cs * 0.2 + f32(i) * dot_offset
		raylib.DrawCircle(i32(dot_x), i32(dot_y), dot_radius, raylib.BLUE)
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
		// Palm tree (desert) - top view: oval fronds
		leaf_radius_x := cs * 0.35
		leaf_radius_y := cs * 0.25
		
		// Palm fronds (ovals)
		raylib.DrawEllipse(i32(center_x), i32(center_y), f32(leaf_radius_x), f32(leaf_radius_y), raylib.Color{34, 139, 34, 255})
		raylib.DrawEllipse(i32(center_x), i32(center_y), f32(leaf_radius_x * 0.7), f32(leaf_radius_y * 0.7), raylib.Color{0, 100, 0, 255})
		
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
		gray(150),
	)
}

// Render obstacles
render_obstacles :: proc(app: ^entities.App_State, cs: f32, gs: i32) {
	m := &app.editor.game_map
	
	for row in 0..<gs {
		for col in 0..<gs {
			if m.obstacle_grid[row][col] == .OBSTACLE {
				x := f32(col) * cs + f32(app.camera_offset_x)
				y := f32(row) * cs + f32(app.camera_offset_y)
				
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
		
		raylib.DrawLineEx(
			raylib.Vector2{beam.start_x + f32(app.camera_offset_x), beam.start_y + f32(app.camera_offset_y)},
			raylib.Vector2{beam.end_x + f32(app.camera_offset_x), beam.end_y + f32(app.camera_offset_y)},
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
			// Arrow
			raylib.DrawCircle(i32(x + cs / 2), i32(y + cs / 2), cs * 0.1, raylib.BROWN)
		case .CANNON:
			// Cannonball
			raylib.DrawCircle(i32(x + cs / 2), i32(y + cs / 2), cs * 0.15, raylib.BLACK)
		case .SNIPER:
			// Bullet
			raylib.DrawCircle(i32(x + cs / 2), i32(y + cs / 2), cs * 0.08, raylib.GREEN)
		case .MISSILE:
			// Missile
			raylib.DrawRectangle(
				i32(x + cs / 2 - cs * 0.08),
				i32(y + cs / 2 - cs * 0.2),
				i32(cs * 0.16),
				i32(cs * 0.4),
				raylib.ORANGE,
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
		font_size := i32(cs * 0.4)
		if dn.is_critical {
			font_size = i32(cs * 0.5)
		}
		
		raylib.DrawText(strings.clone_to_cstring(damage_text), i32(x), i32(y), font_size, color)
	}
}

// Render UI
render_ui :: proc(app: ^entities.App_State) {
	switch app.state {
	case .MENU:
		render_menu_ui(app)
	case .PLAYING, .PAUSED:
		render_game_ui(app)
		// Render tower control panel when a tower is selected
		render_tower_control_panel(app)
	case .EDITOR:
		render_editor_ui(app)
	case .GAME_OVER:
		render_game_over_ui(app)
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
	
	// Title
	title := "Tower Defense"
	title_size := 60
	title_cstr := strings.clone_to_cstring(title)
	title_x := screen_width / 2 - raylib.MeasureText(title_cstr, i32(title_size)) / 2
	raylib.DrawText(title_cstr, title_x, screen_height / 4, i32(title_size), raylib.WHITE)
	
	// Buttons (using UI constants)
	menu_button_width := i32(constants.UI_BUTTON_WIDTH)
	menu_button_height := i32(constants.UI_BUTTON_HEIGHT)
	menu_button_x := screen_width / 2 - menu_button_width / 2
	
	// Editor button
	editor_button_y := screen_height / 2
	if render_button(app, "Editor", menu_button_x, editor_button_y, menu_button_width, menu_button_height) {
		entities.app_set_state(app, .EDITOR)
	}
	
	// Exit button
	exit_button_y := editor_button_y + menu_button_height + 10
	if render_button(app, "Exit", menu_button_x, exit_button_y, menu_button_width, menu_button_height) {
		// Signal to quit
	}
}

// Render game UI (HUD)
render_game_ui :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()
	
	// Money
	money_text := fmt.tprintf("Money: $%d", app.sim.money)
	raylib.DrawText(strings.clone_to_cstring(money_text), 10, 40, 20, raylib.GOLD)
	
	// Health
	health_text := fmt.tprintf("Health: %d", app.sim.health)
	raylib.DrawText(strings.clone_to_cstring(health_text), 10, 70, 20, raylib.RED)
	
	// Wave
	wave_text := fmt.tprintf("Wave: %d", app.sim.wave_number)
	raylib.DrawText(strings.clone_to_cstring(wave_text), 10, 100, 20, raylib.WHITE)
	
	// Enemies remaining
	enemies_text := fmt.tprintf("Enemies: %d", len(app.sim.enemies))
	raylib.DrawText(strings.clone_to_cstring(enemies_text), 10, 130, 20, raylib.WHITE)
	
	// Pause button
	pause_text := "PAUSE"
	if app.sim.paused {
		pause_text = "RESUME"
	}
	if render_button(app, pause_text, screen_width - constants.UI_BUTTON_WIDTH - 10, 10, constants.UI_BUTTON_WIDTH, constants.UI_BUTTON_HEIGHT) {
		simulation_toggle_pause(app)
	}
	
	// Speed buttons
	if render_button(app, "1x", screen_width - constants.UI_BUTTON_WIDTH * 2 - 20, 10, constants.UI_BUTTON_WIDTH, constants.UI_BUTTON_HEIGHT) {
		simulation_set_speed(app, 1.0)
	}
	if render_button(app, "2x", screen_width - constants.UI_BUTTON_WIDTH - 10, 10, constants.UI_BUTTON_WIDTH, constants.UI_BUTTON_HEIGHT) {
		simulation_set_speed(app, 2.0)
	}
	
	// Tower build buttons
	tower_types := []constants.Tile{.TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER}
	tower_names := []string{"Archer", "Cannon", "Sniper", "Missile", "Laser"}
	tower_costs := []i32{20, 40, 60, 50, 80}
	
	for i := 0; i < len(tower_types); i += 1 {
		x := i32(10 + i * (constants.UI_BUTTON_WIDTH + 5))
		y := i32(screen_height - constants.UI_BUTTON_HEIGHT - 10)
		
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
		
		// Draw button manually for color control
		raylib.DrawRectangle(x, y, constants.UI_BUTTON_WIDTH, constants.UI_BUTTON_HEIGHT, button_color)
		raylib.DrawRectangleLines(x, y, constants.UI_BUTTON_WIDTH, constants.UI_BUTTON_HEIGHT, raylib.WHITE)
		
		// Text
		name_cstr := strings.clone_to_cstring(tower_names[i])
		text_width := raylib.MeasureText(name_cstr, constants.UI_BUTTON_FONT_SIZE)
		text_x := x + constants.UI_BUTTON_WIDTH / 2 - text_width / 2
		text_y := y + constants.UI_BUTTON_HEIGHT / 2 - constants.UI_BUTTON_FONT_SIZE / 2
		raylib.DrawText(name_cstr, text_x, text_y, constants.UI_BUTTON_FONT_SIZE, raylib.WHITE)
		
		// Click check
		mouse_x := raylib.GetMouseX()
		mouse_y := raylib.GetMouseY()
		hovered := mouse_x >= x && mouse_x <= x + constants.UI_BUTTON_WIDTH &&
		           mouse_y >= y && mouse_y <= y + constants.UI_BUTTON_HEIGHT
		
		if hovered && raylib.IsMouseButtonPressed(.LEFT) && can_afford {
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
	
	// Biome selector using raygui
	biome_text := "Plain;Forest;Desert;Mountain"
	biome_dropdown_bounds := raylib.Rectangle{f32(10), f32(raylib.GetScreenHeight() - constants.UI_TOOLBAR_HEIGHT + 4), constants.UI_DROPDOWN_WIDTH, constants.UI_DROPDOWN_HEIGHT}
	
	// Convert biome enum to i32 index for dropdown
	biome_index := i32(app.editor.current_biome)
	
	if raylib.GuiComboBox(biome_dropdown_bounds, strings.clone_to_cstring(biome_text), &biome_index) != -1 {
		app.editor.current_biome = constants.Biome(biome_index)
		app.editor.game_map.biome = constants.Biome(biome_index)
	}
	
	// Show Paths toggle button
	paths_button_text := app.editor.show_paths ? "Hide Paths" : "Show Paths"
	if render_button(app, paths_button_text, screen_width - 510, raylib.GetScreenHeight() - constants.UI_TOOLBAR_HEIGHT + 4, constants.UI_BUTTON_WIDTH, constants.UI_BUTTON_HEIGHT) {
		app.editor.show_paths = !app.editor.show_paths
	}
	
	// Save button
	if render_button(app, "Save Map", screen_width - 420, raylib.GetScreenHeight() - constants.UI_TOOLBAR_HEIGHT + 4, constants.UI_BUTTON_WIDTH, constants.UI_BUTTON_HEIGHT) {
		// Save with timestamp AND as last_saved.map for quick loading
		filename := fmt.tprintf("map_%d.map", i32(raylib.GetTime()))
		_ = entities.map_save(&app.editor.game_map, filename)
		_ = entities.map_save(&app.editor.game_map, "last_saved.map")
	}
	
	// Load button - loads last_saved.map
	load_bounds := raylib.Rectangle{f32(screen_width - 330), f32(raylib.GetScreenHeight() - constants.UI_TOOLBAR_HEIGHT + 4), constants.UI_BUTTON_WIDTH, constants.UI_BUTTON_HEIGHT}
	if raylib.GuiButton(load_bounds, "Load Map") {
		if entities.map_load(&app.editor.game_map, "last_saved.map") {
			app.editor.current_biome = app.editor.game_map.biome
		}
	}
	
	// Quick load last map button
	quick_load_bounds := raylib.Rectangle{f32(screen_width - 240), f32(raylib.GetScreenHeight() - constants.UI_TOOLBAR_HEIGHT + 4), constants.UI_BUTTON_WIDTH, constants.UI_BUTTON_HEIGHT}
	if raylib.GuiButton(quick_load_bounds, "Quick Load") {
		// Try to load the most recently saved map
		_ = entities.map_load(&app.editor.game_map, "last_saved.map")
	}
	
	// Test button
	if render_button(app, "Test Map", screen_width - 150, raylib.GetScreenHeight() - constants.UI_TOOLBAR_HEIGHT + 4, constants.UI_BUTTON_WIDTH, constants.UI_BUTTON_HEIGHT) {
		if simulation_init_from_editor(app) {
			entities.app_set_state(app, .PLAYING)
		}
	}
	
	// Menu button
	if render_button(app, "Menu", screen_width - 60, raylib.GetScreenHeight() - constants.UI_TOOLBAR_HEIGHT + 4, constants.UI_BUTTON_WIDTH, constants.UI_BUTTON_HEIGHT) {
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
	
	if render_button(app, "Main Menu", button_x, button_y, button_width, button_height) {
		entities.app_set_state(app, .MENU)
	}
}

// Helper to render a button
render_button :: proc(app: ^entities.App_State, text: string, x, y, width, height: i32) -> bool {
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	hovered := mouse_x >= x && mouse_x <= x + width &&
	           mouse_y >= y && mouse_y <= y + height
	
	color := raylib.LIGHTGRAY
	if hovered {
		color = raylib.GRAY
		if raylib.IsMouseButtonDown(.LEFT) {
			color = raylib.DARKGRAY
		}
	}
	
	raylib.DrawRectangle(x, y, width, height, color)
	raylib.DrawRectangleLines(x, y, width, height, raylib.WHITE)
	
	// Text (centered) - using UI font size
	text_width := raylib.MeasureText(strings.clone_to_cstring(text), constants.UI_BUTTON_FONT_SIZE)
	text_x := x + width / 2 - text_width / 2
	text_y := y + height / 2 - constants.UI_BUTTON_FONT_SIZE / 2
	raylib.DrawText(strings.clone_to_cstring(text), text_x, text_y, constants.UI_BUTTON_FONT_SIZE, raylib.WHITE)
	
	// Click check
	if hovered && raylib.IsMouseButtonPressed(.LEFT) {
		return true
	}
	
	return false
}

// Helper for gray color
gray :: proc(value: u8) -> raylib.Color {
	return raylib.Color{value, value, value, 255}
}

// Check if mouse is over tower control panel (to prevent grid clicks)
is_mouse_over_tower_panel :: proc(app: ^entities.App_State) -> bool {
	if app.selected_tower == nil {
		return false
	}
	
	panel_width: i32 = 200
	panel_height: i32 = 255
	panel_x := raylib.GetScreenWidth() - panel_width - 10
	panel_y := i32(150)
	
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	return mouse_x >= panel_x && mouse_x <= panel_x + panel_width &&
	       mouse_y >= panel_y && mouse_y <= panel_y + panel_height
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
		// Barrel shadow - rotated using DrawRectanglePro with pivot at tower center
		barrel_w := cs * 0.2
		barrel_h := cs * 0.5
		barrel_rect := raylib.Rectangle{
			x = f32(cx + so),
			y = f32(cy + so),
			width = f32(barrel_w),
			height = f32(barrel_h),
		}
		origin := raylib.Vector2{f32(barrel_w/2), f32(barrel_h)}  // Pivot at bottom of barrel (tower center)
		laser_rotation := (rotation - math.PI/2) * 180.0 / math.PI
		raylib.DrawRectangleRounded(barrel_rect, 0.05, 4, constants.TOWER_SHADOW)
		
		// Barrel - rotated using DrawRectanglePro with pivot at tower center
		barrel_rect = raylib.Rectangle{
			x = f32(cx),
			y = f32(cy),
			width = f32(barrel_w),
			height = f32(barrel_h),
		}
		raylib.DrawRectangleRounded(barrel_rect, 0.05, 4, constants.TOWER_BARREL)
		
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
		cannon_rotation := (rotation - math.PI/2) * 180.0 / math.PI
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
		sniper_rotation := (rotation - math.PI/2) * 180.0 / math.PI
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
		pod_rad := r * 0.0075
		pod_color := constants.TOWER_MISSILE_POD
		
		// Calculate pod positions in rotated coordinate space (like JS)
		// Left pod at (-r * 1.4, -r * 0.8), Right pod at (r * 0.6, -r * 0.8)
		
		// Left pod shadow
		left_pod_shadow_x := cx + so + (-r*1.4)*math.cos(rotation) - (-r*0.8)*math.sin(rotation)
		left_pod_shadow_y := cy + so + (-r*1.4)*math.sin(rotation) + (-r*0.8)*math.cos(rotation)
		raylib.DrawRectangleRounded(
			raylib.Rectangle{f32(left_pod_shadow_x - pod_w/2), f32(left_pod_shadow_y - pod_h/2), pod_w, pod_h},
			pod_rad, 4, constants.TOWER_SHADOW,
		)
		
		// Right pod shadow
		right_pod_shadow_x := cx + so + (r*0.6)*math.cos(rotation) - (-r*0.8)*math.sin(rotation)
		right_pod_shadow_y := cy + so + (r*0.6)*math.sin(rotation) + (-r*0.8)*math.cos(rotation)
		raylib.DrawRectangleRounded(
			raylib.Rectangle{f32(right_pod_shadow_x - pod_w/2), f32(right_pod_shadow_y - pod_h/2), pod_w, pod_h},
			pod_rad, 4, constants.TOWER_SHADOW,
		)
		
		// Left pod
		left_pod_x := cx + (-r*1.4)*math.cos(rotation) - (-r*0.8)*math.sin(rotation)
		left_pod_y := cy + (-r*1.4)*math.sin(rotation) + (-r*0.8)*math.cos(rotation)
		raylib.DrawRectangleRounded(
			raylib.Rectangle{f32(left_pod_x - pod_w/2), f32(left_pod_y - pod_h/2), pod_w, pod_h},
			pod_rad, 4, pod_color,
		)
		
		// Right pod
		right_pod_x := cx + (r*0.6)*math.cos(rotation) - (-r*0.8)*math.sin(rotation)
		right_pod_y := cy + (r*0.6)*math.sin(rotation) + (-r*0.8)*math.cos(rotation)
		raylib.DrawRectangleRounded(
			raylib.Rectangle{f32(right_pod_x - pod_w/2), f32(right_pod_y - pod_h/2), pod_w, pod_h},
			pod_rad, 4, pod_color,
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
		archer_rotation := (rotation + math.PI/2) * 180.0 / math.PI
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

// Render tower preview for editor (calls unified function)
render_tower_preview :: proc(x, y: f32, cs: f32, tower_type: constants.Tower_Type) {
	draw_tower_tile(x, y, cs, tower_type, 0, false)
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
	panel_width: i32 = 200
	button_width := panel_width - 20
	button_height: i32 = 30
	spacing: i32 = 5
	section_spacing: i32 = 15
	
	// Calculate panel height dynamically (without title):
	// Tower info (25) + 3 upgrade buttons with spacing + section spacing + dropdown (40) + section spacing + sell button + padding
	// sell_y calculation: start_y(40) + 3*35 + 15 + 40 + 15 = 40 + 105 + 70 = 210, then +30 for button + 15 padding = 255
	panel_height: i32 = 255
	
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
	
	info_text := fmt.tprintf("%s (Lvl %d)", type_name, tower.level)
	info_cstr := strings.clone_to_cstring(info_text)
	raylib.DrawText(info_cstr, panel_x + 10, panel_y + 10, 14, raylib.LIGHTGRAY)
	
	// Button position calculations
	button_x := panel_x + 10
	start_y := panel_y + 40
	
	// Upgrade Damage button (position 0)
	damage_cost := constants.UPGRADE_COST_BASE + (tower.damage_level - 1) * constants.UPGRADE_COST_INCREMENTVEL
	damage_text := fmt.tprintf("Damage ($%d)", damage_cost)
	can_afford_damage := app.sim.money >= damage_cost
	
	if render_button(app, damage_text, button_x, start_y, button_width, button_height) && can_afford_damage {
		entities.tower_upgrade_damage(tower)
		app.sim.money -= damage_cost
	}
	
	// Upgrade Speed button (position 1)
	speed_cost := constants.UPGRADE_COST_BASE + (tower.rate_level - 1) * constants.UPGRADE_COST_INCREMENTVEL
	speed_text := fmt.tprintf("Speed ($%d)", speed_cost)
	can_afford_speed := app.sim.money >= speed_cost
	
	if render_button(app, speed_text, button_x, start_y + button_height + spacing, button_width, button_height) && can_afford_speed {
		entities.tower_upgrade_rate(tower)
		app.sim.money -= speed_cost
	}
	
	// Upgrade Critical button (position 2)
	crit_cost := constants.UPGRADE_COST_BASE + (tower.critical_level - 1) * constants.UPGRADE_COST_INCREMENTVEL
	crit_text := fmt.tprintf("Critical ($%d)", crit_cost)
	can_afford_crit := app.sim.money >= crit_cost
	
	if render_button(app, crit_text, button_x, start_y + (button_height + spacing) * 2, button_width, button_height) && can_afford_crit {
		entities.tower_upgrade_critical(tower)
		app.sim.money -= crit_cost
	}
	
	// Exit button
	if render_button(app, "Exit", button_x, start_y + (button_height + spacing) * 3, button_width, button_height) {
		app.should_quit = true
	}
	
	// Strategy section with GuiComboBox (position 3)
	strategy_y := start_y + (button_height + spacing) * 4 + section_spacing
	
	// Strategy dropdown using raygui
	strategy_text := "First;Last;Strong;Weak"
	strategy_dropdown_bounds := raylib.Rectangle{
		f32(button_x),
		f32(strategy_y),
		f32(button_width),
		f32(30),
	}
	
	// Convert strategy enum to i32 index
	strategy_index := i32(tower.target_strategy)
	
	if raylib.GuiComboBox(strategy_dropdown_bounds, strings.clone_to_cstring(strategy_text), &strategy_index) != -1 {
		tower.target_strategy = constants.Target_Strategy(strategy_index)
	}
	
	// Delete/Sell button at the bottom (position 4, with extra spacing)
	refund := entities.tower_get_sell_refund(tower)
	delete_text := fmt.tprintf("Sell ($%d)", refund)
	sell_y := strategy_y + 40 + section_spacing
	
	if render_button(app, delete_text, button_x, sell_y, button_width, button_height) {
		simulation_remove_tower_at(app, tower.r, tower.c)
		return  // Tower removed, exit panel
	}
}

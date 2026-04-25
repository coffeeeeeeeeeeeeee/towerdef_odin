package systems

import "core:math"
import "core:fmt"
import "vendor:raylib"
import "../constants"
import "../entities"
import "../game"

// Render the entire game
render_game :: proc() {
	render_map()
	render_gameplay()
	render_ui()
}

// Render map (grid, paths, obstacles)
render_map :: proc() {
	m := &game.app.editor.map
	cs := f32(game.app.settings.cell_size)
	gs := constants.GRID_SIZE
	
	// Background
	biome_colors := constants.BIOME_COLORS[m.biome]
	raylib.ClearBackground(biome_colors.bg)
	
	// Fill grid background
	total_size := f32(gs) * cs
	raylib.DrawRectangle(
		i32(game.app.camera_offset_x),
		i32(game.app.camera_offset_y),
		i32(total_size),
		i32(total_size),
		biome_colors.bg_grid,
	)
	
	// Draw paths
	render_paths(cs, gs)
	
	// Draw gameplay tiles (towers, accessories)
	for row in 0..<gs {
		for col in 0..<gs {
			tile := m.grid[row][col]
			x := f32(col) * cs + f32(game.app.camera_offset_x)
			y := f32(row) * cs + f32(game.app.camera_offset_y)
			
			switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
				// Find corresponding tower
				for &tower in game.app.sim.towers {
					if tower.r == row && tower.c == col {
						render_tower(&tower, x, y, cs)
						break
					}
				}
				
			case .SPAWN:
				render_spawn(x, y, cs)
				
			case .GOAL:
				render_goal(x, y, cs)
				
			case .ACCESSORY_TREE:
				render_tree(x, y, cs)
				
			case .ACCESSORY_BLOCK:
				render_block(x, y, cs)
			}
		}
	}
	
	// Draw obstacles
	render_obstacles(cs, gs)
	
	// Draw laser beams (on top of everything)
	if game.app.state == .PLAYING || (game.app.state == .PAUSED && game.app.previous_state == .PLAYING) {
		render_laser_beams(cs)
	}
	
	// Grid lines
	if game.app.settings.show_grid {
		render_grid_lines(cs, gs)
	}
}

// Render paths
render_paths :: proc(cs: f32, gs: i32) {
	m := &game.app.editor.map
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
			
			x := f32(col) * cs + f32(game.app.camera_offset_x)
			y := f32(row) * cs + f32(game.app.camera_offset_y)
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
render_grid_lines :: proc(cs: f32, gs: i32) {
	for i in 0..=gs {
		x := i32(f32(i) * cs) + game.app.camera_offset_x
		y := i32(f32(i) * cs) + game.app.camera_offset_y
		
		// Vertical
		raylib.DrawLine(x, game.app.camera_offset_y, x, game.app.camera_offset_y + i32(f32(gs) * cs), constants.COLOR_GRID_LINE)
		
		// Horizontal
		raylib.DrawLine(game.app.camera_offset_x, y, game.app.camera_offset_x + i32(f32(gs) * cs), y, constants.COLOR_GRID_LINE)
	}
}

// Render tower
render_tower :: proc(tower: ^entities.Tower, x, y, cs: f32) {
	// Get tower color from type
	tower_color := tower_type_to_color(tower.type)
	
	// Draw base
	raylib.DrawRectangle(
		i32(x + cs * 0.1),
		i32(y + cs * 0.1),
		i32(cs * 0.8),
		i32(cs * 0.8),
		gray(100),
	)
	
	// Draw cannon
	center_x := x + cs / 2
	center_y := y + cs / 2
	cannon_length := cs * 0.45
	
	end_x := center_x + math.cos(tower.angle) * cannon_length
	end_y := center_y + math.sin(tower.angle) * cannon_length
	
	raylib.DrawLineEx(
		raylib.Vector2{center_x, center_y},
		raylib.Vector2{end_x, end_y},
		cs * 0.15,
		tower_color,
	)
	
	// Draw tower icon/center
	raylib.DrawCircle(
		i32(center_x),
		i32(center_y),
		cs * 0.25,
		tower_color,
	)
	
	// Draw upgrade indicators
	render_tower_upgrades(tower, x, y, cs)
}

// Helper to get tower spec color
tower_type_to_color :: proc(t: constants.tower_type) -> raylib.Color {
	switch t {
	case .ARCHER: return constants.TOWER_SPECS[.TOWER_ARCHER].color
	case .CANNON: return constants.TOWER_SPECS[.TOWER_CANNON].color
	case .SNIPER: return constants.TOWER_SPECS[.TOWER_SNIPER].color
	case .MISSILE: return constants.TOWER_SPECS[.TOWER_MISSILE].color
	case .LASER: return constants.TOWER_SPECS[.TOWER_LASER].color
	}
	return raylib.GRAY
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
	raylib.DrawCircle(i32(center_x), i32(center_y), cs * 0.25, raylib.WHITE)
	raylib.DrawText("S", i32(center_x - cs * 0.1), i32(center_y - cs * 0.15), i32(cs * 0.3), raylib.BLACK)
}

// Render goal
render_goal :: proc(x, y, cs: f32) {
	center_x := x + cs / 2
	center_y := y + cs / 2
	
	raylib.DrawCircle(i32(center_x), i32(center_y), cs * 0.4, constants.COLOR_GOAL)
	raylib.DrawCircle(i32(center_x), i32(center_y), cs * 0.25, raylib.WHITE)
	raylib.DrawText("G", i32(center_x - cs * 0.1), i32(center_y - cs * 0.15), i32(cs * 0.3), raylib.BLACK)
}

// Render tree accessory
render_tree :: proc(x, y, cs: f32) {
	// Trunk
	trunk_width := cs * 0.2
	trunk_height := cs * 0.3
	trunk_x := x + cs / 2 - trunk_width / 2
	trunk_y := y + cs * 0.5
	
	raylib.DrawRectangle(
		i32(trunk_x),
		i32(trunk_y),
		i32(trunk_width),
		i32(trunk_height),
		constants.COLOR_TREE_TRUNK,
	)
	
	// Leaves (three circles)
	leaf_radius := cs * 0.25
	center_x := x + cs / 2
	center_y := y + cs * 0.4
	
	raylib.DrawCircle(i32(center_x), i32(center_y), leaf_radius, constants.COLOR_TREE_LEAVES)
	raylib.DrawCircle(i32(center_x - leaf_radius * 0.6), i32(center_y + leaf_radius * 0.3), leaf_radius * 0.8, constants.COLOR_TREE_LEAVES)
	raylib.DrawCircle(i32(center_x + leaf_radius * 0.6), i32(center_y + leaf_radius * 0.3), leaf_radius * 0.8, constants.COLOR_TREE_LEAVES)
}

// Render block accessory
render_block :: proc(x, y, cs: f32) {
	raylib.DrawRectangle(
		i32(x + cs * 0.1),
		i32(y + cs * 0.1),
		i32(cs * 0.8),
		i32(cs * 0.8),
		constants.COLOR_BLOCK,
	)
	
	// Highlight
	raylib.DrawRectangle(
		i32(x + cs * 0.15),
		i32(y + cs * 0.15),
		i32(cs * 0.3),
		i32(cs * 0.3),
		gray(150),
	)
}

// Render obstacles
render_obstacles :: proc(cs: f32, gs: i32) {
	m := &game.app.editor.map
	
	for row in 0..<gs {
		for col in 0..<gs {
			if m.obstacle_grid[row][col] == .OBSTACLE {
				x := f32(col) * cs + f32(game.app.camera_offset_x)
				y := f32(row) * cs + f32(game.app.camera_offset_y)
				
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
						level_text,
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
render_laser_beams :: proc(cs: f32) {
	sim := &game.app.sim
	
	for &beam in sim.laser_beams {
		alpha := beam.duration / beam.max_duration
		color := raylib.Color{
			255,
			68,
			68,
			u8(255 * alpha),
		}
		
		raylib.DrawLineEx(
			raylib.Vector2{beam.start_x + f32(game.app.camera_offset_x), beam.start_y + f32(game.app.camera_offset_y)},
			raylib.Vector2{beam.end_x + f32(game.app.camera_offset_x), beam.end_y + f32(game.app.camera_offset_y)},
			3.0,
			color,
		)
	}
}

// Render gameplay elements (enemies, projectiles, effects)
render_gameplay :: proc() {
	if game.app.state != .PLAYING && game.app.state != .PAUSED {
		return
	}
	
	cs := f32(game.app.settings.cell_size)
	
	// Render enemies
	render_enemies(cs)
	
	// Render projectiles
	render_projectiles(cs)
	
	// Render explosions
	render_explosions(cs)
	
	// Render damage numbers
	render_damage_numbers(cs)
}

// Render enemies
render_enemies :: proc(cs: f32) {
	for &enemy in game.app.sim.enemies {
		x := enemy.x * cs + f32(game.app.camera_offset_x)
		y := enemy.y * cs + f32(game.app.camera_offset_y)
		
		size := entities.enemy_get_size(&enemy) * cs
		color := entities.enemy_get_color(&enemy)
		
		// Draw enemy body
		raylib.DrawCircle(i32(x + cs / 2), i32(y + cs / 2), size, color)
		
		// Draw flying indicator
		if enemy.is_flying {
			raylib.DrawCircle(i32(x + cs / 2), i32(y + cs / 2 - size * 0.5), size * 0.3, raylib.WHITE)
		}
		
		// Health bar background
		hp_percent := enemy.hp / enemy.max_hp
		hp_bar_width := cs * 0.8
		hp_bar_height := cs * 0.1
		hp_bar_x := x + cs / 2 - hp_bar_width / 2
		hp_bar_y := y + cs * 0.1
		
		raylib.DrawRectangle(
			i32(hp_bar_x),
			i32(hp_bar_y),
			i32(hp_bar_width),
			i32(hp_bar_height),
			raylib.DARKGRAY,
		)
		
		// Health bar fill
		if hp_percent > 0 {
			hp_color := raylib.GREEN
			if hp_percent < 0.3 {
				hp_color = raylib.RED
			} else if hp_percent < 0.6 {
				hp_color = raylib.YELLOW
			}
			
			raylib.DrawRectangle(
				i32(hp_bar_x),
				i32(hp_bar_y),
				i32(hp_bar_width * hp_percent),
				i32(hp_bar_height),
				hp_color,
			)
		}
	}
}

// Render projectiles
render_projectiles :: proc(cs: f32) {
	for &proj in game.app.sim.projectiles {
		x := proj.x * cs + f32(game.app.camera_offset_x)
		y := proj.y * cs + f32(game.app.camera_offset_y)
		
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
render_explosions :: proc(cs: f32) {
	for &explosion in game.app.sim.explosions {
		x := explosion.x * cs + f32(game.app.camera_offset_x)
		y := explosion.y * cs + f32(game.app.camera_offset_y)
		
		radius := explosion.radius * cs
		alpha := u8(255 * (explosion.life / explosion.max_life))
		
		color := raylib.Color{255, 100, 50, alpha}
		
		raylib.DrawCircle(i32(x + cs / 2), i32(y + cs / 2), radius, color)
	}
}

// Render damage numbers
render_damage_numbers :: proc(cs: f32) {
	for &dn in game.app.sim.damage_numbers {
		x := dn.x * cs + f32(game.app.camera_offset_x)
		y := dn.y * cs + f32(game.app.camera_offset_y)
		
		alpha := u8(255 * dn.life)
		color := dn.color
		color.a = alpha
		
		damage_text := fmt.tprintf("%.0f", dn.value)
		font_size := i32(cs * 0.4)
		if dn.is_critical {
			font_size = i32(cs * 0.5)
		}
		
		raylib.DrawText(damage_text, i32(x), i32(y), font_size, color)
	}
}

// Render UI
render_ui :: proc() {
	switch game.app.state {
	case .MENU:
		render_menu_ui()
	case .PLAYING, .PAUSED:
		render_game_ui()
	case .EDITOR:
		render_editor_ui()
	case .GAME_OVER:
		render_game_over_ui()
	}
	
	// FPS counter
	if game.app.settings.show_fps {
		fps_text := fmt.tprintf("FPS: %d", raylib.GetFPS())
		raylib.DrawText(fps_text, 10, 10, 20, raylib.WHITE)
	}
}

// Render menu UI
render_menu_ui :: proc() {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()
	
	// Title
	title := "Tower Defense"
	title_size := 60
	title_x := screen_width / 2 - raylib.MeasureText(title, i32(title_size)) / 2
	raylib.DrawText(title, title_x, screen_height / 4, i32(title_size), raylib.WHITE)
	
	// Buttons
	button_width := 200
	button_height := 50
	button_x := screen_width / 2 - button_width / 2
	
	// Start button
	start_y := screen_height / 2
	if render_button("Start Game", button_x, start_y, button_width, button_height) {
		game.app_set_state(.EDITOR)
	}
	
	// Exit button
	exit_y := start_y + button_height + 20
	if render_button("Exit", button_x, exit_y, button_width, button_height) {
		// Signal to quit
	}
}

// Render game UI (HUD)
render_game_ui :: proc() {
	// Money
	money_text := fmt.tprintf("Money: $%d", game.app.sim.money)
	raylib.DrawText(money_text, 10, 40, 20, raylib.GOLD)
	
	// Health
	health_text := fmt.tprintf("Health: %d", game.app.sim.health)
	raylib.DrawText(health_text, 10, 70, 20, raylib.RED)
	
	// Wave
	wave_text := fmt.tprintf("Wave: %d", game.app.sim.wave_number)
	raylib.DrawText(wave_text, 10, 100, 20, raylib.WHITE)
	
	// Enemies remaining
	enemies_text := fmt.tprintf("Enemies: %d", len(game.app.sim.enemies))
	raylib.DrawText(enemies_text, 10, 130, 20, raylib.WHITE)
	
	// Pause button
	pause_text := "PAUSE"
	if game.app.sim.paused {
		pause_text = "RESUME"
	}
	if render_button(pause_text, raylib.GetScreenWidth() - 110, 10, 100, 40) {
		simulation_toggle_pause()
	}
	
	// Speed buttons
	if render_button("1x", raylib.GetScreenWidth() - 220, 10, 50, 40) {
		simulation_set_speed(1.0)
	}
	if render_button("2x", raylib.GetScreenWidth() - 165, 10, 50, 40) {
		simulation_set_speed(2.0)
	}
}

// Render editor UI
render_editor_ui :: proc() {
	// Toolbar background
	screen_width := raylib.GetScreenWidth()
	raylib.DrawRectangle(0, 0, screen_width, 60, raylib.Color{50, 50, 50, 200})
	
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
	
	button_width := 80
	button_height := 40
	margin := 10
	
	for tool, i in tools {
		x := margin + i * (button_width + margin)
		y := 10
		
		is_selected := game.app.editor.current_tool == tool.tile
		color := raylib.DARKGRAY
		if is_selected {
			color = raylib.BLUE
		}
		
		raylib.DrawRectangle(i32(x), i32(y), button_width, button_height, color)
		raylib.DrawText(tool.name, i32(x + 5), i32(y + 10), 15, raylib.WHITE)
	}
	
	// Bottom toolbar
	raylib.DrawRectangle(0, raylib.GetScreenHeight() - 60, screen_width, 60, raylib.Color{50, 50, 50, 200})
	
	// Biome selector
	raylib.DrawText("Biome:", 10, raylib.GetScreenHeight() - 50, 20, raylib.WHITE)
	
	// Test button
	if render_button("Test Map", screen_width - 120, raylib.GetScreenHeight() - 50, 100, 40) {
		if game.simulation_init_from_editor() {
			game.app_set_state(.PLAYING)
		}
	}
	
	// Menu button
	if render_button("Menu", screen_width - 230, raylib.GetScreenHeight() - 50, 100, 40) {
		game.app_set_state(.MENU)
	}
}

// Render game over UI
render_game_over_ui :: proc() {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()
	
	// Semi-transparent overlay
	raylib.DrawRectangle(0, 0, screen_width, screen_height, raylib.Color{0, 0, 0, 200})
	
	// Game Over text
	title := "GAME OVER"
	title_size := 60
	title_x := screen_width / 2 - raylib.MeasureText(title, i32(title_size)) / 2
	raylib.DrawText(title, title_x, screen_height / 3, i32(title_size), raylib.RED)
	
	// Wave survived
	wave_text := fmt.tprintf("You survived %d waves", game.app.sim.wave_number)
	wave_size := 30
	wave_x := screen_width / 2 - raylib.MeasureText(wave_text, i32(wave_size)) / 2
	raylib.DrawText(wave_text, wave_x, screen_height / 2, i32(wave_size), raylib.WHITE)
	
	// Menu button
	button_width := 200
	button_height := 50
	button_x := screen_width / 2 - button_width / 2
	button_y := screen_height * 2 / 3
	
	if render_button("Main Menu", button_x, button_y, button_width, button_height) {
		game.app_set_state(.MENU)
	}
}

// Helper to render a button
render_button :: proc(text: string, x, y, width, height: i32) -> bool {
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	hovered := mouse_x >= x && mouse_x <= x + width &&
	           mouse_y >= y && mouse_y <= y + height
	
	// Button background
	color := raylib.DARKGRAY
	if hovered {
		color = raylib.GRAY
	}
	raylib.DrawRectangle(x, y, width, height, color)
	
	// Button border
	raylib.DrawRectangleLines(x, y, width, height, raylib.WHITE)
	
	// Text
	text_width := raylib.MeasureText(text, 20)
	text_x := x + width / 2 - text_width / 2
	text_y := y + height / 2 - 10
	raylib.DrawText(text, text_x, text_y, 20, raylib.WHITE)
	
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

package systems

import "../constants"
import "../entities"
import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

// Render the entire game
render_game :: proc(app: ^entities.App_State) {
	render_map(app)
	render_tower_ranges(app)
	render_map_objects(app)
	render_gameplay(app)
	render_ui(app)
}

// Render tower ranges (separate layer above grid)
render_tower_ranges :: proc(app: ^entities.App_State) {
	if !app.settings.show_tower_range {
		return
	}

	cs := f32(app.settings.cell_size) * app.zoom

	for &tower in app.sim.towers {
		spec := constants.TOWER_SPECS[tower.type]
		x := f32(tower.c) * cs + f32(app.camera_offset_x)
		y := f32(tower.r) * cs + f32(app.camera_offset_y)
		center_x := x + cs / 2
		center_y := y + cs / 2
		range_px := spec.range * cs

		raylib.DrawCircle(i32(center_x), i32(center_y), range_px, constants.TOWER_RANGE_PREVIEW)
	}
}

// Render map objects (towers, spawn, goal, accessories, obstacles) - intermediate layer
render_map_objects :: proc(app: ^entities.App_State) {
	m := &app.editor.game_map
	cs := f32(app.settings.cell_size) * app.zoom

	// Draw gameplay tiles (towers, accessories)
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
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

	// Draw obstacles (use the minimum of width and height)
	gs_for_obstacles := m.width
	if m.height < gs_for_obstacles {
		gs_for_obstacles = m.height
	}
	render_obstacles(m, cs, i32(gs_for_obstacles), app.camera_offset_x, app.camera_offset_y)

	// Draw laser beams (on top of everything)
	if app.state == .PLAYING || (app.state == .PAUSED && app.previous_state == .PLAYING) {
		render_laser_beams(app, cs)
	}

	// Draw reticle for selected tower in PLAYING/PAUSED modes
	if app.selected_tower != nil && (app.state == .PLAYING || app.state == .PAUSED) {
		sx := f32(app.selected_tower.c) * cs + f32(app.camera_offset_x)
		sy := f32(app.selected_tower.r) * cs + f32(app.camera_offset_y)
		render_reticle(sx, sy, cs, constants.UI_RETICLE_COLOR)
	}

	// Draw reticle for selected obstacle in PLAYING/PAUSED modes
	if app.selected_obstacle.valid && (app.state == .PLAYING || app.state == .PAUSED) {
		sx := f32(app.selected_obstacle.col) * cs + f32(app.camera_offset_x)
		sy := f32(app.selected_obstacle.row) * cs + f32(app.camera_offset_y)
		render_reticle(sx, sy, cs, constants.UI_RETICLE_COLOR)
	}

	// Draw reticle for selected cell (in editor and simulation modes)
	if app.selected_cell.valid && app.state == .EDITOR {
		sx := f32(app.selected_cell.col) * cs + f32(app.camera_offset_x)
		sy := f32(app.selected_cell.row) * cs + f32(app.camera_offset_y)
		render_reticle(sx, sy, cs, constants.UI_RETICLE_COLOR)

		// Draw tower ghost if a tower type is selected for building
		if app.sim.selected_build_tower != .EMPTY {
			// Convert tile to tower type
			tower_type := tile_to_tower_type(app.sim.selected_build_tower)
			draw_tower_tile(sx, sy, cs, tower_type, 0, true) // is_ghost = true
			// Draw range preview
			spec := constants.TOWER_SPECS[tower_type]
			raylib.DrawCircle(i32(sx + cs / 2), i32(sy + cs / 2), spec.range * cs, constants.TOWER_RANGE_PREVIEW)
		}
	}
}

// Render map (grid, paths, obstacles)
render_map :: proc(app: ^entities.App_State) {
	m := &app.editor.game_map
	cs := f32(app.settings.cell_size) * app.zoom
	gs := m.width // Use map's actual dimensions

	// Background
	biome_colors := constants.BIOME_COLORS[m.biome]
	raylib.ClearBackground(biome_colors.bg)

	// Fill grid background (use both width and height)
	total_width := f32(m.width) * cs
	total_height := f32(m.height) * cs
	raylib.DrawRectangle(
		i32(app.camera_offset_x),
		i32(app.camera_offset_y),
		i32(total_width),
		i32(total_height),
		biome_colors.bg_grid,
	)

	// Draw paths (use the minimum of width and height for gs parameter)
	gs_for_rendering := m.width
	if m.height < gs_for_rendering {
		gs_for_rendering = m.height
	}
	render_paths(m, cs, i32(gs_for_rendering), app.camera_offset_x, app.camera_offset_y)

	// Grid lines (use the minimum of width and height)
	if app.settings.show_grid {
		gs_for_grid := m.width
		if m.height < gs_for_grid {
			gs_for_grid = m.height
		}
		render_grid_lines(app, cs, i32(gs_for_grid))
	}

	// Draw tower ghost in PLAYING/PAUSED modes when building
	if app.selected_cell.valid && (app.state == .PLAYING || app.state == .PAUSED) {
		if app.sim.selected_build_tower != .EMPTY {
			sx := f32(app.selected_cell.col) * cs + f32(app.camera_offset_x)
			sy := f32(app.selected_cell.row) * cs + f32(app.camera_offset_y)
			tower_type := tile_to_tower_type(app.sim.selected_build_tower)
			draw_tower_tile(sx, sy, cs, tower_type, 0, true) // is_ghost = true
			// Draw range preview
			spec := constants.TOWER_SPECS[tower_type]
			raylib.DrawCircle(i32(sx + cs / 2), i32(sy + cs / 2), spec.range * cs, constants.TOWER_RANGE_PREVIEW)
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

	for row in 0 ..< gs {
		for col in 0 ..< gs {
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

			// Draw center
			is_spawn_or_goal := tile == .SPAWN || tile == .GOAL
			if is_spawn_or_goal {
				raylib.DrawCircleV({cx, cy}, cs / 2, path_color)
			} else {
				raylib.DrawRectangleRec(
					{cx - path_width / 2, cy - path_width / 2, path_width, path_width},
					path_color,
				)
			}

			// Draw connections
			if top {
				raylib.DrawRectangleRec(
					{cx - path_width / 2, y, path_width, cs / 2},
					path_color,
				)
			}
			if right {
				raylib.DrawRectangleRec(
					{cx, cy - path_width / 2, cs / 2, path_width},
					path_color,
				)
			}
			if bottom {
				raylib.DrawRectangleRec(
					{cx - path_width / 2, cy, path_width, cs / 2},
					path_color,
				)
			}
			if left {
				raylib.DrawRectangleRec(
					{x, cy - path_width / 2, cs / 2, path_width},
					path_color,
				)
			}

			// Draw rounded corners for smooth path turns
			corner_radius := path_width / 2
			if top && right {
				// Smooth the outer corner between top and right
				raylib.DrawCircle(i32(cx), i32(cy), corner_radius, path_color)
			}
			if right && bottom {
				raylib.DrawCircle(i32(cx), i32(cy), corner_radius, path_color)
			}
			if bottom && left {
				raylib.DrawCircle(i32(cx), i32(cy), corner_radius, path_color)
			}
			if left && top {
				raylib.DrawCircle(i32(cx), i32(cy), corner_radius, path_color)
			}
		}
	}
}

// Render grid lines
render_grid_lines :: proc(app: ^entities.App_State, cs: f32, gs: i32) {
	for i in 0 ..= gs {
		x := i32(f32(i) * cs) + app.camera_offset_x
		y := i32(f32(i) * cs) + app.camera_offset_y

		// Vertical
		raylib.DrawLine(
			x,
			app.camera_offset_y,
			x,
			app.camera_offset_y + i32(f32(gs) * cs),
			constants.COLOR_GRID_LINE,
		)

		// Horizontal
		raylib.DrawLine(
			app.camera_offset_x,
			y,
			app.camera_offset_x + i32(f32(gs) * cs),
			y,
			constants.COLOR_GRID_LINE,
		)
	}
}

// Render tower upgrades (small dots) - arranged in rows of 5 above the tower
render_tower_upgrades :: proc(tower: ^entities.Tower, x, y, cs: f32, show_on_hover: bool = false) {
	// Check if mouse is over the tower when show_on_hover is enabled
	if show_on_hover {
		mouse_pos := raylib.GetMousePosition()
		tower_rect := raylib.Rectangle{x, y, cs, cs}
		if !raylib.CheckCollisionPointRec(mouse_pos, tower_rect) {
			return
		}
	}

	dot_radius := cs * 0.08
	dot_spacing := cs * 0.20 // Horizontal spacing between dots (increased)
	row_spacing := cs * 0.18 // Vertical spacing between rows (increased)
	pips_per_row : i32 = 5

	// Calculate total number of pips
	total_pips := (tower.damage_level - 1) + (tower.rate_level - 1) + (tower.critical_level - 1)
	if total_pips <= 0 {
		return
	}

	// Calculate number of rows
	num_rows := (total_pips + pips_per_row - 1) / pips_per_row

	// Start position - centered above the tower
	start_y := y - cs * 0.15 // Slightly above the tower

	pip_index : i32 = 0

	// Damage upgrades (red pips) - first
	for i in 0 ..< tower.damage_level - 1 {
		row := pip_index / pips_per_row
		col := pip_index % pips_per_row

		// Calculate pips in this row
		pips_in_this_row := total_pips - row * pips_per_row
		if pips_in_this_row > pips_per_row {
			pips_in_this_row = pips_per_row
		}

		// Center this row based on actual number of pips
		row_width := f32(pips_in_this_row) * dot_spacing
		start_x := x + cs / 2 - row_width / 2

		dot_x := start_x + f32(col) * dot_spacing
		dot_y := start_y - f32(row) * row_spacing
		raylib.DrawCircle(i32(dot_x), i32(dot_y), dot_radius, raylib.RED)
		pip_index += 1
	}

	// Rate upgrades (yellow pips) - second
	for i in 0 ..< tower.rate_level - 1 {
		row := pip_index / pips_per_row
		col := pip_index % pips_per_row

		// Calculate pips in this row
		pips_in_this_row := total_pips - row * pips_per_row
		if pips_in_this_row > pips_per_row {
			pips_in_this_row = pips_per_row
		}

		// Center this row based on actual number of pips
		row_width := f32(pips_in_this_row) * dot_spacing
		start_x := x + cs / 2 - row_width / 2

		dot_x := start_x + f32(col) * dot_spacing
		dot_y := start_y - f32(row) * row_spacing
		// Draw triangle for rate upgrades
		raylib.DrawTriangle(
			{dot_x, dot_y - dot_radius},
			{dot_x - dot_radius, dot_y + dot_radius},
			{dot_x + dot_radius, dot_y + dot_radius},
			raylib.YELLOW,
		)
		pip_index += 1
	}

	// Critical upgrades (blue pips) - third
	for i in 0 ..< tower.critical_level - 1 {
		row := pip_index / pips_per_row
		col := pip_index % pips_per_row

		// Calculate pips in this row
		pips_in_this_row := total_pips - row * pips_per_row
		if pips_in_this_row > pips_per_row {
			pips_in_this_row = pips_per_row
		}

		// Center this row based on actual number of pips
		row_width := f32(pips_in_this_row) * dot_spacing
		start_x := x + cs / 2 - row_width / 2

		dot_x := start_x + f32(col) * dot_spacing
		dot_y := start_y - f32(row) * row_spacing
		// Draw square for critical upgrades
		raylib.DrawRectangle(
			i32(dot_x - dot_radius),
			i32(dot_y - dot_radius),
			i32(dot_radius * 2),
			i32(dot_radius * 2),
			raylib.BLUE,
		)
		pip_index += 1
	}
}

// Render obstacle level pips (similar to tower upgrades)
render_obstacle_pips :: proc(level: i32, x, y, cs: f32, show_on_hover: bool = false) {
	// Check if mouse is over the obstacle when show_on_hover is enabled
	if show_on_hover {
		mouse_pos := raylib.GetMousePosition()
		obstacle_rect := raylib.Rectangle{x, y, cs, cs}
		if !raylib.CheckCollisionPointRec(mouse_pos, obstacle_rect) {
			return
		}
	}

	if level <= 1 {
		return
	}

	dot_radius := cs * 0.08
	dot_spacing := cs * 0.20
	row_spacing := cs * 0.18
	pips_per_row : i32 = 5

	// Calculate total number of pips (level - 1, since level 1 has no pips)
	total_pips := level - 1
	if total_pips <= 0 {
		return
	}

	// Start position - centered above the obstacle
	start_y := y - cs * 0.15

	// Draw pips (all orange for obstacles)
	for i in 0 ..< total_pips {
		row := i / pips_per_row
		col := i % pips_per_row

		// Calculate pips in this row
		pips_in_this_row := total_pips - row * pips_per_row
		if pips_in_this_row > pips_per_row {
			pips_in_this_row = pips_per_row
		}

		// Center this row based on actual number of pips
		row_width := f32(pips_in_this_row) * dot_spacing
		start_x := x + cs / 2 - row_width / 2

		dot_x := start_x + f32(col) * dot_spacing
		dot_y := start_y - f32(row) * row_spacing
		raylib.DrawCircle(i32(dot_x), i32(dot_y), dot_radius, raylib.ORANGE)
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
		// Round tree (plain) - 3-circle gradient using biome colors
		seed := hash_position(row, col)
		tree_colors := constants.BIOME_TREE_COLORS[.PLAIN]

		// Size variation per tree
		base_size := 0.32 + (f32(seed % 15) / 100.0) // 0.32 to 0.46

		// Position jitter for natural look
		jitter_x := (f32(seed % 7) - 3.0) * cs * 0.015
		jitter_y := (f32((seed / 7) % 7) - 3.0) * cs * 0.015
		cx := center_x + jitter_x
		cy := center_y + jitter_y

		// Shadow (10% opacity)
		shadow_offset := max(2, cs * 0.08)
		shadow_color := constants.ENEMY_SHADOW_COLOR
		raylib.DrawCircle(i32(cx + shadow_offset), i32(cy + shadow_offset), cs * base_size, shadow_color)

		// Three concentric circles for gradient effect
		// Outer circle (darkest)
		raylib.DrawCircle(i32(cx), i32(cy), cs * base_size, tree_colors.layer_dark)
		// Middle circle (medium)
		raylib.DrawCircle(i32(cx), i32(cy), cs * base_size * 0.7, tree_colors.layer_mid)
		// Inner circle (lightest)
		raylib.DrawCircle(i32(cx), i32(cy), cs * base_size * 0.4, tree_colors.layer_light)

	case .FOREST:
		// Pine tree (forest) - hexagonal layers with rotation
		seed := hash_position(row, col)
		tree_colors := constants.BIOME_TREE_COLORS[.FOREST]

		// Base size variation per tree
		base_size := 0.32 + (f32(seed % 15) / 100.0) // 0.32 to 0.46

		// Position jitter - each tree is slightly offset
		jitter_x := (f32(seed % 7) - 3.0) * cs * 0.015
		jitter_y := (f32((seed / 7) % 7) - 3.0) * cs * 0.015
		cx := center_x + jitter_x
		cy := center_y + jitter_y

		// Base rotation for this tree (varies by seed)
		base_rotation := f32(seed % 60) // 0 to 59 degrees

		// Draw pine as concentric hexagons (layers of needles)
		layers := 4 + int(seed % 3) // 4 to 6 layers

		// Needle layers - each hexagon slightly smaller, lighter, and rotated
		for i in 0 ..< layers {
			layer_ratio := 1.0 - (f32(i) * 0.18)
			radius := cs * base_size * layer_ratio

			// Choose color based on layer from biome colors
			color :=
				tree_colors.layer_dark if i < layers / 3 else (tree_colors.layer_mid if i < 2 * layers / 3 else tree_colors.layer_light)
			if i == layers - 1 {
				color = tree_colors.layer_tip // Lightest at top
			}

			// Each hexagon layer has slightly different rotation
			layer_rotation := base_rotation + f32(i * 15) // Offset by 15 degrees per layer

			// Draw hexagon (6 sides)
			raylib.DrawPoly(
				raylib.Vector2{f32(cx), f32(cy)},
				6, // hexagon
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
		for i in 0 ..< frond_count {
			angle := f32(i) * math.PI * 2.0 / f32(frond_count)

			// Calculate frond center position (between inner and outer radius)
			frond_center_dist := (inner_radius + outer_radius) * 0.5
			frond_cx := center_x + math.cos(angle) * frond_center_dist
			frond_cy := center_y + math.sin(angle) * frond_center_dist

			// Draw elongated oval frond
			raylib.DrawEllipse(
				i32(frond_cx),
				i32(frond_cy),
				f32(outer_radius - inner_radius) * 0.5, // long axis
				f32(frond_width), // short axis
				raylib.Color{34, 139, 34, 255},
			)
		}

		// Draw smaller inner fronds (darker green)
		for i in 0 ..< frond_count {
			angle := f32(i) * math.PI * 2.0 / f32(frond_count) + math.PI / f32(frond_count)
			frond_center_dist := inner_radius * 1.5
			frond_cx := center_x + math.cos(angle) * frond_center_dist
			frond_cy := center_y + math.sin(angle) * frond_center_dist

			raylib.DrawEllipse(
				i32(frond_cx),
				i32(frond_cy),
				f32(cs * 0.15),
				f32(cs * 0.08),
				raylib.Color{0, 100, 0, 255},
			)
		}

	case .MOUNTAIN:
		// Dead bush (mountain) - top view: branches radiating from center
		branch_length := cs * 0.25

		// Branches radiating from center
		for i in 0 ..< 8 {
			angle := f32(i) * math.PI / 4
			end_x := center_x + math.cos(angle) * branch_length
			end_y := center_y + math.sin(angle) * branch_length
			raylib.DrawLine(
				i32(center_x),
				i32(center_y),
				i32(end_x),
				i32(end_y),
				raylib.Color{101, 67, 33, 255},
			)
		}
	}
}

// Render block accessory
render_block :: proc(x, y, cs: f32) {
	raylib.DrawRectangleRounded(
		raylib.Rectangle{x + cs * 0.1, y + cs * 0.1, cs * 0.8, cs * 0.8},
		constants.UI_BUTTON_ROUNDNESS,
		constants.TOWER_CORNER_SEGMENTS,
		constants.COLOR_BLOCK,
	)

	// Highlight
	raylib.DrawRectangle(
		i32(x + cs * 0.25),
		i32(y + cs * 0.25),
		i32(cs * 0.5),
		i32(cs * 0.5),
		constants.UI_EDITOR_HIGHLIGHT_COLOR,
	)
}

// Draw a single obstacle at specific position (for toolbar preview)
draw_obstacle_preview :: proc(x, y, cs: f32) {
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
}

// Render obstacles
render_obstacles :: proc(
	m: ^entities.Map,
	cs: f32,
	gs: i32,
	camera_offset_x, camera_offset_y: i32,
) {

	for row in 0 ..< gs {
		for col in 0 ..< gs {
			if m.obstacle_grid[row][col] == .OBSTACLE {
				x := f32(col) * cs + f32(camera_offset_x)
				y := f32(row) * cs + f32(camera_offset_y)

				// Determine path direction by checking adjacent cells
				is_horizontal_path := false
				is_vertical_path := false

				// Check left and right for horizontal path
				if col > 0 && m.grid[row][col - 1] == .PATH {
					is_horizontal_path = true
				}
				if col < gs - 1 && m.grid[row][col + 1] == .PATH {
					is_horizontal_path = true
				}

				// Check up and down for vertical path
				if row > 0 && m.grid[row - 1][col] == .PATH {
					is_vertical_path = true
				}
				if row < gs - 1 && m.grid[row + 1][col] == .PATH {
					is_vertical_path = true
				}

				// Calculate rotation (perpendicular to path)
				rotation := f32(0.0)
				if is_horizontal_path && !is_vertical_path {
					rotation = f32(math.PI / 2) // 90 degrees for horizontal path
				} else if is_vertical_path && !is_horizontal_path {
					rotation = f32(0.0) // 0 degrees for vertical path
				} else if is_horizontal_path && is_vertical_path {
					rotation = f32(math.PI / 4) // 45 degrees for intersection
				}

				// Draw obstacle with rotation
				center_x := x + cs / 2
				center_y := y + cs / 2
				width := cs * constants.OBSTACLE_WIDTH_RATIO
				height := cs * constants.OBSTACLE_HEIGHT_RATIO

				// Draw rectangle centered at tile center with rotation
				raylib.DrawRectanglePro(
					raylib.Rectangle{center_x - width / 2, center_y - height / 2, width, height},
					raylib.Vector2{width / 2, height / 2},
					rotation,
					constants.COLOR_OBSTACLE,
				)

				// Level indicator (pips instead of text)
				level := entities.map_get_obstacle_level(m, row, col)
				render_obstacle_pips(level, x, y, cs, true)
			}
		}
	}
}

// Render laser beams
render_laser_beams :: proc(app: ^entities.App_State, cs: f32) {
	sim := &app.sim

	for &beam in sim.laser_beams {
		alpha := beam.duration / beam.max_duration
		color := constants.TOWER_LASER_COLOR
		color.a = u8(255 * alpha)

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
	if app.settings.show_damage_numbers {
		render_damage_numbers(app, cs)
	}
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
		border_color := raylib.Color {
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
			v1_shadow := raylib.Vector2{center_x + so, center_y - size - 2 + so} // Top
			v2_shadow := raylib.Vector2{center_x - size - 2 + so, center_y + size + 2 + so} // Bottom left
			v3_shadow := raylib.Vector2{center_x + size + 2 + so, center_y + size + 2 + so} // Bottom right
			raylib.DrawTriangle(v1_shadow, v2_shadow, v3_shadow, shadow_color)

			// Inner triangle (body)
			v1_body := raylib.Vector2{center_x, center_y - size} // Top
			v2_body := raylib.Vector2{center_x - size, center_y + size} // Bottom left
			v3_body := raylib.Vector2{center_x + size, center_y + size} // Bottom right
			raylib.DrawTriangle(v1_body, v2_body, v3_body, color)

			// Triangle outline using DrawLineEx
			raylib.DrawLineEx(v1_body, v2_body, constants.ENEMY_STROKE_WIDTH, border_color)
			raylib.DrawLineEx(v2_body, v3_body, constants.ENEMY_STROKE_WIDTH, border_color)
			raylib.DrawLineEx(v3_body, v1_body, constants.ENEMY_STROKE_WIDTH, border_color)
		} else {
			// Ground enemies are drawn as circles
			center_x := x + cs / 2
			center_y := y + cs / 2

			// Circle shadow (offset)
			raylib.DrawCircle(i32(center_x + so), i32(center_y + so), size, shadow_color)

			// Circle outline using DrawCircleLines
			raylib.DrawCircle(i32(center_x), i32(center_y), size, border_color)

			// Circle body
			raylib.DrawCircle(i32(center_x), i32(center_y), size - constants.ENEMY_STROKE_WIDTH, color)
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
				hp_color = raylib.Color{200, 50, 50, 255} // Softer red
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
		for i in 0 ..< len(spawn.path) - 1 {
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

		for i in start_idx ..< i32(len(enemy.path) - 1) {
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
			// Arrow - small circle at cannon tip
			raylib.DrawCircle(i32(x), i32(y), cs * 0.08, raylib.BROWN)
		case .CANNON:
			// Cannonball - smaller gray circle at cannon tip
			raylib.DrawCircle(i32(x), i32(y), cs * 0.1, constants.COLOR_BLOCK)
		case .SNIPER:
			// Bullet - smaller gray circle at cannon tip
			raylib.DrawCircle(i32(x), i32(y), cs * 0.06, constants.COLOR_BLOCK)
		case .MISSILE:
			// Missile - aligned body + tip, single color
			px := x
			py := y
			angle := proj.angle
			cos_a := math.cos(angle)
			sin_a := math.sin(angle)

			missile_len := cs * 0.35
			missile_thick := cs * 0.1
			missile_color := raylib.Color{120, 120, 120, 255}

			// Body: thick line from back to front
			back_x := px - cos_a * (missile_len * 0.5)
			back_y := py - sin_a * (missile_len * 0.5)
			front_x := px + cos_a * (missile_len * 0.3)
			front_y := py + sin_a * (missile_len * 0.3)

			raylib.DrawLineEx(
				{back_x, back_y},
				{front_x, front_y},
				missile_thick,
				missile_color,
			)

			// Pointed tip - aligned with body end
			perp_x := -sin_a * (missile_thick * 0.5)
			perp_y := cos_a * (missile_thick * 0.5)

			tip_x := px + cos_a * (missile_len * 0.5)
			tip_y := py + sin_a * (missile_len * 0.5)

			raylib.DrawTriangle(
				{front_x + perp_x, front_y + perp_y},
				{front_x - perp_x, front_y - perp_y},
				{tip_x, tip_y},
				missile_color,
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

// Draw text with outline (stroke around the text)
draw_text_with_outline :: proc(
	text: cstring,
	pos: raylib.Vector2,
	font_size: f32,
	spacing: f32,
	text_color: raylib.Color,
	outline_color: raylib.Color,
	outline_thickness: i32 = 1,
) {
	// Draw outline by drawing the text in outline color at offset positions
	for y_offset in -outline_thickness ..= outline_thickness {
		for x_offset in -outline_thickness ..= outline_thickness {
			if x_offset == 0 && y_offset == 0 {
				continue // Skip center position
			}
			offset_pos := raylib.Vector2{pos.x + f32(x_offset), pos.y + f32(y_offset)}
			raylib.DrawTextEx(
				constants.game_fonts.bold,
				text,
				offset_pos,
				font_size,
				spacing,
				outline_color,
			)
		}
	}

	// Draw main text on top
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		text,
		pos,
		font_size,
		spacing,
		text_color,
	)
}

// Render damage numbers
render_damage_numbers :: proc(app: ^entities.App_State, cs: f32) {
	for &dn in app.sim.damage_numbers {
		x := dn.x * cs + f32(app.camera_offset_x)
		y := dn.y * cs + f32(app.camera_offset_y)

		alpha := u8(255 * dn.life)
		color := dn.color
		color.a = alpha
		outline_color := raylib.Color{0, 0, 0, 255}
		outline_color.a = alpha

		damage_text := fmt.tprintf("%.0f", dn.value)
		font_size := cs * 0.25
		if dn.is_critical {
			font_size = cs * 0.5
		}

		draw_text_with_outline(
			strings.clone_to_cstring(damage_text),
			{x, y},
			font_size,
			0,
			color,
			outline_color,
			1,
		)
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
		render_obstacle_control_panel(app)
	case .PAUSED:
		render_pause_menu(app)
	case .EDITOR:
		render_editor_ui(app)
	case .GAME_OVER:
		render_game_over_ui(app)
	case .SETTINGS:
		render_settings_menu(app)
	}

	// Render toasts (always on top)
	entities.render_toasts(app)

	// FPS counter - bottom left with UI margin padding using custom font (skip in editor mode)
	if app.settings.show_fps && app.state != .EDITOR {
		fps_text := fmt.tprintf("FPS: %d", raylib.GetFPS())
		screen_height := raylib.GetScreenHeight()
		fps_font_size := f32(20)
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring(fps_text),
			{f32(constants.UI_MARGIN_X), f32(screen_height - constants.UI_MARGIN_Y - 20)},
			fps_font_size,
			0,
			raylib.WHITE,
		)
	}
}

// Render gradient background with subtle pattern for menus
render_background :: proc() {
	// Use GetRenderWidth/Height for accurate fullscreen dimensions
	width := raylib.GetRenderWidth()
	height := raylib.GetRenderHeight()

	// Draw gradient rectangle manually
	for y in 0 ..< height {
		t := f32(y) / f32(height)
		r := u8(f32(constants.MENU_BG_TOP_COLOR.r) * (1 - t) + f32(constants.MENU_BG_BOTTOM_COLOR.r) * t)
		g := u8(f32(constants.MENU_BG_TOP_COLOR.g) * (1 - t) + f32(constants.MENU_BG_BOTTOM_COLOR.g) * t)
		b := u8(f32(constants.MENU_BG_TOP_COLOR.b) * (1 - t) + f32(constants.MENU_BG_BOTTOM_COLOR.b) * t)
		raylib.DrawLine(0, y, width, y, raylib.Color{r, g, b, 255})
	}

	// Calculate diagonal offset based on time (wrap around grid spacing)
	time := f32(raylib.GetTime())
	offset := i32(time * constants.MENU_GRID_SPEED) % constants.MENU_GRID_SPACING
	offset_x := offset
	offset_y := offset

	// Draw subtle grid pattern with diagonal movement
	for x := offset_x - constants.MENU_GRID_SPACING; x < width + constants.MENU_GRID_SPACING; x += constants.MENU_GRID_SPACING {
		raylib.DrawLine(x, 0, x, height, constants.MENU_GRID_COLOR)
	}
	for y := offset_y - constants.MENU_GRID_SPACING; y < height + constants.MENU_GRID_SPACING; y += constants.MENU_GRID_SPACING {
		raylib.DrawLine(0, y, width, y, constants.MENU_GRID_COLOR)
	}
}

// Render menu UI
render_menu_ui :: proc(app: ^entities.App_State) {
	// Reset game session stats
	game_session_start_time = 0
	game_session_end_time = 0
	game_session_total_kills = 0

	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	// Black background
	render_background()

	// Title (using bold font)
	title_text := constants.get_text("MENU_TITLE")
	title_size := f32(screen_height) * 0.08
	title_width := f32(
		raylib.MeasureTextEx(constants.game_fonts.bold, strings.clone_to_cstring(title_text), title_size, 0).x,
	)
	title_x := f32(screen_width) / 2 - title_width / 2
	title_y := f32(screen_height) / 4
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		strings.clone_to_cstring(title_text),
		{title_x, title_y},
		title_size,
		0,
		raylib.WHITE,
	)

	// Buttons - each with individual width based on its translation text
	menu_button_height := i32(constants.UI_BUTTON_HEIGHT)
	button_font_size := f32(constants.UI_BUTTON_FONT_SIZE)
	// Calculate vertical centering for all buttons
	total_buttons_height := 4 * menu_button_height + 3 * i32(10)
	start_y := (i32(screen_height) - total_buttons_height) / 2

	// Play button
	play_text := constants.get_text("MENU_BUTTON_PLAY")
	play_button_y := start_y
	play_text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(play_text), button_font_size, 0).x)
	play_width := play_text_width
	play_x := screen_width / 2 - play_width / 2
	if render_button(
		play_text,
		{f32(play_x), f32(play_button_y), f32(play_width), f32(menu_button_height)},
	) {
		entities.app_set_state(app, .PLAYING)
	}

	// Editor button
	editor_text := constants.get_text("MENU_BUTTON_EDITOR")
	editor_button_y := play_button_y + menu_button_height + i32(10)
	editor_text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(editor_text), button_font_size, 0).x)
	editor_width := editor_text_width
	editor_x := screen_width / 2 - editor_width / 2
	if render_button(
		editor_text,
		{f32(editor_x), f32(editor_button_y), f32(editor_width), f32(menu_button_height)},
	) {
		entities.app_set_state(app, .EDITOR)
	}

	// Settings button
	settings_text := constants.get_text("MENU_BUTTON_SETTINGS")
	settings_button_y := editor_button_y + menu_button_height + i32(10)
	settings_text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(settings_text), button_font_size, 0).x)
	settings_width := settings_text_width
	settings_x := screen_width / 2 - settings_width / 2
	if render_button(
		settings_text,
		{f32(settings_x), f32(settings_button_y), f32(settings_width), f32(menu_button_height)},
	) {
		entities.app_set_state(app, .SETTINGS)
	}

	// Exit button
	exit_text := constants.get_text("MENU_BUTTON_EXIT")
	exit_button_y := settings_button_y + menu_button_height + i32(10)
	exit_text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(exit_text), button_font_size, 0).x)
	exit_width := exit_text_width
	exit_x := screen_width / 2 - exit_width / 2
	if render_button(
		exit_text,
		{f32(exit_x), f32(exit_button_y), f32(exit_width), f32(menu_button_height)},
	) {
		app.should_quit = true
	}
}

// Render game UI (HUD)
render_game_ui :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	// Track game session start time
	if game_session_start_time == 0 {
		game_session_start_time = raylib.GetTime()
	}

	// HUD info panel
	font_size := f32(constants.UI_BUTTON_FONT_SIZE)
	hud_line_height := i32(font_size + font_size / 2)
	hud_num_lines: i32 = 4
	hud_panel_width: f32 = 160
	hud_panel_height := f32(hud_num_lines * hud_line_height + 10)
	hud_panel_rect := raylib.Rectangle {
		f32(constants.UI_MARGIN_X),
		f32(constants.UI_MARGIN_Y),
		hud_panel_width,
		hud_panel_height,
	}
	hud_content := render_panel(hud_panel_rect)

	hud_x := hud_content.x
	hud_y := hud_content.y

	// Money
	money_label := constants.get_text("UI_MONEY")
	money_text := fmt.tprintf("%s: %d", money_label, app.sim.money)
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(money_text),
		{hud_x, hud_y},
		font_size,
		0,
		raylib.GOLD,
	)

	// Health
	health_label := constants.get_text("UI_HEALTH")
	health_text := fmt.tprintf("%s: %d", health_label, app.sim.health)
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(health_text),
		{hud_x, hud_y + f32(hud_line_height)},
		font_size,
		0,
		raylib.GREEN,
	)

	// Wave
	wave_label := constants.get_text("UI_WAVE")
	display_wave := app.sim.wave_number
	if display_wave == 0 {
		display_wave = 1
	}
	wave_text := fmt.tprintf("%s: %d", wave_label, display_wave)
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(wave_text),
		{hud_x, hud_y + f32(hud_line_height * 2)},
		font_size,
		0,
		raylib.BLUE,
	)

	// Enemies
	enemies_label := constants.get_text("UI_ENEMIES")
	enemies_text := fmt.tprintf("%s: %d", enemies_label, len(app.sim.enemies))
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(enemies_text),
		{hud_x, hud_y + f32(hud_line_height * 3)},
		font_size,
		0,
		raylib.RED,
	)

	// Calculate button widths based on text
	button_y := i32(10)
	padding := i32(20)
	gap := i32(10)

	// Pause button text and width
	pause_text := constants.get_text("UI_BUTTON_PAUSE")
	if app.sim.paused {
		pause_text = constants.get_text("UI_BUTTON_RESUME")
	}
	pause_text_width := i32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(pause_text), font_size, 0).x,
	)
	pause_width := pause_text_width + padding

	// 1x button width
	speed1_text := "1x"
	speed1_text_width := i32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(speed1_text), font_size, 0).x,
	)
	speed1_width := speed1_text_width + padding

	// 2x button width
	speed2_text := "2x"
	speed2_text_width := i32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(speed2_text), font_size, 0).x,
	)
	speed2_width := speed2_text_width + padding

	// Calculate positions from right to left
	is_between_waves := app.sim.enemies_spawned >= app.sim.enemies_to_spawn && len(app.sim.enemies) == 0
	can_start_wave := is_between_waves || !app.sim.started
	show_next_wave_button := !app.settings.auto_start_wave
	
	next_wave_text := constants.get_text("UI_NEXT_WAVE")
	next_wave_text_width := i32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(next_wave_text), font_size, 0).x,
	)
	next_wave_width := next_wave_text_width + padding

	start_text := constants.get_text("UI_START")
	start_text_width := i32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(start_text), font_size, 0).x,
	)
	start_width := start_text_width + padding

	// Calculate total width based on visible buttons
	visible_button_count := i32(4) // Start + Pause + 1x + 2x
	gap_count := i32(3)
	if show_next_wave_button {
		visible_button_count += 1
		gap_count += 1
	}
	total_buttons_width := pause_width + speed1_width + speed2_width + start_width + gap * gap_count + constants.UI_MARGIN_X
	if show_next_wave_button {
		total_buttons_width += next_wave_width
	}
	
	start_x := screen_width - total_buttons_width
	next_wave_x := start_x + start_width + gap
	pause_x := next_wave_x + (show_next_wave_button ? next_wave_width + gap : 0)
	speed1_x := pause_x + pause_width + gap
	speed2_x := speed1_x + speed1_width + gap

	// Start button (appears before first wave or between waves)
	if render_button(
		start_text,
		{f32(start_x), f32(button_y), f32(start_width), f32(constants.UI_BUTTON_HEIGHT)},
		1,
		can_start_wave,
		constants.UI_TEXT_COLOR,
		raylib.GREEN,
		raylib.Color{0, 180, 0, 255},
		raylib.Color{0, 150, 0, 255},
	) {
		if can_start_wave {
			simulation_set_pause(app, false) // unpause if paused
			start_next_wave(app)
		}
	}

	// Next Wave button (hidden when auto-start is enabled)
	if show_next_wave_button {
		if render_button(
			next_wave_text,
			{f32(next_wave_x), f32(button_y), f32(next_wave_width), f32(constants.UI_BUTTON_HEIGHT)},
			1,
			is_between_waves,
		) {
			if is_between_waves {
				simulation_set_pause(app, false) // unpause if paused
				start_next_wave(app)
			}
		}
	}

	// Pause button
	if render_button(
		pause_text,
		{f32(pause_x), f32(button_y), f32(pause_width), f32(constants.UI_BUTTON_HEIGHT)},
	) {
		simulation_toggle_pause(app)
	}

	// Speed buttons
	if render_button(
		speed1_text,
		{f32(speed1_x), f32(button_y), f32(speed1_width), f32(constants.UI_BUTTON_HEIGHT)},
	) {
		simulation_set_speed(app, 1.0)
	}
	if render_button(
		speed2_text,
		{f32(speed2_x), f32(button_y), f32(speed2_width), f32(constants.UI_BUTTON_HEIGHT)},
	) {
		simulation_set_speed(app, 2.0)
	}

	// Render build toolbar (shared logic)
	render_build_toolbar(app)
}

// Render build toolbar (used in both PLAYING and EDITOR modes)
render_build_toolbar :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()
	bottom_margin := i32(40)

	if app.state == .EDITOR {
		// Editor tools
		tools := []struct {
			name: string,
			tile: constants.Tile,
		} {
			{constants.get_text("EDITOR_TOOL_EMPTY"), .EMPTY},
			{constants.get_text("EDITOR_TOOL_PATH"), .PATH},
			{constants.get_text("EDITOR_TOOL_SPAWN"), .SPAWN},
			{constants.get_text("EDITOR_TOOL_GOAL"), .GOAL},
			{constants.get_text("TOWER_ARCHER_NAME"), .TOWER_ARCHER},
			{constants.get_text("TOWER_CANNON_NAME"), .TOWER_CANNON},
			{constants.get_text("TOWER_SNIPER_NAME"), .TOWER_SNIPER},
			{constants.get_text("TOWER_MISSILE_NAME"), .TOWER_MISSILE},
			{constants.get_text("TOWER_LASER_NAME"), .TOWER_LASER},
			{constants.get_text("EDITOR_TOOL_OBSTACLE"), .OBSTACLE},
			{constants.get_text("EDITOR_TOOL_TREE"), .ACCESSORY_TREE},
			{constants.get_text("EDITOR_TOOL_BLOCK"), .ACCESSORY_BLOCK},
		}

		button_width := i32(75) // slightly narrower to fit 12 buttons
		total_width := i32(len(tools)) * button_width + i32(len(tools) - 1) * 5
		start_x := (screen_width - total_width) / 2

		for tool, i in tools {
			x := start_x + i32(i) * (button_width + 5)
			button_height := i32(45) // Fixed height to fit 2 lines at 12px
			y := i32(screen_height - button_height - bottom_margin)

			is_selected := app.editor.current_tool == tool.tile
			button_color := raylib.LIGHTGRAY
			if is_selected {
				button_color = raylib.BLUE
			}

			// Format with line breaks at start to push text below the preview
			button_text := fmt.tprintf("\n\n%s", tool.name)

			if render_button_with_color(
				   button_text,
				   {f32(x), f32(y), f32(button_width), f32(button_height)},
				   button_color,
				   4,
				   12.0,
			   ) {
				app.editor.current_tool = tool.tile
			}

			// Render visual preview inside the button (positioned at top)
			preview_size := f32(24) // Slightly smaller to fit better
			preview_x := f32(x) + (f32(button_width) - preview_size) / 2
			preview_y := f32(y) + 2 // Small top padding

			switch tool.tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
				tower_type := tile_to_tower_type(tool.tile)
				draw_tower_tile(preview_x, preview_y, preview_size, tower_type, 0, false)
			case .OBSTACLE:
				draw_obstacle_preview(preview_x, preview_y, preview_size)
			case .ACCESSORY_TREE:
				// Use PLAIN biome for consistent preview, with fixed position (0,0)
				render_tree(preview_x, preview_y, preview_size, .PLAIN, 0, 0)
			case .ACCESSORY_BLOCK:
				render_block(preview_x, preview_y, preview_size)
			case .EMPTY:
				// Draw empty cell indicator (light gray square)
				raylib.DrawRectangleLines(
					i32(preview_x + preview_size * 0.2),
					i32(preview_y + preview_size * 0.2),
					i32(preview_size * 0.6),
					i32(preview_size * 0.6),
					raylib.LIGHTGRAY,
				)
			case .PATH:
				// Draw path indicator (dashed lines or path color)
				raylib.DrawRectangle(
					i32(preview_x + preview_size * 0.2),
					i32(preview_y + preview_size * 0.4),
					i32(preview_size * 0.6),
					i32(preview_size * 0.2),
					constants.COLOR_PATH,
				)
			case .SPAWN:
				render_spawn(preview_x, preview_y, preview_size)
			case .GOAL:
				render_goal(preview_x, preview_y, preview_size)
			}
		}
	} else {
		// Playing tools
		tower_types := []constants.Tile {
			.TOWER_ARCHER,
			.TOWER_CANNON,
			.TOWER_SNIPER,
			.TOWER_MISSILE,
			.TOWER_LASER,
		}
		tower_names := []string{
			constants.get_text("TOWER_ARCHER_NAME"),
			constants.get_text("TOWER_CANNON_NAME"),
			constants.get_text("TOWER_SNIPER_NAME"),
			constants.get_text("TOWER_MISSILE_NAME"),
			constants.get_text("TOWER_LASER_NAME"),
		}
		tower_costs := []i32{20, 40, 60, 50, 80}

		total_width :=
			i32(len(tower_types)) * constants.UI_BUTTON_WIDTH + i32(len(tower_types) - 1) * 5
		start_x := (screen_width - total_width) / 2

		for i := 0; i < len(tower_types); i += 1 {
			x := start_x + i32(i) * (constants.UI_BUTTON_WIDTH + 5)
			button_height := i32(75) // Taller to fit tower preview + 2 lines of text
			y := i32(screen_height - button_height - bottom_margin)

			is_selected := app.sim.selected_build_tower == tower_types[i]
			button_color := raylib.LIGHTGRAY
			if is_selected {
				button_color = raylib.GREEN
			}

			can_afford := app.sim.money >= tower_costs[i]
			if !can_afford {
				button_color = raylib.DARKGRAY
			}

			// Add newlines to push text to the bottom
			button_text := fmt.tprintf("\n\n%s\n$%d", tower_names[i], tower_costs[i])

			if render_button_with_color(
				   button_text,
				   {f32(x), f32(y), f32(constants.UI_BUTTON_WIDTH), f32(button_height)},
				   button_color,
				   4,
				   12.0,
			   ) &&
			   can_afford {
				if is_selected {
					app.sim.selected_build_tower = .EMPTY // Deselect
				} else {
					app.sim.selected_build_tower = tower_types[i] // Select
				}
			}

			// Render tower preview inside the button
			tower_type := tile_to_tower_type(tower_types[i])
			dummy_tower := entities.tower_init(tower_type, 0, 0)
			
			old_show_range := app.settings.show_tower_range
			app.settings.show_tower_range = false
			
			tower_cs := f32(32) // Preview size
			tower_x := f32(x) + (f32(constants.UI_BUTTON_WIDTH) - tower_cs) / 2
			tower_y := f32(y) + 4 // Top padding
			
			render_tower(app, &dummy_tower, tower_x, tower_y, tower_cs)
			
			app.settings.show_tower_range = old_show_range
		}
	}
}

// Render editor UI
render_editor_ui :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	// Render build toolbar (shared logic)
	render_build_toolbar(app)

	// Top toolbar
	raylib.DrawRectangle(
		0,
		0,
		screen_width,
		constants.UI_TOOLBAR_HEIGHT,
		raylib.Color{50, 50, 50, 200},
	)

	// Biome selector using render_select (dropdown, not dropup)
	biome_names := []string {
		constants.get_text("EDITOR_BIOME_PLAIN"),
		constants.get_text("EDITOR_BIOME_FOREST"),
		constants.get_text("EDITOR_BIOME_DESERT"),
		constants.get_text("EDITOR_BIOME_MOUNTAIN"),
	}
	biome_index := i32(app.editor.current_biome)

	if render_select(
		"biome",
		constants.get_text("EDITOR_BIOME_LABEL"),
		biome_names,
		&biome_index,
		10,
		4,
		i32(constants.UI_DROPDOWN_WIDTH),
		i32(constants.UI_DROPDOWN_HEIGHT),
		false, // Changed to false for dropdown (opens downward)
	) {
		app.editor.current_biome = constants.Biome(biome_index)
		app.editor.game_map.biome = constants.Biome(biome_index)
	}

	// Right-side buttons - laid out from right to left with consistent gap
	y_pos := 4
	gap := i32(10)

	// Helper to calculate actual button width
	btn_w :: proc(text: string) -> i32 {
		text_width := i32(
			raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text), f32(constants.UI_BUTTON_FONT_SIZE), 0).x,
		)
		min_w := text_width + 20
		return min_w > constants.UI_BUTTON_WIDTH ? min_w : constants.UI_BUTTON_WIDTH
	}

	current_x := screen_width - 10 // right margin

	// Menu button (rightmost)
	w_menu := btn_w(constants.get_text("EDITOR_BUTTON_MENU"))
	current_x -= w_menu
	if render_button(
		constants.get_text("EDITOR_BUTTON_MENU"),
		{f32(current_x), f32(y_pos), f32(w_menu), f32(constants.UI_BUTTON_HEIGHT)},
	) {
		entities.app_set_state(app, .MENU)
	}

	// Test button
	current_x -= gap
	w_test := btn_w(constants.get_text("EDITOR_BUTTON_TEST_MAP"))
	current_x -= w_test
	if render_button(
		constants.get_text("EDITOR_BUTTON_TEST_MAP"),
		{f32(current_x), f32(y_pos), f32(w_test), f32(constants.UI_BUTTON_HEIGHT)},
	) {
		if simulation_init_from_editor(app) {
			entities.app_set_state(app, .PLAYING)
		}
	}

	// Quick Load button
	current_x -= gap
	w_load := btn_w(constants.get_text("EDITOR_BUTTON_QUICK_LOAD"))
	current_x -= w_load
	if render_button(
		constants.get_text("EDITOR_BUTTON_QUICK_LOAD"),
		{f32(current_x), f32(y_pos), f32(w_load), f32(constants.UI_BUTTON_HEIGHT)},
	) {
		if entities.map_load(&app.editor.game_map, "last_saved.map") {
			app.editor.current_biome = app.editor.game_map.biome
		}
	}

	// Save button
	current_x -= gap
	w_save := btn_w(constants.get_text("EDITOR_BUTTON_SAVE_MAP"))
	current_x -= w_save
	if render_button(
		constants.get_text("EDITOR_BUTTON_SAVE_MAP"),
		{f32(current_x), f32(y_pos), f32(w_save), f32(constants.UI_BUTTON_HEIGHT)},
	) {
		// Save with timestamp AND as last_saved.map for quick loading
		filename := fmt.tprintf("map_%d.map", i32(raylib.GetTime()))
		if entities.map_save(&app.editor.game_map, filename) {
			entities.add_toast(app, fmt.tprintf("Map saved: %s", filename), .SUCCESS, 2.0)
		} else {
			entities.add_toast(app, "Failed to save map", .ERROR, 3.0)
			play_sound(.ERROR)
		}
		if entities.map_save(&app.editor.game_map, "last_saved.map") {
			entities.add_toast(app, "Quick save updated", .SUCCESS, 2.0)
		} else {
			entities.add_toast(app, "Failed to update quick save", .ERROR, 3.0)
			play_sound(.ERROR)
		}
	}
}

// Render pause menu overlay
render_pause_menu :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	// Black background
	render_background()

	// Pause title
	title := constants.get_text("PAUSE_TITLE")
	title_cstr := strings.clone_to_cstring(title)
	title_size := f32(40)
	title_width := raylib.MeasureTextEx(constants.game_fonts.bold, title_cstr, title_size, 0).x
	title_x := f32(screen_width) / 2 - title_width / 2
	title_y := f32(screen_height) / 3
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		title_cstr,
		{title_x, title_y},
		title_size,
		0,
		raylib.WHITE,
	)

	// Button dimensions
	button_width := i32(constants.UI_BUTTON_WIDTH)
	button_height := i32(constants.UI_BUTTON_HEIGHT)
	button_x := screen_width / 2 - button_width / 2
	button_spacing := i32(10)

	// Calculate vertical centering for all buttons (3 buttons)
	total_buttons_height := 3 * button_height + 2 * button_spacing
	start_y := (i32(screen_height) - total_buttons_height) / 2

	// Resume button
	resume_y := start_y
	if render_button(
		constants.get_text("PAUSE_RESUME"),
		{f32(button_x), f32(resume_y), f32(button_width), f32(button_height)},
	) {
		simulation_set_pause(app, false)
		entities.app_set_state(app, .PLAYING)
	}

	// Settings button
	settings_y := resume_y + button_height + button_spacing
	if render_button(
		constants.get_text("MENU_BUTTON_SETTINGS"),
		{f32(button_x), f32(settings_y), f32(button_width), f32(button_height)},
	) {
		entities.app_set_state(app, .SETTINGS)
	}

	// Main Menu button
	menu_y := settings_y + button_height + button_spacing
	if render_button(
		constants.get_text("PAUSE_MENU"),
		{f32(button_x), f32(menu_y), f32(button_width), f32(button_height)},
	) {
		simulation_set_pause(app, false)
		entities.app_set_state(app, .MENU)
	}
}

// Render game over UI
render_game_over_ui :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	// Black background
	render_background()

	font_size := f32(constants.UI_BUTTON_FONT_SIZE)
	small_font := font_size * 0.75
	btn_height := i32(constants.UI_BUTTON_HEIGHT)
	spacing := i32(constants.UI_PANEL_MARGIN)

	// --- Title ---
	title := constants.get_text("GAME_OVER_TITLE")
	title_cstr := strings.clone_to_cstring(title)
	title_size := f32(36)
	title_width := raylib.MeasureTextEx(constants.game_fonts.bold, title_cstr, title_size, 0).x
	title_x := f32(screen_width) / 2 - title_width / 2
	title_y := f32(screen_height) * 0.05
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		title_cstr,
		{title_x, title_y},
		title_size,
		0,
		raylib.RED,
	)

	// --- Subtitle ---
	wave_text := constants.get_text_f("GAME_OVER_WAVES_SURVIVED", app.sim.wave_number)
	wave_cstr := strings.clone_to_cstring(wave_text)
	sub_size := f32(18)
	wave_width := raylib.MeasureTextEx(constants.game_fonts.semibold, wave_cstr, sub_size, 0).x
	wave_x := f32(screen_width) / 2 - wave_width / 2
	sub_y := title_y + title_size + 6
	raylib.DrawTextEx(
		constants.game_fonts.semibold,
		wave_cstr,
		{wave_x, sub_y},
		sub_size,
		0,
		raylib.WHITE,
	)

	// ============================================================
	//  GRAPH PANEL
	// ============================================================
	graph_panel_w := i32(f32(screen_width) * 0.75)
	if graph_panel_w > 500 {graph_panel_w = 500}
	graph_panel_h := i32(f32(screen_height) * 0.35)
	if graph_panel_h > 220 {graph_panel_h = 220}
	graph_panel_x := f32(screen_width) / 2 - f32(graph_panel_w) / 2
	graph_panel_y := sub_y + sub_size + 12

	graph_rect := raylib.Rectangle {
		graph_panel_x,
		graph_panel_y,
		f32(graph_panel_w),
		f32(graph_panel_h),
	}
	graph_content := render_panel(graph_rect)

	// Graph area inside panel (leave margin for labels)
	label_margin_l := i32(40) // left labels (money)
	label_margin_r := i32(30) // right labels (health)
	label_margin_b := i32(22) // bottom (wave markers + time)
	label_margin_t := i32(14) // top (legend)

	gx := i32(graph_content.x) + label_margin_l
	gy := i32(graph_content.y) + label_margin_t
	gw := i32(graph_content.width) - label_margin_l - label_margin_r
	gh := i32(graph_content.height) - label_margin_t - label_margin_b

	if gw > 10 && gh > 10 && len(app.sim.graph_samples) > 1 {
		samples := app.sim.graph_samples[:]

		// Find ranges
		max_time := samples[len(samples) - 1].time
		if max_time < 1 {max_time = 1}

		max_money: i32 = 1
		max_health: i32 = 1
		for s in samples {
			if s.money > max_money {max_money = s.money}
			if s.health > max_health {max_health = s.health}
		}

		// Helpers
		time_to_x :: proc(t, max_t: f32, gx, gw: i32) -> f32 {
			return f32(gx) + (t / max_t) * f32(gw)
		}
		val_to_y :: proc(v: f32, max_v: f32, gy, gh: i32) -> f32 {
			return f32(gy + gh) - (v / max_v) * f32(gh)
		}

		// Gridlines (horizontal, subtle)
		for i in 1 ..= 3 {
			ly := f32(gy + gh) - f32(i) / 4.0 * f32(gh)
			raylib.DrawLine(
				i32(gx),
				i32(ly),
				i32(gx + gw),
				i32(ly),
				raylib.Color{180, 180, 180, 60},
			)
		}

		// Draw money line (gold)
		money_color := raylib.GOLD
		for i in 1 ..< len(samples) {
			x0 := time_to_x(samples[i - 1].time, max_time, gx, gw)
			y0 := val_to_y(f32(samples[i - 1].money), f32(max_money), gy, gh)
			x1 := time_to_x(samples[i].time, max_time, gx, gw)
			y1 := val_to_y(f32(samples[i].money), f32(max_money), gy, gh)
			raylib.DrawLineEx({x0, y0}, {x1, y1}, 2.0, money_color)
		}

		// Draw health line (green)
		health_color := raylib.GREEN
		for i in 1 ..< len(samples) {
			x0 := time_to_x(samples[i - 1].time, max_time, gx, gw)
			y0 := val_to_y(f32(samples[i - 1].health), f32(max_health), gy, gh)
			x1 := time_to_x(samples[i].time, max_time, gx, gw)
			y1 := val_to_y(f32(samples[i].health), f32(max_health), gy, gh)
			raylib.DrawLineEx({x0, y0}, {x1, y1}, 2.0, health_color)
		}

		// Y-axis labels
		// Money (left)
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring(fmt.tprintf("$%d", max_money)),
			{f32(gx - label_margin_l + 2), f32(gy)},
			small_font,
			0,
			money_color,
		)
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring("$0"),
			{f32(gx - label_margin_l + 2), f32(gy + gh - i32(small_font))},
			small_font,
			0,
			money_color,
		)
		// Health (right)
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring(fmt.tprintf("%d", max_health)),
			{f32(gx + gw + 4), f32(gy)},
			small_font,
			0,
			health_color,
		)
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring("0"),
			{f32(gx + gw + 4), f32(gy + gh - i32(small_font))},
			small_font,
			0,
			health_color,
		)

		// X-axis line
		raylib.DrawLine(
			i32(gx),
			i32(gy + gh),
			i32(gx + gw),
			i32(gy + gh),
			raylib.Color{180, 180, 180, 120},
		)

		// Time labels
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring("0:00"),
			{f32(gx), f32(gy + gh + 2)},
			small_font,
			0,
			constants.PANEL_TEXT_COLOR,
		)
		end_mins := i32(max_time) / 60
		end_secs := i32(max_time) % 60
		end_str := fmt.tprintf("%d:%02d", end_mins, end_secs)
		end_w :=
			raylib.MeasureTextEx(constants.game_fonts.regular, strings.clone_to_cstring(end_str), small_font, 0).x
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring(end_str),
			{f32(gx + gw) - end_w, f32(gy + gh + 2)},
			small_font,
			0,
			constants.PANEL_TEXT_COLOR,
		)

		// Wave markers along x-axis
		marker_y := f32(gy + gh) + 2
		marker_r: f32 = 4
		for wm in app.sim.wave_marks {
			mx := time_to_x(wm.time, max_time, gx, gw)

			// Pick color
			color: raylib.Color
			switch {
			case wm.is_boss:
				color = constants.COLOR_ENEMY_BOSS
			case wm.is_green:
				color = constants.ENEMY_GREEN
			case wm.is_blue:
				color = constants.ENEMY_BLUE
			case wm.is_flying:
				color = constants.ENEMY_FLYING
			case:
				color = constants.COLOR_ENEMY
			}

			// Vertical tick on graph
			raylib.DrawLine(i32(mx), gy + gh - 4, i32(mx), gy + gh, color)

			// Shape: boss=square, flying=triangle, others=circle
			switch {
			case wm.is_boss:
				raylib.DrawRectangle(
					i32(mx - marker_r),
					i32(marker_y),
					i32(marker_r * 2),
					i32(marker_r * 2),
					color,
				)
			case wm.is_flying:
				raylib.DrawTriangle(
					{mx, marker_y},
					{mx - marker_r, marker_y + marker_r * 2},
					{mx + marker_r, marker_y + marker_r * 2},
					color,
				)
			case:
				raylib.DrawCircle(i32(mx), i32(marker_y + marker_r), marker_r, color)
			}
		}

		// Legend (top-right inside graph)
		legend_x := f32(gx + gw) - 90
		legend_y := f32(gy) - 2
		raylib.DrawLineEx(
			{legend_x, legend_y + 5},
			{legend_x + 14, legend_y + 5},
			2.0,
			money_color,
		)
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring(constants.get_text("UI_MONEY")),
			{legend_x + 18, legend_y},
			small_font,
			0,
			constants.PANEL_TEXT_COLOR,
		)
		raylib.DrawLineEx(
			{legend_x + 55, legend_y + 5},
			{legend_x + 69, legend_y + 5},
			2.0,
			health_color,
		)
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring(constants.get_text("UI_HEALTH")),
			{legend_x + 73, legend_y},
			small_font,
			0,
			constants.PANEL_TEXT_COLOR,
		)
	}

	// ============================================================
	//  STATS PANEL
	// ============================================================
	stats_panel_w := graph_panel_w
	num_stats :: 5
	stat_height := i32(font_size) + 4
	stats_inner := i32(num_stats) * (stat_height + spacing) - spacing
	stats_total := stats_inner + 30
	stats_x := graph_panel_x
	stats_y := graph_panel_y + f32(graph_panel_h) + f32(spacing)

	stats_rect := raylib.Rectangle{stats_x, stats_y, f32(stats_panel_w), f32(stats_total)}
	stats_content := render_panel(stats_rect)

	scx := i32(stats_content.x)
	scw := i32(stats_content.width)
	sy := i32(stats_content.y)

	// Helper: draw a stat row
	draw_stat :: proc(label: string, value: string, cx, cw, y: i32, font_size: f32) {
		label_cstr := strings.clone_to_cstring(label)
		value_cstr := strings.clone_to_cstring(value)
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			label_cstr,
			{f32(cx), f32(y)},
			font_size,
			0,
			constants.PANEL_TEXT_COLOR,
		)
		vw := raylib.MeasureTextEx(constants.game_fonts.semibold, value_cstr, font_size, 0).x
		raylib.DrawTextEx(
			constants.game_fonts.semibold,
			value_cstr,
			{f32(cx + cw) - vw, f32(y)},
			font_size,
			0,
			constants.PANEL_TEXT_COLOR,
		)
	}

	// Play Time
	total_secs := i32(app.sim.play_time)
	draw_stat(
		constants.get_text("GAME_OVER_TIME"),
		fmt.tprintf("%d:%02d", total_secs / 60, total_secs % 60),
		scx,
		scw,
		sy,
		font_size,
	)
	sy += stat_height + spacing

	// Enemies Killed
	draw_stat(
		constants.get_text("GAME_OVER_ENEMIES_KILLED"),
		fmt.tprintf("%d", app.sim.enemies_killed),
		scx,
		scw,
		sy,
		font_size,
	)
	sy += stat_height + spacing

	// Money Earned
	draw_stat(
		constants.get_text("GAME_OVER_MONEY_EARNED"),
		fmt.tprintf("$%d", app.sim.money_earned),
		scx,
		scw,
		sy,
		font_size,
	)
	sy += stat_height + spacing

	// Towers Built
	draw_stat(
		constants.get_text("GAME_OVER_TOWERS_BUILT"),
		fmt.tprintf("%d", app.sim.towers_built),
		scx,
		scw,
		sy,
		font_size,
	)
	sy += stat_height + spacing

	// Upgrades
	draw_stat(
		constants.get_text("GAME_OVER_UPGRADES"),
		fmt.tprintf("%d", app.sim.upgrades_bought),
		scx,
		scw,
		sy,
		font_size,
	)

	// --- Menu button ---
	btn_width := i32(constants.UI_BUTTON_WIDTH) * 2
	btn_x := i32(stats_x) + i32(stats_panel_w) / 2 - btn_width / 2
	btn_y := i32(stats_y) + stats_total + spacing
	if render_button(
		constants.get_text("GAME_OVER_BUTTON_MENU"),
		{f32(btn_x), f32(btn_y), f32(btn_width), f32(btn_height)},
	) {
		entities.app_set_state(app, .MENU)
	}
}

// Render settings menu
render_settings_menu :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	// Black background
	render_background()

	// Layout constants from constants.odin
	font_size := f32(constants.UI_BUTTON_FONT_SIZE)
	item_height := i32(constants.UI_BUTTON_HEIGHT)
	btn_height := i32(constants.UI_BUTTON_HEIGHT)
	btn_width := i32(constants.UI_BUTTON_WIDTH)
	spacing := i32(constants.UI_PANEL_MARGIN)

	// Panel dimensions — 11 setting rows
	num_items :: 11
	panel_width := i32(350)
	panel_inner_height := i32(num_items) * (item_height + spacing) - spacing
	panel_total_height := panel_inner_height + 60 // extra for title + padding
	panel_x := f32(screen_width) / 2 - f32(panel_width) / 2
	panel_y := f32(screen_height) / 2 - f32(panel_total_height) / 2 - 20

	// Use render_panel with title
	panel_rect := raylib.Rectangle{panel_x, panel_y, f32(panel_width), f32(panel_total_height)}
	content := render_panel(panel_rect, constants.get_text("SETTINGS_TITLE"))

	cx := i32(content.x)
	cw := i32(content.width)
	item_y := i32(content.y)

	// Helper: right-aligned control x position
	ctrl_x := cx + cw - btn_width

	// --- Master Volume ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_VOLUME")),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	volume_value := i32(app.settings.master_volume * 100)
	volume_text := fmt.tprintf("%d%%", volume_value)
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(volume_text),
		{f32(ctrl_x + 30), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)

	if render_button("-", {f32(ctrl_x - 40), f32(item_y), 30, f32(btn_height)}) {
		if app.settings.master_volume > 0.0 {
			app.settings.master_volume -= 0.1
			if app.settings.master_volume < 0.0 {
				app.settings.master_volume = 0.0
			}
		}
	}
	if render_button("+", {f32(ctrl_x - 5), f32(item_y), 30, f32(btn_height)}) {
		if app.settings.master_volume < 1.0 {
			app.settings.master_volume += 0.1
			if app.settings.master_volume > 1.0 {
				app.settings.master_volume = 1.0
			}
		}
	}

	item_y += item_height + spacing

	// --- Language ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_LANGUAGE")),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	lang_text := constants.get_text("SETTINGS_LANGUAGE_ENGLISH")
	#partial switch app.settings.language {
	case .SPANISH:
		lang_text = constants.get_text("SETTINGS_LANGUAGE_SPANISH")
	case .PORTUGUESE:
		lang_text = constants.get_text("SETTINGS_LANGUAGE_PORTUGUESE")
	}
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(lang_text),
		{f32(ctrl_x + 30), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)

	if render_button("<", {f32(ctrl_x - 40), f32(item_y), 30, f32(btn_height)}) {
		switch app.settings.language {
		case .ENGLISH:
			app.settings.language = .PORTUGUESE
		case .SPANISH:
			app.settings.language = .ENGLISH
		case .PORTUGUESE:
			app.settings.language = .SPANISH
		}
		constants.set_language(app.settings.language)
	}
	if render_button(">", {f32(ctrl_x - 5), f32(item_y), 30, f32(btn_height)}) {
		switch app.settings.language {
		case .ENGLISH:
			app.settings.language = .SPANISH
		case .SPANISH:
			app.settings.language = .PORTUGUESE
		case .PORTUGUESE:
			app.settings.language = .ENGLISH
		}
		constants.set_language(app.settings.language)
	}

	item_y += item_height + spacing

	// --- Antialiasing ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_ANTIALIASING")),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	aa_options := []string{"Off", "2x", "4x", "8x"}
	_ = render_select(
		"antialiasing",
		"",
		aa_options,
		&app.settings.antialiasing,
		ctrl_x,
		item_y,
		btn_width,
		btn_height,
		true,
	)

	item_y += item_height + spacing

	// --- Grid Size ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring("Grid Size:"),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	grid_size_options := []string{"10x10", "20x20", "30x30", "40x40"}
	grid_size_index: i32 = 0
	switch app.settings.grid_size {
	case 10:
		grid_size_index = 0
	case 15:
		grid_size_index = 1
	case 20:
		grid_size_index = 2
	case 25:
		grid_size_index = 3
	}
	if render_select(
		"gridsize",
		"",
		grid_size_options,
		&grid_size_index,
		ctrl_x,
		item_y,
		btn_width,
		btn_height,
		true,
	) {
		switch grid_size_index {
		case 0:
			app.settings.grid_size = 10
		case 1:
			app.settings.grid_size = 15
		case 2:
			app.settings.grid_size = 20
		case 3:
			app.settings.grid_size = 25
		}
	}

	item_y += item_height + spacing

	// --- Fullscreen ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_FULLSCREEN")),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	fs_text :=
		constants.get_text("UI_ON") if app.settings.fullscreen else constants.get_text("UI_OFF")
	if render_button(fs_text, {f32(ctrl_x), f32(item_y), f32(btn_width), f32(btn_height)}) {
		app.settings.fullscreen = !app.settings.fullscreen
		
		// Toggle window state
		if app.settings.fullscreen {
			if !raylib.IsWindowFullscreen() {
				monitor := raylib.GetCurrentMonitor()
				monitor_pos := raylib.GetMonitorPosition(monitor)
				raylib.SetWindowPosition(i32(monitor_pos.x), i32(monitor_pos.y))
				raylib.SetWindowSize(raylib.GetMonitorWidth(monitor), raylib.GetMonitorHeight(monitor))
				raylib.SetWindowState({.WINDOW_UNDECORATED})
				raylib.ToggleFullscreen()
			}
		} else {
			if raylib.IsWindowFullscreen() {
				raylib.ClearWindowState({.WINDOW_UNDECORATED})
				raylib.ToggleFullscreen()
				raylib.SetWindowSize(800, 600)
			}
		}
	}

	item_y += item_height + spacing

	// --- V-Sync ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_VSYNC")),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	vsync_text :=
		constants.get_text("UI_ON") if app.settings.vsync else constants.get_text("UI_OFF")
	if render_button(vsync_text, {f32(ctrl_x), f32(item_y), f32(btn_width), f32(btn_height)}) {
		app.settings.vsync = !app.settings.vsync
		if app.settings.vsync {
			raylib.SetWindowState({.VSYNC_HINT})
		} else {
			raylib.ClearWindowState({.VSYNC_HINT})
		}
	}

	item_y += item_height + spacing

	// --- Show Grid ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_SHOW_GRID")),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	grid_text :=
		constants.get_text("UI_ON") if app.settings.show_grid else constants.get_text("UI_OFF")
	if render_button(grid_text, {f32(ctrl_x), f32(item_y), f32(btn_width), f32(btn_height)}) {
		app.settings.show_grid = !app.settings.show_grid
	}

	item_y += item_height + spacing

	// --- Damage Numbers ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_SHOW_DAMAGE_NUMBERS")),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	dmg_text :=
		constants.get_text("UI_ON") if app.settings.show_damage_numbers else constants.get_text("UI_OFF")
	if render_button(dmg_text, {f32(ctrl_x), f32(item_y), f32(btn_width), f32(btn_height)}) {
		app.settings.show_damage_numbers = !app.settings.show_damage_numbers
	}

	item_y += item_height + spacing

	// --- Tower Range ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_SHOW_TOWER_RANGE")),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	range_text :=
		constants.get_text("UI_ON") if app.settings.show_tower_range else constants.get_text("UI_OFF")
	if render_button(range_text, {f32(ctrl_x), f32(item_y), f32(btn_width), f32(btn_height)}) {
		app.settings.show_tower_range = !app.settings.show_tower_range
	}

	item_y += item_height + spacing

	// --- Show FPS ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_SHOW_FPS")),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	fps_text :=
		constants.get_text("UI_ON") if app.settings.show_fps else constants.get_text("UI_OFF")
	if render_button(fps_text, {f32(ctrl_x), f32(item_y), f32(btn_width), f32(btn_height)}) {
		app.settings.show_fps = !app.settings.show_fps
	}

	item_y += item_height + spacing

	// --- Auto Wave ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_AUTO_WAVE")),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	auto_text :=
		constants.get_text("UI_ON") if app.settings.auto_start_wave else constants.get_text("UI_OFF")
	if render_button(auto_text, {f32(ctrl_x), f32(item_y), f32(btn_width), f32(btn_height)}) {
		app.settings.auto_start_wave = !app.settings.auto_start_wave
	}

	// --- Back button (below panel) ---
	back_width := i32(constants.UI_BUTTON_WIDTH) * 2
	back_x := i32(panel_x) + panel_width / 2 - back_width / 2
	back_y := i32(panel_y) + panel_total_height + spacing
	if render_button(
		constants.get_text("SETTINGS_BACK_TO_MENU"),
		{f32(back_x), f32(back_y), f32(back_width), f32(btn_height)},
	) {
		entities.app_set_state(app, .MENU)
	}
}

// Global UI state
ui_active_dropdown_id: string = ""

// Render a select dropdown (or dropup)
// Returns true if a new option was selected
render_select :: proc(
	id: string,
	prefix: string,
	options: []string,
	selected_index: ^i32,
	x, y, width, height: i32,
	dropup: bool = false,
) -> bool {
	font_size := f32(constants.UI_BUTTON_FONT_SIZE)

	// Find max width among all options to keep width stable
	max_text_width: f32 = 0
	for opt in options {
		t := fmt.tprintf("%s%s", prefix, opt)
		w := f32(
			raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(t), font_size, 0).x,
		)
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

	hovered_main :=
		mouse_x >= x && mouse_x <= x + actual_width && mouse_y >= y && mouse_y <= y + height

	color := constants.UI_BUTTON_COLOR
	if hovered_main || is_open {
		color = constants.UI_BUTTON_HOVER_COLOR
	}

	raylib.DrawRectangleRounded(
		{
			f32(x + constants.UI_BUTTON_SHADOW_OFFSET),
			f32(y + constants.UI_BUTTON_SHADOW_OFFSET),
			f32(actual_width),
			f32(height),
		},
		constants.UI_BUTTON_ROUNDNESS,
		constants.TOWER_CORNER_SEGMENTS,
		constants.UI_BUTTON_SHADOW_COLOR,
	)
	raylib.DrawRectangleRounded(
		{f32(x), f32(y), f32(actual_width), f32(height)},
		constants.UI_BUTTON_ROUNDNESS,
		constants.TOWER_CORNER_SEGMENTS,
		color,
	)

	// Text
	text := fmt.tprintf("%s%s", prefix, options[selected_index^])
	text_width := f32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text), font_size, 0).x,
	)
	text_x := f32(x) + f32(actual_width) / 2 - text_width / 2
	text_y := f32(y) + f32(height) / 2 - font_size / 2
	raylib.DrawTextEx(
		constants.game_fonts.semibold,
		strings.clone_to_cstring(text),
		{text_x, text_y},
		font_size,
		0,
		constants.UI_TEXT_COLOR,
	)

	// Draw arrow indicator
	arrow_x := f32(x + actual_width - 15)
	arrow_y := f32(y + height / 2)
	if is_open {
		if dropup {
			raylib.DrawTriangle(
				{arrow_x - 5, arrow_y - 2},
				{arrow_x + 5, arrow_y - 2},
				{arrow_x, arrow_y + 3},
				constants.UI_TEXT_COLOR,
			)
		} else {
			raylib.DrawTriangle(
				{arrow_x, arrow_y - 3},
				{arrow_x + 5, arrow_y + 2},
				{arrow_x - 5, arrow_y + 2},
				constants.UI_TEXT_COLOR,
			)
		}
	} else {
		if dropup {
			raylib.DrawTriangle(
				{arrow_x, arrow_y - 3},
				{arrow_x + 5, arrow_y + 2},
				{arrow_x - 5, arrow_y + 2},
				constants.UI_TEXT_COLOR,
			)
		} else {
			raylib.DrawTriangle(
				{arrow_x - 5, arrow_y - 2},
				{arrow_x + 5, arrow_y - 2},
				{arrow_x, arrow_y + 3},
				constants.UI_TEXT_COLOR,
			)
		}
	}

	changed := false

	if is_open {
		list_height := i32(len(options)) * height
		list_y := dropup ? y - list_height : y + height

		// Draw list background shadow
		raylib.DrawRectangle(
			x + constants.UI_BUTTON_SHADOW_OFFSET,
			list_y + constants.UI_BUTTON_SHADOW_OFFSET,
			actual_width,
			list_height,
			constants.UI_BUTTON_SHADOW_COLOR,
		)

		for i := 0; i < len(options); i += 1 {
			item_y := dropup ? y - list_height + i32(i) * height : y + height + i32(i) * height

			hovered_item :=
				mouse_x >= x &&
				mouse_x <= x + actual_width &&
				mouse_y >= item_y &&
				mouse_y <= item_y + height

			item_color := constants.UI_BUTTON_COLOR
			if hovered_item {
				item_color = constants.UI_BUTTON_HOVER_COLOR
				if raylib.IsMouseButtonPressed(.LEFT) {
					selected_index^ = i32(i)
					changed = true
					ui_active_dropdown_id = "" // Close after selection
					play_sound(.CLICK)
				}
			}

			// Highlight current selection
			if i32(i) == selected_index^ && !hovered_item {
				item_color = raylib.Color{60, 60, 60, 255}
			}

			raylib.DrawRectangle(x, item_y, actual_width, height, item_color)
			raylib.DrawRectangleLines(
				x,
				item_y,
				actual_width,
				height,
				constants.UI_BUTTON_SHADOW_COLOR,
			)

			item_text := options[i]
			item_text_width := f32(
				raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(item_text), font_size, 0).x,
			)
			item_text_x := f32(x) + f32(actual_width) / 2 - item_text_width / 2
			item_text_y := f32(item_y) + f32(height) / 2 - font_size / 2
			raylib.DrawTextEx(
				constants.game_fonts.semibold,
				strings.clone_to_cstring(item_text),
				{item_text_x, item_text_y},
				font_size,
				0,
				constants.UI_TEXT_COLOR,
			)
		}

		// Click outside to close
		if raylib.IsMouseButtonPressed(.LEFT) && !hovered_main {
			hovered_list :=
				mouse_x >= x &&
				mouse_x <= x + actual_width &&
				mouse_y >= list_y &&
				mouse_y <= list_y + list_height
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
render_button_with_color :: proc(
	text: string,
	rect: raylib.Rectangle,
	base_color: raylib.Color,
	text_lines: i32 = 1,
	custom_font_size: f32 = 16.0,
) -> bool {
	x := i32(rect.x)
	y := i32(rect.y)
	width := i32(rect.width)
	height := i32(rect.height)

	actual_width := width
	actual_height := height

	font_size := custom_font_size
	line_spacing := font_size * 1.2

	// Calculate minimum height needed for the text (with padding)
	min_text_height := i32(f32(text_lines) * line_spacing + 16) // 8px padding top/bottom
	if min_text_height > height {
		actual_height = min_text_height
	}

	text_width :=
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text), font_size, 0).x
	if int(text_width) + 20 > int(width) {
		actual_width = i32(text_width) + 20
	}

	// Check hover
	mouse_pos := raylib.GetMousePosition()
	hovered := raylib.CheckCollisionPointRec(
		mouse_pos,
		{f32(x), f32(y), f32(actual_width), f32(actual_height)},
	)

	// Determine button color based on hover state
	color := base_color
	if hovered {
		// Darken on hover
		color = raylib.Color {
			u8(f32(base_color.r) * 0.9),
			u8(f32(base_color.g) * 0.9),
			u8(f32(base_color.b) * 0.9),
			base_color.a,
		}
		if raylib.IsMouseButtonDown(.LEFT) {
			color = raylib.Color {
				u8(f32(base_color.r) * 0.8),
				u8(f32(base_color.g) * 0.8),
				u8(f32(base_color.b) * 0.8),
				base_color.a,
			}
		}
	}

	raylib.DrawRectangleRounded(
		{
			f32(x + constants.UI_BUTTON_SHADOW_OFFSET),
			f32(y + constants.UI_BUTTON_SHADOW_OFFSET),
			f32(actual_width),
			f32(actual_height),
		},
		constants.UI_BUTTON_ROUNDNESS,
		constants.TOWER_CORNER_SEGMENTS,
		constants.UI_BUTTON_SHADOW_COLOR,
	)
	raylib.DrawRectangleRounded(
		{f32(x), f32(y), f32(actual_width), f32(actual_height)},
		constants.UI_BUTTON_ROUNDNESS,
		constants.TOWER_CORNER_SEGMENTS,
		color,
	)

	// Text (centered) - calculate vertical position based on number of lines
	total_text_height := f32(text_lines) * line_spacing
	start_y := f32(y) + f32(actual_height) / 2 - total_text_height / 2

	// Split text by newlines and render each line centered
	lines := strings.split(text, "\n")
	defer delete(lines)

	for line, i in lines {
		line_width :=
			raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(line), font_size, 0).x
		line_x := f32(x) + f32(actual_width) / 2 - line_width / 2
		line_y := start_y + f32(i) * line_spacing
		raylib.DrawTextEx(
			constants.game_fonts.semibold,
			strings.clone_to_cstring(line),
			{line_x, line_y},
			font_size,
			0,
			constants.UI_TEXT_COLOR,
		)
	}

	// Click check
	if hovered && raylib.IsMouseButtonPressed(.LEFT) {
		play_sound(.CLICK)
		return true
	}

	return false
}

render_slider :: proc(rect: raylib.Rectangle, value: f32) -> f32 {
	font_size := f32(constants.UI_BUTTON_FONT_SIZE)

	raylib.DrawRectangleRounded(rect, constants.UI_ROUNDNESS, constants.UI_SEGMENTS, constants.UI_BUTTON_COLOR)

	return value
}

render_button :: proc(
	text: string,
	rect: raylib.Rectangle,
	text_lines: i32 = 1,
	enabled: bool = true,
	text_color: raylib.Color = constants.UI_TEXT_COLOR,
	button_color: raylib.Color = raylib.Color{0, 0, 0, 0},
	button_hover_color: raylib.Color = raylib.Color{0, 0, 0, 0},
	button_pressed_color: raylib.Color = raylib.Color{0, 0, 0, 0},
) -> bool {
	font_size := f32(constants.UI_BUTTON_FONT_SIZE)
	text_width := f32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text), font_size, 0).x,
	)

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

	hovered := mouse_x >= x && mouse_x <= x + actual_width && mouse_y >= y && mouse_y <= y + height

	if !enabled || ui_active_dropdown_id != "" {
		hovered = false
	}

	color := constants.UI_BUTTON_COLOR
	if button_color.a != 0 {
		color = button_color
	}
	if !enabled {
		color = raylib.DARKGRAY
	} else if hovered {
		if button_hover_color.a != 0 {
			color = button_hover_color
		} else {
			color = constants.UI_BUTTON_HOVER_COLOR
		}
		if raylib.IsMouseButtonDown(.LEFT) {
			if button_pressed_color.a != 0 {
				color = button_pressed_color
			} else {
				color = constants.UI_BUTTON_PRESSED_COLOR
			}
		}
	}

	raylib.DrawRectangleRounded(
		{
			f32(x + constants.UI_BUTTON_SHADOW_OFFSET),
			f32(y + constants.UI_BUTTON_SHADOW_OFFSET),
			f32(actual_width),
			f32(height),
		},
		constants.UI_BUTTON_ROUNDNESS,
		8,
		constants.UI_BUTTON_SHADOW_COLOR,
	)
	raylib.DrawRectangleRounded(
		{f32(x), f32(y), f32(actual_width), f32(height)},
		constants.UI_BUTTON_ROUNDNESS,
		constants.TOWER_CORNER_SEGMENTS,
		color,
	)

	// Text (centered) - handle multi-line text properly
	line_spacing := font_size * 1.2 // Approximate line spacing for multi-line text
	total_text_height := f32(text_lines) * line_spacing
	start_y := f32(y) + f32(height) / 2 - total_text_height / 2

	// Split text by newlines and render each line centered
	lines := strings.split(text, "\n")
	defer delete(lines)

	for line, i in lines {
		line_width :=
			raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(line), font_size, 0).x
		line_x := f32(x) + f32(actual_width) / 2 - line_width / 2
		line_y := start_y + f32(i) * line_spacing
		raylib.DrawTextEx(
			constants.game_fonts.semibold,
			strings.clone_to_cstring(line),
			{line_x, line_y},
			font_size,
			0,
			text_color,
		)
	}

	// Click check
	if hovered && raylib.IsMouseButtonPressed(.LEFT) {
		play_sound(.CLICK)
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
	if app.selected_tower == nil && !app.selected_obstacle.valid {
		return false
	}

	panel_rect := raylib.Rectangle {
		x      = f32(
			raylib.GetScreenWidth() - constants.UI_PANEL_WIDTH - constants.UI_PANEL_MARGIN,
		),
		y      = f32(constants.UI_PANEL_Y_POSITION),
		width  = f32(constants.UI_PANEL_WIDTH),
		height = f32(constants.UI_PANEL_HEIGHT),
	}

	return is_mouse_over_rect(panel_rect)
}

// Unified tower drawing function (JS style) - works for both editor and simulation
// This is the main function that should be used everywhere
draw_tower_tile :: proc(
	x, y: f32,
	cs: f32,
	tower_type: constants.Tower_Type,
	angle: f32 = 0,
	is_ghost: bool = false,
) {
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
			raylib.Rectangle {
				f32(bx + shadow_offset),
				f32(by + shadow_offset),
				f32(base_w),
				f32(base_h),
			},
			constants.TOWER_ROUNDED_CORNER,
			constants.TOWER_CORNER_SEGMENTS,
			constants.TOWER_SHADOW,
		)
	}

	// Draw base
	raylib.DrawRectangleRounded(
		raylib.Rectangle{f32(bx), f32(by), f32(base_w), f32(base_h)},
		constants.TOWER_ROUNDED_CORNER,
		constants.TOWER_CORNER_SEGMENTS,
		fill,
	)

	// Draw stroke
	raylib.DrawRectangleRoundedLines(
		raylib.Rectangle{f32(bx), f32(by), f32(base_w), f32(base_h)},
		constants.TOWER_ROUNDED_CORNER,
		constants.TOWER_CORNER_SEGMENTS,
		2,
		stroke,
	)

	// Draw tower-specific components
	r := cs * 0.25
	so := cs * 0.03 // Shadow offset for components

	// Rotate for barrel orientation (pointing up by default like JS: angle + PI/2)
	rotation := angle + math.PI / 2

	// Draw tower components with shadows immediately after each component
	switch tower_type {
	case .LASER:
		// Barrel dimensions (matching JS: -cs*0.1, -cs*0.35, cs*0.2, cs*0.3)
		barrel_w := cs * 0.2
		barrel_h := cs * 0.3
		origin := raylib.Vector2{f32(barrel_w / 2), f32(barrel_h)} // Pivot at bottom of barrel (tower center)
		laser_rotation := rotation * 180.0 / math.PI

		// Barrel shadow - rotated using DrawRectanglePro with pivot at tower center
		barrel_rect := raylib.Rectangle {
			x      = f32(cx + so),
			y      = f32(cy + so),
			width  = f32(barrel_w),
			height = f32(barrel_h),
		}
		raylib.DrawRectanglePro(barrel_rect, origin, laser_rotation, constants.TOWER_SHADOW)

		// Barrel - rotated using DrawRectanglePro with pivot at tower center
		barrel_rect = raylib.Rectangle {
			x      = f32(cx),
			y      = f32(cy),
			width  = f32(barrel_w),
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
		barrel_rect := raylib.Rectangle {
			x      = f32(cx + so),
			y      = f32(cy + so),
			width  = f32(barrel_w),
			height = f32(barrel_h),
		}
		origin := raylib.Vector2{f32(barrel_w / 2), f32(barrel_h)}
		cannon_rotation := rotation * 180.0 / math.PI
		raylib.DrawRectanglePro(barrel_rect, origin, cannon_rotation, constants.TOWER_SHADOW)

		// Barrel - rotated using DrawRectanglePro with pivot at tower center
		barrel_rect = raylib.Rectangle {
			x      = f32(cx),
			y      = f32(cy),
			width  = f32(barrel_w),
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
		barrel_rect := raylib.Rectangle {
			x      = f32(cx + so),
			y      = f32(cy + so),
			width  = f32(barrel_w),
			height = f32(barrel_h),
		}
		origin := raylib.Vector2{f32(barrel_w / 2), f32(barrel_h)}
		sniper_rotation := rotation * 180.0 / math.PI
		raylib.DrawRectanglePro(barrel_rect, origin, sniper_rotation, constants.TOWER_SHADOW)

		// Thin barrel - rotated using DrawRectanglePro with pivot at tower center
		barrel_rect = raylib.Rectangle {
			x      = f32(cx),
			y      = f32(cy),
			width  = f32(barrel_w),
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
		right_world_x :=
			cx + right_local_x * math.cos(rotation) - right_local_y * math.sin(rotation)
		right_world_y :=
			cy + right_local_x * math.sin(rotation) + right_local_y * math.cos(rotation)

		// Pod origin at top-left corner (0,0) since we position the rect at its world position
		pod_origin := raylib.Vector2{0, 0}

		// Left pod shadow
		raylib.DrawRectanglePro(
			raylib.Rectangle{f32(left_world_x + so), f32(left_world_y + so), pod_w, pod_h},
			pod_origin,
			missile_rotation_deg,
			constants.TOWER_SHADOW,
		)

		// Right pod shadow
		raylib.DrawRectanglePro(
			raylib.Rectangle{f32(right_world_x + so), f32(right_world_y + so), pod_w, pod_h},
			pod_origin,
			missile_rotation_deg,
			constants.TOWER_SHADOW,
		)

		// Left pod
		raylib.DrawRectanglePro(
			raylib.Rectangle{f32(left_world_x), f32(left_world_y), pod_w, pod_h},
			pod_origin,
			missile_rotation_deg,
			pod_color,
		)

		// Right pod
		raylib.DrawRectanglePro(
			raylib.Rectangle{f32(right_world_x), f32(right_world_y), pod_w, pod_h},
			pod_origin,
			missile_rotation_deg,
			pod_color,
		)

	case .ARCHER:
		// Crossbow-style barrel - rotated using DrawRectanglePro with pivot at tower center
		barrel_w := cs * 0.12
		barrel_h := cs * 0.4

		// Barrel shadow - positioned at tower center + offset, origin at bottom center
		barrel_rect := raylib.Rectangle {
			x      = f32(cx + so),
			y      = f32(cy + so),
			width  = f32(barrel_w),
			height = f32(barrel_h),
		}
		origin := raylib.Vector2{f32(barrel_w / 2), f32(barrel_h)} // Pivot at bottom of barrel (tower center)
		archer_rotation := rotation * 180.0 / math.PI
		raylib.DrawRectanglePro(barrel_rect, origin, archer_rotation, constants.TOWER_SHADOW)

		// Barrel (main body) - positioned at tower center, origin at bottom center
		barrel_rect = raylib.Rectangle {
			x      = f32(cx),
			y      = f32(cy),
			width  = f32(barrel_w),
			height = f32(barrel_h),
		}
		raylib.DrawRectanglePro(barrel_rect, origin, archer_rotation, constants.TOWER_ARCHER_WOOD)
	}
}

// Render tower for simulation (calls unified function with rotation)
render_tower :: proc(app: ^entities.App_State, tower: ^entities.Tower, x, y, cs: f32) {
	// Draw tower
	draw_tower_tile(x, y, cs, tower.type, tower.angle, false)
	// Draw upgrade indicators on top (only on hover)
	render_tower_upgrades(tower, x, y, cs, true)
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
	raylib.DrawLineEx(
		raylib.Vector2{f32(rx), f32(ry)},
		raylib.Vector2{f32(rx + reticle_len), f32(ry)},
		f32(corner_thickness),
		color,
	)
	raylib.DrawLineEx(
		raylib.Vector2{f32(rx), f32(ry)},
		raylib.Vector2{f32(rx), f32(ry + reticle_len)},
		f32(corner_thickness),
		color,
	)

	// Top-right corner
	raylib.DrawLineEx(
		raylib.Vector2{f32(rx + reticle_size - reticle_len), f32(ry)},
		raylib.Vector2{f32(rx + reticle_size), f32(ry)},
		f32(corner_thickness),
		color,
	)
	raylib.DrawLineEx(
		raylib.Vector2{f32(rx + reticle_size), f32(ry)},
		raylib.Vector2{f32(rx + reticle_size), f32(ry + reticle_len)},
		f32(corner_thickness),
		color,
	)

	// Bottom-left corner
	raylib.DrawLineEx(
		raylib.Vector2{f32(rx), f32(ry + reticle_size - reticle_len)},
		raylib.Vector2{f32(rx), f32(ry + reticle_size)},
		f32(corner_thickness),
		color,
	)
	raylib.DrawLineEx(
		raylib.Vector2{f32(rx), f32(ry + reticle_size)},
		raylib.Vector2{f32(rx + reticle_len), f32(ry + reticle_size)},
		f32(corner_thickness),
		color,
	)

	// Bottom-right corner
	raylib.DrawLineEx(
		raylib.Vector2{f32(rx + reticle_size), f32(ry + reticle_size - reticle_len)},
		raylib.Vector2{f32(rx + reticle_size), f32(ry + reticle_size)},
		f32(corner_thickness),
		color,
	)
	raylib.DrawLineEx(
		raylib.Vector2{f32(rx + reticle_size - reticle_len), f32(ry + reticle_size)},
		raylib.Vector2{f32(rx + reticle_size), f32(ry + reticle_size)},
		f32(corner_thickness),
		color,
	)
}

// Tower control panel state
tower_panel_active: bool = false
tower_panel_strategy_active: i32 = 0 // 0 = FIRST, 1 = LAST, 2 = MAX_HP, 3 = MIN_HP

// Game session stats (tracked across play session)
game_session_start_time: f64 = 0
game_session_end_time: f64 = 0
game_session_total_kills: i32 = 0

// Render panel with rounded corners and optional title
// Returns a rectangle representing the available content area
render_panel :: proc(rect: raylib.Rectangle, title: string = "") -> raylib.Rectangle {
	x := i32(rect.x)
	y := i32(rect.y)
	width := i32(rect.width)
	height := i32(rect.height)

	// Draw full panel background uniformly
	raylib.DrawRectangleRounded(rect, constants.UI_BUTTON_ROUNDNESS / 4, constants.TOWER_CORNER_SEGMENTS, raylib.RAYWHITE)

	// Draw title inside panel margins if provided
	title_height: i32 = 0
	if title != "" {
		title_height = 30 // Space for title line
		title_cstr := strings.clone_to_cstring(title)
		raylib.DrawTextEx(
			constants.game_fonts.bold,
			title_cstr,
			{f32(x + 10), f32(y + 10)},
			22,
			0,
			constants.PANEL_TEXT_COLOR,
		)
	}

	// Calculate content area (below title with margin)
	content_x := x + 10
	content_y := y + 10 + title_height
	content_width := width - 20
	content_height := height - 20 - title_height // 10px top + bottom padding

	return raylib.Rectangle {
		x = f32(content_x),
		y = f32(content_y),
		width = f32(content_width),
		height = f32(content_height),
	}
}

// Render tower control panel
render_tower_control_panel :: proc(app: ^entities.App_State) {
	// Only show if a tower is selected
	if app.selected_tower == nil {
		tower_panel_active = false
		return
	}

	tower := app.selected_tower

	// Panel dimensions and position
	panel_rect := raylib.Rectangle {
		x      = f32(raylib.GetScreenWidth() - constants.UI_PANEL_WIDTH - constants.UI_MARGIN_X),
		y      = f32(constants.UI_PANEL_Y_POSITION),
		width  = f32(constants.UI_PANEL_WIDTH),
		height = f32(constants.UI_PANEL_HEIGHT),
	}

	// Render panel background and get content area
	content_area := render_panel(panel_rect, "")
	content_x := i32(content_area.x)
	content_y := i32(content_area.y)
	content_width := i32(content_area.width)
	content_height := i32(content_area.height)

	// Calculate button dimensions based on content area
	button_width := content_width
	button_height: i32 = 30

	// Calculate spacing to distribute elements evenly in available space
	// We have: info text + 4 upgrade buttons + strategy dropdown + sell button
	// Total elements: 7 (with spacing between them)
	info_height: i32 = 25 // Space for tower info text
	strategy_height: i32 = 30 // Height for strategy dropdown
	num_buttons: i32 = 5 // Damage, Speed, Critical, Exit, Sell
	total_elements_height := info_height + (num_buttons * button_height) + strategy_height
	remaining_space := content_height - total_elements_height
	spacing := remaining_space / (num_buttons + 2) // Distribute spacing between elements

	// Tower info (at top of content area)
	type_name := ""
	switch tower.type {
	case .ARCHER:
		type_name = constants.get_text("TOWER_ARCHER_NAME")
	case .CANNON:
		type_name = constants.get_text("TOWER_CANNON_NAME")
	case .SNIPER:
		type_name = constants.get_text("TOWER_SNIPER_NAME")
	case .MISSILE:
		type_name = constants.get_text("TOWER_MISSILE_NAME")
	case .LASER:
		type_name = constants.get_text("TOWER_LASER_NAME")
	}

	info_text := constants.get_text_f("PANEL_TOWER_INFO", type_name, tower.level)
	info_cstr := strings.clone_to_cstring(info_text)
	current_y := content_y
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		info_cstr,
		{f32(content_x), f32(current_y)},
		20,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	current_y += info_height + spacing

	// Stats display in two columns
	stats_height: i32 = 40
	stats_spacing: i32 = 10
	col_width := content_width / 2 - stats_spacing / 2
	font_size: f32 = 14

	// Column 1: Damage and Range
	col1_x := content_x
	col1_y := current_y

	stat_damage_text := fmt.tprintf("Daño: %.1f", tower.damage)
	stat_damage_cstr := strings.clone_to_cstring(stat_damage_text)
	raylib.DrawTextEx(
		constants.game_fonts.semibold,
		stat_damage_cstr,
		{f32(col1_x), f32(col1_y)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)

	range_text := fmt.tprintf("Rango: %.1f", tower.range)
	range_cstr := strings.clone_to_cstring(range_text)
	raylib.DrawTextEx(
		constants.game_fonts.semibold,
		range_cstr,
		{f32(col1_x), f32(col1_y) + font_size + 5},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)

	// Column 2: Speed (cooldown) and Critical
	col2_x := content_x + col_width + stats_spacing
	col2_y := current_y

	cooldown_text := fmt.tprintf("Velocidad: %.2fs", tower.cooldown)
	cooldown_cstr := strings.clone_to_cstring(cooldown_text)
	raylib.DrawTextEx(
		constants.game_fonts.semibold,
		cooldown_cstr,
		{f32(col2_x), f32(col2_y)},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)

	crit_chance := entities.tower_get_critical_chance(tower)
	stat_crit_text := fmt.tprintf("Críticos: %.1f%%", crit_chance * 100)
	stat_crit_cstr := strings.clone_to_cstring(stat_crit_text)
	raylib.DrawTextEx(
		constants.game_fonts.semibold,
		stat_crit_cstr,
		{f32(col2_x), f32(col2_y) + font_size + 5},
		font_size,
		0,
		constants.PANEL_TEXT_COLOR,
	)

	current_y += stats_height + spacing

	// Upgrade Damage button
	damage_cost :=
		constants.UPGRADE_COST_BASE +
		(tower.damage_level - 1) * constants.UPGRADE_COST_INCREMENTVEL
	damage_text := constants.get_text_f("PANEL_BUTTON_DAMAGE", damage_cost)
	can_afford_damage := app.sim.money >= damage_cost

	if render_button(
		   damage_text,
		   {f32(content_x), f32(current_y), f32(button_width), f32(button_height)},
	   ) &&
	   can_afford_damage {
		entities.tower_upgrade_damage(tower)
		app.sim.money -= damage_cost
		app.sim.upgrades_bought += 1
		play_sound(.CONFIRMATION)
	}
	current_y += button_height + spacing

	// Upgrade Speed button
	speed_cost :=
		constants.UPGRADE_COST_BASE + (tower.rate_level - 1) * constants.UPGRADE_COST_INCREMENTVEL
	speed_text := constants.get_text_f("PANEL_BUTTON_SPEED", speed_cost)
	can_afford_speed := app.sim.money >= speed_cost

	if render_button(
		   speed_text,
		   {f32(content_x), f32(current_y), f32(button_width), f32(button_height)},
	   ) &&
	   can_afford_speed {
		entities.tower_upgrade_rate(tower)
		app.sim.money -= speed_cost
		app.sim.upgrades_bought += 1
		play_sound(.CONFIRMATION)
	}
	current_y += button_height + spacing

	// Upgrade Critical button
	crit_cost :=
		constants.UPGRADE_COST_BASE +
		(tower.critical_level - 1) * constants.UPGRADE_COST_INCREMENTVEL
	crit_text := constants.get_text_f("PANEL_BUTTON_CRITICAL", crit_cost)
	can_afford_crit := app.sim.money >= crit_cost

	if render_button(
		   crit_text,
		   {f32(content_x), f32(current_y), f32(button_width), f32(button_height)},
	   ) &&
	   can_afford_crit {
		entities.tower_upgrade_critical(tower)
		app.sim.money -= crit_cost
		app.sim.upgrades_bought += 1
		play_sound(.CONFIRMATION)
	}
	current_y += button_height + spacing

	// Exit button
	if render_button(
		constants.get_text("MENU_BUTTON_EXIT"),
		{f32(content_x), f32(current_y), f32(button_width), f32(button_height)},
	) {
		app.should_quit = true
	}
	current_y += button_height + spacing

	// Strategy section with dropdown
	strategy_names := []string {
		constants.get_text("PANEL_STRATEGY_FIRST"),
		constants.get_text("PANEL_STRATEGY_LAST"),
		constants.get_text("PANEL_STRATEGY_STRONG"),
		constants.get_text("PANEL_STRATEGY_WEAK"),
	}
	strategy_index := i32(tower.target_strategy)

	if render_select(
		"strategy",
		constants.get_text("PANEL_STRATEGY_LABEL"),
		strategy_names,
		&strategy_index,
		content_x,
		current_y,
		button_width,
		strategy_height,
		true,
	) {
		tower.target_strategy = constants.Target_Strategy(strategy_index)
	}
	current_y += strategy_height + spacing

	// Delete/Sell button at the bottom
	refund := entities.tower_get_sell_refund(tower)
	delete_text := constants.get_text_f("PANEL_BUTTON_SELL", refund)

	if render_button(
		delete_text,
		{f32(content_x), f32(current_y), f32(button_width), f32(button_height)},
		1,
		true,
		constants.UI_TEXT_COLOR,
		raylib.RED,
		raylib.Color{200, 0, 0, 255},
		raylib.Color{170, 0, 0, 255},
	) {
		simulation_remove_tower_at(app, tower.r, tower.c)
		play_sound(.CONFIRMATION)
		return // Tower removed, exit panel
	}
}

// Render obstacle control panel
render_obstacle_control_panel :: proc(app: ^entities.App_State) {
	// Only show if an obstacle is selected
	if !app.selected_obstacle.valid {
		return
	}

	row := app.selected_obstacle.row
	col := app.selected_obstacle.col
	level := entities.map_get_obstacle_level(&app.editor.game_map, row, col)

	// Panel dimensions and position
	panel_rect := raylib.Rectangle {
		x      = f32(raylib.GetScreenWidth() - constants.UI_PANEL_WIDTH - constants.UI_MARGIN_X),
		y      = f32(constants.UI_PANEL_Y_POSITION),
		width  = f32(constants.UI_PANEL_WIDTH),
		height = f32(constants.UI_PANEL_HEIGHT),
	}

	// Render panel background and get content area
	content_area := render_panel(panel_rect, "")
	content_x := i32(content_area.x)
	content_y := i32(content_area.y)
	content_width := i32(content_area.width)
	content_height := i32(content_area.height)

	// Calculate button dimensions based on content area
	button_width := content_width
	button_height: i32 = 30

	// Calculate spacing to distribute elements evenly in available space
	// We have: info text + upgrade button + sell button
	// Total elements: 3 (with spacing between them)
	info_height: i32 = 25 // Space for obstacle info text
	num_buttons: i32 = 2 // Upgrade Level, Sell
	total_elements_height := info_height + (num_buttons * button_height)
	remaining_space := content_height - total_elements_height
	spacing := remaining_space / (num_buttons + 1) // Distribute spacing between elements

	// Obstacle info (at top of content area)
	info_text := constants.get_text_f("PANEL_OBSTACLE_INFO", level)
	info_cstr := strings.clone_to_cstring(info_text)
	current_y := content_y
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		info_cstr,
		{f32(content_x), f32(current_y)},
		20,
		0,
		constants.PANEL_TEXT_COLOR,
	)
	current_y += info_height + spacing

	// Upgrade Level button
	level_cost :=
		constants.UPGRADE_COST_BASE + (level - 1) * constants.UPGRADE_COST_INCREMENTVEL
	level_text := constants.get_text_f("PANEL_BUTTON_UPGRADE_LEVEL", level_cost)
	can_afford_level := app.sim.money >= level_cost

	if render_button(
		   level_text,
		   {f32(content_x), f32(current_y), f32(button_width), f32(button_height)},
	   ) &&
	   can_afford_level {
		entities.map_set_obstacle_level(&app.editor.game_map, row, col, level + 1)
		app.sim.money -= level_cost
		app.sim.upgrades_bought += 1
		play_sound(.CONFIRMATION)
	}
	current_y += button_height + spacing

	// Sell button
	sell_cost := level_cost / 2 // Refund half of upgrade cost
	sell_text := constants.get_text_f("PANEL_BUTTON_SELL", sell_cost)

	if render_button(
		sell_text,
		{f32(content_x), f32(current_y), f32(button_width), f32(button_height)},
		1,
		true,
		constants.UI_TEXT_COLOR,
		raylib.RED,
		raylib.Color{200, 0, 0, 255},
		raylib.Color{170, 0, 0, 255},
	) {
		app.editor.game_map.obstacle_grid[row][col] = .EMPTY
		app.sim.money += sell_cost
		app.selected_obstacle.valid = false
		play_sound(.CONFIRMATION)
	}
}

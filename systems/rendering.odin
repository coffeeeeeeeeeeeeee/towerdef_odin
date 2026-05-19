package systems

import "../constants"
import "../entities"
import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

// Render the entire game
render_game :: proc(app: ^entities.App_State) {
	ui_blocks_clear() // Reset click-blocking registry for this frame
	render_map(app)
	render_tower_ranges(app)
	render_map_objects(app)
	render_gameplay(app)
	render_ui(app)
}

// Render tower ranges (separate layer above grid)
render_tower_ranges :: proc(app: ^entities.App_State) {
	cs := f32(app.settings.cell_size) * app.zoom

	// All towers when the setting is on
	if app.settings.show_tower_range {
		for &tower in app.sim.towers {
			center_x := f32(tower.c) * cs + f32(app.camera_offset_x) + cs / 2
			center_y := f32(tower.r) * cs + f32(app.camera_offset_y) + cs / 2
			range_px := tower.range * cs
			raylib.DrawCircle(i32(center_x), i32(center_y), range_px, constants.TOWER_RANGE_PREVIEW)
		}
	}

	// Selected tower always gets a highlighted range ring, regardless of the setting
	if selected := entities.app_get_selected_tower(app); selected != nil {
		center_x := f32(selected.c) * cs + f32(app.camera_offset_x) + cs / 2
		center_y := f32(selected.r) * cs + f32(app.camera_offset_y) + cs / 2
		range_px := selected.range * cs
		cx_i := i32(center_x)
		cy_i := i32(center_y)

		// Relleno sutil dentro del área de rango
		raylib.DrawCircle(cx_i, cy_i, range_px, constants.TOWER_RANGE_PREVIEW)
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
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER, .TOWER_ICE, .TOWER_ENHANCE:
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

	render_obstacles(m, cs, m.width, m.height, app.camera_offset_x, app.camera_offset_y)

	// Draw laser beams (on top of everything)
	if app.state == .PLAYING || (app.state == .PAUSED && app.previous_state == .PLAYING) {
		render_laser_beams(app, cs)
	}

	// Draw reticle for selected tower in PLAYING/PAUSED modes
	if app.selected_tower_r >= 0 && (app.state == .PLAYING || app.state == .PAUSED) {
		sx := f32(app.selected_tower_c) * cs + f32(app.camera_offset_x)
		sy := f32(app.selected_tower_r) * cs + f32(app.camera_offset_y)
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

	render_paths(m, cs, m.width, m.height, app.camera_offset_x, app.camera_offset_y)

	// Grid lines
	if app.settings.show_grid {
		render_grid_lines(app, cs, i32(m.width), i32(m.height))
	}

	// Draw ghost in PLAYING/PAUSED modes when building
	if app.selected_cell.valid && (app.state == .PLAYING || app.state == .PAUSED) {
		if app.sim.selected_build_tower != .EMPTY {
			sx := f32(app.selected_cell.col) * cs + f32(app.camera_offset_x)
			sy := f32(app.selected_cell.row) * cs + f32(app.camera_offset_y)
			if app.sim.selected_build_tower == .OBSTACLE {
				// Ghost de obstáculo: preview semi-transparente
				draw_obstacle_preview(sx, sy, cs)
			} else {
				tower_type := tile_to_tower_type(app.sim.selected_build_tower)
				draw_tower_tile(sx, sy, cs, tower_type, 0, true) // is_ghost = true
				spec  := constants.TOWER_SPECS[tower_type]
				cx_px := i32(sx + cs / 2)
				cy_px := i32(sy + cs / 2)
				// Relleno semitransparente + outline nítido del rango
				raylib.DrawCircle(cx_px, cy_px, spec.range * cs, constants.TOWER_RANGE_PREVIEW)
				raylib.DrawCircleLines(cx_px, cy_px, spec.range * cs, constants.TOWER_RANGE_OUTLINE)
				// Círculo interior de AoE (solo si la torre tiene explosión)
				if spec.aoe > 0 {
					raylib.DrawCircleLines(cx_px, cy_px, spec.aoe * cs, raylib.Color{255, 180, 60, 180})
				}
			}
		}
	}
}

// Render paths
render_paths :: proc(m: ^entities.Map, cs: f32, map_w, map_h: i32, camera_offset_x, camera_offset_y: i32) {
	path_width := cs * constants.PATH_WIDTH_RATIO
	path_color := constants.BIOME_COLORS[m.biome].path

	is_path_like :: proc(m: ^entities.Map, row, col, map_w, map_h: i32) -> bool {
		if row < 0 || row >= map_h || col < 0 || col >= map_w {
			return false
		}
		tile := m.grid[row][col]
		return tile == .PATH || tile == .SPAWN || tile == .GOAL
	}

	for row in 0 ..< map_h {
		for col in 0 ..< map_w {
			tile := m.grid[row][col]
			if tile != .PATH && tile != .SPAWN && tile != .GOAL {
				continue
			}

			x := f32(col) * cs + f32(camera_offset_x)
			y := f32(row) * cs + f32(camera_offset_y)
			cx := x + cs / 2
			cy := y + cs / 2

			top := is_path_like(m, row - 1, col, map_w, map_h)
			right := is_path_like(m, row, col + 1, map_w, map_h)
			bottom := is_path_like(m, row + 1, col, map_w, map_h)
			left := is_path_like(m, row, col - 1, map_w, map_h)

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
render_grid_lines :: proc(app: ^entities.App_State, cs: f32, map_w, map_h: i32) {
	// Vertical lines (one per column boundary)
	for i in 0 ..= map_w {
		x := i32(f32(i) * cs) + app.camera_offset_x
		raylib.DrawLine(
			x, app.camera_offset_y,
			x, app.camera_offset_y + i32(f32(map_h) * cs),
			constants.COLOR_GRID_LINE,
		)
	}
	// Horizontal lines (one per row boundary)
	for i in 0 ..= map_h {
		y := i32(f32(i) * cs) + app.camera_offset_y
		raylib.DrawLine(
			app.camera_offset_x, y,
			app.camera_offset_x + i32(f32(map_w) * cs), y,
			constants.COLOR_GRID_LINE,
		)
	}
}


// Dibuja el fondo base de un tooltip: clampea a pantalla, sombra + rect redondeado RAYWHITE.
// Devuelve el rect final (ya clampeado) para que el caller posicione su contenido.
render_tooltip :: proc(rect: raylib.Rectangle) -> raylib.Rectangle {
	mx := f32(constants.TOOLTIP_MARGIN_X)
	my := f32(constants.TOOLTIP_MARGIN_Y)
	sw := f32(raylib.GetScreenWidth())
	sh := f32(raylib.GetScreenHeight())

	r := rect
	if r.x < mx                      { r.x = mx }
	if r.x + r.width  > sw - mx      { r.x = sw - r.width  - mx }
	if r.y < my                      { r.y = my }
	if r.y + r.height > sh - my      { r.y = sh - r.height - my }

	roundness := f32(constants.UI_TOOLTIP_ROUNDNESS)
	segments  := i32(constants.UI_TOOLTIP_SEGMENTS)
	raylib.DrawRectangleRounded(
		{
			r.x + constants.UI_TOOLTIP_SHADOW_OFF,
			r.y + constants.UI_TOOLTIP_SHADOW_OFF,
			r.width, r.height
		},
		roundness, segments, raylib.Color{0, 0, 0, 40},
	)
	raylib.DrawRectangleRounded(r, roundness, segments, raylib.RAYWHITE)
	return r
}

// Tooltip de texto simple.
render_label_tooltip :: proc(label: string, trigger_rect: raylib.Rectangle) {
	mouse := raylib.GetMousePosition()
	if !raylib.CheckCollisionPointRec(mouse, trigger_rect) {
		return
	}

	pad      := f32(10)
	font_sz  := f32(constants.UI_TOOLTIP_FONT_SIZE)
	label_cstr := strings.clone_to_cstring(label, context.temp_allocator)
	label_w := raylib.MeasureTextEx(constants.game_fonts.bold, label_cstr, font_sz, 0).x

	tip_w := label_w + pad * 2
	tip_h := font_sz + pad

	tip_x := trigger_rect.x + trigger_rect.width/2 - tip_w/2
	tip_y := trigger_rect.y - tip_h - f32(constants.UI_TOOLTIP_OFFSET)

	// render_tooltip clampea a pantalla con TOOLTIP_MARGIN_X/Y y devuelve el rect final
	r := render_tooltip({tip_x, tip_y, tip_w, tip_h})
	tip_x = r.x
	tip_y = r.y

	// Texto centrado verticalmente
	text_x := tip_x + tip_w/2 - label_w/2
	text_y := tip_y + tip_h/2 - font_sz/2
	raylib.DrawTextEx(
		constants.game_fonts.bold, label_cstr,
		{text_x, text_y}, font_sz, 0, constants.UI_PANEL_TEXT_COLOR,
	)
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
		shadow_color := constants.COLOR_ENEMY_SHADOW
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
		// Palmera (desierto) - vista cenital: hojas en rombo alargado con variación por seed
		seed        := hash_position(row, col)
		tree_colors := constants.BIOME_TREE_COLORS[.DESERT]

		// Jitter de posición
		jitter_x := (f32(seed % 7) - 3.0) * cs * 0.015
		jitter_y := (f32((seed / 7) % 7) - 3.0) * cs * 0.015
		cx := center_x + jitter_x
		cy := center_y + jitter_y

		// Sombra
		raylib.DrawCircle(i32(cx + cs*0.06), i32(cy + cs*0.06), cs * 0.30, constants.COLOR_ENEMY_SHADOW)

		// Parámetros generales
		frond_count := 6 + int(seed % 3)           // 6, 7 u 8 hojas
		base_rot    := f32(seed % 60) * math.PI / 180.0  // rotación global 0–59°
		inner_r     := cs * 0.06                    // distancia del centro a la base de cada hoja

		draw_rhombus_frond :: proc(
			cx, cy: f32,
			angle: f32,
			half_len_out: f32,  // distancia del pivote a la punta exterior
			half_len_in:  f32,  // distancia del pivote a la punta interior
			half_w: f32,        // semiancho en el punto más ancho
			mid_shift: f32,     // desplazamiento del punto medio a lo largo del eje (+ = hacia punta)
			color: raylib.Color,
		) {
			perp_x := -math.sin(angle)
			perp_y :=  math.cos(angle)
			fwd_x  :=  math.cos(angle)
			fwd_y  :=  math.sin(angle)

			// Punto medio desplazado a lo largo del eje de la hoja
			mid_x := cx + fwd_x * mid_shift
			mid_y := cy + fwd_y * mid_shift

			tip_out := raylib.Vector2{cx + fwd_x * half_len_out, cy + fwd_y * half_len_out}
			tip_in  := raylib.Vector2{cx - fwd_x * half_len_in,  cy - fwd_y * half_len_in}
			side_l  := raylib.Vector2{mid_x + perp_x * half_w,   mid_y + perp_y * half_w}
			side_r  := raylib.Vector2{mid_x - perp_x * half_w,   mid_y - perp_y * half_w}

			// Triángulo exterior (punta → lados)
			raylib.DrawTriangle(tip_out, side_r, side_l, color)
			// Triángulo interior (punta trasera → lados), mismo orden CCW
			raylib.DrawTriangle(tip_in, side_l, side_r, color)
		}

		for i in 0 ..< frond_count {
			// Ángulo base equidistribuido + rotación global
			base_angle := base_rot + f32(i) * 2.0 * math.PI / f32(frond_count)

			// Rotación desprolija por hoja usando bits distintos del seed
			leaf_seed := seed >> u32(i * 3 + 2)
			wobble    := (f32(leaf_seed % 21) - 10.0) * math.PI / 180.0  // ±10°
			angle     := base_angle + wobble

			// Largo variable por hoja
			len_seed     := seed >> u32(i * 5 + 1)
			len_factor   := 0.75 + f32(len_seed % 26) / 100.0  // 0.75 a 1.00
			half_len_out := (cs * 0.34) * len_factor
			half_len_in  := half_len_out * 0.22
			half_w       := cs * 0.07

			// Desplazamiento del punto medio: varía entre -30% y +30% del largo exterior
			mid_seed  := seed >> u32(i * 7 + 3)
			mid_shift := (f32(mid_seed % 13) - 6.0) / 6.0 * half_len_out * 0.30

			// Pivote en el borde del tronco en la dirección de la hoja
			leaf_cx := cx + math.cos(angle) * inner_r
			leaf_cy := cy + math.sin(angle) * inner_r

			// Hojas alternas más oscuras para dar profundidad
			color := tree_colors.layer_mid if i % 2 == 0 else tree_colors.layer_dark

			draw_rhombus_frond(leaf_cx, leaf_cy, angle, half_len_out, half_len_in, half_w, mid_shift, color)
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
	// Preview: barrera vertical (orientación por defecto)
	bar_w := cs * constants.OBSTACLE_BARRIER_THICKNESS
	bar_h := cs * constants.OBSTACLE_BARRIER_LENGTH
	bar_x := x + cs/2 - bar_w/2
	bar_y := y + cs/2 - bar_h/2
	rect  := raylib.Rectangle{bar_x, bar_y, bar_w, bar_h}
	shadow := raylib.Rectangle{bar_x + constants.OBSTACLE_BARRIER_SHADOW_OFFSET, bar_y + constants.OBSTACLE_BARRIER_SHADOW_OFFSET, bar_w, bar_h}
	raylib.DrawRectangleRounded(shadow, constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, constants.COLOR_OBSTACLE_SHADOW)
	raylib.DrawRectangleRounded(rect,   constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, constants.COLOR_OBSTACLE_FILL)
	raylib.DrawRectangleRoundedLines(rect, constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, constants.OBSTACLE_BARRIER_BORDER_THICK, constants.COLOR_OBSTACLE_BORDER)
}

// Render obstacles
render_obstacles :: proc(
	m: ^entities.Map,
	cs: f32,
	map_w, map_h: i32,
	camera_offset_x, camera_offset_y: i32,
) {

	// Helper: ¿es la celda adyacente parte del camino?
	is_path :: proc(m: ^entities.Map, r, c, map_w, map_h: i32) -> bool {
		if r < 0 || r >= map_h || c < 0 || c >= map_w { return false }
		t := m.grid[r][c]
		return t == .PATH || t == .SPAWN || t == .GOAL
	}

	for row in 0 ..< map_h {
		for col in 0 ..< map_w {
			if m.obstacle_grid[row][col] == .OBSTACLE {
				x := f32(col) * cs + f32(camera_offset_x)
				y := f32(row) * cs + f32(camera_offset_y)

				// Camino horizontal → barrera vertical (estrecha en X, larga en Y)
				// Camino vertical   → barrera horizontal (larga en X, estrecha en Y)
				has_h := is_path(m, row, col-1, map_w, map_h) || is_path(m, row, col+1, map_w, map_h)
				has_v := is_path(m, row-1, col, map_w, map_h) || is_path(m, row+1, col, map_w, map_h)

				cx := x + cs/2
				cy := y + cs/2

				if has_h && has_v {
					// Codo: barrera rotada 45°. DrawRectanglePro no soporta esquinas
					// redondeadas, así que el borde se simula con un rect más grande debajo.
					bar_w := cs * constants.OBSTACLE_BARRIER_THICKNESS
					bar_h := cs * constants.OBSTACLE_BARRIER_LENGTH
					bx    := cx - bar_w/2
					by    := cy - bar_h/2
					pivot := raylib.Vector2{bar_w/2, bar_h/2}
					be    := constants.OBSTACLE_BARRIER_BORDER_THICK
					so    := constants.OBSTACLE_BARRIER_SHADOW_OFFSET

					// Sombra
					raylib.DrawRectanglePro(
						{bx + so, by + so, bar_w, bar_h}, pivot, 45, constants.COLOR_OBSTACLE_SHADOW,
					)
					// Borde (rect ligeramente más grande)
					raylib.DrawRectanglePro(
						{bx - be/2, by - be/2, bar_w + be, bar_h + be},
						{(bar_w+be)/2, (bar_h+be)/2}, 45, constants.COLOR_OBSTACLE_BORDER,
					)
					// Fill
					raylib.DrawRectanglePro(
						{bx, by, bar_w, bar_h}, pivot, 45, constants.COLOR_OBSTACLE_FILL,
					)
				} else {
					// Recto: barrera alineada al eje, con esquinas redondeadas
					bar_w, bar_h: f32
					if has_v && !has_h {
						bar_w = cs * constants.OBSTACLE_BARRIER_LENGTH
						bar_h = cs * constants.OBSTACLE_BARRIER_THICKNESS
					} else {
						bar_w = cs * constants.OBSTACLE_BARRIER_THICKNESS
						bar_h = cs * constants.OBSTACLE_BARRIER_LENGTH
					}
					bx := cx - bar_w/2
					by := cy - bar_h/2
					rect   := raylib.Rectangle{bx, by, bar_w, bar_h}
					shadow := raylib.Rectangle{
						bx + constants.OBSTACLE_BARRIER_SHADOW_OFFSET,
						by + constants.OBSTACLE_BARRIER_SHADOW_OFFSET,
						bar_w, bar_h,
					}
					raylib.DrawRectangleRounded(shadow, constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, constants.COLOR_OBSTACLE_SHADOW)
					raylib.DrawRectangleRounded(rect,   constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, constants.COLOR_OBSTACLE_FILL)
					raylib.DrawRectangleRoundedLines(rect, constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, constants.OBSTACLE_BARRIER_BORDER_THICK, constants.COLOR_OBSTACLE_BORDER)
				}

				level := entities.map_get_obstacle_level(m, row, col)
				_ = level
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

// Render ice pulses — each is an expanding ring that fades as it grows
render_ice_pulses :: proc(app: ^entities.App_State, cs: f32) {
	for &pulse in app.sim.ice_pulses {
		// Screen center of the tower
		cx := pulse.x * cs + f32(app.camera_offset_x)
		cy := pulse.y * cs + f32(app.camera_offset_y)

		radius_px  := pulse.radius * cs
		// t goes 1→0 (full alpha at birth, transparent when done)
		t          := pulse.life / pulse.max_life
		alpha      := u8(t * 210.0)

		ring_thick := max(2.5, cs * 0.09)
		outer_r    := radius_px
		inner_r    := max(0.0, outer_r - ring_thick)

		// Faint filled disc — subtle interior glow
		raylib.DrawCircle(i32(cx), i32(cy), outer_r, raylib.Color{140, 220, 255, alpha / 4})

		// Bright ring edge
		raylib.DrawRing(
			raylib.Vector2{cx, cy},
			inner_r,
			outer_r,
			0,
			360,
			48,
			raylib.Color{180, 235, 255, alpha},
		)
	}
}

// Render gameplay elements (enemies, projectiles, effects)
render_gameplay :: proc(app: ^entities.App_State) {
	if app.state != .PLAYING && app.state != .PAUSED {
		return
	}

	cs := f32(app.settings.cell_size) * app.zoom

	// Render ice pulses (expanding rings, below enemies)
	render_ice_pulses(app, cs)

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

// Draw a single enemy shape at screen position (cx, cy).
// size is the radius/half-size in pixels. shadow_offset > 0 draws a drop shadow.
// Bosses are always drawn as squares; flying non-bosses as triangles; others as circles.
render_enemy_shape :: proc(cx, cy, size: f32, color: raylib.Color, is_flying: bool, is_boss: bool = false, shadow_offset: f32 = 0) {
	border_color := raylib.Color{
		u8(f32(color.r) * 0.6),
		u8(f32(color.g) * 0.6),
		u8(f32(color.b) * 0.6),
		color.a,
	}
	shadow_color := constants.COLOR_ENEMY_SHADOW
	sw := f32(constants.ENEMY_BORDER_THICKNESS)

	if is_boss {
		// Square — border rect then inner rect
		if shadow_offset > 0 {
			raylib.DrawRectangle(
				i32(cx - size + shadow_offset), i32(cy - size + shadow_offset),
				i32(size * 2), i32(size * 2),
				shadow_color,
			)
		}
		raylib.DrawRectangle(i32(cx - size), i32(cy - size), i32(size * 2), i32(size * 2), border_color)
		raylib.DrawRectangle(
			i32(cx - size + sw), i32(cy - size + sw),
			i32(size * 2 - sw * 2), i32(size * 2 - sw * 2),
			color,
		)
	} else if is_flying {
		if shadow_offset > 0 {
			v1s := raylib.Vector2{cx + shadow_offset, cy - size - 2 + shadow_offset}
			v2s := raylib.Vector2{cx - size - 2 + shadow_offset, cy + size + 2 + shadow_offset}
			v3s := raylib.Vector2{cx + size + 2 + shadow_offset, cy + size + 2 + shadow_offset}
			raylib.DrawTriangle(v1s, v2s, v3s, shadow_color)
		}
		v1 := raylib.Vector2{cx, cy - size}
		v2 := raylib.Vector2{cx - size, cy + size}
		v3 := raylib.Vector2{cx + size, cy + size}
		raylib.DrawTriangle(v1, v2, v3, color)
		raylib.DrawLineEx(v1, v2, sw, border_color)
		raylib.DrawLineEx(v2, v3, sw, border_color)
		raylib.DrawLineEx(v3, v1, sw, border_color)
	} else {
		if shadow_offset > 0 {
			raylib.DrawCircle(i32(cx + shadow_offset), i32(cy + shadow_offset), size, shadow_color)
		}
		raylib.DrawCircle(i32(cx), i32(cy), size, border_color)
		raylib.DrawCircle(i32(cx), i32(cy), size - sw, color)
	}
}

// Render all enemies in the simulation
render_enemies :: proc(app: ^entities.App_State, cs: f32) {
	for &enemy in app.sim.enemies {
		x := enemy.x * cs + f32(app.camera_offset_x)
		y := enemy.y * cs + f32(app.camera_offset_y)

		size  := entities.enemy_get_size(&enemy) * cs
		color := entities.enemy_get_color(&enemy)
		so    := max(f32(2), cs * 0.08)
		cx    := x + cs / 2
		cy    := y + cs / 2

		render_enemy_shape(cx, cy, size, color, enemy.is_flying, enemy.is_boss, so)

		// Slow overlay: translucent blue halo when slowed by ice tower
		if enemy.slow_timer > 0 {
			pulse := f32(math.abs(math.sin(f64(raylib.GetTime()) * 5.0)))
			alpha := u8(60.0 + 50.0 * pulse)
			raylib.DrawCircle(i32(cx), i32(cy), size + max(1.5, cs * 0.07), raylib.Color{100, 200, 255, alpha})
		}

		// Health bar
		hp_percent  := enemy.hp / enemy.max_hp
		hp_bar_w    := cs * 0.6
		hp_bar_h    := cs * 0.1
		hp_bar_x    := cx - hp_bar_w / 2
		hp_bar_y    := y - cs * 0.05

		raylib.DrawRectangle(i32(hp_bar_x), i32(hp_bar_y), i32(hp_bar_w), i32(hp_bar_h), raylib.DARKGRAY)

		if hp_percent > 0.01 {
			hp_color := raylib.GREEN
			if hp_percent < 0.3 {
				hp_color = raylib.Color{200, 50, 50, 255}
			} else if hp_percent < 0.6 {
				hp_color = raylib.YELLOW
			}
			fill_w := max(hp_bar_w * hp_percent, 1.0)
			raylib.DrawRectangle(i32(hp_bar_x), i32(hp_bar_y), i32(fill_w), i32(hp_bar_h), hp_color)
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

		#partial switch proj.type {
		case .ARCHER:
			// Flecha: fuste + punta metálica + plumas
			angle  := proj.angle
			cos_a  := math.cos(angle)
			sin_a  := math.sin(angle)
			perp_x := -sin_a
			perp_y :=  cos_a

			arrow_len     := cs * 0.42
			head_len      := cs * 0.16
			shaft_thick   := cs * 0.06
			fletch_len    := cs * 0.10
			fletch_spread := cs * 0.08

			// Puntos del fuste
			back_x  := x - cos_a * (arrow_len * 0.55)
			back_y  := y - sin_a * (arrow_len * 0.55)
			front_x := x + cos_a * (arrow_len * 0.38)
			front_y := y + sin_a * (arrow_len * 0.38)
			tip_x   := front_x + cos_a * head_len
			tip_y   := front_y + sin_a * head_len

			// Fuste (madera)
			raylib.DrawLineEx(
				{back_x, back_y},
				{front_x, front_y},
				shaft_thick,
				raylib.Color{160, 110, 55, 255},
			)

			// Punta metálica — orden CCW en screen-space (y hacia abajo)
			head_w := cs * 0.09
			raylib.DrawTriangle(
				{front_x - perp_x * head_w, front_y - perp_y * head_w},
				{front_x + perp_x * head_w, front_y + perp_y * head_w},
				{tip_x, tip_y},
				raylib.Color{80, 85, 95, 255},
			)

			// Plumas (dos líneas en la cola)
			fletch_root_x := back_x + cos_a * fletch_len
			fletch_root_y := back_y + sin_a * fletch_len
			fletch_color  := raylib.Color{180, 55, 55, 220}
			raylib.DrawLineEx(
				{fletch_root_x, fletch_root_y},
				{back_x + perp_x * fletch_spread, back_y + perp_y * fletch_spread},
				shaft_thick * 1.5,
				fletch_color,
			)
			raylib.DrawLineEx(
				{fletch_root_x, fletch_root_y},
				{back_x - perp_x * fletch_spread, back_y - perp_y * fletch_spread},
				shaft_thick * 1.5,
				fletch_color,
			)
		case .CANNON:
			// Cannonball - smaller gray circle at cannon tip
			raylib.DrawCircle(i32(x), i32(y), cs * 0.1, constants.COLOR_BLOCK)
		case .SNIPER:
			// Bullet - smaller gray circle at cannon tip
			raylib.DrawCircle(i32(x), i32(y), cs * 0.06, constants.COLOR_BLOCK)
		case .MISSILE:
			// Missile - cuerpo + punta cónica
			px    := x
			py    := y
			angle := proj.angle
			cos_a := math.cos(angle)
			sin_a := math.sin(angle)
			perp_x := -sin_a
			perp_y :=  cos_a

			missile_len   := cs * 0.38
			missile_thick := cs * 0.10
			body_color    := raylib.Color{110, 115, 125, 255}
			tip_color     := raylib.Color{220, 80, 60, 255} // rojo-naranja (ojiva)

			// Cuerpo
			back_x  := px - cos_a * (missile_len * 0.50)
			back_y  := py - sin_a * (missile_len * 0.50)
			front_x := px + cos_a * (missile_len * 0.28)
			front_y := py + sin_a * (missile_len * 0.28)

			raylib.DrawLineEx(
				{back_x, back_y},
				{front_x, front_y},
				missile_thick,
				body_color,
			)

			// Punta (ojiva) — orden CCW en screen-space
			head_w := missile_thick * 0.65
			tip_x  := px + cos_a * (missile_len * 0.58)
			tip_y  := py + sin_a * (missile_len * 0.58)

			raylib.DrawTriangle(
				{front_x - perp_x * head_w, front_y - perp_y * head_w},
				{front_x + perp_x * head_w, front_y + perp_y * head_w},
				{tip_x, tip_y},
				tip_color,
			)
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

		// Redondear al entero más cercano; si queda en 0 no dibujar nada
		display_value := i32(dn.value + 0.5)
		if display_value == 0 {
			continue
		}
		damage_text := fmt.ctprintf("%d", display_value)
		font_size := cs * 0.25
		if dn.is_critical {
			font_size = cs * 0.5
		}

		draw_text_with_outline(damage_text, {x, y}, font_size, 0, color, outline_color, 1)
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
		render_card_hand(app)
		if app.sim.card_selection_active {
			render_card_selection_overlay(app)
		}
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
			strings.clone_to_cstring(fps_text, context.temp_allocator),
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
		raylib.MeasureTextEx(constants.game_fonts.bold, strings.clone_to_cstring(title_text, context.temp_allocator), title_size, 0).x,
	)
	title_x := f32(screen_width) / 2 - title_width / 2
	title_y := f32(screen_height) / 4
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		strings.clone_to_cstring(title_text, context.temp_allocator),
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
	play_text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(play_text, context.temp_allocator), button_font_size, 0).x)
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
	editor_text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(editor_text, context.temp_allocator), button_font_size, 0).x)
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
	settings_text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(settings_text, context.temp_allocator), button_font_size, 0).x)
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
	exit_text_width := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(exit_text, context.temp_allocator), button_font_size, 0).x)
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

	// HUD info panels — 4 paneles separados, alineados a la izquierda
	hud_panel_w   : f32 = 110
	hud_panel_h   : f32 = constants.UI_PANEL_HEADER_SIZE + constants.UI_PANEL_PADDING * 2  // 32 + 28 = 60
	hud_panel_gap : f32 = constants.UI_MARGIN_Y / 2
	hud_px        := f32(constants.UI_MARGIN_X)
	hud_py        := f32(constants.UI_MARGIN_Y)

	// Money
	render_info_panel(
		{hud_px, hud_py, hud_panel_w, hud_panel_h},
		constants.get_text("UI_MONEY"),
		fmt.tprintf("%d", app.sim.money),
		constants.game_icons.money,
	)

	// Health
	hud_py += hud_panel_h + hud_panel_gap
	render_info_panel(
		{hud_px, hud_py, hud_panel_w, hud_panel_h},
		constants.get_text("UI_HEALTH"),
		fmt.tprintf("%d", app.sim.health),
		constants.game_icons.health,
	)

	// Wave
	hud_py += hud_panel_h + hud_panel_gap
	{
		display_wave := app.sim.wave_number
		if display_wave == 0 { display_wave = 1 }
		render_info_panel(
			{hud_px, hud_py, hud_panel_w, hud_panel_h},
			constants.get_text("UI_WAVE"),
			fmt.tprintf("%d", display_wave),
			constants.game_icons.wave,
		)
	}

	// Upcoming waves preview — 3 icons horizontal
	hud_py += hud_panel_h + hud_panel_gap
	{
		c := render_info_panel({hud_px, hud_py, hud_panel_w, hud_panel_h}, constants.get_text("UI_UPCOMING"))

		base_wave := app.sim.wave_number
		icon_r    : f32 = 9
		slot_w    := c.width / 3
		cy        := c.y + c.height / 2

		// Helper: nombre del sub-tipo para el tooltip del panel de próximas oleadas
		wave_type_label := proc(green, flying, blue, split, boss, bonus: bool) -> string {
			switch {
			case boss:   return constants.get_text("ENEMY_TYPE_BOSS")
			case bonus:  return constants.get_text("ENEMY_TYPE_BONUS")
			case green:  return constants.get_text("ENEMY_TYPE_FAST")
			case flying: return constants.get_text("ENEMY_TYPE_FLYING")
			case blue:   return constants.get_text("ENEMY_TYPE_HEALER")
			case split:  return constants.get_text("ENEMY_TYPE_SPLITTER")
			case:        return constants.get_text("ENEMY_TYPE_NORMAL")
			}
		}

		for i in 0 ..< 3 {
			wave_n    := base_wave + 1 + i32(i)
			cx        := c.x + (f32(i) + 0.5) * slot_w

			is_boss   := wave_n % constants.BOSS_WAVE_INTERVAL == 0
			is_bonus  := !is_boss && app.sim.lookahead_bonus[i]
			primary   := wave_n % 4
			is_green  := !is_boss && !is_bonus && primary == 1
			is_flying := !is_boss && !is_bonus && primary == 2
			is_blue   := !is_boss && !is_bonus && primary == 3
			is_split  := !is_boss && !is_bonus && primary == 0

			// Oleada mixta: secundario desfasado 2 (mismo cálculo que start_next_wave)
			is_mixed := !is_boss && !is_bonus && wave_n > constants.MIXED_WAVE_MIN_WAVE
			sec_green, sec_flying, sec_blue, sec_split := false, false, false, false
			if is_mixed {
				secondary  := (wave_n + 2) % 4
				sec_green   = secondary == 1
				sec_flying  = secondary == 2
				sec_blue    = secondary == 3
				sec_split   = secondary == 0
			}

			// Color primario
			wave_color: raylib.Color
			switch {
			case is_boss:   wave_color = constants.COLOR_ENEMY_BOSS
			case is_bonus:  wave_color = constants.COLOR_ENEMY_BONUS
			case is_green:  wave_color = constants.COLOR_ENEMY_GREEN
			case is_flying: wave_color = constants.COLOR_ENEMY_FLYING
			case is_blue:   wave_color = constants.COLOR_ENEMY_BLUE
			case is_split:  wave_color = constants.COLOR_ENEMY_SPLIT
			case:           wave_color = constants.COLOR_ENEMY
			}

			// Color secundario (solo en oleadas mixtas)
			sec_color: raylib.Color
			switch {
			case sec_green:  sec_color = constants.COLOR_ENEMY_GREEN
			case sec_flying: sec_color = constants.COLOR_ENEMY_FLYING
			case sec_blue:   sec_color = constants.COLOR_ENEMY_BLUE
			case sec_split:  sec_color = constants.COLOR_ENEMY_SPLIT
			}

			// Tooltip: nombre del tipo primario (y secundario si es oleada mixta)
			primary_name := wave_type_label(is_green, is_flying, is_blue, is_split, is_boss, is_bonus)
			tooltip: string
			if is_mixed {
				sec_name := wave_type_label(sec_green, sec_flying, sec_blue, sec_split, false, false)
				tooltip = fmt.tprintf("%s + %s", primary_name, sec_name)
			} else {
				tooltip = primary_name
			}

			// Ícono principal
			render_enemy_shape(cx, cy, icon_r, wave_color, is_flying, is_boss)

			// Punto secundario (esquina inferior-derecha del ícono principal)
			if is_mixed {
				sec_r : f32 = 4
				raylib.DrawCircle(i32(cx + icon_r - 1), i32(cy + icon_r - 1), sec_r, sec_color)
				raylib.DrawCircleLines(i32(cx + icon_r - 1), i32(cy + icon_r - 1), sec_r, raylib.ColorAlpha(raylib.BLACK, 0.4))
			}

			// Tooltip
			hit_r    := icon_r + 4
			hit_rect := raylib.Rectangle{cx - hit_r, cy - hit_r, hit_r * 2, hit_r * 2}
			render_label_tooltip(tooltip, hit_rect)
		}
	}

	font_size := f32(constants.UI_BUTTON_FONT_SIZE) // usado por el resto del proc

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
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(pause_text, context.temp_allocator), font_size, 0).x,
	)
	pause_width := pause_text_width + padding

	// 1x button width
	speed1_text := "1x"
	speed1_text_width := i32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(speed1_text, context.temp_allocator), font_size, 0).x,
	)
	speed1_width := speed1_text_width + padding

	// 2x button width
	speed2_text := "2x"
	speed2_text_width := i32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(speed2_text, context.temp_allocator), font_size, 0).x,
	)
	speed2_width := speed2_text_width + padding

	// 3x button width
	speed3_text := "3x"
	speed3_text_width := i32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(speed3_text, context.temp_allocator), font_size, 0).x,
	)
	speed3_width := speed3_text_width + padding

	// Calculate positions from right to left
	is_between_waves := app.sim.enemies_spawned >= app.sim.enemies_to_spawn && len(app.sim.enemies) == 0
	wave_limit_reached := app.sim.wave_number >= constants.MAX_WAVE
	can_start_wave := (is_between_waves || !app.sim.started) && !wave_limit_reached
	show_next_wave_button := !app.settings.auto_start_wave

	next_wave_text := constants.get_text("UI_NEXT_WAVE")
	next_wave_text_width := i32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(next_wave_text, context.temp_allocator), font_size, 0).x,
	)
	next_wave_width := next_wave_text_width + padding

	start_text := constants.get_text("UI_START")
	start_text_width := i32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(start_text, context.temp_allocator), font_size, 0).x,
	)
	start_width := start_text_width + padding

	// Calculate total width based on visible buttons
	visible_button_count := i32(5) // Start + Pause + 1x + 2x + 3x
	gap_count := i32(4)
	if show_next_wave_button {
		visible_button_count += 1
		gap_count += 1
	}
	total_buttons_width := pause_width + speed1_width + speed2_width + speed3_width + start_width + gap * gap_count + constants.UI_MARGIN_X
	if show_next_wave_button {
		total_buttons_width += next_wave_width
	}

	start_x  := screen_width - total_buttons_width
	next_wave_x := start_x + start_width + gap
	pause_x  := next_wave_x + (show_next_wave_button ? next_wave_width + gap : 0)
	speed1_x := pause_x + pause_width + gap
	speed2_x := speed1_x + speed1_width + gap
	speed3_x := speed2_x + speed2_width + gap

	// Active-state colors
	active_green        := constants.UI_BUTTON_ACTION_COLOR
	active_green_hover  := constants.UI_BUTTON_ACTION_HOVER
	active_green_press  := constants.UI_BUTTON_ACTION_PRESS
	active_yellow       := constants.UI_BUTTON_PAUSE_COLOR
	active_yellow_hover := constants.UI_BUTTON_PAUSE_HOVER
	active_yellow_press := constants.UI_BUTTON_PAUSE_PRESS
	no_color            := constants.COLOR_NONE

	// Start button (appears before first wave or between waves)
	if render_button(
		start_text,
		{f32(start_x), f32(button_y), f32(start_width), f32(constants.UI_BUTTON_HEIGHT)},
		1,
		can_start_wave,
		constants.UI_TEXT_COLOR,
		constants.UI_BUTTON_ACTION_COLOR,
		constants.UI_BUTTON_ACTION_HOVER,
		constants.UI_BUTTON_ACTION_PRESS,
	) {
		if can_start_wave {
			simulation_set_pause(app, false)
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
				simulation_set_pause(app, false)
				start_next_wave(app)
			}
		}
	}

	// Pause button — yellow when paused
	pause_col, pause_hover_col, pause_press_col := no_color, no_color, no_color
	if app.sim.paused {
		pause_col       = active_yellow
		pause_hover_col = active_yellow_hover
		pause_press_col = active_yellow_press
	}
	if render_button(
		pause_text,
		{f32(pause_x), f32(button_y), f32(pause_width), f32(constants.UI_BUTTON_HEIGHT)},
		1, true,
		constants.UI_TEXT_COLOR,
		pause_col, pause_hover_col, pause_press_col,
	) {
		simulation_toggle_pause(app)
	}

	// Speed buttons — green when that speed is active
	speed1_col, speed1_hover_col, speed1_press_col := no_color, no_color, no_color
	if app.sim.speed == 1.0 {
		speed1_col       = active_green
		speed1_hover_col = active_green_hover
		speed1_press_col = active_green_press
	}
	if render_button(
		speed1_text,
		{f32(speed1_x), f32(button_y), f32(speed1_width), f32(constants.UI_BUTTON_HEIGHT)},
		1, true,
		constants.UI_TEXT_COLOR,
		speed1_col, speed1_hover_col, speed1_press_col,
	) {
		simulation_set_speed(app, 1.0)
	}

	speed2_col, speed2_hover_col, speed2_press_col := no_color, no_color, no_color
	if app.sim.speed == 2.0 {
		speed2_col       = active_green
		speed2_hover_col = active_green_hover
		speed2_press_col = active_green_press
	}
	if render_button(
		speed2_text,
		{f32(speed2_x), f32(button_y), f32(speed2_width), f32(constants.UI_BUTTON_HEIGHT)},
		1, true,
		constants.UI_TEXT_COLOR,
		speed2_col, speed2_hover_col, speed2_press_col,
	) {
		simulation_set_speed(app, 2.0)
	}

	speed3_col, speed3_hover_col, speed3_press_col := no_color, no_color, no_color
	if app.sim.speed == 3.0 {
		speed3_col       = active_green
		speed3_hover_col = active_green_hover
		speed3_press_col = active_green_press
	}
	if render_button(
		speed3_text,
		{f32(speed3_x), f32(button_y), f32(speed3_width), f32(constants.UI_BUTTON_HEIGHT)},
		1, true,
		constants.UI_TEXT_COLOR,
		speed3_col, speed3_hover_col, speed3_press_col,
	) {
		simulation_set_speed(app, 3.0)
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
			{constants.get_text("TOWER_ICE_NAME"), .TOWER_ICE},
			{constants.get_text("TOWER_ENHANCE_NAME"), .TOWER_ENHANCE},
			{constants.get_text("EDITOR_TOOL_OBSTACLE"), .OBSTACLE},
			{constants.get_text("EDITOR_TOOL_TREE"), .ACCESSORY_TREE},
			{constants.get_text("EDITOR_TOOL_BLOCK"), .ACCESSORY_BLOCK},
		}

		button_width := i32(70) // slightly narrower to fit 13 buttons
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

			btn_rect := raylib.Rectangle{f32(x), f32(y), f32(button_width), f32(button_height)}

			if render_button_with_color(
				   "",
				   btn_rect,
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
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER, .TOWER_ICE, .TOWER_ENHANCE:
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
	}
}

// Render editor UI
render_editor_ui :: proc(app: ^entities.App_State) {
	screen_width := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	// Render build toolbar (shared logic)
	render_build_toolbar(app)

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
		constants.UI_MARGIN_X,
		constants.UI_MARGIN_Y,
		i32(constants.UI_DROPDOWN_WIDTH),
		i32(constants.UI_DROPDOWN_HEIGHT),
		false, // Changed to false for dropdown (opens downward)
	) {
		editor_push_undo(app)
		app.editor.current_biome = constants.Biome(biome_index)
		app.editor.game_map.biome = constants.Biome(biome_index)
	}

	// Right-side buttons - laid out from right to left with consistent gap
	y_pos := constants.UI_MARGIN_Y
	gap := i32(10)

	// Helper to calculate actual button width
	btn_w :: proc(text: string) -> i32 {
		text_width := i32(
			raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text, context.temp_allocator), f32(constants.UI_BUTTON_FONT_SIZE), 0).x,
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
		} else {
			entities.add_toast(app, constants.get_text("EDITOR_ERROR_NO_PATH"), .ERROR, 3.0)
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
		editor_push_undo(app)
		if entities.map_load(&app.editor.game_map, "last_saved.map") {
			app.editor.current_biome = app.editor.game_map.biome
			app.editor.current_map_name = "last_saved.map"
			entities.add_toast(app, "Map loaded!", .SUCCESS, 2.0)
			play_sound(.CONFIRMATION, .UI)
		} else {
			// Roll back the undo push since nothing changed
			if len(app.editor.undo_stack) > 0 {
				last := len(app.editor.undo_stack) - 1
				snap := app.editor.undo_stack[last]
				ordered_remove(&app.editor.undo_stack, last)
				entities.map_snapshot_destroy(&snap)
			}
			entities.add_toast(app, "No quick save found", .WARNING, 3.0)
			play_sound(.ERROR, .UI)
		}
	}

	// Browse Maps button
	current_x -= gap
	w_browse := btn_w(constants.get_text("EDITOR_BUTTON_BROWSE_MAPS"))
	current_x -= w_browse
	if render_button(
		constants.get_text("EDITOR_BUTTON_BROWSE_MAPS"),
		{f32(current_x), f32(y_pos), f32(w_browse), f32(constants.UI_BUTTON_HEIGHT)},
	) {
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
			play_sound(.OPEN, .UI)
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
		// Guarda con timestamp y también como last_saved.map para carga rápida
		filename := fmt.tprintf("map_%d.map", i32(raylib.GetTime()))
		if entities.map_save(&app.editor.game_map, filename) {
			app.editor.current_map_name = filename
			entities.add_toast(app, fmt.tprintf("Map saved: %s", filename), .SUCCESS, 2.5)
			play_sound(.CONFIRMATION, .UI)
		} else {
			entities.add_toast(app, "Failed to save map", .ERROR, 3.0)
			play_sound(.ERROR, .UI)
		}
		entities.map_save(&app.editor.game_map, "last_saved.map")
	}

	// Modal del browser de mapas (encima de todo el editor UI)
	if app.editor.show_map_browser {
		render_map_browser(app)
	}
}

// Render modal de selección de mapas guardados
render_map_browser :: proc(app: ^entities.App_State) {
	screen_width  := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	// Fondo semi-transparente que oscurece el editor debajo
	raylib.DrawRectangle(0, 0, screen_width, screen_height, constants.UI_MAP_BROWSER_OVERLAY_COLOR)

	// Posición y dimensiones del panel (todo i32 para aritmética limpia)
	panel_w := i32(constants.UI_MAP_BROWSER_WIDTH)
	panel_h := i32(constants.UI_MAP_BROWSER_HEIGHT)
	panel_x := screen_width / 2 - panel_w / 2
	panel_y := screen_height / 2 - panel_h / 2

	// Dibuja el shell del panel (sombra + fondo + título via render_panel)
	render_panel(
		{f32(panel_x), f32(panel_y), f32(panel_w), f32(panel_h)},
		constants.get_text("EDITOR_MAP_BROWSER_TITLE"),
	)

	// El contenido de la lista comienza debajo de la cabecera del panel
	list_top      := panel_y + constants.UI_MAP_BROWSER_HEADER_HEIGHT
	item_h        := i32(constants.UI_MAP_BROWSER_ITEM_HEIGHT)
	list_h        := panel_h - constants.UI_MAP_BROWSER_HEADER_HEIGHT - constants.UI_MAP_BROWSER_FOOTER_HEIGHT
	visible_items := list_h / item_h
	item_font     := f32(constants.UI_MAP_BROWSER_ITEM_FONT_SIZE)

	// Mensaje cuando no hay mapas guardados
	if len(app.editor.map_browser_files) == 0 {
		no_maps_cs := strings.clone_to_cstring("No saved maps found", context.temp_allocator)
		nw := raylib.MeasureTextEx(constants.game_fonts.regular, no_maps_cs, item_font, 0).x
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			no_maps_cs,
			{
				f32(panel_x) + f32(panel_w) / 2 - nw / 2,
				f32(list_top) + f32(list_h) / 2 - item_font / 2,
			},
			item_font, 0,
			constants.UI_MAP_BROWSER_MUTED_COLOR,
		)
	}

	mouse := raylib.GetMousePosition()

	for i in 0 ..< visible_items {
		idx := i + app.editor.map_browser_scroll
		if idx >= i32(len(app.editor.map_browser_files)) {
			break
		}

		fname  := app.editor.map_browser_files[idx]
		item_y := list_top + i * item_h

		// Rect del item con margen vertical entre filas
		item_rect := raylib.Rectangle{
			f32(panel_x + constants.UI_MAP_BROWSER_ITEM_SIDE_PADDING),
			f32(item_y + constants.UI_MAP_BROWSER_ITEM_VERT_GAP / 2),
			f32(panel_w - constants.UI_MAP_BROWSER_ITEM_SIDE_PADDING * 2),
			f32(item_h  - constants.UI_MAP_BROWSER_ITEM_VERT_GAP),
		}

		hovered := raylib.CheckCollisionPointRec(mouse, item_rect)
		if hovered {
			raylib.DrawRectangleRounded(
				item_rect,
				constants.UI_BUTTON_ROUNDNESS,
				constants.TOWER_CORNER_SEGMENTS,
				constants.UI_BUTTON_HOVER_COLOR,
			)
		}

		// El mapa actualmente cargado se muestra en verde
		text_color := constants.UI_TEXT_COLOR
		if fname == app.editor.current_map_name {
			text_color = constants.UI_MAP_BROWSER_LOADED_COLOR
		}

		fname_cs := strings.clone_to_cstring(fname, context.temp_allocator)
		// Centrar el texto verticalmente dentro del item rect
		text_y := item_rect.y + (f32(item_h - constants.UI_MAP_BROWSER_ITEM_VERT_GAP) - item_font) / 2
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			fname_cs,
			{item_rect.x + f32(constants.UI_MAP_BROWSER_ITEM_TEXT_INDENT), text_y},
			item_font, 0,
			text_color,
		)

		// Click para cargar el mapa seleccionado
		if hovered && raylib.IsMouseButtonPressed(.LEFT) {
			editor_push_undo(app)
			if entities.map_load(&app.editor.game_map, fname) {
				app.editor.current_biome    = app.editor.game_map.biome
				app.editor.current_map_name = strings.clone(fname)
				entities.add_toast(app, fmt.tprintf("Loaded: %s", fname), .SUCCESS, 2.0)
				play_sound(.CONFIRMATION, .UI)
			} else {
				// Roll back the undo push since nothing changed
				if len(app.editor.undo_stack) > 0 {
					last := len(app.editor.undo_stack) - 1
					snap := app.editor.undo_stack[last]
					ordered_remove(&app.editor.undo_stack, last)
					entities.map_snapshot_destroy(&snap)
				}
				entities.add_toast(app, fmt.tprintf("Failed to load: %s", fname), .ERROR, 3.0)
				play_sound(.ERROR, .UI)
			}
			app.editor.show_map_browser = false
		}
	}

	// Indicador de scroll cuando hay más mapas que los visibles
	total := i32(len(app.editor.map_browser_files))
	if total > visible_items {
		last_visible := min(app.editor.map_browser_scroll + visible_items, total)
		scroll_text  := fmt.tprintf(
			"%d-%d / %d  (scroll para navegar)",
			app.editor.map_browser_scroll + 1,
			last_visible,
			total,
		)
		scroll_font := f32(constants.UI_MAP_BROWSER_SCROLL_FONT_SIZE)
		scroll_cs   := strings.clone_to_cstring(scroll_text, context.temp_allocator)
		sw          := raylib.MeasureTextEx(constants.game_fonts.regular, scroll_cs, scroll_font, 0).x
		// Posición: centrado, justo arriba del botón Close
		scroll_y := f32(panel_y + panel_h - constants.UI_MAP_BROWSER_FOOTER_HEIGHT) + scroll_font
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			scroll_cs,
			{f32(panel_x) + f32(panel_w) / 2 - sw / 2, scroll_y},
			scroll_font, 0,
			constants.UI_MAP_BROWSER_MUTED_COLOR,
		)
	}

	// Botón Close centrado en la parte inferior del panel
	close_w := i32(constants.UI_BUTTON_WIDTH)
	close_h := i32(constants.UI_MAP_BROWSER_CLOSE_HEIGHT)
	close_x := panel_x + panel_w / 2 - close_w / 2
	close_y := panel_y + panel_h - close_h - constants.UI_MAP_BROWSER_CLOSE_BTN_MARGIN
	if render_button(
		"Close",
		{f32(close_x), f32(close_y), f32(close_w), f32(close_h)},
	) {
		app.editor.show_map_browser = false
		play_sound(.CLOSE, .UI)
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
	title_cstr := strings.clone_to_cstring(title, context.temp_allocator)
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
	title_cstr := strings.clone_to_cstring(title, context.temp_allocator)
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

	// ============================================================
	//  GRAPH PANEL
	// ============================================================
	graph_panel_w := i32(f32(screen_width) * 0.75)
	if graph_panel_w > 500 {graph_panel_w = 500}
	graph_panel_h := i32(f32(screen_height) * 0.35)
	if graph_panel_h > 220 {graph_panel_h = 220}
	graph_panel_x := f32(screen_width) / 2 - f32(graph_panel_w) / 2
	graph_panel_y := title_y + title_size + 12

	graph_rect := raylib.Rectangle {
		graph_panel_x,
		graph_panel_y,
		f32(graph_panel_w),
		f32(graph_panel_h),
	}
	graph_content := render_panel(graph_rect)

	// Graph area inside panel
	label_margin_l := i32(6)  // small padding left
	label_margin_r := i32(6)  // small padding right
	label_margin_b := i32(14) // bottom (wave markers)
	label_margin_t := i32(6)  // top padding

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

		// X-axis line
		raylib.DrawLine(
			i32(gx),
			i32(gy + gh),
			i32(gx + gw),
			i32(gy + gh),
			raylib.Color{180, 180, 180, 120},
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
				color = constants.COLOR_ENEMY_FLYING
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

	}

	// ============================================================
	//  STATS PANEL
	// ============================================================
	stats_panel_w := graph_panel_w
	num_stats :: 5
	stat_height := i32(font_size) + 4
	stats_inner := i32(num_stats) * (stat_height + spacing) - spacing
	stats_total := stats_inner + constants.UI_PANEL_PADDING * 2
	stats_x := graph_panel_x
	stats_y := graph_panel_y + f32(graph_panel_h) + f32(spacing)

	stats_rect := raylib.Rectangle{stats_x, stats_y, f32(stats_panel_w), f32(stats_total)}
	stats_content := render_panel(stats_rect)

	scx := i32(stats_content.x)
	scw := i32(stats_content.width)
	sy := i32(stats_content.y)

	// Helper: draw a stat row
	draw_stat :: proc(label: string, value: string, cx, cw, y: i32, font_size: f32) {
		label_cstr := strings.clone_to_cstring(label, context.temp_allocator)
		value_cstr := strings.clone_to_cstring(value, context.temp_allocator)
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			label_cstr,
			{f32(cx), f32(y)},
			font_size,
			0,
			constants.UI_PANEL_TEXT_COLOR,
		)
		vw := raylib.MeasureTextEx(constants.game_fonts.semibold, value_cstr, font_size, 0).x
		raylib.DrawTextEx(
			constants.game_fonts.semibold,
			value_cstr,
			{f32(cx + cw) - vw, f32(y)},
			font_size,
			0,
			constants.UI_PANEL_TEXT_COLOR,
		)
	}

	// Waves Survived
	draw_stat(
		constants.get_text("GAME_OVER_WAVES_SURVIVED"),
		fmt.tprintf("%d", app.sim.wave_number),
		scx,
		scw,
		sy,
		font_size,
	)
	sy += stat_height + spacing

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

	// Panel dimensions — 13 setting rows
	num_items :: 13
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
	vol_label := fmt.tprintf(
		"%s  %d%%",
		constants.get_text("SETTINGS_VOLUME"),
		i32(app.settings.master_volume * 100),
	)
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(vol_label, context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
	)
	new_master := render_slider(
		{f32(ctrl_x), f32(item_y), f32(btn_width), f32(btn_height)},
		app.settings.master_volume,
	)
	if new_master != app.settings.master_volume {
		app.settings.master_volume = new_master
		raylib.SetMasterVolume(new_master)
		set_volume(.UI,  new_master * app.settings.ui_volume)
		set_volume(.SFX, new_master * app.settings.sfx_volume)
	}

	item_y += item_height + spacing

	// --- UI Volume ---
	ui_vol_label := fmt.tprintf(
		"%s  %d%%",
		constants.get_text("SETTINGS_UI_VOLUME"),
		i32(app.settings.ui_volume * 100),
	)
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(ui_vol_label, context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
	)
	new_ui_vol := render_slider(
		{f32(ctrl_x), f32(item_y), f32(btn_width), f32(btn_height)},
		app.settings.ui_volume,
	)
	if new_ui_vol != app.settings.ui_volume {
		app.settings.ui_volume = new_ui_vol
		set_volume(.UI, app.settings.master_volume * new_ui_vol)
	}

	item_y += item_height + spacing

	// --- SFX Volume ---
	sfx_vol_label := fmt.tprintf(
		"%s  %d%%",
		constants.get_text("SETTINGS_SFX_VOLUME"),
		i32(app.settings.sfx_volume * 100),
	)
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(sfx_vol_label, context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
	)
	new_sfx_vol := render_slider(
		{f32(ctrl_x), f32(item_y), f32(btn_width), f32(btn_height)},
		app.settings.sfx_volume,
	)
	if new_sfx_vol != app.settings.sfx_volume {
		app.settings.sfx_volume = new_sfx_vol
		set_volume(.SFX, app.settings.master_volume * new_sfx_vol)
	}

	item_y += item_height + spacing

	// --- Language ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_LANGUAGE"), context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
	)
	lang_options := []string{
		constants.get_text("SETTINGS_LANGUAGE_ENGLISH"),
		constants.get_text("SETTINGS_LANGUAGE_SPANISH"),
		constants.get_text("SETTINGS_LANGUAGE_PORTUGUESE"),
	}
	lang_index := i32(app.settings.language)
	if render_select("language", "", lang_options, &lang_index, ctrl_x, item_y, btn_width, btn_height, true) {
		app.settings.language = constants.Language(lang_index)
		constants.set_language(app.settings.language)
	}

	item_y += item_height + spacing

	// --- Antialiasing ---
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(constants.get_text("SETTINGS_ANTIALIASING"), context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
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
		strings.clone_to_cstring("Grid Size:", context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
	)
	grid_size_options := []string{"10x10", "15x15", "20x20", "25x25"}
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
		strings.clone_to_cstring(constants.get_text("SETTINGS_FULLSCREEN"), context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
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
		strings.clone_to_cstring(constants.get_text("SETTINGS_VSYNC"), context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
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
		strings.clone_to_cstring(constants.get_text("SETTINGS_SHOW_GRID"), context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
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
		strings.clone_to_cstring(constants.get_text("SETTINGS_SHOW_DAMAGE_NUMBERS"), context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
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
		strings.clone_to_cstring(constants.get_text("SETTINGS_SHOW_TOWER_RANGE"), context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
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
		strings.clone_to_cstring(constants.get_text("SETTINGS_SHOW_FPS"), context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
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
		strings.clone_to_cstring(constants.get_text("SETTINGS_AUTO_WAVE"), context.temp_allocator),
		{f32(cx), f32(item_y + 4)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
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
		entities.app_set_state(app, app.previous_state)
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
			raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(t, context.temp_allocator), font_size, 0).x,
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

	// Always block clicks through the main select button
	append(&ui_click_blocks, raylib.Rectangle{f32(x), f32(y), f32(actual_width), f32(height)})

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
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text, context.temp_allocator), font_size, 0).x,
	)
	text_x := f32(x) + f32(actual_width) / 2 - text_width / 2
	text_y := f32(y) + f32(height) / 2 - font_size / 2
	raylib.DrawTextEx(
		constants.game_fonts.semibold,
		strings.clone_to_cstring(text, context.temp_allocator),
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

		// Block clicks through the open dropdown list
		append(&ui_click_blocks, raylib.Rectangle{f32(x), f32(list_y), f32(actual_width), f32(list_height)})

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
					play_sound(.CLICK, .UI)
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
				raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(item_text, context.temp_allocator), font_size, 0).x,
			)
			item_text_x := f32(x) + f32(actual_width) / 2 - item_text_width / 2
			item_text_y := f32(item_y) + f32(height) / 2 - font_size / 2
			raylib.DrawTextEx(
				constants.game_fonts.semibold,
				strings.clone_to_cstring(item_text, context.temp_allocator),
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
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text, context.temp_allocator), font_size, 0).x
	if int(text_width) + 20 > int(width) {
		actual_width = i32(text_width) + 20
	}

	// Register final button area to block grid clicks behind it
	append(&ui_click_blocks, raylib.Rectangle{f32(x), f32(y), f32(actual_width), f32(actual_height)})

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
			raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(line, context.temp_allocator), font_size, 0).x
		line_x := f32(x) + f32(actual_width) / 2 - line_width / 2
		line_y := start_y + f32(i) * line_spacing
		raylib.DrawTextEx(
			constants.game_fonts.semibold,
			strings.clone_to_cstring(line, context.temp_allocator),
			{line_x, line_y},
			font_size,
			0,
			constants.UI_TEXT_COLOR,
		)
	}

	// Click check
	if hovered && raylib.IsMouseButtonPressed(.LEFT) {
		play_sound(.CLICK, .UI)
		return true
	}

	return false
}

render_slider :: proc(rect: raylib.Rectangle, value: f32) -> f32 {
	v := clamp(value, 0.0, 1.0)

	// Track geometry
	track_height := rect.height * 0.3
	track_y      := rect.y + (rect.height - track_height) / 2
	track_rect   := raylib.Rectangle{rect.x, track_y, rect.width, track_height}

	// Thumb geometry
	thumb_radius := rect.height * 0.45
	thumb_x      := rect.x + v * rect.width
	thumb_x       = clamp(thumb_x, rect.x + thumb_radius, rect.x + rect.width - thumb_radius)
	thumb_y      := rect.y + rect.height / 2

	// Mouse interaction
	mouse_pos := raylib.GetMousePosition()
	hovered   := raylib.CheckCollisionPointRec(mouse_pos, rect)

	new_value := v
	if hovered && raylib.IsMouseButtonDown(.LEFT) {
		raw       := (mouse_pos.x - rect.x) / rect.width
		new_value  = clamp(raw, 0.0, 1.0)
		thumb_x    = clamp(rect.x + new_value * rect.width, rect.x + thumb_radius, rect.x + rect.width - thumb_radius)
	}

	// Track shadow
	raylib.DrawRectangleRounded(
		{
			track_rect.x + f32(constants.UI_BUTTON_SHADOW_OFFSET),
			track_rect.y + f32(constants.UI_BUTTON_SHADOW_OFFSET),
			track_rect.width,
			track_rect.height,
		},
		constants.UI_ROUNDNESS,
		constants.UI_SEGMENTS,
		constants.UI_BUTTON_SHADOW_COLOR,
	)

	// Track background
	raylib.DrawRectangleRounded(track_rect, constants.UI_ROUNDNESS, constants.UI_SEGMENTS, constants.UI_BUTTON_COLOR)

	// Filled portion (left of thumb)
	fill_width := new_value * rect.width
	if fill_width > 0 {
		raylib.DrawRectangleRounded(
			{rect.x, track_y, fill_width, track_height},
			constants.UI_ROUNDNESS,
			constants.UI_SEGMENTS,
			constants.UI_BUTTON_HOVER_COLOR,
		)
	}

	// Thumb shadow
	raylib.DrawCircle(
		i32(thumb_x) + constants.UI_BUTTON_SHADOW_OFFSET,
		i32(thumb_y) + constants.UI_BUTTON_SHADOW_OFFSET,
		thumb_radius,
		constants.UI_BUTTON_SHADOW_COLOR,
	)

	// Thumb
	thumb_color := constants.UI_BUTTON_COLOR
	if hovered {
		if raylib.IsMouseButtonDown(.LEFT) {
			thumb_color = constants.UI_BUTTON_PRESSED_COLOR
		} else {
			thumb_color = constants.UI_BUTTON_HOVER_COLOR
		}
	}
	raylib.DrawCircle(i32(thumb_x), i32(thumb_y), thumb_radius, thumb_color)

	return new_value
}

render_button :: proc(
	text: string,
	rect: raylib.Rectangle,
	text_lines: i32 = 1,
	enabled: bool = true,
	text_color: raylib.Color = constants.COLOR_NONE,
	button_color: raylib.Color = constants.COLOR_NONE,
	button_hover_color: raylib.Color = constants.COLOR_NONE,
	button_pressed_color: raylib.Color = constants.COLOR_NONE,
) -> bool {
	// Resolve text color: explicit > white-when-colored > default UI text
	resolved_text_color := text_color
	if resolved_text_color.a == 0 {
		if button_color.a != 0 {
			resolved_text_color = raylib.WHITE
		} else {
			resolved_text_color = constants.UI_TEXT_COLOR
		}
	}

	font_size := f32(constants.UI_BUTTON_FONT_SIZE)
	text_width := f32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(text, context.temp_allocator), font_size, 0).x,
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

	// Register button area to block grid clicks behind it
	append(&ui_click_blocks, raylib.Rectangle{f32(x), f32(y), f32(actual_width), f32(height)})

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
			raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(line, context.temp_allocator), font_size, 0).x
		line_x := f32(x) + f32(actual_width) / 2 - line_width / 2
		line_y := start_y + f32(i) * line_spacing
		raylib.DrawTextEx(
			constants.game_fonts.semibold,
			strings.clone_to_cstring(line, context.temp_allocator),
			{line_x, line_y},
			font_size,
			0,
			resolved_text_color,
		)
	}

	// Click check
	if hovered && raylib.IsMouseButtonPressed(.LEFT) {
		play_sound(.CLICK, .UI)
		return true
	}

	return false
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
	case .ICE:
		fill = constants.TOWER_ICE_BASE
		stroke = constants.TOWER_ICE_STROKE
	case .ENHANCE:
		fill = constants.TOWER_ENHANCE_BASE
		stroke = constants.TOWER_ENHANCE_STROKE
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

	case .ICE:
		// Snowflake: 6 lines radiating from center at 30° intervals, no rotation needed
		snow_r := cs * 0.32
		num_arms :: 6
		for i in 0 ..< num_arms {
			a := f32(i) * math.PI / f32(num_arms / 2)
			ex := cx + math.cos(a) * snow_r
			ey := cy + math.sin(a) * snow_r
			// Shadow
			raylib.DrawLineEx(
				{cx + so, cy + so},
				{ex + so, ey + so},
				max(1.5, cs * 0.05),
				constants.TOWER_SHADOW,
			)
			// Arm
			raylib.DrawLineEx(
				{cx, cy},
				{ex, ey},
				max(1.5, cs * 0.05),
				constants.TOWER_ICE_STROKE,
			)
		}
		// Center crystal
		raylib.DrawCircle(i32(cx + so), i32(cy + so), r * 0.55, constants.TOWER_SHADOW)
		raylib.DrawCircle(i32(cx), i32(cy), r * 0.55, raylib.Color{220, 245, 255, 255})
		raylib.DrawCircle(i32(cx), i32(cy), r * 0.28, constants.TOWER_ICE_STROKE)

	case .ENHANCE:
		// Star: 8 radiating arms alternating long/short
		num_arms :: 8
		for i in 0 ..< num_arms {
			a := f32(i) * math.PI * 2 / f32(num_arms)
			arm_r := cs * 0.30 if i % 2 == 0 else cs * 0.17
			ex := cx + math.cos(a) * arm_r
			ey := cy + math.sin(a) * arm_r
			// Shadow
			raylib.DrawLineEx(
				{cx + so, cy + so},
				{ex + so, ey + so},
				max(2.0, cs * 0.07),
				constants.TOWER_SHADOW,
			)
			// Arm
			raylib.DrawLineEx(
				{cx, cy},
				{ex, ey},
				max(2.0, cs * 0.07),
				constants.TOWER_ENHANCE_STROKE,
			)
		}
		// Glow ring
		raylib.DrawCircle(i32(cx + so), i32(cy + so), r * 0.60, constants.TOWER_SHADOW)
		raylib.DrawCircle(i32(cx), i32(cy), r * 0.60, constants.TOWER_ENHANCE_GLOW)
		// Core
		raylib.DrawCircle(i32(cx), i32(cy), r * 0.35, constants.TOWER_ENHANCE_BASE)
		raylib.DrawCircle(i32(cx), i32(cy), r * 0.18, constants.TOWER_ENHANCE_STROKE)
	}
}

// Render tower for simulation (calls unified function with rotation)
render_tower :: proc(app: ^entities.App_State, tower: ^entities.Tower, x, y, cs: f32) {
	// Draw tower
	draw_tower_tile(x, y, cs, tower.type, tower.angle, false)
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

// UI click-blocking registry.
// Every rendered panel and button appends its screen rectangle here.
// input_handle_playing reads this to ignore grid clicks that land on UI.
// Cleared at the start of each frame in render_game.
ui_click_blocks: [dynamic]raylib.Rectangle

ui_blocks_clear :: proc() {
	clear(&ui_click_blocks)
}

// Returns true if screen position (x, y) falls inside any registered UI rect.
ui_is_click_blocked :: proc(x, y: i32) -> bool {
	p := raylib.Vector2{f32(x), f32(y)}
	for rect in ui_click_blocks {
		if raylib.CheckCollisionPointRec(p, rect) {
			return true
		}
	}
	return false
}

// Game session stats (tracked across play session)
game_session_start_time: f64 = 0
game_session_end_time: f64 = 0
game_session_total_kills: i32 = 0

// Render panel with rounded corners and optional title
// Returns a rectangle representing the available content area
render_panel :: proc(rect: raylib.Rectangle, title: string = "") -> raylib.Rectangle {
	// Register panel area so input system ignores grid clicks behind it
	append(&ui_click_blocks, rect)

	x := i32(rect.x)
	y := i32(rect.y)
	width := i32(rect.width)
	height := i32(rect.height)

	// Drop shadow
	raylib.DrawRectangleRounded(
		{
			rect.x + constants.UI_SHADOW_OFFSET,
			rect.y + constants.UI_SHADOW_OFFSET,
			rect.width,
			rect.height
		},
		constants.UI_ROUNDNESS,
		constants.UI_SEGMENTS,
		constants.UI_SHADOW_COLOR,
	)

	// Draw full panel background uniformly
	raylib.DrawRectangleRounded(
		rect,
		constants.UI_ROUNDNESS,
		constants.UI_SEGMENTS,
		constants.UI_PANEL_COLOR
	)

	margin_x := i32(constants.UI_PANEL_PADDING)
	margin_y := i32(constants.UI_PANEL_PADDING)

	// Draw title inside panel margins if provided
	title_height: i32 = 0
	if title != "" {
		title_height = 30 // Space for title line
		title_cstr := strings.clone_to_cstring(title, context.temp_allocator)
		raylib.DrawTextEx(
			constants.game_fonts.bold,
			title_cstr,
			{f32(x + margin_x), f32(y + margin_y)},
			constants.UI_PANEL_TITLE_SIZE,
			0,
			constants.UI_PANEL_TITLE_COLOR,
		)
	}

	// Calculate content area (below title with margin)
	content_x      := x + margin_x
	content_y      := y + margin_y + title_height
	content_width  := width  - margin_x * 2
	content_height := height - margin_y * 2 - title_height

	return raylib.Rectangle {
		x = f32(content_x),
		y = f32(content_y),
		width = f32(content_width),
		height = f32(content_height),
	}
}

// Render info panel: icon + large bold value filling the panel, tooltip on hover.
// Delegates shadow + background + click-blocking to render_panel (called with no title).
// Returns the content rectangle so callers can draw additional content.
render_info_panel :: proc(rect: raylib.Rectangle, tooltip: string, value: string = "", icon: raylib.Texture2D = {}) -> raylib.Rectangle {
	// render_panel handles: drop shadow, rounded background, ui_click_blocks registration.
	_ = render_panel(rect)

	margin    : f32 = constants.UI_PANEL_PADDING
	content_x := rect.x + margin
	content_y := rect.y + margin
	content_w := rect.width  - margin * 2
	content_h := rect.height - margin * 2

	// Large bold value + optional icon, left-aligned and vertically centered
	if value != "" {
		value_font_size : f32 = constants.UI_PANEL_HEADER_SIZE
		value_cstr  := strings.clone_to_cstring(value, context.temp_allocator)
		value_size  := raylib.MeasureTextEx(constants.game_fonts.bold, value_cstr, value_font_size, 0)

		icon_gap : f32 = 6
		icon_w   : f32 = 0
		icon_h   : f32 = value_size.y * 0.75  // slightly smaller than the text

		if icon.id != 0 && icon.height > 0 {
			aspect := f32(icon.width) / f32(icon.height)
			icon_w  = icon_h * aspect
		}

		center_y := content_y + (content_h - icon_h) / 2

		if icon.id != 0 && icon_w > 0 {
			raylib.DrawTexturePro(
				icon,
				{0, 0, f32(icon.width), f32(icon.height)},
				{content_x, center_y, icon_w, icon_h},
				{0, 0}, 0,
				raylib.WHITE,
			)
		}

		value_x := content_x + icon_w + (icon_gap if icon_w > 0 else 0)
		value_y := content_y + (content_h - value_size.y) / 2
		raylib.DrawTextEx(
			constants.game_fonts.bold,
			value_cstr,
			{value_x, value_y},
			value_font_size, 0,
			constants.UI_TEXT_COLOR,
		)
	}

	// Tooltip on hover
	if tooltip != "" {
		render_label_tooltip(tooltip, rect)
	}

	return raylib.Rectangle{content_x, content_y, content_w, content_h}
}

// Render tower control panel
render_tower_control_panel :: proc(app: ^entities.App_State) {
	// Only show if a tower is selected
	tower := entities.app_get_selected_tower(app)
	if tower == nil {
		tower_panel_active = false
		return
	}

	// Layout constants — height computed from actual content
	button_height  : i32 = 30
	strategy_height: i32 = 30
	spacing        : i32 = constants.UI_PANEL_MARGIN / 2
	font_size      : f32 = constants.UI_PANEL_TEXT_SIZE
	info_height    : i32 = i32(constants.UI_PANEL_LABEL_SIZE) + 4  // coincide con current_y += UI_PANEL_LABEL_SIZE + 4
	line_height    : i32 = i32(font_size) + 10         // más espacio entre líneas de stats
	stats_height   : i32 = 3 * line_height             // 3 líneas: daño, velocidad, críticos
	is_enhance    := tower.type == .ENHANCE
	show_stats    := !is_enhance
	show_strategy := !is_enhance

	// Alto del contenido = suma exacta de lo que se renderiza + gaps entre secciones
	// Orden: info → [stats+gap] → upgrade+gap → [strategy+gap] → sell
	content_height := info_height + button_height + spacing  // upgrade + gap
	if show_stats    { content_height += stats_height    + spacing }
	if show_strategy { content_height += strategy_height + spacing }
	content_height += button_height  // sell (último, sin gap)

	// render_panel consume: margin_y + title(30) + margin_y = UI_PANEL_PADDING*2 + 30
	PANEL_OVERHEAD :: i32(constants.UI_PANEL_PADDING * 2 + 30)
	panel_height   := content_height + PANEL_OVERHEAD

	// Panel dimensions and position
	panel_rect := raylib.Rectangle {
		x      = f32(raylib.GetScreenWidth() - constants.UI_PANEL_WIDTH - constants.UI_MARGIN_X),
		y      = f32(constants.UI_PANEL_Y_POSITION),
		width  = f32(constants.UI_PANEL_WIDTH),
		height = f32(panel_height),
	}

	// Tower info
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
	case .ICE:
		type_name = constants.get_text("TOWER_ICE_NAME")
	case .ENHANCE:
		type_name = constants.get_text("TOWER_ENHANCE_NAME")
	}

	// Level subtitle — separate from type_name so the title doesn't overflow at size 22
	level_text: string
	if tower.enhance_bonus > 0 {
		base_level := tower.level - tower.enhance_bonus
		level_text = fmt.tprintf("%s %d + %d", constants.get_text("PANEL_LEVEL_ABBREV"), base_level, tower.enhance_bonus)
	} else {
		level_text = fmt.tprintf("%s %d", constants.get_text("PANEL_LEVEL_ABBREV"), tower.level)
	}

	// Render panel background and get content area (title = type name only)
	content_area  := render_panel(panel_rect, type_name)
	content_x     := i32(content_area.x)
	content_y     := i32(content_area.y)
	content_width := i32(content_area.width)
	button_width  := content_width

	current_y := content_y

	// Level line (below type name, above stats)
	raylib.DrawTextEx(
		constants.game_fonts.semibold,
		strings.clone_to_cstring(level_text, context.temp_allocator),
		{f32(content_x), f32(current_y)},
		f32(constants.UI_PANEL_LABEL_SIZE),
		0,
		constants.UI_PANEL_LABEL_COLOR,
	)
	current_y += i32(constants.UI_PANEL_LABEL_SIZE) + 4

	// Stats — no se muestran para el Potenciador
	if show_stats {
		icon_size := f32(line_height - 2)

		ICON_SLOT  :: f32(20)  // ancho fijo reservado para el ícono (todos los iconos caben aquí)
		ICON_GAP   :: f32(6)   // margen fijo entre la columna del ícono y el texto

		draw_icon_stat :: proc(icon: raylib.Texture2D, value: string, x, y: i32, icon_sz, font_sz: f32) {
			// Ícono centrado dentro del slot fijo
			aspect := f32(icon.width) / f32(icon.height) if icon.height > 0 else 1
			draw_w := icon_sz * aspect
			icon_x := f32(x) + (ICON_SLOT - draw_w) / 2  // centrado horizontalmente en el slot
			raylib.DrawTexturePro(
				icon,
				{0, 0, f32(icon.width), f32(icon.height)},
				{icon_x, f32(y), draw_w, icon_sz},
				{0, 0},
				0,
				raylib.WHITE,
			)
			// Texto siempre a ICON_SLOT + ICON_GAP del origen — gap constante en los tres stats
			val_cstr := strings.clone_to_cstring(value, context.temp_allocator)
			raylib.DrawTextEx(
				constants.game_fonts.semibold,
				val_cstr,
				{f32(x) + ICON_SLOT + ICON_GAP, f32(y) + (icon_sz - font_sz) / 2},
				font_sz,
				0,
				constants.UI_PANEL_TEXT_COLOR,
			)
		}

		crit_pct := entities.tower_get_critical_chance(tower) * 100
		draw_icon_stat(constants.game_icons.damage, fmt.tprintf("%.1f",  tower.damage),   content_x, current_y + 0 * line_height, icon_size, font_size)
		draw_icon_stat(constants.game_icons.speed,  fmt.tprintf("%.2fs", tower.cooldown), content_x, current_y + 1 * line_height, icon_size, font_size)
		draw_icon_stat(constants.game_icons.crit,   fmt.tprintf("%.0f%%", crit_pct),      content_x, current_y + 2 * line_height, icon_size, font_size)
		current_y += stats_height + spacing
	}

	// Upgrade button — ENHANCE se limita a nivel 5; resto se limita a nivel 20
	base_level      := tower.level - tower.enhance_bonus
	manual_cap      := constants.TOWER_MAX_MANUAL_LEVEL if tower.type != .ENHANCE else constants.ENHANCE_MAX_LEVEL
	at_max_manual   := base_level >= manual_cap
	at_max_absolute := tower.level >= constants.TOWER_MAX_LEVEL
	at_max          := at_max_manual || at_max_absolute
	upgrade_cost      := entities.tower_get_upgrade_cost(tower)
	upgrade_text      := at_max \
		? constants.get_text("PANEL_BUTTON_MAX_LEVEL") \
		: constants.get_text_f("PANEL_BUTTON_UPGRADE", upgrade_cost)
	can_afford_upgrade := !at_max && app.sim.money >= upgrade_cost

	if render_button(
		   upgrade_text,
		   {f32(content_x), f32(current_y), f32(button_width), f32(button_height)},
		   enabled = !at_max,
	   ) &&
	   can_afford_upgrade {
		entities.tower_upgrade(tower)
		app.sim.money -= upgrade_cost
		app.sim.upgrades_bought += 1
		play_sound(.CONFIRMATION, .UI)
	}
	current_y += button_height + spacing

	// Strategy section — no aplica para el Potenciador (no tiene objetivo)
	if show_strategy {
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
	}

	// Delete/Sell button at the bottom
	refund := entities.tower_get_sell_refund(tower)
	delete_text := constants.get_text_f("PANEL_BUTTON_SELL", refund)

	if render_button(
		delete_text,
		{f32(content_x), f32(current_y), f32(button_width), f32(button_height)},
		1,
		true,
		constants.UI_TEXT_COLOR,
		constants.UI_BUTTON_SELL_COLOR,
		constants.UI_BUTTON_SELL_HOVER,
		constants.UI_BUTTON_SELL_PRESS,
	) {
		simulation_remove_tower_at(app, tower.r, tower.c)
		play_sound(.CONFIRMATION, .UI)
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

	// Layout constants — compact panel sized to content
	button_height: i32 = 30
	spacing      : i32 = 8
	font_size    : f32 = 14
	info_height  : i32 = 22
	line_height  : i32 = i32(font_size) + 5
	stat_height  : i32 = line_height
	// elements: info, stat, upgrade btn, sell btn; gaps between them: 3
	inner_height := info_height + stat_height + 2 * button_height + 3 * spacing
	panel_height := inner_height + 20 // 10px top + 10px bottom padding

	// Panel dimensions and position
	panel_rect := raylib.Rectangle {
		x      = f32(raylib.GetScreenWidth() - constants.UI_PANEL_WIDTH - constants.UI_MARGIN_X),
		y      = f32(constants.UI_PANEL_Y_POSITION),
		width  = f32(constants.UI_PANEL_WIDTH),
		height = f32(panel_height),
	}

	// Render panel background and get content area
	content_area  := render_panel(panel_rect, "")
	content_x     := i32(content_area.x)
	content_y     := i32(content_area.y)
	content_width := i32(content_area.width)
	button_width  := content_width
	current_y     := content_y

	// Obstacle info
	info_text := constants.get_text_f("PANEL_OBSTACLE_INFO", level)
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		strings.clone_to_cstring(info_text, context.temp_allocator),
		{f32(content_x), f32(current_y)},
		20,
		0,
		constants.UI_PANEL_TEXT_COLOR,
	)
	current_y += info_height + spacing

	// Stat: Daño exponencial — base × 2^(level-1), igual que enemy_apply_obstacle_damage
	damage_stat := i32(constants.OBSTACLE_DAMAGE_PER_LEVEL * f32(i32(1) << uint(level - 1)))
	raylib.DrawTextEx(
		constants.game_fonts.semibold,
		fmt.ctprintf("Daño: %d", damage_stat),
		{f32(content_x), f32(current_y)},
		font_size,
		0,
		constants.UI_PANEL_TEXT_COLOR,
	)
	current_y += stat_height + spacing

	// Upgrade Level button
	level_cost := constants.OBSTACLE_UPGRADE_COST_BASE * i32(i32(1) << uint(level - 1))
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
		play_sound(.CONFIRMATION, .UI)
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
		constants.UI_BUTTON_SELL_COLOR,
		constants.UI_BUTTON_SELL_HOVER,
		constants.UI_BUTTON_SELL_PRESS,
	) {
		app.editor.game_map.obstacle_grid[row][col] = .EMPTY
		// Clear level data so a new obstacle placed here starts at level 1
		if existing_key, ok := entities.map_get_existing_key(&app.editor.game_map, row, col); ok {
			delete_key(&app.editor.game_map.tile_data, existing_key)
			delete(existing_key)
		}
		app.sim.money += sell_cost
		app.selected_obstacle.valid = false
		play_sound(.CONFIRMATION, .UI)
	}
}

// ─── Deck builder UI ──────────────────────────────────────────────────────────

// Dimensiones de una carta en la mano
CARD_W  :: f32(110)
CARD_H  :: f32(155)
CARD_GAP :: f32(10)
CARD_BOTTOM_MARGIN :: f32(16)

// Color de fondo de carta según tipo
// Renderiza una sola carta en la posición dada
render_card :: proc(
	app: ^entities.App_State,
	card: entities.Card,
	x, y: f32,
	is_selected: bool,
	can_afford: bool,
) {
	bg := constants.UI_PANEL_COLOR
	if !can_afford {
		bg = raylib.Color{20, 20, 20, 220}
	}

	// Sombra de la carta
	card_shadow_rect := raylib.Rectangle{
		x + constants.UI_SHADOW_OFFSET,
		y + constants.UI_SHADOW_OFFSET,
		CARD_W, CARD_H
	}
	raylib.DrawRectangleRounded(card_shadow_rect, constants.UI_ROUNDNESS, constants.UI_SEGMENTS, constants.UI_SHADOW_COLOR)

	// Fondo de la carta
	card_rect := raylib.Rectangle{x, y, CARD_W, CARD_H}
	raylib.DrawRectangleRounded(card_rect, constants.UI_ROUNDNESS, constants.UI_SEGMENTS, bg)

	// Preview — ocupa el tercio superior
	preview_size : f32 = 58
	preview_x := x + (CARD_W - preview_size) / 2
	preview_y := y + 12
	icon_cx   := x + CARD_W / 2
	icon_cy   := preview_y + preview_size / 2
	switch card.kind {
	case .OBSTACLE:
		draw_obstacle_preview(preview_x, preview_y, preview_size)
	case .TOWER:
		dummy := entities.tower_init(card.tower_type, 0, 0)
		old_show_range := app.settings.show_tower_range
		app.settings.show_tower_range = false
		render_tower(app, &dummy, preview_x, preview_y, preview_size)
		app.settings.show_tower_range = old_show_range
	case .INTEREST_BOOST:
		raylib.DrawCircle(i32(icon_cx), i32(icon_cy), 20, raylib.Color{200, 160, 20, 255})
		raylib.DrawCircle(i32(icon_cx), i32(icon_cy), 16, raylib.Color{240, 200, 40, 255})
		lbl   := cstring("x2")
		lbl_w := raylib.MeasureTextEx(constants.game_fonts.semibold, lbl, 16, 0).x
		raylib.DrawTextEx(constants.game_fonts.semibold, lbl, {icon_cx - lbl_w / 2, icon_cy - 9}, 16, 0, raylib.Color{80, 40, 0, 255})
	case .EXTRA_DRAW:
		raylib.DrawRectangleRounded({icon_cx - 14, icon_cy - 16, 26, 18}, 0.2, 4, raylib.Color{80, 140, 220, 255})
		raylib.DrawRectangleRounded({icon_cx - 12, icon_cy - 4,  26, 18}, 0.2, 4, raylib.Color{110, 170, 255, 255})
		raylib.DrawRectangleRoundedLinesEx({icon_cx - 12, icon_cy - 4, 26, 18}, 0.2, 4, 1.5, raylib.Color{180, 210, 255, 255})
		lbl2   := cstring("?")
		lbl2_w := raylib.MeasureTextEx(constants.game_fonts.semibold, lbl2, 14, 0).x
		raylib.DrawTextEx(constants.game_fonts.semibold, lbl2, {icon_cx - lbl2_w / 2 + 1, icon_cy - 3}, 14, 0, raylib.WHITE)
	case .WEAKEN:
		raylib.DrawCircle(i32(icon_cx), i32(icon_cy) - 8, 14, raylib.Color{200, 60, 60, 255})
		raylib.DrawCircle(i32(icon_cx), i32(icon_cy) - 8, 10, raylib.Color{240, 100, 80, 255})
		skull  := cstring("↓")
		sk_w   := raylib.MeasureTextEx(constants.game_fonts.semibold, skull, 18, 0).x
		raylib.DrawTextEx(constants.game_fonts.semibold, skull, {icon_cx - sk_w / 2, icon_cy - 20}, 18, 0, raylib.WHITE)
		pct    := cstring("30%")
		pct_w  := raylib.MeasureTextEx(constants.game_fonts.regular, pct, 11, 0).x
		raylib.DrawTextEx(constants.game_fonts.regular, pct, {icon_cx - pct_w / 2, icon_cy + 8}, 11, 0, raylib.Color{255, 160, 160, 255})
	case .DIVIDEND:
		raylib.DrawCircle(i32(icon_cx), i32(icon_cy) - 6, 15, raylib.Color{60, 180, 100, 255})
		raylib.DrawCircle(i32(icon_cx), i32(icon_cy) - 6, 11, raylib.Color{80, 220, 120, 255})
		dlbl   := cstring("$")
		dlbl_w := raylib.MeasureTextEx(constants.game_fonts.semibold, dlbl, 16, 0).x
		raylib.DrawTextEx(constants.game_fonts.semibold, dlbl, {icon_cx - dlbl_w / 2, icon_cy - 16}, 16, 0, raylib.Color{10, 60, 20, 255})
		pct2   := cstring("15%")
		pct2_w := raylib.MeasureTextEx(constants.game_fonts.regular, pct2, 11, 0).x
		raylib.DrawTextEx(constants.game_fonts.regular, pct2, {icon_cx - pct2_w / 2, icon_cy + 10}, 11, 0, raylib.Color{160, 255, 180, 255})
	}

	// Nombre de la carta
	name := entities.card_name(card)
	name_size : f32 = 12
	name_w := raylib.MeasureTextEx(constants.game_fonts.regular, strings.clone_to_cstring(name, context.temp_allocator), name_size, 0).x
	name_color := constants.UI_PANEL_TEXT_COLOR
	if !can_afford { name_color = raylib.Color{100, 100, 100, 255} }
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(name, context.temp_allocator),
		{x + (CARD_W - name_w) / 2, y + 78},
		name_size, 0, name_color,
	)

	// Separador
	raylib.DrawLineEx({x + 10, y + 96}, {x + CARD_W - 10, y + 96}, 1, raylib.Color{100, 100, 120, 120})

	// Costo
	cost_str  := fmt.ctprintf("$%d", entities.card_cost(card))
	cost_size : f32 = 15
	cost_w := raylib.MeasureTextEx(constants.game_fonts.semibold, cost_str, cost_size, 0).x
	cost_color := can_afford ? raylib.Color{80, 220, 100, 255} : raylib.Color{200, 60, 60, 255}
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		cost_str,
		{x + (CARD_W - cost_w) / 2, y + 102},
		cost_size, 0, cost_color,
	)
}

// Renderiza la mano de cartas en la parte inferior de la pantalla
render_card_hand :: proc(app: ^entities.App_State) {
	if len(app.sim.hand) == 0 {
		return
	}

	screen_w := f32(raylib.GetScreenWidth())
	screen_h := f32(raylib.GetScreenHeight())

	n      := f32(len(app.sim.hand))
	total_w := n * CARD_W + (n - 1) * CARD_GAP
	start_x := (screen_w - total_w) / 2
	card_y  := screen_h - CARD_H - CARD_BOTTOM_MARGIN

	// Panel de fondo semitransparente detrás de las cartas
	panel_pad : f32 = 8
	panel_rect := raylib.Rectangle{
		start_x - panel_pad,
		card_y - panel_pad,
		total_w + panel_pad * 2,
		CARD_H + panel_pad * 2,
	}

	// Botón de re-reparto — gratis antes de iniciar, cuesta HAND_REDEAL_COST después
	{
		game_started := app.sim.started
		can_redeal   := !game_started || app.sim.money >= constants.HAND_REDEAL_COST
		btn_label    := game_started \
			? fmt.tprintf("%s ($%d)", constants.get_text("DECK_REDEAL_BUTTON"), constants.HAND_REDEAL_COST) \
			: constants.get_text("DECK_REDEAL_BUTTON")
		btn_w  : f32 = 150
		btn_h  : f32 = 28
		btn_x  := (screen_w - btn_w) / 2
		btn_y  := card_y - panel_pad - btn_h - 6
		btn_rect := raylib.Rectangle{btn_x, btn_y, btn_w, btn_h}
		if render_button(btn_label, btn_rect, enabled = can_redeal) {
			if game_started {
				app.sim.money -= constants.HAND_REDEAL_COST
			}
			entities.hand_redeal(&app.sim)
			app.sim.selected_build_tower = .EMPTY
			app.sim.selected_card_idx    = -1
			play_sound(.SELECT, .UI)
		}
	}

	sold_this_frame := false
	for i := 0; i < len(app.sim.hand); i += 1 {
		card       := app.sim.hand[i]
		cx         := start_x + f32(i) * (CARD_W + CARD_GAP)
		can_afford := app.sim.money >= entities.card_cost(card)
		is_selected := app.sim.selected_card_idx == i

		// Hover: detectar si el mouse está sobre la carta o el botón de venta debajo
		SELL_BTN_H :: f32(22)
		HOVER_LIFT  :: f32(28) // levantada extra para dejar espacio al botón debajo
		mouse_x := f32(raylib.GetMouseX())
		mouse_y := f32(raylib.GetMouseY())
		// Zona de hover incluye la carta levantada + el espacio del botón debajo
		is_hovered := mouse_x >= cx && mouse_x <= cx + CARD_W &&
		              mouse_y >= card_y - HOVER_LIFT && mouse_y <= card_y + CARD_H
		draw_y := card_y
		if is_hovered && !is_selected {
			draw_y -= HOVER_LIFT
		}
		if is_selected {
			draw_y -= HOVER_LIFT
		}

		render_card(app, card, cx, draw_y, is_selected, can_afford)

		// Botón de venta — aparece debajo de la carta solo al hacer hover
		if is_hovered {
			sell_btn_rect := raylib.Rectangle{cx, draw_y + CARD_H + 2, CARD_W, SELL_BTN_H}
			sell_label := fmt.tprintf("%s $%d", constants.get_text("CARD_SELL_BUTTON"), constants.CARD_SELL_PRICE)
			if render_button(
				sell_label,
				sell_btn_rect,
				button_color         = constants.UI_BUTTON_SELL_COLOR,
				button_hover_color   = constants.UI_BUTTON_SELL_HOVER,
				button_pressed_color = constants.UI_BUTTON_SELL_PRESS,
			) && !sold_this_frame {
				if app.sim.selected_card_idx == i {
					app.sim.selected_build_tower = .EMPTY
					app.sim.selected_card_idx    = -1
				}
				entities.card_sell(&app.sim, i)
				entities.app_add_money(app, constants.CARD_SELL_PRICE)
				sold_this_frame = true
				i -= 1
				continue
			}
		}

		// Click en la carta completa
		card_rect := raylib.Rectangle{cx, draw_y, CARD_W, CARD_H}
		append(&ui_click_blocks, card_rect)
		if raylib.IsMouseButtonPressed(.LEFT) && is_hovered && can_afford {
			if card.kind == .INTEREST_BOOST {
				app.sim.interest_multiplier *= 2
				entities.card_play(&app.sim, i)
				play_sound(.CONFIRMATION, .UI)
			} else if card.kind == .EXTRA_DRAW {
				draw_random_card(&app.sim)
				entities.card_play(&app.sim, i)
				play_sound(.CONFIRMATION, .UI)
			} else if card.kind == .WEAKEN {
				app.sim.next_wave_weakened = true
				entities.card_play(&app.sim, i)
				play_sound(.CONFIRMATION, .UI)
			} else if card.kind == .DIVIDEND {
				app.sim.dividend_stacks += 1
				entities.card_play(&app.sim, i)
				play_sound(.CONFIRMATION, .UI)
			} else if is_selected {
				// Deseleccionar
				app.sim.selected_build_tower = .EMPTY
				app.sim.selected_card_idx    = -1
			} else {
				// Seleccionar esta carta
				app.sim.selected_card_idx    = i
				app.sim.selected_build_tower = entities.card_to_tile(card)
			}
		}

	}
}

// Overlay de selección de carta (cada DECK_SELECTION_INTERVAL oleadas)
render_card_selection_overlay :: proc(app: ^entities.App_State) {
	screen_w := f32(raylib.GetScreenWidth())
	screen_h := f32(raylib.GetScreenHeight())

	// Fondo oscuro
	raylib.DrawRectangle(0, 0, i32(screen_w), i32(screen_h), raylib.Color{0, 0, 0, 170})

	// Las 3 cartas centradas en pantalla
	CARD_GAP_OVERLAY :: f32(16)
	cards_total_w := f32(3) * CARD_W + f32(2) * CARD_GAP_OVERLAY

	// Título y subtítulo centrados sobre las cartas
	title      := strings.clone_to_cstring(constants.get_text("DECK_CHOOSE_CARD"), context.temp_allocator)
	title_size : f32 = 20
	title_w    := raylib.MeasureTextEx(constants.game_fonts.semibold, title, title_size, 0).x
	title_x    := (screen_w - title_w) / 2
	title_y    := screen_h / 2 - CARD_H / 2 - 52
	raylib.DrawTextEx(constants.game_fonts.semibold, title, {title_x, title_y}, title_size, 0, raylib.WHITE)

	cx := (screen_w - cards_total_w) / 2
	cy := screen_h / 2 - CARD_H / 2

	for i in 0 ..< 3 {
		choice := app.sim.card_selection_choices[i]
		card_x := cx + f32(i) * (CARD_W + CARD_GAP_OVERLAY)

		can_afford := app.sim.money >= entities.card_cost(choice)
		render_card(app, choice, card_x, cy, false, can_afford)

		// Hover highlight + click
		mouse_x := f32(raylib.GetMouseX())
		mouse_y := f32(raylib.GetMouseY())
		card_rect := raylib.Rectangle{card_x, cy, CARD_W, CARD_H}
		is_hovered := mouse_x >= card_rect.x && mouse_x <= card_rect.x + card_rect.width &&
		              mouse_y >= card_rect.y && mouse_y <= card_rect.y + card_rect.height
		if is_hovered {
			raylib.DrawRectangleRoundedLinesEx(card_rect, constants.UI_ROUNDNESS, constants.UI_SEGMENTS, 3, raylib.Color{60, 220, 80, 255})
		}
		append(&ui_click_blocks, card_rect)

		if raylib.IsMouseButtonPressed(.LEFT) && is_hovered {
			entities.card_add_to_hand(&app.sim, choice)
			entities.add_toast(
				app,
				fmt.tprintf("%s %s", constants.get_text("DECK_CARD_ADDED"), entities.card_name(choice)),
				.SUCCESS,
				3.0,
			)
			app.sim.card_selection_active = false
			simulation_set_pause(app, false)
		}
	}

	// Botón de reroll — disponible desde la oleada CARD_REROLL_MIN_WAVE
	if app.sim.wave_number >= constants.CARD_REROLL_MIN_WAVE {
		can_reroll := app.sim.money >= constants.CARD_REROLL_COST
		reroll_label := fmt.tprintf("%s ($%d)", constants.get_text("DECK_REROLL_BUTTON"), constants.CARD_REROLL_COST)
		btn_rect := raylib.Rectangle{
			(screen_w - 160) / 2,
			cy + CARD_H + 20,
			160, 30,
		}
		col     := raylib.Color{80, 100, 180, 220} if can_reroll else raylib.Color{60, 60, 60, 180}
		hov_col := raylib.Color{100, 130, 220, 255} if can_reroll else raylib.Color{60, 60, 60, 180}
		if render_button(reroll_label, btn_rect, button_color = col, button_hover_color = hov_col) && can_reroll {
			app.sim.money -= constants.CARD_REROLL_COST
			generate_card_selection(&app.sim)
			play_sound(.SELECT, .UI)
		}
	}
}
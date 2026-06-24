package systems

import "../constants"
import "../entities"
import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

// ── Nebula background shader ──────────────────────────────────────────────────

Nebula_Shader :: struct {
	shader:   raylib.Shader,
	loc_time: i32,
	loc_res:  i32,
}

nebula_shader: Nebula_Shader

nebula_init :: proc() {
	s := raylib.LoadShader(nil, "assets/nebula.glsl")
	nebula_shader = Nebula_Shader{
		shader   = s,
		loc_time = raylib.GetShaderLocation(s, "u_time"),
		loc_res  = raylib.GetShaderLocation(s, "u_resolution"),
	}
}

nebula_unload :: proc() {
	raylib.UnloadShader(nebula_shader.shader)
}

nebula_draw :: proc() {
	// Shader id == 1 means Raylib returned the default shader (load failed).
	// In that case skip to avoid corrupting rendering state.
	if nebula_shader.shader.id <= 1 { return }

	w := f32(raylib.GetRenderWidth())
	h := f32(raylib.GetRenderHeight())

	t   := f32(raylib.GetTime())
	res := [2]f32{w, h}

	if nebula_shader.loc_time >= 0 {
		raylib.SetShaderValue(nebula_shader.shader, nebula_shader.loc_time, &t, .FLOAT)
	}
	if nebula_shader.loc_res >= 0 {
		raylib.SetShaderValue(nebula_shader.shader, nebula_shader.loc_res, &res, .VEC2)
	}

	raylib.BeginShaderMode(nebula_shader.shader)
	raylib.DrawRectangle(0, 0, i32(w), i32(h), raylib.WHITE)
	raylib.EndShaderMode()
}

// ── Water blob shader ────────────────────────────────────────────────────────

Water_Shader :: struct {
	shader:      raylib.Shader,
	loc_texel:   i32,
	loc_water:   i32,
	loc_edge:    i32,
	loc_time:    i32,
	loc_cam:     i32,
	loc_zoom:    i32,
	mask_tex:    raylib.RenderTexture2D,
	tex_w:       i32,
	tex_h:       i32,
}

water_shader: Water_Shader

water_shader_init :: proc() {
	s := raylib.LoadShader(nil, "assets/water.glsl")
	water_shader.shader    = s
	water_shader.loc_texel = raylib.GetShaderLocation(s, "texelSize")
	water_shader.loc_water = raylib.GetShaderLocation(s, "waterColor")
	water_shader.loc_edge  = raylib.GetShaderLocation(s, "edgeColor")
	water_shader.loc_time  = raylib.GetShaderLocation(s, "u_time")
	water_shader.loc_cam   = raylib.GetShaderLocation(s, "u_camera_offset")
	water_shader.loc_zoom  = raylib.GetShaderLocation(s, "u_zoom")
	water_shader_resize()
}

water_shader_resize :: proc() {
	w := raylib.GetRenderWidth()
	h := raylib.GetRenderHeight()
	if water_shader.tex_w == w && water_shader.tex_h == h { return }
	if water_shader.tex_w > 0 {
		raylib.UnloadRenderTexture(water_shader.mask_tex)
	}
	water_shader.mask_tex = raylib.LoadRenderTexture(w, h)
	water_shader.tex_w    = w
	water_shader.tex_h    = h
}

water_shader_unload :: proc() {
	raylib.UnloadShader(water_shader.shader)
	if water_shader.tex_w > 0 {
		raylib.UnloadRenderTexture(water_shader.mask_tex)
	}
}

// ── Heightmap overlay shader ─────────────────────────────────────────────────

Heightmap_Shader :: struct {
	shader:               raylib.Shader,
	loc_contrast:         i32,
	loc_alpha_max:        i32,
	loc_contour_steps:    i32,
	loc_contour_strength: i32,
	loc_contour_width:    i32,
	loc_map_pixel_size:   i32,
}

heightmap_shader: Heightmap_Shader

heightmap_shader_init :: proc() {
	s := raylib.LoadShader(nil, "assets/heightmap.glsl")
	heightmap_shader = Heightmap_Shader{
		shader               = s,
		loc_contrast         = raylib.GetShaderLocation(s, "u_contrast"),
		loc_alpha_max        = raylib.GetShaderLocation(s, "u_alpha_max"),
		loc_contour_steps    = raylib.GetShaderLocation(s, "u_contour_steps"),
		loc_contour_strength = raylib.GetShaderLocation(s, "u_contour_strength"),
		loc_contour_width    = raylib.GetShaderLocation(s, "u_contour_width"),
		loc_map_pixel_size   = raylib.GetShaderLocation(s, "u_map_pixel_size"),
	}
}

heightmap_shader_unload :: proc() {
	raylib.UnloadShader(heightmap_shader.shader)
}

// ── Grass overlay shader (Plain & Forest biomes) ─────────────────────────────

Grass_Shader :: struct {
	shader:          raylib.Shader,
	loc_resolution:  i32,
	loc_cam_offset:  i32,
	loc_zoom:        i32,
	loc_time:        i32,
	loc_alpha:       i32,
	loc_density:     i32,
	loc_grass_color: i32,
}

grass_shader: Grass_Shader

grass_shader_init :: proc() {
	s := raylib.LoadShader(nil, "assets/grass.glsl")
	grass_shader = Grass_Shader{
		shader          = s,
		loc_resolution  = raylib.GetShaderLocation(s, "u_resolution"),
		loc_cam_offset  = raylib.GetShaderLocation(s, "u_camera_offset"),
		loc_zoom        = raylib.GetShaderLocation(s, "u_zoom"),
		loc_time        = raylib.GetShaderLocation(s, "u_time"),
		loc_alpha       = raylib.GetShaderLocation(s, "u_alpha"),
		loc_density     = raylib.GetShaderLocation(s, "u_density"),
		loc_grass_color = raylib.GetShaderLocation(s, "u_grass_color"),
	}
}

grass_shader_unload :: proc() {
	raylib.UnloadShader(grass_shader.shader)
}

render_grass_overlay :: proc(app: ^entities.App_State, m: ^entities.Map, cs: f32) {
	style := constants.BIOME_GRASS_STYLES[m.biome]
	if style.alpha <= 0 { return }
	if grass_shader.shader.id <= 1 { return }

	w    := f32(raylib.GetRenderWidth())
	h    := f32(raylib.GetRenderHeight())
	t    := f32(raylib.GetTime())
	res  := [2]f32{w, h}
	cam  := [2]f32{f32(app.camera_offset_x), f32(app.camera_offset_y)}
	zoom := app.zoom

	if grass_shader.loc_resolution  >= 0 { raylib.SetShaderValue(grass_shader.shader, grass_shader.loc_resolution,  &res,              .VEC2)  }
	if grass_shader.loc_cam_offset  >= 0 { raylib.SetShaderValue(grass_shader.shader, grass_shader.loc_cam_offset,  &cam,              .VEC2)  }
	if grass_shader.loc_zoom        >= 0 { raylib.SetShaderValue(grass_shader.shader, grass_shader.loc_zoom,        &zoom,             .FLOAT) }
	if grass_shader.loc_time        >= 0 { raylib.SetShaderValue(grass_shader.shader, grass_shader.loc_time,        &t,                .FLOAT) }
	if grass_shader.loc_alpha       >= 0 { raylib.SetShaderValue(grass_shader.shader, grass_shader.loc_alpha,       &style.alpha,      .FLOAT) }
	if grass_shader.loc_density     >= 0 { raylib.SetShaderValue(grass_shader.shader, grass_shader.loc_density,     &style.density,    .FLOAT) }
	if grass_shader.loc_grass_color >= 0 { raylib.SetShaderValue(grass_shader.shader, grass_shader.loc_grass_color, &style.grass_color, .VEC4) }

	raylib.BeginShaderMode(grass_shader.shader)
	raylib.DrawRectangle(
		app.camera_offset_x,
		app.camera_offset_y,
		i32(f32(m.width) * cs),
		i32(f32(m.height) * cs),
		raylib.WHITE,
	)
	raylib.EndShaderMode()
}

// ── Glow circle shader (enemy spawn / goal-reach particles) ─────────────────

_glow_circle_shader: raylib.Shader
_glow_white_tex:     raylib.Texture2D  // 1×1 white pixel — ensures UV interpolates 0..1

glow_circle_shader_init :: proc() {
	_glow_circle_shader = raylib.LoadShader(nil, "assets/glow_circle.glsl")
	img := raylib.GenImageColor(1, 1, raylib.WHITE)
	_glow_white_tex = raylib.LoadTextureFromImage(img)
	raylib.UnloadImage(img)
}

glow_circle_shader_unload :: proc() {
	raylib.UnloadShader(_glow_circle_shader)
	raylib.UnloadTexture(_glow_white_tex)
}

render_glow_particles :: proc(app: ^entities.App_State, cs: f32) {
	if len(app.sim.glow_particles) == 0 { return }

	raylib.BeginShaderMode(_glow_circle_shader)
	defer raylib.EndShaderMode()

	for &p in app.sim.glow_particles {
		progress  := p.t / p.lifetime           // 0..1
		ease      := progress * progress         // cuadrático: acelera hacia el final
		alpha     := u8((1.0 - progress) * 255)

		color := raylib.Color{255, 255, 255, alpha}

		radius_px := (p.radius_start + (p.radius_end - p.radius_start) * progress) * cs
		quad_half := radius_px * 2.2  // ring_d=0.45 → ring edge sits at 0.45*2.2*r = r

		dy_cells  := p.dy_start + (p.dy_end - p.dy_start) * ease
		sx := f32(app.camera_offset_x) + p.grid_x * cs
		sy := f32(app.camera_offset_y) + p.grid_y * cs + dy_cells * cs

		// DrawTexturePro interpolates UV 0..1 across the quad — required for shader
		raylib.DrawTexturePro(
			_glow_white_tex,
			{0, 0, 1, 1},
			{sx - quad_half, sy - quad_half, quad_half * 2, quad_half * 2},
			{0, 0},
			0,
			color,
		)
	}
}

// ── Cloud layer shader ───────────────────────────────────────────────────────

Cloud_Shader :: struct {
	shader:            raylib.Shader,
	loc_res:           i32,
	loc_time:          i32,
	loc_opacity:       i32,
	loc_camera_offset: i32,
}

cloud_shader: Cloud_Shader

cloud_shader_init :: proc() {
	s := raylib.LoadShader(nil, "assets/clouds.glsl")
	cloud_shader = Cloud_Shader{
		shader            = s,
		loc_res           = raylib.GetShaderLocation(s, "u_resolution"),
		loc_time          = raylib.GetShaderLocation(s, "u_time"),
		loc_opacity       = raylib.GetShaderLocation(s, "u_opacity"),
		loc_camera_offset = raylib.GetShaderLocation(s, "u_camera_offset"),
	}
}

cloud_shader_unload :: proc() {
	raylib.UnloadShader(cloud_shader.shader)
}

cloud_shader_draw :: proc(app: ^entities.App_State) {
	if app.zoom == constants.ZOOM_MAX { return }

	// Opacity: 1.0 at ZOOM_MIN, 0.0 at ZOOM_FADE_OUT
	// smoothstep maps zoom → [0,1] then we invert
	zoom_fade_out :: f32(1.3)
	opacity := 1.0 - math.smoothstep(constants.ZOOM_MIN, zoom_fade_out, app.zoom)
	if opacity <= 0.001 { return }

	w   := f32(raylib.GetRenderWidth())
	h   := f32(raylib.GetRenderHeight())
	t   := f32(raylib.GetTime())
	res := [2]f32{w, h}
	cam := [2]f32{f32(app.camera_offset_x), f32(app.camera_offset_y)}

	if cloud_shader.loc_res >= 0 {
		raylib.SetShaderValue(cloud_shader.shader, cloud_shader.loc_res, &res, .VEC2)
	}
	if cloud_shader.loc_time >= 0 {
		raylib.SetShaderValue(cloud_shader.shader, cloud_shader.loc_time, &t, .FLOAT)
	}
	if cloud_shader.loc_opacity >= 0 {
		raylib.SetShaderValue(cloud_shader.shader, cloud_shader.loc_opacity, &opacity, .FLOAT)
	}
	if cloud_shader.loc_camera_offset >= 0 {
		raylib.SetShaderValue(cloud_shader.shader, cloud_shader.loc_camera_offset, &cam, .VEC2)
	}

	raylib.BeginShaderMode(cloud_shader.shader)
	raylib.DrawRectangle(0, 0, i32(w), i32(h), raylib.WHITE)
	raylib.EndShaderMode()
}

// Render the entire game
render_game :: proc(app: ^entities.App_State) {
	ui_blocks_clear()
	raylib.ClearBackground(raylib.BLACK)		

	if app.state == .MENU ||
		app.state == .RUN_COMPLETE ||
		app.state == .CAMPAIGN_MAP ||
		app.state == .PROGRESSION {
			nebula_draw()
	}

	// Map and gameplay are only visible while actually playing or editing.
	// In menu/overlay states the nebula is the sole background.
	if app.state == .PLAYING || app.state == .PAUSED || app.state == .EDITOR {
		render_map(app, &app.editor.game_map)
		render_tower_ranges(app)
		render_map_objects(app, &app.editor.game_map)
		render_gameplay(app)
		render_airdrops(app)
	}

	if app.state == .PLAYING || app.state == .PAUSED || app.state == .EDITOR {
		update_bird_flock(app, app.delta_time)
		render_bird_flock(app)
		// cloud_shader_draw(app)  // desactivado
	}
	render_ui(app)
	render_tooltip_layer(app) // Always last — draws on top of everything
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

		// Relleno sutil + outline nítido (sin outline el rango es invisible).
		// Ver CLAUDE.md → "render_tower_ranges → ⚠️ Trampa conocida".
		raylib.DrawCircle(cx_i, cy_i, range_px, constants.TOWER_RANGE_PREVIEW)
		raylib.DrawCircleLines(cx_i, cy_i, range_px, raylib.Color{255, 255, 255, 200})
	}
}

// Dibuja un overlay difuminado sobre un tile para marcar un action target.
// El blur se simula con LAYERS rectángulos concéntricos: el más externo cubre el
// tile completo y el más interno cubre el 80%. Cada capa tiene el mismo alpha base,
// por lo que el área central (cubierta por todas las capas) acumula más opacidad.
// layer_alpha controla la intensidad: más bajo = más sutil (p.ej. al hacer hover).
draw_action_target :: proc(x, y, cs: f32, color: raylib.Color, layer_alpha: u8 = 20) {
	LAYERS   :: 5
	PAD_STEP :: f32(0.025)   // cada capa se inset 2.5% del tile
	for k in 0 ..< LAYERS {
		pad := cs * PAD_STEP * f32(k)
		sz  := cs - 2 * pad
		c   := raylib.Color{color.r, color.g, color.b, layer_alpha}
		raylib.DrawRectangleRounded(raylib.Rectangle{x + pad, y + pad, sz, sz}, 0.4, 6, c)
	}
}

// Render map objects (towers, spawn, goal, accessories, obstacles) - intermediate layer
render_map_objects :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs    := f32(app.settings.cell_size) * app.zoom
	mouse := raylib.GetMousePosition()

	COLOR_TARGET_VALID   :: raylib.Color{60, 220, 90, 255}   // verde: action target válido
	COLOR_TARGET_INVALID :: raylib.Color{220, 60, 60, 255}   // rojo: inválido / origen Gardener

	// ── Pasada 1: overlays de casillas posibles (debajo de los objetos del mapa) ──
	if app.pending_tower_action != .TOWER && (app.state == .PLAYING || app.state == .PAUSED) {
		for row in 0 ..< m.height {
			for col in 0 ..< m.width {
				tile    := m.grid[row][col]
				x       := f32(col) * cs + f32(app.camera_offset_x)
				y       := f32(row) * cs + f32(app.camera_offset_y)
				hovered := raylib.CheckCollisionPointRec(mouse, raylib.Rectangle{x, y, cs, cs})
				// Hover más sutil: layer_alpha más bajo para dar mayor transparencia
				layer_a := u8(hovered ? 10 : 20)

				is_tower_tile := tile == .TOWER_ARCHER || tile == .TOWER_CANNON ||
				                 tile == .TOWER_SNIPER  || tile == .TOWER_MISSILE ||
				                 tile == .TOWER_LASER   || tile == .TOWER_ICE ||
				                 tile == .TOWER_ENHANCE || tile == .TOWER_TESLA ||
				                 tile == .TOWER_MORTAR

				drew_target := false

				#partial switch app.pending_tower_action {
				case .LUMBERJACK:
					if tile == .ACCESSORY_TREE && !m.water_grid[row][col] {
						draw_action_target(x, y, cs, COLOR_TARGET_VALID, layer_a)
						drew_target = true
					}
				case .OVERDRIVE:
					if is_tower_tile {
						draw_action_target(x, y, cs, COLOR_TARGET_VALID, layer_a)
						drew_target = true
					}
				case .GARDENER:
					if app.gardener_source == {-1, -1} {
						// Fase 1: torres válidas en verde
						if is_tower_tile {
							draw_action_target(x, y, cs, COLOR_TARGET_VALID, layer_a)
							drew_target = true
						}
					} else {
						// Fase 2: origen siempre en rojo, destinos válidos en verde
						if app.gardener_source == {i32(row), i32(col)} {
							draw_action_target(x, y, cs, COLOR_TARGET_INVALID, 25)
							drew_target = true
						} else if tile == .EMPTY &&
						          m.obstacle_grid[row][col] == .EMPTY &&
						          !m.water_grid[row][col] {
							draw_action_target(x, y, cs, COLOR_TARGET_VALID, layer_a)
							drew_target = true
						}
					}
				case .TOWER:
					// inactivo
				}

				// Tile hovereado sin ser target válido → overlay rojo sutil
				if hovered && !drew_target {
					draw_action_target(x, y, cs, COLOR_TARGET_INVALID, 8)
				}
			}
		}
	}

	// ── Pasada 2: objetos del mapa (encima de los overlays) ──────────────────────
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			tile := m.grid[row][col]
			x := f32(col) * cs + f32(app.camera_offset_x)
			y := f32(row) * cs + f32(app.camera_offset_y)

			#partial switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER,
			     .TOWER_ICE, .TOWER_ENHANCE, .TOWER_TESLA, .TOWER_MORTAR:
				if app.state == .PLAYING || app.state == .PAUSED {
					for &tower in app.sim.towers {
						if tower.r == i32(row) && tower.c == i32(col) {
							render_tower(&tower, x, y, cs)
							break
						}
					}
				} else {
					tower_type := tile_to_tower_type(tile)
					draw_tower_tile(x, y, cs, tower_type, 0, false)
				}

			case .SPAWN:
				render_spawn(x, y, cs)

			case .GOAL:
				render_goal(x, y, cs)

			case .ACCESSORY_TREE:
				if m.water_grid[row][col] {
					render_water_lily(x, y, cs, i32(row), i32(col))
				} else {
					render_tree(x, y, cs, m.biome, i32(row), i32(col))
				}

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

	// Retícula sobre el tile hovereado en modo selección de carta activa
	if app.pending_tower_action != .TOWER && (app.state == .PLAYING || app.state == .PAUSED) {
		hover_col := int((mouse.x - f32(app.camera_offset_x)) / cs)
		hover_row := int((mouse.y - f32(app.camera_offset_y)) / cs)
		if hover_col >= 0 && hover_col < int(m.width) && hover_row >= 0 && hover_row < int(m.height) {
			rx := f32(hover_col) * cs + f32(app.camera_offset_x)
			ry := f32(hover_row) * cs + f32(app.camera_offset_y)
			render_reticle(rx, ry, cs, constants.UI_RETICLE_COLOR)
		}
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

// Overlay de heightmap — dibuja un gradient continuo (vía shader) que tinta el
// terreno según el heightmap del mapa. Hace upload lazy de la textura GPU si
// está marcada como dirty (típicamente después de map_load o map_init).
// La intensidad/contraste/isolíneas dependen del bioma (BIOME_HEIGHTMAP_STYLES).
render_heightmap_overlay :: proc(app: ^entities.App_State, m: ^entities.Map, cs: f32) {
	style := constants.BIOME_HEIGHTMAP_STYLES[m.biome]
	if style.alpha_max <= 0 && style.contour_strength <= 0 { return }

	// Lazy upload: si dirty o nunca subida, regenerar la textura desde m.heightmap.
	if m.heightmap_tex_dirty || !m.heightmap_tex_valid {
		entities.map_upload_heightmap_to_gpu(m)
	}
	if !m.heightmap_tex_valid { return }

	// Si el shader no cargó (id <= 1 = default fallback), salir.
	if heightmap_shader.shader.id <= 1 { return }

	// Pasar uniforms del bioma.
	contrast        := style.contrast_mult
	alpha_max       := style.alpha_max
	contour_steps   := style.contour_steps
	contour_strength := style.contour_strength
	contour_width   := style.contour_width
	if heightmap_shader.loc_contrast >= 0 {
		raylib.SetShaderValue(heightmap_shader.shader, heightmap_shader.loc_contrast, &contrast, .FLOAT)
	}
	if heightmap_shader.loc_alpha_max >= 0 {
		raylib.SetShaderValue(heightmap_shader.shader, heightmap_shader.loc_alpha_max, &alpha_max, .FLOAT)
	}
	if heightmap_shader.loc_contour_steps >= 0 {
		raylib.SetShaderValue(heightmap_shader.shader, heightmap_shader.loc_contour_steps, &contour_steps, .FLOAT)
	}
	if heightmap_shader.loc_contour_strength >= 0 {
		raylib.SetShaderValue(heightmap_shader.shader, heightmap_shader.loc_contour_strength, &contour_strength, .FLOAT)
	}
	if heightmap_shader.loc_contour_width >= 0 {
		raylib.SetShaderValue(heightmap_shader.shader, heightmap_shader.loc_contour_width, &contour_width, .FLOAT)
	}
	// Tamaño del mapa en "píxeles de referencia" (constante, sin zoom) — ancla el
	// patrón de dithering al terreno en vez de a la pantalla.
	map_pixel_size := [2]f32{f32(m.width) * f32(constants.CELL_SIZE), f32(m.height) * f32(constants.CELL_SIZE)}
	if heightmap_shader.loc_map_pixel_size >= 0 {
		raylib.SetShaderValue(heightmap_shader.shader, heightmap_shader.loc_map_pixel_size, &map_pixel_size, .VEC2)
	}

	// src: solo la porción del heightmap que corresponde al mapa real (m.width × m.height).
	// dst: el área del mapa en pantalla.
	src := raylib.Rectangle{0, 0, f32(m.width), f32(m.height)}
	dst := raylib.Rectangle{
		f32(app.camera_offset_x),
		f32(app.camera_offset_y),
		f32(m.width) * cs,
		f32(m.height) * cs,
	}

	raylib.BeginShaderMode(heightmap_shader.shader)
	raylib.DrawTexturePro(m.heightmap_tex, src, dst, {0, 0}, 0, raylib.WHITE)
	raylib.EndShaderMode()
}

// Render map (grid, paths, obstacles)
render_map :: proc(app: ^entities.App_State, m: ^entities.Map, for_preview: bool = false) {
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

	// Grass overlay — se dibuja ANTES del agua para que el agua la tape naturalmente.
	if !for_preview { render_grass_overlay(app, m, cs) }

	// Heightmap overlay — se dibuja ANTES del agua para que el agua lo tape
	// en las celdas acuáticas (sin heightmap ni contornos sobre el agua).
	render_heightmap_overlay(app, m, cs)

	render_water_layer(m, cs, app.camera_offset_x, app.camera_offset_y, app.zoom, for_preview)
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
				// Ghost de obstáculo: rojo si está en esquina/unión, normal si es válido
				forbidden := entities.map_is_path_corner_or_junction(
					m,
					app.selected_cell.row, app.selected_cell.col,
				)
				if forbidden {
					draw_obstacle_preview_invalid(sx, sy, cs, m, app.selected_cell.row, app.selected_cell.col)
				} else {
					draw_obstacle_preview(sx, sy, cs, m, app.selected_cell.row, app.selected_cell.col)
				}
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

// Render map preview to a RenderTexture2D for the map browser.
// Saves and restores the relevant app fields used by render_map / render_map_objects.
render_map_preview_to_texture :: proc(app: ^entities.App_State) {
	m := &app.editor.browser.preview

	// Unload previous texture if any
	if app.editor.browser.preview_tex_valid {
		raylib.UnloadRenderTexture(app.editor.browser.preview_tex)
		app.editor.browser.preview_tex_valid = false
	}

	cs    := f32(app.settings.cell_size)
	tex_w := i32(f32(m.width)  * cs)
	tex_h := i32(f32(m.height) * cs)
	app.editor.browser.preview_tex = raylib.LoadRenderTexture(tex_w, tex_h)

	// Save fields that render_map / render_map_objects read from app
	saved_offset_x          := app.camera_offset_x
	saved_offset_y          := app.camera_offset_y
	saved_zoom              := app.zoom
	saved_state             := app.state
	saved_show_grid         := app.settings.show_grid
	saved_selected_cell     := app.selected_cell.valid

	// Override for a clean, static preview (no camera pan, no ghost, no reticles)
	app.camera_offset_x     = 0
	app.camera_offset_y     = 0
	app.zoom                = 1.0
	app.state               = .EDITOR
	app.settings.show_grid  = false
	app.selected_cell.valid = false

	// Pre-computar la máscara de agua ANTES de entrar al BeginTextureMode.
	// La máscara se redimensiona temporalmente al tamaño del preview (1:1 pixel)
	// para que el shader UV mapping sea exacto, luego se restaura al tamaño
	// de pantalla para el render normal.
	cs_preview := f32(app.settings.cell_size)  // zoom=1 en la preview

	// Swap mask to preview size
	saved_mask_w := water_shader.tex_w
	saved_mask_h := water_shader.tex_h
	saved_mask   := water_shader.mask_tex
	water_shader.mask_tex = raylib.LoadRenderTexture(tex_w, tex_h)
	water_shader.tex_w    = tex_w
	water_shader.tex_h    = tex_h

	water_render_mask(m, cs_preview, 0, 0)

	raylib.BeginTextureMode(app.editor.browser.preview_tex)
		render_map(app, m, true)
		render_map_objects(app, m)
	raylib.EndTextureMode()

	// Restore mask to screen size
	raylib.UnloadRenderTexture(water_shader.mask_tex)
	water_shader.mask_tex = saved_mask
	water_shader.tex_w    = saved_mask_w
	water_shader.tex_h    = saved_mask_h

	// Restore
	app.camera_offset_x     = saved_offset_x
	app.camera_offset_y     = saved_offset_y
	app.zoom                = saved_zoom
	app.state               = saved_state
	app.settings.show_grid  = saved_show_grid
	app.selected_cell.valid = saved_selected_cell

	app.editor.browser.preview_tex_valid = true
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

			// Bridge railings — solo en PATH con agua debajo
			if tile == .PATH && m.water_grid[row][col] {
				pw := path_width
				rt := cs * constants.BRIDGE_RAILING_THICK
				rc := constants.COLOR_BRIDGE_RAILING
				sg := constants.BRIDGE_RAILING_SEGS

				if !top    { raylib.DrawRectangleRounded({cx - pw/2,      cy - pw/2,      pw, rt}, 1, sg, rc) }
				if !bottom { raylib.DrawRectangleRounded({cx - pw/2,      cy + pw/2 - rt, pw, rt}, 1, sg, rc) }
				if !left   { raylib.DrawRectangleRounded({cx - pw/2,      cy - pw/2,      rt, pw}, 1, sg, rc) }
				if !right  { raylib.DrawRectangleRounded({cx + pw/2 - rt, cy - pw/2,      rt, pw}, 1, sg, rc) }
			}
		}
	}
}

// Render grid lines
render_grid_lines :: proc(app: ^entities.App_State, cs: f32, map_w, map_h: i32) {
	raylib.BeginBlendMode(.MULTIPLIED)
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
	raylib.EndBlendMode()
}
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

// Calcula las dimensiones (bar_w, bar_h) de un obstáculo según la orientación del camino
// en (row, col). Igual lógica que render_obstacles para mantener coherencia visual.
obstacle_bar_dims :: proc(m: ^entities.Map, row, col: i32, cs: f32) -> (bar_w, bar_h: f32) {
	is_path_like :: proc(m: ^entities.Map, r, c: i32) -> bool {
		if r < 0 || r >= m.height || c < 0 || c >= m.width { return false }
		t := m.grid[r][c]
		return t == .PATH || t == .SPAWN || t == .GOAL
	}
	has_v := is_path_like(m, row-1, col) || is_path_like(m, row+1, col)
	has_h := is_path_like(m, row, col-1) || is_path_like(m, row, col+1)
	if has_v && !has_h {
		// Camino vertical → barrera horizontal
		bar_w = cs * constants.OBSTACLE_BARRIER_LENGTH
		bar_h = cs * constants.OBSTACLE_BARRIER_THICKNESS
	} else {
		// Camino horizontal (o por defecto) → barrera vertical
		bar_w = cs * constants.OBSTACLE_BARRIER_THICKNESS
		bar_h = cs * constants.OBSTACLE_BARRIER_LENGTH
	}
	return
}

// Draw a single obstacle at specific position (for toolbar preview)
draw_obstacle_preview :: proc(x, y, cs: f32, m: ^entities.Map = nil, row: i32 = -1, col: i32 = -1) {
	bar_w, bar_h: f32
	if m != nil && row >= 0 {
		bar_w, bar_h = obstacle_bar_dims(m, row, col, cs)
	} else {
		// Orientación por defecto (toolbar)
		bar_w = cs * constants.OBSTACLE_BARRIER_THICKNESS
		bar_h = cs * constants.OBSTACLE_BARRIER_LENGTH
	}
	bar_x := x + cs/2 - bar_w/2
	bar_y := y + cs/2 - bar_h/2
	rect  := raylib.Rectangle{bar_x, bar_y, bar_w, bar_h}
	shadow := raylib.Rectangle{bar_x + constants.OBSTACLE_BARRIER_SHADOW_OFFSET, bar_y + constants.OBSTACLE_BARRIER_SHADOW_OFFSET, bar_w, bar_h}
	raylib.DrawRectangleRounded(shadow, constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, constants.COLOR_OBSTACLE_SHADOW)
	raylib.DrawRectangleRounded(rect,   constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, constants.COLOR_OBSTACLE_FILL)
	raylib.DrawRectangleRoundedLines(rect, constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, constants.OBSTACLE_BARRIER_BORDER_THICK, constants.COLOR_OBSTACLE_BORDER)
}

// Preview de obstáculo inválido (esquina/unión): tinte rojo semitransparente
draw_obstacle_preview_invalid :: proc(x, y, cs: f32, m: ^entities.Map = nil, row: i32 = -1, col: i32 = -1) {
	bar_w, bar_h: f32
	if m != nil && row >= 0 {
		bar_w, bar_h = obstacle_bar_dims(m, row, col, cs)
	} else {
		bar_w = cs * constants.OBSTACLE_BARRIER_THICKNESS
		bar_h = cs * constants.OBSTACLE_BARRIER_LENGTH
	}
	bar_x := x + cs/2 - bar_w/2
	bar_y := y + cs/2 - bar_h/2
	rect  := raylib.Rectangle{bar_x, bar_y, bar_w, bar_h}
	raylib.DrawRectangleRounded(rect, constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, raylib.Color{220, 50, 50, 160})
	raylib.DrawRectangleRoundedLines(rect, constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, constants.OBSTACLE_BARRIER_BORDER_THICK, raylib.Color{255, 80, 80, 220})
	// Cruz para indicar que no es válido
	cx := x + cs/2
	cy := y + cs/2
	arm := cs * 0.18
	thick := f32(2)
	raylib.DrawLineEx({cx - arm, cy - arm}, {cx + arm, cy + arm}, thick, raylib.Color{255, 255, 255, 200})
	raylib.DrawLineEx({cx + arm, cy - arm}, {cx - arm, cy + arm}, thick, raylib.Color{255, 255, 255, 200})
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
		color := beam.color
		color.a = u8(f32(color.a) * alpha)

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

	// Render glow particles (spawn / goal-reach ring effects, above enemies)
	render_glow_particles(app, cs)

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

		render_enemy_shape(cx, cy, size, color, .FLYING in enemy.flags, .BOSS in enemy.flags, so)

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

		case .MORTAR:
			// Large dark shell — bigger and slower-looking than a cannonball
			raylib.DrawCircle(i32(x) + 1, i32(y) + 1, cs * 0.14, raylib.Color{0, 0, 0, 60})
			raylib.DrawCircle(i32(x), i32(y), cs * 0.13, constants.TOWER_MORTAR_BASE)
			raylib.DrawCircle(i32(x), i32(y), cs * 0.06, constants.TOWER_MORTAR_STROKE)
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
	font: raylib.Font = {},
) {
	f := font if font.baseSize > 0 else constants.game_fonts.bold

	// Draw outline by drawing the text in outline color at offset positions
	for y_offset in -outline_thickness ..= outline_thickness {
		for x_offset in -outline_thickness ..= outline_thickness {
			if x_offset == 0 && y_offset == 0 do continue
			raylib.DrawTextEx(f, text, {pos.x + f32(x_offset), pos.y + f32(y_offset)}, font_size, spacing, outline_color)
		}
	}

	// Draw main text on top
	raylib.DrawTextEx(f, text, pos, font_size, spacing, text_color)
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

		display_value := i32(dn.value + 0.5)
		if display_value == 0 {
			continue
		}

		if dn.is_money {
			// Número de dinero: "+$X" en amarillo, tamaño fijo ligeramente mayor
			money_text := fmt.ctprintf("+$%d", display_value)
			font_size  := cs * 0.32
			draw_text_with_outline(money_text, {x, y}, font_size, 0, color, outline_color, 1)
		} else {
			damage_text := fmt.ctprintf("%d", display_value)
			font_size := cs * 0.25
			if dn.is_critical {
				font_size = cs * 0.5
			}
			draw_text_with_outline(damage_text, {x, y}, font_size, 0, color, outline_color, 1)
		}
	}
}
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
	case .TESLA:
		fill = constants.TOWER_TESLA_BASE
		stroke = constants.TOWER_TESLA_STROKE
	case .MORTAR:
		fill = constants.TOWER_MORTAR_BASE
		stroke = constants.TOWER_MORTAR_STROKE
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
	case .LASER:   draw_tower_components_laser(cx, cy, cs, rotation, so, r)
	case .CANNON:  draw_tower_components_cannon(cx, cy, cs, rotation, so, r, stroke)
	case .SNIPER:  draw_tower_components_sniper(cx, cy, cs, rotation, so, r, stroke)
	case .MISSILE: draw_tower_components_missile(cx, cy, rotation, so, r)
	case .ARCHER:  draw_tower_components_archer(cx, cy, cs, rotation, so)
	case .ICE:     draw_tower_components_ice(cx, cy, cs, so, r)
	case .ENHANCE: draw_tower_components_enhance(cx, cy, cs, so, r)
	case .TESLA:   draw_tower_components_tesla(cx, cy, cs, so, r)
	case .MORTAR:  draw_tower_components_mortar(cx, cy, cs, so)
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Componentes por tipo de torre — extraídos de draw_tower_tile.
// Cada proc dibuja los elementos específicos (barril, núcleo, brazos, etc.).
// El fondo común (sombra + base rounded) se dibuja en draw_tower_tile antes
// del dispatch. Las procs reciben todas las variables locales que necesitan
// para no depender de cierres léxicos.
// ─────────────────────────────────────────────────────────────────────────────

draw_tower_components_laser :: proc(cx, cy, cs, rotation, so, r: f32) {
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
}

draw_tower_components_cannon :: proc(cx, cy, cs, rotation, so, r: f32, stroke: raylib.Color) {
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
}

draw_tower_components_sniper :: proc(cx, cy, cs, rotation, so, r: f32, stroke: raylib.Color) {
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
}

draw_tower_components_missile :: proc(cx, cy, rotation, so, r: f32) {
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
}

draw_tower_components_archer :: proc(cx, cy, cs, rotation, so: f32) {
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

draw_tower_components_ice :: proc(cx, cy, cs, so, r: f32) {
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
}

draw_tower_components_enhance :: proc(cx, cy, cs, so, r: f32) {
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

draw_tower_components_tesla :: proc(cx, cy, cs, so, r: f32) {
	// 3 electrodes at 120° apart, each with a glowing tip
	elec_r  := cs * 0.30
	prong_w := max(1.5, cs * 0.065)
	for i in 0 ..< 3 {
		a  := f32(i) * math.PI * 2.0 / 3.0
		ex := cx + math.cos(a) * elec_r
		ey := cy + math.sin(a) * elec_r
		// Shadow
		raylib.DrawLineEx({cx + so, cy + so}, {ex + so, ey + so}, prong_w, constants.TOWER_SHADOW)
		// Electrode arm
		raylib.DrawLineEx({cx, cy}, {ex, ey}, prong_w, constants.TOWER_TESLA_STROKE)
		// Tip ball
		raylib.DrawCircle(i32(ex + so), i32(ey + so), cs * 0.065, constants.TOWER_SHADOW)
		raylib.DrawCircle(i32(ex), i32(ey), cs * 0.065, constants.TOWER_TESLA_ARC)
	}
	// Central core
	raylib.DrawCircle(i32(cx + so), i32(cy + so), r * 0.48, constants.TOWER_SHADOW)
	raylib.DrawCircle(i32(cx), i32(cy), r * 0.48, constants.TOWER_TESLA_STROKE)
	raylib.DrawCircle(i32(cx), i32(cy), r * 0.24, constants.TOWER_TESLA_ARC)
}

draw_tower_components_mortar :: proc(cx, cy, cs, so: f32) {
	// Wide squat barrel always pointing straight up (ignores tower rotation)
	barrel_w := cs * 0.26
	barrel_h := cs * 0.28
	bx       := cx - barrel_w / 2
	by       := cy - barrel_h
	// Shadow
	raylib.DrawRectangle(i32(bx + so), i32(by + so), i32(barrel_w), i32(barrel_h), constants.TOWER_SHADOW)
	// Barrel body
	raylib.DrawRectangle(i32(bx), i32(by), i32(barrel_w), i32(barrel_h), constants.TOWER_MORTAR_BASE)
	raylib.DrawRectangleLines(i32(bx), i32(by), i32(barrel_w), i32(barrel_h), constants.TOWER_MORTAR_STROKE)
	// Bore (dark circle at barrel mouth)
	bore_r := cs * 0.068
	raylib.DrawCircle(i32(cx + so), i32(by + bore_r + so), bore_r, constants.TOWER_SHADOW)
	raylib.DrawCircle(i32(cx), i32(by + bore_r), bore_r, constants.TOWER_MORTAR_STROKE)
	raylib.DrawCircle(i32(cx), i32(by + bore_r), bore_r * 0.5, raylib.Color{20, 20, 20, 220})
}

// Render tower for simulation (calls unified function with rotation)
render_tower :: proc(tower: ^entities.Tower, x, y, cs: f32) {
	draw_tower_tile(x, y, cs, tower.type, tower.angle, false)
}

// Render reticle for selected cell (corner brackets style like JS)
render_reticle :: proc(x, y, cs: f32, color: raylib.Color) {
	reticle_size := cs * 0.7
	reticle_len := cs * 0.15
	corner_thickness := max(2, cs * 0.04)

	cx := x + cs / 2
	cy := y + cs / 2
	rx := cx - reticle_size / 2
	ry := cy - reticle_size / 2

	// Top-left corner
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

// =============================================================================
// Water layer
// =============================================================================

// Fase 1: renderiza la máscara de agua (rectángulos blancos) en water_shader.mask_tex.
// Debe llamarse FUERA de cualquier BeginTextureMode activo.
water_render_mask :: proc(m: ^entities.Map, cs: f32, camera_offset_x, camera_offset_y: i32) {
	// No llamar water_shader_resize() aquí: la máscara ya tiene el tamaño
	// correcto (pantalla en el path normal, preview en render_map_preview_to_texture).
	raylib.BeginTextureMode(water_shader.mask_tex)
	raylib.ClearBackground(raylib.Color{0, 0, 0, 0})
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			if !m.water_grid[row][col] { continue }
			x := f32(col) * cs + f32(camera_offset_x)
			y := f32(row) * cs + f32(camera_offset_y)
			raylib.DrawRectangleRec({x, y, cs, cs}, raylib.WHITE)
		}
	}
	raylib.EndTextureMode()
}

// Fase 2: aplica el shader de blur+threshold sobre la máscara pre-computada.
// Dibuja al render target activo (pantalla o una RenderTexture2D de preview).
water_render_apply :: proc(cam_x: f32 = 0, cam_y: f32 = 0, zoom: f32 = 1.0) {
	wc := constants.COLOR_WATER
	ec := constants.COLOR_WATER_EDGE
	water_color := [4]f32{f32(wc.r)/255, f32(wc.g)/255, f32(wc.b)/255, f32(wc.a)/255}
	edge_color  := [4]f32{f32(ec.r)/255, f32(ec.g)/255, f32(ec.b)/255, f32(ec.a)/255}
	texel_size  := [2]f32{1.0 / f32(water_shader.tex_w), 1.0 / f32(water_shader.tex_h)}
	t           := f32(raylib.GetTime())
	cam         := [2]f32{cam_x, cam_y}
	z           := zoom

	raylib.SetShaderValue(water_shader.shader, water_shader.loc_texel, &texel_size,  .VEC2)
	raylib.SetShaderValue(water_shader.shader, water_shader.loc_water, &water_color, .VEC4)
	raylib.SetShaderValue(water_shader.shader, water_shader.loc_edge,  &edge_color,  .VEC4)
	if water_shader.loc_time >= 0 { raylib.SetShaderValue(water_shader.shader, water_shader.loc_time, &t,    .FLOAT) }
	if water_shader.loc_cam  >= 0 { raylib.SetShaderValue(water_shader.shader, water_shader.loc_cam,  &cam,  .VEC2)  }
	if water_shader.loc_zoom >= 0 { raylib.SetShaderValue(water_shader.shader, water_shader.loc_zoom, &z,    .FLOAT) }

	raylib.BeginShaderMode(water_shader.shader)
	src := raylib.Rectangle{
		0, f32(water_shader.tex_h),
		f32(water_shader.tex_w), -f32(water_shader.tex_h),
	}
	raylib.DrawTextureRec(water_shader.mask_tex.texture, src, {0, 0}, raylib.WHITE)
	raylib.EndShaderMode()
}

// Render de agua completo (máscara + shader). Usado en el camino normal de juego/editor.
render_water_layer :: proc(m: ^entities.Map, cs: f32, camera_offset_x, camera_offset_y: i32, zoom: f32 = 1.0, for_preview: bool = false) {
	// En modo preview la máscara ya fue computada antes de entrar al BeginTextureMode.
	// Solo aplicamos el shader al render target activo (la textura de preview).
	if for_preview {
		water_render_apply() // preview: sin transform de cámara
		return
	}

	// Verificar que haya agua antes de hacer los dos passes
	has_water := false
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			if m.water_grid[row][col] { has_water = true; break }
		}
		if has_water { break }
	}
	if !has_water { return }

	// Asegurar que la máscara tenga el tamaño de pantalla antes del render normal
	water_shader_resize()
	water_render_mask(m, cs, camera_offset_x, camera_offset_y)
	water_render_apply(f32(camera_offset_x), f32(camera_offset_y), zoom)
}

// =============================================================================
// Bird flock ambient animation
// =============================================================================

update_bird_flock :: proc(app: ^entities.App_State, dt: f32) {
	f    := &app.bird_flock
	zoom := app.zoom

	if f.active {
		f.anim_time += dt

		// Move in world space — velocity is stored as screen px/sec,
		// divide by zoom to get world px/sec so apparent screen speed is constant.
		for i in 0 ..< f.bird_count {
			f.birds[i].pos.x += f.velocity.x / zoom * dt
			f.birds[i].pos.y += f.velocity.y / zoom * dt
		}

		// Deactivate when all birds are off-screen (convert world→screen to check)
		sw   := f32(raylib.GetScreenWidth())
		sh   := f32(raylib.GetScreenHeight())
		cx   := f32(app.camera_offset_x)
		cy   := f32(app.camera_offset_y)
		margin := f32(100)
		all_gone := true
		for i in 0 ..< f.bird_count {
			sx := f.birds[i].pos.x * zoom + cx
			sy := f.birds[i].pos.y * zoom + cy
			if sx > -margin && sx < sw+margin && sy > -margin && sy < sh+margin {
				all_gone = false
				break
			}
		}
		if all_gone {
			f.active = false
		}
	} else {
		f.spawn_timer -= dt
		if f.spawn_timer <= 0 {
			spawn_bird_flock(app)
		}
	}
}

spawn_bird_flock :: proc(app: ^entities.App_State) {
	f    := &app.bird_flock
	zoom := app.zoom
	cam_x := f32(app.camera_offset_x)
	cam_y := f32(app.camera_offset_y)
	sw   := f32(raylib.GetScreenWidth())
	sh   := f32(raylib.GetScreenHeight())

	// World-space screen edges: world = (screen - cam) / zoom
	w_left   := (-cam_x - 60) / zoom
	w_right  := (sw - cam_x + 60) / zoom
	w_top    := (-cam_y - 60) / zoom
	w_bottom := (sh - cam_y + 60) / zoom

	// Use time as a cheap seed
	t := u32(raylib.GetTime() * 1000)
	rng :: proc(seed: ^u32) -> f32 {
		seed^ = seed^ * 1664525 + 1013904223
		return f32(seed^ & 0xFFFF) / f32(0xFFFF)
	}

	// Pick a random edge to spawn from (world coords)
	edge := t % 4  // 0=top, 1=right, 2=bottom, 3=left
	r := rng(&t)

	origin: raylib.Vector2
	target: raylib.Vector2
	w := w_right - w_left
	h := w_bottom - w_top
	switch edge {
	case 0: // top → bottom
		origin = {w_left + r * w, w_top}
		target = {w_left + rng(&t) * w, w_bottom}
	case 1: // right → left
		origin = {w_right, w_top + r * h}
		target = {w_left, w_top + rng(&t) * h}
	case 2: // bottom → top
		origin = {w_left + r * w, w_bottom}
		target = {w_left + rng(&t) * w, w_top}
	case: // left → right
		origin = {w_left, w_top + r * h}
		target = {w_right, w_top + rng(&t) * h}
	}

	// Direction vector
	dx := target.x - origin.x
	dy := target.y - origin.y
	dist := math.sqrt(dx*dx + dy*dy)
	if dist < 1 { dist = 1 }
	dir := raylib.Vector2{dx / dist, dy / dist}

	// Velocity stored as screen px/sec; update divides by zoom to get world px/sec
	f.velocity = {dir.x * constants.BIRD_SPEED, dir.y * constants.BIRD_SPEED}
	f.anim_time = 0

	// Bird count
	count_range := constants.BIRD_COUNT_MAX - constants.BIRD_COUNT_MIN
	f.bird_count = constants.BIRD_COUNT_MIN + i32(rng(&t) * f32(count_range + 1))
	if f.bird_count > 12 { f.bird_count = 12 }

	// Scatter in world space (BIRD_SCATTER_RADIUS is in screen px, convert)
	scatter_world := constants.BIRD_SCATTER_RADIUS / zoom
	for i in 0 ..< f.bird_count {
		scatter_x := (rng(&t) - 0.5) * 2 * scatter_world
		scatter_y := (rng(&t) - 0.5) * 2 * scatter_world
		f.birds[i] = entities.Bird{
			pos   = {origin.x + scatter_x, origin.y + scatter_y},
			phase = rng(&t) * math.PI * 2,
		}
	}

	f.active = true

	// Schedule next flock
	interval_range := constants.BIRD_SPAWN_INTERVAL_MAX - constants.BIRD_SPAWN_INTERVAL_MIN
	f.spawn_timer = constants.BIRD_SPAWN_INTERVAL_MIN + rng(&t) * interval_range
}

render_bird_flock :: proc(app: ^entities.App_State) {
	f := &app.bird_flock
	if !f.active { return }

	zoom  := app.zoom
	cam_x := f32(app.camera_offset_x)
	cam_y := f32(app.camera_offset_y)
	s     := constants.BIRD_SIZE * zoom   // scale with zoom
	c     := constants.COLOR_BIRD
	flap_amp := constants.BIRD_WING_AMP * zoom

	for i in 0 ..< f.bird_count {
		bird := f.birds[i]

		// World → screen
		cx := bird.pos.x * zoom + cam_x
		cy := bird.pos.y * zoom + cam_y

		// Wing-tip vertical oscillation
		flap := math.sin(f.anim_time * constants.BIRD_FLAP_FREQ + bird.phase) * flap_amp

		// M-shape: two V strokes sharing a center point
		tip_l  := raylib.Vector2{cx - s,     cy + flap}
		tip_r  := raylib.Vector2{cx + s,     cy + flap}
		mid_l  := raylib.Vector2{cx - s*0.5, cy + flap*0.4}
		mid_r  := raylib.Vector2{cx + s*0.5, cy + flap*0.4}
		center := raylib.Vector2{cx, cy}

		thick := f32(1.5) * zoom
		raylib.DrawLineEx(tip_l, mid_l, thick, c)
		raylib.DrawLineEx(mid_l, center, thick, c)
		raylib.DrawLineEx(center, mid_r, thick, c)
		raylib.DrawLineEx(mid_r, tip_r, thick, c)
	}
}

// =============================================================================
// Water lily (nenúfar) — planta sobre tile de agua
// =============================================================================

render_water_lily :: proc(x, y, cs: f32, row, col: i32) {
	seed := hash_position(row, col)
	rng :: proc(s: ^u32) -> f32 {
		s^ = s^ * 1664525 + 1013904223
		return f32(s^ & 0xFFFF) / f32(0xFFFF)
	}

	// 2-4 lily pads
	pad_count := 2 + i32(hash_random(row, col, 0) * 3)  // 2..4
	for i in 0 ..< pad_count {
		s := seed + u32(i) * 97
		px := x + rng(&s) * cs * 0.70 + cs * 0.15
		py := y + rng(&s) * cs * 0.70 + cs * 0.15
		pr := cs * (0.14 + rng(&s) * 0.10)  // radius 0.14..0.24 of cs

		// Pad shadow
		raylib.DrawCircle(i32(px + 1), i32(py + 1), pr, raylib.Color{0, 0, 0, 40})
		// Pad fill — verde oscuro
		raylib.DrawCircle(i32(px), i32(py), pr, raylib.Color{40, 110, 50, 230})
		// Pad highlight — borde más claro
		raylib.DrawCircleLines(i32(px), i32(py), pr, raylib.Color{70, 150, 70, 160})

		// 50% chance of a small pink flower on this pad
		if rng(&s) > 0.5 {
			fr := cs * (0.025 + rng(&s) * 0.035)  // petal radius 0.025..0.06 of cs
			fc := raylib.Color{255, 150, 190, 240}  // rosa
			yc := raylib.Color{255, 230, 80, 255}   // amarillo centro
			// 5 petals around center
			for p in 0 ..< 5 {
				a := f32(p) * 1.2566  // 2π/5
				fpx := px + math.cos(a) * fr * 1.6
				fpy := py + math.sin(a) * fr * 1.6
				raylib.DrawCircle(i32(fpx), i32(fpy), fr, fc)
			}
			// Yellow center
			raylib.DrawCircle(i32(px), i32(py), fr * 0.6, yc)
		}
	}
}

// =============================================================================
// Airdrop rendering
// =============================================================================

render_airdrops :: proc(app: ^entities.App_State) {
	if app.state != .PLAYING && app.state != .PAUSED { return }

	cs := f32(app.settings.cell_size) * app.zoom
	ox := f32(app.camera_offset_x)
	oy := f32(app.camera_offset_y)

	for &drop in app.sim.airdrops {

		// ── Estela jet (solo mientras el avión está volando) ─────────────────
		if drop.phase == .PLANE_FLYING && drop.trail_len > 1 {
			for i in 1 ..< int(drop.trail_len) {
				// Índices en el ring buffer: más antiguo = trail_head
				i0 := (int(drop.trail_head) + i - 1) % len(drop.trail)
				i1 := (int(drop.trail_head) + i    ) % len(drop.trail)
				p0 := drop.trail[i0]
				p1 := drop.trail[i1]
				// Alpha crece de 0 (punta vieja) a 180 (punta reciente)
				alpha := u8(f32(i) / f32(drop.trail_len) * 180)
				s0 := raylib.Vector2{p0.x * app.zoom + ox, p0.y * app.zoom + oy}
				s1 := raylib.Vector2{p1.x * app.zoom + ox, p1.y * app.zoom + oy}
				thick := max(f32(1), app.zoom * 1.5)
				raylib.DrawLineEx(s0, s1, thick, raylib.Color{255, 255, 255, alpha})
			}
		}

		switch drop.phase {

		case .PLANE_FLYING:
			// Solo dibujar si el avión aún está visible (no marcado como salido)
			if drop.plane_x < -9000 { break }

			angle := math.atan2_f32(drop.plane_dir_y, drop.plane_dir_x)
			cos_a := math.cos_f32(angle)
			sin_a := math.sin_f32(angle)

			// Helper: convierte coordenadas locales (en world units) a screen
			// lx = eje adelante/atrás, ly = eje izquierda/derecha
			to_s :: #force_inline proc(pwx, pwy, lx, ly, cos_a, sin_a: f32,
			                           zoom, ox, oy: f32) -> raylib.Vector2 {
				wx := pwx + lx*cos_a - ly*sin_a
				wy := pwy + lx*sin_a + ly*cos_a
				return {wx*zoom + ox, wy*zoom + oy}
			}
			pwx := drop.plane_x
			pwy := drop.plane_y
			z   := app.zoom

			// ── Ala delta (triángulo: punta al frente, borde trasero ancho) ────
			//   Nose:    lx=+14,  ly=0
			//   L-trail: lx=-7,   ly=-11
			//   R-trail: lx=-7,   ly=+11
			v_nose  := to_s(pwx, pwy,  14,   0, cos_a, sin_a, z, ox, oy)
			v_left  := to_s(pwx, pwy,  -7, -11, cos_a, sin_a, z, ox, oy)
			v_right := to_s(pwx, pwy,  -7,  11, cos_a, sin_a, z, ox, oy)
			// Raylib DrawTriangle: CCW en screen (y↓)
			raylib.DrawTriangle(v_nose, v_right, v_left, constants.COLOR_AIRDROP_PLANE)

			// ── Fuselaje (franja central estrecha) ─────────────────────────────
			ang_deg := angle * (180.0 / math.PI)
			body_w  := f32(28) * z
			body_h  := f32(4)  * z
			raylib.DrawRectanglePro(
				{drop.plane_x*z + ox, drop.plane_y*z + oy, body_w, body_h},
				{body_w / 2, body_h / 2},
				ang_deg,
				raylib.Color{220, 220, 230, 255},
			)

			// ── Dos motores (pequeños rectángulos en el borde trasero del ala) ─
			eng_w := f32(7) * z
			eng_h := f32(3) * z
			sides := [2]f32{-7.5, 7.5}
			for side in sides {
				// Centro del motor en world space
				ecx := pwx + (-5)*cos_a - side*sin_a
				ecy := pwy + (-5)*sin_a + side*cos_a
				raylib.DrawRectanglePro(
					{ecx*z + ox, ecy*z + oy, eng_w, eng_h},
					{eng_w / 2, eng_h / 2},
					ang_deg,
					raylib.Color{80, 80, 100, 255},
				)
				// Llama del motor (pequeño círculo naranja en la tobera)
				nozzle_cx := pwx + (-9)*cos_a - side*sin_a
				nozzle_cy := pwy + (-9)*sin_a + side*cos_a
				raylib.DrawCircleV(
					{nozzle_cx*z + ox, nozzle_cy*z + oy},
					f32(2.5) * z,
					raylib.Color{255, 140, 40, 200},
				)
			}

		case .BOX_FALLING:
			// Paracaídas: círculo encogiendo en el tile destino
			sx := drop.target_wx * app.zoom + ox
			sy := drop.target_wy * app.zoom + oy

			radius := drop.chute_t * constants.AIRDROP_CHUTE_RADIUS_MAX * cs
			if radius >= 1 {
				raylib.DrawCircleV({sx, sy}, radius, constants.COLOR_AIRDROP_CHUTE)
				raylib.DrawCircleLinesV({sx, sy}, radius, raylib.Color{200, 200, 200, 255})
			}

		case .BOX_LANDED:
			sx  := drop.target_wx * app.zoom + ox
			sy  := drop.target_wy * app.zoom + oy
			sz  := cs * 0.66
			bx  := sx - sz / 2
			by_ := sy - sz / 2

			// Colores del crate (wood + metal)
			COL_SHADOW  :: raylib.Color{18, 10, 4, 70}
			COL_WOOD    :: raylib.Color{178, 136, 68, 255}  // tablas principales
			COL_WOOD_LT :: raylib.Color{202, 162, 90, 255}  // tabla superior iluminada
			COL_GAP     :: raylib.Color{138, 100, 42, 255}  // ranuras entre tablas
			COL_METAL   :: raylib.Color{102, 82, 56, 255}   // correa + soportes de esquina

			soff    := max(f32(1.5), cs * 0.06)
			rnd     := f32(0.12)
			seg     := i32(4)
			plank_h := sz / 3

			// 1. Sombra
			raylib.DrawRectangleRounded({bx + soff, by_ + soff, sz, sz}, rnd, seg, COL_SHADOW)

			// 2. Cuerpo principal (madera)
			raylib.DrawRectangleRounded({bx, by_, sz, sz}, rnd, seg, COL_WOOD)

			// 3. Tabla superior más iluminada
			raylib.DrawRectangleRec({bx + sz*0.06, by_, sz*0.88, plank_h}, COL_WOOD_LT)

			// 4. Ranuras entre tablas (x2)
			gap_h := max(f32(1), sz * 0.035)
			raylib.DrawRectangleRec({bx + sz*0.06, by_ + plank_h - gap_h*0.5, sz*0.88, gap_h}, COL_GAP)
			raylib.DrawRectangleRec({bx + sz*0.06, by_ + 2*plank_h - gap_h*0.5, sz*0.88, gap_h}, COL_GAP)

			// 5. Tablas cruzadas (X) sobre la cara frontal
			COL_BOARD :: raylib.Color{152, 112, 48, 255}
			board_w   := max(f32(2), sz * 0.11)
			board_l   := sz * 1.36   // ligeramente mayor que la diagonal para llegar a esquinas
			raylib.DrawRectanglePro(
				{sx, sy, board_l, board_w},
				{board_l * 0.5, board_w * 0.5},
				45,
				COL_BOARD,
			)
			raylib.DrawRectanglePro(
				{sx, sy, board_l, board_w},
				{board_l * 0.5, board_w * 0.5},
				-45,
				COL_BOARD,
			)

			// 6. Correa metálica horizontal al centro
			strap_h := max(f32(2), sz * 0.08)
			raylib.DrawRectangleRec({bx, sy - strap_h*0.5, sz, strap_h}, COL_METAL)

			// 7. Soportes de esquina (4 cuadrados en vértices)
			bkt     := sz * 0.14
			bkt_pad := sz * 0.02
			raylib.DrawRectangleRec({bx + bkt_pad,          by_ + bkt_pad,          bkt, bkt}, COL_METAL)
			raylib.DrawRectangleRec({bx + sz - bkt - bkt_pad, by_ + bkt_pad,          bkt, bkt}, COL_METAL)
			raylib.DrawRectangleRec({bx + bkt_pad,          by_ + sz - bkt - bkt_pad, bkt, bkt}, COL_METAL)
			raylib.DrawRectangleRec({bx + sz - bkt - bkt_pad, by_ + sz - bkt - bkt_pad, bkt, bkt}, COL_METAL)
		}

		// ── Ping convergente (siempre visible en pantalla) ─────────────────
		if (drop.phase == .BOX_FALLING || drop.phase == .BOX_LANDED) && drop.ping_t > 0 {
			raw_sx := drop.target_wx * app.zoom + ox
			raw_sy := drop.target_wy * app.zoom + oy
			sw_f   := f32(raylib.GetScreenWidth())
			sh_f   := f32(raylib.GetScreenHeight())

			// Clampear al área visible para que el círculo siempre se vea
			CLAMP_PAD :: f32(30)
			ping_sx := clamp(raw_sx, CLAMP_PAD, sw_f - CLAMP_PAD)
			ping_sy := clamp(raw_sy, CLAMP_PAD, sh_f - CLAMP_PAD)

			radius     := drop.ping_t * constants.AIRDROP_PING_RADIUS * cs
			ping_alpha := u8(drop.ping_t * 220)
			ping_col   := constants.COLOR_AIRDROP_PING
			ping_col.a  = ping_alpha
			if radius > 0.5 {
				raylib.DrawCircleLinesV({ping_sx, ping_sy}, radius, ping_col)
			}
		}

		// ── Indicador de borde cuando la caja está fuera de pantalla ─────────
		if drop.phase == .BOX_FALLING || drop.phase == .BOX_LANDED {
			sx := drop.target_wx * app.zoom + ox
			sy := drop.target_wy * app.zoom + oy
			sw := f32(raylib.GetScreenWidth())
			sh := f32(raylib.GetScreenHeight())
			PAD :: f32(20)  // distancia desde el borde de pantalla

			on_screen := sx >= 0 && sx <= sw && sy >= 0 && sy <= sh
			if !on_screen {
				// Dirección desde el centro de la pantalla hacia la caja
				cx := sw / 2
				cy := sh / 2
				dx := sx - cx
				dy := sy - cy
				len := math.sqrt_f32(dx*dx + dy*dy)
				if len < 0.001 { break }
				ndx := dx / len
				ndy := dy / len

				// Intersección con el borde de pantalla (con padding)
				t_left   := (-PAD - cx)    / ndx if ndx < -0.001 else f32(1e9)
				t_right  := (sw+PAD - cx)  / ndx if ndx >  0.001 else f32(1e9)
				t_top    := (-PAD - cy)    / ndy if ndy < -0.001 else f32(1e9)
				t_bottom := (sh+PAD - cy)  / ndy if ndy >  0.001 else f32(1e9)

				t_hit := min(
					min(t_left  if t_left  > 0 else f32(1e9), t_right  if t_right  > 0 else f32(1e9)),
					min(t_top   if t_top   > 0 else f32(1e9), t_bottom if t_bottom > 0 else f32(1e9)),
				)
				// Clamp al área visible con margen interno
				INNER :: f32(16)
				ix := clamp(cx + ndx * t_hit, INNER, sw - INNER)
				iy := clamp(cy + ndy * t_hit, INNER, sh - INNER)

				// Triángulo apuntando hacia la caja (punta en ix,iy; base perpendicular)
				TSIZE :: f32(20)
				px_perp := -ndy  // perpendicular al vector dirección
				py_perp :=  ndx
				tip  := raylib.Vector2{ix,                    iy                   }
				bl   := raylib.Vector2{ix - ndx*TSIZE + px_perp*TSIZE*0.6,
				                       iy - ndy*TSIZE + py_perp*TSIZE*0.6}
				br   := raylib.Vector2{ix - ndx*TSIZE - px_perp*TSIZE*0.6,
				                       iy - ndy*TSIZE - py_perp*TSIZE*0.6}

				raylib.DrawTriangle(tip, bl, br, constants.COLOR_AIRDROP_PING)
				// Outline más grueso: dibujar 3 líneas
				out_col := raylib.Color{200, 160, 20, 255}
				raylib.DrawLineEx(tip, bl,  3, out_col)
				raylib.DrawLineEx(bl,  br,  3, out_col)
				raylib.DrawLineEx(br,  tip, 3, out_col)
			}
		}
	}
}

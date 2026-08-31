package systems

import "../constants"
import "../entities"
import "core:fmt"
import "core:math"
import "core:math/linalg"
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

// ── Pause "glass" blur (vidrio esmerilado sobre el mundo congelado) ─────────
//
// capture_tex: el mundo se renderiza acá en vez de a pantalla mientras
// app.state == .PAUSED (ver render_game). blur_tex: buffer intermedio para
// la pasada horizontal antes de la vertical (que se dibuja directo a
// pantalla). Se re-hace todo el trabajo cada frame en vez de cachear un
// solo capture — el mundo está congelado (simulation_update no corre en
// pausa) así que el resultado es idéntico frame a frame, pero cachear
// traería complejidad de invalidación (resize de ventana, etc.) sin
// beneficio real: redirigir el render normal a una textura + 2 blur passes
// no es más caro que ya lo que se dibuja hoy en pantalla.
Pause_Blur :: struct {
	shader:        raylib.Shader,
	loc_texel:     i32,
	loc_direction: i32,
	capture_tex:   raylib.RenderTexture2D,
	blur_tex:      raylib.RenderTexture2D,
	tex_w:         i32,
	tex_h:         i32,
}

pause_blur: Pause_Blur

pause_blur_init :: proc() {
	s := raylib.LoadShader(nil, "assets/blur.glsl")
	pause_blur.shader        = s
	pause_blur.loc_texel     = raylib.GetShaderLocation(s, "texelSize")
	pause_blur.loc_direction = raylib.GetShaderLocation(s, "direction")
	pause_blur_resize()
}

pause_blur_resize :: proc() {
	w := raylib.GetRenderWidth()
	h := raylib.GetRenderHeight()
	if pause_blur.tex_w == w && pause_blur.tex_h == h { return }
	if pause_blur.tex_w > 0 {
		raylib.UnloadRenderTexture(pause_blur.capture_tex)
		raylib.UnloadRenderTexture(pause_blur.blur_tex)
	}
	pause_blur.capture_tex = raylib.LoadRenderTexture(w, h)
	pause_blur.blur_tex    = raylib.LoadRenderTexture(w, h)
	pause_blur.tex_w       = w
	pause_blur.tex_h       = h
}

pause_blur_unload :: proc() {
	raylib.UnloadShader(pause_blur.shader)
	if pause_blur.tex_w > 0 {
		raylib.UnloadRenderTexture(pause_blur.capture_tex)
		raylib.UnloadRenderTexture(pause_blur.blur_tex)
	}
}

// Aplica el blur de 2 pasadas (horizontal → blur_tex, vertical → target
// activo, que en el caso de uso real es la pantalla) sobre capture_tex, y
// encima un tinte oscuro semitransparente ("vidrio esmerilado").
// Debe llamarse FUERA de cualquier BeginTextureMode activo (la pasada 2
// dibuja directo al render target que esté activo en ese momento).
pause_blur_draw :: proc() {
	texel_size := [2]f32{
		constants.PAUSE_BLUR_SPREAD / f32(pause_blur.tex_w),
		constants.PAUSE_BLUR_SPREAD / f32(pause_blur.tex_h),
	}
	raylib.SetShaderValue(pause_blur.shader, pause_blur.loc_texel, &texel_size, .VEC2)

	src := raylib.Rectangle{0, f32(pause_blur.tex_h), f32(pause_blur.tex_w), -f32(pause_blur.tex_h)}

	// Pasada 1: horizontal, capture_tex → blur_tex
	dir_h := [2]f32{1, 0}
	raylib.SetShaderValue(pause_blur.shader, pause_blur.loc_direction, &dir_h, .VEC2)
	raylib.BeginTextureMode(pause_blur.blur_tex)
	raylib.BeginShaderMode(pause_blur.shader)
	raylib.DrawTextureRec(pause_blur.capture_tex.texture, src, {0, 0}, raylib.WHITE)
	raylib.EndShaderMode()
	raylib.EndTextureMode()

	// Pasada 2: vertical, blur_tex → target activo (pantalla)
	dir_v := [2]f32{0, 1}
	raylib.SetShaderValue(pause_blur.shader, pause_blur.loc_direction, &dir_v, .VEC2)
	raylib.BeginShaderMode(pause_blur.shader)
	raylib.DrawTextureRec(pause_blur.blur_tex.texture, src, {0, 0}, raylib.WHITE)
	raylib.EndShaderMode()

	// Tinte de vidrio — oscurece/opaca un poco encima del blur
	raylib.DrawRectangle(0, 0, pause_blur.tex_w, pause_blur.tex_h, constants.PAUSE_GLASS_TINT)
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

// ── Mapa 3D (Camera3D fija-isométrica) ──────────────────────────────────────
// Ver 3D_RENDER_PLAN.md.

// Construye una Camera3D a partir de un foco (punto de mundo mirado) y un
// zoom, con el ángulo de inclinación fijo (CAMERA_PITCH_DEG) — no rota nunca,
// solo "top-down inclinado". zoom alto = cámara más cerca (ver
// constants.camera_distance_from_zoom).
camera3d_for_focus :: proc(focus: raylib.Vector3, zoom: f32) -> raylib.Camera3D {
	pitch_rad := constants.CAMERA_PITCH_DEG * math.RAD_PER_DEG
	dist := constants.camera_distance_from_zoom(zoom)
	offset := raylib.Vector3{
		0,
		dist * math.sin(pitch_rad),
		dist * math.cos(pitch_rad),
	}
	return raylib.Camera3D{
		position   = focus + offset,
		target     = focus,
		up         = {0, 1, 0},
		fovy       = constants.CAMERA_FOVY,
		projection = .PERSPECTIVE,
	}
}

// Deriva app.camera3d a partir del estado actual de app.camera_focus/zoom —
// llamar una vez por frame antes de dibujar/pickear el mundo 3D.
update_camera3d :: proc(app: ^entities.App_State) {
	app.camera3d = camera3d_for_focus(app.camera_focus, app.zoom)
}

// ── Iluminación 3D (shader real con normales) ───────────────────────────────
// Sol direccional fijo + relleno tenue + ambient, sin especular ni sombras
// proyectadas — "simple" a propósito. Ver 3D_RENDER_PLAN.md.
//
// Nota de diseño: el vertex shader NO usa matModel/matNormal — toda la
// geometría 3D de este proyecto (malla de terreno y formas inmediatas de
// torres/enemigos/etc) ya se construye en coordenadas de mundo absolutas, sin
// pasar por la pila de transformación de rlgl, así que vertexPosition/
// vertexNormal ya son world-space tal cual llegan.
Lighting_Shader :: struct {
	shader:          raylib.Shader,
	loc_sun_dir:     i32,
	loc_sun_color:   i32,
	loc_fill_dir:    i32,
	loc_fill_color:  i32,
	loc_ambient:     i32,
	loc_use_mask:    i32,  // 1.0 solo mientras se dibuja el terreno (ver render_map_3d)
	loc_path_color:  i32,
	loc_water_color:      i32,
	loc_water_edge_color: i32,
	loc_dune_seed:    i32,
	loc_dune_time:    i32,
	loc_dune_alpha:   i32,
	loc_dune_density: i32,
	loc_dune_color:   i32,
	loc_map_size:     i32,
	loc_caustics_time: i32,
	loc_grass_time:    i32,
	loc_grass_alpha:   i32,
	loc_grass_density: i32,
	loc_grass_color:   i32,
	loc_rock_seed:     i32,
	loc_rock_alpha:    i32,
	loc_rock_density:  i32,
	loc_rock_color:    i32,
	dune_anim_time:     f32,  // acumulado con dt clampeado, no reloj de pared — ver render_map_3d
	caustics_anim_time: f32,
	grass_anim_time:    f32,
}

lighting_shader: Lighting_Shader

lighting_shader_init :: proc() {
	s := raylib.LoadShader("assets/lighting.vs", "assets/lighting.fs")
	lighting_shader = Lighting_Shader{
		shader           = s,
		loc_sun_dir      = raylib.GetShaderLocation(s, "sunDir"),
		loc_sun_color    = raylib.GetShaderLocation(s, "sunColor"),
		loc_fill_dir     = raylib.GetShaderLocation(s, "fillDir"),
		loc_fill_color   = raylib.GetShaderLocation(s, "fillColor"),
		loc_ambient      = raylib.GetShaderLocation(s, "ambient"),
		loc_use_mask     = raylib.GetShaderLocation(s, "useTerrainMask"),
		loc_path_color   = raylib.GetShaderLocation(s, "pathColor"),
		loc_water_color      = raylib.GetShaderLocation(s, "waterColor"),
		loc_water_edge_color = raylib.GetShaderLocation(s, "waterEdgeColor"),
		loc_dune_seed    = raylib.GetShaderLocation(s, "duneSeed"),
		loc_dune_time    = raylib.GetShaderLocation(s, "duneTime"),
		loc_dune_alpha   = raylib.GetShaderLocation(s, "duneAlpha"),
		loc_dune_density = raylib.GetShaderLocation(s, "duneDensity"),
		loc_dune_color   = raylib.GetShaderLocation(s, "duneColor"),
		loc_map_size     = raylib.GetShaderLocation(s, "mapSize"),
		loc_caustics_time = raylib.GetShaderLocation(s, "causticsTime"),
		loc_grass_time    = raylib.GetShaderLocation(s, "grassTime"),
		loc_grass_alpha   = raylib.GetShaderLocation(s, "grassAlpha"),
		loc_grass_density = raylib.GetShaderLocation(s, "grassDensity"),
		loc_grass_color   = raylib.GetShaderLocation(s, "grassColor"),
		loc_rock_seed     = raylib.GetShaderLocation(s, "rockSeed"),
		loc_rock_alpha    = raylib.GetShaderLocation(s, "rockAlpha"),
		loc_rock_density  = raylib.GetShaderLocation(s, "rockDensity"),
		loc_rock_color    = raylib.GetShaderLocation(s, "rockColor"),
	}

	// Luz "sol" alineada con el ángulo de la cámara isométrica (arriba-
	// adelante), luz de relleno tenue del lado opuesto para que las caras en
	// sombra no queden negro puro. Direccionales, fijas — no cambian en
	// runtime.
	// Intensidades pensadas para que ambient + sol + relleno sumen ~1.0 en la
	// cara mejor iluminada (el techo del terreno, que mira casi derecho al
	// sol) — antes sumaban >1.3 y saturaban a blanco, tapando el color de
	// bioma por completo sin importar cuál estuviera activo.
	sun_dir := linalg.normalize(raylib.Vector3{0.45, 1.0, 0.3})
	sun_color := raylib.Vector3{0.55, 0.53, 0.48}
	fill_dir := linalg.normalize(raylib.Vector3{-0.35, 0.4, -0.5})
	fill_color := raylib.Vector3{0.12, 0.14, 0.18}
	ambient := raylib.Vector3{0.45, 0.45, 0.5}

	raylib.SetShaderValue(s, lighting_shader.loc_sun_dir, &sun_dir, .VEC3)
	raylib.SetShaderValue(s, lighting_shader.loc_sun_color, &sun_color, .VEC3)
	raylib.SetShaderValue(s, lighting_shader.loc_fill_dir, &fill_dir, .VEC3)
	raylib.SetShaderValue(s, lighting_shader.loc_fill_color, &fill_color, .VEC3)
	raylib.SetShaderValue(s, lighting_shader.loc_ambient, &ambient, .VEC3)

	// Color de agua fijo (no depende del bioma, a diferencia de pathColor)
	// — se setea una sola vez acá en vez de en terrain_cache_ensure.
	wc := constants.COLOR_WATER
	ec := constants.COLOR_WATER_EDGE
	water_color := raylib.Vector3{f32(wc.r) / 255, f32(wc.g) / 255, f32(wc.b) / 255}
	water_edge_color := raylib.Vector3{f32(ec.r) / 255, f32(ec.g) / 255, f32(ec.b) / 255}
	raylib.SetShaderValue(s, lighting_shader.loc_water_color, &water_color, .VEC3)
	raylib.SetShaderValue(s, lighting_shader.loc_water_edge_color, &water_edge_color, .VEC3)

	// Apagado por defecto — solo el draw del terreno lo prende (ver
	// render_map_3d). Formas inmediatas (torres/enemigos/...) que comparten
	// este shader vía BeginShaderMode nunca deben mezclar color de camino.
	use_mask_off := f32(0)
	raylib.SetShaderValue(s, lighting_shader.loc_use_mask, &use_mask_off, .FLOAT)
}

lighting_shader_unload :: proc() {
	raylib.UnloadShader(lighting_shader.shader)
}

// ── Malla cacheada del terreno (plano continuo, desniveles diagonales) ─────
// Se construye una sola vez por run (invalidada en simulation_fit_camera):
// una grilla de (width+1)×(height+1) vértices — un vértice por esquina
// compartida entre hasta 4 tiles — en vez de una caja por tile. La diagonal
// del desnivel sale sola: si dos tiles vecinos tienen distinta altura, la
// arista que comparten interpola linealmente entre ambas.
//
// El color de camino se resuelve aparte, con una textura-máscara (1 texel
// por tile, filtro POINT = bordes nítidos) sampleada en el fragment shader
// — así el límite del camino queda nítido pese a que la malla es continua
// (si fuera solo color de vértice, se difuminaría en cada arista
// compartida). "Área construible" y "no-camino" son el mismo dato en este
// juego (todo lo que no es camino se puede construir), así que una sola
// máscara alcanza para las dos cosas que pedía el usuario.
Terrain_Cache :: struct {
	model:          raylib.Model,
	path_mask_tex:  raylib.Texture2D,
	water_mask_tex: raylib.Texture2D,
	valid:          bool,
}

terrain_cache: Terrain_Cache

terrain_cache_invalidate :: proc() {
	if terrain_cache.valid {
		raylib.UnloadModel(terrain_cache.model)
		raylib.UnloadTexture(terrain_cache.path_mask_tex)
		raylib.UnloadTexture(terrain_cache.water_mask_tex)
		terrain_cache.valid = false
	}
}

_terrain_push_vertex :: proc(positions, normals, texcoords: ^[dynamic]f32, colors: ^[dynamic]u8, p, n: raylib.Vector3, uv: raylib.Vector2, c: raylib.Color) {
	append(positions, p.x, p.y, p.z)
	append(normals, n.x, n.y, n.z)
	append(texcoords, uv.x, uv.y)
	append(colors, c.r, c.g, c.b, c.a)
}

// Un triángulo con normal plana (calculada del propio triángulo — look
// "low-poly", coherente con caras diagonales de distinta inclinación).
// Winding CCW visto desde arriba (+Y) — ver comentario de _terrain_corner
// más abajo para el orden de los 3 vértices que hay que pasar.
_terrain_push_tri :: proc(
	positions, normals, texcoords: ^[dynamic]f32, colors: ^[dynamic]u8,
	v0, v1, v2: raylib.Vector3, uv0, uv1, uv2: raylib.Vector2, c0, c1, c2: raylib.Color,
) {
	n := linalg.normalize(linalg.cross(v1 - v0, v2 - v0))
	if n.y < 0 { n = -n }  // seguro — no debería pasar con las pendientes suaves de este mapa
	_terrain_push_vertex(positions, normals, texcoords, colors, v0, n, uv0, c0)
	_terrain_push_vertex(positions, normals, texcoords, colors, v1, n, uv1, c1)
	_terrain_push_vertex(positions, normals, texcoords, colors, v2, n, uv2, c2)
}

// Altura y color "de terreno" (sin camino, eso lo resuelve el shader) de un
// tile — el agua es plana a WORLD_WATER_HEIGHT, el resto sigue el heightmap.
_terrain_tile_height_color :: proc(m: ^entities.Map, row, col: i32, biome_colors: constants.Biome_Colors) -> (h: f32, color: raylib.Color) {
	if m.water_grid[row][col] {
		return constants.WORLD_WATER_HEIGHT, constants.COLOR_WATER
	}
	return m.heightmap[row][col] * constants.WORLD_HEIGHT_SCALE, biome_colors.bg_grid
}

// Altura/color de una esquina de grilla (r,c en [0,height]×[0,width]) —
// promedio de los hasta 4 tiles que la tocan. Esto es lo que produce el
// desnivel diagonal: dos tiles vecinos con distinta altura comparten esta
// esquina, así que la arista entre ellos interpola en vez de cortar en
// escalón.
_terrain_corner :: proc(m: ^entities.Map, r, c: i32, biome_colors: constants.Biome_Colors) -> (h: f32, color: [3]f32) {
	sum_h := f32(0)
	sum_c := [3]f32{0, 0, 0}
	n := f32(0)
	for dr in -1 ..= 0 {
		for dc in -1 ..= 0 {
			tr, tc := r + i32(dr), c + i32(dc)
			if tr < 0 || tr >= m.height || tc < 0 || tc >= m.width { continue }
			th, tcol := _terrain_tile_height_color(m, tr, tc, biome_colors)
			sum_h += th
			sum_c += [3]f32{f32(tcol.r), f32(tcol.g), f32(tcol.b)}
			n += 1
		}
	}
	if n == 0 { return 0, {0, 0, 0} }
	return sum_h / n, sum_c / n
}

terrain_cache_ensure :: proc(m: ^entities.Map) {
	if terrain_cache.valid { return }

	positions := make([dynamic]f32)
	normals := make([dynamic]f32)
	texcoords := make([dynamic]f32)
	colors := make([dynamic]u8)
	defer delete(positions)
	defer delete(normals)
	defer delete(texcoords)
	defer delete(colors)

	biome_colors := constants.BIOME_COLORS[m.biome]
	cs := constants.WORLD_CELL_SIZE

	// world_corner: posición de mundo (X,Z) + altura promediada de la
	// esquina de grilla (r,c). uv mapea 1:1 a la textura-máscara del camino.
	world_corner :: proc(m: ^entities.Map, r, c: i32, biome_colors: constants.Biome_Colors, cs: f32) -> (pos: raylib.Vector3, uv: raylib.Vector2, color: raylib.Color) {
		h, col3 := _terrain_corner(m, r, c, biome_colors)
		pos = {f32(c) * cs, h, f32(r) * cs}
		uv = {f32(c) / f32(m.width), f32(r) / f32(m.height)}
		color = raylib.Color{u8(col3.r), u8(col3.g), u8(col3.b), 255}
		return
	}

	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			p_tl, uv_tl, c_tl := world_corner(m, row, col, biome_colors, cs)
			p_tr, uv_tr, c_tr := world_corner(m, row, col + 1, biome_colors, cs)
			p_bl, uv_bl, c_bl := world_corner(m, row + 1, col, biome_colors, cs)
			p_br, uv_br, c_br := world_corner(m, row + 1, col + 1, biome_colors, cs)

			// 2 triángulos por tile, CCW visto desde +Y en ambos.
			_terrain_push_tri(&positions, &normals, &texcoords, &colors, p_tl, p_bl, p_tr, uv_tl, uv_bl, uv_tr, c_tl, c_bl, c_tr)
			_terrain_push_tri(&positions, &normals, &texcoords, &colors, p_tr, p_bl, p_br, uv_tr, uv_bl, uv_br, c_tr, c_bl, c_br)
		}
	}

	mesh: raylib.Mesh
	mesh.vertexCount = i32(len(positions) / 3)
	mesh.triangleCount = i32(len(positions) / 3 / 3)
	mesh.vertices = ([^]f32)(raw_data(positions[:]))
	mesh.normals = ([^]f32)(raw_data(normals[:]))
	mesh.texcoords = ([^]f32)(raw_data(texcoords[:]))
	mesh.colors = ([^]u8)(raw_data(colors[:]))

	raylib.UploadMesh(&mesh, false)

	// Ya subida a GPU — no hace falta conservar los punteros CPU. Los
	// dejamos en nil para que un futuro UnloadModel/UnloadMesh no intente
	// liberar memoria alojada por Odin (los `defer delete(...)` de arriba
	// son la única vía de liberación de estos arrays).
	mesh.vertices = nil
	mesh.normals = nil
	mesh.texcoords = nil
	mesh.colors = nil

	model := raylib.LoadModelFromMesh(mesh)
	model.materials[0].shader = lighting_shader.shader

	// Textura-máscara de camino: 1 texel por tile, R8, POINT filter (sin
	// blur — el límite del camino tiene que quedar nítido). 255 = tile de
	// camino, 0 = resto del mapa (agua incluida — el agua ya tiene su color
	// propio vía vertex color, la máscara no la toca).
	mask_pixels := make([]u8, int(m.width) * int(m.height))
	defer delete(mask_pixels)
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			v: u8 = 255 if m.grid[row][col] == .PATH else 0
			mask_pixels[row * m.width + col] = v
		}
	}
	mask_img := raylib.Image{
		data    = raw_data(mask_pixels),
		width   = m.width,
		height  = m.height,
		mipmaps = 1,
		format  = .UNCOMPRESSED_GRAYSCALE,
	}
	mask_tex := raylib.LoadTextureFromImage(mask_img)
	raylib.SetTextureFilter(mask_tex, .POINT)
	raylib.SetTextureWrap(mask_tex, .CLAMP)
	model.materials[0].maps[raylib.MaterialMapIndex.ALBEDO].texture = mask_tex

	// Textura-máscara de agua — mismo esquema que la de camino, en el
	// segundo slot de material (texture1 para el shader). Sirve para que el
	// overlay de dunas no pinte encima del agua (ver duneOverlay en
	// lighting.fs), igual que en la versión 2D (dune se dibuja antes que
	// water/path, así que esos tiles tapan la duna).
	water_pixels := make([]u8, int(m.width) * int(m.height))
	defer delete(water_pixels)
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			water_pixels[row * m.width + col] = 255 if m.water_grid[row][col] else 0
		}
	}
	water_img := raylib.Image{
		data    = raw_data(water_pixels),
		width   = m.width,
		height  = m.height,
		mipmaps = 1,
		format  = .UNCOMPRESSED_GRAYSCALE,
	}
	water_tex := raylib.LoadTextureFromImage(water_img)
	raylib.SetTextureFilter(water_tex, .POINT)
	raylib.SetTextureWrap(water_tex, .CLAMP)
	model.materials[0].maps[raylib.MaterialMapIndex.METALNESS].texture = water_tex

	path_color := raylib.Vector3{f32(biome_colors.path.r) / 255, f32(biome_colors.path.g) / 255, f32(biome_colors.path.b) / 255}
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_path_color, &path_color, .VEC3)

	// Dunas (bioma DESERT) — adaptado de assets/dune.glsl. alpha=0 en
	// cualquier otro bioma (BIOME_DUNE_STYLES), así que el resto de los
	// mapas no paga ni el costo de la rama en el shader (duneAlpha <= 0.001
	// la saltea, ver lighting.fs).
	dune_style := constants.BIOME_DUNE_STYLES[m.biome]
	dune_seed := f32(m.seed)
	dune_alpha := dune_style.alpha
	dune_density := dune_style.density
	dune_color := raylib.Vector3{dune_style.dune_color[0], dune_style.dune_color[1], dune_style.dune_color[2]}
	map_size := raylib.Vector2{f32(m.width), f32(m.height)}
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_dune_seed, &dune_seed, .FLOAT)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_dune_alpha, &dune_alpha, .FLOAT)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_dune_density, &dune_density, .FLOAT)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_dune_color, &dune_color, .VEC3)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_map_size, &map_size, .VEC2)
	lighting_shader.dune_anim_time = 0
	lighting_shader.caustics_anim_time = 0
	lighting_shader.grass_anim_time = 0

	// Pasto (biomas PLAIN/FOREST) — adaptado de assets/grass.glsl.
	grass_style := constants.BIOME_GRASS_STYLES[m.biome]
	grass_alpha := grass_style.alpha
	grass_density := grass_style.density
	grass_color := raylib.Vector3{grass_style.grass_color[0], grass_style.grass_color[1], grass_style.grass_color[2]}
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_grass_alpha, &grass_alpha, .FLOAT)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_grass_density, &grass_density, .FLOAT)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_grass_color, &grass_color, .VEC3)

	// Roca agrietada (bioma MOUNTAIN) — adaptado de assets/rock.glsl.
	rock_style := constants.BIOME_ROCK_STYLES[m.biome]
	rock_seed := f32(m.seed)
	rock_alpha := rock_style.alpha
	rock_density := rock_style.density
	rock_color := raylib.Vector3{rock_style.rock_color[0], rock_style.rock_color[1], rock_style.rock_color[2]}
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_rock_seed, &rock_seed, .FLOAT)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_rock_alpha, &rock_alpha, .FLOAT)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_rock_density, &rock_density, .FLOAT)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_rock_color, &rock_color, .VEC3)

	terrain_cache.model = model
	terrain_cache.path_mask_tex = mask_tex
	terrain_cache.water_mask_tex = water_tex
	terrain_cache.valid = true
}

// Terreno del mapa: malla continua cacheada (ver terrain_cache_ensure),
// desniveles diagonales reales, color de camino nítido vía textura-máscara,
// iluminada con Lighting_Shader. Reemplaza a render_map para los estados 3D.
render_map_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	terrain_cache_ensure(m)

	// Tiempo acumulado con dt clampeado (no reloj de pared) para animar
	// dunas/cáusticas/pasto — mismo patrón que Water_Shader.anim_time, ver
	// CLAUDE.md.
	frame_dt := min(raylib.GetFrameTime(), constants.WATER_ANIM_MAX_DT)
	lighting_shader.dune_anim_time += frame_dt * constants.DUNE_ANIM_SPEED
	lighting_shader.caustics_anim_time += frame_dt * constants.WATER_ANIM_SPEED
	lighting_shader.grass_anim_time += frame_dt * constants.GRASS_ANIM_SPEED
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_dune_time, &lighting_shader.dune_anim_time, .FLOAT)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_caustics_time, &lighting_shader.caustics_anim_time, .FLOAT)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_grass_time, &lighting_shader.grass_anim_time, .FLOAT)

	on := f32(1)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_use_mask, &on, .FLOAT)
	raylib.DrawModel(terrain_cache.model, {0, 0, 0}, 1.0, raylib.WHITE)
	off := f32(0)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_use_mask, &off, .FLOAT)
}

// Centro (X,Z) de un tile en unidades de mundo, y la altura de su superficie
// (Y) según el heightmap — para asentar objetos sobre el terreno voxel.
tile_world_top :: proc(m: ^entities.Map, row, col: i32) -> (center: raylib.Vector3, top_y: f32) {
	cs := constants.WORLD_CELL_SIZE
	top_y = m.heightmap[row][col] * constants.WORLD_HEIGHT_SCALE
	center = {f32(col) * cs + cs * 0.5, top_y, f32(row) * cs + cs * 0.5}
	return
}

// Cuerpo (cilindro) + cañón orientado por `angle` (mismo ángulo 2D que ya usa
// el juego: atan2(dz, dx) sobre el plano XZ) — usado tanto por torres reales
// como por el ghost de construcción. `alpha` permite semitransparencia (ghost).
draw_tower_shape_3d :: proc(base: raylib.Vector3, cs: f32, angle, recoil: f32, color: raylib.Color, alpha: u8 = 255) {
	c := color
	c.a = alpha
	body_r := cs * 0.32
	body_h := cs * 0.45
	raylib.DrawCylinder(base, body_r, body_r, body_h, 12, c)

	dir := raylib.Vector3{math.cos(angle), 0, math.sin(angle)}
	recoil_pull := recoil * cs * constants.TOWER_RECOIL_DISTANCE_RATIO
	barrel_len := cs * 0.5 - recoil_pull
	start := raylib.Vector3{base.x, base.y + body_h * 0.75, base.z}
	end := start + dir * barrel_len
	barrel := raylib.Color{40, 40, 40, alpha}
	raylib.DrawCylinderEx(start, end, cs * 0.08, cs * 0.06, 8, barrel)
}

render_tower_3d :: proc(tower: ^entities.Tower, m: ^entities.Map) {
	_, top_y := tile_world_top(m, tower.r, tower.c)
	cs := constants.WORLD_CELL_SIZE
	base := raylib.Vector3{f32(tower.c) * cs + cs * 0.5, top_y, f32(tower.r) * cs + cs * 0.5}
	color := constants.TOWER_SPECS[tower.type].color
	draw_tower_shape_3d(base, cs, tower.angle, tower.recoil, color)
}

render_spawn_3d :: proc(center: raylib.Vector3) {
	cs := constants.WORLD_CELL_SIZE
	pos := center
	raylib.DrawCylinder(pos, cs * 0.4, cs * 0.4, cs * 0.06, 16, constants.COLOR_SPAWN)
}

render_goal_3d :: proc(center: raylib.Vector3) {
	cs := constants.WORLD_CELL_SIZE
	pos := center
	raylib.DrawCylinder(pos, cs * 0.4, cs * 0.4, cs * 0.06, 16, constants.COLOR_GOAL)
}

render_tree_3d :: proc(center: raylib.Vector3, biome: constants.Biome) {
	cs := constants.WORLD_CELL_SIZE
	colors := constants.BIOME_TREE_COLORS[biome]
	trunk_h := cs * 0.3
	raylib.DrawCylinder(center, cs * 0.09, cs * 0.11, trunk_h, 8, colors.trunk)
	foliage_base := raylib.Vector3{center.x, center.y + trunk_h, center.z}
	raylib.DrawCylinder(foliage_base, cs * 0.34, 0, cs * 0.55, 10, colors.layer_mid)
}

render_block_3d :: proc(center: raylib.Vector3, biome: constants.Biome, level: i32) {
	cs := constants.WORLD_CELL_SIZE
	lvl := clamp(level, 1, 3)
	h := cs * (0.35 + f32(lvl - 1) * 0.15)
	color := constants.BIOME_TREE_COLORS[biome].trunk
	pos := raylib.Vector3{center.x, center.y + h * 0.5, center.z}
	raylib.DrawCube(pos, cs * 0.75, h, cs * 0.75, color)
}

// Barrera de obstáculo simplificada: caja orientada según a qué lado del
// camino da (recto horizontal/vertical). El caso de esquina/unión (dos ejes
// a la vez) se simplifica a una caja cuadrada — sin rotación 45°, ver
// 3D_RENDER_PLAN.md (color plano, sin geometría rotada en esta v1).
render_obstacles_3d :: proc(m: ^entities.Map, map_w, map_h: i32) {
	cs := constants.WORLD_CELL_SIZE
	is_path :: proc(m: ^entities.Map, r, c, map_w, map_h: i32) -> bool {
		if r < 0 || r >= map_h || c < 0 || c >= map_w { return false }
		t := m.grid[r][c]
		return t == .PATH || t == .SPAWN || t == .GOAL
	}
	for row in 0 ..< map_h {
		for col in 0 ..< map_w {
			if m.obstacle_grid[row][col] != .OBSTACLE { continue }
			center, top_y := tile_world_top(m, row, col)
			has_h := is_path(m, row, col - 1, map_w, map_h) || is_path(m, row, col + 1, map_w, map_h)
			has_v := is_path(m, row - 1, col, map_w, map_h) || is_path(m, row + 1, col, map_w, map_h)

			bar_len := cs * constants.OBSTACLE_BARRIER_LENGTH
			bar_thk := cs * constants.OBSTACLE_BARRIER_THICKNESS
			bar_h := cs * 0.3
			size_x, size_z := bar_thk, bar_thk
			switch {
			case has_v && !has_h:
				size_x, size_z = bar_len, bar_thk
			case has_h && !has_v:
				size_x, size_z = bar_thk, bar_len
			case:
				size_x, size_z = bar_len * 0.6, bar_len * 0.6
			}
			pos := raylib.Vector3{center.x, top_y + bar_h * 0.5, center.z}
			raylib.DrawCube(pos, size_x, bar_h, size_z, constants.COLOR_OBSTACLE_FILL)
		}
	}
}

// Rieles de puente — versión 3D del viejo render_path_railings (2D,
// eliminado junto al resto del renderer 2D). El tile en sí ya se ve como
// camino sobre agua gracias a la máscara horneada en terrain_cache
// (pathColor sobre la altura fija de agua, ver lighting.fs) — esto solo
// agrega la baranda en los bordes que NO conectan con otro tile de camino
// (bordes "abiertos" del puente), igual criterio de vecinos que antes.
render_bridge_railings_3d :: proc(m: ^entities.Map) {
	cs         := constants.WORLD_CELL_SIZE
	path_width := cs * constants.PATH_WIDTH_RATIO
	rail_t     := cs * constants.BRIDGE_RAILING_THICK
	rail_h     := cs * 0.18
	color      := constants.COLOR_BRIDGE_RAILING
	// El tile-puente es agua a altura FIJA (ver _terrain_tile_height_color) —
	// no el heightmap, así que la baranda se apoya en WORLD_WATER_HEIGHT.
	deck_y := constants.WORLD_WATER_HEIGHT + rail_h*0.5

	is_path_like :: proc(m: ^entities.Map, r, c: i32) -> bool {
		if r < 0 || r >= m.height || c < 0 || c >= m.width { return false }
		t := m.grid[r][c]
		return t == .PATH || t == .SPAWN || t == .GOAL
	}

	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			if m.grid[row][col] != .PATH || !m.water_grid[row][col] { continue }
			cx := f32(col) * cs + cs*0.5
			cz := f32(row) * cs + cs*0.5

			if !is_path_like(m, row - 1, col) {
				raylib.DrawCube({cx, deck_y, cz - path_width*0.5}, path_width, rail_h, rail_t, color)
			}
			if !is_path_like(m, row + 1, col) {
				raylib.DrawCube({cx, deck_y, cz + path_width*0.5}, path_width, rail_h, rail_t, color)
			}
			if !is_path_like(m, row, col - 1) {
				raylib.DrawCube({cx - path_width*0.5, deck_y, cz}, rail_t, rail_h, path_width, color)
			}
			if !is_path_like(m, row, col + 1) {
				raylib.DrawCube({cx + path_width*0.5, deck_y, cz}, rail_t, rail_h, path_width, color)
			}
		}
	}
}

// Nenúfar 3D — versión del viejo render_water_lily (2D, eliminado) para
// árboles que caen en tile de agua. Discos chatos (cilindros muy bajos,
// simulan un círculo plano — raylib no tiene un DrawCircle3D relleno)
// apoyados sobre el agua en vez de círculos de pantalla; misma semilla
// determinística por tile (hash_position/hash_random, definidas más abajo)
// y misma deriva animada que la versión 2D, ahora usando
// lighting_shader.caustics_anim_time (water_shader ya no existe).
render_water_lily_3d :: proc(center: raylib.Vector3, row, col: i32) {
	cs := constants.WORLD_CELL_SIZE
	seed := hash_position(row, col)
	rng :: proc(s: ^u32) -> f32 {
		s^ = s^ * 1664525 + 1013904223
		return f32(s^ & 0xFFFF) / f32(0xFFFF)
	}

	t := lighting_shader.caustics_anim_time
	pad_count := 2 + i32(hash_random(row, col, 0) * 3)  // 2..4

	for i in 0 ..< pad_count {
		s := seed + u32(i) * 97
		local_x := (rng(&s) * 0.70 + 0.15 - 0.5) * cs
		local_z := (rng(&s) * 0.70 + 0.15 - 0.5) * cs
		pr := cs * (0.09 + rng(&s) * 0.07)  // radio 0.09..0.16 de cs

		// Deriva suave sobre el agua — fase y frecuencia propias por pad.
		phase := rng(&s) * 6.2832
		freq  := 0.5 + rng(&s) * 0.3
		amp   := cs * 0.05
		dx := math.cos(t * freq + phase) * amp
		dz := math.sin(t * freq * 0.8 + phase) * amp * 0.6

		pad_pos := raylib.Vector3{center.x + local_x + dx, center.y + 0.02, center.z + local_z + dz}
		raylib.DrawCylinder(pad_pos, pr, pr, 0.02, 12, raylib.Color{40, 110, 50, 230})
		raylib.DrawCylinderWires(pad_pos, pr, pr, 0.02, 12, raylib.Color{70, 150, 70, 160})

		// 50% de chance de una florcita rosa sobre el pad.
		if rng(&s) > 0.5 {
			fr := cs * (0.016 + rng(&s) * 0.023)
			flower_pos := raylib.Vector3{pad_pos.x, pad_pos.y + 0.015, pad_pos.z}
			for p in 0 ..< 5 {
				a := f32(p) * 1.2566  // 2π/5
				ppos := raylib.Vector3{
					flower_pos.x + math.cos(a) * fr * 1.6,
					flower_pos.y,
					flower_pos.z + math.sin(a) * fr * 1.6,
				}
				raylib.DrawCylinder(ppos, fr, fr, 0.015, 8, raylib.Color{255, 150, 190, 240})
			}
			raylib.DrawCylinder(flower_pos, fr * 0.6, fr * 0.6, 0.018, 8, raylib.Color{255, 230, 80, 255})
		}
	}
}

// Anillo plano sobre el suelo (rango de torre, AoE, action-target hover) —
// DrawCircle3D acostado sobre el plano XZ.
draw_ground_ring :: proc(center: raylib.Vector3, radius: f32, color: raylib.Color) {
	raylib.DrawCircle3D(center, radius, {1, 0, 0}, 90, color)
}

render_tower_ranges_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	if app.settings.show_tower_range {
		for &tower in app.sim.towers {
			center, top_y := tile_world_top(m, tower.r, tower.c)
			ring := raylib.Vector3{center.x, top_y + 0.02, center.z}
			draw_ground_ring(ring, tower.range * cs, constants.TOWER_RANGE_PREVIEW)
		}
	}
	if selected := entities.app_get_selected_tower(app); selected != nil {
		center, top_y := tile_world_top(m, selected.r, selected.c)
		ring := raylib.Vector3{center.x, top_y + 0.02, center.z}
		draw_ground_ring(ring, selected.range * cs, constants.TOWER_RANGE_PREVIEW)
		draw_ground_ring(ring, selected.range * cs, raylib.Color{255, 255, 255, 200})
	}
}

// Caja plana semitransparente sobre un tile — reemplazo simplificado del
// blur de 5 capas 2D (draw_action_target) para el mapa 3D.
draw_action_target_3d :: proc(center: raylib.Vector3, color: raylib.Color, alpha: u8) {
	cs := constants.WORLD_CELL_SIZE
	c := color
	c.a = alpha
	pos := raylib.Vector3{center.x, center.y + 0.03, center.z}
	raylib.DrawCube(pos, cs * 0.9, 0.02, cs * 0.9, c)
}

// Objetos del mapa (torres, spawn/goal, accesorios, obstáculos), overlays de
// acción por tile y ghost de construcción — versión 3D de render_map_objects.
// Debe llamarse dentro de un bloque BeginMode3D/EndMode3D activo.
render_map_objects_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	COLOR_TARGET_VALID   :: raylib.Color{60, 220, 90, 255}
	COLOR_TARGET_INVALID :: raylib.Color{220, 60, 60, 255}

	// ── Overlays de casillas posibles para reliquias activas con objetivo ──
	// Guard defensivo: pending_tower_action no se resetea al cambiar de
	// estado (solo al completar/cancelar la acción durante PLAYING), así que
	// sin el chequeo de estado este loop podría dispararse en EDITOR si
	// quedó en un valor distinto de .TOWER desde una sesión PLAYING previa.
	if app.state == .PLAYING && app.pending_tower_action != .TOWER {
		hover_row, hover_col, hover_valid := input_get_hovered_cell(app)
		for row in 0 ..< m.height {
			for col in 0 ..< m.width {
				tile := m.grid[row][col]
				center, top_y := tile_world_top(m, row, col)
				surface := raylib.Vector3{center.x, top_y, center.z}
				hovered := hover_valid && hover_row == row && hover_col == col
				layer_a := u8(hovered ? 60 : 90)

				is_tower_tile := tile == .TOWER_ARCHER || tile == .TOWER_CANNON ||
				                  tile == .TOWER_SNIPER  || tile == .TOWER_MISSILE ||
				                  tile == .TOWER_LASER   || tile == .TOWER_ICE ||
				                  tile == .TOWER_ENHANCE || tile == .TOWER_TESLA ||
				                  tile == .TOWER_MORTAR

				drew_target := false
				#partial switch app.pending_tower_action {
				case .LUMBERJACK:
					if tile == .ACCESSORY_TREE && !m.water_grid[row][col] {
						draw_action_target_3d(surface, COLOR_TARGET_VALID, layer_a)
						drew_target = true
					}
				case .OVERDRIVE:
					if is_tower_tile {
						draw_action_target_3d(surface, COLOR_TARGET_VALID, layer_a)
						drew_target = true
					}
				case .GARDENER:
					if app.gardener_source == {-1, -1} {
						if is_tower_tile {
							draw_action_target_3d(surface, COLOR_TARGET_VALID, layer_a)
							drew_target = true
						}
					} else {
						if app.gardener_source == {row, col} {
							draw_action_target_3d(surface, COLOR_TARGET_INVALID, 100)
							drew_target = true
						} else if tile == .EMPTY &&
						          m.obstacle_grid[row][col] == .EMPTY &&
						          !m.water_grid[row][col] {
							draw_action_target_3d(surface, COLOR_TARGET_VALID, layer_a)
							drew_target = true
						}
					}
				case .TOWER:
				}

				if hovered && !drew_target {
					draw_action_target_3d(surface, COLOR_TARGET_INVALID, 40)
				}
			}
		}
	}

	// ── Objetos del mapa ── (formas sólidas con normal — se iluminan; los
	// rings/reticles/overlays de arriba y abajo se quedan con el shader
	// default a propósito, ver Lighting_Shader).
	biome_colors := constants.BIOME_COLORS[m.biome]  // para el promedio de altura de agua bajo los nenúfares, ver caso ACCESSORY_TREE
	raylib.BeginShaderMode(lighting_shader.shader)
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			tile := m.grid[row][col]
			center, top_y := tile_world_top(m, row, col)
			surface := raylib.Vector3{center.x, top_y, center.z}

			#partial switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER,
			     .TOWER_ICE, .TOWER_ENHANCE, .TOWER_TESLA, .TOWER_MORTAR:
				found := false
				for &tower in app.sim.towers {
					if tower.r == row && tower.c == col {
						render_tower_3d(&tower, m)
						found = true
						break
					}
				}
				if !found {
					// Sin torre real en la simulación (EDITOR, o el preview
					// del browser de mapas) — dibujar una forma genérica a
					// partir del tipo de tile en vez de nada, mismo criterio
					// que usaba el render 2D (tile_to_tower_type +
					// draw_tower_tile) pero con la primitiva 3D.
					tower_type := tile_to_tower_type(tile)
					color := constants.TOWER_SPECS[tower_type].color
					draw_tower_shape_3d(surface, constants.WORLD_CELL_SIZE, 0, 0, color)
				}
			case .SPAWN:
				render_spawn_3d(surface)
			case .GOAL:
				render_goal_3d(surface)
			case .ACCESSORY_TREE:
				if m.water_grid[row][col] {
					// La malla del terreno promedia la altura por ESQUINA
					// compartida entre tiles vecinos (ver _terrain_corner) —
					// un tile de agua junto a tierra no queda perfectamente
					// plano en WORLD_WATER_HEIGHT cerca del borde. Promediar
					// las 4 esquinas del tile da la altura real de la
					// superficie en el centro (donde se planta el nenúfar),
					// para que quede apoyado en el agua y no floreciendo por
					// encima o hundido.
					water_y := f32(0)
					for dr in 0 ..= 1 {
						for dc in 0 ..= 1 {
							h, _ := _terrain_corner(m, row + i32(dr), col + i32(dc), biome_colors)
							water_y += h
						}
					}
					water_y *= 0.25
					lily_center := raylib.Vector3{surface.x, water_y, surface.z}
					render_water_lily_3d(lily_center, row, col)
				} else {
					render_tree_3d(surface, m.biome)
				}
			case .ACCESSORY_BLOCK:
				blk_level := entities.map_get_obstacle_level(m, row, col)
				render_block_3d(surface, m.biome, blk_level)
			}
		}
	}

	render_obstacles_3d(m, m.width, m.height)
	render_bridge_railings_3d(m)
	raylib.EndShaderMode()

	// ── Retículas (torre/obstáculo seleccionado, hover en modo acción) ──
	if app.selected_tower_r >= 0 {
		center, top_y := tile_world_top(m, app.selected_tower_r, app.selected_tower_c)
		render_reticle_3d({center.x, top_y, center.z}, constants.UI_RETICLE_COLOR)
	}
	if app.state == .PLAYING && app.pending_tower_action != .TOWER {
		hover_row, hover_col, hover_valid := input_get_hovered_cell(app)
		if hover_valid {
			center, top_y := tile_world_top(m, hover_row, hover_col)
			render_reticle_3d({center.x, top_y, center.z}, constants.UI_RETICLE_COLOR)
		}
	}
	if app.selected_obstacle.valid {
		center, top_y := tile_world_top(m, app.selected_obstacle.row, app.selected_obstacle.col)
		render_reticle_3d({center.x, top_y, center.z}, constants.UI_RETICLE_COLOR)
	}
	// Retículo de celda seleccionada del editor — el ghost-preview 2D viejo
	// (app.sim.selected_build_tower) es código muerto para EDITOR, que solo
	// usa app.editor.current_tool; acá solo hace falta el marco de la celda.
	if app.state == .EDITOR && app.selected_cell.valid {
		center, top_y := tile_world_top(m, app.selected_cell.row, app.selected_cell.col)
		render_reticle_3d({center.x, top_y, center.z}, constants.UI_RETICLE_COLOR)
	}

	// ── Ghost de construcción ──
	if app.selected_cell.valid && app.sim.selected_build_tower != .EMPTY {
		center, top_y := tile_world_top(m, app.selected_cell.row, app.selected_cell.col)
		surface := raylib.Vector3{center.x, top_y, center.z}
		cs := constants.WORLD_CELL_SIZE

		if app.sim.selected_build_tower == .OBSTACLE {
			forbidden := entities.map_is_path_corner_or_junction(m, app.selected_cell.row, app.selected_cell.col)
			color := COLOR_TARGET_VALID if !forbidden else COLOR_TARGET_INVALID
			draw_action_target_3d(surface, color, 130)
		} else {
			tower_type := tile_to_tower_type(app.sim.selected_build_tower)
			spec := constants.TOWER_SPECS[tower_type]
			draw_tower_shape_3d(surface, cs, 0, 0, spec.color, 160)
			ring := raylib.Vector3{surface.x, surface.y + 0.02, surface.z}
			draw_ground_ring(ring, spec.range * cs, constants.TOWER_RANGE_PREVIEW)
			if spec.aoe > 0 {
				draw_ground_ring(ring, spec.aoe * cs, raylib.Color{255, 180, 60, 180})
			}
		}
	}
}

// ── Gameplay 3D (enemigos, proyectiles, efectos) ────────────────────────────
// Ver 3D_RENDER_PLAN.md, paso 4. Las funciones *_3d deben llamarse dentro de
// un bloque BeginMode3D/EndMode3D activo; render_gameplay_screenspace_3d es
// la excepción — se llama DESPUÉS de EndMode3D (barras de vida y números de
// daño se resuelven reproyectando con GetWorldToScreen, así el texto siempre
// mira a cámara sin billboarding real).

// Altura de superficie aproximada bajo una posición fraccional de grilla —
// heightmap del tile más cercano, sin interpolar (misma simplificación que
// el resto del terreno 3D v1).
world_ground_y :: proc(m: ^entities.Map, gx, gy: f32) -> f32 {
	col := clamp(i32(gx), 0, m.width - 1)
	row := clamp(i32(gy), 0, m.height - 1)
	return m.heightmap[row][col] * constants.WORLD_HEIGHT_SCALE
}

// enemy.x/y son "crudas" (índice de celda sin +0.5, igual que tile_world_top).
world_from_raw_grid :: proc(m: ^entities.Map, gx, gy: f32) -> raylib.Vector3 {
	cs := constants.WORLD_CELL_SIZE
	return {gx * cs + cs * 0.5, world_ground_y(m, gx, gy), gy * cs + cs * 0.5}
}

// proyectiles/partículas/beams ya vienen centradas (+0.5 aplicado al spawnear).
world_from_centered_grid :: proc(m: ^entities.Map, gx, gy: f32) -> raylib.Vector3 {
	cs := constants.WORLD_CELL_SIZE
	return {gx * cs, world_ground_y(m, gx, gy), gy * cs}
}

// Cuerpos de enemigos — formas sólidas con normal, se llama dentro del wrap
// de Lighting_Shader (ver render_gameplay_3d). Los anillos de estado
// (armored/slow) se resuelven aparte en render_enemy_status_rings_3d, fuera
// del shader de iluminación (DrawCircle3D no emite normales).
render_enemies_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	for &enemy in app.sim.enemies {
		pos := world_from_raw_grid(m, enemy.x, enemy.y)
		size := entities.enemy_get_size(&enemy) * cs
		color := entities.enemy_get_color(&enemy)
		if .INVISIBLE in enemy.flags && enemy.revealed_timer <= 0 {
			color.a = u8(f32(color.a) * constants.ENEMY_INVISIBLE_ALPHA)
		}
		squash := enemy.hit_squash * constants.ENEMY_HIT_SQUASH_AMOUNT
		size_xz := size * (1 + squash)
		size_y := size * (1 - squash)

		switch {
		case .BOSS in enemy.flags:
			center := raylib.Vector3{pos.x, pos.y + size_y, pos.z}
			raylib.DrawCube(center, size_xz * 2, size_y * 2, size_xz * 2, color)
		case .FLYING in enemy.flags:
			base := raylib.Vector3{pos.x, pos.y + cs * 0.6, pos.z}
			raylib.DrawCylinder(base, size_xz, 0, size_y * 2, 4, color)
		case:
			center := raylib.Vector3{pos.x, pos.y + size_y, pos.z}
			raylib.DrawSphereEx(center, size_xz, 10, 10, color)
		}
	}
}

render_enemy_status_rings_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	for &enemy in app.sim.enemies {
		pos := world_from_raw_grid(m, enemy.x, enemy.y)
		size := entities.enemy_get_size(&enemy) * cs
		squash := enemy.hit_squash * constants.ENEMY_HIT_SQUASH_AMOUNT
		size_xz := size * (1 + squash)

		if .ARMORED in enemy.flags {
			draw_ground_ring({pos.x, pos.y + 0.02, pos.z}, size_xz * 1.1, constants.COLOR_ENEMY_ARMORED)
		}
		if enemy.slow_timer > 0 {
			pulse := f32(math.abs(math.sin(f64(raylib.GetTime()) * 5.0)))
			alpha := u8(60.0 + 50.0 * pulse)
			draw_ground_ring({pos.x, pos.y + 0.03, pos.z}, size_xz * 1.2, raylib.Color{100, 200, 255, alpha})
		}
	}
}

render_projectiles_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	for &proj in app.sim.projectiles {
		pos := world_from_centered_grid(m, proj.x, proj.y)
		pos.y += cs * 0.35
		#partial switch proj.type {
		case .ARCHER:
			raylib.DrawSphere(pos, cs * 0.05, raylib.Color{160, 110, 55, 255})
		case .CANNON:
			raylib.DrawSphere(pos, cs * 0.1, constants.COLOR_BLOCK)
		case .SNIPER:
			raylib.DrawSphere(pos, cs * 0.06, constants.COLOR_BLOCK)
		case .MISSILE:
			raylib.DrawSphere(pos, cs * 0.08, raylib.Color{220, 80, 60, 255})
		case .MORTAR:
			raylib.DrawSphere(pos, cs * 0.13, constants.TOWER_MORTAR_BASE)
		case:
			raylib.DrawSphere(pos, cs * 0.06, raylib.WHITE)
		}
	}
}

render_explosions_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	for &explosion in app.sim.explosions {
		cs := constants.WORLD_CELL_SIZE
		pos := world_from_centered_grid(m, explosion.x, explosion.y)
		radius := explosion.radius * cs
		alpha := u8(255 * (explosion.life / explosion.max_life))
		pos.y += radius * 0.5
		raylib.DrawSphere(pos, radius, raylib.Color{255, 100, 50, alpha})
	}
}

render_hit_particles_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	for &p in app.sim.hit_particles {
		pos := world_from_centered_grid(m, p.x, p.y)
		pos.y += cs * 0.25
		alpha := u8(255 * (p.life / p.max_life))
		color := p.color
		color.a = alpha
		raylib.DrawSphere(pos, p.radius * cs, color)
	}
}

render_ice_pulses_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	for &pulse in app.sim.ice_pulses {
		pos := world_from_centered_grid(m, pulse.x, pulse.y)
		t := pulse.life / pulse.max_life
		alpha := u8(t * 210.0)
		ring := raylib.Vector3{pos.x, pos.y + 0.02, pos.z}
		draw_ground_ring(ring, pulse.radius * cs, raylib.Color{180, 235, 255, alpha})
	}
}

render_laser_beams_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	for &beam in app.sim.laser_beams {
		alpha := beam.duration / beam.max_duration
		color := beam.color
		color.a = u8(f32(color.a) * alpha)
		start := world_from_centered_grid(m, beam.start_x, beam.start_y)
		end := world_from_centered_grid(m, beam.end_x, beam.end_y)
		start.y += cs * 0.4
		end.y += cs * 0.35
		raylib.DrawLine3D(start, end, color)
	}
}

// dy_start/dy_end vienen en convención screen-space (negativo = arriba) —
// se invierte el signo para el mundo 3D (arriba = +Y).
render_glow_particles_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	for &p in app.sim.glow_particles {
		progress := p.t / p.lifetime
		ease := progress * progress
		alpha := u8((1.0 - progress) * 255)
		radius := p.radius_start + (p.radius_end - p.radius_start) * progress
		dy_cells := p.dy_start + (p.dy_end - p.dy_start) * ease
		pos := world_from_centered_grid(m, p.grid_x, p.grid_y)
		pos.y += -dy_cells * cs + 0.05
		draw_ground_ring(pos, radius * cs, raylib.Color{255, 255, 255, alpha})
	}
}

render_gameplay_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	// Rings/líneas primero, sin iluminar (DrawCircle3D/DrawLine3D no emiten
	// normales — el depth buffer se encarga del orden visual correcto, no
	// hace falta un painter's-algorithm como en la versión 2D).
	render_ice_pulses_3d(app, m)
	render_glow_particles_3d(app, m)
	render_laser_beams_3d(app, m)

	// Formas sólidas — iluminadas.
	raylib.BeginShaderMode(lighting_shader.shader)
	render_enemies_3d(app, m)
	render_projectiles_3d(app, m)
	render_explosions_3d(app, m)
	render_hit_particles_3d(app, m)
	render_airdrop_boxes_3d(app, m)
	raylib.EndShaderMode()

	render_enemy_status_rings_3d(app, m)
}

// Caja de airdrop ya aterrizada — cubo real apoyado sobre el terreno (antes
// era un dibujo pixel-art 2D reproyectado, ver render_airdrops; el resto de
// las fases del airdrop — avión, estela, paracaídas, ping, indicador de
// borde — se quedan 2D screen-space a propósito, son overlays "siempre
// visibles en pantalla", no objetos del mundo).
render_airdrop_boxes_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	size := cs * 0.5

	for &drop in app.sim.airdrops {
		if drop.phase != .BOX_LANDED { continue }
		center, top_y := tile_world_top(m, drop.target_row, drop.target_col)
		pos := raylib.Vector3{center.x, top_y + size * 0.5, center.z}
		raylib.DrawCube(pos, size, size, size, constants.COLOR_AIRDROP_BOX)
		raylib.DrawCubeWires(pos, size, size, size, constants.COLOR_AIRDROP_BOX_DARK)
	}
}

// Barras de vida + números de daño — screen-space, reproyectados con
// GetWorldToScreen tras cerrar BeginMode3D (ver comentario arriba).
render_gameplay_screenspace_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE

	for &enemy in app.sim.enemies {
		pos := world_from_raw_grid(m, enemy.x, enemy.y)
		size := entities.enemy_get_size(&enemy) * cs
		top := raylib.Vector3{pos.x, pos.y + size * 2 + 0.15, pos.z}
		screen := raylib.GetWorldToScreen(top, app.camera3d)

		hp_percent := enemy.hp / enemy.max_hp
		bar_w := f32(36)
		bar_h := f32(5)
		bx := screen.x - bar_w * 0.5
		by := screen.y

		raylib.DrawRectangle(i32(bx), i32(by), i32(bar_w), i32(bar_h), raylib.DARKGRAY)
		if hp_percent > 0.01 {
			hp_color := raylib.GREEN
			if hp_percent < 0.3 {
				hp_color = raylib.Color{200, 50, 50, 255}
			} else if hp_percent < 0.6 {
				hp_color = raylib.YELLOW
			}
			fill_w := max(bar_w * hp_percent, 1.0)
			raylib.DrawRectangle(i32(bx), i32(by), i32(fill_w), i32(bar_h), hp_color)
		}
	}

	if !app.settings.show_damage_numbers { return }
	for &dn in app.sim.damage_numbers {
		pos := world_from_centered_grid(m, dn.x, dn.y)
		screen := raylib.GetWorldToScreen(pos, app.camera3d)

		display_value := i32(dn.value + 0.5)
		if display_value == 0 { continue }

		alpha := u8(255 * dn.life)
		color := dn.color
		color.a = alpha
		outline_color := raylib.Color{0, 0, 0, alpha}

		if dn.is_money {
			money_text := fmt.ctprintf("+$%d", display_value)
			draw_text_with_outline(money_text, screen, 10 * app.zoom, 0, color, outline_color, 1)
		} else {
			font_size := f32(9) * app.zoom
			if dn.is_critical {
				font_size = 18 * app.zoom
			}
			damage_text := fmt.ctprintf("%d", display_value)
			draw_text_with_outline(damage_text, screen, font_size, 0, color, outline_color, 1)
		}
	}
}

// Render the entire game
render_game :: proc(app: ^entities.App_State) {
	ui_blocks_clear()
	raylib.ClearBackground(raylib.BLACK)

	if constants.NEBULA_BACKGROUND_ENABLED &&
		(app.state == .MENU ||
		app.state == .RUN_COMPLETE ||
		app.state == .CAMPAIGN_MAP ||
		app.state == .PROGRESSION ||
		app.state == .LIBRARY) {
			nebula_draw()
	}

	// Screen shake: desplaza la cámara solo durante el render del mundo (mapa,
	// enemigos, torres, pájaros) — se restaura antes de la UI para que paneles/
	// botones/tooltips nunca tiemblen. Offset determinístico (seno/coseno en el
	// tiempo) en vez de random puro por frame, para que se vea suave y no "buzz".
	saved_cam_x := app.camera_offset_x
	saved_cam_y := app.camera_offset_y
	if app.screen_shake_trauma > 0 {
		t   := f32(raylib.GetTime())
		amt := app.screen_shake_trauma * app.screen_shake_trauma * constants.SCREEN_SHAKE_MAX_OFFSET_PX
		app.camera_offset_x += i32(math.sin(t * 37.0) * amt)
		app.camera_offset_y += i32(math.cos(t * 43.0) * amt)
	}

	// Pausa: el mundo se redirige a una textura en vez de dibujarse directo a
	// pantalla, para poder pasarlo por el blur de 2 pasadas + tinte ("vidrio
	// esmerilado") antes de que se vea. Ver Pause_Blur más arriba.
	//
	// PAUSED ahora comparte el mismo camino 3D que PLAYING/EDITOR (mapa
	// congelado tal cual quedó, no un snapshot 2D aparte) — ya no hace falta
	// precomputar water_render_mask/path_render_mask (esa trampa era
	// específica del render 2D con for_preview=true; el terreno 3D usa un
	// Model cacheado con las máscaras ya horneadas en las texturas del
	// material, sin ningún BeginTextureMode propio en el camino de dibujo).
	// BeginMode3D/EndMode3D corre sin problema dentro de un BeginTextureMode
	// activo — la trampa de "no anida" es específica de BeginTextureMode.
	is_paused_glass := app.state == .PAUSED
	if is_paused_glass {
		pause_blur_resize()
		raylib.BeginTextureMode(pause_blur.capture_tex)
		raylib.ClearBackground(raylib.BLACK)
	}

	// Map and gameplay are only visible while actually playing, editing, or
	// paused. In menu/overlay states the nebula is the sole background.
	if app.state == .PLAYING || app.state == .PAUSED || app.state == .EDITOR {
		m := &app.editor.game_map
		update_camera3d(app)

		raylib.ClearBackground(constants.BIOME_COLORS[m.biome].bg)
		raylib.BeginMode3D(app.camera3d)
		render_map_3d(app, m)
		if app.settings.show_grid {
			render_grid_lines_3d(app, m)
		}
		render_tower_ranges_3d(app, m)
		render_map_objects_3d(app, m)
		render_gameplay_3d(app, m)          // no-op en EDITOR: sim.enemies/... vacío fuera de una run
		raylib.EndMode3D()
		render_gameplay_screenspace_3d(app, m)  // no-op en EDITOR, misma razón
		render_airdrops(app)
	}

	// Pájaros: decoración ambiental 2D pura (líneas en world-px de pantalla,
	// sin relación con el grid), fuera del alcance de 3D_RENDER_PLAN.md. Se
	// ven "pegados" como un plano flotando sobre el mundo 3D — desactivados
	// en todo estado con cámara 3D (PLAYING, EDITOR y ahora PAUSED también)
	// hasta portarlos (necesitarían posición 3D real + billboarding). Ya no
	// queda ningún estado que los dibuje.
	// cloud_shader_draw(app)  // desactivado

	if is_paused_glass {
		raylib.EndTextureMode()
	}

	app.camera_offset_x = saved_cam_x
	app.camera_offset_y = saved_cam_y

	if is_paused_glass {
		pause_blur_draw()
	}

	render_ui(app)
	render_tooltip_layer(app) // Siempre antes de la consola
	render_console(app)       // La consola va encima de absolutamente todo
}

// Genera el thumbnail del browser de mapas con el mismo pipeline 3D
// iluminado que PLAYING/EDITOR/PAUSED (terreno con biomas/agua/camino +
// torres/spawn/goal/árboles/obstáculos vía render_map_3d/render_map_objects_3d)
// en vez del render 2D plano que tenía antes. Cámara fija-isométrica propia,
// encuadrada para que el mapa entero entre en el rect de la textura con el
// mismo criterio de zoom-to-fit que simulation_fit_camera (systems/simulation.odin)
// — no toca camera_focus/zoom/camera3d en vivo, la cámara real del editor
// queda intacta.
render_map_preview_to_texture :: proc(app: ^entities.App_State) {
	m := &app.editor.browser.preview

	if app.editor.browser.preview_tex_valid {
		raylib.UnloadRenderTexture(app.editor.browser.preview_tex)
		app.editor.browser.preview_tex_valid = false
	}

	cs := f32(app.settings.cell_size)
	tex_w := i32(f32(m.width)  * cs)
	tex_h := i32(f32(m.height) * cs)
	app.editor.browser.preview_tex = raylib.LoadRenderTexture(tex_w, tex_h)

	MARGIN :: f32(24)
	zoom_x := (f32(tex_w) - MARGIN * 2) / (f32(m.width)  * cs)
	zoom_y := (f32(tex_h) - MARGIN * 2) / (f32(m.height) * cs)
	zoom := clamp(min(zoom_x, zoom_y), constants.ZOOM_MIN, constants.ZOOM_MAX)

	wcs := constants.WORLD_CELL_SIZE
	focus := raylib.Vector3{f32(m.width) * wcs * 0.5, 0, f32(m.height) * wcs * 0.5}
	camera := camera3d_for_focus(focus, zoom)

	// terrain_cache es un singleton compartido con el mapa real en curso —
	// invalidar antes (para que tome los datos de `m`, el preview) y después
	// (para que el próximo frame real lo reconstruya desde app.editor.game_map
	// en vez de quedarse con el del preview).
	terrain_cache_invalidate()

	// render_map_objects_3d lee app.sim.towers/app.state/app.selected_cell
	// para dibujar torres reales y overlays de PLAYING — el preview no tiene
	// una simulación asociada a `m`, así que se pisan temporalmente:
	// sim.towers vacío hace caer a render_map_objects_3d en su fallback "sin
	// torre real" (tile → forma genérica del tipo, igual que en el editor), y
	// state=.EDITOR desactiva los overlays de PLAYING.
	saved_towers        := app.sim.towers
	saved_state         := app.state
	saved_selected_cell := app.selected_cell.valid
	app.sim.towers          = nil
	app.state               = .EDITOR
	app.selected_cell.valid = false

	raylib.BeginTextureMode(app.editor.browser.preview_tex)
	raylib.ClearBackground(constants.BIOME_COLORS[m.biome].bg)
	raylib.BeginMode3D(camera)
	render_map_3d(app, m)
	render_map_objects_3d(app, m)
	raylib.EndMode3D()
	raylib.EndTextureMode()

	app.sim.towers          = saved_towers
	app.state               = saved_state
	app.selected_cell.valid = saved_selected_cell

	terrain_cache_invalidate()

	app.editor.browser.preview_tex_valid = true
}

// Líneas de grilla en 3D — cubre PLAYING, EDITOR y PAUSED por igual (los
// tres comparten el mismo bloque de render 3D, ver render_game), gateada
// por el mismo toggle general app.settings.show_grid del menú de Settings.
// Sigue la altura de cada esquina con el mismo criterio de promedio que
// _terrain_corner (ver terrain_cache_ensure) para que las líneas se apoyen
// sobre el terreno real en vez de flotar o enterrarse en las pendientes
// diagonales del mesh.
render_grid_lines_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	biome_colors := constants.BIOME_COLORS[m.biome]
	LIFT :: f32(0.03)  // evita z-fighting contra la superficie del terreno

	for r in 0 ..= m.height {
		for c in 0 ..= m.width {
			// _terrain_corner ya devuelve la altura final en unidades de mundo
			// (la escala se aplica adentro, en _terrain_tile_height_color) —
			// no volver a multiplicar por WORLD_HEIGHT_SCALE acá.
			h, _ := _terrain_corner(m, r, c, biome_colors)
			y := h + LIFT
			if c < m.width {
				h2, _ := _terrain_corner(m, r, c + 1, biome_colors)
				y2 := h2 + LIFT
				raylib.DrawLine3D({f32(c) * cs, y, f32(r) * cs}, {f32(c + 1) * cs, y2, f32(r) * cs}, constants.COLOR_GRID_LINE)
			}
			if r < m.height {
				h2, _ := _terrain_corner(m, r + 1, c, biome_colors)
				y2 := h2 + LIFT
				raylib.DrawLine3D({f32(c) * cs, y, f32(r) * cs}, {f32(c) * cs, y2, f32(r + 1) * cs}, constants.COLOR_GRID_LINE)
			}
		}
	}
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

// Render block accessory — aspecto varía por bioma (vista top-down).
// level: 1→70%, 2→80%, 3→90% de la celda.  row/col: seed de variación visual.
render_block :: proc(x, y, cs: f32, biome: constants.Biome = constants.Biome.PLAIN, level: i32 = 1, row: i32 = 0, col: i32 = 0) {
	lvl    := clamp(level, 1, 3)
	scale  := 0.70 + f32(lvl - 1) * 0.10
	margin := cs * (1.0 - scale) / 2.0
	bx     := x + margin
	by     := y + margin
	bw     := cs * scale
	bh     := cs * scale
	cx     := bx + bw * 0.5
	cy     := by + bh * 0.5
	so     := f32(2)

	// Semilla de variación por celda
	seed := u32(row * 17 + col * 31)

	switch biome {
	case .PLAIN:
		// Casa con techo de tejas rojas (top-down)
		raylib.DrawRectangle(i32(bx + so), i32(by + so), i32(bw), i32(bh), {0, 0, 0, 55})
		// Techo terracota
		raylib.DrawRectangleRec({bx, by, bw, bh}, {185, 65, 50, 255})
		// Líneas de tejas horizontales
		for i in 1..=5 {
			ty := by + bh * f32(i) / 6.0
			raylib.DrawRectangleRec({bx + bw * 0.05, ty, bw * 0.90, 1.5}, {155, 45, 32, 200})
		}
		// Cumbrera (más gruesa y oscura en el centro)
		raylib.DrawRectangleRec({bx + bw * 0.04, by + bh * 0.5 - 1.5, bw * 0.92, 3}, {125, 32, 22, 255})
		// Chimenea — posición varía según seed
		ch_size := bw * 0.13
		ch_x    := bx + bw * (0.15 if seed % 2 == 0 else 0.70)
		ch_y    := by + bh * (0.12 if seed % 4 < 2 else 0.70)
		raylib.DrawRectangleRec({ch_x, ch_y, ch_size, ch_size}, {82, 58, 52, 255})
		raylib.DrawRectangleRec({ch_x + 2, ch_y + 2, ch_size - 4, ch_size - 4}, {45, 30, 25, 200})

	case .FOREST:
		// Cabaña de madera (top-down)
		raylib.DrawRectangle(i32(bx + so), i32(by + so), i32(bw), i32(bh), {0, 0, 0, 60})
		// Paredes exteriores (borde visible alrededor del techo)
		raylib.DrawRectangleRec({bx, by, bw, bh}, {95, 65, 42, 255})
		// Techo oscuro (inset)
		pad := bw * 0.07
		raylib.DrawRectangleRec({bx + pad, by + pad, bw - pad * 2, bh - pad * 2}, {52, 33, 18, 255})
		// Vetas de madera horizontales
		for i in 1..=6 {
			ly := by + pad + (bh - pad * 2) * f32(i) / 7.0
			raylib.DrawRectangleRec({bx + pad, ly, bw - pad * 2, 1}, {38, 23, 11, 180})
		}
		// Viga central (más gruesa)
		raylib.DrawRectangleRec({bx + pad, by + bh * 0.5 - 1.5, bw - pad * 2, 3}, {28, 16, 7, 230})
		// Chimenea
		ch_size := bw * 0.11
		ch_x    := bx + bw * (0.68 + f32(seed % 3) * 0.05)
		ch_y    := by + pad + bh * 0.08
		raylib.DrawRectangleRec({ch_x, ch_y, ch_size, ch_size}, {62, 44, 30, 255})

	case .DESERT:
		// Construcción baja irregular color blanco/crema (top-down)
		raylib.DrawRectangle(i32(bx + so), i32(by + so), i32(bw), i32(bh), {0, 0, 0, 45})
		// Bloque principal
		raylib.DrawRectangleRec({bx, by, bw, bh}, {232, 222, 202, 255})
		// Anexo superpuesto — forma irregular característica
		annex_w := bw * (0.48 + f32(seed % 5) * 0.02)
		annex_h := bh * (0.42 + f32((seed / 5) % 5) * 0.02)
		annex_x := bx + bw * (0.44 if seed % 2 == 0 else 0.08)
		annex_y := by + bh * (0.40 if seed % 3 < 2 else 0.08)
		raylib.DrawRectangleRec({annex_x, annex_y, annex_w, annex_h}, {246, 238, 220, 255})
		// Bordes de cornisa
		detail := raylib.Color{182, 165, 140, 255}
		raylib.DrawRectangleLinesEx({bx, by, bw, bh}, 1.5, detail)
		raylib.DrawRectangleLinesEx({annex_x, annex_y, annex_w, annex_h}, 1.0, detail)
		// Entrada/puerta
		door_w := bw * 0.16
		door_h := bh * 0.10
		door_x := bx + (bw - door_w) * 0.5
		door_y := by + bh - door_h - bh * 0.04
		raylib.DrawRectangleRec({door_x, door_y, door_w, door_h}, detail)

	case .MOUNTAIN:
		// Rocas grises formadas con polígonos (top-down)
		rock_col  := raylib.Color{132, 132, 138, 255}
		rock_hi   := raylib.Color{165, 166, 172, 255}
		rock_dark := raylib.Color{88, 88, 94, 255}

		n_sides := i32(5 + seed % 3)
		r1      := bw * 0.40
		rot1    := f32(seed % 360)
		// Sombra + contorno oscuro + roca principal + resalte
		raylib.DrawPoly({cx + so, cy + so}, n_sides, r1, rot1, {0, 0, 0, 55})
		raylib.DrawPoly({cx, cy}, n_sides, r1 + 2, rot1, rock_dark)
		raylib.DrawPoly({cx, cy}, n_sides, r1, rot1, rock_col)
		raylib.DrawPoly({cx - r1 * 0.12, cy - r1 * 0.14}, n_sides, r1 * 0.52, rot1 + 18, rock_hi)

		// Roca secundaria en una esquina
		sign_x : f32 = 1 if seed % 2 == 0 else -1
		sign_y : f32 = 1 if (seed >> 1) % 2 == 0 else -1
		r2_cx := cx + sign_x * bw * 0.28
		r2_cy := cy + sign_y * bh * 0.28
		r2    := bw * 0.20
		rot2  := f32((seed * 13) % 360)
		n2    := i32(4 + seed % 3)
		raylib.DrawPoly({r2_cx + so, r2_cy + so}, n2, r2, rot2, {0, 0, 0, 40})
		raylib.DrawPoly({r2_cx, r2_cy}, n2, r2 + 1.5, rot2, rock_dark)
		raylib.DrawPoly({r2_cx, r2_cy}, n2, r2, rot2, rock_col)
	}
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
	raylib.DrawRectangleRoundedLinesEx(rect, constants.OBSTACLE_BARRIER_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS, constants.OBSTACLE_BARRIER_BORDER_THICK, constants.COLOR_OBSTACLE_BORDER)
}

// Draw a single enemy shape at screen position (cx, cy).
// size is the radius/half-size in pixels. shadow_offset > 0 draws a drop shadow.
// Bosses are always drawn as squares; flying non-bosses as triangles; others as circles.
// Color/nombre de un sub-tipo de enemigo — usado por el panel de próximas
// oleadas (SCOUT, systems/menus.odin) para no depender de la fórmula de
// wave_number (el sub-tipo real ahora sale de sim.lookahead_subtype).
enemy_subtype_color :: proc(f: entities.Enemy_Flag) -> raylib.Color {
	#partial switch f {
	case .GREEN:      return constants.COLOR_ENEMY_GREEN
	case .FLYING:     return constants.COLOR_ENEMY_FLYING
	case .BLUE:       return constants.COLOR_ENEMY_BLUE
	case .SPLIT:      return constants.COLOR_ENEMY_SPLIT
	case .ARMORED:    return constants.COLOR_ENEMY_ARMORED
	case .INVISIBLE:  return constants.COLOR_ENEMY_INVISIBLE
	}
	return constants.COLOR_ENEMY
}

enemy_subtype_label :: proc(f: entities.Enemy_Flag) -> string {
	#partial switch f {
	case .GREEN:      return constants.get_text("ENEMY_TYPE_FAST")
	case .FLYING:     return constants.get_text("ENEMY_TYPE_FLYING")
	case .BLUE:       return constants.get_text("ENEMY_TYPE_HEALER")
	case .SPLIT:      return constants.get_text("ENEMY_TYPE_SPLITTER")
	case .ARMORED:    return constants.get_text("ENEMY_TYPE_ARMORED")
	case .INVISIBLE:  return constants.get_text("ENEMY_TYPE_INVISIBLE")
	}
	return constants.get_text("ENEMY_TYPE_NORMAL")
}

// squash: fracción de deformación anisotrópica al recibir un golpe (0 = sin
// deformar). Ensancha en X y achica en Y — igual en las 3 formas de base.
render_enemy_shape :: proc(cx, cy, size: f32, color: raylib.Color, is_flying: bool, is_boss: bool = false, shadow_offset: f32 = 0, is_armored: bool = false, squash: f32 = 0) {
	border_color := raylib.Color{
		u8(f32(color.r) * 0.6),
		u8(f32(color.g) * 0.6),
		u8(f32(color.b) * 0.6),
		color.a,
	}
	shadow_color := constants.COLOR_ENEMY_SHADOW
	sw := f32(constants.ENEMY_BORDER_THICKNESS)

	size_x := size * (1 + squash)
	size_y := size * (1 - squash)

	if is_boss {
		// Square — border rect then inner rect
		if shadow_offset > 0 {
			raylib.DrawRectangle(
				i32(cx - size_x + shadow_offset), i32(cy - size_y + shadow_offset),
				i32(size_x * 2), i32(size_y * 2),
				shadow_color,
			)
		}
		raylib.DrawRectangle(i32(cx - size_x), i32(cy - size_y), i32(size_x * 2), i32(size_y * 2), border_color)
		raylib.DrawRectangle(
			i32(cx - size_x + sw), i32(cy - size_y + sw),
			i32(size_x * 2 - sw * 2), i32(size_y * 2 - sw * 2),
			color,
		)
	} else if is_flying {
		if shadow_offset > 0 {
			v1s := raylib.Vector2{cx + shadow_offset, cy - size_y - 2 + shadow_offset}
			v2s := raylib.Vector2{cx - size_x - 2 + shadow_offset, cy + size_y + 2 + shadow_offset}
			v3s := raylib.Vector2{cx + size_x + 2 + shadow_offset, cy + size_y + 2 + shadow_offset}
			raylib.DrawTriangle(v1s, v2s, v3s, shadow_color)
		}
		v1 := raylib.Vector2{cx, cy - size_y}
		v2 := raylib.Vector2{cx - size_x, cy + size_y}
		v3 := raylib.Vector2{cx + size_x, cy + size_y}
		raylib.DrawTriangle(v1, v2, v3, color)
		raylib.DrawLineEx(v1, v2, sw, border_color)
		raylib.DrawLineEx(v2, v3, sw, border_color)
		raylib.DrawLineEx(v3, v1, sw, border_color)
	} else {
		if shadow_offset > 0 {
			raylib.DrawEllipse(i32(cx + shadow_offset), i32(cy + shadow_offset), size_x, size_y, shadow_color)
		}
		raylib.DrawEllipse(i32(cx), i32(cy), size_x, size_y, border_color)
		raylib.DrawEllipse(i32(cx), i32(cy), size_x - sw, size_y - sw, color)
	}

	// Plating ring — decorador aditivo (funciona sobre cualquier forma de base:
	// círculo, cuadrado de boss, triángulo de flying).
	if is_armored {
		raylib.DrawCircleLines(i32(cx), i32(cy), size + sw, constants.COLOR_ENEMY_ARMORED)
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

draw_tower_tile :: proc(
	x, y: f32,
	cs: f32,
	tower_type: constants.Tower_Type,
	angle: f32 = 0,
	is_ghost: bool = false,
	recoil: f32 = 0,
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
	raylib.DrawRectangleRoundedLinesEx(
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

	// Recoil: retrae el barril un poco en la dirección opuesta al disparo.
	// El MORTAR ignora `angle` y dispara siempre hacia arriba, así que su
	// recoil va derecho hacia abajo en vez de usar cos/sin(angle).
	recoil_dist := recoil * cs * constants.TOWER_RECOIL_DISTANCE_RATIO
	rcx, rcy := cx, cy
	if tower_type == .MORTAR {
		rcy = cy + recoil_dist
	} else {
		rcx = cx - math.cos(angle) * recoil_dist
		rcy = cy - math.sin(angle) * recoil_dist
	}

	// Draw tower components with shadows immediately after each component
	switch tower_type {
	case .LASER:   draw_tower_components_laser(rcx, rcy, cs, rotation, so, r)
	case .CANNON:  draw_tower_components_cannon(rcx, rcy, cs, rotation, so, r, stroke)
	case .SNIPER:  draw_tower_components_sniper(rcx, rcy, cs, rotation, so, r, stroke)
	case .MISSILE: draw_tower_components_missile(rcx, rcy, rotation, so, r)
	case .ARCHER:  draw_tower_components_archer(rcx, rcy, cs, rotation, so, recoil)
	case .ICE:     draw_tower_components_ice(cx, cy, cs, so, r)
	case .ENHANCE: draw_tower_components_enhance(cx, cy, cs, so, r)
	case .TESLA:   draw_tower_components_tesla(cx, cy, cs, so, r)
	case .MORTAR:  draw_tower_components_mortar(rcx, rcy, cs, so)
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

// Arco recurvo: dos brazos (spline cuadrático Bezier, control hacia adelante
// para el "bulge" característico del recurvo) unidos por una empuñadura
// central, más la cuerda entre las puntas. `recoil` (0..1, ver tower.recoil)
// tensa la cuerda hacia atrás — nocked/drawn look justo después de disparar.
// Coordenadas locales: adelante (hacia el objetivo) = -Y, igual convención
// que el resto de los barriles ("apunta hacia arriba antes de rotar");
// `rotation` ya viene como radianes (angle + PI/2, ver draw_tower_tile).
// Ballesta: riel recto (el "palito" original, DrawRectanglePro) + un arco
// perpendicular montado en la punta del riel, dibujado con
// DrawSplineSegmentBezierQuadratic (grip → control que bulge hacia adelante
// → punta). El arco no retrocede (eso ya lo hace el offset de recoil sobre
// cx,cy que aplica draw_tower_tile a todo el conjunto) — en cambio se
// "aplana": stretch anisotrópico centrado en el punto de montaje, ensancha
// en X (tips_w) y achica la profundidad en Y (bulge) a medida que crece el
// recoil, simulando el arco liberando tensión al disparar. Vuelve a su
// curva de descanso a medida que decae.
draw_tower_components_archer :: proc(cx, cy, cs, rotation, so: f32, recoil: f32 = 0) {
	rot_pt :: proc(cx, cy, lx, ly, rotation: f32) -> raylib.Vector2 {
		c, s := math.cos(rotation), math.sin(rotation)
		return {cx + lx * c - ly * s, cy + lx * s + ly * c}
	}

	// Riel (palito) — mismo rect que la versión original, pivot en el centro
	// de la torre, apunta hacia adelante (-Y local antes de rotar).
	rail_w := cs * 0.12
	rail_h := cs * 0.42
	rail_rect := raylib.Rectangle{x = cx + so, y = cy + so, width = rail_w, height = rail_h}
	rail_origin := raylib.Vector2{rail_w / 2, rail_h}
	rail_rotation_deg := rotation * 180.0 / math.PI
	raylib.DrawRectanglePro(rail_rect, rail_origin, rail_rotation_deg, constants.TOWER_SHADOW)
	rail_rect.x, rail_rect.y = cx, cy
	raylib.DrawRectanglePro(rail_rect, rail_origin, rail_rotation_deg, constants.TOWER_ARCHER_WOOD)

	// Arco montado cerca de la punta del riel. Stretch: ensancha en X,
	// aplana la profundidad del bulge en Y — todo relativo al mount point.
	mount        := raylib.Vector2{0, -cs * 0.30}
	stretch      := recoil * constants.TOWER_ARCHER_BOW_STRETCH
	sx           := 1 + stretch
	sy           := 1 - stretch
	tip_w        := cs * 0.26 * sx
	tip_forward  := cs * 0.04 * sy
	bulge_w      := cs * 0.16 * sx
	bulge_depth  := cs * 0.14 * sy

	tip_l   := raylib.Vector2{mount.x - tip_w, mount.y + tip_forward}
	tip_r   := raylib.Vector2{mount.x + tip_w, mount.y + tip_forward}
	bulge_l := raylib.Vector2{mount.x - bulge_w, mount.y - bulge_depth}
	bulge_r := raylib.Vector2{mount.x + bulge_w, mount.y - bulge_depth}

	limb_thick := max(1.5, cs * 0.045)
	string_thick := max(1.0, cs * 0.02)

	draw_limbs :: proc(cx, cy, rotation, thick: f32, mount, tip_l, tip_r, bulge_l, bulge_r: raylib.Vector2, color: raylib.Color, rot_pt: proc(f32, f32, f32, f32, f32) -> raylib.Vector2) {
		raylib.DrawSplineSegmentBezierQuadratic(
			rot_pt(cx, cy, mount.x, mount.y, rotation),
			rot_pt(cx, cy, bulge_l.x, bulge_l.y, rotation),
			rot_pt(cx, cy, tip_l.x, tip_l.y, rotation),
			thick, color,
		)
		raylib.DrawSplineSegmentBezierQuadratic(
			rot_pt(cx, cy, mount.x, mount.y, rotation),
			rot_pt(cx, cy, bulge_r.x, bulge_r.y, rotation),
			rot_pt(cx, cy, tip_r.x, tip_r.y, rotation),
			thick, color,
		)
	}

	// Sombra
	draw_limbs(cx + so, cy + so, rotation, limb_thick, mount, tip_l, tip_r, bulge_l, bulge_r, constants.TOWER_SHADOW, rot_pt)

	// Brazos del arco
	draw_limbs(cx, cy, rotation, limb_thick, mount, tip_l, tip_r, bulge_l, bulge_r, constants.TOWER_ARCHER_WOOD, rot_pt)

	// Cuerda — punta a punta, pasando por el mount point.
	// Color opaco propio: TOWER_SHADOW es casi transparente (alpha=30), pensado
	// para sombras, no serviría para una cuerda que tiene que verse tensa.
	string_color :: raylib.Color{230, 225, 210, 255}
	tip_l_w   := rot_pt(cx, cy, tip_l.x, tip_l.y, rotation)
	tip_r_w   := rot_pt(cx, cy, tip_r.x, tip_r.y, rotation)
	mount_w   := rot_pt(cx, cy, mount.x, mount.y, rotation)
	raylib.DrawLineEx(tip_l_w, mount_w, string_thick, string_color)
	raylib.DrawLineEx(mount_w, tip_r_w, string_thick, string_color)
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
	draw_tower_tile(x, y, cs, tower.type, tower.angle, false, tower.recoil)
}


// Versión 3D de render_reticle — mismos 4 brackets de esquina, acostados
// sobre el plano del suelo (XZ) en vez de en pantalla. `center` es el centro
// (X,Z) + altura de superficie (Y) del tile, ver tile_world_top.
render_reticle_3d :: proc(center: raylib.Vector3, color: raylib.Color) {
	cs := constants.WORLD_CELL_SIZE
	size := cs * 0.7
	len := cs * 0.15
	y := center.y + 0.02
	rx := center.x - size / 2
	rz := center.z - size / 2

	line :: proc(x1, z1, x2, z2, y: f32, color: raylib.Color) {
		raylib.DrawLine3D({x1, y, z1}, {x2, y, z2}, color)
	}

	// Top-left
	line(rx, rz, rx + len, rz, y, color)
	line(rx, rz, rx, rz + len, y, color)
	// Top-right
	line(rx + size - len, rz, rx + size, rz, y, color)
	line(rx + size, rz, rx + size, rz + len, y, color)
	// Bottom-left
	line(rx, rz + size - len, rx, rz + size, y, color)
	line(rx, rz + size, rx + len, rz + size, y, color)
	// Bottom-right
	line(rx + size, rz + size - len, rx + size, rz + size, y, color)
	line(rx + size - len, rz + size, rx + size, rz + size, y, color)
}


// =============================================================================
// Airdrop rendering
// =============================================================================

render_airdrops :: proc(app: ^entities.App_State) {
	if app.state != .PLAYING && app.state != .PAUSED { return }

	m := &app.editor.game_map

	// El sistema de airdrops sigue calculando sus posiciones en el espacio
	// 2D viejo (world px = tile*cell_size, ver airdrop_spawn en
	// simulation.odin) — nunca se migró a unidades de mundo 3D porque el
	// avión vuela en línea recta fuera del grid (no tiene sentido en
	// tiles). Acá se proyecta cada punto a 3D real (world 2D → Vector3 con
	// una altura fija de vuelo, reproyectado con GetWorldToScreen) en vez
	// de usar camera_offset_x/y — esa variable ya no se actualiza durante
	// PLAYING/EDITOR (la mueve camera_focus/camera3d, ver
	// input_handle_camera_3d), así que quedaba desincronizada del pan/zoom
	// real apenas el jugador movía la cámara.
	cs2d        := f32(app.settings.cell_size)
	scale_to_3d := constants.WORLD_CELL_SIZE / cs2d
	cs          := f32(app.settings.cell_size) * app.zoom  // tamaños en pantalla, sin cambios (ver damage numbers: misma heurística de font_size*zoom)

	// Altura fija de vuelo del avión en unidades de mundo 3D — no tiene
	// relación con el heightmap, el avión siempre pasa por encima del mapa.
	PLANE_ALTITUDE :: f32(3.0)

	project :: proc(app: ^entities.App_State, wx2d, wy2d, scale, altitude: f32) -> raylib.Vector2 {
		pos := raylib.Vector3{wx2d * scale, altitude, wy2d * scale}
		return raylib.GetWorldToScreen(pos, app.camera3d)
	}

	for &drop in app.sim.airdrops {
		// Posición en pantalla del tile destino — un solo raycast/proyección
		// reusado por todas las fases que anclan al tile (antes, caja, ping,
		// indicador de borde). tile_world_top ya da el punto sobre la
		// superficie real del terreno (heightmap incluido).
		target_center, _ := tile_world_top(m, drop.target_row, drop.target_col)
		target_screen := raylib.GetWorldToScreen(target_center, app.camera3d)

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
				s0 := project(app, p0.x, p0.y, scale_to_3d, PLANE_ALTITUDE)
				s1 := project(app, p1.x, p1.y, scale_to_3d, PLANE_ALTITUDE)
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

			// Helper: convierte coordenadas locales (en world units 2D) a
			// screen, proyectando por 3D real en vez de camera_offset_x/y.
			// lx = eje adelante/atrás, ly = eje izquierda/derecha
			to_s :: #force_inline proc(app: ^entities.App_State, pwx, pwy, lx, ly, cos_a, sin_a, scale, altitude: f32) -> raylib.Vector2 {
				wx := pwx + lx*cos_a - ly*sin_a
				wy := pwy + lx*sin_a + ly*cos_a
				return project(app, wx, wy, scale, altitude)
			}
			pwx := drop.plane_x
			pwy := drop.plane_y
			z   := app.zoom

			// ── Ala delta (triángulo: punta al frente, borde trasero ancho) ────
			//   Nose:    lx=+14,  ly=0
			//   L-trail: lx=-7,   ly=-11
			//   R-trail: lx=-7,   ly=+11
			v_nose  := to_s(app, pwx, pwy,  14,   0, cos_a, sin_a, scale_to_3d, PLANE_ALTITUDE)
			v_left  := to_s(app, pwx, pwy,  -7, -11, cos_a, sin_a, scale_to_3d, PLANE_ALTITUDE)
			v_right := to_s(app, pwx, pwy,  -7,  11, cos_a, sin_a, scale_to_3d, PLANE_ALTITUDE)
			// Raylib DrawTriangle: CCW en screen (y↓)
			raylib.DrawTriangle(v_nose, v_right, v_left, constants.COLOR_AIRDROP_PLANE)

			// ── Fuselaje (franja central estrecha) ─────────────────────────────
			ang_deg := angle * (180.0 / math.PI)
			body_w  := f32(28) * z
			body_h  := f32(4)  * z
			plane_screen := project(app, drop.plane_x, drop.plane_y, scale_to_3d, PLANE_ALTITUDE)
			raylib.DrawRectanglePro(
				{plane_screen.x, plane_screen.y, body_w, body_h},
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
				eng_screen := project(app, ecx, ecy, scale_to_3d, PLANE_ALTITUDE)
				raylib.DrawRectanglePro(
					{eng_screen.x, eng_screen.y, eng_w, eng_h},
					{eng_w / 2, eng_h / 2},
					ang_deg,
					raylib.Color{80, 80, 100, 255},
				)
				// Llama del motor (pequeño círculo naranja en la tobera)
				nozzle_cx := pwx + (-9)*cos_a - side*sin_a
				nozzle_cy := pwy + (-9)*sin_a + side*cos_a
				nozzle_screen := project(app, nozzle_cx, nozzle_cy, scale_to_3d, PLANE_ALTITUDE)
				raylib.DrawCircleV(
					nozzle_screen,
					f32(2.5) * z,
					raylib.Color{255, 140, 40, 200},
				)
			}

		case .BOX_FALLING:
			// Paracaídas: círculo encogiendo en el tile destino
			sx := target_screen.x
			sy := target_screen.y

			radius := drop.chute_t * constants.AIRDROP_CHUTE_RADIUS_MAX * cs
			if radius >= 1 {
				raylib.DrawCircleV({sx, sy}, radius, constants.COLOR_AIRDROP_CHUTE)
				raylib.DrawCircleLinesV({sx, sy}, radius, raylib.Color{200, 200, 200, 255})
			}

		case .BOX_LANDED:
			// La caja en sí ahora es geometría 3D real (ver render_airdrop_boxes_3d,
			// dibujada dentro de BeginMode3D junto con torres/árboles/enemigos) —
			// acá solo quedan los overlays 2D de "siempre visible en pantalla"
			// (ping, indicador de borde) más abajo.
		}

		// ── Ping convergente (siempre visible en pantalla) ─────────────────
		if (drop.phase == .BOX_FALLING || drop.phase == .BOX_LANDED) && drop.ping_t > 0 {
			raw_sx := target_screen.x
			raw_sy := target_screen.y
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
			sx := target_screen.x
			sy := target_screen.y
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

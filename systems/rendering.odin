package systems

import "../constants"
import "../entities"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "vendor:raylib"
import "vendor:raylib/rlgl"

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

// ── Shadow mapping (sombra proyectada real) ──────────────────────────────────
//
// Depth pre-pass desde el punto de vista del sol: se dibuja la escena (solo
// los casters — ver render_shadow_depth_pass) con un shader mínimo que
// únicamente escribe profundidad, a una textura de profundidad muestreable
// (no un RenderTexture2D común — ese trae un COLOR texture + un depth
// RENDERBUFFER, no muestreable como textura; hace falta el camino de bajo
// nivel de rlgl: LoadTextureDepth + LoadFramebuffer + FramebufferAttach).
// lighting.fs después muestrea esa textura (PCF manual, sin sampler de
// comparación por hardware en estos bindings) para saber si un fragmento
// está tapado del sol por otro objeto.
Shadow_Map :: struct {
	depth_shader: raylib.Shader,    // assets/shadow_depth.vs/.fs — solo posición, sin color
	fbo_id:       u32,
	depth_tex:    raylib.Texture2D, // wrapeado a mano desde rlgl.LoadTextureDepth
	view:         raylib.Matrix,    // recalculada cada frame en render_shadow_depth_pass
	proj:         raylib.Matrix,
	valid:        bool,             // false si el FBO no quedó completo — el juego sigue sin sombra en vez de crashear
}

shadow_map: Shadow_Map

shadow_map_init :: proc() {
	s := raylib.LoadShader("assets/shadow_depth.vs", "assets/shadow_depth.fs")
	shadow_map.depth_shader = s

	res := constants.SHADOW_MAP_RESOLUTION
	tex_id := rlgl.LoadTextureDepth(res, res, false)
	shadow_map.depth_tex = raylib.Texture2D{
		id       = tex_id,
		width    = res,
		height   = res,
		mipmaps  = 1,
		format   = .UNCOMPRESSED_R32, // cosmético — solo se usa el .id para bindear a mano, ver shadow_map_bind_for_sampling
	}

	shadow_map.fbo_id = rlgl.LoadFramebuffer()
	rlgl.EnableFramebuffer(shadow_map.fbo_id)
	rlgl.FramebufferAttach(shadow_map.fbo_id, tex_id, i32(rlgl.FramebufferAttachType.DEPTH), i32(rlgl.FramebufferAttachTextureType.TEXTURE2D), 0)
	ok := rlgl.FramebufferComplete(shadow_map.fbo_id)
	if !ok {
		fmt.println("WARNING: shadow map FBO incompleto — el juego sigue sin sombras proyectadas")
	}
	rlgl.DisableFramebuffer()
	shadow_map.valid = ok
}

shadow_map_unload :: proc() {
	raylib.UnloadShader(shadow_map.depth_shader)
	rlgl.UnloadTexture(shadow_map.depth_tex.id)
	rlgl.UnloadFramebuffer(shadow_map.fbo_id)
}

// ── Glow ring shader (anillos de spawn/goal-reach) ───────────────────────────
//
// Portado del viejo assets/glow_circle.glsl (2D, borrado en la migración a
// 3D) — ver draw_glow_ring_3d/render_glow_particles_3d. Anillo con falloff
// gaussiano, no un disco relleno como range_disc_shader.
glow_ring_shader: raylib.Shader

glow_ring_shader_init :: proc() {
	glow_ring_shader = raylib.LoadShader("assets/glow_ring.vs", "assets/glow_ring.fs")
}

glow_ring_shader_unload :: proc() {
	raylib.UnloadShader(glow_ring_shader)
}

// Quad chato sobre el plano XZ, UV (0,0)-(1,1) en las esquinas para que el
// fragment shader arme uv*2-1 ∈ [-1,1] y calcule el anillo centrado. Debe
// dibujarse dentro de un BeginShaderMode(glow_ring_shader) activo.
draw_glow_ring_3d :: proc(center: raylib.Vector3, radius: f32, color: raylib.Color) {
	half := radius * 2.2  // mismo factor que el viejo glow_circle.glsl (quad_half = radius*2.2)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	rlgl.TexCoord2f(0, 0); rlgl.Vertex3f(center.x - half, center.y, center.z - half)
	rlgl.TexCoord2f(0, 1); rlgl.Vertex3f(center.x - half, center.y, center.z + half)
	rlgl.TexCoord2f(1, 1); rlgl.Vertex3f(center.x + half, center.y, center.z + half)
	rlgl.TexCoord2f(1, 0); rlgl.Vertex3f(center.x + half, center.y, center.z - half)
	rlgl.End()
}

// ── Range disc shader (rango/AoE de torres, estado de enemigos, pulsos de
// hielo) ──────────────────────────────────────────────────────────────────
//
// Reemplaza a draw_ground_ring (DrawCircle3D — un anillo sin relleno, solo
// el contorno). Acá es un disco relleno con falloff invertido respecto de
// glow_ring: transparente en el centro, crece hacia el borde, con un
// corte nítido en el radio real en vez del difuminado a ambos lados de un
// glow típico.
range_disc_shader: raylib.Shader

range_disc_shader_init :: proc() {
	range_disc_shader = raylib.LoadShader("assets/range_disc.vs", "assets/range_disc.fs")
}

range_disc_shader_unload :: proc() {
	raylib.UnloadShader(range_disc_shader)
}

// ── Spawn/goal shader (marca de dónde aparecen y a dónde llegan los
// enemigos) ──────────────────────────────────────────────────────────────
//
// Reemplaza al viejo DrawCylinder plano de color sólido (render_spawn_3d/
// render_goal_3d, eliminadas). Reusa la geometría de draw_range_disc_3d
// (mismo quad+shader teselado por tile, siguiendo la altura real de la
// malla — ver el comentario ahí) con un shader propio en vez de
// range_disc_shader: acá es un disco relleno PAREJO (no crece desde el
// centro) con un pulso suave de intensidad en el tiempo, no un falloff de
// radio — es una marca de lugar fija, no un área de efecto.
spawn_goal_shader: raylib.Shader
spawn_goal_shader_loc_pulse_time: i32
spawn_goal_anim_time: f32

spawn_goal_shader_init :: proc() {
	spawn_goal_shader = raylib.LoadShader("assets/spawn_goal.vs", "assets/spawn_goal.fs")
	spawn_goal_shader_loc_pulse_time = raylib.GetShaderLocation(spawn_goal_shader, "pulseTime")
}

spawn_goal_shader_unload :: proc() {
	raylib.UnloadShader(spawn_goal_shader)
}

// ── Shader de la grilla del editor (shimmer sutil) ───────────────────────
//
// render_grid_lines_3d dibujaba las líneas con color plano fijo
// (constants.COLOR_GRID_LINE) vía raylib.DrawLine3D. Este shader le suma
// un ruido de brillo de alta frecuencia espacial con deriva lenta en el
// tiempo — ver grid_line.fs para por qué el value noise ya sale "suave"
// sin un blur aparte.
grid_line_shader: raylib.Shader
grid_line_shader_loc_noise_time: i32
grid_line_anim_time: f32

grid_line_shader_init :: proc() {
	grid_line_shader = raylib.LoadShader("assets/grid_line.vs", "assets/grid_line.fs")
	grid_line_shader_loc_noise_time = raylib.GetShaderLocation(grid_line_shader, "gridNoiseTime")
}

grid_line_shader_unload :: proc() {
	raylib.UnloadShader(grid_line_shader)
}

// Radio de la marca — mismo 0.4*cs que tenía el cilindro viejo, para no
// cambiar el tamaño visual de golpe.
SPAWN_GOAL_MARKER_RADIUS_RATIO :: f32(0.4)

render_spawn_goal_markers_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	frame_dt := min(raylib.GetFrameTime(), constants.WATER_ANIM_MAX_DT)
	spawn_goal_anim_time += frame_dt * constants.SPAWN_GOAL_PULSE_SPEED
	raylib.SetShaderValue(spawn_goal_shader, spawn_goal_shader_loc_pulse_time, &spawn_goal_anim_time, .FLOAT)

	cs := constants.WORLD_CELL_SIZE
	raylib.BeginShaderMode(spawn_goal_shader)
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			tile := m.grid[row][col]
			if tile != .SPAWN && tile != .GOAL { continue }
			color := constants.COLOR_SPAWN if tile == .SPAWN else constants.COLOR_GOAL
			center, _ := tile_world_top(m, row, col)
			ring := raylib.Vector3{center.x, 0.02, center.z}
			draw_range_disc_3d(m, ring, cs * SPAWN_GOAL_MARKER_RADIUS_RATIO, color)
		}
	}
	raylib.EndShaderMode()
}

// El terreno NO es un plano ni siquiera un escalón por tile: cada tile de
// la malla real está subdividido (TERRAIN_MESH_SUBDIV) e interpolado
// bilinealmente entre esquinas promediadas con los vecinos, más el
// hundimiento del camino (ver terrain_surface_height / terrain_cache_ensure)
// — hay pendientes suaves DENTRO de un mismo tile, no solo entre tiles.
// Un quad flotando a la altura cruda de tile_world_top (sin promediar, sin
// hundimiento) queda por encima o por debajo de esa superficie real, así
// que el disco se veía "cortado" contra el terreno en cualquier pendiente
// o borde de camino. La solución: teselar a la MISMA densidad que el mesh
// real (un sub-quad por celda de TERRAIN_MESH_SUBDIV) y samplear
// terrain_surface_height en cada vértice — igual que las sombras reales
// (shadow map) se resuelven contra la geometría real en vez de un plano
// fijo. El UV de cada vértice se calcula en espacio de mundo relativo a
// center/radius (no 0..1 por sub-quad) para que el falloff del shader
// quede continuo en todo el disco, no en mosaico. La geometría es
// agnóstica del shader que la pinta — hay que dibujarla dentro de un
// BeginShaderMode activo (range_disc_shader para rango/AoE/estado de
// enemigos/pulsos de hielo, spawn_goal_shader para las marcas de
// spawn/goal — ver render_spawn_goal_markers_3d).
draw_range_disc_3d :: proc(m: ^entities.Map, center: raylib.Vector3, radius: f32, color: raylib.Color) {
	cs := constants.WORLD_CELL_SIZE
	col_min := max(i32(math.floor((center.x - radius) / cs)), 0)
	col_max := min(i32(math.floor((center.x + radius) / cs)), m.width - 1)
	row_min := max(i32(math.floor((center.z - radius) / cs)), 0)
	row_max := min(i32(math.floor((center.z + radius) / cs)), m.height - 1)

	SUBDIV :: constants.TERRAIN_MESH_SUBDIV
	step := f32(1) / f32(SUBDIV)

	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for row in row_min ..= row_max {
		for col in col_min ..= col_max {
			for sr in 0 ..< SUBDIV {
				for sc in 0 ..< SUBDIV {
					u0, u1 := f32(sc) * step, f32(sc + 1) * step
					v0, v1 := f32(sr) * step, f32(sr + 1) * step
					x0, x1 := f32(col) * cs + u0 * cs, f32(col) * cs + u1 * cs
					z0, z1 := f32(row) * cs + v0 * cs, f32(row) * cs + v1 * cs
					y00 := terrain_surface_height(m, row, col, u0, v0) + center.y
					y01 := terrain_surface_height(m, row, col, u0, v1) + center.y
					y11 := terrain_surface_height(m, row, col, u1, v1) + center.y
					y10 := terrain_surface_height(m, row, col, u1, v0) + center.y
					tu0, tv0 := (x0-center.x)/radius*0.5+0.5, (z0-center.z)/radius*0.5+0.5
					tu1, tv1 := (x1-center.x)/radius*0.5+0.5, (z1-center.z)/radius*0.5+0.5
					rlgl.TexCoord2f(tu0, tv0); rlgl.Vertex3f(x0, y00, z0)
					rlgl.TexCoord2f(tu0, tv1); rlgl.Vertex3f(x0, y01, z1)
					rlgl.TexCoord2f(tu1, tv1); rlgl.Vertex3f(x1, y11, z1)
					rlgl.TexCoord2f(tu1, tv0); rlgl.Vertex3f(x1, y10, z0)
				}
			}
		}
	}
	rlgl.End()
}

// Sube lightSpaceMatrix + bindea shadow_map.depth_tex como sampler2D en
// lighting_shader. shadow_map.depth_tex NO es parte de un Material (no
// hay Model/Mesh detrás, es una textura suelta) — raylib.SetShaderValueTexture
// no sirve para este caso (ver la trampa documentada en CLAUDE.md sobre
// colisión de texture units con el material del terreno). El patrón
// correcto, calcado del ejemplo oficial de raylib (shaders_shadowmap.c):
// elegir un texture unit propio y fijo, bindear la textura ahí con
// rlgl.ActiveTextureSlot/EnableTexture, y subir el UNIFORM SAMPLER2D como
// un entero (el índice de unidad), no como una Texture2D.
shadow_map_bind_for_sampling :: proc() {
	// proj*view, NO view*proj — para transformar un punto mundo hay que
	// aplicar view PRIMERO (mundo→vista) y proj DESPUÉS (vista→clip):
	// (proj*view)*p = proj*(view*p). El orden contrario aplicaba proj a
	// coordenadas de mundo directamente, lo cual no tiene sentido — daba
	// un clip.z gigante y fuera de [-1,1] para TODO fragmento, sin
	// importar dónde estuviera parado. Verificado a mano con un caso real
	// (ver CLAUDE.md, sección de shadow mapping) antes de aplicar el fix.
	light_space := shadow_map.proj * shadow_map.view
	raylib.SetShaderValueMatrix(lighting_shader.shader, lighting_shader.loc_light_space_matrix, light_space)
	raylib.SetShaderValueMatrix(tree_shader.shader, tree_shader.loc_light_space_matrix, light_space)

	slot := constants.SHADOW_MAP_TEXTURE_SLOT
	rlgl.ActiveTextureSlot(slot)
	rlgl.EnableTexture(shadow_map.depth_tex.id)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_shadow_map, &slot, .INT)
	raylib.SetShaderValue(tree_shader.shader, tree_shader.loc_shadow_map, &slot, .INT)
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

// Construye una Camera3D a partir de un foco (punto de mundo mirado), un
// zoom y un yaw (rotación alrededor del foco, radianes) — ángulo de
// inclinación fijo (CAMERA_PITCH_DEG), solo el yaw gira la vista alrededor
// del eje Y. zoom alto = cámara más cerca (ver
// constants.camera_distance_from_zoom). En yaw=0 da exactamente la misma
// posición que la cámara fija de antes (sin(0)=0, cos(0)=1).
camera3d_for_focus :: proc(focus: raylib.Vector3, zoom: f32, yaw: f32) -> raylib.Camera3D {
	pitch_rad := constants.CAMERA_PITCH_DEG * math.RAD_PER_DEG
	dist := constants.camera_distance_from_zoom(zoom)
	horizontal_dist := dist * math.cos(pitch_rad)
	offset := raylib.Vector3{
		horizontal_dist * math.sin(yaw),
		dist * math.sin(pitch_rad),
		horizontal_dist * math.cos(yaw),
	}
	return raylib.Camera3D{
		position   = focus + offset,
		target     = focus,
		up         = {0, 1, 0},
		fovy       = constants.CAMERA_FOVY,
		projection = .PERSPECTIVE,
	}
}

// Deriva app.camera3d a partir del estado actual de app.camera_focus/zoom/yaw —
// llamar una vez por frame antes de dibujar/pickear el mundo 3D.
update_camera3d :: proc(app: ^entities.App_State) {
	app.camera3d = camera3d_for_focus(app.camera_focus, app.zoom, app.camera_yaw)
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
	loc_view_dir:    i32,  // uniform por frame, la cámara rota — ver render_map_3d
	loc_specular_strength: i32,  // 0 por defecto; bracket puntual alrededor del draw de torres
	loc_use_mask:    i32,  // 1.0 solo mientras se dibuja el terreno (ver render_map_3d)
	loc_path_color:  i32,
	loc_path_emboss_depth: i32,  // profundidad fija del hundimiento — ver PATH_EMBOSS_DEPTH
	loc_path_mask_texel:   i32,  // tamaño de un texel de la máscara de camino, para el gradiente central en el VS
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
	loc_light_space_matrix: i32,  // sombra proyectada real — ver render_shadow_depth_pass
	loc_shadow_map:         i32,
	loc_shadow_bias:        i32,  // fijo, seteado una vez en init desde constants.SHADOW_DEPTH_BIAS
	loc_shadow_min_factor:  i32,  // idem, constants.SHADOW_MIN_FACTOR
	dune_anim_time:     f32,  // acumulado con dt clampeado, no reloj de pared — ver render_map_3d
	caustics_anim_time: f32,
	grass_anim_time:    f32,
	day_night_anim_time: f32,  // idem, gateado a app.state == .PLAYING — ver render_map_3d
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
		loc_view_dir     = raylib.GetShaderLocation(s, "viewDir"),
		loc_specular_strength = raylib.GetShaderLocation(s, "specularStrength"),
		loc_use_mask     = raylib.GetShaderLocation(s, "useTerrainMask"),
		loc_path_color   = raylib.GetShaderLocation(s, "pathColor"),
		loc_path_emboss_depth = raylib.GetShaderLocation(s, "pathEmbossDepth"),
		loc_path_mask_texel   = raylib.GetShaderLocation(s, "pathMaskTexel"),
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
		loc_light_space_matrix = raylib.GetShaderLocation(s, "lightSpaceMatrix"),
		loc_shadow_map          = raylib.GetShaderLocation(s, "shadowMap"),
		loc_shadow_bias         = raylib.GetShaderLocation(s, "shadowDepthBias"),
		loc_shadow_min_factor   = raylib.GetShaderLocation(s, "shadowMinFactor"),
	}

	// Luz "sol" alineada con el ángulo de la cámara isométrica (arriba-
	// adelante), luz de relleno tenue del lado opuesto para que las caras en
	// sombra no queden negro puro. Direccionales, fijas — no cambian en
	// runtime. Valores centralizados en constants.odin (LIGHT_*) — ver esa
	// sección para la disciplina de "sumar ~1.0 en la cara mejor iluminada".
	sun_dir := linalg.normalize(constants.LIGHT_SUN_DIR)
	sun_color := constants.LIGHT_SUN_COLOR
	fill_dir := linalg.normalize(constants.LIGHT_FILL_DIR)
	fill_color := constants.LIGHT_FILL_COLOR
	ambient := constants.LIGHT_AMBIENT

	raylib.SetShaderValue(s, lighting_shader.loc_sun_dir, &sun_dir, .VEC3)
	raylib.SetShaderValue(s, lighting_shader.loc_sun_color, &sun_color, .VEC3)
	raylib.SetShaderValue(s, lighting_shader.loc_fill_dir, &fill_dir, .VEC3)
	raylib.SetShaderValue(s, lighting_shader.loc_fill_color, &fill_color, .VEC3)
	raylib.SetShaderValue(s, lighting_shader.loc_ambient, &ambient, .VEC3)

	// viewDir ya NO se sube acá — la cámara ahora rota (botón central +
	// drag), así que dejó de ser una constante. Se recalcula cada frame en
	// render_map_3d a partir de app.camera3d. loc_view_dir queda resuelto
	// acá igual, solo se movió la subida del valor.

	// Apagado por defecto — solo se prende puntualmente alrededor del draw
	// de torres (ver render_map_objects_3d). El agua tiene su propio
	// multiplicador fijo dentro del shader (SPECULAR_STRENGTH_WATER).
	specular_off := f32(0)
	raylib.SetShaderValue(s, lighting_shader.loc_specular_strength, &specular_off, .FLOAT)

	// Sombra proyectada real — bias/piso fijos, ajustables sin tocar el
	// .fs (ver constants.SHADOW_DEPTH_BIAS/SHADOW_MIN_FACTOR).
	shadow_bias := constants.SHADOW_DEPTH_BIAS
	shadow_min_factor := constants.SHADOW_MIN_FACTOR
	raylib.SetShaderValue(s, lighting_shader.loc_shadow_bias, &shadow_bias, .FLOAT)
	raylib.SetShaderValue(s, lighting_shader.loc_shadow_min_factor, &shadow_min_factor, .FLOAT)

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

	// Profundidad del hundimiento del camino — fija, no depende del mapa
	// (a diferencia de pathMaskTexel, que sí depende del tamaño del mapa y
	// se setea en terrain_cache_ensure).
	emboss_depth := constants.PATH_EMBOSS_DEPTH
	raylib.SetShaderValue(s, lighting_shader.loc_path_emboss_depth, &emboss_depth, .FLOAT)
}

lighting_shader_unload :: proc() {
	raylib.UnloadShader(lighting_shader.shader)
}

// ── Shader de modelos reales (árboles importados) ────────────────────────
//
// lighting_shader asume todo en espacio de mundo (torres/enemigos/etc. se
// arman a mano vértice por vértice, ya ubicados) — no tiene matModel ni
// sampling de textura difusa real, porque nunca le hizo falta. Un modelo
// real (con su propia malla, UVs y normales, rotado/escalado por
// instancia vía DrawModelEx) sí necesita las dos cosas, así que en vez de
// forzarlo adentro de lighting_shader (arriesgando romper el resto del
// terreno/formas inmediatas que ya dependen de ese shader) es un shader
// aparte — mismo sol/fill/ambient/sombra, ver tree.fs.
Tree_Shader :: struct {
	shader:                 raylib.Shader,
	loc_sun_dir:            i32,
	loc_sun_color:          i32,
	loc_fill_dir:           i32,
	loc_fill_color:         i32,
	loc_ambient:            i32,
	loc_light_space_matrix: i32,
	loc_shadow_map:         i32,
	loc_shadow_bias:        i32,
	loc_shadow_min_factor:  i32,
}

tree_shader: Tree_Shader

tree_shader_init :: proc() {
	s := raylib.LoadShader("assets/tree.vs", "assets/tree.fs")
	tree_shader = Tree_Shader{
		shader                 = s,
		loc_sun_dir            = raylib.GetShaderLocation(s, "sunDir"),
		loc_sun_color          = raylib.GetShaderLocation(s, "sunColor"),
		loc_fill_dir           = raylib.GetShaderLocation(s, "fillDir"),
		loc_fill_color         = raylib.GetShaderLocation(s, "fillColor"),
		loc_ambient            = raylib.GetShaderLocation(s, "ambient"),
		loc_light_space_matrix = raylib.GetShaderLocation(s, "lightSpaceMatrix"),
		loc_shadow_map         = raylib.GetShaderLocation(s, "shadowMap"),
		loc_shadow_bias        = raylib.GetShaderLocation(s, "shadowDepthBias"),
		loc_shadow_min_factor  = raylib.GetShaderLocation(s, "shadowMinFactor"),
	}

	sun_dir := linalg.normalize(constants.LIGHT_SUN_DIR)
	sun_color := constants.LIGHT_SUN_COLOR
	fill_dir := linalg.normalize(constants.LIGHT_FILL_DIR)
	fill_color := constants.LIGHT_FILL_COLOR
	ambient := constants.LIGHT_AMBIENT
	raylib.SetShaderValue(s, tree_shader.loc_sun_dir, &sun_dir, .VEC3)
	raylib.SetShaderValue(s, tree_shader.loc_sun_color, &sun_color, .VEC3)
	raylib.SetShaderValue(s, tree_shader.loc_fill_dir, &fill_dir, .VEC3)
	raylib.SetShaderValue(s, tree_shader.loc_fill_color, &fill_color, .VEC3)
	raylib.SetShaderValue(s, tree_shader.loc_ambient, &ambient, .VEC3)

	shadow_bias := constants.SHADOW_DEPTH_BIAS
	shadow_min_factor := constants.SHADOW_MIN_FACTOR
	raylib.SetShaderValue(s, tree_shader.loc_shadow_bias, &shadow_bias, .FLOAT)
	raylib.SetShaderValue(s, tree_shader.loc_shadow_min_factor, &shadow_min_factor, .FLOAT)
}

tree_shader_unload :: proc() {
	raylib.UnloadShader(tree_shader.shader)
}

// Un modelo real por bioma, cargado una sola vez (LoadModel resuelve las
// texturas del .mtl solo, relativas a la carpeta del .obj). `needs_z_up_fix`
// queda como mecanismo general por si algún asset futuro viene Z-up (ver
// _fix_model_z_up) — los 4 modelos actuales, modelados en Blender para este
// proyecto, ya se exportan Y-up con base en y=0, así que ninguno lo usa hoy.
// `scale` corrige la escala de diseño (ajena a WORLD_CELL_SIZE = 1) una sola
// vez acá, no en cada draw.
Tree_Model :: struct {
	model: raylib.Model,
	scale: f32,
}

tree_models: [constants.Biome]Tree_Model

Tree_Model_Spec :: struct {
	path:           cstring,
	scale:          f32,
	needs_z_up_fix: bool,
}

// Modelos propios, modelados en Blender (color plano, sin texturas) para
// esta run — reemplazan los 4 assets de terceros que había antes (uno de
// ellos, el de MOUNTAIN, era directamente un llavero decorativo sin
// textura de 107k triángulos, ver el commit anterior a este). Todos se
// construyeron ya Y-up (base en y=0, centrados en x=0/z=0) usando el
// exportador de Blender con forward_axis='NEGATIVE_Z'/up_axis='Y', así que
// ninguno necesita needs_z_up_fix. Escalas calculadas a mano desde el
// bounding box real reportado por Blender al exportar, mismo criterio que
// ya usaba este archivo: altura_blender_z medida, scale = 0.85 /
// altura_blender_z para que el árbol quede en el mismo orden que el cono
// procedural viejo (~0.85 unidades de mundo).
TREE_MODEL_SPECS := [constants.Biome]Tree_Model_Spec{
	// plain_tree.obj: tronco + 3 icosferas solapadas, altura Blender 1.0600.
	.PLAIN    = {"models/tree/plain_tree.obj", 0.85 / 1.0600, false},
	// forest_pine.obj: tronco fino + 4 conos apilados, altura Blender 1.3000.
	.FOREST   = {"models/pine/forest_pine.obj", 0.85 / 1.3000, false},
	// desert_palm.obj: tronco de 5 segmentos + 8 palmas curvas (ancho
	// variable, caída progresiva, nervadura central — reconstruidas tras un
	// primer intento con cajas rígidas que leía como "estrella"), altura
	// Blender 1.3883.
	.DESERT   = {"models/palm/desert_palm.obj", 0.85 / 1.3883, false},
	// mountain_bush.obj: 6 icosferas achaparradas sin tronco, altura Blender
	// 0.6800 — target de altura en mundo más bajo que los demás (0.45 en vez
	// de 0.85) a propósito: es un arbusto, no un árbol de tamaño completo.
	.MOUNTAIN = {"models/bush/mountain_bush.obj", 0.45 / 0.6800, false},
}

// Corrige un mesh Z-up a Y-up rotando vértices/normales A MANO —
// (x,y,z) -> (x,z,-y), derivado directo de RotateX(-90°) sobre las
// fórmulas de rotación (newY = y·cos θ − z·sin θ, newZ = y·sin θ + z·cos θ,
// con θ=−90°) en vez de armar una Matrix: raylib.odin no trae las
// funciones de raymath.h (MatrixRotate/MatrixMultiply no están
// bindeadas), y mezclar a mano una matrix `#row_major` de raylib con las
// de `core:math/linalg` (convención de columna) es terreno fácil para
// terminar con una rotación transpuesta sin darse cuenta — esto evita el
// problema de raíz. Se hace UNA sola vez al cargar, contra los datos CPU
// del mesh (LoadModel ya los subió a GPU), así que hace falta
// UpdateMeshBuffer después o la corrección se queda solo en CPU y el
// modelo se ve exactamente igual que antes.
_fix_model_z_up :: proc(model: raylib.Model) {
	for i in 0 ..< int(model.meshCount) {
		mesh := &model.meshes[i]
		n := int(mesh.vertexCount)
		for v in 0 ..< n {
			y := mesh.vertices[v * 3 + 1]
			z := mesh.vertices[v * 3 + 2]
			mesh.vertices[v * 3 + 1] = z
			mesh.vertices[v * 3 + 2] = -y
			if mesh.normals != nil {
				ny := mesh.normals[v * 3 + 1]
				nz := mesh.normals[v * 3 + 2]
				mesh.normals[v * 3 + 1] = nz
				mesh.normals[v * 3 + 2] = -ny
			}
		}
		buf_size := i32(n) * 3 * size_of(f32)
		raylib.UpdateMeshBuffer(mesh^, 0, mesh.vertices, buf_size, 0)
		if mesh.normals != nil {
			raylib.UpdateMeshBuffer(mesh^, 2, mesh.normals, buf_size, 0)
		}
	}
}

tree_models_init :: proc() {
	for biome in constants.Biome {
		spec := TREE_MODEL_SPECS[biome]
		model := raylib.LoadModel(spec.path)
		if spec.needs_z_up_fix {
			_fix_model_z_up(model)
		}
		for i in 0 ..< int(model.materialCount) {
			model.materials[i].shader = tree_shader.shader
		}
		tree_models[biome] = Tree_Model{
			model = model,
			scale = spec.scale,
		}
	}
}

tree_models_unload :: proc() {
	for biome in constants.Biome {
		raylib.UnloadModel(tree_models[biome].model)
	}
}

// Nenúfares reales — mismo mecanismo que tree_models (Tree_Model/tree_shader
// reusados tal cual, ver render_water_lily_3d), dos variantes en vez de una
// por bioma: PAD (disco solo) y PAD_FLOWER (disco + rosetón de pétalos),
// para preservar el 50% de chance de flor por pad que ya tenía la versión
// procedural vieja. Ambos modelados con radio=1.0 unidad Blender por
// diseño (`scale = 1.0` acá abajo, sin necesidad de medir bounding box) —
// el radio final en pantalla sale de escalar uniformemente por `pr` (el
// radio real 0.09..0.16*cs que ya sorteaba render_water_lily_3d), no de
// este spec.
Lily_Model_Kind :: enum {
	PAD,
	PAD_FLOWER,
}

lily_models: [Lily_Model_Kind]Tree_Model

LILY_MODEL_SPECS := [Lily_Model_Kind]Tree_Model_Spec{
	.PAD        = {"models/waterlily/lily_pad.obj", 1.0, false},
	.PAD_FLOWER = {"models/waterlily/lily_pad_flower.obj", 1.0, false},
}

lily_models_init :: proc() {
	for kind in Lily_Model_Kind {
		spec := LILY_MODEL_SPECS[kind]
		model := raylib.LoadModel(spec.path)
		for i in 0 ..< int(model.materialCount) {
			model.materials[i].shader = tree_shader.shader
		}
		lily_models[kind] = Tree_Model{
			model = model,
			scale = spec.scale,
		}
	}
}

lily_models_unload :: proc() {
	for kind in Lily_Model_Kind {
		raylib.UnloadModel(lily_models[kind].model)
	}
}

// Casas/rocas por bioma para ACCESSORY_BLOCK — mismo mecanismo que
// tree_models (Tree_Model/tree_shader reusados tal cual). Reemplazan al
// cubo genérico que dibujaba antes render_block_3d. MOUNTAIN no es una
// casa (el ícono 2D de referencia, render_block más abajo en este mismo
// archivo, ya lo dibuja como rocas, no como construcción) — un cluster de
// rocas angulares en vez de una cuarta casa, a pedido explícito.
BLOCK_MODEL_SPECS := [constants.Biome]Tree_Model_Spec{
	// plain_house.obj: paredes + techo a dos aguas terracota + chimenea,
	// altura Blender 0.5600.
	.PLAIN    = {"models/house_plain/plain_house.obj", 0.35 / 0.5600, false},
	// forest_cabin.obj: mismo esquema, madera oscura + techo más oscuro,
	// altura Blender 0.5200.
	.FOREST   = {"models/house_forest/forest_cabin.obj", 0.35 / 0.5200, false},
	// desert_adobe.obj: bloque bajo + anexo asimétrico, techo plano. A
	// diferencia de las demás, esta NO escala por altura (0.2200, muy baja
	// por diseño — es una construcción chata de adobe) sino por ANCHO
	// (footprint Blender X 0.6400) igualado al ancho final que ya dan
	// PLAIN/FOREST tras su propio scale (~0.379) — escalar por altura como
	// las demás inflaba el ancho final a ~0.95 (2.5x más ancha que el
	// resto) porque el adobe es mucho más ancho que alto en su diseño
	// original. Resultado: mismo footprint que el resto, más baja (según
	// corresponde a su diseño), en vez de mismo alto y desproporcionada.
	.DESERT   = {"models/house_desert/desert_adobe.obj", 0.379 / 0.6400, false},
	// mountain_rocks.obj: 2 rocas angulares (polígonos irregulares
	// ahusados), altura Blender 0.2993.
	.MOUNTAIN = {"models/rocks_mountain/mountain_rocks.obj", 0.35 / 0.2993, false},
}

block_models: [constants.Biome]Tree_Model

block_models_init :: proc() {
	for biome in constants.Biome {
		spec := BLOCK_MODEL_SPECS[biome]
		model := raylib.LoadModel(spec.path)
		for i in 0 ..< int(model.materialCount) {
			model.materials[i].shader = tree_shader.shader
		}
		block_models[biome] = Tree_Model{
			model = model,
			scale = spec.scale,
		}
	}
}

block_models_unload :: proc() {
	for biome in constants.Biome {
		raylib.UnloadModel(block_models[biome].model)
	}
}

// Caja de madera del airdrop (reemplaza el DrawCube liso), avión F-16
// (reemplaza el dibujo 2D en pantalla), y las dos piezas modulares del
// puente colgante (tablón de piso + baranda con cables) — mismo mecanismo
// que tree_models/block_models (Tree_Model/tree_shader reusados).
CRATE_MODEL_SPEC := Tree_Model_Spec{"models/crate/wooden_crate.obj", 0.5 / 1.0050, false}
crate_model: Tree_Model

// Largo objetivo 1.3 unidades de mundo (un poco más de un tile) — un
// avión chico pero imponente sobrevolando el mapa. Nariz en eje local +X
// (ver tree_tile_offset/block_tile_yaw para el mismo criterio de
// convención de ángulos — acá el yaw sale de airdrop_plane_yaw_deg).
PLANE_MODEL_SPEC := Tree_Model_Spec{"models/plane/cargo_plane.obj", 1.3 / 1.0600, false}
plane_model: Tree_Model

// Tablón: pieza de 1×1 (footprint) × 0.108 (espesor) — el código la
// escala NO uniforme en X/Z según el tramo de camino que tenga que cubrir
// (igual criterio que ya usaba el DrawCube que reemplaza), dejando la
// superficie de arriba plana para que el escalado no la deforme.
BRIDGE_DECK_MODEL_SPEC := Tree_Model_Spec{"models/bridge/deck_plank.obj", 1.0, false}
bridge_deck_model: Tree_Model

// Baranda colgante (postes + cable principal en catenaria + suspensores) —
// ancho de referencia real 1.06 (no exactamente 1.0, la curva del cable se
// pasa un poco de los postes), profundidad 0.06, altura 1.0. El código
// sigue escalando cada eje por separado, como con el tablón.
BRIDGE_RAILING_MODEL_SPEC := Tree_Model_Spec{"models/bridge/railing.obj", 1.0, false}
bridge_railing_model: Tree_Model

crate_model_init :: proc() {
	spec := CRATE_MODEL_SPEC
	model := raylib.LoadModel(spec.path)
	for i in 0 ..< int(model.materialCount) {
		model.materials[i].shader = tree_shader.shader
	}
	crate_model = Tree_Model{model = model, scale = spec.scale}
}
crate_model_unload :: proc() { raylib.UnloadModel(crate_model.model) }

plane_model_init :: proc() {
	spec := PLANE_MODEL_SPEC
	model := raylib.LoadModel(spec.path)
	for i in 0 ..< int(model.materialCount) {
		model.materials[i].shader = tree_shader.shader
	}
	plane_model = Tree_Model{model = model, scale = spec.scale}
}
plane_model_unload :: proc() { raylib.UnloadModel(plane_model.model) }

bridge_models_init :: proc() {
	deck_spec := BRIDGE_DECK_MODEL_SPEC
	deck := raylib.LoadModel(deck_spec.path)
	for i in 0 ..< int(deck.materialCount) {
		deck.materials[i].shader = tree_shader.shader
	}
	bridge_deck_model = Tree_Model{model = deck, scale = deck_spec.scale}

	rail_spec := BRIDGE_RAILING_MODEL_SPEC
	rail := raylib.LoadModel(rail_spec.path)
	for i in 0 ..< int(rail.materialCount) {
		rail.materials[i].shader = tree_shader.shader
	}
	bridge_railing_model = Tree_Model{model = rail, scale = rail_spec.scale}
}
bridge_models_unload :: proc() {
	raylib.UnloadModel(bridge_deck_model.model)
	raylib.UnloadModel(bridge_railing_model.model)
}

// Multiplicador de escala por nivel de obstáculo (1-3) — mismo ratio que
// ya usaba el cubo genérico viejo (`h := cs*(0.35 + (lvl-1)*0.15)`),
// normalizado contra el nivel 1 (que es la altura de referencia de
// BLOCK_MODEL_SPECS): nivel 2 queda ~1.43x más grande que nivel 1, nivel 3
// ~1.86x — escala el modelo ENTERO (no solo la altura como hacía el
// cubo), así que en nivel 3 la casa también se ve más ancha/imponente,
// no solo más alta.
block_level_scale :: proc(level: i32) -> f32 {
	lvl := clamp(level, 1, 3)
	return (0.35 + f32(lvl - 1) * 0.15) / 0.35
}

// ── Malla cacheada del terreno (plano continuo, desniveles diagonales) ─────
// Se construye una sola vez por run (invalidada en simulation_fit_camera):
// una grilla de (width+1)×(height+1) vértices — un vértice por esquina
// compartida entre hasta 4 tiles — en vez de una caja por tile. La diagonal
// del desnivel sale sola: si dos tiles vecinos tienen distinta altura, la
// arista que comparten interpola linealmente entre ambas.
//
// El camino se resuelve con una textura-máscara supersampleada (varios
// texels por tile, filtro BILINEAR, ver _path_strip_mask) sampleada tanto en
// el vertex shader (hunde el terreno en una franja angosta — "embossed",
// PATH_EMBOSS_DEPTH) como en el fragment shader (pathColor, mix con el color
// de bioma). El mismo dato sirve para las dos cosas: dónde pintar y cuánto
// hundir son literalmente el mismo valor [0,1].
Terrain_Cache :: struct {
	model:          raylib.Model,
	path_mask_tex:  raylib.Texture2D,
	water_mask_tex: raylib.Texture2D,
	foam_mask_tex:  raylib.Texture2D, // supersampleada + mipmaps, ver foamMask en lighting.fs
	valid:          bool,

	// Copia CPU de los mismos pixeles (post-blur) subidos a path_mask_tex —
	// draw_range_disc_3d la usa para calcular la altura EXACTA que dibuja
	// lighting.vs (bilinear + blur en cruz incluidos), en vez de recalcular
	// _path_strip_mask analítico (que no tiene el blur y difiere justo en
	// bordes/uniones de camino, donde el min() entre brazos deja una cresta
	// dura — ver terrain_cache_ensure). Vive y muere con el resto del cache.
	path_mask_cpu: []u8,
	path_mask_w:   i32,
	path_mask_h:   i32,
}

terrain_cache: Terrain_Cache

terrain_cache_invalidate :: proc() {
	if terrain_cache.valid {
		raylib.UnloadModel(terrain_cache.model)
		raylib.UnloadTexture(terrain_cache.path_mask_tex)
		raylib.UnloadTexture(terrain_cache.water_mask_tex)
		raylib.UnloadTexture(terrain_cache.foam_mask_tex)
		delete(terrain_cache.path_mask_cpu)
		terrain_cache.path_mask_cpu = nil
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

// Triángulo con normal DADA A MANO, no calculada del propio triángulo —
// para las paredes de orilla (ver _terrain_add_bank_wall): son casi
// verticales (n.y ≈ 0), así que el "flip si n.y<0" de _terrain_push_tri
// (pensado para las pendientes suaves del resto del terreno, casi siempre
// mirando hacia arriba) no tiene un lado claro que elegir ahí y podría
// voltear la normal para un lado o el otro según ruido de punto flotante,
// dando sombreado inconsistente pared por pared.
_terrain_push_wall_tri :: proc(
	positions, normals, texcoords: ^[dynamic]f32, colors: ^[dynamic]u8,
	v0, v1, v2: raylib.Vector3, n: raylib.Vector3, uv0, uv1, uv2: raylib.Vector2, c0, c1, c2: raylib.Color,
) {
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

// ANY: promedia los hasta 4 tiles que tocan la esquina sin distinguir
// agua de tierra (comportamiento viejo, el que producía el error que
// arregla esto — agua no perfectamente plana cerca de la orilla, ver
// terrain_cache_ensure). LAND/WATER: promedia SOLO los tiles de esa
// categoría — con esto un tile de agua nunca mezcla su altura con la
// tierra vecina (todas las esquinas de agua dan exactamente
// WORLD_WATER_HEIGHT, agua perfectamente plana) y un tile de tierra
// nunca se hunde/levanta por el agua de al lado (sigue su propio
// heightmap sin interrupción). El escalón resultante entre las dos
// categorías se tapa con geometría real, no con una interpolación —
// ver _terrain_add_bank_wall.
Terrain_Corner_Category :: enum { ANY, LAND, WATER }

// Altura/color de una esquina de grilla (r,c en [0,height]×[0,width]) —
// promedio de los tiles que la tocan (los 4, o solo los de `category` si
// no es .ANY). Con .ANY es lo que produce el desnivel diagonal: dos tiles
// vecinos con distinta altura comparten esta esquina, así que la arista
// entre ellos interpola en vez de cortar en escalón — deliberado para
// tierra-tierra (mismo criterio que siempre), evitado a propósito para
// agua-tierra (ver arriba).
_terrain_corner :: proc(m: ^entities.Map, r, c: i32, biome_colors: constants.Biome_Colors, category := Terrain_Corner_Category.ANY) -> (h: f32, color: [3]f32) {
	sum_h := f32(0)
	sum_c := [3]f32{0, 0, 0}
	n := f32(0)
	for dr in -1 ..= 0 {
		for dc in -1 ..= 0 {
			tr, tc := r + i32(dr), c + i32(dc)
			if tr < 0 || tr >= m.height || tc < 0 || tc >= m.width { continue }
			if category != .ANY {
				wants_water := category == .WATER
				if m.water_grid[tr][tc] != wants_water { continue }
			}
			th, tcol := _terrain_tile_height_color(m, tr, tc, biome_colors)
			sum_h += th
			sum_c += [3]f32{f32(tcol.r), f32(tcol.g), f32(tcol.b)}
			n += 1
		}
	}
	if n == 0 { return 0, {0, 0, 0} }
	return sum_h / n, sum_c / n
}

// Altura/color interpolados bilinealmente dentro del tile (row,col), en un
// punto fraccional (u,v) en [0,1]×[0,1] — u=0/v=0 es la esquina (row,col),
// u=1/v=1 es (row+1,col+1). Usa las mismas 4 esquinas de _terrain_corner que
// ya arma el mesh sin subdividir, así que en u,v ∈ {0,1} da exactamente lo
// mismo que antes — la subdivisión no cambia el terreno, solo lo hace más
// denso para poder tallar el camino (ver terrain_cache_ensure).
_terrain_corner_lerp :: proc(m: ^entities.Map, row, col: i32, u, v: f32, biome_colors: constants.Biome_Colors, category := Terrain_Corner_Category.ANY) -> (h: f32, color: [3]f32) {
	h_tl, c_tl := _terrain_corner(m, row, col, biome_colors, category)
	h_tr, c_tr := _terrain_corner(m, row, col + 1, biome_colors, category)
	h_bl, c_bl := _terrain_corner(m, row + 1, col, biome_colors, category)
	h_br, c_br := _terrain_corner(m, row + 1, col + 1, biome_colors, category)

	h_top := h_tl + (h_tr - h_tl) * u
	h_bot := h_bl + (h_br - h_bl) * u
	h = h_top + (h_bot - h_top) * v

	c_top := c_tl + (c_tr - c_tl) * u
	c_bot := c_bl + (c_br - c_bl) * u
	color = c_top + (c_bot - c_top) * v
	return
}

// Máscara del camino "embossed": valor [0,1] en un punto fraccional (u,v)
// dentro del tile (row,col) — 1.0 sobre la línea central de la franja de
// camino (ancho PATH_WIDTH_RATIO), con falloff suave hacia 0 en el borde.
// Se usa tanto para pintar pathColor como para el hundimiento (lighting.vs)
// — un solo dato para las dos cosas. La franja se modela como segmentos
// centro-del-tile → punto-medio-de-cada-borde-conectado (forma de cruz),
// reusando el mismo criterio PATH/SPAWN/GOAL que render_bridge_3d
// y obstacle_bar_dims para decidir qué vecinos "cuentan" como camino.
_path_strip_mask :: proc(m: ^entities.Map, row, col: i32, u, v: f32) -> f32 {
	is_path_like :: proc(m: ^entities.Map, r, c: i32) -> bool {
		if r < 0 || r >= m.height || c < 0 || c >= m.width { return false }
		t := m.grid[r][c]
		return t == .PATH || t == .SPAWN || t == .GOAL
	}
	if !is_path_like(m, row, col) { return 0 }

	dist_to_segment :: proc(p, a, b: raylib.Vector2) -> f32 {
		ab := b - a
		denom := linalg.dot(ab, ab)
		t: f32 = 0
		if denom > 0 { t = clamp(linalg.dot(p - a, ab) / denom, 0, 1) }
		closest := a + ab * t
		return linalg.length(p - closest)
	}

	p := raylib.Vector2{u - 0.5, v - 0.5}
	center := raylib.Vector2{0, 0}
	half_width := f32(constants.PATH_WIDTH_RATIO) * 0.5

	best := f32(1e9)
	found := false
	if is_path_like(m, row - 1, col) { best = min(best, dist_to_segment(p, center, {0, -0.5})); found = true }
	if is_path_like(m, row + 1, col) { best = min(best, dist_to_segment(p, center, {0, 0.5}));  found = true }
	if is_path_like(m, row, col - 1) { best = min(best, dist_to_segment(p, center, {-0.5, 0})); found = true }
	if is_path_like(m, row, col + 1) { best = min(best, dist_to_segment(p, center, {0.5, 0}));  found = true }
	d := best if found else linalg.length(p - center)

	soft := constants.PATH_EDGE_SOFTNESS * half_width
	return 1.0 - math.smoothstep(half_width - soft, half_width + soft, d)
}

// Altura real de la malla de terreno en un punto fraccional (u,v) del tile
// (row,col) — mismo cálculo que terrain_cache_ensure usa para plantar los
// vértices del mesh (interpolación bilineal entre esquinas promediadas,
// _terrain_corner_lerp) MÁS el mismo hundimiento de camino que aplica
// lighting.vs en el vertex shader: no es _path_strip_mask analítico (ese no
// tiene el blur en cruz de terrain_cache_ensure, y difiere justo en
// bordes/uniones donde el min() entre brazos deja una cresta dura — eso
// hacía que el disco se cortara contra el terreno ahí) sino
// _path_mask_sample, que lee la MISMA textura-máscara ya blureada, con el
// mismo bilinear+clamp que la GPU. Un tile de agua nunca se hunde (bridge:
// bridgeGuard=0 en lighting.vs), así que ahí directamente se devuelve la
// altura fija del agua. A diferencia de tile_world_top (altura CRUDA del
// tile, sin promediar con vecinos ni hundir el camino), esto es lo que el
// jugador realmente ve dibujado.
terrain_surface_height :: proc(m: ^entities.Map, row, col: i32, u, v: f32) -> f32 {
	if m.water_grid[row][col] { return constants.WORLD_WATER_HEIGHT }
	h, _ := _terrain_corner_lerp(m, row, col, u, v, constants.Biome_Colors{}, .LAND)
	wu := (f32(col) + u) / f32(m.width)
	wv := (f32(row) + v) / f32(m.height)
	h -= _path_mask_sample(wu, wv) * constants.PATH_EMBOSS_DEPTH
	return h
}

// Pared vertical (banco/orilla) donde un tile de TIERRA linda con uno de
// AGUA — conecta la altura real de la tierra (su propia interpolación
// .LAND, sin promediar con el agua) con el nivel plano del agua
// (WORLD_WATER_HEIGHT), tapando el escalón entre las dos categorías que
// ahora deja _terrain_corner al no mezclarlas. `land_row`/`land_col` son
// SIEMPRE el tile de tierra (nunca el de agua) — la pared se arma desde
// su propio borde, con el mismo _terrain_corner_lerp(.LAND) que ya usa
// sub_vertex para ese tile, así que el borde superior de la pared
// coincide vértice a vértice con el borde real de la malla de tierra (sin
// costura). El borde inferior es agua perfectamente plana en todos lados,
// así que coincide con CUALQUIER tile de agua vecino sin más cálculo.
//
// `fixed_is_u`+`fixed_value` ubican el borde del tile de tierra que da al
// agua (u=1 borde derecho, u=0 izquierdo, v=1 abajo, v=0 arriba);
// `outward_normal` apunta hacia el agua (lejos de la tierra) — se pasa a
// mano en vez de calcularla del triángulo porque una pared casi vertical
// (n.y≈0) no tiene un lado "hacia arriba" claro del que _terrain_push_tri
// pueda partir (ver _terrain_push_wall_tri).
//
// Funciona sin importar si la tierra queda más alta o más baja que el
// agua en cada tramo — el agua se pinta a mano en el editor, sin relación
// con el heightmap de abajo, así que no hay que asumir ninguna de las dos
// direcciones (ver el pedido original que motivó esto).
_terrain_add_bank_wall :: proc(
	positions, normals, texcoords: ^[dynamic]f32, colors: ^[dynamic]u8,
	m: ^entities.Map, land_row, land_col: i32, biome_colors: constants.Biome_Colors,
	fixed_is_u: bool, fixed_value: f32, outward_normal: raylib.Vector3,
) {
	cs := constants.WORLD_CELL_SIZE
	SUBDIV :: constants.TERRAIN_MESH_SUBDIV
	for i in i32(0) ..< SUBDIV {
		t0 := f32(i) / f32(SUBDIV)
		t1 := f32(i + 1) / f32(SUBDIV)

		u0 := fixed_value if fixed_is_u else t0
		v0 := t0 if fixed_is_u else fixed_value
		u1 := fixed_value if fixed_is_u else t1
		v1 := t1 if fixed_is_u else fixed_value

		h0, col3_0 := _terrain_corner_lerp(m, land_row, land_col, u0, v0, biome_colors, .LAND)
		h1, col3_1 := _terrain_corner_lerp(m, land_row, land_col, u1, v1, biome_colors, .LAND)
		c0 := raylib.Color{u8(col3_0.r), u8(col3_0.g), u8(col3_0.b), 255}
		c1 := raylib.Color{u8(col3_1.r), u8(col3_1.g), u8(col3_1.b), 255}

		wx0 := (f32(land_col) + u0) * cs
		wz0 := (f32(land_row) + v0) * cs
		wx1 := (f32(land_col) + u1) * cs
		wz1 := (f32(land_row) + v1) * cs

		top0 := raylib.Vector3{wx0, h0, wz0}
		top1 := raylib.Vector3{wx1, h1, wz1}
		bot0 := raylib.Vector3{wx0, constants.WORLD_WATER_HEIGHT, wz0}
		bot1 := raylib.Vector3{wx1, constants.WORLD_WATER_HEIGHT, wz1}

		// UV en espacio de mundo normalizado (wc/width, wr/height) — el
		// MISMO convenio que sub_vertex, no un UV local 0..1 por segmento:
		// esta pared entra al mismo mesh que el resto del terreno, bajo el
		// mismo lighting_shader con useTerrainMask activo, así que su
		// texcoord tiene que apuntar al lugar correcto de texture0/texture1
		// (máscaras de camino/agua) — un UV local samplearía esas texturas
		// en un punto cualquiera y podría pintar camino/agua donde no va.
		uv0 := raylib.Vector2{wx0 / (f32(m.width) * cs), wz0 / (f32(m.height) * cs)}
		uv1 := raylib.Vector2{wx1 / (f32(m.width) * cs), wz1 / (f32(m.height) * cs)}

		_terrain_push_wall_tri(positions, normals, texcoords, colors, bot0, bot1, top1, outward_normal, uv0, uv1, uv1, c0, c1, c1)
		_terrain_push_wall_tri(positions, normals, texcoords, colors, bot0, top1, top0, outward_normal, uv0, uv1, uv0, c0, c1, c0)
	}
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

	// sub_vertex: posición de mundo (X,Z) + altura interpolada bilinealmente
	// del punto (su,sv en [0,SUBDIV]) dentro del tile (row,col). uv mapea 1:1
	// a la textura-máscara del camino. La malla se subdivide (en vez de un
	// solo quad por tile) para poder tallar una franja angosta de camino
	// hundida dentro del tile — ver _path_strip_mask y lighting.vs. En las
	// esquinas del tile (su/sv en {0,SUBDIV}) da exactamente lo mismo que la
	// vieja world_corner, así que el terreno sin camino no cambia de forma.
	SUBDIV :: constants.TERRAIN_MESH_SUBDIV
	sub_vertex :: proc(m: ^entities.Map, row, col, su, sv: i32, biome_colors: constants.Biome_Colors, cs: f32) -> (pos: raylib.Vector3, uv: raylib.Vector2, color: raylib.Color) {
		u := f32(su) / f32(SUBDIV)
		v := f32(sv) / f32(SUBDIV)
		// Categoría del PROPIO tile — un tile de agua nunca promedia con la
		// tierra vecina (queda perfectamente plano) y viceversa (ver
		// Terrain_Corner_Category). El escalón resultante se tapa aparte,
		// ver la pasada de _terrain_add_bank_wall más abajo.
		category := Terrain_Corner_Category.WATER if m.water_grid[row][col] else Terrain_Corner_Category.LAND
		h, col3 := _terrain_corner_lerp(m, row, col, u, v, biome_colors, category)
		wc := f32(col) + u
		wr := f32(row) + v
		pos = {wc * cs, h, wr * cs}
		uv = {wc / f32(m.width), wr / f32(m.height)}
		color = raylib.Color{u8(col3.r), u8(col3.g), u8(col3.b), 255}
		return
	}

	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			for sv in i32(0) ..< SUBDIV {
				for su in i32(0) ..< SUBDIV {
					p_tl, uv_tl, c_tl := sub_vertex(m, row, col, su,     sv,     biome_colors, cs)
					p_tr, uv_tr, c_tr := sub_vertex(m, row, col, su + 1, sv,     biome_colors, cs)
					p_bl, uv_bl, c_bl := sub_vertex(m, row, col, su,     sv + 1, biome_colors, cs)
					p_br, uv_br, c_br := sub_vertex(m, row, col, su + 1, sv + 1, biome_colors, cs)

					// 2 triángulos por sub-quad, CCW visto desde +Y en ambos.
					_terrain_push_tri(&positions, &normals, &texcoords, &colors, p_tl, p_bl, p_tr, uv_tl, uv_bl, uv_tr, c_tl, c_bl, c_tr)
					_terrain_push_tri(&positions, &normals, &texcoords, &colors, p_tr, p_bl, p_br, uv_tr, uv_bl, uv_br, c_tr, c_bl, c_br)
				}
			}
		}
	}

	// Un tile de agua que además es PATH/SPAWN/GOAL es un puente (piso
	// propio dibujado por render_bridge_3d, a nivel de la tierra — ver el
	// comentario ahí) y no una orilla real. La pared NO debe salir ahí: el
	// puente ya resuelve la conexión visual con la tierra por su cuenta
	// (piso + barandas), una pared cortando justo donde arranca se vería
	// mal. Mismo criterio de clasificación que is_path_like en
	// render_bridge_3d, pero mirando el tile en sí (no sus vecinos).
	_is_bridge_water :: proc(m: ^entities.Map, r, c: i32) -> bool {
		if !m.water_grid[r][c] { return false }
		t := m.grid[r][c]
		return t == .PATH || t == .SPAWN || t == .GOAL
	}

	// Paredes de orilla — un solo barrido por borde HORIZONTAL (col/col+1)
	// y otro por VERTICAL (row/row+1) entre tiles de categoría distinta,
	// cada arista visitada una sola vez (solo se mira el vecino de la
	// derecha/abajo, nunca el de la izquierda/arriba — si se miraran los
	// dos, cada borde saldría duplicado). Ver _terrain_add_bank_wall para
	// el porqué completo.
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			is_water := m.water_grid[row][col]

			if col + 1 < m.width && m.water_grid[row][col + 1] != is_water {
				if is_water {
					// este tile es agua, el de la derecha es tierra: la
					// pared la arma el de tierra, por su borde IZQUIERDO
					// (u=0), mirando hacia -X (hacia el agua).
					if !_is_bridge_water(m, row, col) {
						_terrain_add_bank_wall(&positions, &normals, &texcoords, &colors, m, row, col + 1, biome_colors, true, 0, {-1, 0, 0})
					}
				} else {
					// este tile es tierra, el de la derecha es agua: la
					// pared la arma este mismo tile, por su borde DERECHO
					// (u=1), mirando hacia +X.
					if !_is_bridge_water(m, row, col + 1) {
						_terrain_add_bank_wall(&positions, &normals, &texcoords, &colors, m, row, col, biome_colors, true, 1, {1, 0, 0})
					}
				}
			}

			if row + 1 < m.height && m.water_grid[row + 1][col] != is_water {
				if is_water {
					if !_is_bridge_water(m, row, col) {
						_terrain_add_bank_wall(&positions, &normals, &texcoords, &colors, m, row + 1, col, biome_colors, false, 0, {0, 0, -1})
					}
				} else {
					if !_is_bridge_water(m, row + 1, col) {
						_terrain_add_bank_wall(&positions, &normals, &texcoords, &colors, m, row, col, biome_colors, false, 1, {0, 0, 1})
					}
				}
			}
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

	// Textura-máscara de camino: supersampleada (PATH_MASK_SUBDIV texels por
	// tile en cada eje), R8, BILINEAR filter — a diferencia de la vieja
	// versión de 1 texel/tile + POINT, acá el valor de cada texel es la
	// franja angosta de _path_strip_mask (1.0 en el centro del camino,
	// falloff suave hacia 0 en el borde), así que hace falta blur real para
	// que el borde de la franja se vea suave. Este mismo dato pinta
	// pathColor (lighting.fs) Y hunde el terreno (lighting.vs) — ver
	// PATH_EMBOSS_DEPTH.
	mask_w := m.width * constants.PATH_MASK_SUBDIV
	mask_h := m.height * constants.PATH_MASK_SUBDIV
	mask_pixels := make([]u8, int(mask_w) * int(mask_h))
	for ty in 0 ..< mask_h {
		row := ty / constants.PATH_MASK_SUBDIV
		v := (f32(ty % constants.PATH_MASK_SUBDIV) + 0.5) / f32(constants.PATH_MASK_SUBDIV)
		for tx in 0 ..< mask_w {
			col := tx / constants.PATH_MASK_SUBDIV
			u := (f32(tx % constants.PATH_MASK_SUBDIV) + 0.5) / f32(constants.PATH_MASK_SUBDIV)
			mask_val := _path_strip_mask(m, row, col, u, v)
			mask_pixels[ty * mask_w + tx] = u8(clamp(mask_val, 0, 1) * 255)
		}
	}

	// Blur en cruz (centro + 4 vecinos ortogonales, sin diagonales — caja
	// más chica que un 3x3 completo) en espacio de texel. En curvas/T, el
	// min() de arriba entre las distancias a cada brazo del camino deja una
	// cresta dura donde dos campos empatan — la normal del VS sale de
	// diferencias finitas de esta misma textura, así que ese escalón se
	// traduce en un pliegue raro visible desde ciertos ángulos de cámara.
	// Emprolijar acá, en la imagen ya rasterizada, es más predecible que
	// redondear el campo de distancia analítico (probado y revertido:
	// "smooth minimum" sobre 3-4 segmentos combinados en cadena termina
	// hundiendo de más, empeora en vez de mejorar).
	{
		blurred := make([]u8, len(mask_pixels))
		defer delete(blurred)
		OFFSETS := [5][2]i32{{0, 0}, {-1, 0}, {1, 0}, {0, -1}, {0, 1}}
		for ty in 0 ..< mask_h {
			for tx in 0 ..< mask_w {
				sum := 0
				n := 0
				for off in OFFSETS {
					sx, sy := tx + off[0], ty + off[1]
					if sx < 0 || sx >= mask_w || sy < 0 || sy >= mask_h { continue }
					sum += int(mask_pixels[sy * mask_w + sx])
					n += 1
				}
				blurred[ty * mask_w + tx] = u8(sum / n)
			}
		}
		copy(mask_pixels, blurred)
	}

	mask_img := raylib.Image{
		data    = raw_data(mask_pixels),
		width   = mask_w,
		height  = mask_h,
		mipmaps = 1,
		format  = .UNCOMPRESSED_GRAYSCALE,
	}
	mask_tex := raylib.LoadTextureFromImage(mask_img)
	raylib.SetTextureFilter(mask_tex, .BILINEAR)
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

	// Máscara de agua para la espuma de orilla (foamMask en lighting.fs),
	// tercer slot de material (texture2 para el shader) — distinta de
	// water_tex de arriba a propósito. water_tex es 1 texel/tile con
	// filtro POINT (nítida, para decidir "esta tile es agua sí/no" sin
	// artefactos); esta es supersampleada (FOAM_MASK_SUBDIV texels/tile)
	// CON MIPMAPS. El truco: la espuma necesita un blur de RADIO
	// VARIABLE en el tiempo para simular el vaivén de las olas, y
	// rearmar ese blur a mano en el shader (un loop de muestreo por
	// fragmento) con un radio de varios tiles sale carísimo. Un mipmap ya
	// ES un blur — cada nivel promedia un área más grande que el
	// anterior — así que sampleando con textureLod() y animando el nivel
	// de LOD se obtiene "cambiar el radio del blur" con una sola lectura
	// de textura, gratis vía el mismo hardware que ya genera mipmaps para
	// todo lo demás.
	foam_w := m.width * constants.FOAM_MASK_SUBDIV
	foam_h := m.height * constants.FOAM_MASK_SUBDIV
	foam_pixels := make([]u8, int(foam_w) * int(foam_h))
	defer delete(foam_pixels)
	for ty in 0 ..< foam_h {
		row := ty / constants.FOAM_MASK_SUBDIV
		for tx in 0 ..< foam_w {
			col := tx / constants.FOAM_MASK_SUBDIV
			foam_pixels[ty * foam_w + tx] = 255 if m.water_grid[row][col] else 0
		}
	}
	foam_img := raylib.Image{
		data    = raw_data(foam_pixels),
		width   = foam_w,
		height  = foam_h,
		mipmaps = 1,
		format  = .UNCOMPRESSED_GRAYSCALE,
	}
	foam_tex := raylib.LoadTextureFromImage(foam_img)
	raylib.GenTextureMipmaps(&foam_tex)
	raylib.SetTextureFilter(foam_tex, .TRILINEAR)
	raylib.SetTextureWrap(foam_tex, .CLAMP)
	model.materials[0].maps[raylib.MaterialMapIndex.NORMAL].texture = foam_tex

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
	path_mask_texel := raylib.Vector2{1.0 / f32(mask_w), 1.0 / f32(mask_h)}
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_path_mask_texel, &path_mask_texel, .VEC2)
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
	terrain_cache.foam_mask_tex = foam_tex
	terrain_cache.path_mask_cpu = mask_pixels
	terrain_cache.path_mask_w = mask_w
	terrain_cache.path_mask_h = mask_h
	terrain_cache.valid = true
}

// Replica a mano el sampler BILINEAR+CLAMP que lighting.vs usa sobre
// path_mask_tex, pero leyendo la copia CPU (terrain_cache.path_mask_cpu) —
// mismo pixel exacto que ve la GPU, blur en cruz incluido. u,v en
// coordenadas de mundo normalizadas [0,1] sobre TODO el mapa (mismo espacio
// que vertexTexCoord = wc/width, wr/height en terrain_cache_ensure), no
// fraccional-por-tile como _path_strip_mask.
_path_mask_sample :: proc(u, v: f32) -> f32 {
	w, h := terrain_cache.path_mask_w, terrain_cache.path_mask_h
	if w == 0 || h == 0 { return 0 }
	// Centro de texel en 0.5/w, así que restamos medio texel antes de
	// interpolar — mismo convenio que cualquier sampler bilineal de GL.
	fx := clamp(u, 0, 1) * f32(w) - 0.5
	fy := clamp(v, 0, 1) * f32(h) - 0.5
	x0 := i32(math.floor(fx))
	y0 := i32(math.floor(fy))
	tx := fx - f32(x0)
	ty := fy - f32(y0)
	sample :: proc(x, y, w, h: i32) -> f32 {
		cx := clamp(x, 0, w - 1)
		cy := clamp(y, 0, h - 1)
		return f32(terrain_cache.path_mask_cpu[cy * w + cx]) / 255.0
	}
	v00 := sample(x0, y0, w, h)
	v10 := sample(x0 + 1, y0, w, h)
	v01 := sample(x0, y0 + 1, w, h)
	v11 := sample(x0 + 1, y0 + 1, w, h)
	top := v00 + (v10 - v00) * tx
	bot := v01 + (v11 - v01) * tx
	return top + (bot - top) * ty
}

// Terreno del mapa: malla continua cacheada (ver terrain_cache_ensure),
// desniveles diagonales reales, color de camino nítido vía textura-máscara,
// iluminada con Lighting_Shader. Reemplaza a render_map para los estados 3D.
// Interpola linealmente entre las 2 fases vecinas de DAY_NIGHT_KEYFRAMES
// según `t` (en "fases", no segundos — ver DAY_NIGHT_CYCLE_SPEED). Las
// direcciones se devuelven sin normalizar; normalizar en el caller antes de
// subirlas al shader (mismo criterio que sun_dir/fill_dir en
// lighting_shader_init).
day_night_sample :: proc(t: f32) -> constants.Day_Night_Values {
	PHASE_COUNT :: len(constants.Day_Night_Phase)
	local := math.mod_f32(t, f32(PHASE_COUNT))
	if local < 0 { local += f32(PHASE_COUNT) }
	i0 := int(local)
	i1 := (i0 + 1) % PHASE_COUNT
	frac := local - f32(i0)
	a := constants.DAY_NIGHT_KEYFRAMES[constants.Day_Night_Phase(i0)]
	b := constants.DAY_NIGHT_KEYFRAMES[constants.Day_Night_Phase(i1)]
	return constants.Day_Night_Values{
		sun_dir    = linalg.lerp(a.sun_dir, b.sun_dir, frac),
		sun_color  = linalg.lerp(a.sun_color, b.sun_color, frac),
		fill_dir   = linalg.lerp(a.fill_dir, b.fill_dir, frac),
		fill_color = linalg.lerp(a.fill_color, b.fill_color, frac),
		ambient    = linalg.lerp(a.ambient, b.ambient, frac),
	}
}

// Fondo (cielo) detrás del mapa = color del sol actual (día/noche), no un
// color fijo por bioma — así el cielo acompaña el ciclo de luz. Compartido
// entre render_game y render_map_preview_to_texture para no duplicar la
// conversión Vector3[0,1] → raylib.Color en los dos call sites.
sky_color_from_sun :: proc() -> raylib.Color {
	dn := day_night_sample(lighting_shader.day_night_anim_time)
	return raylib.Color{
		u8(clamp(dn.sun_color.r, 0, 1) * 255),
		u8(clamp(dn.sun_color.g, 0, 1) * 255),
		u8(clamp(dn.sun_color.b, 0, 1) * 255),
		255,
	}
}

// Matriz vista×proyección ortográfica del "sol", centrada en el mapa
// actual (no en la cámara del jugador — el mapa tiene una extensión de
// mundo fija, GRID_SIZE como tope, independiente del zoom/pan). `sun_dir`
// ya normalizado — mismo vector que sube render_map_3d como uniform
// sunDir. El caller compone `proj * view` (NO `view * proj`) para
// transformar un punto de mundo — ver la nota en shadow_map_bind_for_sampling,
// ese orden invertido fue justo el bug que hizo que no se viera ninguna
// sombra la primera vez.
shadow_light_matrix :: proc(m: ^entities.Map, sun_dir: raylib.Vector3) -> (view, proj: raylib.Matrix) {
	wcs := constants.WORLD_CELL_SIZE
	center := raylib.Vector3{f32(m.width) * wcs * 0.5, 0.5, f32(m.height) * wcs * 0.5}
	// sun_dir apunta DESDE la superficie HACIA el sol (misma convención que
	// lighting.fs) — el ojo de la cámara-luz tiene que ubicarse EN esa
	// dirección desde el centro (arriba, del lado del sol) para mirar hacia
	// abajo al mapa; con el signo invertido la "luz" quedaba del lado
	// opuesto al sol real y el depth pass no producía sombras utilizables.
	eye := center + sun_dir * constants.SHADOW_LIGHT_DISTANCE
	view = raylib.MatrixLookAt(eye, center, {0, 1, 0})

	// El frustum ortográfico se ajusta al AABB real del mundo (todo el
	// ancho/alto del mapa, Y desde bien debajo del terreno hasta arriba
	// del caster más alto — el terreno tiene su propio desplazamiento
	// hacia abajo cerca del camino, PATH_EMBOSS_DEPTH, así que el margen
	// de abajo tiene que cubrir eso también), NO un half-extent isotrópico
	// basado solo en la diagonal X/Z: para un sol con componente horizontal
	// grande (DAWN/DUSK) la proyección del mapa sobre los ejes de la
	// cámara-luz NO es un círculo, es un rectángulo estirado que un
	// half-extent isotrópico subestima — las esquinas del mapa quedaban
	// literalmente afuera del frustum y no aparecía ninguna sombra ahí.
	// Se proyectan los 8 vértices del AABB a espacio de la cámara-luz
	// (Vector3Transform con `view`) y se toma el min/max real de esas 8
	// proyecciones para los 6 planos del frustum.
	w := f32(m.width) * wcs
	h := f32(m.height) * wcs
	min_x, min_y, min_z := f32(math.F32_MAX), f32(math.F32_MAX), f32(math.F32_MAX)
	max_x, max_y, max_z := -f32(math.F32_MAX), -f32(math.F32_MAX), -f32(math.F32_MAX)
	for cx in ([2]f32{0, w}) {
		for cz in ([2]f32{0, h}) {
			for cy in ([2]f32{constants.SHADOW_WORLD_Y_MIN, constants.SHADOW_WORLD_Y_MAX}) {
				vs := raylib.Vector3Transform(raylib.Vector3{cx, cy, cz}, view)
				min_x = min(min_x, vs.x)
				max_x = max(max_x, vs.x)
				min_y = min(min_y, vs.y)
				max_y = max(max_y, vs.y)
				// Espacio de vista de raylib: la cámara mira hacia -Z, así
				// que la distancia real hacia adelante es -vs.z.
				dist := -vs.z
				min_z = min(min_z, dist)
				max_z = max(max_z, dist)
			}
		}
	}
	margin := constants.SHADOW_FRUSTUM_MARGIN
	near := max(constants.SHADOW_NEAR_PLANE, min_z - margin)
	far := max_z + margin
	proj = raylib.MatrixOrtho(min_x - margin, max_x + margin, min_y - margin, max_y + margin, near, far)
	return
}

// Depth pre-pass: dibuja los casters (torres, árboles en tierra, bloques +
// barras de obstáculo, puente, enemigos) con shadow_map.depth_shader en vez
// de lighting_shader.shader, a la textura de profundidad de shadow_map.
// El terreno NO es caster (solo receptor, ver lighting.fs) — evita
// duplicar el hundimiento del camino embossed acá. Reusa exactamente los
// mismos procs de dibujo que render_map_objects_3d/render_gameplay_3d —
// mismo geometría, shader distinto (el bind de BeginShaderMode es lo único
// que cambia qué uniform "mvp" recibe cada draw).
render_shadow_depth_pass :: proc(app: ^entities.App_State, m: ^entities.Map, sun_dir: raylib.Vector3) {
	if !shadow_map.valid { return }

	// Esta pasada corre ANTES que render_map_3d en el frame (el shadow map
	// tiene que estar listo antes de que la pasada visible lo samplee) —
	// terrain_cache_ensure normalmente se garantiza desde ahí, pero acá
	// también hace falta: terrain_surface_height (usada más abajo para
	// asentar la sombra del árbol a la altura real) lee
	// terrain_cache.path_mask_cpu, que sin este call todavía puede estar
	// vacío en el primer frame tras cargar un mapa — panic de índice fuera
	// de rango, no un shadow raro. Idempotente (guardado por
	// terrain_cache.valid), así que llamarlo de nuevo en render_map_3d no
	// hace nada de más.
	terrain_cache_ensure(m)

	shadow_map.view, shadow_map.proj = shadow_light_matrix(m, sun_dir)

	res := constants.SHADOW_MAP_RESOLUTION
	rlgl.EnableFramebuffer(shadow_map.fbo_id)
	rlgl.Viewport(0, 0, res, res)
	rlgl.ClearScreenBuffers()

	// Mismo manejo de matrices que raylib.BeginMode3D/EndMode3D por dentro
	// — imprescindible, NO alcanza con Set*+restaurar el framebuffer/
	// viewport al final. rlSetMatrixProjection escribe directo sobre el
	// mismo storage que apila rlPushMatrix en modo PROJECTION, así que
	// push-antes/pop-después deja la proyección 2D de pantalla intacta
	// para el resto del frame (UI incluida). El modelview no se apila —
	// mismo criterio que EndMode3D, que siempre vuelve a identidad en vez
	// de "restaurar" (el modo 2D no tiene cámara, es identidad siempre).
	// Sin este push/pop, la proyección ortográfica de la sombra quedaba
	// pisada para el resto del frame y la UI 2D se renderizaba con las
	// coordenadas equivocadas — se veía como si hubiera desaparecido.
	rlgl.DrawRenderBatchActive()
	rlgl.MatrixMode(rlgl.PROJECTION)
	rlgl.PushMatrix()
	rlgl.SetMatrixProjection(shadow_map.proj)
	rlgl.MatrixMode(rlgl.MODELVIEW)
	rlgl.SetMatrixModelview(shadow_map.view)
	rlgl.EnableDepthTest()

	raylib.BeginShaderMode(shadow_map.depth_shader)
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
					tower_type := tile_to_tower_type(tile)
					draw_tower_shape_3d(surface, constants.WORLD_CELL_SIZE, 0, 0, raylib.WHITE, 255, tower_type_has_barrel(tower_type))
				}
			case .ACCESSORY_TREE:
				if !m.water_grid[row][col] {
					// Mismo offset+altura real que la pasada visible (ver la nota
					// en render_map_objects_3d) — si no, la sombra se proyecta
					// desde una posición distinta a donde el árbol realmente
					// se ve, y queda notoriamente desalineada del propio árbol.
					u, v, dx, dz := tree_tile_offset(row, col)
					tree_y := terrain_surface_height(m, row, col, u, v)
					tree_surface := raylib.Vector3{surface.x + dx, tree_y, surface.z + dz}
					render_tree_shadow_3d(tree_surface, m.biome, row, col)
				}
			case .ACCESSORY_BLOCK:
				// Misma razón que los árboles (ver la nota en
				// render_map_objects_3d): surface.y es la altura CRUDA del
				// tile, sin la interpolación real de la malla — con
				// pendiente dentro del tile o entre vecinos, eso dejaba la
				// casa flotando o hundida. Centrado (u=v=0.5, sin el offset
				// aleatorio de los árboles — una casa sí queda fija al
				// centro del tile).
				blk_level := entities.map_get_obstacle_level(m, row, col)
				blk_y := terrain_surface_height(m, row, col, 0.5, 0.5)
				blk_surface := raylib.Vector3{surface.x, blk_y, surface.z}
				render_block_shadow_3d(blk_surface, m.biome, blk_level, row, col)
			}
		}
	}
	render_obstacles_3d(m, m.width, m.height)
	render_bridge_shadow_3d(m)
	render_enemies_3d(app, m)
	render_airdrop_boxes_shadow_3d(app, m)
	render_airdrop_plane_shadow_3d(app)
	raylib.EndShaderMode()

	rlgl.DrawRenderBatchActive()
	rlgl.MatrixMode(rlgl.PROJECTION)
	rlgl.PopMatrix()      // restaura la proyección 2D de pantalla que había antes
	rlgl.MatrixMode(rlgl.MODELVIEW)
	rlgl.LoadIdentity()   // vuelve a identidad — mismo criterio que EndMode3D

	rlgl.DisableFramebuffer()
	rlgl.Viewport(0, 0, raylib.GetRenderWidth(), raylib.GetRenderHeight())
}

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

	// Ciclo día/noche — solo avanza durante una partida (PLAYING); el
	// preview de miniatura de mapa fuerza app.state = .EDITOR, así que ya
	// queda excluido sin código extra. sunDir/sunColor/fillDir/fillColor/
	// ambient pasan de "se setean una vez en init" a "se actualizan cada
	// frame" — dejan de ser los LIGHT_* fijos de constants.odin salvo en
	// NOON, que es justamente ese valor.
	if app.state == .PLAYING {
		lighting_shader.day_night_anim_time += frame_dt * constants.DAY_NIGHT_CYCLE_SPEED
	}
	dn := day_night_sample(lighting_shader.day_night_anim_time)
	dn_sun_dir := linalg.normalize(dn.sun_dir)
	dn_fill_dir := linalg.normalize(dn.fill_dir)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_sun_dir, &dn_sun_dir, .VEC3)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_sun_color, &dn.sun_color, .VEC3)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_fill_dir, &dn_fill_dir, .VEC3)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_fill_color, &dn.fill_color, .VEC3)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_ambient, &dn.ambient, .VEC3)

	// Mismos valores para tree_shader — los árboles reales viven fuera de
	// lighting_shader (ver Tree_Shader) pero comparten el mismo sol/día-noche.
	raylib.SetShaderValue(tree_shader.shader, tree_shader.loc_sun_dir, &dn_sun_dir, .VEC3)
	raylib.SetShaderValue(tree_shader.shader, tree_shader.loc_sun_color, &dn.sun_color, .VEC3)
	raylib.SetShaderValue(tree_shader.shader, tree_shader.loc_fill_dir, &dn_fill_dir, .VEC3)
	raylib.SetShaderValue(tree_shader.shader, tree_shader.loc_fill_color, &dn.fill_color, .VEC3)
	raylib.SetShaderValue(tree_shader.shader, tree_shader.loc_ambient, &dn.ambient, .VEC3)

	// viewDir por frame — la cámara ahora rota (botón central + drag), ya
	// no es la constante fija de antes. Sin gate de estado: también hace
	// falta en EDITOR, donde también se puede rotar.
	view_dir := linalg.normalize(app.camera3d.position - app.camera3d.target)
	raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_view_dir, &view_dir, .VEC3)

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
// `has_barrel` lo apaga para hielo/potenciador — no apuntan a un blanco como
// las torres de daño directo, no tiene sentido que tengan cañón.
// raylib.DrawCylinder()/DrawCylinderEx() no llaman rlNormal3f — el atributo
// de normal que le llega al shader es el que haya quedado de la última
// llamada a rlNormal3f en TODO el frame (constante, no varía por vértice),
// así que bajo un shader de iluminación por normal el objeto entero queda
// con una sola intensidad de luz: se ve como una silueta plana de un solo
// tono en vez de una forma tallada. El fix de "locations explícitas" en
// lighting.vs (ver comentario ahí) solo garantiza que ESE valor constante
// aterrice en el atributo correcto — nunca resolvió que el valor variara.
// Estos dos helpers dibujan la misma geometría a mano vía rlgl, con
// rlNormal3f real por vértice (radial en el cuerpo, plana en las tapas),
// para que las torres (lo único donde esto se nota a simple vista) se vean
// sombreadas de verdad. El resto de los DrawCylinder del proyecto
// (nenúfares, sombras de contacto, spawn/goal, proyectiles) quedan como
// estaban — están fuera del shader de iluminación o son demasiado chicos/
// finos como para que la falta de normal se note.
draw_cylinder_lit_3d :: proc(base: raylib.Vector3, radius, height: f32, sides: i32, color: raylib.Color) {
	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)

	step := 2 * math.PI / f32(sides)
	for i in 0 ..< sides {
		a0 := f32(i) * step
		a1 := f32(i + 1) * step
		x0, z0 := math.sin(a0), math.cos(a0)
		x1, z1 := math.sin(a1), math.cos(a1)

		bl := base + raylib.Vector3{x0 * radius, 0, z0 * radius}
		br := base + raylib.Vector3{x1 * radius, 0, z1 * radius}
		tr := base + raylib.Vector3{x1 * radius, height, z1 * radius}
		tl := base + raylib.Vector3{x0 * radius, height, z0 * radius}

		rlgl.Normal3f(x0, 0, z0); rlgl.Vertex3f(bl.x, bl.y, bl.z)
		rlgl.Normal3f(x1, 0, z1); rlgl.Vertex3f(br.x, br.y, br.z)
		rlgl.Normal3f(x1, 0, z1); rlgl.Vertex3f(tr.x, tr.y, tr.z)

		rlgl.Normal3f(x0, 0, z0); rlgl.Vertex3f(bl.x, bl.y, bl.z)
		rlgl.Normal3f(x1, 0, z1); rlgl.Vertex3f(tr.x, tr.y, tr.z)
		rlgl.Normal3f(x0, 0, z0); rlgl.Vertex3f(tl.x, tl.y, tl.z)
	}

	// Tapa superior — plana, normal (0,1,0). La inferior no hace falta:
	// nunca queda visible, apoyada sobre el tile.
	rlgl.Normal3f(0, 1, 0)
	top := base + raylib.Vector3{0, height, 0}
	for i in 0 ..< sides {
		a0 := f32(i) * step
		a1 := f32(i + 1) * step
		p0 := base + raylib.Vector3{math.sin(a0) * radius, height, math.cos(a0) * radius}
		p1 := base + raylib.Vector3{math.sin(a1) * radius, height, math.cos(a1) * radius}
		rlgl.Vertex3f(top.x, top.y, top.z)
		rlgl.Vertex3f(p0.x, p0.y, p0.z)
		rlgl.Vertex3f(p1.x, p1.y, p1.z)
	}

	rlgl.End()
}

// Igual que arriba, pero entre dos puntos arbitrarios y con radio propio en
// cada extremo (cono) — usado por el cañón. La normal ignora la leve
// inclinación del cono por el cambio de radio (aproximación radial pura);
// con radios tan parecidos (0.08cs → 0.06cs) el error es imperceptible.
draw_cylinder_ex_lit_3d :: proc(start_pos, end_pos: raylib.Vector3, start_radius, end_radius: f32, sides: i32, color: raylib.Color) {
	axis := end_pos - start_pos
	axis_len := linalg.length(axis)
	if axis_len < 0.0001 { return }
	dir := axis / axis_len

	up_ref := raylib.Vector3{0, 1, 0}
	if math.abs(linalg.dot(dir, up_ref)) > 0.99 {
		up_ref = raylib.Vector3{1, 0, 0}
	}
	right := linalg.normalize(linalg.cross(dir, up_ref))
	up := linalg.cross(right, dir)

	rlgl.Begin(rlgl.TRIANGLES)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)

	step := 2 * math.PI / f32(sides)
	for i in 0 ..< sides {
		a0 := f32(i) * step
		a1 := f32(i + 1) * step
		radial0 := right * math.cos(a0) + up * math.sin(a0)
		radial1 := right * math.cos(a1) + up * math.sin(a1)

		bl := start_pos + radial0 * start_radius
		br := start_pos + radial1 * start_radius
		tr := end_pos + radial1 * end_radius
		tl := end_pos + radial0 * end_radius

		rlgl.Normal3f(radial0.x, radial0.y, radial0.z); rlgl.Vertex3f(bl.x, bl.y, bl.z)
		rlgl.Normal3f(radial1.x, radial1.y, radial1.z); rlgl.Vertex3f(br.x, br.y, br.z)
		rlgl.Normal3f(radial1.x, radial1.y, radial1.z); rlgl.Vertex3f(tr.x, tr.y, tr.z)

		rlgl.Normal3f(radial0.x, radial0.y, radial0.z); rlgl.Vertex3f(bl.x, bl.y, bl.z)
		rlgl.Normal3f(radial1.x, radial1.y, radial1.z); rlgl.Vertex3f(tr.x, tr.y, tr.z)
		rlgl.Normal3f(radial0.x, radial0.y, radial0.z); rlgl.Vertex3f(tl.x, tl.y, tl.z)
	}

	// Tapa del extremo (boca del cañón) — normal = dirección del eje.
	rlgl.Normal3f(dir.x, dir.y, dir.z)
	for i in 0 ..< sides {
		a0 := f32(i) * step
		a1 := f32(i + 1) * step
		p0 := end_pos + (right * math.cos(a0) + up * math.sin(a0)) * end_radius
		p1 := end_pos + (right * math.cos(a1) + up * math.sin(a1)) * end_radius
		rlgl.Vertex3f(end_pos.x, end_pos.y, end_pos.z)
		rlgl.Vertex3f(p0.x, p0.y, p0.z)
		rlgl.Vertex3f(p1.x, p1.y, p1.z)
	}

	rlgl.End()
}

draw_tower_shape_3d :: proc(base: raylib.Vector3, cs: f32, angle, recoil: f32, color: raylib.Color, alpha: u8 = 255, has_barrel: bool = true) {
	c := color
	c.a = alpha
	body_r := cs * 0.32
	body_h := cs * 0.45
	draw_cylinder_lit_3d(base, body_r, body_h, 24, c)

	if !has_barrel { return }

	dir := raylib.Vector3{math.cos(angle), 0, math.sin(angle)}
	recoil_pull := recoil * cs * constants.TOWER_RECOIL_DISTANCE_RATIO
	barrel_len := cs * 0.5 - recoil_pull
	start := raylib.Vector3{base.x, base.y + body_h * 0.75, base.z}
	end := start + dir * barrel_len
	barrel := raylib.Color{40, 40, 40, alpha}
	draw_cylinder_ex_lit_3d(start, end, cs * 0.08, cs * 0.06, 16, barrel)
}

// Tipos que no apuntan/disparan un proyectil hacia un blanco — no llevan cañón.
tower_type_has_barrel :: proc(t: constants.Tower_Type) -> bool {
	return t != .ICE && t != .ENHANCE
}

render_tower_3d :: proc(tower: ^entities.Tower, m: ^entities.Map) {
	_, top_y := tile_world_top(m, tower.r, tower.c)
	cs := constants.WORLD_CELL_SIZE
	base := raylib.Vector3{f32(tower.c) * cs + cs * 0.5, top_y, f32(tower.r) * cs + cs * 0.5}
	color := constants.TOWER_SPECS[tower.type].color
	draw_tower_shape_3d(base, cs, tower.angle, tower.recoil, color, 255, tower_type_has_barrel(tower.type))
}

// Árbol real (ver tree_models) — dibuja con tree_shader (asignado a los
// materiales del modelo en tree_models_init) y VUELVE a activar
// lighting_shader al final: DrawModelEx no respeta el BeginShaderMode que
// esté activo en el llamador (usa material.shader directo), así que sin
// este restore el resto de los draws inmediatos del mismo loop
// (obstáculos, la torre del tile siguiente...) quedarían pintados con
// tree_shader el resto del frame — el estado de shader de rlgl es global,
// no se acota solo al terminar este draw. Solo para la pasada visible
// (render_map_objects_3d); la pasada de sombra usa render_tree_shadow_3d.
//
// row/col: solo para el yaw — hash_random(row, col, ...) da un ángulo
// estable por tile (mismo árbol, mismo giro en todos los frames) en vez de
// uno que cambie cuadro a cuadro. El giro va en el propio DrawModelEx
// (rotationAxis={0,1,0}), libre de usar porque la corrección Z-up→Y-up ya
// no vive ahí — quedó horneada en los vértices del mesh en
// tree_models_init (_fix_model_z_up), así que acá no hay dos rotaciones
// que combinar, una sola.
// Offset determinístico (mismo hash-por-tile que el resto de la variación
// visual) para que el árbol no quede plantado justo en el centro exacto de
// la celda — usado tanto por la pasada visible como por la de sombra (ver
// las dos llamadas a esta función), con los MISMOS índices de hash_random,
// para que la sombra no se desalinee del árbol que la tira (mismo criterio
// que ya aplica el yaw). Devuelve u,v en [0,1] (para sampleear la altura
// real del terreno en ese punto exacto vía terrain_surface_height, no en
// el centro) y el offset ya convertido a unidades de mundo en x/z. Rango
// ±0.25 de la celda — deja margen para no cruzar al tile vecino ni pisar
// el camino en una esquina/unión.
tree_tile_offset :: proc(row, col: i32) -> (u, v, world_dx, world_dz: f32) {
	cs := constants.WORLD_CELL_SIZE
	ju := (hash_random(row, col, 11) - 0.5) * 0.5
	jv := (hash_random(row, col, 13) - 0.5) * 0.5
	u = 0.5 + ju
	v = 0.5 + jv
	world_dx = ju * cs
	world_dz = jv * cs
	return
}

render_tree_3d :: proc(center: raylib.Vector3, biome: constants.Biome, row, col: i32) {
	tm := tree_models[biome]
	yaw := hash_random(row, col, 7) * 360.0
	raylib.DrawModelEx(tm.model, center, {0, 1, 0}, yaw, {tm.scale, tm.scale, tm.scale}, raylib.WHITE)
	raylib.BeginShaderMode(lighting_shader.shader)
}

// Sombra real del árbol — mismo modelo y misma geometría que render_tree_3d,
// para el shadow map (ver render_shadow_depth_pass). DrawModelEx usa
// material.shader DIRECTO (no lo que esté activo vía BeginShaderMode, ver
// la nota de arriba), así que acá no alcanza con un BeginShaderMode
// alrededor del draw como hacen las formas inmediatas (torres/obstáculos)
// — hay que pisar el shader del material a mano antes de dibujar y
// devolverlo a tree_shader después, o el modelo quedaría "roto" (con el
// shader de profundidad puesto) la próxima vez que se dibuje en la pasada
// visible. Nunca usar tree_shader para la pasada de sombra ni de casualidad
// aunque el depth-write saldría bien igual (el rasterizador escribe
// profundidad sin importar qué hace el fragment shader): tree_shader
// samplea shadowMap para SU PROPIO shadow_factor(), y esa textura es
// justamente el attachment de profundidad que se está escribiendo en este
// mismo pass — leer y escribir la misma textura a la vez es undefined
// behavior en GL. shadow_map.depth_shader (posición nada más, sin
// samplers) es el único shader seguro acá, mismo criterio que ya usan
// todos los demás casters.
render_tree_shadow_3d :: proc(center: raylib.Vector3, biome: constants.Biome, row, col: i32) {
	tm := tree_models[biome]
	// Mismo yaw que render_tree_3d (mismo hash, mismo row/col) — si no, la
	// sombra proyectada gira distinto que el árbol que la tira.
	yaw := hash_random(row, col, 7) * 360.0
	for i in 0 ..< int(tm.model.materialCount) {
		tm.model.materials[i].shader = shadow_map.depth_shader
	}
	raylib.DrawModelEx(tm.model, center, {0, 1, 0}, yaw, {tm.scale, tm.scale, tm.scale}, raylib.WHITE)
	for i in 0 ..< int(tm.model.materialCount) {
		tm.model.materials[i].shader = tree_shader.shader
	}
}

// Yaw en pasos de 90° (no un ángulo libre como los árboles) — la silueta
// es rectangular, no radialmente simétrica, así que un giro arbitrario
// haría que la casa sobresalga del tile en las esquinas; 4 orientaciones
// alcanzan para que no todas miren para el mismo lado sin arriesgar eso.
block_tile_yaw :: proc(row, col: i32) -> f32 {
	step := i32(hash_random(row, col, 17) * 4)
	return f32(step) * 90.0
}

render_block_3d :: proc(center: raylib.Vector3, biome: constants.Biome, level: i32, row, col: i32) {
	bm := block_models[biome]
	sc := bm.scale * block_level_scale(level)
	yaw := block_tile_yaw(row, col)
	raylib.DrawModelEx(bm.model, center, {0, 1, 0}, yaw, {sc, sc, sc}, raylib.WHITE)
	raylib.BeginShaderMode(lighting_shader.shader)
}

// Sombra real — mismo modelo/yaw/escala que render_block_3d, mismo patrón
// de pisar el shader del material a shadow_map.depth_shader (ver la nota
// larga en render_tree_shadow_3d, aplica igual acá: DrawModelEx usa
// material.shader directo, no lo que esté activo vía BeginShaderMode).
render_block_shadow_3d :: proc(center: raylib.Vector3, biome: constants.Biome, level: i32, row, col: i32) {
	bm := block_models[biome]
	sc := bm.scale * block_level_scale(level)
	yaw := block_tile_yaw(row, col)
	for i in 0 ..< int(bm.model.materialCount) {
		bm.model.materials[i].shader = shadow_map.depth_shader
	}
	raylib.DrawModelEx(bm.model, center, {0, 1, 0}, yaw, {sc, sc, sc}, raylib.WHITE)
	for i in 0 ..< int(bm.model.materialCount) {
		bm.model.materials[i].shader = tree_shader.shader
	}
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
// Puente (piso + barandas) para tiles de PATH sobre agua. El tile-puente es
// agua a altura FIJA en la malla del terreno (ver _terrain_tile_height_color
// — sin tocar, sigue siendo agua de verdad debajo), así que un puente que no
// se hunda necesita piso propio dibujado por encima, a nivel de la tierra
// circundante — se usa el heightmap del tile COMO SI no tuviera agua
// (water_grid es solo una capa visual encima; el heightmap sigue teniendo un
// valor de "tierra" válido ahí debajo, y es continuo con los tiles vecinos
// por construcción del ruido — así el piso queda a nivel con la orilla en
// vez de a la altura plana y baja del agua).
// Dimensiones REALES medidas de los archivos exportados (no 1.0/1.0
// redondo) — deck_plank.obj y railing.obj, ver bridge_models_init. El
// tablón mide exactamente 1×1 de footprint, pero la baranda quedó en 1.06
// de ancho (la curva del cable principal se pasa un poco de los postes),
// así que hace falta esta referencia para no dejarla resacada.
BRIDGE_DECK_REF_SIZE   :: f32(1.0)
BRIDGE_DECK_REF_THICK  :: f32(0.108)
BRIDGE_RAIL_REF_WIDTH  :: f32(1.06)
BRIDGE_RAIL_REF_HEIGHT :: f32(1.0)
BRIDGE_RAIL_REF_THICK  :: f32(0.06)

_bridge_is_path_like :: proc(m: ^entities.Map, r, c: i32) -> bool {
	if r < 0 || r >= m.height || c < 0 || c >= m.width { return false }
	t := m.grid[r][c]
	return t == .PATH || t == .SPAWN || t == .GOAL
}

// Arma un tile de puente entero (tablones + barandas), ya sea con
// tree_shader (pasada visible) o shadow_map.depth_shader (pasada de
// sombra) según qué shader tengan puestos los materiales de los dos
// modelos al momento de llamar — ver render_bridge_3d/render_bridge_shadow_3d,
// que solo difieren en eso. Antes eran puros DrawCube (respetan cualquier
// BeginShaderMode activo); con modelos reales (DrawModelEx, material.shader
// directo) hace falta este desdoblamiento, mismo criterio que árboles/casas.
_bridge_draw_tile :: proc(m: ^entities.Map, row, col: i32) {
	cs         := constants.WORLD_CELL_SIZE
	path_width := cs * constants.PATH_WIDTH_RATIO
	rail_t     := cs * constants.BRIDGE_RAILING_THICK
	rail_h     := cs * 0.18
	deck_thick := cs * constants.BRIDGE_DECK_THICK

	cx := f32(col) * cs + cs*0.5
	cz := f32(row) * cs + cs*0.5
	half := cs * 0.5
	deck_top := m.heightmap[row][col] * constants.WORLD_HEIGHT_SCALE
	// Modelo con base en y=0 (a diferencia del DrawCube viejo, centrado en
	// su pos) — colocarlo en deck_top-deck_thick pone la base ahí y la
	// superficie de arriba (tras el scale en Y) llega justo a deck_top.
	deck_y_pos := deck_top - deck_thick

	dm := bridge_deck_model.model
	dsx := path_width / BRIDGE_DECK_REF_SIZE
	dsz := path_width / BRIDGE_DECK_REF_SIZE
	dsy := deck_thick / BRIDGE_DECK_REF_THICK
	raylib.DrawModelEx(dm, {cx, deck_y_pos, cz}, {0, 1, 0}, 0, {dsx, dsy, dsz}, raylib.WHITE)
	if _bridge_is_path_like(m, row - 1, col) {
		raylib.DrawModelEx(dm, {cx, deck_y_pos, cz - half*0.5}, {0, 1, 0}, 0, {dsx, dsy, half / BRIDGE_DECK_REF_SIZE}, raylib.WHITE)
	}
	if _bridge_is_path_like(m, row + 1, col) {
		raylib.DrawModelEx(dm, {cx, deck_y_pos, cz + half*0.5}, {0, 1, 0}, 0, {dsx, dsy, half / BRIDGE_DECK_REF_SIZE}, raylib.WHITE)
	}
	if _bridge_is_path_like(m, row, col - 1) {
		raylib.DrawModelEx(dm, {cx - half*0.5, deck_y_pos, cz}, {0, 1, 0}, 0, {half / BRIDGE_DECK_REF_SIZE, dsy, dsz}, raylib.WHITE)
	}
	if _bridge_is_path_like(m, row, col + 1) {
		raylib.DrawModelEx(dm, {cx + half*0.5, deck_y_pos, cz}, {0, 1, 0}, 0, {half / BRIDGE_DECK_REF_SIZE, dsy, dsz}, raylib.WHITE)
	}

	// Baranda: escala SIEMPRE en el mismo orden que su eje local (X=ancho
	// entre postes, Y=altura, Z=espesor) — para los bordes este/oeste
	// (columna vecina), en vez de swapear width/length como hacía el
	// DrawCube viejo, se rota 90° en yaw DESPUÉS de escalar (la escala se
	// aplica en espacio local, donde X sigue siendo "el ancho entre
	// postes" — girarla manda ese ancho a Z, exactamente lo que hacía el
	// swap manual, sin distorsionar postes/cables).
	rm := bridge_railing_model.model
	rsx := path_width / BRIDGE_RAIL_REF_WIDTH
	rsy := rail_h / BRIDGE_RAIL_REF_HEIGHT
	rsz := rail_t / BRIDGE_RAIL_REF_THICK
	if !_bridge_is_path_like(m, row - 1, col) {
		raylib.DrawModelEx(rm, {cx, deck_top, cz - path_width*0.5}, {0, 1, 0}, 0, {rsx, rsy, rsz}, raylib.WHITE)
	}
	if !_bridge_is_path_like(m, row + 1, col) {
		raylib.DrawModelEx(rm, {cx, deck_top, cz + path_width*0.5}, {0, 1, 0}, 0, {rsx, rsy, rsz}, raylib.WHITE)
	}
	if !_bridge_is_path_like(m, row, col - 1) {
		raylib.DrawModelEx(rm, {cx - path_width*0.5, deck_top, cz}, {0, 1, 0}, 90, {rsx, rsy, rsz}, raylib.WHITE)
	}
	if !_bridge_is_path_like(m, row, col + 1) {
		raylib.DrawModelEx(rm, {cx + path_width*0.5, deck_top, cz}, {0, 1, 0}, 90, {rsx, rsy, rsz}, raylib.WHITE)
	}
}

render_bridge_3d :: proc(m: ^entities.Map) {
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			if m.grid[row][col] != .PATH || !m.water_grid[row][col] { continue }
			_bridge_draw_tile(m, row, col)
		}
	}
	raylib.BeginShaderMode(lighting_shader.shader)
}

// Sombra real del puente — mismo patrón shader-swap que el resto de los
// modelos (árboles/casas/caja/avión): pisar el shader de los materiales a
// shadow_map.depth_shader antes de dibujar, devolverlo a tree_shader
// después. Antes, con DrawCube, esta pasada compartía directamente
// render_bridge_3d (las formas inmediatas respetan cualquier
// BeginShaderMode activo) — con modelos reales ya no alcanza.
render_bridge_shadow_3d :: proc(m: ^entities.Map) {
	for i in 0 ..< int(bridge_deck_model.model.materialCount) {
		bridge_deck_model.model.materials[i].shader = shadow_map.depth_shader
	}
	for i in 0 ..< int(bridge_railing_model.model.materialCount) {
		bridge_railing_model.model.materials[i].shader = shadow_map.depth_shader
	}
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			if m.grid[row][col] != .PATH || !m.water_grid[row][col] { continue }
			_bridge_draw_tile(m, row, col)
		}
	}
	for i in 0 ..< int(bridge_deck_model.model.materialCount) {
		bridge_deck_model.model.materials[i].shader = tree_shader.shader
	}
	for i in 0 ..< int(bridge_railing_model.model.materialCount) {
		bridge_railing_model.model.materials[i].shader = tree_shader.shader
	}
}

// Nenúfar 3D — modelos reales (lily_models, ver arriba) en vez de los
// cilindros a mano de la versión anterior. Misma semilla determinística por
// tile (hash_position/hash_random, definidas más abajo), misma cantidad de
// pads, mismo rango de radio/posición/deriva animada (lighting_shader.
// caustics_anim_time) y mismo 50% de chance de flor por pad — lo único que
// cambia es CÓMO se dibuja cada pad (DrawModelEx en vez de DrawCylinder) y
// que ahora tiene un yaw aleatorio propio (el disco viejo era perfectamente
// simétrico así que no le hacía falta; el modelo real tiene una muesca en
// el borde, así que sí). DrawModelEx ignora el BeginShaderMode activo del
// llamador (usa material.shader directo, mismo caso que render_tree_3d) —
// por eso reactiva lighting_shader.shader al final, para las formas
// inmediatas que el resto del loop siga dibujando después.
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
		yaw := rng(&s) * 360.0

		// Deriva suave sobre el agua — fase y frecuencia propias por pad.
		phase := rng(&s) * 6.2832
		freq  := 0.5 + rng(&s) * 0.3
		amp   := cs * 0.05
		dx := math.cos(t * freq + phase) * amp
		dz := math.sin(t * freq * 0.8 + phase) * amp * 0.6

		pad_pos := raylib.Vector3{center.x + local_x + dx, center.y + 0.02, center.z + local_z + dz}

		kind := Lily_Model_Kind.PAD
		if rng(&s) > 0.5 {
			kind = .PAD_FLOWER
		}
		lm := lily_models[kind]
		sc := pr * lm.scale
		raylib.DrawModelEx(lm.model, pad_pos, {0, 1, 0}, yaw, {sc, sc, sc}, raylib.WHITE)
	}
	raylib.BeginShaderMode(lighting_shader.shader)
}

render_tower_ranges_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	raylib.BeginShaderMode(range_disc_shader)
	if app.settings.show_tower_range {
		for &tower in app.sim.towers {
			center, _ := tile_world_top(m, tower.r, tower.c)
			ring := raylib.Vector3{center.x, 0.02, center.z}
			draw_range_disc_3d(m, ring, tower.range * cs, constants.TOWER_RANGE_PREVIEW)
		}
	}
	if selected := entities.app_get_selected_tower(app); selected != nil {
		center, _ := tile_world_top(m, selected.r, selected.c)
		ring := raylib.Vector3{center.x, 0.02, center.z}
		// Antes eran 2 draw_ground_ring superpuestos (relleno tenue + "contorno"
		// blanco) porque el anillo viejo no tenía relleno real — el disco nuevo
		// ya trae el borde nítido incluido, una sola pasada alcanza.
		draw_range_disc_3d(m, ring, selected.range * cs, raylib.Color{255, 255, 255, 90})
	}
	raylib.EndShaderMode()
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
	raylib.BeginShaderMode(lighting_shader.shader)
	for row in 0 ..< m.height {
		for col in 0 ..< m.width {
			tile := m.grid[row][col]
			center, top_y := tile_world_top(m, row, col)
			surface := raylib.Vector3{center.x, top_y, center.z}

			#partial switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER,
			     .TOWER_ICE, .TOWER_ENHANCE, .TOWER_TESLA, .TOWER_MORTAR:
				// Especular suave prendido solo mientras se dibuja la torre —
				// ver SPECULAR_STRENGTH_WATER en lighting.fs para el agua,
				// que no necesita este bracket (siempre activo vía isWater).
				tower_spec := constants.LIGHT_SPECULAR_STRENGTH_TOWER
				raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_specular_strength, &tower_spec, .FLOAT)
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
					draw_tower_shape_3d(surface, constants.WORLD_CELL_SIZE, 0, 0, color, 255, tower_type_has_barrel(tower_type))
				}
				tower_spec_off := f32(0)
				raylib.SetShaderValue(lighting_shader.shader, lighting_shader.loc_specular_strength, &tower_spec_off, .FLOAT)
			case .ACCESSORY_TREE:
				if m.water_grid[row][col] {
					// El agua es perfectamente plana en toda la malla ahora
					// (_terrain_corner por categoría, ver Terrain_Corner_Category
					// más arriba — un tile de agua nunca promedia su altura
					// con la tierra vecina), así que no hace falta promediar
					// esquinas para saber dónde apoyar el nenúfar: es
					// WORLD_WATER_HEIGHT en cualquier punto de un tile de
					// agua, sin excepción.
					lily_center := raylib.Vector3{surface.x, constants.WORLD_WATER_HEIGHT, surface.z}
					render_water_lily_3d(lily_center, row, col)
				} else {
					// surface.y es la altura CRUDA del tile (tile_world_top, sin
					// promediar con vecinos) — la malla real interpola por
					// esquina (terrain_surface_height, igual que draw_range_disc_3d
					// y el nenúfar de arriba), así que plantar el árbol ahí lo
					// dejaba flotando o hundido según cómo diera el heightmap
					// crudo contra el promedio real en ese punto.
					u, v, dx, dz := tree_tile_offset(row, col)
					tree_y := terrain_surface_height(m, row, col, u, v)
					tree_surface := raylib.Vector3{surface.x + dx, tree_y, surface.z + dz}
					render_tree_3d(tree_surface, m.biome, row, col)
				}
			case .ACCESSORY_BLOCK:
				// Mismo motivo que el árbol de arriba: surface.y es la
				// altura cruda del tile, sin la interpolación real de la
				// malla — dejaba la casa flotando/hundida según la
				// pendiente. Centrado (u=v=0.5), sin el offset de los
				// árboles.
				blk_level := entities.map_get_obstacle_level(m, row, col)
				blk_y := terrain_surface_height(m, row, col, 0.5, 0.5)
				blk_surface := raylib.Vector3{surface.x, blk_y, surface.z}
				render_block_3d(blk_surface, m.biome, blk_level, row, col)
			}
		}
	}

	render_obstacles_3d(m, m.width, m.height)
	render_bridge_3d(m)
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
			draw_tower_shape_3d(surface, cs, 0, 0, spec.color, 160, tower_type_has_barrel(tower_type))
			ring := raylib.Vector3{surface.x, 0.02, surface.z}
			raylib.BeginShaderMode(range_disc_shader)
			draw_range_disc_3d(m, ring, spec.range * cs, constants.TOWER_RANGE_PREVIEW)
			if spec.aoe > 0 {
				draw_range_disc_3d(m, ring, spec.aoe * cs, raylib.Color{255, 180, 60, 180})
			}
			raylib.EndShaderMode()
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
			// DrawCylinder pinta radiusBottom en la base (position.y) y
			// radiusTop en la punta (position.y + height) — quedaba ancho
			// arriba y en punta abajo (cono al revés, "patas para arriba").
			base := raylib.Vector3{pos.x, pos.y + cs * 0.6, pos.z}
			raylib.DrawCylinder(base, 0, size_xz, size_y * 2, 4, color)
		case:
			center := raylib.Vector3{pos.x, pos.y + size_y, pos.z}
			raylib.DrawSphereEx(center, size_xz, 20, 20, color)
		}
	}
}

render_enemy_status_rings_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	raylib.BeginShaderMode(range_disc_shader)
	for &enemy in app.sim.enemies {
		pos := world_from_raw_grid(m, enemy.x, enemy.y)
		size := entities.enemy_get_size(&enemy) * cs
		squash := enemy.hit_squash * constants.ENEMY_HIT_SQUASH_AMOUNT
		size_xz := size * (1 + squash)

		if .ARMORED in enemy.flags {
			draw_range_disc_3d(m, {pos.x, 0.02, pos.z}, size_xz * 1.1, constants.COLOR_ENEMY_ARMORED)
		}
		if enemy.slow_timer > 0 {
			pulse := f32(math.abs(math.sin(f64(raylib.GetTime()) * 5.0)))
			alpha := u8(60.0 + 50.0 * pulse)
			draw_range_disc_3d(m, {pos.x, 0.03, pos.z}, size_xz * 1.2, raylib.Color{100, 200, 255, alpha})
		}
	}
	raylib.EndShaderMode()
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
	raylib.BeginShaderMode(range_disc_shader)
	for &pulse in app.sim.ice_pulses {
		pos := world_from_centered_grid(m, pulse.x, pulse.y)
		t := pulse.life / pulse.max_life
		alpha := u8(t * 210.0)
		ring := raylib.Vector3{pos.x, 0.02, pos.z}
		draw_range_disc_3d(m, ring, pulse.radius * cs, raylib.Color{180, 235, 255, alpha})
	}
	raylib.EndShaderMode()
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
	if len(app.sim.glow_particles) == 0 { return }
	cs := constants.WORLD_CELL_SIZE
	raylib.BeginShaderMode(glow_ring_shader)
	for &p in app.sim.glow_particles {
		progress := p.t / p.lifetime
		ease := progress * progress
		alpha := u8((1.0 - progress) * 255)
		radius := p.radius_start + (p.radius_end - p.radius_start) * progress
		dy_cells := p.dy_start + (p.dy_end - p.dy_start) * ease
		pos := world_from_centered_grid(m, p.grid_x, p.grid_y)
		pos.y += -dy_cells * cs + 0.05
		// SPAWN: anillos blancos. GOAL_REACH: rojo oscuro — mismo criterio
		// que el viejo glow_circle.glsl 2D (comentario original: "enemy
		// spawn = white circles rise; goal reach = dark red circles fall").
		tint := raylib.Color{255, 255, 255, alpha}
		if p.kind == .GOAL_REACH {
			tint = raylib.Color{200, 60, 60, alpha}
		}
		draw_glow_ring_3d(pos, radius * cs, tint)
	}
	raylib.EndShaderMode()
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
	render_airdrop_plane_3d(app)
	raylib.EndShaderMode()

	render_enemy_status_rings_3d(app, m)
}

// Caja de airdrop ya aterrizada — modelo real de cajón de madera (antes
// era un DrawCube liso; antes de eso, un dibujo pixel-art 2D reproyectado).
// La estela/paracaídas/ping/indicador de borde se quedan 2D screen-space a
// propósito (ver render_airdrops) — son overlays "siempre visibles en
// pantalla", no objetos del mundo; el avión SÍ pasó a 3D real, ver
// render_airdrop_plane_3d.
render_airdrop_boxes_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	sc := crate_model.scale
	for &drop in app.sim.airdrops {
		if drop.phase != .BOX_LANDED { continue }
		center, top_y := tile_world_top(m, drop.target_row, drop.target_col)
		pos := raylib.Vector3{center.x, top_y, center.z}
		yaw := hash_random(drop.target_row, drop.target_col, 21) * 360.0
		raylib.DrawModelEx(crate_model.model, pos, {0, 1, 0}, yaw, {sc, sc, sc}, raylib.WHITE)
	}
	raylib.BeginShaderMode(lighting_shader.shader)
}

// Sombra real de la caja — mismo patrón shader-swap que render_tree_shadow_3d.
render_airdrop_boxes_shadow_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	sc := crate_model.scale
	for i in 0 ..< int(crate_model.model.materialCount) {
		crate_model.model.materials[i].shader = shadow_map.depth_shader
	}
	for &drop in app.sim.airdrops {
		if drop.phase != .BOX_LANDED { continue }
		center, top_y := tile_world_top(m, drop.target_row, drop.target_col)
		pos := raylib.Vector3{center.x, top_y, center.z}
		yaw := hash_random(drop.target_row, drop.target_col, 21) * 360.0
		raylib.DrawModelEx(crate_model.model, pos, {0, 1, 0}, yaw, {sc, sc, sc}, raylib.WHITE)
	}
	for i in 0 ..< int(crate_model.model.materialCount) {
		crate_model.model.materials[i].shader = tree_shader.shader
	}
}

// Avión F-16 volando (fase PLANE_FLYING) — geometría 3D real dentro del
// mundo, no un dibujo 2D reproyectado como antes. Reusa la misma posición
// 2D→3D que ya calculaba render_airdrops (ver esa función para el porqué:
// el sistema de airdrops sigue en coordenadas de mundo 2D viejas). yaw:
// `angle` es atan2(dir_y, dir_x), mismo convenio 2D que usa el ángulo de
// las torres (dir := {cos(angle),0,sin(angle)}) — con el modelo modelado
// con la nariz en +X local, alinear esa nariz a `dir` requiere yaw =
// -angle en grados (una rotación positiva alrededor de +Y en raylib manda
// +X hacia -Z, el sentido opuesto a como crece `angle` acá).
render_airdrop_plane_3d :: proc(app: ^entities.App_State) {
	cs2d := f32(app.settings.cell_size)
	scale_to_3d := constants.WORLD_CELL_SIZE / cs2d
	PLANE_ALTITUDE :: f32(3.0)
	sc := plane_model.scale

	for &drop in app.sim.airdrops {
		// El avión sigue volando (y hay que seguir dibujándolo) más allá de
		// que la caja ya haya empezado a caer/aterrizado — drop.phase pasa
		// a describir la fase de la CAJA en cuanto se suelta, así que ya no
		// sirve para decidir si el avión sigue en pantalla. plane_x < -9000
		// es el único centinela real (ver airdrop_update, simulation.odin).
		if drop.plane_x < -9000 { continue }
		pos := raylib.Vector3{drop.plane_x * scale_to_3d, PLANE_ALTITUDE, drop.plane_y * scale_to_3d}
		angle := math.atan2_f32(drop.plane_dir_y, drop.plane_dir_x)
		yaw := -angle * (180.0 / math.PI)
		raylib.DrawModelEx(plane_model.model, pos, {0, 1, 0}, yaw, {sc, sc, sc}, raylib.WHITE)
	}
	raylib.BeginShaderMode(lighting_shader.shader)
}

// Sombra real del avión — mismo patrón shader-swap. El frustum de sombra
// cubre hasta SHADOW_WORLD_Y_MAX=4.0, por encima de PLANE_ALTITUDE=3.0,
// así que el avión entra sin tocar el rango del shadow map.
render_airdrop_plane_shadow_3d :: proc(app: ^entities.App_State) {
	cs2d := f32(app.settings.cell_size)
	scale_to_3d := constants.WORLD_CELL_SIZE / cs2d
	PLANE_ALTITUDE :: f32(3.0)
	sc := plane_model.scale

	for i in 0 ..< int(plane_model.model.materialCount) {
		plane_model.model.materials[i].shader = shadow_map.depth_shader
	}
	for &drop in app.sim.airdrops {
		if drop.plane_x < -9000 { continue }
		pos := raylib.Vector3{drop.plane_x * scale_to_3d, PLANE_ALTITUDE, drop.plane_y * scale_to_3d}
		angle := math.atan2_f32(drop.plane_dir_y, drop.plane_dir_x)
		yaw := -angle * (180.0 / math.PI)
		raylib.DrawModelEx(plane_model.model, pos, {0, 1, 0}, yaw, {sc, sc, sc}, raylib.WHITE)
	}
	for i in 0 ..< int(plane_model.model.materialCount) {
		plane_model.model.materials[i].shader = tree_shader.shader
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

	// En DEVELOPER se apaga el shader del vórtice detrás de los paneles —
	// molesta durante el desarrollo (distrae/cuesta rendimiento en cada
	// recarga), sin motivo para tenerlo prendido fuera de una build final.
	if constants.NEBULA_BACKGROUND_ENABLED && !constants.DEVELOPER &&
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

	// Shadow mapping: el depth pre-pass usa su propio framebuffer (Enable/
	// DisableFramebuffer de rlgl, no BeginTextureMode) — tiene que completar
	// ANTES de que arranque el BeginTextureMode de pause_blur más abajo, si
	// no, el DisableFramebuffer del shadow pass pisaría el framebuffer del
	// blur en vez de dejarlo activo. Por eso va acá afuera, no "justo antes
	// de BeginMode3D" como el resto del bloque 3D.
	if app.state == .PLAYING || app.state == .PAUSED || app.state == .EDITOR {
		m := &app.editor.game_map
		dn_sun_dir := linalg.normalize(day_night_sample(lighting_shader.day_night_anim_time).sun_dir)
		render_shadow_depth_pass(app, m, dn_sun_dir)
		shadow_map_bind_for_sampling()
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

		raylib.ClearBackground(sky_color_from_sun())
		raylib.BeginMode3D(app.camera3d)
		render_map_3d(app, m)
		if app.settings.show_grid {
			render_grid_lines_3d(app, m)
		}
		render_tower_ranges_3d(app, m)
		render_spawn_goal_markers_3d(app, m)
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
	camera := camera3d_for_focus(focus, zoom, 0)  // miniatura: siempre yaw=0, independiente de la cámara en vivo

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

	// Mismo shadow pass que render_game — una vez por preview generado, no
	// por frame, así que el costo es irrelevante. Tiene que completar antes
	// del BeginTextureMode de abajo (mismo motivo que en render_game: el
	// framebuffer propio del shadow pass no debe pisar el del preview_tex).
	dn_sun_dir := linalg.normalize(day_night_sample(lighting_shader.day_night_anim_time).sun_dir)
	render_shadow_depth_pass(app, m, dn_sun_dir)
	shadow_map_bind_for_sampling()

	raylib.BeginTextureMode(app.editor.browser.preview_tex)
	raylib.ClearBackground(sky_color_from_sun())
	raylib.BeginMode3D(camera)
	render_map_3d(app, m)
	render_spawn_goal_markers_3d(app, m)
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
// Ancho real en unidades de mundo (no píxeles) de la línea de grilla — ver
// draw_grid_line_ribbon_3d, por qué hace falta ser geometría real y no
// DrawLine3D. Punto de partida, no verificado en pantalla.
GRID_LINE_WIDTH :: f32(0.02)

// Cinta angosta acostada sobre el terreno entre dos puntos — reemplaza a
// DrawLine3D para que el ancho de la línea sea geometría 3D real (un quad
// finito en unidades de mundo) en vez de la primitiva GL_LINES, que se
// rasteriza a un ancho FIJO EN PÍXELES DE PANTALLA sin importar la
// distancia de la cámara (por eso la grilla se veía siempre del mismo
// grosor de cerca o de lejos). Con un quad real, la perspectiva normal ya
// hace que se vea más ancha cerca y más fina lejos, sin ningún cálculo de
// distancia a mano. Perpendicular en el plano XZ (la grilla es
// básicamente horizontal, apoyada en el terreno — no hace falta billboard
// hacia la cámara).
draw_grid_line_ribbon_3d :: proc(p0, p1: raylib.Vector3, width: f32, color: raylib.Color) {
	dx := p1.x - p0.x
	dz := p1.z - p0.z
	length := math.sqrt(dx * dx + dz * dz)
	if length < 0.0001 { return }
	half := width * 0.5
	perp_x := -dz / length * half
	perp_z := dx / length * half

	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	rlgl.TexCoord2f(0, 0); rlgl.Vertex3f(p0.x - perp_x, p0.y, p0.z - perp_z)
	rlgl.TexCoord2f(0, 1); rlgl.Vertex3f(p0.x + perp_x, p0.y, p0.z + perp_z)
	rlgl.TexCoord2f(1, 1); rlgl.Vertex3f(p1.x + perp_x, p1.y, p1.z + perp_z)
	rlgl.TexCoord2f(1, 0); rlgl.Vertex3f(p1.x - perp_x, p1.y, p1.z - perp_z)
	rlgl.End()
}

// Dibuja un segmento de grilla entre dos puntos de esquina (r0,c0)-(r1,c1),
// con la altura resuelta para UNA categoría (agua o tierra) — ver el
// comentario grande en render_grid_lines_3d sobre por qué hace falta
// elegir categoría acá también, no solo en la malla real. En un punto de
// esquina exacto (u,v ∈ {0,1}), _terrain_corner_lerp se reduce exactamente
// a _terrain_corner sin pasar por ningún tile "dueño" — por eso alcanza
// con pedirle la esquina directo, igual que hace terrain_cache_ensure.
_grid_draw_segment :: proc(m: ^entities.Map, biome_colors: constants.Biome_Colors, r0, c0, r1, c1: i32, x0, z0, x1, z1: f32, is_water: bool, lift: f32) {
	category := Terrain_Corner_Category.WATER if is_water else .LAND
	h0, _ := _terrain_corner(m, r0, c0, biome_colors, category)
	h1, _ := _terrain_corner(m, r1, c1, biome_colors, category)
	draw_grid_line_ribbon_3d({x0, h0 + lift, z0}, {x1, h1 + lift, z1}, GRID_LINE_WIDTH, constants.COLOR_GRID_LINE)
}

// La grilla no puede seguir usando _terrain_corner sin categoría (.ANY):
// desde que el agua es plana de verdad y la tierra tiene su propio
// desnivel sin mezclarse (Terrain_Corner_Category, ver más arriba), un
// punto de esquina compartido entre un tile de agua y uno de tierra YA NO
// tiene una única altura — tiene DOS, una por lado, con un escalón real
// entre ellas (la pared de orilla). Un segmento de grilla que cruza ese
// borde necesita la misma categoría que el tile al que pertenece: si los
// dos tiles que tocan el segmento son de la MISMA categoría, una sola
// línea alcanza (da la altura de siempre, sin cambios); si son de
// categorías DISTINTAS, se dibujan DOS líneas superpuestas en X/Z pero a
// la altura de cada lado — la grilla también "escalona" en la orilla, en
// vez de flotar a una altura promedio que no es ninguna de las dos reales.
render_grid_lines_3d :: proc(app: ^entities.App_State, m: ^entities.Map) {
	cs := constants.WORLD_CELL_SIZE
	biome_colors := constants.BIOME_COLORS[m.biome]
	LIFT :: f32(0.03)  // evita z-fighting contra la superficie del terreno

	frame_dt := min(raylib.GetFrameTime(), constants.WATER_ANIM_MAX_DT)
	grid_line_anim_time += frame_dt * constants.GRID_LINE_NOISE_SPEED
	raylib.SetShaderValue(grid_line_shader, grid_line_shader_loc_noise_time, &grid_line_anim_time, .FLOAT)
	raylib.BeginShaderMode(grid_line_shader)
	defer raylib.EndShaderMode()

	for r in 0 ..= m.height {
		for c in 0 ..= m.width {
			// Segmento horizontal (r,c)-(r,c+1): lo bordean el tile de
			// ARRIBA (r-1,c) y el de ABAJO (r,c) — la fila de tiles a cada
			// lado de esta línea de grilla en Z.
			if c < m.width {
				x0, x1 := f32(c) * cs, f32(c + 1) * cs
				z := f32(r) * cs
				has_above := r > 0
				has_below := r < m.height
				cat_above := m.water_grid[r - 1][c] if has_above else false
				cat_below := m.water_grid[r][c] if has_below else false
				if has_above && has_below && cat_above != cat_below {
					_grid_draw_segment(m, biome_colors, r, c, r, c + 1, x0, z, x1, z, cat_above, LIFT)
					_grid_draw_segment(m, biome_colors, r, c, r, c + 1, x0, z, x1, z, cat_below, LIFT)
				} else if has_above || has_below {
					cat := cat_above if has_above else cat_below
					_grid_draw_segment(m, biome_colors, r, c, r, c + 1, x0, z, x1, z, cat, LIFT)
				}
			}
			// Segmento vertical (r,c)-(r+1,c): lo bordean el tile de la
			// IZQUIERDA (r,c-1) y el de la DERECHA (r,c).
			if r < m.height {
				x := f32(c) * cs
				z0, z1 := f32(r) * cs, f32(r + 1) * cs
				has_left := c > 0
				has_right := c < m.width
				cat_left := m.water_grid[r][c - 1] if has_left else false
				cat_right := m.water_grid[r][c] if has_right else false
				if has_left && has_right && cat_left != cat_right {
					_grid_draw_segment(m, biome_colors, r, c, r + 1, c, x, z0, x, z1, cat_left, LIFT)
					_grid_draw_segment(m, biome_colors, r, c, r + 1, c, x, z0, x, z1, cat_right, LIFT)
				} else if has_left || has_right {
					cat := cat_left if has_left else cat_right
					_grid_draw_segment(m, biome_colors, r, c, r + 1, c, x, z0, x, z1, cat, LIFT)
				}
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

		// ── Estela jet + llama de motor (mientras el avión siga en pantalla,
		// más allá de en qué fase esté la caja — ver la nota grande en
		// airdrop_update, simulation.odin: drop.phase pasa a describir la
		// fase de la CAJA en cuanto se suelta, plane_x < -9000 es el único
		// centinela real de "avión todavía visible") ─────────────────────
		if drop.plane_x > -9000 {
			if drop.trail_len > 1 {
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

			// El cuerpo del avión (F-16 real, ver plane_model) ya se dibuja
			// en 3D de verdad dentro de BeginMode3D — render_airdrop_plane_3d,
			// llamado desde render_gameplay_3d. Acá solo queda la llama del
			// motor (single-engine, a diferencia del avión genérico viejo de
			// 2 motores) como acento 2D barato — no vale la pena un glow
			// real en 3D para un solo círculo chico.
			angle := math.atan2_f32(drop.plane_dir_y, drop.plane_dir_x)
			cos_a := math.cos_f32(angle)
			sin_a := math.sin_f32(angle)
			z     := app.zoom

			// Tobera del motor, detrás del fuselaje (lx negativo = atrás).
			nozzle_cx := drop.plane_x + (-16)*cos_a
			nozzle_cy := drop.plane_y + (-16)*sin_a
			nozzle_screen := project(app, nozzle_cx, nozzle_cy, scale_to_3d, PLANE_ALTITUDE)
			raylib.DrawCircleV(
				nozzle_screen,
				f32(3) * z,
				raylib.Color{255, 140, 40, 200},
			)
		}

		switch drop.phase {

		case .PLANE_FLYING:
			// No queda nada específico de esta fase acá — el avión (estela,
			// llama, modelo 3D) ya se maneja arriba de forma independiente
			// de drop.phase, ver la nota grande de más arriba.

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

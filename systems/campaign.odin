package systems

import "../constants"
import "../entities"
import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

// ─────────────────────────────────────────────────────────────────────────────
// Campaign editor — reutiliza el map browser. Activado vía toggle "Campaña"
// en el footer (sólo cuando constants.DEVELOPER). Cuando está activo, el
// panel derecho del browser se reemplaza por la lista de nodos editables y
// el footer cambia a Agregar / Guardar / Salir.
// ─────────────────────────────────────────────────────────────────────────────

// Recalcula requires_node de cada nodo: el predecesor del nodo i es el último
// nodo no-OPTIONAL anterior. Mantiene el main path conectado cuando se
// insertan o togglean opcionales sin gatear la cadena principal.
campaign_editor_recompute_requires :: proc(c: ^entities.Campaign_File) {
	for i in 0 ..< int(c.node_count) {
		c.nodes[i].requires_node = -1
		for j := i - 1; j >= 0; j -= 1 {
			if .OPTIONAL not_in c.nodes[j].flags {
				c.nodes[i].requires_node = i32(j)
				break
			}
		}
	}
}

// Entra al modo edición de campaña. Sólo carga campaign.bin si todavía no fue
// cargada esta sesión — así si reabrís el editor después de hacer cambios, los
// preserva. Para forzar reload desde disco, setear app.campaign_loaded = false
// antes de entrar.
campaign_editor_enter :: proc(app: ^entities.App_State) {
	if !app.campaign_loaded {
		loaded, ok := entities.campaign_load()
		if ok {
			app.campaign = loaded
		} else {
			app.campaign = entities.Campaign_File{}
		}
		app.campaign_loaded = true
	}
	app.editor.campaign_editor.active        = true
	app.editor.campaign_editor.selected_node = -1
	app.editor.campaign_editor.scroll        = 0
	// No resetar dirty — si entraste con cambios pendientes, los conservás.
}

// Sale del modo edición de campaña. No persiste cambios — el dev debe haber
// pulsado Guardar antes. Si tiene cambios sin guardar muestra warning.
campaign_editor_exit :: proc(app: ^entities.App_State) {
	if app.editor.campaign_editor.dirty {
		entities.add_toast(app, "Saliste sin guardar — cambios perdidos", .WARNING, 3.0)
	}
	app.editor.campaign_editor.active        = false
	app.editor.campaign_editor.selected_node = -1
}

// Agrega el mapa seleccionado en el browser como nuevo nodo al final de la
// campaña. Marca dirty.
campaign_editor_add_selected_map :: proc(app: ^entities.App_State) {
	sel := app.editor.browser.selected
	if sel < 0 || int(sel) >= len(app.editor.browser.entries) {
		entities.add_toast(app, constants.get_text("CAMPAIGN_EDITOR_SELECT_MAP_FIRST"), .WARNING, 2.0)
		play_sound(.ERROR, .UI)
		return
	}
	if app.campaign.node_count >= i32(constants.CAMPAIGN_MAX_NODES) {
		entities.add_toast(app, "Campaña llena (máximo de nodos)", .ERROR, 2.5)
		play_sound(.ERROR, .UI)
		return
	}
	entry := app.editor.browser.entries[sel]
	node  := entities.campaign_node_init(entry.name, entry.name, 0, 0)
	idx   := entities.campaign_append_node(&app.campaign, node)
	if idx < 0 { return }
	campaign_editor_recompute_requires(&app.campaign)
	app.editor.campaign_editor.selected_node = idx
	app.editor.campaign_editor.dirty         = true
	play_sound(.CONFIRMATION, .UI)
}

// Elimina el nodo seleccionado de la campaña.
campaign_editor_remove_selected_node :: proc(app: ^entities.App_State) {
	idx := app.editor.campaign_editor.selected_node
	if idx < 0 || idx >= app.campaign.node_count { return }
	if entities.campaign_remove_node(&app.campaign, idx) {
		campaign_editor_recompute_requires(&app.campaign)
		app.editor.campaign_editor.selected_node = -1
		app.editor.campaign_editor.dirty         = true
		play_sound(.CLICK, .UI)
	}
}

// Mueve el nodo seleccionado una posición arriba o abajo en la secuencia.
campaign_editor_move_selected :: proc(app: ^entities.App_State, delta: i32) {
	idx := app.editor.campaign_editor.selected_node
	if idx < 0 || idx >= app.campaign.node_count { return }
	new_idx := idx + delta
	if new_idx < 0 || new_idx >= app.campaign.node_count { return }
	// Swap
	c := &app.campaign
	c.nodes[idx], c.nodes[new_idx] = c.nodes[new_idx], c.nodes[idx]
	app.editor.campaign_editor.selected_node = new_idx
	campaign_editor_recompute_requires(c)
	app.editor.campaign_editor.dirty = true
	play_sound(.CLICK, .UI)
}

// Toggle de un flag del nodo seleccionado.
campaign_editor_toggle_flag :: proc(app: ^entities.App_State, flag: entities.Campaign_Node_Flag) {
	idx := app.editor.campaign_editor.selected_node
	if idx < 0 || idx >= app.campaign.node_count { return }
	node := &app.campaign.nodes[idx]
	if flag in node.flags {
		node.flags -= {flag}
	} else {
		node.flags |= {flag}
	}
	campaign_editor_recompute_requires(&app.campaign)
	app.editor.campaign_editor.dirty = true
	play_sound(.CLICK, .UI)
}

// Persiste la campaña a campaign.bin.
campaign_editor_save :: proc(app: ^entities.App_State) {
	if entities.campaign_save(&app.campaign) {
		app.editor.campaign_editor.dirty = false
		entities.add_toast(app, "campaign.bin guardado", .SUCCESS, 2.0)
		play_sound(.CONFIRMATION, .UI)
	} else {
		entities.add_toast(app, "Error al guardar campaign.bin", .ERROR, 3.0)
		play_sound(.ERROR, .UI)
	}
}

// Renderiza el panel derecho del browser cuando campaign_editor_active=true.
// Muestra: header con conteo + dirty marker, lista de nodos con flags badges,
// panel de propiedades del nodo seleccionado (toggles + move up/down + remove).
render_campaign_editor_right_panel :: proc(
	app: ^entities.App_State,
	content_y, content_h, preview_x, preview_w: i32,
) {
	c     := &app.campaign
	mouse := raylib.GetMousePosition()

	font_md : f32 = 14
	font_sm : f32 = 11
	pad     : i32 = 8

	// ── Header: nombre de la campaña + conteo + dirty marker ────────────────
	header_y := content_y + pad
	dirty_marker := "" if !app.editor.campaign_editor.dirty else "  •"
	header_base := constants.get_text_f("CAMPAIGN_EDITOR_HEADER",
		c.node_count, constants.CAMPAIGN_MAX_NODES)
	header := fmt.tprintf("%s%s", header_base, dirty_marker)
	header_cs := strings.clone_to_cstring(header, context.temp_allocator)
	raylib.DrawTextEx(
		constants.game_fonts.bold, header_cs,
		{f32(preview_x), f32(header_y)},
		font_md, 0, constants.UI_TEXT_COLOR,
	)

	// ── Lista de nodos ────────────────────────────────────────────────────────
	list_y := header_y + i32(font_md) + i32(pad)
	// Reservar espacio para el property panel abajo
	props_h: i32 = 110
	list_h := content_h - (list_y - content_y) - props_h - i32(pad)
	item_h: i32 = 22

	if c.node_count == 0 {
		hint_cs := strings.clone_to_cstring(constants.get_text("CAMPAIGN_EDITOR_EMPTY"),
			context.temp_allocator)
		raylib.DrawTextEx(
			constants.game_fonts.regular, hint_cs,
			{f32(preview_x), f32(list_y + pad)},
			font_sm, 0, constants.UI_MAP_BROWSER_MUTED_COLOR,
		)
	}

	visible := list_h / item_h
	for i in 0 ..< visible {
		node_idx := i + app.editor.campaign_editor.scroll
		if node_idx >= c.node_count { break }
		node := &c.nodes[node_idx]

		item_y := list_y + i * item_h
		rect := raylib.Rectangle{
			f32(preview_x), f32(item_y),
			f32(preview_w), f32(item_h - 2),
		}
		hovered := raylib.CheckCollisionPointRec(mouse, rect)
		selected := node_idx == app.editor.campaign_editor.selected_node

		// Fondo según estado
		if selected {
			raylib.DrawRectangleRounded(rect, 0.2, 6, constants.UI_MAP_BROWSER_SELECTED_BG_COLOR)
		} else if hovered {
			raylib.DrawRectangleRounded(rect, 0.2, 6, constants.UI_BUTTON_HOVER_COLOR)
		}

		// "1.  map_name  [BOSS][OPT][FIN]"
		fname := entities.campaign_node_map_filename(node)
		prefix := fmt.tprintf("%d. %s", node_idx + 1, fname)
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring(prefix, context.temp_allocator),
			{rect.x + 6, rect.y + (rect.height - font_sm) / 2},
			font_sm, 0, constants.UI_TEXT_COLOR,
		)

		// Badges de flags a la derecha
		badge_x := rect.x + rect.width - 6
		draw_badge :: proc(text: cstring, x_right: f32, y_center: f32, active: bool, font: raylib.Font) -> f32 {
			fs : f32 = 10
			tw := raylib.MeasureTextEx(font, text, fs, 0).x
			pad_h : f32 = 4
			bw := tw + pad_h * 2
			rect_b := raylib.Rectangle{x_right - bw, y_center - 7, bw, 14}
			col_bg := raylib.Color{120, 120, 120, 200} if active else raylib.Color{60, 60, 60, 120}
			col_fg := raylib.Color{255, 255, 255, 255} if active else raylib.Color{180, 180, 180, 255}
			raylib.DrawRectangleRounded(rect_b, 0.3, 4, col_bg)
			raylib.DrawTextEx(font, text, {rect_b.x + pad_h, rect_b.y + 2}, fs, 0, col_fg)
			return x_right - bw - 4
		}
		y_mid := rect.y + rect.height / 2
		if .FINALE in node.flags {
			badge_x = draw_badge(fmt.ctprintf("FIN"), badge_x, y_mid, true, constants.game_fonts.bold)
		}
		if .OPTIONAL in node.flags {
			badge_x = draw_badge(fmt.ctprintf("OPT"), badge_x, y_mid, true, constants.game_fonts.bold)
		}
		if .BOSS in node.flags {
			badge_x = draw_badge(fmt.ctprintf("BOSS"), badge_x, y_mid, true, constants.game_fonts.bold)
		}

		// Click sobre el nodo lo selecciona
		if hovered && raylib.IsMouseButtonPressed(.LEFT) {
			app.editor.campaign_editor.selected_node = node_idx
		}
	}

	// ── Property panel del nodo seleccionado ─────────────────────────────────
	props_y := content_y + content_h - props_h
	raylib.DrawLine(
		preview_x, props_y,
		preview_x + preview_w, props_y,
		constants.UI_MAP_BROWSER_SEPARATOR_COLOR,
	)

	sel := app.editor.campaign_editor.selected_node
	if sel < 0 || sel >= c.node_count {
		hint_cs := strings.clone_to_cstring(constants.get_text("CAMPAIGN_EDITOR_NO_SELECTION"),
			context.temp_allocator)
		raylib.DrawTextEx(
			constants.game_fonts.regular, hint_cs,
			{f32(preview_x), f32(props_y + pad)},
			font_sm, 0, constants.UI_MAP_BROWSER_MUTED_COLOR,
		)
		return
	}

	node := &c.nodes[sel]

	// Línea 1: "Nodo N — <map>"
	title := constants.get_text_f("CAMPAIGN_EDITOR_NODE_TITLE",
		sel + 1, entities.campaign_node_map_filename(node))
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		strings.clone_to_cstring(title, context.temp_allocator),
		{f32(preview_x), f32(props_y + pad)},
		font_sm, 0, constants.UI_TEXT_COLOR,
	)

	// Línea 2: requires_node info
	req_str: string
	if node.requires_node < 0 {
		req_str = constants.get_text("CAMPAIGN_EDITOR_PRED_NONE")
	} else {
		req_str = constants.get_text_f("CAMPAIGN_EDITOR_PRED_AUTO", node.requires_node + 1)
	}
	raylib.DrawTextEx(
		constants.game_fonts.regular,
		strings.clone_to_cstring(req_str, context.temp_allocator),
		{f32(preview_x), f32(props_y + pad + i32(font_sm) + 4)},
		font_sm, 0, constants.UI_MAP_BROWSER_MUTED_COLOR,
	)

	// Botones de acción — fila horizontal
	btn_y2 := props_y + props_h - 30
	btn_h2 : f32 = 24
	btn_w2 : f32 = 56
	gap    : f32 = 4
	x      := f32(preview_x)

	// Toggles de flags
	flag_active_color   := constants.UI_BUTTON_ACTION_COLOR
	flag_inactive_color := constants.COLOR_NONE
	if render_button("BOSS", {x, f32(btn_y2), btn_w2, btn_h2}, {
		text_color    = constants.UI_TEXT_COLOR,
		button_color  = flag_active_color if .BOSS in node.flags else flag_inactive_color,
		hover_color   = constants.UI_BUTTON_ACTION_HOVER,
		pressed_color = constants.UI_BUTTON_ACTION_PRESS,
	}) {
		campaign_editor_toggle_flag(app, .BOSS)
	}
	x += btn_w2 + gap

	if render_button("OPT", {x, f32(btn_y2), btn_w2, btn_h2}, {
		text_color    = constants.UI_TEXT_COLOR,
		button_color  = flag_active_color if .OPTIONAL in node.flags else flag_inactive_color,
		hover_color   = constants.UI_BUTTON_ACTION_HOVER,
		pressed_color = constants.UI_BUTTON_ACTION_PRESS,
	}) {
		campaign_editor_toggle_flag(app, .OPTIONAL)
	}
	x += btn_w2 + gap

	if render_button("FIN", {x, f32(btn_y2), btn_w2, btn_h2}, {
		text_color    = constants.UI_TEXT_COLOR,
		button_color  = flag_active_color if .FINALE in node.flags else flag_inactive_color,
		hover_color   = constants.UI_BUTTON_ACTION_HOVER,
		pressed_color = constants.UI_BUTTON_ACTION_PRESS,
	}) {
		campaign_editor_toggle_flag(app, .FINALE)
	}
	x += btn_w2 + gap + 8

	// Move up/down
	if render_button("↑", {x, f32(btn_y2), 28, btn_h2}) {
		campaign_editor_move_selected(app, -1)
	}
	x += 28 + gap

	if render_button("↓", {x, f32(btn_y2), 28, btn_h2}) {
		campaign_editor_move_selected(app, +1)
	}
	x += 28 + gap + 8

	// Remove
	if render_button(constants.get_text("CAMPAIGN_EDITOR_REMOVE"), {x, f32(btn_y2), 60, btn_h2}, {
		text_color    = constants.UI_TEXT_COLOR,
		button_color  = constants.UI_BUTTON_SELL_COLOR,
		hover_color   = constants.UI_BUTTON_SELL_HOVER,
		pressed_color = constants.UI_BUTTON_SELL_PRESS,
	}) {
		campaign_editor_remove_selected_node(app)
	}
}

// Renderiza el footer del browser en modo campaña: Salir / Agregar / Guardar.
render_campaign_editor_footer :: proc(
	app: ^entities.App_State,
	panel_x, panel_w, btn_y: i32,
	btn_w, btn_h: i32,
	side_pad: i32,
) {
	exit_x := panel_x + side_pad * 2
	save_x := panel_x + panel_w - btn_w - side_pad * 2
	add_x  := panel_x + panel_w / 2 - btn_w / 2

	if render_button(constants.get_text("CAMPAIGN_EDITOR_EXIT"), {f32(exit_x), f32(btn_y), f32(btn_w), f32(btn_h)}) {
		campaign_editor_exit(app)
		play_sound(.CLICK, .UI)
	}

	if render_button(constants.get_text("CAMPAIGN_EDITOR_ADD"), {f32(add_x), f32(btn_y), f32(btn_w), f32(btn_h)}, {
		text_color    = constants.UI_TEXT_COLOR,
		button_color  = constants.UI_BUTTON_ACTION_COLOR,
		hover_color   = constants.UI_BUTTON_ACTION_HOVER,
		pressed_color = constants.UI_BUTTON_ACTION_PRESS,
	}) {
		campaign_editor_add_selected_map(app)
	}

	save_color := constants.UI_BUTTON_ACTION_COLOR if app.editor.campaign_editor.dirty else constants.COLOR_NONE
	if render_button(constants.get_text("CAMPAIGN_EDITOR_SAVE"), {f32(save_x), f32(btn_y), f32(btn_w), f32(btn_h)}, {
		text_color    = constants.UI_TEXT_COLOR,
		button_color  = save_color,
		hover_color   = constants.UI_BUTTON_ACTION_HOVER,
		pressed_color = constants.UI_BUTTON_ACTION_PRESS,
	}) {
		campaign_editor_save(app)
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Campaign map (visualizador) — Game_State.CAMPAIGN_MAP
//
// Layout automático: nodos del main path (sin OPTIONAL) en línea horizontal,
// los OPTIONAL cuelgan arriba/abajo de su requires_node con leve offset en X.
// El render usa el shader de nebula como fondo (drawn by render_game).
// ─────────────────────────────────────────────────────────────────────────────

// Calcula posiciones en [0..1]² para cada nodo.
// El array se devuelve por valor — son ~64 × 8 bytes = 512 bytes, no es mucho.
compute_campaign_layout :: proc(c: ^entities.Campaign_File) -> [constants.CAMPAIGN_MAX_NODES][2]f32 {
	layout: [constants.CAMPAIGN_MAX_NODES][2]f32

	// Contar nodos del main path (no OPTIONAL)
	main_count := 0
	for i in 0 ..< int(c.node_count) {
		if .OPTIONAL not_in c.nodes[i].flags { main_count += 1 }
	}
	if main_count == 0 { return layout }

	// Distribuir nodos del main path sobre la línea horizontal central
	main_idx := 0
	for i in 0 ..< int(c.node_count) {
		if .OPTIONAL in c.nodes[i].flags { continue }
		x: f32
		if main_count == 1 {
			x = 0.5
		} else {
			x = f32(main_idx) / f32(main_count - 1)
		}
		layout[i] = {x, 0.5}
		main_idx += 1
	}

	// Posicionar OPTIONAL cerca de su parent (requires_node)
	for i in 0 ..< int(c.node_count) {
		if .OPTIONAL not_in c.nodes[i].flags { continue }
		parent_idx := c.nodes[i].requires_node

		parent_x: f32 = 0.5
		parent_y: f32 = 0.5
		if parent_idx >= 0 && int(parent_idx) < int(c.node_count) {
			parent_x = layout[parent_idx].x
			parent_y = layout[parent_idx].y
		}

		// Contar hermanos opcionales anteriores (mismos parent) para decidir lado
		sibling_idx := 0
		for j in 0 ..< i {
			if .OPTIONAL in c.nodes[j].flags && c.nodes[j].requires_node == parent_idx {
				sibling_idx += 1
			}
		}

		// Alternar arriba/abajo; cada par adicional se aleja más en X
		y_offset: f32 = 0.22
		if sibling_idx % 2 == 1 { y_offset = -0.22 }
		x_offset := f32(0.06) + f32(sibling_idx / 2) * 0.06

		layout[i] = {parent_x + x_offset, parent_y + y_offset}
	}

	return layout
}

// Inicia el run del nodo de campaña dado: carga el mapa, aplica overrides y
// transiciona a PLAYING. Setea app.current_campaign_node para que app_finish_run
// pueda registrar el resultado al terminar.
launch_campaign_node :: proc(app: ^entities.App_State, node_idx: i32) {
	c := &app.campaign
	if node_idx < 0 || node_idx >= c.node_count { return }

	node  := &c.nodes[node_idx]
	fname := entities.campaign_node_map_filename(node)

	if !entities.map_load(&app.editor.game_map, fname) {
		entities.add_toast(app, fmt.tprintf("Mapa no encontrado: %s", fname), .ERROR, 3.0)
		play_sound(.ERROR, .UI)
		return
	}

	app.editor.current_biome = app.editor.game_map.biome
	if len(app.editor.current_map_name) > 0 {
		delete(app.editor.current_map_name)
	}
	app.editor.current_map_name = strings.clone(fname)

	// Limpieza preventiva — simulation_init_from_editor llama a reset
	app.current_campaign_node = -1

	if simulation_init_from_editor(app) {
		// Settear DESPUÉS del reset para que sobreviva al init
		app.current_campaign_node = node_idx
		simulation_fit_camera(app, f32(raylib.GetScreenWidth()), f32(raylib.GetScreenHeight()))
		entities.app_set_state(app, .PLAYING)
		play_sound(.CONFIRMATION, .UI)
	} else {
		entities.add_toast(app, constants.get_text("EDITOR_ERROR_NO_PATH"), .ERROR, 3.0)
		play_sound(.ERROR, .UI)
	}
}

// Convierte una posición [0..1]² a coordenadas de pantalla dentro del área dada.
campaign_pos_to_screen :: proc(pos: [2]f32, x_lef, y_top, x_rig, y_bot: f32) -> [2]f32 {
	return [2]f32{
		x_lef + pos.x * (x_rig - x_lef),
		y_top + pos.y * (y_bot - y_top),
	}
}

// Dibuja una conexión entre dos nodos con routing ortogonal de esquinas a 45°.
// Geometría: segmento recto → diagonal 45° → segmento recto, con la parte recta
// dividida simétricamente (mitad antes de la diagonal, mitad después).
draw_campaign_connection :: proc(from, to: [2]f32, thickness: f32, color: raylib.Color) {
	x0, y0 := from[0], from[1]
	x1, y1 := to[0],   to[1]
	dx := x1 - x0
	dy := y1 - y0
	adx := abs(dx)
	ady := abs(dy)
	sx := f32(1) if dx >= 0 else f32(-1)
	sy := f32(1) if dy >= 0 else f32(-1)

	p0 := raylib.Vector2{x0, y0}
	p3 := raylib.Vector2{x1, y1}
	p1, p2: raylib.Vector2

	if adx >= ady {
		// Eje horizontal dominante: H → diagonal → H
		diag         := ady
		half_straight := (adx - diag) / 2
		p1 = {x0 + sx * half_straight, y0}
		p2 = {x0 + sx * (half_straight + diag), y0 + sy * diag}
	} else {
		// Eje vertical dominante: V → diagonal → V
		diag         := adx
		half_straight := (ady - diag) / 2
		p1 = {x0, y0 + sy * half_straight}
		p2 = {x0 + sx * diag, y0 + sy * (half_straight + diag)}
	}

	raylib.DrawLineEx(p0, p1, thickness, color)
	raylib.DrawLineEx(p1, p2, thickness, color)
	raylib.DrawLineEx(p2, p3, thickness, color)
}

// Render del visualizador de campaña — Game_State.CAMPAIGN_MAP.
render_campaign_map :: proc(app: ^entities.App_State) {
	// Carga lazy de campaign.bin la primera vez que se entra.
	// En DEVELOPER, además hot-reload si el archivo cambió en disco — permite
	// editar campaign.bin desde otra herramienta sin reiniciar el juego.
	when constants.DEVELOPER {
		current_mtime := entities.campaign_file_mtime()
		if app.campaign_loaded && current_mtime != 0 && current_mtime != app.campaign_file_mtime {
			loaded, ok := entities.campaign_load()
			if ok {
				app.campaign = loaded
				app.campaign_file_mtime = current_mtime
				entities.add_toast(app, "campaign.bin recargado (hot-reload)", .INFO, 2.0)
			}
		}
	}

	if !app.campaign_loaded {
		loaded, ok := entities.campaign_load()
		if ok {
			app.campaign = loaded
		} else {
			app.campaign = entities.Campaign_File{}
		}
		app.campaign_loaded = true
		when constants.DEVELOPER {
			app.campaign_file_mtime = entities.campaign_file_mtime()
		}
	}

	sw := f32(raylib.GetScreenWidth())
	sh := f32(raylib.GetScreenHeight())
	c  := &app.campaign

	// Título
	name := entities.campaign_name(c)
	if len(name) == 0 { name = constants.get_text("CAMPAIGN_MAP_TITLE_DEFAULT") }
	title_size : f32 = sh * 0.06
	title_cs   := strings.clone_to_cstring(name, context.temp_allocator)
	title_w    := raylib.MeasureTextEx(constants.game_fonts.bold, title_cs, title_size, 0).x
	raylib.DrawTextEx(
		constants.game_fonts.bold, title_cs,
		{sw / 2 - title_w / 2, sh * 0.06},
		title_size, 0, raylib.WHITE,
	)

	// Conteo de progreso
	if c.node_count > 0 {
		completed := entities.campaign_completed_count(c, app.meta.campaign_completed[:])
		progress := constants.get_text_f("CAMPAIGN_MAP_PROGRESS", completed, c.node_count)
		progress_cs := strings.clone_to_cstring(progress, context.temp_allocator)
		progress_w  := raylib.MeasureTextEx(constants.game_fonts.regular, progress_cs, 16, 0).x
		raylib.DrawTextEx(
			constants.game_fonts.regular, progress_cs,
			{sw / 2 - progress_w / 2, sh * 0.06 + title_size + 8},
			16, 0, constants.COLOR_CAMPAIGN_PROGRESS_DIM,
		)
	}

	if c.node_count == 0 {
		// Empty state
		empty_cs := strings.clone_to_cstring(constants.get_text("CAMPAIGN_MAP_EMPTY"), context.temp_allocator)
		ew       := raylib.MeasureTextEx(constants.game_fonts.regular, empty_cs, 22, 0).x
		raylib.DrawTextEx(
			constants.game_fonts.regular, empty_cs,
			{sw / 2 - ew / 2, sh * 0.5}, 22, 0, raylib.WHITE,
		)
	} else {
		// Layout area
		vis_x_lef := sw * 0.10
		vis_x_rig := sw * 0.90
		vis_y_top := sh * 0.22
		vis_y_bot := sh * 0.82

		layout := compute_campaign_layout(c)
		mouse  := raylib.GetMousePosition()
		t      := f32(raylib.GetTime())

		// Nodo "activo" — primer nodo NO opcional, desbloqueado y no completado.
		// Recibe un anillo blanco para destacar visualmente "lo que sigue".
		active_idx := -1
		for i in 0 ..< int(c.node_count) {
			if .OPTIONAL in c.nodes[i].flags { continue }
			completed := i < len(app.meta.campaign_completed) && app.meta.campaign_completed[i]
			if completed { continue }
			if entities.campaign_is_node_unlocked(c, app.meta.campaign_completed[:], i) {
				active_idx = i
				break
			}
		}

		// 1ª pasada: conexiones (atrás)
		for i in 0 ..< int(c.node_count) {
			node := &c.nodes[i]
			if node.requires_node < 0 { continue }
			parent_idx := int(node.requires_node)
			if parent_idx < 0 || parent_idx >= int(c.node_count) { continue }

			from := campaign_pos_to_screen(layout[parent_idx], vis_x_lef, vis_y_top, vis_x_rig, vis_y_bot)
			to   := campaign_pos_to_screen(layout[i],          vis_x_lef, vis_y_top, vis_x_rig, vis_y_bot)

			unlocked := entities.campaign_is_node_unlocked(c, app.meta.campaign_completed[:], i)
			line_col := constants.COLOR_CAMPAIGN_CONNECTION_ACTIVE if unlocked else constants.COLOR_CAMPAIGN_CONNECTION_INACTIVE
			draw_campaign_connection({from[0], from[1]}, {to[0], to[1]}, 2, line_col)
		}

		// 2ª pasada: nodos (encima de las conexiones)
		hovered_idx := -1
		for i in 0 ..< int(c.node_count) {
			node := &c.nodes[i]
			pos  := campaign_pos_to_screen(layout[i], vis_x_lef, vis_y_top, vis_x_rig, vis_y_bot)

			// Tamaño según flags
			radius: f32 = constants.CAMPAIGN_NODE_RADIUS_DEFAULT
			if .OPTIONAL in node.flags { radius = constants.CAMPAIGN_NODE_RADIUS_OPTIONAL }
			if .BOSS     in node.flags { radius = constants.CAMPAIGN_NODE_RADIUS_BOSS }
			if .FINALE   in node.flags { radius = constants.CAMPAIGN_NODE_RADIUS_FINALE }

			unlocked  := entities.campaign_is_node_unlocked(c, app.meta.campaign_completed[:], i)
			completed := i < len(app.meta.campaign_completed) && app.meta.campaign_completed[i]

			// Colores base
			fill_col   : raylib.Color
			border_col : raylib.Color
			switch {
			case completed:
				fill_col   = constants.COLOR_CAMPAIGN_COMPLETED_FILL
				border_col = constants.COLOR_CAMPAIGN_COMPLETED_BORDER
			case unlocked:
				fill_col   = constants.COLOR_CAMPAIGN_AVAILABLE_FILL
				border_col = constants.COLOR_CAMPAIGN_AVAILABLE_BORDER
			case:
				fill_col   = constants.COLOR_CAMPAIGN_LOCKED_FILL
				border_col = constants.COLOR_CAMPAIGN_LOCKED_BORDER
			}
			// Outline especial para boss/finale (sobreescribe)
			if .FINALE in node.flags {
				border_col = constants.COLOR_CAMPAIGN_FINALE_BORDER
			} else if .BOSS in node.flags {
				border_col = constants.COLOR_CAMPAIGN_BOSS_BORDER
			}

			// Pulso para available
			if unlocked && !completed {
				pulse := 0.5 + 0.5 * math.sin(t * 3.0)
				glow_r := radius * (1.0 + 0.4 * pulse)
				pulse_col := constants.COLOR_CAMPAIGN_PULSE
				pulse_col.a = u8(70.0 * pulse)
				raylib.DrawCircleV({pos[0], pos[1]}, glow_r, pulse_col)
			}

			// Hover check
			dx := mouse.x - pos[0]
			dy := mouse.y - pos[1]
			hovered := dx*dx + dy*dy <= radius * radius

			// Dibujar círculo + borde
			raylib.DrawCircleV({pos[0], pos[1]}, radius, fill_col)
			raylib.DrawCircleLines(i32(pos[0]), i32(pos[1]), radius, border_col)

			// Anillo blanco para el nodo activo (encima del borde normal).
			// Doble línea para grosor de ~2px sin depender de DrawCircleLinesEx.
			if i == active_idx {
				r0 := radius + f32(constants.CAMPAIGN_ACTIVE_RING_OFFSET)
				raylib.DrawCircleLines(i32(pos[0]), i32(pos[1]), r0,     raylib.WHITE)
				raylib.DrawCircleLines(i32(pos[0]), i32(pos[1]), r0 + 1, raylib.WHITE)
			}

			// Estrellas para completados (texto centrado)
			if completed {
				stars : u8 = 0
				if i < len(app.meta.campaign_stars) {
					stars = app.meta.campaign_stars[i]
				}
				stars_str := fmt.ctprintf("%d*", stars)
				fs : f32 = 12
				tw := raylib.MeasureTextEx(constants.game_fonts.bold, stars_str, fs, 0).x
				raylib.DrawTextEx(
					constants.game_fonts.bold, stars_str,
					{pos[0] - tw / 2, pos[1] - fs / 2},
					fs, 0, raylib.WHITE,
				)
			}

			if hovered {
				hovered_idx = i
			}

			// Click sobre nodo disponible → lanzar run
			if hovered && unlocked && raylib.IsMouseButtonPressed(.LEFT) {
				launch_campaign_node(app, i32(i))
			}
		}

		// 3ª pasada: tooltip (encima de todo). Sólo el último hovered.
		if hovered_idx >= 0 {
			i := hovered_idx
			node := &c.nodes[i]
			pos  := campaign_pos_to_screen(layout[i], vis_x_lef, vis_y_top, vis_x_rig, vis_y_bot)

			unlocked  := entities.campaign_is_node_unlocked(c, app.meta.campaign_completed[:], i)
			completed := i < len(app.meta.campaign_completed) && app.meta.campaign_completed[i]

			disp := entities.campaign_node_display_name(node)
			if len(disp) == 0 { disp = entities.campaign_node_map_filename(node) }

			status: string
			switch {
			case completed:
				stars : u8 = 0
				if i < len(app.meta.campaign_stars) { stars = app.meta.campaign_stars[i] }
				best : i32 = 0
				if i < len(app.meta.campaign_best) { best = app.meta.campaign_best[i] }
				status = constants.get_text_f("CAMPAIGN_MAP_STATUS_COMPLETED", stars, best)
			case unlocked:
				status = constants.get_text("CAMPAIGN_MAP_STATUS_AVAILABLE")
			case:
				status = constants.get_text("CAMPAIGN_MAP_STATUS_LOCKED")
			}

			line1_cs := strings.clone_to_cstring(disp,   context.temp_allocator)
			line2_cs := strings.clone_to_cstring(status, context.temp_allocator)
			fs : f32 = 13
			tw1 := raylib.MeasureTextEx(constants.game_fonts.bold,    line1_cs, fs, 0).x
			tw2 := raylib.MeasureTextEx(constants.game_fonts.regular, line2_cs, fs, 0).x
			max_w := tw1 if tw1 > tw2 else tw2
			pad : f32 = 8
			tip_h : f32 = (fs + 2) * 2 + pad * 2
			radius : f32 = constants.CAMPAIGN_NODE_RADIUS_FINALE  // approx max node radius
			tip_y := pos[1] - radius - tip_h - 8
			if tip_y < 100 { tip_y = pos[1] + radius + 8 }
			tip_x := pos[0] - (max_w + pad * 2) / 2
			raylib.DrawRectangleRounded(
				{tip_x, tip_y, max_w + pad * 2, tip_h}, 0.3, 8,
				constants.COLOR_CAMPAIGN_TOOLTIP_BG,
			)
			raylib.DrawTextEx(
				constants.game_fonts.bold, line1_cs,
				{tip_x + pad, tip_y + pad},
				fs, 0, raylib.WHITE,
			)
			raylib.DrawTextEx(
				constants.game_fonts.regular, line2_cs,
				{tip_x + pad, tip_y + pad + fs + 2},
				fs, 0, constants.COLOR_CAMPAIGN_TOOLTIP_DIM,
			)
		}
	}

	// Botón de volver
	back_w : f32 = 140
	back_h : f32 = 32
	back_x := sw / 2 - back_w / 2
	back_y := sh - back_h - 24
	if render_button(constants.get_text("CAMPAIGN_MAP_BACK"), {back_x, back_y, back_w, back_h}) {
		entities.app_set_state(app, .MENU)
		play_sound(.CLICK, .UI)
	}
}

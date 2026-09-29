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
		entities.add_toast(app, "Saliste sin guardar - cambios perdidos", .WARNING, 3.0)
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

	// Toggles de flags — indicador de estado "activo", no un botón afirmativo
	// (ver UI_BUTTON_TOGGLE_ACTIVE_COLOR).
	flag_active_color   := constants.UI_BUTTON_TOGGLE_ACTIVE_COLOR
	flag_inactive_color := constants.COLOR_NONE
	if render_button("BOSS", {x, f32(btn_y2), btn_w2, btn_h2}, {
		text_color    = constants.UI_TEXT_COLOR,
		button_color  = flag_active_color if .BOSS in node.flags else flag_inactive_color,
		hover_color   = constants.UI_BUTTON_TOGGLE_ACTIVE_HOVER,
		pressed_color = constants.UI_BUTTON_TOGGLE_ACTIVE_PRESS,
	}) {
		campaign_editor_toggle_flag(app, .BOSS)
	}
	x += btn_w2 + gap

	if render_button("OPT", {x, f32(btn_y2), btn_w2, btn_h2}, {
		text_color    = constants.UI_TEXT_COLOR,
		button_color  = flag_active_color if .OPTIONAL in node.flags else flag_inactive_color,
		hover_color   = constants.UI_BUTTON_TOGGLE_ACTIVE_HOVER,
		pressed_color = constants.UI_BUTTON_TOGGLE_ACTIVE_PRESS,
	}) {
		campaign_editor_toggle_flag(app, .OPTIONAL)
	}
	x += btn_w2 + gap

	if render_button("FIN", {x, f32(btn_y2), btn_w2, btn_h2}, {
		text_color    = constants.UI_TEXT_COLOR,
		button_color  = flag_active_color if .FINALE in node.flags else flag_inactive_color,
		hover_color   = constants.UI_BUTTON_TOGGLE_ACTIVE_HOVER,
		pressed_color = constants.UI_BUTTON_TOGGLE_ACTIVE_PRESS,
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
		button_color  = constants.UI_BUTTON_AFFIRMATIVE_COLOR,
		hover_color   = constants.UI_BUTTON_AFFIRMATIVE_HOVER,
		pressed_color = constants.UI_BUTTON_AFFIRMATIVE_PRESS,
	}) {
		campaign_editor_add_selected_map(app)
	}

	save_color := constants.UI_BUTTON_AFFIRMATIVE_COLOR if app.editor.campaign_editor.dirty else constants.COLOR_NONE
	if render_button(constants.get_text("CAMPAIGN_EDITOR_SAVE"), {f32(save_x), f32(btn_y), f32(btn_w), f32(btn_h)}, {
		text_color    = constants.UI_TEXT_COLOR,
		button_color  = save_color,
		hover_color   = constants.UI_BUTTON_AFFIRMATIVE_HOVER,
		pressed_color = constants.UI_BUTTON_AFFIRMATIVE_PRESS,
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

	// Distribuir nodos del main path sobre la línea vertical central —
	// el camino principal crece hacia abajo (estilo mapa de niveles).
	main_idx := 0
	for i in 0 ..< int(c.node_count) {
		if .OPTIONAL in c.nodes[i].flags { continue }
		y: f32
		if main_count == 1 {
			y = 0.5
		} else {
			y = f32(main_idx) / f32(main_count - 1)
		}
		layout[i] = {0.5, y}
		main_idx += 1
	}

	// Posicionar OPTIONAL cerca de su parent (requires_node), colgando a los
	// costados (izquierda/derecha) en vez de arriba/abajo.
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

		// Alternar izquierda/derecha; cada par adicional se aleja más en Y
		x_offset: f32 = 0.22
		if sibling_idx % 2 == 1 { x_offset = -0.22 }
		y_offset := f32(0.06) + f32(sibling_idx / 2) * 0.06

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

// Refresca el cache de nombre + bioma de mapa por nodo — se llama al
// cargar/recargar campaign.bin. Carga cada .map una sola vez acá (no por
// frame) sólo para leer su nombre editable y su bioma.
campaign_refresh_map_display_names :: proc(app: ^entities.App_State) {
	for i in 0 ..< len(app.campaign_map_display_names) {
		if len(app.campaign_map_display_names[i]) > 0 {
			delete(app.campaign_map_display_names[i])
			app.campaign_map_display_names[i] = ""
		}
		app.campaign_map_biome_valid[i] = false
	}
	c := &app.campaign
	for i in 0 ..< int(c.node_count) {
		fname   := entities.campaign_node_map_filename(&c.nodes[i])
		scratch := entities.map_init()
		if entities.map_load(&scratch, fname) {
			name := entities.map_display_name(&scratch)
			if len(name) > 0 {
				app.campaign_map_display_names[i] = strings.clone(name)
			}
			app.campaign_map_biomes[i]      = scratch.biome
			app.campaign_map_biome_valid[i] = true
		}
		entities.map_destroy(&scratch)
	}
}

// Título a mostrar para un nodo: display_name propio del nodo (seteado a
// mano en el editor de campaña) > nombre editable del .map (cacheado) >
// nombre del archivo, en ese orden de prioridad.
campaign_node_title :: proc(app: ^entities.App_State, node_idx: int) -> string {
	node := &app.campaign.nodes[node_idx]
	disp := entities.campaign_node_display_name(node)
	if len(disp) > 0 { return disp }
	if node_idx < len(app.campaign_map_display_names) && len(app.campaign_map_display_names[node_idx]) > 0 {
		return app.campaign_map_display_names[node_idx]
	}
	return entities.campaign_node_map_filename(node)
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

// Estado del visualizador de campaña (scroll vertical + nodo seleccionado
// para el panel de detalle). Se resetea al salir (botón Volver o ESC).
campaign_map_scroll:        f32 = 0
campaign_map_selected_node: i32 = -1

// Nodo con foco de navegación por mando — sólo se usa en modo grafo
// (campaign_map_selected_node < 0). Distinto de campaign_map_selected_node:
// éste es "el cursor", aquél es "el panel está abierto para este nodo".
// -1 = sin foco asignado todavía (se auto-inicializa en active_idx).
campaign_map_gamepad_focus: i32 = -1

// Vecino más cercano de `current` en la dirección `dir`, en el espacio
// normalizado [0,1]² que ya devuelve compute_campaign_layout — no camina
// el grafo (requires_node) porque las ramas OPTIONAL cuelgan a los
// costados y el layout es espacial, no jerárquico. `along` mide qué tan
// lejos está en la dirección pedida (se descarta si es <= 0, no está para
// ese lado), `perp` qué tan desalineado está — se penaliza el
// desalineado el doble que la distancia para preferir vecinos derechos
// por sobre vecinos lejanos pero alineados.
campaign_nav_move :: proc(c: ^entities.Campaign_File, layout: ^[constants.CAMPAIGN_MAX_NODES][2]f32, current: i32, dir: Gamepad_Nav_Dir) -> i32 {
	if dir == .NONE || current < 0 { return current }
	dir_vec: [2]f32
	switch dir {
	case .UP:    dir_vec = {0, -1}
	case .DOWN:  dir_vec = {0, 1}
	case .LEFT:  dir_vec = {-1, 0}
	case .RIGHT: dir_vec = {1, 0}
	case .NONE:
	}
	cur_pos := layout[current]
	best_idx: i32 = -1
	best_score := max(f32)
	for i in 0 ..< int(c.node_count) {
		if i32(i) == current { continue }
		delta := layout[i] - cur_pos
		along := delta.x*dir_vec.x + delta.y*dir_vec.y
		if along <= 0.001 { continue }
		perp := abs(delta.x*dir_vec.y - delta.y*dir_vec.x)
		score := along + perp*2.0
		if score < best_score {
			best_score = score
			best_idx = i32(i)
		}
	}
	return best_idx if best_idx >= 0 else current
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
				campaign_refresh_map_display_names(app)
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
		campaign_refresh_map_display_names(app)
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

		// El main path crece verticalmente — si hay más nodos de los que
		// entran en el viewport, el canvas se estira y se scrollea con la
		// rueda (mismo patrón que progression_scroll/library_scroll, eje Y).
		main_count := entities.campaign_main_path_count(c)
		canvas_h   := max(vis_y_bot - vis_y_top, f32(max(main_count - 1, 0)) * constants.CAMPAIGN_NODE_SPACING_PX)
		max_scroll := max(f32(0), canvas_h - (vis_y_bot - vis_y_top))

		wheel := raylib.GetMouseWheelMove()
		if wheel != 0 { campaign_map_scroll -= wheel * 60 }
		if campaign_map_scroll < 0          { campaign_map_scroll = 0 }
		if campaign_map_scroll > max_scroll { campaign_map_scroll = max_scroll }

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

		// Foco de mando — sólo en modo grafo (panel cerrado). Se
		// auto-inicializa en el nodo activo si quedó inválido (pantalla
		// recién entrada, o la campaña cambió de tamaño).
		if campaign_map_gamepad_focus < 0 || campaign_map_gamepad_focus >= i32(c.node_count) {
			campaign_map_gamepad_focus = i32(active_idx) if active_idx >= 0 else 0
		}
		if campaign_map_selected_node < 0 {
			campaign_map_gamepad_focus = campaign_nav_move(c, &layout, campaign_map_gamepad_focus, current_nav_dir)

			// Auto-scroll: si el nodo recién enfocado quedó fuera de la
			// banda visible, correr el scroll lo mínimo necesario para
			// volver a mostrarlo — mismo clamp [0, max_scroll] de la rueda.
			focus_margin : f32 = 40
			focus_y := vis_y_top - campaign_map_scroll + layout[campaign_map_gamepad_focus].y*canvas_h
			if focus_y < vis_y_top + focus_margin {
				campaign_map_scroll -= (vis_y_top + focus_margin) - focus_y
			} else if focus_y > vis_y_bot - focus_margin {
				campaign_map_scroll += focus_y - (vis_y_bot - focus_margin)
			}
			if campaign_map_scroll < 0          { campaign_map_scroll = 0 }
			if campaign_map_scroll > max_scroll { campaign_map_scroll = max_scroll }
		}

		y_top_eff := vis_y_top - campaign_map_scroll
		y_bot_eff := y_top_eff + canvas_h

		scissor_margin := constants.CAMPAIGN_SCISSOR_MARGIN_PX
		raylib.BeginScissorMode(
			i32(vis_x_lef - scissor_margin), i32(vis_y_top - scissor_margin),
			i32(vis_x_rig - vis_x_lef + scissor_margin*2), i32(vis_y_bot - vis_y_top + scissor_margin*2),
		)

		// 1ª pasada: conexiones (atrás). Las ramas OPTIONAL se dibujan más
		// finas y apagadas para distinguirlas del main path.
		for i in 0 ..< int(c.node_count) {
			node := &c.nodes[i]
			if node.requires_node < 0 { continue }
			parent_idx := int(node.requires_node)
			if parent_idx < 0 || parent_idx >= int(c.node_count) { continue }

			from := campaign_pos_to_screen(layout[parent_idx], vis_x_lef, y_top_eff, vis_x_rig, y_bot_eff)
			to   := campaign_pos_to_screen(layout[i],          vis_x_lef, y_top_eff, vis_x_rig, y_bot_eff)

			unlocked := entities.campaign_is_node_unlocked(c, app.meta.campaign_completed[:], i)
			line_col: raylib.Color
			thickness: f32 = 2
			if .OPTIONAL in node.flags {
				line_col  = constants.COLOR_CAMPAIGN_CONNECTION_OPTIONAL
				thickness = 1
			} else {
				line_col = constants.COLOR_CAMPAIGN_CONNECTION_ACTIVE if unlocked else constants.COLOR_CAMPAIGN_CONNECTION_INACTIVE
			}
			draw_campaign_connection({from[0], from[1]}, {to[0], to[1]}, thickness, line_col)
		}

		// 2ª pasada: nodos (encima de las conexiones)
		mouse_blocked      := ui_is_modal_blocked(i32(mouse.x), i32(mouse.y))
		node_click_handled := false
		for i in 0 ..< int(c.node_count) {
			node := &c.nodes[i]
			pos  := campaign_pos_to_screen(layout[i], vis_x_lef, y_top_eff, vis_x_rig, y_bot_eff)

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
			// Outline especial para boss/finale (sobreescribe), y anillo de
			// selección si este es el nodo con el panel de detalle abierto.
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

			// Hover check (círculo, no hay widget compartido para esto). El
			// nodo con foco de mando (sólo en modo grafo, panel cerrado)
			// cuenta como hovereado igual que el mouse — mismo tooltip,
			// mismo gatillo de click.
			dx := mouse.x - pos[0]
			dy := mouse.y - pos[1]
			gamepad_focused_node := app.gamepad_nav_active && campaign_map_selected_node < 0 &&
				campaign_map_gamepad_focus == i32(i)
			hovered := (dx*dx + dy*dy <= radius*radius && !mouse_blocked) || gamepad_focused_node

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

			// Anillo de foco de mando — offset mayor que el del nodo activo,
			// para que si coinciden en el mismo nodo se vean los dos anillos
			// anidados en vez de pisarse.
			if gamepad_focused_node {
				r1 := radius + f32(constants.CAMPAIGN_ACTIVE_RING_OFFSET) + 6
				raylib.DrawCircleLines(i32(pos[0]), i32(pos[1]), r1,     constants.UI_BUTTON_AFFIRMATIVE_COLOR)
				raylib.DrawCircleLines(i32(pos[0]), i32(pos[1]), r1 + 1, constants.UI_BUTTON_AFFIRMATIVE_COLOR)
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

			node_rect := raylib.Rectangle{pos[0] - radius, pos[1] - radius, radius * 2, radius * 2}
			append(&ui_click_blocks, node_rect)

			// Tooltip rápido de una línea en hover (widget compartido, no un
			// DrawRectangleRounded a mano).
			if hovered {
				disp := campaign_node_title(app, i)
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
				quick_line := fmt.tprintf("%s - %s", disp, status)
				map_fname  := entities.campaign_node_map_filename(node)
				sub_line   := map_fname
				if i < len(app.campaign_map_biome_valid) && app.campaign_map_biome_valid[i] {
					sub_line = fmt.tprintf("%s - %s", map_fname, constants.get_biome_name(app.campaign_map_biomes[i]))
				}
				render_label_tooltip(app, quick_line, node_rect, sub_line, force = gamepad_focused_node)
			}

			// Click (o Confirmar de mando sobre el nodo enfocado) selecciona/
			// deselecciona el nodo y abre el panel de detalle — ya NO lanza
			// la run directamente (evita lanzamientos accidentales y
			// permite ver info de nodos bloqueados).
			if hovered && (raylib.IsMouseButtonPressed(.LEFT) ||
			   (gamepad_focused_node && gamepad_confirm_pressed())) {
				if campaign_map_selected_node == i32(i) {
					campaign_map_selected_node = -1
				} else {
					campaign_map_selected_node = i32(i)
				}
				node_click_handled = true
				play_sound(.CLICK, .UI)
			}
		}

		raylib.EndScissorMode()

		// 3ª pasada: panel de detalle del nodo seleccionado (fuera del
		// scissor — puede sobresalir del área del grafo si hace falta).
		if campaign_map_selected_node >= 0 && int(campaign_map_selected_node) < int(c.node_count) {
			sel := campaign_map_selected_node
			pos := campaign_pos_to_screen(layout[sel], vis_x_lef, y_top_eff, vis_x_rig, y_bot_eff)
			panel_rect := render_campaign_node_detail_panel(app, sel, {pos[0], pos[1]})

			// Click fuera del panel (y no sobre el nodo que lo abrió/cerró
			// este mismo frame) lo cierra.
			if !node_click_handled && raylib.IsMouseButtonPressed(.LEFT) &&
			   !raylib.CheckCollisionPointRec(mouse, panel_rect) {
				campaign_map_selected_node = -1
			}
		}
	}

	// Botón de volver — ya NO gamepad-focused incondicional: compite con el
	// foco de nodos y con "Jugar" del panel. Con mando, salir de esta
	// pantalla es Cancelar (B), no Confirmar sobre este botón (ver
	// systems/input.odin, case .CAMPAIGN_MAP).
	back_w : f32 = 140
	back_h : f32 = 32
	back_x := sw / 2 - back_w / 2
	back_y := sh - back_h - 24
	if render_button(constants.get_text("CAMPAIGN_MAP_BACK"), {back_x, back_y, back_w, back_h}) {
		campaign_map_scroll        = 0
		campaign_map_selected_node = -1
		campaign_map_gamepad_focus = -1
		entities.app_set_state(app, .MENU)
		play_sound(.CLICK, .UI)
	}
}

// Panel de detalle de un nodo del mapa de campaña — reemplaza el rol
// informativo del viejo tooltip hecho a mano. Se abre al clickear un nodo;
// el botón "Jugar" es el único punto de entrada para lanzar la run.
// Devuelve el rect ocupado por el panel (el caller lo usa para detectar
// clicks afuera y cerrarlo).
render_campaign_node_detail_panel :: proc(app: ^entities.App_State, node_idx: i32, anchor: raylib.Vector2) -> raylib.Rectangle {
	c    := &app.campaign
	node := &c.nodes[node_idx]

	unlocked  := entities.campaign_is_node_unlocked(c, app.meta.campaign_completed[:], int(node_idx))
	completed := int(node_idx) < len(app.meta.campaign_completed) && app.meta.campaign_completed[node_idx]

	disp := campaign_node_title(app, int(node_idx))

	// Tier de dificultad — puramente presentacional.
	diff_tier: string
	switch {
	case node.difficulty_mult <= constants.CAMPAIGN_DIFFICULTY_EASY_MAX:
		diff_tier = constants.get_text("CAMPAIGN_DIFFICULTY_EASY")
	case node.difficulty_mult >= constants.CAMPAIGN_DIFFICULTY_VERY_HARD_MIN:
		diff_tier = constants.get_text("CAMPAIGN_DIFFICULTY_VERY_HARD")
	case node.difficulty_mult >= constants.CAMPAIGN_DIFFICULTY_HARD_MIN:
		diff_tier = constants.get_text("CAMPAIGN_DIFFICULTY_HARD")
	case:
		diff_tier = constants.get_text("CAMPAIGN_DIFFICULTY_NORMAL")
	}

	waves := node.waves_override if node.waves_override != 0 else constants.RUN_MAX_WAVES

	status: string
	switch {
	case completed:
		stars : u8 = 0
		if int(node_idx) < len(app.meta.campaign_stars) { stars = app.meta.campaign_stars[node_idx] }
		best : i32 = 0
		if int(node_idx) < len(app.meta.campaign_best) { best = app.meta.campaign_best[node_idx] }
		status = constants.get_text_f("CAMPAIGN_MAP_STATUS_COMPLETED", stars, best)
	case unlocked:
		status = constants.get_text("CAMPAIGN_MAP_STATUS_AVAILABLE")
	case:
		status = constants.get_text("CAMPAIGN_MAP_STATUS_LOCKED")
	}

	// Armar las líneas de contenido primero para poder dimensionar el panel.
	lines := make([dynamic]string, context.temp_allocator)
	append(&lines, disp)
	append(&lines, status)
	if !unlocked && node.requires_node >= 0 && int(node.requires_node) < int(c.node_count) {
		pred_name := campaign_node_title(app, int(node.requires_node))
		append(&lines, constants.get_text_f("CAMPAIGN_MAP_DETAIL_LOCKED_REQUIRES", pred_name))
	}
	append(&lines, constants.get_text_f("CAMPAIGN_MAP_DETAIL_DIFFICULTY", diff_tier, node.difficulty_mult))
	append(&lines, constants.get_text_f("CAMPAIGN_MAP_DETAIL_WAVES", waves))
	if node.reward_cristales > 0 {
		append(&lines, constants.get_text_f("CAMPAIGN_MAP_DETAIL_REWARD", node.reward_cristales))
	}

	fs        : f32 = 14
	line_h    : f32 = fs + 6
	pad       : f32 = 12
	badge_h   : f32 = 20
	button_h  : f32 = 32
	panel_w   : f32 = 260
	panel_h   := pad*2 + f32(len(lines))*line_h + badge_h + button_h + 8

	sw := f32(raylib.GetScreenWidth())
	sh := f32(raylib.GetScreenHeight())
	px := anchor.x - panel_w/2
	py := anchor.y - panel_h - 16
	if py < 90         { py = anchor.y + 24 }
	if px < 12          { px = 12 }
	if px + panel_w > sw - 12 { px = sw - 12 - panel_w }
	if py + panel_h > sh - 12 { py = sh - 12 - panel_h }

	panel_rect := raylib.Rectangle{px, py, panel_w, panel_h}
	content    := render_panel(panel_rect, "", 1.0)

	y := content.y
	for line, i in lines {
		font := constants.game_fonts.bold if i == 0 else constants.game_fonts.regular
		col  := raylib.WHITE if i == 0 else constants.UI_TEXT_COLOR
		raylib.DrawTextEx(
			font, strings.clone_to_cstring(line, context.temp_allocator),
			{content.x + pad, y}, fs, 0, col,
		)
		y += line_h
	}

	// Badges de flags
	badge_x := content.x + content.width - pad
	draw_detail_badge :: proc(text: cstring, x_right: f32, y_center: f32, font: raylib.Font) -> f32 {
		fs : f32 = 11
		tw := raylib.MeasureTextEx(font, text, fs, 0).x
		pad_h : f32 = 5
		bw := tw + pad_h * 2
		rect_b := raylib.Rectangle{x_right - bw, y_center - 8, bw, 16}
		raylib.DrawRectangleRounded(rect_b, 0.3, 4, raylib.Color{120, 120, 120, 200})
		raylib.DrawTextEx(font, text, {rect_b.x + pad_h, rect_b.y + 2}, fs, 0, raylib.WHITE)
		return x_right - bw - 4
	}
	badge_y := y + badge_h/2 - 4
	if .FINALE   in node.flags { badge_x = draw_detail_badge("FIN",   badge_x, badge_y, constants.game_fonts.bold) }
	if .BOSS     in node.flags { badge_x = draw_detail_badge("BOSS",  badge_x, badge_y, constants.game_fonts.bold) }
	if .OPTIONAL in node.flags { badge_x = draw_detail_badge("OPT",   badge_x, badge_y, constants.game_fonts.bold) }

	// Botón Jugar
	playable := unlocked || constants.DEVELOPER
	btn_y := content.y + content.height - button_h
	if render_button(constants.get_text("CAMPAIGN_MAP_PLAY_BUTTON"), {content.x, btn_y, content.width, button_h}, {
		disabled      = !playable,
		text_color    = raylib.WHITE,
		button_color  = constants.UI_BUTTON_AFFIRMATIVE_COLOR,
		hover_color   = constants.UI_BUTTON_AFFIRMATIVE_HOVER,
		pressed_color = constants.UI_BUTTON_AFFIRMATIVE_PRESS,
		// Único widget de "modo panel" — scoped automáticamente porque esta
		// función sólo se llama mientras el panel está abierto.
		gamepad_focused = app.gamepad_nav_active,
	}) {
		launch_campaign_node(app, node_idx)
	}

	return panel_rect
}

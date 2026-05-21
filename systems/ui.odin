package systems

// ══════════════════════════════════════════════════════════════════════════════
//  ui.odin — Sistema de UI retenida con capas y auto-sizing por doble pasada
//
//  Ciclo de vida por frame:
//    1. DECLARE  — ui_clear(panel); ui_label(...); ui_button(...); ...
//    2. FRAME    — ui_frame(&g_ui)  → layout + input + render de capas activas
//    3. REACT    — ui_button_clicked(panel, idx); ui_select_result(panel, idx)
//
//  Las capas se activan/desactivan con ui_set_layer. Las capas con
//  blocks_below = true impiden que las capas inferiores reciban input.
// ══════════════════════════════════════════════════════════════════════════════

import "core:strings"
import "../constants"
import "vendor:raylib"

// ─────────────────────────────────────────────────────────
//  Capas
// ─────────────────────────────────────────────────────────

UI_Layer_Kind :: enum {
	HUD         = 0,  // dinero, vida, oleada — siempre activo durante el juego
	TOWER_PANEL = 1,  // controles de la torre seleccionada
	BUILD_PANEL = 2,  // panel de construcción / cartas
	GAME_OVER   = 3,  // pantalla de fin de partida
	SETTINGS    = 4,  // overlay de configuración
	EDITOR      = 5,  // herramientas del editor
	PAUSE       = 6,  // overlay de pausa
}

// ─────────────────────────────────────────────────────────
//  Tipos de elementos
// ─────────────────────────────────────────────────────────

// Espacio vertical vacío
UI_Gap :: struct {
	h: i32,
}

// Línea de texto
UI_Label :: struct {
	text:  string,
	size:  f32,
	color: raylib.Color,
	bold:  bool,
}

// Fila con ícono a la izquierda y valor a la derecha (stats de torre)
UI_Stat :: struct {
	icon:  raylib.Texture2D,
	value: string,
}

// Fila con etiqueta izquierda y valor derecha (stats de Game Over)
UI_Info_Row :: struct {
	label: string,
	value: string,
}

// Botón clickeable de ancho completo
UI_Button :: struct {
	label:         string,
	color:         raylib.Color,
	hover_color:   raylib.Color,
	pressed_color: raylib.Color,
	enabled:       bool,
	height:        i32,
	// Escritos por el sistema cada frame — leer después de ui_frame
	clicked: bool,
	hovered: bool,
}

// Grupo horizontal de botones mutuamente exclusivos (selector de estrategia, etc.)
UI_Select :: struct {
	options:  [4]string,
	count:    int,
	selected: int,
	height:   i32,
	// Escritos por el sistema cada frame — leer después de ui_frame
	changed: bool,
	new_idx: int,
}

UI_Element :: union {
	UI_Gap,
	UI_Label,
	UI_Stat,
	UI_Info_Row,
	UI_Button,
	UI_Select,
}

// ─────────────────────────────────────────────────────────
//  Panel
// ─────────────────────────────────────────────────────────

UI_MAX_ELEMENTS :: 32

UI_Panel :: struct {
	title:   string,
	x, y, w: f32,
	visible: bool,
	// Contenido declarado por el caller cada frame
	elements: [UI_MAX_ELEMENTS]UI_Element,
	count:    int,
	// Calculado por el sistema (solo lectura para el caller)
	_rect:    raylib.Rectangle,
	_content: raylib.Rectangle,
}

// ─────────────────────────────────────────────────────────
//  Capa
// ─────────────────────────────────────────────────────────

UI_MAX_PANELS :: 8

UI_Layer :: struct {
	active:       bool,
	blocks_below: bool, // si true, capas por debajo no reciben input
	panels:       [UI_MAX_PANELS]^UI_Panel,
	panel_count:  int,
}

// ─────────────────────────────────────────────────────────
//  Estado global
// ─────────────────────────────────────────────────────────

UI_State :: struct {
	layers: [UI_Layer_Kind]UI_Layer,
}

// Instancia global — inicializar con ui_init al arrancar el juego
g_ui: UI_State

// Señal interna: cuando true, los elementos no disparan eventos de click.
// Seteado por ui_frame según la capa más alta con blocks_below activo.
_ui_input_blocked: bool

// ─────────────────────────────────────────────────────────
//  Constantes de layout
// ─────────────────────────────────────────────────────────

_UI_TITLE_H  :: i32(30)    // alto reservado para el título del panel
_UI_STAT_H   :: i32(constants.UI_PANEL_TEXT_SIZE) + 10  // altura de fila UI_Stat
_UI_ROW_H    :: i32(constants.UI_PANEL_TEXT_SIZE) + 4   // altura de fila UI_Info_Row
_UI_ICON_SLOT :: f32(20)   // columna fija para el ícono en UI_Stat
_UI_ICON_GAP  :: f32(6)    // margen entre ícono y texto en UI_Stat

// ══════════════════════════════════════════════════════════════════════════════
//  Ciclo de vida
// ══════════════════════════════════════════════════════════════════════════════

// Inicializa flags de bloqueo para las capas que cubren todo por encima.
// Llamar una vez al arrancar el juego, después de ui_register_panel.
ui_init :: proc(ui: ^UI_State) {
	ui.layers[.SETTINGS].blocks_below  = true
	ui.layers[.GAME_OVER].blocks_below = true
	ui.layers[.PAUSE].blocks_below     = true
}

// Activa o desactiva una capa.
ui_set_layer :: proc(ui: ^UI_State, kind: UI_Layer_Kind, active: bool) {
	ui.layers[kind].active = active
}

// Registra un panel en una capa. El panel debe vivir en memoria del caller.
// Llamar una vez por panel al inicializar (no cada frame).
ui_register_panel :: proc(ui: ^UI_State, kind: UI_Layer_Kind, panel: ^UI_Panel) {
	layer := &ui.layers[kind]
	assert(layer.panel_count < UI_MAX_PANELS, "ui_register_panel: demasiados paneles en la capa")
	layer.panels[layer.panel_count] = panel
	layer.panel_count += 1
}

// ══════════════════════════════════════════════════════════════════════════════
//  Helpers de declaración de elementos
//  Llamar cada frame entre ui_clear y ui_frame para describir el contenido.
// ══════════════════════════════════════════════════════════════════════════════

// Borra todos los elementos del panel para redeclarar este frame.
ui_clear :: proc(panel: ^UI_Panel) {
	panel.count = 0
}

// Agrega un elemento y devuelve su índice (para leer eventos después).
_ui_add :: proc(panel: ^UI_Panel, elem: UI_Element) -> int {
	assert(panel.count < UI_MAX_ELEMENTS, "ui_add: overflow de elementos en el panel")
	idx := panel.count
	panel.elements[idx] = elem
	panel.count += 1
	return idx
}

// Espacio vertical vacío.
ui_gap :: proc(panel: ^UI_Panel, h: i32) {
	_ui_add(panel, UI_Gap{h = h})
}

// Texto con tipografía configurable.
ui_label :: proc(
	panel: ^UI_Panel,
	text:  string,
	size:  f32              = f32(constants.UI_PANEL_LABEL_SIZE),
	color: raylib.Color     = constants.UI_PANEL_LABEL_COLOR,
	bold:  bool             = true,
) {
	_ui_add(panel, UI_Label{text = text, size = size, color = color, bold = bold})
}

// Fila de ícono + valor (stats de torre: daño, velocidad, críticos).
ui_stat :: proc(panel: ^UI_Panel, icon: raylib.Texture2D, value: string) -> int {
	return _ui_add(panel, UI_Stat{icon = icon, value = value})
}

// Fila label-izquierda / valor-derecha (estadísticas de Game Over).
ui_info_row :: proc(panel: ^UI_Panel, label: string, value: string) {
	_ui_add(panel, UI_Info_Row{label = label, value = value})
}

// Botón de ancho completo. Devuelve índice para leer .clicked después de ui_frame.
ui_button :: proc(
	panel:         ^UI_Panel,
	label:         string,
	color:         raylib.Color = constants.COLOR_NONE,
	hover_color:   raylib.Color = constants.COLOR_NONE,
	pressed_color: raylib.Color = constants.COLOR_NONE,
	enabled:       bool         = true,
	height:        i32          = i32(constants.UI_BUTTON_HEIGHT),
) -> int {
	return _ui_add(panel, UI_Button{
		label         = label,
		color         = color,
		hover_color   = hover_color,
		pressed_color = pressed_color,
		enabled       = enabled,
		height        = height,
	})
}

// Grupo horizontal de botones mutuamente exclusivos.
// options: slice de strings (máx. 4). Devuelve índice para leer .changed después de ui_frame.
ui_select :: proc(
	panel:    ^UI_Panel,
	options:  []string,
	selected: int,
	height:   i32 = i32(constants.UI_BUTTON_HEIGHT),
) -> int {
	sel := UI_Select{selected = selected, height = height}
	n := min(len(options), 4)
	sel.count = n
	for i in 0 ..< n {
		sel.options[i] = options[i]
	}
	return _ui_add(panel, sel)
}

// ══════════════════════════════════════════════════════════════════════════════
//  Lectores de eventos
//  Llamar después de ui_frame para reaccionar a la interacción del usuario.
// ══════════════════════════════════════════════════════════════════════════════

// Devuelve true si el botón en `idx` fue clickeado este frame.
ui_button_clicked :: proc(panel: ^UI_Panel, idx: int) -> bool {
	if idx < 0 || idx >= panel.count {return false}
	if btn, ok := panel.elements[idx].(UI_Button); ok {return btn.clicked}
	return false
}

// Devuelve (changed, new_idx) para el selector en `idx`.
// changed es true solo el frame en que el usuario cambió la selección.
ui_select_result :: proc(panel: ^UI_Panel, idx: int) -> (changed: bool, new_idx: int) {
	if idx < 0 || idx >= panel.count {return false, -1}
	if sel, ok := panel.elements[idx].(UI_Select); ok {return sel.changed, sel.new_idx}
	return false, -1
}

// ══════════════════════════════════════════════════════════════════════════════
//  Frame principal
//  Llamar una vez por frame, después de declarar contenido y antes de leer eventos.
// ══════════════════════════════════════════════════════════════════════════════

ui_frame :: proc(ui: ^UI_State) {
	// Determinar la capa bloqueante de mayor prioridad (mayor índice enum activo con blocks_below)
	blocking_floor := -1
	for kind in UI_Layer_Kind {
		layer := &ui.layers[kind]
		if layer.active && layer.blocks_below {
			blocking_floor = int(kind)
		}
	}

	// Renderizar capas de menor a mayor (las superiores quedan encima visualmente)
	for kind in UI_Layer_Kind {
		layer := &ui.layers[kind]
		if !layer.active {continue}

		// Esta capa puede procesar input solo si está en o por encima del piso bloqueante
		process_input := blocking_floor < 0 || int(kind) >= blocking_floor

		for i in 0 ..< layer.panel_count {
			panel := layer.panels[i]
			if panel == nil || !panel.visible {continue}
			_ui_render_panel(panel, process_input)
		}
	}
}

// ══════════════════════════════════════════════════════════════════════════════
//  Internos — layout, dibujo e input
// ══════════════════════════════════════════════════════════════════════════════

// Altura de un elemento en píxeles.
_ui_elem_h :: proc(elem: UI_Element) -> i32 {
	switch e in elem {
	case UI_Gap:
		return e.h
	case UI_Label:
		return i32(e.size) + 4
	case UI_Stat:
		return _UI_STAT_H
	case UI_Info_Row:
		return _UI_ROW_H
	case UI_Button:
		return e.height if e.height > 0 else i32(constants.UI_BUTTON_HEIGHT)
	case UI_Select:
		return e.height if e.height > 0 else i32(constants.UI_BUTTON_HEIGHT)
	}
	return 0
}

// Suma los altos de todos los elementos declarados.
_ui_content_h :: proc(panel: ^UI_Panel) -> i32 {
	h: i32 = 0
	for i in 0 ..< panel.count {
		h += _ui_elem_h(panel.elements[i])
	}
	return h
}

// Renderiza un panel completo con dos pasadas:
//   Pasada 1 — mide el contenido → calcula _rect
//   Pasada 2 — dibuja fondo (render_panel) + itera elementos (draw + input)
_ui_render_panel :: proc(panel: ^UI_Panel, process_input: bool) {
	// ── Pasada 1: medir ─────────────────────────────────────────────
	content_h := _ui_content_h(panel)
	overhead  := i32(constants.UI_PANEL_PADDING) * 2
	if panel.title != "" {overhead += _UI_TITLE_H}

	panel._rect    = {panel.x, panel.y, panel.w, f32(content_h + overhead)}
	panel._content = render_panel(panel._rect, panel.title)

	cx := panel._content.x
	cy := panel._content.y
	cw := panel._content.width

	// Input del frame actual
	mouse   := raylib.GetMousePosition()
	clicked := process_input && raylib.IsMouseButtonPressed(.LEFT)

	// ── Pasada 2: dibujar + procesar input ──────────────────────────
	cursor_y: i32 = 0

	for i in 0 ..< panel.count {
		elem := &panel.elements[i]
		h    := _ui_elem_h(elem^)
		ey   := cy + f32(cursor_y)
		rect := raylib.Rectangle{cx, ey, cw, f32(h)}

		switch &e in elem {

		case UI_Gap:
		// nada que dibujar

		case UI_Label:
			font := constants.game_fonts.bold if e.bold else constants.game_fonts.regular
			raylib.DrawTextEx(
				font,
				strings.clone_to_cstring(e.text, context.temp_allocator),
				{cx, ey}, e.size, 0, e.color,
			)

		case UI_Stat:
			font_sz  := f32(constants.UI_PANEL_TEXT_SIZE)
			icon_sz  := f32(h) - 4
			aspect   := f32(e.icon.width) / f32(e.icon.height) if e.icon.height > 0 else 1
			draw_w   := icon_sz * aspect
			icon_x   := cx + (_UI_ICON_SLOT - draw_w) / 2
			raylib.DrawTexturePro(
				e.icon,
				{0, 0, f32(e.icon.width), f32(e.icon.height)},
				{icon_x, ey + 2, draw_w, icon_sz},
				{0, 0}, 0, raylib.WHITE,
			)
			val_cstr := strings.clone_to_cstring(e.value, context.temp_allocator)
			raylib.DrawTextEx(
				constants.game_fonts.semibold, val_cstr,
				{cx + _UI_ICON_SLOT + _UI_ICON_GAP, ey + (f32(h) - font_sz) / 2},
				font_sz, 0, constants.UI_PANEL_TEXT_COLOR,
			)

		case UI_Info_Row:
			font_sz    := f32(constants.UI_PANEL_TEXT_SIZE)
			label_cstr := strings.clone_to_cstring(e.label, context.temp_allocator)
			value_cstr := strings.clone_to_cstring(e.value, context.temp_allocator)
			vw         := raylib.MeasureTextEx(constants.game_fonts.semibold, value_cstr, font_sz, 0).x
			text_y     := ey + (f32(h) - font_sz) / 2
			raylib.DrawTextEx(constants.game_fonts.regular,  label_cstr, {cx, text_y},          font_sz, 0, constants.UI_PANEL_TEXT_COLOR)
			raylib.DrawTextEx(constants.game_fonts.semibold, value_cstr, {cx + cw - vw, text_y}, font_sz, 0, constants.UI_PANEL_TEXT_COLOR)

		case UI_Button:
			e.clicked = false
			e.hovered = false

			font_sz    := f32(constants.UI_BUTTON_FONT_SIZE)
			label_cstr := strings.clone_to_cstring(e.label, context.temp_allocator)
			tw         := raylib.MeasureTextEx(constants.game_fonts.semibold, label_cstr, font_sz, 0).x

			// Color base
			bg_color: raylib.Color
			if !e.enabled {
				bg_color = raylib.DARKGRAY
			} else {
				hovered  := process_input && raylib.CheckCollisionPointRec(mouse, rect)
				e.hovered = hovered
				if hovered {
					if raylib.IsMouseButtonDown(.LEFT) {
						bg_color = e.pressed_color if e.pressed_color.a != 0 else constants.UI_BUTTON_PRESSED_COLOR
					} else {
						bg_color = e.hover_color if e.hover_color.a != 0 else constants.UI_BUTTON_HOVER_COLOR
					}
					if clicked {
						e.clicked = true
						play_sound(.CLICK, .UI)
					}
				} else {
					bg_color = e.color if e.color.a != 0 else constants.UI_BUTTON_COLOR
				}
			}

			// Sombra
			shadow := rect
			shadow.x += f32(constants.UI_BUTTON_SHADOW_OFFSET)
			shadow.y += f32(constants.UI_BUTTON_SHADOW_OFFSET)
			raylib.DrawRectangleRounded(shadow, constants.UI_BUTTON_ROUNDNESS, 8, constants.UI_BUTTON_SHADOW_COLOR)
			// Fondo
			raylib.DrawRectangleRounded(rect, constants.UI_BUTTON_ROUNDNESS, 8, bg_color)
			// Texto centrado
			text_color := raylib.WHITE if e.color.a != 0 else constants.UI_TEXT_COLOR
			raylib.DrawTextEx(
				constants.game_fonts.semibold, label_cstr,
				{rect.x + (rect.width - tw) / 2, rect.y + (rect.height - font_sz) / 2},
				font_sz, 0, text_color,
			)
			// Registrar en click-blocks para que el input de grilla no pase por debajo
			append(&ui_click_blocks, rect)

		case UI_Select:
			e.changed = false
			n     := e.count
			slot_w := cw / f32(n)
			font_sz := f32(constants.UI_BUTTON_FONT_SIZE)

			for j in 0 ..< n {
				sr     := raylib.Rectangle{cx + f32(j) * slot_w, ey, slot_w, f32(h)}
				is_sel := j == e.selected

				hovered := process_input && raylib.CheckCollisionPointRec(mouse, sr)

				bg: raylib.Color
				switch {
				case !is_sel && hovered && raylib.IsMouseButtonDown(.LEFT):
					bg = constants.UI_BUTTON_PRESSED_COLOR
				case !is_sel && hovered:
					bg = constants.UI_BUTTON_HOVER_COLOR
				case is_sel:
					bg = constants.UI_BUTTON_ACTION_COLOR
				case:
					bg = constants.UI_BUTTON_COLOR
				}

				if hovered && clicked && j != e.selected {
					e.selected = j
					e.changed  = true
					e.new_idx  = j
					play_sound(.CLICK, .UI)
				}

				// Sombra
				shadow := sr
				shadow.x += f32(constants.UI_BUTTON_SHADOW_OFFSET)
				shadow.y += f32(constants.UI_BUTTON_SHADOW_OFFSET)
				raylib.DrawRectangleRounded(shadow, constants.UI_BUTTON_ROUNDNESS, 8, constants.UI_BUTTON_SHADOW_COLOR)
				// Fondo
				raylib.DrawRectangleRounded(sr, constants.UI_BUTTON_ROUNDNESS, 8, bg)

				// Texto centrado
				lbl_cstr := strings.clone_to_cstring(e.options[j], context.temp_allocator)
				tw       := raylib.MeasureTextEx(constants.game_fonts.semibold, lbl_cstr, font_sz, 0).x
				text_col := raylib.WHITE if is_sel else constants.UI_TEXT_COLOR
				raylib.DrawTextEx(
					constants.game_fonts.semibold, lbl_cstr,
					{sr.x + (sr.width - tw) / 2, sr.y + (sr.height - font_sz) / 2},
					font_sz, 0, text_col,
				)
				append(&ui_click_blocks, sr)
			}
		}
		cursor_y += h
	}
}

package systems

import "../constants"
import "../entities"
import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

// Formatea un número para el HUD: < 1000 → "999", 1000–9999 → "1.2k", ≥ 10000 → "12k"
format_short :: proc(n: i32) -> string {
	if n < 1000 { return fmt.tprintf("%d", n) }
	k := f32(n) / 1000.0
	if k < 10.0 { return fmt.tprintf("%.1fk", k) }
	return fmt.tprintf("%.0fk", k)
}

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

// Encola un tooltip de texto simple para que se dibuje al final del frame.
// Solo el primer llamado por frame tiene efecto (first-writer wins).
render_label_tooltip :: proc(app: ^entities.App_State, label: string, trigger_rect: raylib.Rectangle) {
	if app.pending_tooltip.kind != .NONE { return }
	if !raylib.CheckCollisionPointRec(raylib.GetMousePosition(), trigger_rect) { return }
	app.pending_tooltip = {
		kind    = .LABEL,
		trigger = trigger_rect,
		label   = label,
	}
}

// Encola un tooltip de carta para que se dibuje al final del frame.
render_card_tooltip :: proc(app: ^entities.App_State, card: entities.Card, trigger_rect: raylib.Rectangle) {
	if app.pending_tooltip.kind != .NONE { return }
	if !raylib.CheckCollisionPointRec(raylib.GetMousePosition(), trigger_rect) { return }
	app.pending_tooltip = {
		kind    = .CARD,
		trigger = trigger_rect,
		card    = card,
	}
}

// Dibuja el tooltip encolado este frame y limpia el estado.
// Llamar al final de render_game, después de todo lo demás.
render_tooltip_layer :: proc(app: ^entities.App_State) {
	defer app.pending_tooltip.kind = .NONE

	switch app.pending_tooltip.kind {
	case .NONE:
		return

	case .LABEL:
		tip   := &app.pending_tooltip
		pad   := f32(10)
		fsz   := f32(constants.UI_TOOLTIP_FONT_SIZE)
		cs    := strings.clone_to_cstring(tip.label, context.temp_allocator)
		lw    := raylib.MeasureTextEx(constants.game_fonts.bold, cs, fsz, 0).x
		tip_w := lw + pad * 2
		tip_h := fsz + pad
		tip_x := tip.trigger.x + tip.trigger.width/2 - tip_w/2
		tip_y := tip.trigger.y - tip_h - f32(constants.UI_TOOLTIP_OFFSET)
		r     := render_tooltip({tip_x, tip_y, tip_w, tip_h})
		raylib.DrawTextEx(
			constants.game_fonts.bold, cs,
			{r.x + r.width/2 - lw/2, r.y + r.height/2 - fsz/2},
			fsz, 0, constants.UI_PANEL_TEXT_COLOR,
		)

	case .CARD:
		tip      := &app.pending_tooltip
		card     := tip.card
		FONT_SIZE : f32 = f32(constants.UI_TOOLTIP_FONT_SIZE)
		PAD       : f32 = 10
		LINE_H    : f32 = FONT_SIZE + 4

		lines : [4]string
		n     := 0
		push :: proc(lines: ^[4]string, n: ^int, text: string) {
			if n^ >= 4 { return }
			lines[n^] = text
			n^ += 1
		}

		#partial switch card.kind {
		case .TOWER:
			tower_desc_key : string
			switch card.tower_type {
			case .ARCHER:  tower_desc_key = "TOOLTIP_ARCHER_DESC"
			case .CANNON:  tower_desc_key = "TOOLTIP_CANNON_DESC"
			case .SNIPER:  tower_desc_key = "TOOLTIP_SNIPER_DESC"
			case .MISSILE: tower_desc_key = "TOOLTIP_MISSILE_DESC"
			case .LASER:   tower_desc_key = "TOOLTIP_LASER_DESC"
			case .ICE:     tower_desc_key = "TOOLTIP_ICE_DESC"
			case .ENHANCE: tower_desc_key = "TOOLTIP_ENHANCE_DESC"
			case .TESLA:   tower_desc_key = "TOOLTIP_TESLA_DESC"
			case .MORTAR:  tower_desc_key = "TOOLTIP_MORTAR_DESC"
			}
			push(&lines, &n, constants.get_text(tower_desc_key))
		case .OBSTACLE:
			push(&lines, &n, constants.get_text("TOOLTIP_OBSTACLE_DESC"))
		case:
			rspec, rok := entities.relic_spec_for(card.kind)
			if rok { push(&lines, &n, constants.get_text(rspec.desc_key)) }
		}

		#partial switch card.kind {
		case .TOWER:
			tspec := constants.TOWER_SPECS[card.tower_type]
			push(&lines, &n, fmt.tprintf("DMG %.1f  CD %.2fs  RNG %.1f", tspec.damage, tspec.cooldown, tspec.range))
			if tspec.aoe > 0 {
				push(&lines, &n, fmt.tprintf("AoE %.1f", tspec.aoe))
			}
		case .OBSTACLE:
			// sin stat numérico
		case:
			rspec, rok := entities.relic_spec_for(card.kind)
			if rok && rspec.stat_format != nil {
				push(&lines, &n, rspec.stat_format())
			}
		}

		max_w : f32 = 0
		for i in 0 ..< n {
			w := raylib.MeasureTextEx(constants.game_fonts.bold,
				strings.clone_to_cstring(lines[i], context.temp_allocator), FONT_SIZE, 0).x
			if w > max_w { max_w = w }
		}
		tip_w := max_w + PAD * 2
		tip_h := f32(n) * LINE_H + PAD * 2 - 4
		tip_x := tip.trigger.x + tip.trigger.width/2 - tip_w/2
		tip_y := tip.trigger.y - tip_h - f32(constants.UI_TOOLTIP_OFFSET)
		r     := render_tooltip({tip_x, tip_y, tip_w, tip_h})
		for i in 0 ..< n {
			col := constants.UI_PANEL_TEXT_COLOR if i == 0 else raylib.Color{60, 100, 160, 255}
			raylib.DrawTextEx(
				constants.game_fonts.bold,
				strings.clone_to_cstring(lines[i], context.temp_allocator),
				{r.x + PAD, r.y + PAD + f32(i) * LINE_H},
				FONT_SIZE, 0, col,
			)
		}
	}
}
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

	append(&ui_click_blocks, raylib.Rectangle{f32(x), f32(y), f32(actual_width), f32(actual_height)})

	if hovered && raylib.IsMouseButtonPressed(.LEFT) &&
	   !ui_is_modal_blocked(i32(mouse_pos.x), i32(mouse_pos.y)) {
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
	if !enabled {
		resolved_text_color = raylib.WHITE
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

	append(&ui_click_blocks, raylib.Rectangle{f32(x), f32(y), f32(actual_width), f32(height)})

	if hovered && raylib.IsMouseButtonPressed(.LEFT) &&
	   !ui_is_modal_blocked(i32(mouse_x), i32(mouse_y)) {
		play_sound(.CLICK, .UI)
		return true
	}

	return false
}
tower_panel_active: bool = false
tower_panel_strategy_active: i32 = 0 // 0 = FIRST, 1 = LAST, 2 = MAX_HP, 3 = MIN_HP

// UI click-blocking registry.
// Every rendered panel and button appends its screen rectangle here.
// input_handle_playing reads this to ignore grid clicks that land on UI.
// Cleared at the start of each frame in render_game.
ui_click_blocks: [dynamic]raylib.Rectangle

ui_blocks_clear :: proc() {
	clear(&ui_click_blocks)
	clear(&ui_modal_blocks)
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

// Modal blocking registry — exclusivo para overlays que deben bloquear todos los
// botones de capas inferiores (ej. el shop). A diferencia de ui_click_blocks,
// render_button consulta esta lista en vez de la de paneles/grilla.
// Se limpia en ui_blocks_clear (inicio de frame) y también dentro del overlay
// modal antes de renderizar sus propios botones.
ui_modal_blocks: [dynamic]raylib.Rectangle

ui_is_modal_blocked :: proc(x, y: i32) -> bool {
	p := raylib.Vector2{f32(x), f32(y)}
	for rect in ui_modal_blocks {
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
render_info_panel :: proc(app: ^entities.App_State, rect: raylib.Rectangle, tooltip: string, value: string = "", icon: raylib.Texture2D = {}) -> raylib.Rectangle {
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
		render_label_tooltip(app, tooltip, rect)
	}

	return raylib.Rectangle{content_x, content_y, content_w, content_h}
}
// ─── Deck builder UI ──────────────────────────────────────────────────────────

// Dimensiones de una carta en la mano
CARD_W  :: f32(110)
CARD_H  :: f32(155)
CARD_GAP :: f32(10)
CARD_BOTTOM_MARGIN :: f32(16)

render_relic_preview :: proc(
	app: ^entities.App_State,
	kind: entities.Card_Kind,
	icon_cx: f32, preview_y: f32, preview_size: f32,
) {
	icon   := entities.relic_icon(kind)
	stacks := entities.relic_stacks(&app.sim, kind)

	if icon.id != 0 {
		sz     := preview_size
		aspect := f32(icon.width) / f32(icon.height) if icon.height > 0 else 1.0
		iw     := sz * aspect
		src    := raylib.Rectangle{0, 0, f32(icon.width), f32(icon.height)}
		dst    := raylib.Rectangle{icon_cx - iw / 2, preview_y, iw, sz}
		raylib.DrawTexturePro(icon, src, dst, {0, 0}, 0, raylib.WHITE)
	}

	// Badge con número de stacks acumulados
	if stacks > 0 {
		badge   := fmt.ctprintf("x%d", stacks)
		badge_w := raylib.MeasureTextEx(constants.game_fonts.semibold, badge, 13, 0).x
		badge_y := preview_y + preview_size - 2
		raylib.DrawTextEx(constants.game_fonts.semibold, badge, {icon_cx - badge_w / 2, badge_y}, 13, 0, raylib.Color{255, 220, 100, 255})
	}
}
render_card :: proc(
	app: ^entities.App_State,
	card: entities.Card,
	x, y: f32,
	is_selected: bool,
	can_afford: bool,
	bg_override := raylib.Color{},
	show_price: bool = false,
) {
	bg: raylib.Color
	if !can_afford {
		bg = raylib.Color{110, 110, 115, 255}
	} else if bg_override.a > 0 {
		bg = bg_override
	} else {
		bg = constants.UI_PANEL_COLOR
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

	// Borde sutil
	raylib.DrawRectangleRoundedLinesEx(card_rect, constants.UI_ROUNDNESS, constants.UI_SEGMENTS, 1.5, raylib.Color{160, 160, 160, 120})

	// Preview — ocupa el tercio superior
	preview_size : f32 = 58
	preview_x := x + (CARD_W - preview_size) / 2
	preview_y := y + 12
	icon_cx   := x + CARD_W / 2
	icon_cy   := preview_y + preview_size / 2
	if card.kind == .OBSTACLE {
		draw_obstacle_preview(preview_x, preview_y, preview_size)
	} else if card.kind == .TOWER {
		dummy := entities.tower_init(card.tower_type, 0, 0)
		old_show_range := app.settings.show_tower_range
		app.settings.show_tower_range = false
		render_tower(&dummy, preview_x, preview_y, preview_size)
		app.settings.show_tower_range = old_show_range
	} else if entities.is_relic(card.kind) {
		// Relictos: icono PNG + badge de stacks acumulados
		render_relic_preview(app, card.kind, icon_cx, preview_y, preview_size)
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

	// Bonus level badge — solo torres con bonus_level > 0
	if card.kind == .TOWER && card.bonus_level > 0 {
		// "+X" en esquina superior derecha
		bonus_str  := fmt.ctprintf("+%d", card.bonus_level)
		bonus_size : f32 = 13
		bonus_w    := raylib.MeasureTextEx(constants.game_fonts.bold, bonus_str, bonus_size, 0).x
		bonus_x    := x + CARD_W - bonus_w - 6
		bonus_y    := y + 6
		draw_text_with_outline(bonus_str, {bonus_x, bonus_y}, bonus_size, 0,
			raylib.Color{100, 220, 255, 255}, raylib.Color{0, 0, 0, 200}, 1,
			constants.game_fonts.bold)

		// "→ Nv. X" debajo del nombre
		level_str  := fmt.ctprintf("-> Nv. %d", card.bonus_level + 1)
		level_size : f32 = 11
		level_w    := raylib.MeasureTextEx(constants.game_fonts.regular, level_str, level_size, 0).x
		draw_text_with_outline(level_str, {x + (CARD_W - level_w) / 2, y + 90}, level_size, 0,
			raylib.Color{100, 220, 255, 255}, raylib.Color{0, 0, 0, 200}, 1,
			constants.game_fonts.regular)
	}

	// Separador
	raylib.DrawLineEx({x + 10, y + 96}, {x + CARD_W - 10, y + 96}, 1, raylib.Color{100, 100, 120, 120})

	// Costo — solo en el shop y solo para cartas que tienen precio (no relictos)
	if show_price && !entities.is_relic(card.kind) {
		cost_str  := fmt.ctprintf("$%d", entities.card_cost(card))
		cost_size : f32 = 15
		cost_w    := raylib.MeasureTextEx(constants.game_fonts.semibold, cost_str, cost_size, 0).x
		cost_color := can_afford ? raylib.Color{80, 220, 100, 255} : raylib.Color{200, 60, 60, 255}
		raylib.DrawTextEx(
			constants.game_fonts.bold,
			cost_str,
			{x + (CARD_W - cost_w) / 2, y + 102},
			cost_size, 0, cost_color,
		)
	}

	// Badge de rareza — siempre al pie de la carta
	render_rarity(entities.card_rarity(card), x, y + CARD_H - 24, CARD_W)
}

// Devuelve el color de acento (badge/borde) según rareza.
rarity_border_color :: proc(rarity: constants.Card_Rarity) -> raylib.Color {
	switch rarity {
	case .COMMON:   return constants.RARITY_COLOR_COMMON
	case .UNCOMMON: return constants.RARITY_COLOR_UNCOMMON
	case .RARE:     return constants.RARITY_COLOR_RARE
	case .UNIQUE:   return constants.RARITY_COLOR_UNIQUE
	}
	return constants.RARITY_COLOR_COMMON
}

// Devuelve el color de fondo de carta según rareza.
rarity_card_bg :: proc(rarity: constants.Card_Rarity) -> raylib.Color {
	switch rarity {
	case .COMMON:   return constants.RARITY_CARD_BG_COMMON
	case .UNCOMMON: return constants.RARITY_CARD_BG_UNCOMMON
	case .RARE:     return constants.RARITY_CARD_BG_RARE
	case .UNIQUE:   return constants.RARITY_CARD_BG_UNIQUE
	}
	return constants.RARITY_CARD_BG_COMMON
}

// Renderiza una etiqueta de rareza al pie de una carta.
// badge_y: coordenada Y de la parte superior del badge.
render_rarity :: proc(rarity: constants.Card_Rarity, card_x, badge_y, card_w: f32) {
	BADGE_H  : f32 = 20
	PAD      : f32 = 8
	FONT_SZ  : f32 = 11

	label : string
	switch rarity {
	case .COMMON:   label = constants.get_text("RARITY_COMMON")
	case .UNCOMMON: label = constants.get_text("RARITY_UNCOMMON")
	case .RARE:     label = constants.get_text("RARITY_RARE")
	case .UNIQUE:   label = constants.get_text("RARITY_UNIQUE")
	}

	text_w := raylib.MeasureTextEx(constants.game_fonts.semibold,
		strings.clone_to_cstring(label, context.temp_allocator), FONT_SZ, 0).x
	badge_w := text_w + PAD * 2
	badge_x := card_x + (card_w - badge_w) / 2

	bg_col := rarity_border_color(rarity)
	badge_rect := raylib.Rectangle{badge_x, badge_y, badge_w, BADGE_H}
	raylib.DrawRectangleRounded(badge_rect, 0.4, 6, bg_col)
	raylib.DrawTextEx(
		constants.game_fonts.semibold,
		strings.clone_to_cstring(label, context.temp_allocator),
		{badge_x + PAD, badge_y + (BADGE_H - FONT_SZ) / 2},
		FONT_SZ, 0, raylib.WHITE,
	)
}

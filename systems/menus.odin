package systems

import "../constants"
import "../entities"
import "core:fmt"
import "core:os"
import "core:math"
import "core:strings"
import "vendor:raylib"

render_ui :: proc(app: ^entities.App_State) {
	// El shop es modal: bloquea toda la pantalla para que los botones de PLAYING
	// no respondan mientras el overlay está activo. Usa ui_modal_blocks (separado
	// de ui_click_blocks) para no interferir con los paneles normales.
	if app.state == .PLAYING && app.sim.card_selection_active {
		sw := f32(raylib.GetScreenWidth())
		sh := f32(raylib.GetScreenHeight())
		append(&ui_modal_blocks, raylib.Rectangle{0, 0, sw, sh})
	}

	// El modal de confirmación Sí/No también es modal: bloquea toda la pantalla
	// mientras está activo (mismo patrón que el shop, ver arriba).
	if app.confirm_modal.active {
		sw := f32(raylib.GetScreenWidth())
		sh := f32(raylib.GetScreenHeight())
		append(&ui_modal_blocks, raylib.Rectangle{0, 0, sw, sh})
	}

	switch app.state {
	case .MENU:
		render_menu_ui(app)
	case .PLAYING:
		render_game_ui(app)
		render_tower_control_panel(app)
		render_obstacle_control_panel(app)
		render_relic_tray(app)
	case .PAUSED:
		render_pause_menu(app)
	case .EDITOR:
		render_editor_ui(app)
	case .GAME_OVER:
		render_game_over_ui(app)
	case .SETTINGS:
		render_settings_menu(app)
	case .RUN_COMPLETE:
		render_run_complete_ui(app)
	case .PROGRESSION:
		render_progression_ui(app)
	}

	// Shop — capa superior: siempre encima del resto de la UI de juego
	if app.state == .PLAYING && app.sim.card_selection_active {
		render_card_selection_overlay(app)
	}

	// Modal de confirmación Sí/No — capa superior absoluta, encima de todo
	if app.confirm_modal.active {
		switch render_confirm_modal(app.confirm_modal.text) {
		case .CONFIRMED:
			action := app.confirm_modal.action
			app.confirm_modal = entities.Confirm_Modal{}
			switch action {
			case .NEW_GAME:
				app.meta = entities.Meta_State{}
				entities.meta_save(&app.meta)
				_open_map_browser(app)
			case .RESTART_RUN:
				map_name := app.editor.current_map_name
				simulation_set_pause(app, false)
				simulation_reset(app)
				entities.map_load(&app.editor.game_map, map_name)
				entities.app_set_state(app, .PLAYING)
			case .EXIT_GAME:
				app.should_quit = true
			case .NONE:
			}
		case .CANCELLED:
			app.confirm_modal = entities.Confirm_Modal{}
		case .NONE:
		}
	}

	// La mano se renderiza siempre al frente durante PLAYING:
	// encima del shop overlay para que las cartas sean visibles y vendibles en todo momento.
	if app.state == .PLAYING {
		render_card_hand(app)
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
// render_background is a no-op: the nebula shader is drawn once at the start
// of render_game (before render_ui), so it already sits behind everything.
render_background :: proc() {}

_open_map_browser :: proc(app: ^entities.App_State) {
	entities.map_file_entries_destroy(&app.editor.map_browser_entries)
	app.editor.map_browser_entries       = entities.map_list_saved_entries()
	app.editor.map_browser_scroll        = 0
	app.editor.map_browser_selected      = -1
	app.editor.map_browser_preview       = entities.map_init()
	app.editor.map_browser_preview_valid = false
	app.editor.show_map_browser          = true
	app.editor.map_browser_play_mode     = true
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
	button_font_size   := f32(constants.UI_BUTTON_FONT_SIZE)
	gap                := i32(10)

	savegame_exists := os.exists(entities.META_SAVE_PATH)

	// Slot count: Continue (conditional) + Nueva Partida + Editor + Settings + Progression + Exit
	slot_count := (4 if constants.DEVELOPER else 3) + (1 if savegame_exists else 0)
	total_buttons_height := slot_count * int(menu_button_height) + (slot_count - 1) * int(gap)
	start_y := (i32(screen_height) - i32(total_buttons_height)) / 2
	current_y := start_y

	// Continue (only if savegame exists)
	if savegame_exists {
		continue_text := constants.get_text("MENU_BUTTON_CONTINUE")
		continue_w    := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(continue_text, context.temp_allocator), button_font_size, 0).x)
		if render_button(
			continue_text,
			{f32(screen_width / 2 - continue_w / 2), f32(current_y), f32(continue_w), f32(menu_button_height)},
		) {
			_open_map_browser(app)
		}
		current_y += menu_button_height + gap
	}

	// Nueva Partida
	new_game_text := constants.get_text("MENU_BUTTON_NEW_GAME")
	new_game_w    := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(new_game_text, context.temp_allocator), button_font_size, 0).x)
	if render_button(
		new_game_text,
		{f32(screen_width / 2 - new_game_w / 2), f32(current_y), f32(new_game_w), f32(menu_button_height)},
	) {
		app.confirm_modal = entities.Confirm_Modal{
			active = true,
			text   = "¿Iniciar una nueva campaña?\nSe reiniciará tu progreso guardado.",
			action = .NEW_GAME,
		}
	}
	current_y += menu_button_height + gap

	// Editor (solo en modo Developer)
	if constants.DEVELOPER {
		txt := constants.get_text("MENU_BUTTON_EDITOR")
		w   := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(txt, context.temp_allocator), button_font_size, 0).x)
		if render_button(txt, {f32(screen_width / 2 - w / 2), f32(current_y), f32(w), f32(menu_button_height)}) {
			entities.app_set_state(app, .EDITOR)
		}
		current_y += menu_button_height + gap
	}

	// Settings
	{
		txt := constants.get_text("MENU_BUTTON_SETTINGS")
		w   := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(txt, context.temp_allocator), button_font_size, 0).x)
		if render_button(txt, {f32(screen_width / 2 - w / 2), f32(current_y), f32(w), f32(menu_button_height)}) {
			entities.app_set_state(app, .SETTINGS)
		}
		current_y += menu_button_height + gap
	}

	// Progression
	{
		txt := constants.get_text("MENU_BUTTON_PROGRESSION")
		w   := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(txt, context.temp_allocator), button_font_size, 0).x)
		if render_button(txt, {f32(screen_width / 2 - w / 2), f32(current_y), f32(w), f32(menu_button_height)}) {
			entities.app_set_state(app, .PROGRESSION)
		}
		current_y += menu_button_height + gap
	}

	// Exit
	{
		txt := constants.get_text("MENU_BUTTON_EXIT")
		w   := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(txt, context.temp_allocator), button_font_size, 0).x)
		if render_button(txt, {f32(screen_width / 2 - w / 2), f32(current_y), f32(w), f32(menu_button_height)}) {
			app.confirm_modal = entities.Confirm_Modal{
				active = true,
				text   = "¿Salir del juego?",
				action = .EXIT_GAME,
			}
		}
	}

	// Browser de mapas en play mode (encima del menú)
	if app.editor.show_map_browser {
		render_map_browser(app)
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
		app,
		{hud_px, hud_py, hud_panel_w, hud_panel_h},
		constants.get_text("UI_MONEY"),
		format_short(app.sim.money),
		constants.game_icons.money,
	)

	// Health
	hud_py += hud_panel_h + hud_panel_gap
	render_info_panel(
		app,
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
			app,
			{hud_px, hud_py, hud_panel_w, hud_panel_h},
			constants.get_text("UI_WAVE"),
			fmt.tprintf("%d", display_wave),
			constants.game_icons.wave,
		)
	}

	// Upcoming waves preview — visible solo con la reliquia Scout activa; muestra N oleadas según stacks
	if app.sim.relic_stacks[.SCOUT] > 0 {
	hud_py += hud_panel_h + hud_panel_gap
	{
		c := render_info_panel(app, {hud_px, hud_py, hud_panel_w, hud_panel_h}, constants.get_text("UI_UPCOMING"))

		scout_slots := min(app.sim.relic_stacks[.SCOUT], 3)
		base_wave := app.sim.wave_number
		icon_r    : f32 = 9
		slot_w    := c.width / f32(scout_slots)
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

		for i in 0 ..< scout_slots {
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
			render_label_tooltip(app, tooltip, hit_rect)
		}
	}
	} // Scout panel

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
	show_next_wave_button := !app.settings.auto_start_wave && can_start_wave

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

	// Skip Shop toggle button width
	skip_shop_text := "Skip Shop"
	skip_shop_text_width := i32(
		raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(skip_shop_text, context.temp_allocator), font_size, 0).x,
	)
	skip_shop_width := skip_shop_text_width + padding

	// Calculate total width based on visible buttons
	visible_button_count := i32(6) // Start + Skip Shop + Pause + 1x + 2x + 3x
	gap_count := i32(5)
	if show_next_wave_button {
		visible_button_count += 1
		gap_count += 1
	}
	total_buttons_width := pause_width + speed1_width + speed2_width + speed3_width + start_width + skip_shop_width + gap * gap_count + constants.UI_MARGIN_X
	if show_next_wave_button {
		total_buttons_width += next_wave_width
	}

	start_x  := screen_width - total_buttons_width
	skip_shop_x := start_x + start_width + gap
	next_wave_x := skip_shop_x + skip_shop_width + gap
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

	// Skip Shop toggle — activa/desactiva el cierre automático de la tienda al final de cada oleada
	if render_button(
		skip_shop_text,
		{f32(skip_shop_x), f32(button_y), f32(skip_shop_width), f32(constants.UI_BUTTON_HEIGHT)},
		1,
		true,
		no_color,
		app.settings.auto_skip_shop ? active_green : no_color,
		app.settings.auto_skip_shop ? active_green_hover : no_color,
		app.settings.auto_skip_shop ? active_green_press : no_color,
	) {
		app.settings.auto_skip_shop = !app.settings.auto_skip_shop
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
			{constants.get_text("TOWER_TESLA_NAME"), .TOWER_TESLA},
			{constants.get_text("TOWER_MORTAR_NAME"), .TOWER_MORTAR},
			{constants.get_text("EDITOR_TOOL_OBSTACLE"), .OBSTACLE},
			{constants.get_text("EDITOR_TOOL_TREE"), .ACCESSORY_TREE},
			{constants.get_text("EDITOR_TOOL_BLOCK"), .ACCESSORY_BLOCK},
			{constants.get_text("EDITOR_TOOL_WATER"), .WATER},
		}

		preview_size := f32(34)
		btn_pad      := i32(5)
		btn_size     := i32(preview_size) + btn_pad * 2  // botón se ajusta al ícono
		gap          := i32(4)
		total_width  := i32(len(tools)) * btn_size + i32(len(tools) - 1) * gap
		start_x      := (screen_width - total_width) / 2

		for tool, i in tools {
			x := start_x + i32(i) * (btn_size + gap)
			y := i32(screen_height) - btn_size - bottom_margin

			is_selected  := app.editor.current_tool == tool.tile
			button_color := raylib.LIGHTGRAY
			if is_selected { button_color = raylib.BLUE }

			btn_rect := raylib.Rectangle{f32(x), f32(y), f32(btn_size), f32(btn_size)}

			if render_button_with_color("", btn_rect, button_color, 4, 12.0) {
				app.editor.current_tool = tool.tile
			}

			// Preview centrado en el botón
			preview_x := f32(x) + f32(btn_pad)
			preview_y := f32(y) + f32(btn_pad)

			switch tool.tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER,
			     .TOWER_ICE, .TOWER_ENHANCE, .TOWER_TESLA, .TOWER_MORTAR:
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
			case .WATER:
				// Preview: rectángulo redondeado azul
				raylib.DrawRectangleRounded(
					{preview_x, preview_y, preview_size, preview_size},
					0.4, 6, constants.COLOR_WATER,
				)
			}

			// Tooltip con el nombre del tile al pasar el mouse
			render_label_tooltip(app, tool.name, btn_rect)
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
			simulation_fit_camera(app, f32(raylib.GetScreenWidth()), f32(raylib.GetScreenHeight()))
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
			entities.map_destroy(&app.editor.map_browser_preview)
			app.editor.map_browser_preview_valid = false
			if app.editor.map_browser_preview_tex_valid {
				raylib.UnloadRenderTexture(app.editor.map_browser_preview_tex)
				app.editor.map_browser_preview_tex_valid = false
			}
			app.editor.show_map_browser = false
		} else {
			entities.map_file_entries_destroy(&app.editor.map_browser_entries)
			app.editor.map_browser_entries = entities.map_list_saved_entries()
			app.editor.map_browser_scroll   = 0
			app.editor.map_browser_selected = -1
			app.editor.map_browser_preview  = entities.map_init()
			app.editor.map_browser_preview_valid = false
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

// Render modal de selección de mapas (visor split: lista izq. + preview der.)
render_map_browser :: proc(app: ^entities.App_State) {
	screen_width  := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	// Overlay
	raylib.DrawRectangle(0, 0, screen_width, screen_height, constants.UI_MAP_BROWSER_OVERLAY_COLOR)

	panel_w := i32(constants.UI_MAP_BROWSER_WIDTH)
	panel_h := i32(constants.UI_MAP_BROWSER_HEIGHT)
	panel_x := screen_width  / 2 - panel_w / 2
	panel_y := screen_height / 2 - panel_h / 2

	render_panel(
		{f32(panel_x), f32(panel_y), f32(panel_w), f32(panel_h)},
		constants.get_text("EDITOR_MAP_BROWSER_TITLE"),
	)

	header_h      := i32(constants.UI_MAP_BROWSER_HEADER_HEIGHT)
	footer_h      := i32(constants.UI_MAP_BROWSER_FOOTER_HEIGHT)
	list_w        := i32(constants.UI_MAP_BROWSER_LIST_WIDTH)
	content_y     := panel_y + header_h
	content_h     := panel_h - header_h - footer_h
	item_h        := i32(constants.UI_MAP_BROWSER_ITEM_HEIGHT)
	item_font     := f32(constants.UI_MAP_BROWSER_ITEM_FONT_SIZE)
	visible_items := content_h / item_h
	side_pad      := i32(constants.UI_MAP_BROWSER_ITEM_SIDE_PADDING)
	vert_gap      := i32(constants.UI_MAP_BROWSER_ITEM_VERT_GAP)

	// ── Left: map list ────────────────────────────────────────────────────────
	list_x     := panel_x
	divider_x  := panel_x + list_w
	mouse      := raylib.GetMousePosition()

	// Vertical divider
	raylib.DrawLine(
		divider_x, content_y,
		divider_x, content_y + content_h,
		constants.UI_MAP_BROWSER_SEPARATOR_COLOR,
	)

	if len(app.editor.map_browser_entries) == 0 {
		no_maps_cs := strings.clone_to_cstring("No hay mapas guardados", context.temp_allocator)
		nw := raylib.MeasureTextEx(constants.game_fonts.regular, no_maps_cs, item_font, 0).x
		raylib.DrawTextEx(
			constants.game_fonts.regular, no_maps_cs,
			{f32(list_x) + f32(list_w)/2 - nw/2, f32(content_y) + f32(content_h)/2 - item_font/2},
			item_font, 0, constants.UI_MAP_BROWSER_MUTED_COLOR,
		)
	}

	for i in 0 ..< visible_items {
		idx    := i + app.editor.map_browser_scroll
		if idx >= i32(len(app.editor.map_browser_entries)) { break }

		entry  := app.editor.map_browser_entries[idx]
		item_y := content_y + i * item_h

		item_rect := raylib.Rectangle{
			f32(list_x + side_pad),
			f32(item_y + vert_gap / 2),
			f32(list_w - side_pad * 2),
			f32(item_h - vert_gap),
		}

		is_selected := idx == app.editor.map_browser_selected
		hovered     := raylib.CheckCollisionPointRec(mouse, item_rect)

		if is_selected {
			raylib.DrawRectangleRounded(
				item_rect, constants.UI_BUTTON_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS,
				constants.UI_MAP_BROWSER_SELECTED_BG_COLOR,
			)
		} else if hovered {
			raylib.DrawRectangleRounded(
				item_rect, constants.UI_BUTTON_ROUNDNESS, constants.TOWER_CORNER_SEGMENTS,
				constants.UI_BUTTON_HOVER_COLOR,
			)
		}

		text_color: raylib.Color
		if is_selected || entry.name == app.editor.current_map_name {
			text_color = constants.UI_MAP_BROWSER_LOADED_COLOR
		} else {
			text_color = constants.UI_TEXT_COLOR
		}

		fname_cs := strings.clone_to_cstring(entry.name, context.temp_allocator)
		text_y   := item_rect.y + (f32(item_h - vert_gap) - item_font) / 2
		raylib.DrawTextEx(
			constants.game_fonts.regular, fname_cs,
			{item_rect.x + f32(constants.UI_MAP_BROWSER_ITEM_TEXT_INDENT), text_y},
			item_font, 0, text_color,
		)

		// Click selecciona y carga la vista previa
		if hovered && raylib.IsMouseButtonPressed(.LEFT) {
			app.editor.map_browser_selected = idx
			entities.map_load(&app.editor.map_browser_preview, entry.name)
			app.editor.map_browser_preview_valid = true
			render_map_preview_to_texture(app)
		}
	}

	// Scroll indicator
	total := i32(len(app.editor.map_browser_entries))
	if total > visible_items {
		last_visible := min(app.editor.map_browser_scroll + visible_items, total)
		scroll_text  := fmt.tprintf("%d–%d / %d", app.editor.map_browser_scroll + 1, last_visible, total)
		scroll_font  := f32(constants.UI_MAP_BROWSER_SCROLL_FONT_SIZE)
		scroll_cs    := strings.clone_to_cstring(scroll_text, context.temp_allocator)
		sw           := raylib.MeasureTextEx(constants.game_fonts.regular, scroll_cs, scroll_font, 0).x
		scroll_y     := f32(content_y + content_h) - scroll_font - 6
		raylib.DrawTextEx(
			constants.game_fonts.regular, scroll_cs,
			{f32(list_x) + f32(list_w)/2 - sw/2, scroll_y},
			scroll_font, 0, constants.UI_MAP_BROWSER_MUTED_COLOR,
		)
	}

	// ── Right: preview ────────────────────────────────────────────────────────
	preview_pad  := i32(constants.UI_MAP_BROWSER_PREVIEW_PAD)
	preview_x    := divider_x + 1 + preview_pad
	preview_w    := panel_x + panel_w - preview_x - preview_pad
	info_h       := i32(constants.UI_MAP_BROWSER_INFO_HEIGHT)
	mini_area_h  := content_h - info_h - 4
	info_font    := f32(constants.UI_MAP_BROWSER_INFO_FONT_SIZE)

	if !app.editor.map_browser_preview_valid {
		hint    := strings.clone_to_cstring("← Selecciona un mapa", context.temp_allocator)
		hw      := raylib.MeasureTextEx(constants.game_fonts.regular, hint, item_font, 0).x
		raylib.DrawTextEx(
			constants.game_fonts.regular, hint,
			{f32(preview_x) + f32(preview_w)/2 - hw/2, f32(content_y) + f32(content_h)/2 - item_font/2},
			item_font, 0, constants.UI_MAP_BROWSER_MUTED_COLOR,
		)
	} else {
		pmap := &app.editor.map_browser_preview

		map_w := pmap.width  if pmap.width  > 0 else 1
		map_h := pmap.height if pmap.height > 0 else 1

		if app.editor.map_browser_preview_tex_valid {
			tex   := app.editor.map_browser_preview_tex
			tex_w := f32(tex.texture.width)
			tex_h := f32(tex.texture.height)

			// Fit texture inside preview area preserving aspect ratio
			scale  := min(f32(preview_w) / tex_w, f32(mini_area_h) / tex_h)
			dest_w := tex_w * scale
			dest_h := tex_h * scale
			dest_x := f32(preview_x) + (f32(preview_w) - dest_w) / 2
			dest_y := f32(content_y)  + (f32(mini_area_h) - dest_h) / 2

			// Negative source height corrects OpenGL Y-flip in RenderTexture2D
			src  := raylib.Rectangle{0, 0, tex_w, -tex_h}
			dest := raylib.Rectangle{dest_x, dest_y, dest_w, dest_h}
			raylib.DrawTexturePro(tex.texture, src, dest, {0, 0}, 0, raylib.WHITE)

			// Border
			raylib.DrawRectangleLines(
				i32(dest_x), i32(dest_y), i32(dest_w), i32(dest_h),
				constants.UI_MAP_BROWSER_SEPARATOR_COLOR,
			)
		}

		// Info: filename + dimensions + date below the mini-map
		if app.editor.map_browser_selected >= 0 &&
		   int(app.editor.map_browser_selected) < len(app.editor.map_browser_entries) {
			sel := app.editor.map_browser_entries[app.editor.map_browser_selected]
			info_y := f32(content_y + mini_area_h + 4)

			name_cs := strings.clone_to_cstring(sel.name, context.temp_allocator)
			raylib.DrawTextEx(
				constants.game_fonts.regular, name_cs,
				{f32(preview_x), info_y},
				info_font, 0, constants.UI_TEXT_COLOR,
			)

			dims_str := fmt.tprintf("%dx%d  •  %s", map_w, map_h, sel.mod_date)
			dims_cs  := strings.clone_to_cstring(dims_str, context.temp_allocator)
			raylib.DrawTextEx(
				constants.game_fonts.regular, dims_cs,
				{f32(preview_x), info_y + info_font + 3},
				info_font, 0, constants.UI_MAP_BROWSER_MUTED_COLOR,
			)
		}
	}

	// ── Footer ───────────────────────────────────────────────────────────────
	btn_h   := i32(constants.UI_MAP_BROWSER_CLOSE_HEIGHT)
	btn_y   := panel_y + panel_h - btn_h - i32(constants.UI_MAP_BROWSER_CLOSE_BTN_MARGIN)
	btn_w   := i32(constants.UI_BUTTON_WIDTH)
	close_x := panel_x + side_pad * 2
	open_x  := panel_x + panel_w - btn_w - side_pad * 2

	if app.editor.map_browser_renaming {
		// ── Modo rename: [Cancelar] [  input  ] [Confirmar] ──────────────────
		input_x := f32(close_x + btn_w + 8)
		input_w := f32(open_x - btn_w - 8) - input_x
		confirmed := render_input(
			&app.editor.map_browser_rename_input,
			{input_x, f32(btn_y), input_w, f32(btn_h)},
			app.delta_time,
		)

		if render_button("Cancelar", {f32(close_x), f32(btn_y), f32(btn_w), f32(btn_h)}) {
			app.editor.map_browser_renaming = false
		}

		btn_confirm := render_button("Confirmar", {f32(open_x - btn_w), f32(btn_y), f32(btn_w), f32(btn_h)})
		if confirmed || btn_confirm {
			sel      := app.editor.map_browser_selected
			new_name := entities.input_str(&app.editor.map_browser_rename_input)
			if new_name == "" {
				entities.add_toast(app, "El nombre no puede estar vacío", .ERROR, 2.5)
				play_sound(.ERROR, .UI)
			} else if sel >= 0 && int(sel) < len(app.editor.map_browser_entries) {
				old_name := app.editor.map_browser_entries[sel].name
				if new_name == old_name {
					app.editor.map_browser_renaming = false
				} else if entities.map_rename(old_name, new_name) {
					// Actualizar current_map_name si se renombró el mapa activo
					if app.editor.current_map_name == old_name {
						delete(app.editor.current_map_name)
						app.editor.current_map_name = strings.clone(new_name)
					}
					// Refrescar la lista y seleccionar el nuevo nombre
					entities.map_file_entries_destroy(&app.editor.map_browser_entries)
					app.editor.map_browser_entries = entities.map_list_saved_entries()
					app.editor.map_browser_selected = -1
					for entry, i in app.editor.map_browser_entries {
						if entry.name == new_name {
							app.editor.map_browser_selected = i32(i)
							break
						}
					}
					app.editor.map_browser_renaming = false
					entities.add_toast(app, fmt.tprintf("Renombrado a: %s", new_name), .SUCCESS, 2.0)
					play_sound(.CONFIRMATION, .UI)
				} else {
					entities.add_toast(app, fmt.tprintf("No se pudo renombrar: %s", old_name), .ERROR, 3.0)
					play_sound(.ERROR, .UI)
				}
			}
		}
	} else {
		// ── Modo normal: [Cerrar]  [Renombrar]  [Abrir] ──────────────────────
		if render_button("Cerrar", {f32(close_x), f32(btn_y), f32(btn_w), f32(btn_h)}) {
			entities.map_destroy(&app.editor.map_browser_preview)
			app.editor.map_browser_preview_valid = false
			if app.editor.map_browser_preview_tex_valid {
				raylib.UnloadRenderTexture(app.editor.map_browser_preview_tex)
				app.editor.map_browser_preview_tex_valid = false
			}
			app.editor.show_map_browser = false
			app.editor.map_browser_play_mode = false
			play_sound(.CLOSE, .UI)
		}

		// Renombrar — solo en modo editor (no play mode), con un mapa seleccionado
		sel_valid := app.editor.map_browser_selected >= 0 &&
		             int(app.editor.map_browser_selected) < len(app.editor.map_browser_entries)
		if sel_valid && !app.editor.map_browser_play_mode {
			rename_x := close_x + btn_w + 8
			if render_button("Renombrar", {f32(rename_x), f32(btn_y), f32(btn_w), f32(btn_h)}) {
				sel      := app.editor.map_browser_selected
				old_name := app.editor.map_browser_entries[sel].name
				entities.input_clear(&app.editor.map_browser_rename_input)
				_input_insert_str(&app.editor.map_browser_rename_input, old_name)
				app.editor.map_browser_rename_input.sel_anchor = 0
				app.editor.map_browser_rename_input.cursor     = app.editor.map_browser_rename_input.len
				app.editor.map_browser_rename_input.focused    = true
				app.editor.map_browser_renaming = true
				play_sound(.CLICK, .UI)
			}
		}

		if app.editor.map_browser_preview_valid {
			if render_button("Abrir", {f32(open_x), f32(btn_y), f32(btn_w), f32(btn_h)}) {
				sel := app.editor.map_browser_selected
				if sel >= 0 && int(sel) < len(app.editor.map_browser_entries) {
					fname := app.editor.map_browser_entries[sel].name
					editor_push_undo(app)
					if entities.map_load(&app.editor.game_map, fname) {
						app.editor.current_biome    = app.editor.game_map.biome
						app.editor.current_map_name = strings.clone(fname)
						entities.map_destroy(&app.editor.map_browser_preview)
						app.editor.map_browser_preview_valid = false
						if app.editor.map_browser_preview_tex_valid {
							raylib.UnloadRenderTexture(app.editor.map_browser_preview_tex)
							app.editor.map_browser_preview_tex_valid = false
						}
						app.editor.show_map_browser = false
						if app.editor.map_browser_play_mode {
							app.editor.map_browser_play_mode = false
							if simulation_init_from_editor(app) {
								simulation_fit_camera(app, f32(raylib.GetScreenWidth()), f32(raylib.GetScreenHeight()))
								entities.app_set_state(app, .PLAYING)
							} else {
								entities.add_toast(app, constants.get_text("EDITOR_ERROR_NO_PATH"), .ERROR, 3.0)
								play_sound(.ERROR, .UI)
							}
						} else {
							entities.add_toast(app, fmt.tprintf("Loaded: %s", fname), .SUCCESS, 2.0)
							play_sound(.CONFIRMATION, .UI)
						}
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
				}
			}
		}
	}
}

// Render pause menu overlay
render_pause_menu :: proc(app: ^entities.App_State) {
	screen_width  := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	render_background()

	// Title
	title      := constants.get_text("PAUSE_TITLE")
	title_cstr := strings.clone_to_cstring(title, context.temp_allocator)
	title_size := f32(40)
	title_w    := raylib.MeasureTextEx(constants.game_fonts.bold, title_cstr, title_size, 0).x
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		title_cstr,
		{f32(screen_width) / 2 - title_w / 2, f32(screen_height) / 4},
		title_size, 0, raylib.WHITE,
	)

	// Buttons — same pattern as main menu: centered in full screen, width = text width
	btn_h      := i32(constants.UI_BUTTON_HEIGHT)
	btn_gap    := i32(10)
	btn_fs     := f32(constants.UI_BUTTON_FONT_SIZE)

	total_h := 4 * btn_h + 3 * btn_gap
	start_y := (screen_height - total_h) / 2

	// Resume
	resume_txt := constants.get_text("PAUSE_RESUME")
	resume_w   := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(resume_txt, context.temp_allocator), btn_fs, 0).x)
	resume_y   := start_y
	if render_button(
		resume_txt,
		{f32(screen_width / 2 - resume_w / 2), f32(resume_y), f32(resume_w), f32(btn_h)},
	) {
		simulation_set_pause(app, false)
		entities.app_set_state(app, .PLAYING)
	}

	// Restart
	restart_txt := constants.get_text("PAUSE_RESTART")
	restart_w   := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(restart_txt, context.temp_allocator), btn_fs, 0).x)
	restart_y   := resume_y + btn_h + btn_gap
	if render_button(
		restart_txt,
		{f32(screen_width / 2 - restart_w / 2), f32(restart_y), f32(restart_w), f32(btn_h)},
	) {
		app.confirm_modal = entities.Confirm_Modal{
			active = true,
			text   = "¿Reiniciar la partida?\nPerderás el progreso de esta corrida.",
			action = .RESTART_RUN,
		}
	}

	// Settings
	settings_txt := constants.get_text("MENU_BUTTON_SETTINGS")
	settings_w   := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(settings_txt, context.temp_allocator), btn_fs, 0).x)
	settings_y   := restart_y + btn_h + btn_gap
	if render_button(
		settings_txt,
		{f32(screen_width / 2 - settings_w / 2), f32(settings_y), f32(settings_w), f32(btn_h)},
	) {
		entities.app_set_state(app, .SETTINGS)
	}

	// Main Menu
	menu_txt := constants.get_text("PAUSE_MENU")
	menu_w   := i32(raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(menu_txt, context.temp_allocator), btn_fs, 0).x)
	menu_y   := settings_y + btn_h + btn_gap
	if render_button(
		menu_txt,
		{f32(screen_width / 2 - menu_w / 2), f32(menu_y), f32(menu_w), f32(btn_h)},
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
	title_key := "GAME_VICTORY_TITLE" if app.sim.is_victory else "GAME_OVER_TITLE"
	title_color := raylib.Color{50, 205, 50, 255} if app.sim.is_victory else raylib.RED
	title := constants.get_text(title_key)
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
		title_color,
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
			case .BOSS   in wm.flags: color = constants.COLOR_ENEMY_BOSS
			case .GREEN  in wm.flags: color = constants.ENEMY_GREEN
			case .BLUE   in wm.flags: color = constants.ENEMY_BLUE
			case .FLYING in wm.flags: color = constants.COLOR_ENEMY_FLYING
			case:                     color = constants.COLOR_ENEMY
			}

			// Vertical tick on graph
			raylib.DrawLine(i32(mx), gy + gh - 4, i32(mx), gy + gh, color)

			// Shape: boss=square, flying=triangle, others=circle
			switch {
			case .BOSS in wm.flags:
				raylib.DrawRectangle(
					i32(mx - marker_r),
					i32(marker_y),
					i32(marker_r * 2),
					i32(marker_r * 2),
					color,
				)
			case .FLYING in wm.flags:
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
	total_secs := i32(app.sim.play_time)

	// Para agregar un stat nuevo: solo añadir una línea al slice.
	// El tamaño del panel se calcula automáticamente a partir de len(stats).
	Stat_Row :: struct { label, value: string }
	stats := []Stat_Row{
		{constants.get_text("GAME_OVER_WAVES_SURVIVED"), fmt.tprintf("%d",      app.sim.wave_number)},
		{constants.get_text("GAME_OVER_TIME"),           fmt.tprintf("%d:%02d", total_secs / 60, total_secs % 60)},
		{constants.get_text("GAME_OVER_ENEMIES_KILLED"), fmt.tprintf("%d",      app.sim.enemies_killed)},
		{constants.get_text("GAME_OVER_MONEY_EARNED"),   fmt.tprintf("$%d",     app.sim.money_earned)},
		{constants.get_text("GAME_OVER_TOWERS_BUILT"),   fmt.tprintf("%d",      app.sim.towers_built)},
		{constants.get_text("GAME_OVER_UPGRADES"),       fmt.tprintf("%d",      app.sim.upgrades_bought)},
		{constants.get_text("GAME_OVER_SEED"),            fmt.tprintf("%d",      app.sim.seed)},
	}

	stats_panel_w := graph_panel_w
	stat_height   := i32(font_size) + 4
	stats_inner   := i32(len(stats)) * (stat_height + spacing) - spacing
	stats_total   := stats_inner + constants.UI_PANEL_PADDING * 2
	stats_x       := graph_panel_x
	stats_y       := graph_panel_y + f32(graph_panel_h) + f32(spacing)

	stats_rect    := raylib.Rectangle{stats_x, stats_y, f32(stats_panel_w), f32(stats_total)}
	stats_content := render_panel(stats_rect)

	scx := i32(stats_content.x)
	scw := i32(stats_content.width)
	sy  := i32(stats_content.y)

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

	for row in stats {
		draw_stat(row.label, row.value, scx, scw, sy, font_size)
		sy += stat_height + spacing
	}

	// --- Menu button ---
	btn_width := i32(constants.UI_BUTTON_WIDTH) * 2
	btn_x := i32(stats_x) + i32(stats_panel_w) / 2 - btn_width / 2
	btn_y := i32(stats_y) + stats_total + spacing
	if render_button(
		constants.get_text("GAME_OVER_BUTTON_MENU"),
		{f32(btn_x), f32(btn_y), f32(btn_width), f32(btn_height)},
	) {
		simulation_reset(app)
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
	case .TESLA:
		type_name = constants.get_text("TOWER_TESLA_NAME")
	case .MORTAR:
		type_name = constants.get_text("TOWER_MORTAR_NAME")
	}

	// Level subtitle — separate from type_name so the title doesn't overflow at size 22
	// Desglosa las tres fuentes de nivel: manual + Potenciador (enhance) + Cryptobro
	level_text: string
	{
		base_level := tower.level - tower.enhance_bonus - tower.cryptobro_bonus
		abbrev     := constants.get_text("PANEL_LEVEL_ABBREV")
		switch {
		case tower.enhance_bonus > 0 && tower.cryptobro_bonus > 0:
			level_text = fmt.tprintf("%s %d + %d + %d", abbrev, base_level, tower.enhance_bonus, tower.cryptobro_bonus)
		case tower.enhance_bonus > 0:
			level_text = fmt.tprintf("%s %d + %d", abbrev, base_level, tower.enhance_bonus)
		case tower.cryptobro_bonus > 0:
			level_text = fmt.tprintf("%s %d + %d", abbrev, base_level, tower.cryptobro_bonus)
		case:
			level_text = fmt.tprintf("%s %d", abbrev, tower.level)
		}
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
		draw_icon_stat(constants.game_icons.damage, fmt.tprintf("%.1f", tower.damage), content_x, current_y + 0 * line_height, icon_size, font_size)

		// Bonus de daño extra (Bloodlust + Formation): mostrar en verde junto al stat de daño
		{
			bloodlust_bonus := tower.damage * (app.sim.bloodlust_mult - 1.0)
			formation_bonus : f32 = 0
			if app.sim.relic_stacks[.FORMATION] > 0 && tower._in_formation {
				formation_bonus = tower.damage * constants.FORMATION_BONUS * f32(app.sim.relic_stacks[.FORMATION])
			}
			total_bonus := bloodlust_bonus + formation_bonus
			if total_bonus >= 0.05 {
				dmg_str      := fmt.tprintf("%.1f", tower.damage)
				dmg_width    := raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(dmg_str, context.temp_allocator), font_size, 0).x
				bonus_x      := f32(content_x) + ICON_SLOT + ICON_GAP + dmg_width + 4
				bonus_y      := f32(current_y + 0 * line_height) + (icon_size - font_size) / 2
				bonus_str    := fmt.ctprintf("(+%.1f)", total_bonus)
				raylib.DrawTextEx(constants.game_fonts.semibold, bonus_str, {bonus_x, bonus_y}, font_size, 0, raylib.Color{80, 220, 80, 255})
			}
		}

		draw_icon_stat(constants.game_icons.speed,  fmt.tprintf("%.2fs", tower.cooldown), content_x, current_y + 1 * line_height, icon_size, font_size)
		draw_icon_stat(constants.game_icons.crit,   fmt.tprintf("%.0f%%", crit_pct),      content_x, current_y + 2 * line_height, icon_size, font_size)
		current_y += stats_height + spacing
	}

	// Upgrade button — ENHANCE se limita a nivel 5; resto se limita a nivel 20
	base_level      := tower.level - tower.enhance_bonus - tower.cryptobro_bonus
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
// Muestra los relictos activos (stacks > 0) en la esquina inferior izquierda.
// Cada relicto aparece como un slot cuadrado con icono y badge "x N".
render_relic_tray :: proc(app: ^entities.App_State) {
	ICON_SIZE    : f32 = 40  // tamaño del icono
	BADGE_SIZE   : f32 = 16  // tamaño de fuente del número de stacks
	SLOT_GAP     : f32 = 8   // separación entre iconos (vertical y horizontal)
	MAX_PER_COL  : i32 = 5   // máximo de relictos por columna antes de abrir una nueva

	screen_h := f32(raylib.GetScreenHeight())
	base_x   := f32(constants.UI_MARGIN_X)

	// Ancla inferior: justo encima de la zona de cartas
	anchor_y := screen_h - CARD_H - CARD_BOTTOM_MARGIN - SLOT_GAP

	slot_idx := i32(0)
	for spec in entities.RELIC_SPECS {
		kind   := spec.kind
		stacks := entities.relic_stacks(&app.sim, kind)
		if stacks == 0 do continue

		col := slot_idx / MAX_PER_COL  // columna (0 = izquierda, crece a la derecha)
		row := slot_idx % MAX_PER_COL  // fila dentro de la columna (0 = abajo)

		sx := base_x + f32(col) * (ICON_SIZE + SLOT_GAP)
		sy := anchor_y - f32(row) * (ICON_SIZE + SLOT_GAP) - ICON_SIZE

		// Icono sin fondo ni contorno
		icon := entities.relic_icon(kind)
		if icon.id != 0 {
			src := raylib.Rectangle{0, 0, f32(icon.width), f32(icon.height)}
			dst := raylib.Rectangle{sx, sy, ICON_SIZE, ICON_SIZE}
			raylib.DrawTexturePro(icon, src, dst, {0, 0}, 0, raylib.WHITE)

			// Flash blanco — alpha proporcional al tiempo restante
			flash_t := app.sim.relic_flash_timers[kind]
			if flash_t > 0 {
				alpha := u8(255.0 * (flash_t / constants.RELIC_FLASH_DURATION))
				raylib.DrawRectangleRounded(
					raylib.Rectangle{sx, sy, ICON_SIZE, ICON_SIZE},
					0.2, 4,
					raylib.Color{255, 255, 255, alpha},
				)
			}
		}

		// Número de stacks — solo si hay más de 1, sin "x"
		if stacks > 1 {
			badge   := fmt.ctprintf("%d", stacks)
			badge_w := raylib.MeasureTextEx(constants.game_fonts.semibold, badge, BADGE_SIZE, 0).x
			badge_x := sx + ICON_SIZE - badge_w
			badge_y := sy + ICON_SIZE - BADGE_SIZE
			draw_text_with_outline(badge, {badge_x, badge_y}, BADGE_SIZE, 0,
				raylib.Color{255, 220, 80, 255}, raylib.Color{0, 0, 0, 220}, 1,
				constants.game_fonts.semibold)
		}

		// Tooltip al hacer hover — mismo contenido que la carta en mano/tienda
		render_card_tooltip(app, entities.Card{kind = kind}, raylib.Rectangle{sx, sy, ICON_SIZE, ICON_SIZE})

		slot_idx += 1
	}
}
apply_relic_card :: proc(app: ^entities.App_State, kind: entities.Card_Kind) {
	entities.relic_apply(&app.sim, kind)
	stacks := entities.relic_stacks(&app.sim, kind)
	spec, ok := entities.relic_spec_for(kind)
	if ok {
		entities.add_toast(app, spec.toast_format(stacks), .SUCCESS)
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers de sinergia para el shop — devuelven si una carta del shop combina con
// lo que el jugador ya tiene (relictos acumulados o composición del mazo/torres).
// ─────────────────────────────────────────────────────────────────────────────

shop_player_has_tower_type :: proc(sim: ^entities.Simulation, t: constants.Tower_Type) -> bool {
	for tower in sim.towers {
		if tower.type == t { return true }
	}
	for card in sim.hand {
		if card.kind == .TOWER && card.tower_type == t { return true }
	}
	for card in sim.deck {
		if card.kind == .TOWER && card.tower_type == t { return true }
	}
	return false
}

shop_player_has_n_same_tower_placed :: proc(sim: ^entities.Simulation, n: int) -> bool {
	counts: [constants.Tower_Type]int
	for tower in sim.towers {
		counts[tower.type] += 1
	}
	for t in constants.Tower_Type {
		if counts[t] >= n { return true }
	}
	return false
}

shop_player_has_n_same_tower_type_placed :: proc(sim: ^entities.Simulation, t: constants.Tower_Type, n: int) -> bool {
	count := 0
	for tower in sim.towers {
		if tower.type == t { count += 1 }
	}
	return count >= n
}

shop_player_has_any_tower_card :: proc(sim: ^entities.Simulation) -> bool {
	for card in sim.hand {
		if card.kind == .TOWER { return true }
	}
	for card in sim.deck {
		if card.kind == .TOWER { return true }
	}
	return false
}

// Devuelve true si comprar la carta combina con el estado actual del jugador.
// Se usa para dibujar un badge de sinergia en el shop.
shop_card_has_synergy :: proc(sim: ^entities.Simulation, card: entities.Card) -> bool {
	if entities.is_relic(card.kind) {
		#partial switch card.kind {
		case .FROZEN_AMP:
			return shop_player_has_tower_type(sim, .ICE)
		case .WARMED_UP:
			return shop_player_has_tower_type(sim, .LASER) || shop_player_has_tower_type(sim, .MORTAR)
		case .FORMATION:
			return shop_player_has_n_same_tower_placed(sim, 2)
		case .CRYPTOBRO:
			return shop_player_has_tower_type(sim, .SNIPER) || shop_player_has_tower_type(sim, .MORTAR)
		case .BLOODLUST:
			return shop_player_has_tower_type(sim, .ARCHER) ||
			       shop_player_has_tower_type(sim, .MISSILE) ||
			       shop_player_has_tower_type(sim, .TESLA)
		case .VETERAN:
			return shop_player_has_any_tower_card(sim)
		case .AUTO_UPGRADE, .DIVIDEND, .INTEREST_BOOST, .MEMENTO, .RECYCLER:
			return len(sim.towers) >= 2
		case .FLAWLESS:
			return len(sim.towers) >= 3
		case .LOOT, .STEAL:
			return sim.relic_stacks[card.kind] > 0
		}
		return false
	}
	if card.kind == .TOWER {
		if sim.relic_stacks[.FORMATION] > 0 &&
		   shop_player_has_n_same_tower_type_placed(sim, card.tower_type, 2) {
			return true
		}
		if card.tower_type == .ICE && sim.relic_stacks[.FROZEN_AMP] > 0 {
			return true
		}
		if (card.tower_type == .LASER || card.tower_type == .MORTAR) &&
		   sim.relic_stacks[.WARMED_UP] > 0 {
			return true
		}
		if (card.tower_type == .SNIPER || card.tower_type == .MORTAR) &&
		   sim.relic_stacks[.CRYPTOBRO] > 0 {
			return true
		}
		if (card.tower_type == .ARCHER || card.tower_type == .MISSILE ||
		    card.tower_type == .TESLA) && sim.relic_stacks[.BLOODLUST] > 0 {
			return true
		}
	}
	return false
}

// Precio en el shop con el modificador del bioma aplicado (price_mult + uncommon_discount).
shop_price_for_card :: proc(app: ^entities.App_State, card: entities.Card) -> i32 {
	base: i32
	if entities.is_relic(card.kind) {
		base = entities.card_shop_price(card)
	} else {
		base = entities.card_cost(card)
	}
	biome_mod := constants.BIOME_SHOP_MODS[app.editor.game_map.biome]
	price := f32(base) * biome_mod.price_mult
	if entities.card_rarity(card) == .UNCOMMON && biome_mod.uncommon_discount > 0 {
		price *= 1.0 - biome_mod.uncommon_discount
	}
	return i32(price)
}

// Costo del próximo reroll según el bioma y rerolls_this_shop.
shop_next_reroll_cost :: proc(app: ^entities.App_State) -> i32 {
	biome_mod := constants.BIOME_SHOP_MODS[app.editor.game_map.biome]
	if biome_mod.free_reroll { return 0 }
	idx := int(app.sim.rerolls_this_shop)
	if idx >= len(constants.SHOP_REROLL_COSTS) {
		idx = len(constants.SHOP_REROLL_COSTS) - 1
	}
	return constants.SHOP_REROLL_COSTS[idx]
}

// Renderiza el overlay de selección de carta (tienda entre oleadas).
// El shop permanece abierto mientras el jugador compra cartas.
// Click izquierdo sobre una carta la compra directamente.
// Click derecho sobre una carta la bloquea (sobrevive al reroll).
// El shop se cierra solo con el botón Skip (o cuando se abre la siguiente oleada).
render_card_selection_overlay :: proc(app: ^entities.App_State) {
	// Limpiamos ui_modal_blocks: la UI de juego subyacente ya fue procesada y
	// correctamente bloqueada; ahora solo los botones del shop deben recibir clicks.
	clear(&ui_modal_blocks)

	sim := &app.sim
	screen_w := f32(raylib.GetScreenWidth())
	screen_h := f32(raylib.GetScreenHeight())

	// Fondo oscuro modal
	raylib.DrawRectangle(0, 0, i32(screen_w), i32(screen_h), raylib.Color{0, 0, 0, 160})

	// Cantidad de slots activos según el bioma (clamped a [1, MAX_SHOP_SLOTS]).
	n_cards := int(sim.shop_slot_count)
	if n_cards <= 0 { n_cards = int(constants.SHOP_BASE_SLOTS) }
	if n_cards > int(constants.MAX_SHOP_SLOTS) { n_cards = int(constants.MAX_SHOP_SLOTS) }

	// Posición del panel — se centra sobre la cantidad real de slots
	panel_w  := f32(n_cards) * CARD_W + f32(n_cards + 1) * CARD_GAP
	panel_x  := (screen_w - panel_w) / 2
	panel_y  := screen_h / 2 - CARD_H / 2 - 20

	biome     := app.editor.game_map.biome
	biome_mod := constants.BIOME_SHOP_MODS[biome]

	// Header de bioma — describe el efecto del bioma sobre el shop
	biome_label   := constants.get_text(biome_mod.label_key)
	biome_label_sz : f32 = 13
	biome_label_w  := raylib.MeasureTextEx(constants.game_fonts.regular,
		strings.clone_to_cstring(biome_label, context.temp_allocator), biome_label_sz, 0).x
	raylib.DrawTextEx(constants.game_fonts.regular,
		strings.clone_to_cstring(biome_label, context.temp_allocator),
		{screen_w / 2 - biome_label_w / 2, panel_y - 70},
		biome_label_sz, 0, raylib.Color{200, 200, 220, 240})

	// Título
	title   := constants.get_text("DECK_CHOOSE_CARD")
	title_sz : f32 = 22
	title_w := raylib.MeasureTextEx(constants.game_fonts.bold,
		strings.clone_to_cstring(title, context.temp_allocator), title_sz, 0).x
	raylib.DrawTextEx(constants.game_fonts.bold,
		strings.clone_to_cstring(title, context.temp_allocator),
		{screen_w / 2 - title_w / 2, panel_y - 44},
		title_sz, 0, raylib.WHITE)

	mouse  := raylib.GetMousePosition()
	HOVER_LIFT :: f32(8)

	for i in 0 ..< n_cards {
		card     := sim.card_selection_choices[i]
		cx       := panel_x + CARD_GAP + f32(i) * (CARD_W + CARD_GAP)
		cy       := panel_y
		bought   := sim.card_selection_bought[i]
		locked   := sim.card_selection_locked[i]
		is_relic := entities.is_relic(card.kind)
		price    := shop_price_for_card(app, card)
		can_buy  := !bought && price <= sim.money
		synergy  := !bought && shop_card_has_synergy(sim, card)

		card_rect := raylib.Rectangle{cx, cy, CARD_W, CARD_H}
		hovered   := !bought && raylib.CheckCollisionPointRec(mouse, card_rect)
		lift      := hovered ? HOVER_LIFT : f32(0)
		draw_cy   := cy - lift

		// Fondo según estado
		bg := raylib.Color{}
		switch {
		case bought:     bg = raylib.Color{50, 50, 50, 200}
		case is_relic:   bg = rarity_card_bg(entities.card_rarity(card))
		}

		// show_price = false: dibujamos el precio nosotros con el modificador del bioma
		render_card(app, card, cx, draw_cy, false, can_buy, bg, false)

		// Precio con modificador de bioma — sobreescribe el que dibujaría render_card
		cost_str  := fmt.ctprintf("$%d", price)
		cost_size : f32 = 15
		cost_w    := raylib.MeasureTextEx(constants.game_fonts.semibold, cost_str, cost_size, 0).x
		cost_color := can_buy ? raylib.Color{80, 220, 100, 255} : raylib.Color{200, 60, 60, 255}
		raylib.DrawTextEx(
			constants.game_fonts.bold, cost_str,
			{cx + (CARD_W - cost_w) / 2, draw_cy + 102},
			cost_size, 0, cost_color,
		)

		lifted_rect := raylib.Rectangle{cx, draw_cy, CARD_W, CARD_H}
		render_card_tooltip(app, card, lifted_rect)

		// Indicador de lock — borde dorado constante + label "[L]" esquina superior izq
		if locked {
			raylib.DrawRectangleRoundedLinesEx(
				{cx, draw_cy, CARD_W, CARD_H},
				constants.UI_ROUNDNESS, constants.UI_SEGMENTS, 2.5,
				raylib.Color{220, 180, 60, 240},
			)
			draw_text_with_outline(
				fmt.ctprintf("[L]"), {cx + 6, draw_cy + 6}, 12, 0,
				raylib.Color{240, 200, 60, 255}, raylib.Color{0, 0, 0, 200}, 1,
				constants.game_fonts.bold,
			)
		}

		// Indicador de sinergia — símbolo "~" en esquina superior derecha
		if synergy {
			draw_text_with_outline(
				fmt.ctprintf("~"), {cx + CARD_W - 18, draw_cy + 6}, 14, 0,
				raylib.Color{120, 230, 255, 255}, raylib.Color{0, 0, 0, 200}, 1,
				constants.game_fonts.bold,
			)
		}

		// Borde dorado al hacer hover sobre carta comprable (sin lock, que ya tiene su borde)
		if hovered && can_buy && !locked {
			raylib.DrawRectangleRoundedLinesEx(
				{cx, draw_cy, CARD_W, CARD_H},
				constants.UI_ROUNDNESS, constants.UI_SEGMENTS, 2.5,
				raylib.Color{255, 215, 0, 220},
			)
			append(&ui_click_blocks, card_rect)
		}

		// Click izquierdo: comprar
		if hovered && can_buy && raylib.IsMouseButtonPressed(.LEFT) {
			sim.money -= price
			sim.card_selection_bought[i] = true
			sim.shop_purchases_this_visit += 1
			sim.skip_streak_count = 0  // comprar rompe el streak
			if is_relic {
				apply_relic_card(app, card.kind)
			} else {
				entities.card_add_to_hand(&app.sim, card)
			}
			play_sound(.CONFIRMATION, .UI)
		}

		// Click derecho: toggle lock (también si bought — permite "marcar" cartas)
		if hovered && raylib.IsMouseButtonPressed(.RIGHT) {
			sim.card_selection_locked[i] = !sim.card_selection_locked[i]
			play_sound(.CLICK, .UI)
		}
	}

	// Botones Skip y Reroll
	BTN_W      : f32 = 150
	BTN_H      : f32 = 34
	BTN_GAP    : f32 = 12
	total_btn_w := BTN_W * 2 + BTN_GAP
	skip_x     := screen_w / 2 - total_btn_w / 2
	reroll_x   := skip_x + BTN_W + BTN_GAP
	btn_y      := panel_y + CARD_H + 36

	reroll_cost := shop_next_reroll_cost(app)
	can_reroll  := sim.money >= reroll_cost

	// Skip: si el jugador no compró nada, gana bonus de oro escalado por skip_streak
	skip_label: string
	if sim.shop_purchases_this_visit == 0 {
		next_bonus := (sim.skip_streak_count + 1) * constants.SHOP_SKIP_BONUS_PER_SKIP
		if next_bonus > constants.SHOP_SKIP_BONUS_CAP { next_bonus = constants.SHOP_SKIP_BONUS_CAP }
		skip_label = fmt.tprintf("%s (+$%d)", constants.get_text("SHOP_SKIP"), next_bonus)
	} else {
		skip_label = constants.get_text("SHOP_SKIP")
	}

	if render_button(skip_label, {skip_x, btn_y, BTN_W, BTN_H}, 1, true) {
		shop_perform_skip(app)
	}

	// Reroll: costo progresivo. Si el bioma da free_reroll, label distinto.
	reroll_label: string
	if biome_mod.free_reroll {
		reroll_label = fmt.tprintf("%s (gratis)", constants.get_text("DECK_REROLL_BUTTON"))
	} else if reroll_cost == 0 {
		reroll_label = fmt.tprintf("%s (1° gratis)", constants.get_text("DECK_REROLL_BUTTON"))
	} else {
		reroll_label = fmt.tprintf("%s $%d", constants.get_text("DECK_REROLL_BUTTON"), reroll_cost)
	}

	if render_button(
		reroll_label,
		{reroll_x, btn_y, BTN_W, BTN_H},
		1, can_reroll,
		constants.UI_TEXT_COLOR,
		can_reroll ? constants.UI_BUTTON_ACTION_COLOR : constants.COLOR_NONE,
		can_reroll ? constants.UI_BUTTON_ACTION_HOVER : constants.COLOR_NONE,
		can_reroll ? constants.UI_BUTTON_ACTION_PRESS : constants.COLOR_NONE,
	) {
		if can_reroll {
			sim.money -= reroll_cost
			sim.rerolls_this_shop += 1
			generate_card_selection(app)
			play_sound(.CLICK, .UI)
		}
	}

	// ── Panel de refund de stacks de relictos ─────────────────────────────────
	// Muestra una fila debajo de los botones con un icono por relicto poseído.
	// Click sobre el icono → -1 stack, +SHOP_RELIC_REFUND_PRICE oro.
	render_relic_refund_row(app, screen_w, btn_y + BTN_H + 24)
}

// Fila de iconos pequeños — un slot por relicto con stacks > 0.
// Click izquierdo: refund de 1 stack a cambio de SHOP_RELIC_REFUND_PRICE oro.
render_relic_refund_row :: proc(app: ^entities.App_State, screen_w, y_pos: f32) {
	sim := &app.sim

	// Cuenta relictos con stacks
	owned_kinds: [32]entities.Card_Kind
	n_owned := 0
	for kind in entities.Card_Kind {
		if !entities.is_relic(kind) { continue }
		if sim.relic_stacks[kind] <= 0 { continue }
		if n_owned < 32 {
			owned_kinds[n_owned] = kind
			n_owned += 1
		}
	}
	if n_owned == 0 { return }

	ICON_SIZE :: f32(40)
	ICON_GAP  :: f32(8)
	row_w     := f32(n_owned) * ICON_SIZE + f32(n_owned - 1) * ICON_GAP
	start_x   := (screen_w - row_w) / 2

	// Label arriba de la fila
	label   := fmt.tprintf("%s ($%d/stack)", constants.get_text("SHOP_RELIC_REFUND"), constants.SHOP_RELIC_REFUND_PRICE)
	label_sz : f32 = 12
	label_w := raylib.MeasureTextEx(constants.game_fonts.regular,
		strings.clone_to_cstring(label, context.temp_allocator), label_sz, 0).x
	raylib.DrawTextEx(constants.game_fonts.regular,
		strings.clone_to_cstring(label, context.temp_allocator),
		{screen_w / 2 - label_w / 2, y_pos - 16},
		label_sz, 0, raylib.Color{200, 200, 220, 220})

	mouse := raylib.GetMousePosition()

	for i in 0 ..< n_owned {
		kind  := owned_kinds[i]
		x     := start_x + f32(i) * (ICON_SIZE + ICON_GAP)
		rect  := raylib.Rectangle{x, y_pos, ICON_SIZE, ICON_SIZE}
		hover := raylib.CheckCollisionPointRec(mouse, rect)

		// Fondo
		bg := raylib.Color{30, 30, 40, 200}
		if hover { bg = raylib.Color{60, 60, 80, 230} }
		raylib.DrawRectangleRounded(rect, 0.2, 6, bg)
		raylib.DrawRectangleRoundedLinesEx(rect, 0.2, 6, 1.5, raylib.Color{120, 120, 140, 200})

		// Icono — usar la textura cargada del relicto
		tex := entities.relic_icon(kind)
		if tex.id != 0 {
			src := raylib.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
			dst := raylib.Rectangle{x + 4, y_pos + 4, ICON_SIZE - 8, ICON_SIZE - 8}
			raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
		}

		// Stack count badge
		stacks_str := fmt.ctprintf("%d", sim.relic_stacks[kind])
		draw_text_with_outline(
			stacks_str, {x + ICON_SIZE - 14, y_pos + ICON_SIZE - 14}, 11, 0,
			raylib.WHITE, raylib.Color{0, 0, 0, 220}, 1, constants.game_fonts.bold,
		)

		// Tooltip al hover + click para refund
		if hover {
			append(&ui_click_blocks, rect)
			render_card_tooltip(app, entities.Card{kind = kind}, rect)
			if raylib.IsMouseButtonPressed(.LEFT) {
				sim.relic_stacks[kind] -= 1
				entities.app_add_money(app, constants.SHOP_RELIC_REFUND_PRICE)
				entities.add_toast(app,
					fmt.tprintf("+$%d refund", constants.SHOP_RELIC_REFUND_PRICE),
					.INFO)
				play_sound(.CONFIRMATION, .UI)
			}
		}
	}
}

// Renderiza la mano del jugador en la zona inferior.
// Las cartas están plegadas (solapadas). Pasar el mouse sobre una carta
// separa el mazo en dos mitades para revelarla completamente.
render_card_hand :: proc(app: ^entities.App_State) {
	n := len(app.sim.hand)
	if n == 0 { return }

	screen_w := f32(raylib.GetScreenWidth())
	screen_h := f32(raylib.GetScreenHeight())

	// Paso y solapamiento
	max_w  := screen_w * 0.60
	step   := min(CARD_W * 0.70, (max_w - CARD_W) / max(f32(n - 1), 1))
	total_w := CARD_W + step * f32(n - 1)
	start_x := (screen_w - total_w) / 2
	card_y  := screen_h - CARD_H - CARD_BOTTOM_MARGIN
	overlap := CARD_W - step

	mouse := raylib.GetMousePosition()

	// Detectar carta bajo el cursor (última = la más encima)
	hovered_idx := -1
	if !ui_is_modal_blocked(i32(mouse.x), i32(mouse.y)) {
		for i in 0 ..< n {
			cx := start_x + f32(i) * step
			if raylib.CheckCollisionPointRec(mouse, raylib.Rectangle{cx, card_y, CARD_W, CARD_H}) {
				hovered_idx = i
			}
		}
	}

	// Posición X con efecto split: cartas a la izquierda de la hovereada
	// se alejan -overlap, cartas a la derecha +overlap.
	card_draw_x := proc(i, hovered: int, sx, stp, ovlp: f32) -> f32 {
		base := sx + f32(i) * stp
		if hovered < 0 || i == hovered { return base }
		if i < hovered { return base - ovlp }
		return base + ovlp
	}

	relic_activated := false

	// ── Pasada 1: todas las cartas excepto la hovereada ──────────────────────
	for i in 0 ..< n {
		if i == hovered_idx { continue }
		card    := app.sim.hand[i]
		cx      := card_draw_x(i, hovered_idx, start_x, step, overlap)
		render_card(app, card, cx, card_y, app.sim.selected_card_idx == i, true)
		append(&ui_click_blocks, raylib.Rectangle{cx, card_y, CARD_W, CARD_H})
	}

	// ── Pasada 2: carta hovereada encima (levantada) ─────────────────────────
	if hovered_idx >= 0 {
		HOVER_LIFT :: f32(20)
		i      := hovered_idx
		card   := app.sim.hand[i]
		cx     := card_draw_x(i, hovered_idx, start_x, step, overlap)
		cy     := card_y - HOVER_LIFT
		render_card(app, card, cx, cy, app.sim.selected_card_idx == i, true)
		card_rect := raylib.Rectangle{cx, cy, CARD_W, CARD_H}
		append(&ui_click_blocks, card_rect)
		render_card_tooltip(app, card, card_rect)

		// Clic para seleccionar / activar relicto
		if raylib.IsMouseButtonPressed(.LEFT) {
			if entities.is_relic(card.kind) && !relic_activated {
				relic_activated = true
				apply_relic_card(app, card.kind)
				entities.card_play(&app.sim, i)
				app.sim.selected_build_tower = .EMPTY
				app.sim.selected_card_idx    = -1
			} else if !entities.is_relic(card.kind) {
				tile := entities.card_to_tile(card)
				app.sim.selected_build_tower = tile
				app.sim.selected_card_idx    = i
				play_sound(.SELECT, .UI)
			}
		}

		// Botón de venta — precio según rareza para relictos, fijo para el resto
		sell_price := entities.card_sell_price(card)
		sell_label := fmt.tprintf("%s $%d", constants.get_text("CARD_SELL_BUTTON"), sell_price)
		sell_rect  := raylib.Rectangle{cx, cy + CARD_H + 4, CARD_W, 24}
		if render_button(sell_label, sell_rect, 1, true) {
			entities.card_play(&app.sim, i)
			app.sim.money += sell_price
			if app.sim.selected_card_idx == i {
				app.sim.selected_build_tower = .EMPTY
				app.sim.selected_card_idx    = -1
			}
			play_sound(.CONFIRMATION, .UI)
		}
	}
}

// ─── RUN COMPLETE SCREEN ────────────────────────────────────────────────────

render_run_complete_ui :: proc(app: ^entities.App_State) {
	screen_width  := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	render_background()

	font_size  := f32(constants.UI_BUTTON_FONT_SIZE)
	small_size := f32(13)
	btn_height := i32(constants.UI_BUTTON_HEIGHT)
	spacing    := i32(constants.UI_PANEL_MARGIN)

	CRISTAL_COLOR :: raylib.Color{100, 200, 255, 255}
	DIM_COLOR     :: raylib.Color{140, 140, 140, 255}

	// Title
	title_key   := "RUN_VICTORY_TITLE" if app.sim.is_victory else "RUN_DEFEAT_TITLE"
	title_color := raylib.Color{80, 220, 80, 255} if app.sim.is_victory else raylib.Color{220, 80, 80, 255}
	title       := constants.get_text(title_key)
	title_cstr  := strings.clone_to_cstring(title, context.temp_allocator)
	title_size  := f32(36)
	title_w     := raylib.MeasureTextEx(constants.game_fonts.bold, title_cstr, title_size, 0).x
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		title_cstr,
		{f32(screen_width) / 2 - title_w / 2, f32(screen_height) * 0.05},
		title_size, 0, title_color,
	)

	// Pre-compute cristal components from sim state (still valid before simulation_reset)
	lives_at_end := app.sim.health if app.sim.is_victory else 0
	c_waves := entities.meta_cristales_from_waves(app.sim.wave_number)
	c_kills := entities.meta_cristales_from_kills(app.sim.enemies_killed)
	c_lives := entities.meta_cristales_from_lives(lives_at_end)

	// ── Stats panel ──────────────────────────────────────────────────────────
	// Layout: two columns.
	//   Left  (60%): stat label
	//   Right (40%): value  |  +XC badge (right-aligned)
	// All text at small_size to avoid crowding. Separator + total row included in panel_h.

	panel_w := i32(f32(screen_width) * 0.55)
	if panel_w > 460 { panel_w = 460 }
	if panel_w < 320 { panel_w = 320 }
	panel_x := f32(screen_width) / 2 - f32(panel_w) / 2
	panel_y := f32(screen_height) * 0.18

	Contrib_Row :: struct {
		label: string,
		value: string,
		c:     i32   // -1 = no badge
	}
	total_secs := i32(app.sim.play_time)
	rows := []Contrib_Row{
		{constants.get_text("GAME_OVER_WAVES_SURVIVED"), fmt.tprintf("%d / %d", app.sim.wave_number, constants.RUN_MAX_WAVES), c_waves},
		{constants.get_text("GAME_OVER_TIME"),           fmt.tprintf("%d:%02d", total_secs / 60, total_secs % 60),             -1},
		{constants.get_text("GAME_OVER_ENEMIES_KILLED"), fmt.tprintf("%d", app.sim.enemies_killed),                            c_kills},
		{constants.get_text("RUN_LIVES_REMAINING"),      fmt.tprintf("%d", lives_at_end),                                     c_lives},
	}

	row_h := i32(small_size) + 8
	// Panel height: data rows + separator line + total row, all with spacing between
	num_rows  := i32(len(rows))
	inner_h   := num_rows * (row_h + spacing) + spacing + row_h  // rows + sep gap + total row
	panel_h   := f32(inner_h + constants.UI_PANEL_PADDING * 2)
	content   := render_panel(raylib.Rectangle{panel_x, panel_y, f32(panel_w), panel_h})

	cx     := i32(content.x)
	cw     := i32(content.width)
	sy     := i32(content.y)
	col_w  := i32(f32(cw) * 0.55)  // label column width

	for row in rows {
		label_cstr := strings.clone_to_cstring(row.label, context.temp_allocator)
		value_cstr := strings.clone_to_cstring(row.value, context.temp_allocator)

		// Label — clipped to left column
		raylib.DrawTextEx(constants.game_fonts.regular, label_cstr,
			{f32(cx), f32(sy)}, small_size, 0, constants.UI_PANEL_TEXT_COLOR)

		// Right column: value flush-right, badge flush-far-right
		right_x := cx + col_w  // start of right column

		if row.c >= 0 {
			badge     := fmt.tprintf("+%dC", row.c)
			badge_c   := strings.clone_to_cstring(badge, context.temp_allocator)
			badge_w   := raylib.MeasureTextEx(constants.game_fonts.semibold, badge_c, small_size, 0).x
			badge_col := CRISTAL_COLOR if row.c > 0 else DIM_COLOR
			raylib.DrawTextEx(constants.game_fonts.semibold, badge_c,
				{f32(cx + cw) - badge_w, f32(sy)}, small_size, 0, badge_col)

			val_w := raylib.MeasureTextEx(constants.game_fonts.semibold, value_cstr, small_size, 0).x
			raylib.DrawTextEx(constants.game_fonts.semibold, value_cstr,
				{f32(cx + cw) - badge_w - val_w - 10, f32(sy)}, small_size, 0, constants.UI_PANEL_TEXT_COLOR)
		} else {
			val_w := raylib.MeasureTextEx(constants.game_fonts.semibold, value_cstr, small_size, 0).x
			_ = right_x
			raylib.DrawTextEx(constants.game_fonts.semibold, value_cstr,
				{f32(cx + cw) - val_w, f32(sy)}, small_size, 0, constants.UI_PANEL_TEXT_COLOR)
		}

		sy += row_h + spacing
	}

	// Separator
	raylib.DrawLine(cx, sy, cx + cw, sy, raylib.Color{180, 180, 180, 100})
	sy += spacing

	// Total row
	total_lbl   := constants.get_text("RUN_TOTAL_CRISTALES")
	total_lbl_c := strings.clone_to_cstring(total_lbl, context.temp_allocator)
	total_val   := fmt.tprintf("+%d C", app.run_cristales)
	total_val_c := strings.clone_to_cstring(total_val, context.temp_allocator)
	total_val_w := raylib.MeasureTextEx(constants.game_fonts.bold, total_val_c, font_size, 0).x
	raylib.DrawTextEx(constants.game_fonts.semibold, total_lbl_c,
		{f32(cx), f32(sy)}, font_size, 0, constants.UI_PANEL_TEXT_COLOR)
	raylib.DrawTextEx(constants.game_fonts.bold, total_val_c,
		{f32(cx + cw) - total_val_w, f32(sy)}, font_size, 0, CRISTAL_COLOR)

	// Acumulado (debajo del panel)
	acum_y   := panel_y + panel_h + f32(spacing) * 2
	acum_txt := fmt.tprintf("%s: %d C", constants.get_text("RUN_ACUM_CRISTALES"), app.meta.cristales)
	acum_c   := strings.clone_to_cstring(acum_txt, context.temp_allocator)
	acum_w   := raylib.MeasureTextEx(constants.game_fonts.regular, acum_c, font_size, 0).x
	raylib.DrawTextEx(constants.game_fonts.regular, acum_c,
		{f32(screen_width) / 2 - acum_w / 2, acum_y}, font_size, 0, raylib.Color{180, 220, 255, 255})

	// Buttons — en derrota hay un tercer botón: Reintentar
	btn_w  := i32(constants.UI_BUTTON_WIDTH) * 2
	gap    := i32(10)
	btns_y := i32(acum_y) + i32(font_size) + spacing * 2

	if !app.sim.is_victory {
		// 3 botones: Reintentar | Mejoras | Menú
		total_w_btns := btn_w * 3 + gap * 2
		btn_left_x   := screen_width / 2 - total_w_btns / 2

		if render_button(
			constants.get_text("RUN_BUTTON_RETRY"),
			{f32(btn_left_x), f32(btns_y), f32(btn_w), f32(btn_height)},
		) {
			// Recargar el mismo mapa y reiniciar la simulación
			map_name := app.editor.current_map_name
			simulation_reset(app)
			entities.map_load(&app.editor.game_map, map_name)
			entities.app_set_state(app, .PLAYING)
		}
		if render_button(
			constants.get_text("RUN_BUTTON_PROGRESSION"),
			{f32(btn_left_x + btn_w + gap), f32(btns_y), f32(btn_w), f32(btn_height)},
		) {
			simulation_reset(app)
			entities.app_set_state(app, .PROGRESSION)
		}
		if render_button(
			constants.get_text("GAME_OVER_BUTTON_MENU"),
			{f32(btn_left_x + btn_w * 2 + gap * 2), f32(btns_y), f32(btn_w), f32(btn_height)},
		) {
			simulation_reset(app)
			entities.app_set_state(app, .MENU)
		}
	} else {
		// 2 botones: Mejoras | Menú
		total_w_btns := btn_w * 2 + gap
		btn_left_x   := screen_width / 2 - total_w_btns / 2

		if render_button(
			constants.get_text("RUN_BUTTON_PROGRESSION"),
			{f32(btn_left_x), f32(btns_y), f32(btn_w), f32(btn_height)},
		) {
			simulation_reset(app)
			entities.app_set_state(app, .PROGRESSION)
		}
		if render_button(
			constants.get_text("GAME_OVER_BUTTON_MENU"),
			{f32(btn_left_x + btn_w + gap), f32(btns_y), f32(btn_w), f32(btn_height)},
		) {
			simulation_reset(app)
			entities.app_set_state(app, .MENU)
		}
	}
}

// ─── PROGRESSION SCREEN ─────────────────────────────────────────────────────

render_progression_ui :: proc(app: ^entities.App_State) {
	screen_width  := raylib.GetScreenWidth()
	screen_height := raylib.GetScreenHeight()

	render_background()

	font_size  := f32(constants.UI_BUTTON_FONT_SIZE)
	small_size := f32(12)
	btn_height := i32(constants.UI_BUTTON_HEIGHT)
	spacing    := i32(constants.UI_PANEL_MARGIN)

	// Title
	title := constants.get_text("PROGRESSION_TITLE")
	title_cstr := strings.clone_to_cstring(title, context.temp_allocator)
	title_size := f32(30)
	title_w := raylib.MeasureTextEx(constants.game_fonts.bold, title_cstr, title_size, 0).x
	raylib.DrawTextEx(
		constants.game_fonts.bold,
		title_cstr,
		{f32(screen_width) / 2 - title_w / 2, f32(spacing) * 2},
		title_size,
		0,
		raylib.WHITE,
	)

	// Cristales display
	cristal_txt := fmt.tprintf("%s: %d", constants.get_text("RUN_TOTAL_CRISTALES"), app.meta.cristales)
	cristal_cstr := strings.clone_to_cstring(cristal_txt, context.temp_allocator)
	cristal_w := raylib.MeasureTextEx(constants.game_fonts.semibold, cristal_cstr, font_size, 0).x
	raylib.DrawTextEx(
		constants.game_fonts.semibold,
		cristal_cstr,
		{f32(screen_width) / 2 - cristal_w / 2, f32(spacing) * 2 + title_size + 4},
		font_size,
		0,
		raylib.Color{100, 200, 255, 255},
	)

	// Tower unlock row — cards drawn with render_card, unlock button below each
	lockable_towers := [6]constants.Tower_Type{.ICE, .ENHANCE, .MISSILE, .LASER, .TESLA, .MORTAR}
	tower_card_gap  := f32(16)
	tower_btn_h     := f32(constants.UI_BUTTON_HEIGHT)
	tower_total_w   := f32(len(lockable_towers)) * CARD_W + f32(len(lockable_towers) - 1) * tower_card_gap
	tower_cards_x   := f32(screen_width) / 2 - tower_total_w / 2
	tower_cards_y   := f32(spacing) * 2 + title_size + font_size + f32(spacing) * 2

	for i in 0 ..< len(lockable_towers) {
		t        := lockable_towers[i]
		cx       := tower_cards_x + f32(i) * (CARD_W + tower_card_gap)
		cy       := tower_cards_y
		unlocked := entities.meta_is_tower_unlocked(&app.meta, t)
		cost     := entities.meta_tower_unlock_cost(t)
		can_buy  := !unlocked && app.meta.cristales >= cost

		card := entities.Card{kind = .TOWER, tower_type = t}
		bg   := raylib.Color{50, 70, 50, 220} if unlocked else raylib.Color{}
		render_card(app, card, cx, cy, false, can_buy || unlocked, bg)
		render_card_tooltip(app, card, raylib.Rectangle{cx, cy, CARD_W, CARD_H})

		// Unlock button / unlocked badge below the card
		btn_y := cy + CARD_H + 6
		if unlocked {
			ok_cs := strings.clone_to_cstring(constants.get_text("PROGRESSION_UNLOCKED"), context.temp_allocator)
			ok_w  := raylib.MeasureTextEx(constants.game_fonts.semibold, ok_cs, small_size, 0).x
			raylib.DrawTextEx(constants.game_fonts.semibold, ok_cs,
				{cx + (CARD_W - ok_w) / 2, btn_y + (tower_btn_h - small_size) / 2},
				small_size, 0, raylib.Color{80, 210, 80, 255})
		} else {
			cost_str  := fmt.tprintf("%d C", cost)
			if render_button(cost_str, {cx, btn_y, CARD_W, tower_btn_h}, 1, can_buy) && can_buy {
				app.meta.cristales -= cost
				app.meta.unlocked_towers[int(t)] = true
				entities.meta_save(&app.meta)
				play_sound(.CONFIRMATION, .UI)
			}
		}
	}

	// Tier grid — 3 tiers, relics per tier
	tier_relics := [3][dynamic]entities.Card_Kind{
		{},  // Tier 1
		{},  // Tier 2
		{},  // Tier 3
	}
	for spec in entities.RELIC_SPECS {
		tier := entities.meta_relic_tier(spec.kind)
		if tier >= 1 && tier <= 3 {
			append(&tier_relics[int(tier) - 1], spec.kind)
		}
	}
	defer {
		delete(tier_relics[0])
		delete(tier_relics[1])
		delete(tier_relics[2])
	}

	tier_costs := [3]i32{5, 10, 20}
	tier_colors := [3]raylib.Color{
		{160, 160, 160, 255},  // grey (common)
		{ 50, 200, 100, 255},  // green (uncommon)
		{255, 160,  20, 255},  // gold (rare)
	}

	col_gap   := f32(40)                                  // gap between columns
	col_count := f32(3)
	panel_w   := i32(f32(screen_width) * 0.90)
	if panel_w > 780 { panel_w = 780 }
	panel_x   := f32(screen_width) / 2 - f32(panel_w) / 2
	content_y := tower_cards_y + CARD_H + tower_btn_h + f32(spacing) * 3

	icon_size := f32(36)
	row_gap   := f32(16)                                  // extra vertical space between relic rows
	cell_w    := (f32(panel_w) - col_gap * (col_count - 1)) / col_count
	cell_pad  := f32(spacing)

	for ti in 0 ..< 3 {
		relics := tier_relics[ti][:]
		col_x  := panel_x + f32(ti) * (cell_w + col_gap)
		row_y  := content_y

		for kind in relics {
			unlocked   := app.meta.unlocked_relics[kind]
			name       := entities.card_name(entities.Card{kind = kind})
			cost       := tier_costs[ti]
			icon_x     := col_x + cell_pad
			icon_tex   := entities.relic_icon(kind)

			// Icon
			if icon_tex.id > 0 {
				tint := raylib.WHITE if unlocked else raylib.Color{80, 80, 80, 200}
				raylib.DrawTextureEx(icon_tex, {icon_x, row_y}, 0, icon_size / f32(icon_tex.width), tint)
			} else {
				bg := tier_colors[ti] if unlocked else raylib.Color{60, 60, 60, 255}
				raylib.DrawRectangleRounded({icon_x, row_y, icon_size, icon_size}, 0.3, 8, bg)
			}
			render_card_tooltip(app, entities.Card{kind = kind}, raylib.Rectangle{icon_x, row_y, icon_size, icon_size})

			// Name
			name_cstr := strings.clone_to_cstring(name, context.temp_allocator)
			raylib.DrawTextEx(
				constants.game_fonts.regular,
				name_cstr,
				{icon_x + icon_size + 6, row_y + icon_size / 2 - small_size / 2},
				small_size, 0,
				raylib.WHITE if unlocked else raylib.Color{120, 120, 120, 255},
			)

			if !unlocked {
				can_afford := app.meta.cristales >= cost
				btn_label  := fmt.tprintf("%d C", cost)
				btn_w      := raylib.MeasureTextEx(constants.game_fonts.semibold, strings.clone_to_cstring(btn_label, context.temp_allocator), small_size, 0).x + 12
				btn_rect   := raylib.Rectangle{
					col_x + cell_w - btn_w - cell_pad,
					row_y + icon_size / 2 - f32(btn_height) / 2,
					btn_w,
					f32(btn_height),
				}
				if render_button(
					btn_label, btn_rect,
					1, can_afford,
					raylib.WHITE if can_afford else raylib.Color{100, 100, 100, 255},
					constants.UI_BUTTON_ACTION_COLOR if can_afford else raylib.Color{50, 50, 50, 255},
					constants.UI_BUTTON_ACTION_HOVER if can_afford else raylib.Color{50, 50, 50, 255},
					constants.UI_BUTTON_ACTION_PRESS if can_afford else raylib.Color{50, 50, 50, 255},
				) {
					if can_afford {
						app.meta.cristales -= cost
						app.meta.unlocked_relics[kind] = true
						entities.meta_save(&app.meta)
						play_sound(.CONFIRMATION, .UI)
					}
				}
			} else {
				badge_txt  := constants.get_text("PROGRESSION_UNLOCKED")
				badge_cstr := strings.clone_to_cstring(badge_txt, context.temp_allocator)
				badge_w    := raylib.MeasureTextEx(constants.game_fonts.regular, badge_cstr, small_size, 0).x
				badge_x    := col_x + cell_w - badge_w - cell_pad
				badge_y    := row_y + icon_size / 2 - small_size / 2
				raylib.DrawTextEx(constants.game_fonts.regular, badge_cstr, {badge_x, badge_y}, small_size, 0, raylib.Color{80, 220, 80, 255})
			}

			row_y += icon_size + row_gap
		}
	}

	// Back button
	back_y   := f32(screen_height) - f32(btn_height) - f32(spacing) * 2
	back_txt := constants.get_text("PROGRESSION_BACK")
	back_cstr := strings.clone_to_cstring(back_txt, context.temp_allocator)
	back_w   := raylib.MeasureTextEx(constants.game_fonts.semibold, back_cstr, font_size, 0).x + 20
	back_x   := f32(screen_width) / 2 - back_w / 2
	if render_button(
		back_txt,
		{back_x, back_y, back_w, f32(btn_height)},
	) {
		entities.app_set_state(app, .MENU)
	}
}

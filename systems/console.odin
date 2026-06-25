package systems

import "../entities"
import "../constants"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// Parsea un entero decimal con signo. Retorna (0, false) si la cadena es inválida.
_parse_i32 :: proc(s: string) -> (n: i32, ok: bool) {
	if len(s) == 0 { return 0, false }
	neg := false
	i   := 0
	if s[0] == '-' { neg = true; i = 1 }
	if i >= len(s) { return 0, false }
	for ; i < len(s); i += 1 {
		c := s[i]
		if c < '0' || c > '9' { return 0, false }
		n = n * 10 + i32(c - '0')
	}
	if neg { n = -n }
	return n, true
}

CONSOLE_H          :: f32(200)
CONSOLE_HEADER_H   :: f32(22)
CONSOLE_CMD_H      :: f32(24)
CONSOLE_SLIDE_SPD  :: f32(10.0)   // lerp speed (factor por segundo)
CONSOLE_LOG_FS     :: f32(12)
CONSOLE_LOG_LINE_H :: f32(16)
CONSOLE_PAD        :: f32(6)

// Actualiza la animación de slide. Llamar cada frame antes de render_console.
console_update :: proc(app: ^entities.App_State, dt: f32) {
	target := f32(1) if app.console.open else f32(0)
	t      := min(1.0, CONSOLE_SLIDE_SPD * dt)
	app.console.slide_t += (target - app.console.slide_t) * t
	if app.console.slide_t > 0.999 { app.console.slide_t = 1 }
	if app.console.slide_t < 0.001 { app.console.slide_t = 0 }
}

// Renderiza la consola. Siempre llamar — se oculta sola cuando slide_t == 0.
render_console :: proc(app: ^entities.App_State) {
	if app.console.slide_t <= 0 { return }

	sw := f32(rl.GetScreenWidth())

	// Panel desliza desde -CONSOLE_H hasta 0
	panel_y := -CONSOLE_H + app.console.slide_t * CONSOLE_H

	// ── Fondo principal ────────────────────────────────────────────────────────
	rl.DrawRectangleRec(
		{0, panel_y, sw, CONSOLE_H},
		rl.Color{15, 15, 25, 230},
	)

	// ── Header ─────────────────────────────────────────────────────────────────
	rl.DrawRectangleRec(
		{0, panel_y, sw, CONSOLE_HEADER_H},
		rl.Color{28, 28, 44, 255},
	)
	rl.DrawTextEx(
		constants.game_fonts.semibold,
		"CONSOLE  [Tab]",
		{CONSOLE_PAD, panel_y + 4},
		13, 0,
		rl.Color{140, 160, 220, 255},
	)
	// Hint de cierre a la derecha
	hint := "[Tab] cerrar"
	hint_cstr := strings.clone_to_cstring(hint, context.temp_allocator)
	hint_w := rl.MeasureTextEx(constants.game_fonts.regular, hint_cstr, 11, 0).x
	rl.DrawTextEx(
		constants.game_fonts.regular,
		hint_cstr,
		{sw - hint_w - CONSOLE_PAD, panel_y + 5},
		11, 0,
		rl.Color{80, 90, 120, 200},
	)

	// Línea divisora bajo el header
	rl.DrawLineV(
		{0, panel_y + CONSOLE_HEADER_H},
		{sw, panel_y + CONSOLE_HEADER_H},
		rl.Color{50, 55, 80, 255},
	)

	// ── Área de log ────────────────────────────────────────────────────────────
	log_y := panel_y + CONSOLE_HEADER_H
	log_h := CONSOLE_H - CONSOLE_HEADER_H - CONSOLE_CMD_H - 1

	n       := len(app.console.entries)
	total_h := f32(n) * CONSOLE_LOG_LINE_H + CONSOLE_PAD * 2
	max_scroll := max(f32(0), total_h - log_h)

	// Scroll con rueda del ratón (solo cuando la consola está abierta)
	if app.console.open && app.console.slide_t >= 0.95 {
		wheel := rl.GetMouseWheelMove()
		if wheel != 0 {
			app.console.scroll_y -= wheel * CONSOLE_LOG_LINE_H * 3
		}
	}
	app.console.scroll_y = clamp(app.console.scroll_y, 0, max_scroll)

	rl.BeginScissorMode(0, i32(log_y), i32(sw), i32(log_h))

	base_y := log_y + CONSOLE_PAD - app.console.scroll_y
	for entry, i in app.console.entries {
		ey := base_y + f32(i) * CONSOLE_LOG_LINE_H
		if ey + CONSOLE_LOG_LINE_H < log_y            { continue }
		if ey > log_y + log_h                         { break    }

		// Color y prefijo por tipo
		prefix_col : rl.Color
		prefix_str : string
		switch entry.type {
		case .SUCCESS:
			prefix_col = rl.Color{80,  200, 100, 255}
			prefix_str = "OK"
		case .INFO:
			prefix_col = rl.Color{140, 180, 255, 255}
			prefix_str = "--"
		case .WARNING:
			prefix_col = rl.Color{255, 200, 60,  255}
			prefix_str = "!!"
		case .ERROR:
			prefix_col = rl.Color{255,  80,  80, 255}
			prefix_str = "XX"
		}

		// Prefijo "[OK]" fijo en columna izquierda
		pfx_cstr := strings.clone_to_cstring(
			fmt.tprintf("[%s]", prefix_str),
			context.temp_allocator,
		)
		pfx_w := rl.MeasureTextEx(constants.game_fonts.regular, pfx_cstr, CONSOLE_LOG_FS, 0).x
		rl.DrawTextEx(
			constants.game_fonts.regular, pfx_cstr,
			{CONSOLE_PAD, ey},
			CONSOLE_LOG_FS, 0, prefix_col,
		)

		// Mensaje
		msg_cstr := strings.clone_to_cstring(entry.message, context.temp_allocator)
		rl.DrawTextEx(
			constants.game_fonts.regular, msg_cstr,
			{CONSOLE_PAD + pfx_w + 6, ey},
			CONSOLE_LOG_FS, 0, rl.Color{200, 205, 220, 255},
		)
	}

	rl.EndScissorMode()

	// Línea divisora sobre el campo de comandos
	div_y := panel_y + CONSOLE_H - CONSOLE_CMD_H
	rl.DrawLineV(
		{0, div_y},
		{sw, div_y},
		rl.Color{50, 55, 80, 255},
	)

	// ── Campo de comandos ──────────────────────────────────────────────────────
	rl.DrawRectangleRec(
		{0, div_y, sw, CONSOLE_CMD_H},
		rl.Color{20, 20, 35, 255},
	)

	// Prompt ">"
	PROMPT_W :: f32(16)
	rl.DrawTextEx(
		constants.game_fonts.semibold, ">",
		{CONSOLE_PAD, div_y + (CONSOLE_CMD_H - CONSOLE_LOG_FS) / 2},
		CONSOLE_LOG_FS, 0, rl.Color{100, 210, 110, 255},
	)

	// render_input para el campo de comandos
	cmd_rect := rl.Rectangle{
		CONSOLE_PAD + PROMPT_W, div_y + 2,
		sw - CONSOLE_PAD - PROMPT_W - 4, CONSOLE_CMD_H - 4,
	}
	if render_input(&app.console.cmd_input, cmd_rect, app.delta_time) {
		cmd := entities.input_str(&app.console.cmd_input)
		if len(cmd) > 0 {
			console_exec(app, cmd)
		}
		entities.input_clear(&app.console.cmd_input)
	}

	// Borde inferior de la consola
	rl.DrawLineV(
		{0, panel_y + CONSOLE_H},
		{sw, panel_y + CONSOLE_H},
		rl.Color{60, 65, 100, 200},
	)
}

// Ejecuta un comando de la consola.
console_exec :: proc(app: ^entities.App_State, cmd: string) {
	// Eco del comando
	entities.console_log(app, fmt.tprintf("> %s", cmd), .INFO)

	// Separar nombre del comando y argumentos
	cmd_name, rest: string
	space := -1
	for r, i in cmd {
		if r == ' ' { space = i; break }
	}
	if space >= 0 {
		cmd_name = cmd[:space]
		rest     = strings.trim_left_space(cmd[space+1:])
	} else {
		cmd_name = cmd
		rest     = ""
	}

	switch cmd_name {
	case "/help":
		entities.console_log(app, "Comandos disponibles:", .INFO)
		entities.console_log(app, "  /help               muestra esta ayuda", .INFO)
		entities.console_log(app, "  /gold <n>           da n monedas", .INFO)
		entities.console_log(app, "  /wave <n>           salta a la oleada n", .INFO)
		entities.console_log(app, "  /lives <n>          establece las vidas", .INFO)
		entities.console_log(app, "  /clear              limpia la consola", .INFO)

	case "/gold":
		if len(rest) == 0 {
			entities.console_log(app, "Uso: /gold <cantidad>", .WARNING)
			return
		}
		n, ok := _parse_i32(rest)
		if !ok {
			entities.console_log(app, fmt.tprintf("Cantidad inválida: %s", rest), .ERROR)
			return
		}
		app.sim.money += n
		entities.console_log(app, fmt.tprintf("+ $%d  (total: $%d)", n, app.sim.money), .SUCCESS)

	case "/wave":
		if len(rest) == 0 {
			entities.console_log(app, "Uso: /wave <número>", .WARNING)
			return
		}
		n, ok := _parse_i32(rest)
		if !ok {
			entities.console_log(app, fmt.tprintf("Número inválido: %s", rest), .ERROR)
			return
		}
		app.sim.wave_number = n
		entities.console_log(app, fmt.tprintf("Oleada → %d", n), .SUCCESS)

	case "/lives":
		if len(rest) == 0 {
			entities.console_log(app, "Uso: /lives <n>", .WARNING)
			return
		}
		n, ok := _parse_i32(rest)
		if !ok {
			entities.console_log(app, fmt.tprintf("Número inválido: %s", rest), .ERROR)
			return
		}
		app.sim.health = n
		entities.console_log(app, fmt.tprintf("Vidas → %d", n), .SUCCESS)

	case "/clear":
		for &e in app.console.entries { delete(e.message) }
		clear(&app.console.entries)
		app.console.scroll_y = 0

	case:
		entities.console_log(app, fmt.tprintf("Comando desconocido: %s", cmd_name), .ERROR)
	}
}

package entities

import "../constants"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// Toast types for different messages
Toast_Type :: enum {
	SUCCESS,
	INFO,
	WARNING,
	ERROR,
}

// Toast message structure
Toast :: struct {
	message:       string,
	type:          Toast_Type,
	duration:      f32,
	creation_time: f64,  // se asigna cuando el toast pasa a ser el activo (head de la cola)
	opacity:       f32,
}

// Agrega un toast a la cola.
// Si la cola está vacía se activa inmediatamente (creation_time = ahora).
// Si hay toasts esperando, creation_time = 0 hasta que llegue su turno.
// El mensaje se clona en el heap para que sobreviva al free_all(context.temp_allocator).
add_toast :: proc(app: ^App_State, message: string, type: Toast_Type, duration: f32 = 2.5) {
	toast := Toast{
		message  = strings.clone(message),
		type     = type,
		duration = duration,
		// Si la cola está vacía este toast es el activo de inmediato
		creation_time = rl.GetTime() if len(app.toasts) == 0 else 0,
		opacity  = 0,
	}
	append(&app.toasts, toast)
}

// Actualiza la cola de toasts:
// solo el primero (índice 0) está activo — los demás esperan su turno.
update_toasts :: proc(app: ^App_State, dt: f32) {
	if len(app.toasts) == 0 do return

	head := &app.toasts[0]
	age  := f32(rl.GetTime() - head.creation_time)

	// Fade in / visible / fade out
	FADE :: f32(0.25)
	if age < FADE {
		head.opacity = age / FADE
	} else if age > head.duration - FADE {
		head.opacity = max(0, (head.duration - age) / FADE)
	} else {
		head.opacity = 1.0
	}

	// Expirado: eliminar y activar el siguiente
	if age >= head.duration {
		delete(app.toasts[0].message)
		ordered_remove(&app.toasts, 0)
		// Activar el nuevo head asignándole creation_time ahora
		if len(app.toasts) > 0 {
			app.toasts[0].creation_time = rl.GetTime()
			app.toasts[0].opacity       = 0
		}
	}
}

// Renderiza únicamente el toast activo (head de la cola).
render_toasts :: proc(app: ^App_State) {
	if len(app.toasts) == 0 do return

	toast      := &app.toasts[0]
	screen_w   := rl.GetScreenWidth()
	font_size  := f32(constants.UI_TOAST_FONT_SIZE)
	padding    := f32(constants.UI_TOAST_PADDING)
	margin_top := f32(constants.UI_MARGIN_Y)

	bg_color, text_color: rl.Color
	switch toast.type {
	case .SUCCESS:
		bg_color   = constants.UI_TOAST_SUCCESS_COLOR
		text_color = constants.UI_TOAST_SUCCESS_TEXT_COLOR
	case .INFO:
		bg_color   = constants.UI_TOAST_INFO_COLOR
		text_color = constants.UI_TOAST_INFO_TEXT_COLOR
	case .WARNING:
		bg_color   = constants.UI_TOAST_WARNING_COLOR
		text_color = constants.UI_TOAST_WARNING_TEXT_COLOR
	case .ERROR:
		bg_color   = constants.UI_TOAST_ERROR_COLOR
		text_color = constants.UI_TOAST_ERROR_TEXT_COLOR
	}

	bg_color.a   = u8(f32(bg_color.a)   * toast.opacity)
	text_color.a = u8(f32(text_color.a) * toast.opacity)

	cstr        := strings.clone_to_cstring(toast.message, context.temp_allocator)
	text_w      := rl.MeasureTextEx(constants.game_fonts.regular, cstr, font_size, 0).x
	toast_w     := text_w + padding * 2
	toast_h     := font_size + padding * 2
	toast_x     := f32(screen_w) / 2 - toast_w / 2

	rl.DrawRectangleRounded(
		{toast_x, margin_top, toast_w, toast_h},
		constants.UI_TOAST_ROUNDNESS,
		constants.TOWER_CORNER_SEGMENTS,
		bg_color,
	)
	rl.DrawTextEx(
		constants.game_fonts.regular,
		cstr,
		{toast_x + padding, margin_top + padding},
		font_size, 0, text_color,
	)

	// Indicador de cola: etiqueta "+N" si hay más toasts esperando
	pending := len(app.toasts) - 1
	if pending > 0 {
		label     := strings.clone_to_cstring(fmt.tprintf("+%d", pending), context.temp_allocator)
		label_sz  : f32 = font_size - 2
		label_w   := rl.MeasureTextEx(constants.game_fonts.regular, label, label_sz, 0).x
		label_x   := f32(screen_w) / 2 - label_w / 2
		label_y   := margin_top + toast_h + 4
		label_col := rl.Color{255, 255, 255, u8(160 * toast.opacity)}
		rl.DrawTextEx(constants.game_fonts.regular, label, {label_x, label_y}, label_sz, 0, label_col)
	}
}

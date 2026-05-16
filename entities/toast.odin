package entities

import "../constants"
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
	message: string,
	type: Toast_Type,
	creation_time: f64,
	duration: f32,
	y_position: f32,
	opacity: f32,
	is_active: bool,
}

// Add a new toast to the system.
// El mensaje se clona en el heap para que sobreviva al free_all(context.temp_allocator)
// que ocurre al final de cada frame. El caller puede pasar un string literal, un tprintf,
// o cualquier string — aquí siempre se hace una copia propia.
add_toast :: proc(app: ^App_State, message: string, type: Toast_Type, duration: f32 = 3.0) {
	toast := Toast {
		message = strings.clone(message), // heap — no depende del temp_allocator
		type = type,
		creation_time = rl.GetTime(),
		duration = duration,
		y_position = 0,
		opacity = 0,
		is_active = true,
	}
	append(&app.toasts, toast)
}

// Update all toasts (remove expired ones, update animations)
update_toasts :: proc(app: ^App_State, dt: f32) {
	current_time := rl.GetTime()
	
	for i := len(app.toasts) - 1; i >= 0; i -= 1 {
		toast := &app.toasts[i]
		
		// Check if toast should be removed
		if current_time - toast.creation_time > f64(toast.duration) {
			delete(app.toasts[i].message) // liberar el string clonado en add_toast
			ordered_remove(&app.toasts, i)
			continue
		}
		
		// Update opacity for fade in/out animation
		age := f32(current_time - toast.creation_time)
		if age < 0.5 {
			// Fade in
			toast.opacity = age / 0.5
		} else if age > toast.duration - 0.5 {
			// Fade out
			toast.opacity = (toast.duration - age) / 0.5
		} else {
			// Fully visible
			toast.opacity = 1.0
		}
	}
}

// Render all active toasts
render_toasts :: proc(app: ^App_State) {
	if len(app.toasts) == 0 {
		return
	}
	
	screen_width := rl.GetScreenWidth()
	font_size := f32(constants.UI_TOAST_FONT_SIZE)
	padding := constants.UI_TOAST_PADDING
	spacing := constants.UI_TOAST_SPACING
	margin_top := constants.UI_TOAST_MARGIN_TOP
	
	// Calculate positions for all toasts (stack from top)
	current_y := f32(margin_top)
	for i in 0 ..< len(app.toasts) {
		toast := &app.toasts[i]
		toast.y_position = current_y
		
		// Get color based on toast type
		bg_color, text_color: rl.Color
		switch toast.type {
		case .SUCCESS:
			bg_color = constants.UI_TOAST_SUCCESS_COLOR
			text_color = constants.UI_TOAST_SUCCESS_TEXT_COLOR
		case .INFO:
			bg_color = constants.UI_TOAST_INFO_COLOR
			text_color = constants.UI_TOAST_INFO_TEXT_COLOR
		case .WARNING:
			bg_color = constants.UI_TOAST_WARNING_COLOR
			text_color = constants.UI_TOAST_WARNING_TEXT_COLOR
		case .ERROR:
			bg_color = constants.UI_TOAST_ERROR_COLOR
			text_color = constants.UI_TOAST_ERROR_TEXT_COLOR
		}
		
		// Apply opacity to colors
		bg_color.a = u8(f32(bg_color.a) * toast.opacity)
		text_color.a = u8(f32(text_color.a) * toast.opacity)
		
		// Measure text dimensions
		text_width := rl.MeasureTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring(toast.message, context.temp_allocator),
			font_size,
			0,
		).x
		
		// Calculate toast dimensions
		toast_width := text_width + f32(padding * 2)
		toast_height := font_size + f32(padding * 2)
		toast_x := f32(screen_width) / 2 - toast_width / 2
		
		// Draw background
		rl.DrawRectangleRounded(
			{toast_x, current_y, toast_width, toast_height},
			constants.UI_TOAST_ROUNDNESS,
			constants.TOWER_CORNER_SEGMENTS,
			bg_color,
		)
		
		// Draw text
		text_x := toast_x + f32(padding)
		text_y := current_y + f32(padding)
		rl.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring(toast.message, context.temp_allocator),
			{text_x, text_y},
			font_size,
			0,
			text_color,
		)
		
		// Move to next toast position
		current_y += toast_height + f32(spacing)
	}
}

package entities

import "core:strings"
import rl "vendor:raylib"

// Entrada individual del log de la consola.
Console_Entry :: struct {
	message:   string,     // clonado en heap
	type:      Toast_Type,
	timestamp: f64,        // rl.GetTime() al momento de creación
}

// Estado de la consola.
Console_State :: struct {
	entries:   [dynamic]Console_Entry,
	cmd_input: Input_State,
	open:      bool,
	slide_t:   f32,    // 0.0 = cerrada, 1.0 = abierta (animación)
	scroll_y:  f32,    // offset de scroll del log en píxeles
}

// Agrega una entrada al log. Hace auto-scroll al fondo.
console_log :: proc(app: ^App_State, message: string, type: Toast_Type) {
	entry := Console_Entry{
		message   = strings.clone(message),
		type      = type,
		timestamp = rl.GetTime(),
	}
	append(&app.console.entries, entry)
	// Auto-scroll al fondo: valor grande que render_console va a clampear
	app.console.scroll_y = 1e9
}

// Libera todos los recursos de la consola.
console_destroy :: proc(c: ^Console_State) {
	for &e in c.entries {
		delete(e.message)
	}
	delete(c.entries)
}

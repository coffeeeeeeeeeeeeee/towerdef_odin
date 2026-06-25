package entities

// Toast types for different messages
Toast_Type :: enum {
	SUCCESS,
	INFO,
	WARNING,
	ERROR,
}

// Toast message structure (conservado para compatibilidad con app.toasts)
Toast :: struct {
	message:       string,
	type:          Toast_Type,
	duration:      f32,
	creation_time: f64,
	opacity:       f32,
}

// Registra el mensaje en la consola.
// duration se conserva por compatibilidad de firma pero ya no se usa.
add_toast :: proc(app: ^App_State, message: string, type: Toast_Type, duration: f32 = 2.5) {
	console_log(app, message, type)
}

// No-op: los toasts ya no se procesan en cola.
update_toasts :: proc(app: ^App_State, dt: f32) {}

// No-op: render_console se encarga de mostrar los mensajes.
render_toasts :: proc(app: ^App_State) {}

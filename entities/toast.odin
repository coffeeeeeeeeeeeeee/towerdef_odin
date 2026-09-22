package entities

// Toast types for different messages
Toast_Type :: enum {
	SUCCESS,
	INFO,
	WARNING,
	ERROR,
}

// Registra el mensaje en la consola.
// duration se conserva por compatibilidad de firma pero ya no se usa.
add_toast :: proc(app: ^App_State, message: string, type: Toast_Type, duration: f32 = 2.5) {
	console_log(app, message, type)
}

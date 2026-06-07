package entities

import "core:strings"
import "../constants"

// Estado de un campo de texto interactivo.
// Embeber en cualquier struct que necesite un input de texto.
Input_State :: struct {
	buf:        [constants.MAX_INPUT_LEN]rune,
	len:        int,       // número de runes actualmente en buf
	cursor:     int,       // índice del cursor (0..len)
	sel_anchor: int,       // -1 = sin selección; de lo contrario, ancla de la selección
	scroll_x:   f32,       // desplazamiento horizontal del viewport en píxeles
	blink:      f32,       // 0..1; cursor visible cuando < INPUT_BLINK_HALF
	focused:    bool,
}

// Devuelve el contenido del input como string (válido hasta que se resetea el temp_allocator).
input_str :: proc(s: ^Input_State) -> string {
	if s.len == 0 { return "" }
	b := strings.builder_make(context.temp_allocator)
	for i in 0..<s.len {
		strings.write_rune(&b, s.buf[i])
	}
	return strings.to_string(b)
}

// Resetea el input al estado vacío.
input_clear :: proc(s: ^Input_State) {
	s.len        = 0
	s.cursor     = 0
	s.sel_anchor = -1
	s.scroll_x   = 0
	s.blink      = 0
}

// Devuelve el rango de selección [lo, hi) ordenado de menor a mayor.
// Si no hay selección, devuelve (cursor, cursor).
input_sel_range :: proc(s: ^Input_State) -> (lo, hi: int) {
	if s.sel_anchor < 0 { return s.cursor, s.cursor }
	if s.sel_anchor <= s.cursor { return s.sel_anchor, s.cursor }
	return s.cursor, s.sel_anchor
}

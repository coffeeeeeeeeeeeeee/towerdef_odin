package systems

import "vendor:raylib"
import "../entities"
import "../constants"
import "core:fmt"
import "core:strings"

// Overlay de diagnóstico (ver render_gamepad_debug_overlay más abajo) —
// toggle en runtime con F10 (systems/input.odin), no atado a
// constants.DEVELOPER: así sirve para diagnosticar en cualquier build,
// no sólo mientras se desarrolla.
gamepad_debug_active: bool = false

// ─────────────────────────────────────────────────────────────────────────────
// Navegación de menús con mando — primera etapa (ver CLAUDE.md). Sólo lee el
// mando resuelto en _gamepad_index (un jugador). Toda la lectura cruda de
// raylib vive acá; interface.odin/menus.odin/campaign.odin sólo consumen
// gamepad_nav_update/gamepad_confirm_pressed/gamepad_cancel_pressed.
// ─────────────────────────────────────────────────────────────────────────────

// Índice del mando activo — se resuelve en runtime cada frame (ver
// _gamepad_resolve_index), no queda fijo en 0: en algunos sistemas (sobre
// todo Linux) el mando "real" no siempre enumera en el índice 0, sobre
// todo si hay otro dispositivo (o un mando fantasma ya desconectado) que
// ocupa ese slot — con el índice fijo en 0, esos casos hacían que
// IsGamepadAvailable(0) diera false para siempre y el mando no hiciera
// absolutamente nada, sin ningún error visible. -1 = ninguno detectado.
_gamepad_index: i32 = -1

GAMEPAD_MAX_SLOTS :: 4  // raylib no expone MAX_GAMEPADS; se prueban 4 slots

GAMEPAD_DEADZONE             :: f32(0.35)
GAMEPAD_NAV_REPEAT_DELAY     :: f32(0.35)  // espera inicial antes de repetir
GAMEPAD_NAV_REPEAT_INTERVAL  :: f32(0.12)  // cada cuánto repite una vez pasado el delay

Gamepad_Nav_Dir :: enum { NONE, UP, DOWN, LEFT, RIGHT }

_GAMEPAD_NAV_DIRS :: [4]Gamepad_Nav_Dir{.UP, .DOWN, .LEFT, .RIGHT}

// Segundos que cada dirección lleva sostenida sin soltarse — static de
// paquete, persiste entre frames (0 = no sostenida este frame).
_gamepad_dir_held: [Gamepad_Nav_Dir]f32

// Recorre los primeros GAMEPAD_MAX_SLOTS índices y devuelve el primero
// disponible (-1 si ninguno). Se llama una vez por frame — barato (4
// chequeos) y tolera que el mando se conecte/desconecte en caliente o que
// el SO lo enumere en un índice distinto de 0.
_gamepad_resolve_index :: proc() -> i32 {
	for i in i32(0) ..< GAMEPAD_MAX_SLOTS {
		if raylib.IsGamepadAvailable(i) { return i }
	}
	return -1
}

// True si `dir` está siendo empujada ahora mismo (D-pad o stick izquierdo
// más allá del deadzone) — no aplica repeat, es el estado crudo "down".
// El aporte del STICK exige eje dominante (|eje relevante| >= |el otro
// eje|) — sin esto, un empuje "hacia la derecha" con la más mínima deriva
// vertical (inevitable en un stick analógico real) también cruza el
// deadzone de Y y, como UP/DOWN se evalúan antes que LEFT/RIGHT en
// `_GAMEPAD_NAV_DIRS`, current_nav_dir salía DOWN en vez de RIGHT ese
// frame. En la tienda eso disparaba el salto a Saltar/Reroll a mitad de
// una navegación horizontal — bug real reportado por el usuario ("no
// puede elegir a partir de la segunda carta"). El botón de D-pad no lleva
// este chequeo (una pulsación de botón no tiene "magnitud" que comparar,
// y presionar dos direcciones de d-pad a la vez es intencional, no deriva
// analógica).
_gamepad_dir_down :: proc(dir: Gamepad_Nav_Dir) -> bool {
	if _gamepad_index < 0 { return false }
	ax := raylib.GetGamepadAxisMovement(_gamepad_index, .LEFT_X)
	ay := raylib.GetGamepadAxisMovement(_gamepad_index, .LEFT_Y)
	switch dir {
	case .NONE:
		return false
	case .UP:
		return raylib.IsGamepadButtonDown(_gamepad_index, .LEFT_FACE_UP) ||
			(ay < -GAMEPAD_DEADZONE && abs(ay) >= abs(ax))
	case .DOWN:
		return raylib.IsGamepadButtonDown(_gamepad_index, .LEFT_FACE_DOWN) ||
			(ay > GAMEPAD_DEADZONE && abs(ay) >= abs(ax))
	case .LEFT:
		return raylib.IsGamepadButtonDown(_gamepad_index, .LEFT_FACE_LEFT) ||
			(ax < -GAMEPAD_DEADZONE && abs(ax) >= abs(ay))
	case .RIGHT:
		return raylib.IsGamepadButtonDown(_gamepad_index, .LEFT_FACE_RIGHT) ||
			(ax > GAMEPAD_DEADZONE && abs(ax) >= abs(ay))
	}
	return false
}

// Dispara true en el primer frame que `dir` se sostiene, y de nuevo cada
// GAMEPAD_NAV_REPEAT_INTERVAL segundos una vez pasado el delay inicial —
// mismo idiolecto que IsKeyPressedRepeat de raylib (usado para el cursor de
// texto en render_input), pero hand-rolleado porque raylib no ofrece repeat
// para gamepad, sólo para teclado.
_gamepad_dir_check :: proc(dir: Gamepad_Nav_Dir, dt: f32) -> bool {
	if !_gamepad_dir_down(dir) {
		_gamepad_dir_held[dir] = 0
		return false
	}
	prev := _gamepad_dir_held[dir]
	_gamepad_dir_held[dir] += dt
	if prev == 0 { return true }
	if prev < GAMEPAD_NAV_REPEAT_DELAY { return false }
	prev_steps := int((prev - GAMEPAD_NAV_REPEAT_DELAY) / GAMEPAD_NAV_REPEAT_INTERVAL)
	new_steps  := int((_gamepad_dir_held[dir] - GAMEPAD_NAV_REPEAT_DELAY) / GAMEPAD_NAV_REPEAT_INTERVAL)
	return new_steps > prev_steps
}

// NOTA: hubo acá un chequeo "sólo stick, sin d-pad" (_gamepad_stick_dir_*/
// gamepad_shop_stick_dir) para la navegación de cartas de la tienda,
// agregado a pedido explícito ("saca el d-pad") y sacado de nuevo a
// pedido explícito poco después ("quiero que el d-pad también funcione
// ahí") — la tienda volvió a usar `current_nav_dir` (fusionado) como
// cualquier otra pantalla, ver render_card_selection_overlay
// (systems/menus.odin). El chequeo de eje dominante en `_gamepad_dir_down`
// de arriba sigue vigente y es lo que de verdad soluciona el problema que
// motivó el intento "sólo stick" en primer lugar.

gamepad_confirm_pressed :: proc() -> bool {
	return _gamepad_index >= 0 && raylib.IsGamepadButtonPressed(_gamepad_index, .RIGHT_FACE_DOWN)
}

gamepad_cancel_pressed :: proc() -> bool {
	return _gamepad_index >= 0 && raylib.IsGamepadButtonPressed(_gamepad_index, .RIGHT_FACE_RIGHT)
}

// Triángulo — "vender" en la mano de cartas durante PLAYING (mismo botón
// que en el resto del juego significa "confirmar"/"cancelar" para X/Círculo,
// pero éste es específico de la mano, no un botón genérico de UI).
gamepad_sell_pressed :: proc() -> bool {
	return _gamepad_index >= 0 && raylib.IsGamepadButtonPressed(_gamepad_index, .RIGHT_FACE_UP)
}

// Px/s de movimiento del cursor real a deflexión completa del stick
// derecho — ver gamepad_virtual_mouse_update.
GAMEPAD_VIRTUAL_MOUSE_SPEED :: f32(900)

// Mueve el cursor REAL del sistema con el stick derecho (sólo PLAYING,
// ver input_handle_playing) — no un cursor dibujado aparte, así que todo
// el hit-testing que ya existe (mano, tienda, grilla, paneles) sigue
// funcionando tal cual sin duplicar nada. Devuelve true si se movió algo
// este frame (input_handle_playing lo usa para decidir el contexto
// activo — ver Playing_Gamepad_Context).
gamepad_virtual_mouse_update :: proc(dt: f32) -> bool {
	if _gamepad_index < 0 { return false }
	ax := raylib.GetGamepadAxisMovement(_gamepad_index, .RIGHT_X)
	ay := raylib.GetGamepadAxisMovement(_gamepad_index, .RIGHT_Y)
	if abs(ax) < GAMEPAD_DEADZONE { ax = 0 }
	if abs(ay) < GAMEPAD_DEADZONE { ay = 0 }
	if ax == 0 && ay == 0 { return false }
	pos := raylib.GetMousePosition()
	pos.x = clamp(pos.x + ax*GAMEPAD_VIRTUAL_MOUSE_SPEED*dt, 0, f32(raylib.GetScreenWidth()))
	pos.y = clamp(pos.y + ay*GAMEPAD_VIRTUAL_MOUSE_SPEED*dt, 0, f32(raylib.GetScreenHeight()))
	raylib.SetMousePosition(i32(pos.x), i32(pos.y))
	return true
}

// NOTA: el paso fijo en píxeles de pantalla que había acá (48px por
// tap/repeat del D-pad) se sacó — con la grilla en proyección 3D
// (perspectiva + rotación de cámara con L2/R2) un paso de píxeles fijo no
// corresponde a un tile real: según el zoom/ángulo podía saltear celdas
// enteras o no alcanzar la siguiente, y nunca aterrizaba prolijo en el
// centro de un tile ("el mouse se saltea algunos lugares de la grilla",
// reporte real del usuario). Reemplazado por `gamepad_snap_cursor_to_grid`
// (`systems/input.odin`, que sí tiene a mano el mapa/cámara para resolver
// el tile vecino real en vez de un desplazamiento ciego en píxeles).

// Actualiza el estado de navegación de mando y decide qué dispositivo está
// "activo" (el último que se usó — si hay input de mando, mando; si hay
// movimiento o click real de mouse, mouse). Llamar una sola vez por frame,
// desde input_handle, antes del switch por estado. Devuelve la dirección a
// mover en las listas de botones este frame (o .NONE).
gamepad_nav_update :: proc(app: ^entities.App_State, dt: f32) -> Gamepad_Nav_Dir {
	_gamepad_index = _gamepad_resolve_index()
	if _gamepad_index < 0 {
		app.gamepad_nav_active = false
		return .NONE
	}

	result := Gamepad_Nav_Dir.NONE
	any_input := false
	for dir in _GAMEPAD_NAV_DIRS {
		if _gamepad_dir_check(dir, dt) {
			any_input = true
			if result == .NONE { result = dir }
		}
	}
	if gamepad_confirm_pressed() || gamepad_cancel_pressed() { any_input = true }

	if any_input {
		app.gamepad_nav_active = true
	} else {
		mouse_delta := raylib.GetMouseDelta()
		if mouse_delta.x != 0 || mouse_delta.y != 0 ||
		   raylib.IsMouseButtonPressed(.LEFT) || raylib.IsMouseButtonPressed(.RIGHT) {
			app.gamepad_nav_active = false
		}
	}

	return result
}

// Overlay de diagnóstico — F10 lo prende/apaga (gamepad_debug_active,
// systems/input.odin). Mientras el mando no responda en ningún lado, esto
// es la forma de ver qué está viendo raylib realmente, sin depender de
// que el bug se pueda razonar leyendo código: si acá no aparece ningún
// slot disponible, el problema es de detección del sistema operativo/
// raylib (no hay nada para arreglar en el juego); si aparece disponible
// pero al tocar botones no cambia nada en "Botones down" ni en los ejes,
// el problema es de mapeo de ESE control puntual. Se dibuja en cualquier
// pantalla — ver la llamada en render_ui (systems/menus.odin).
render_gamepad_debug_overlay :: proc(app: ^entities.App_State) {
	x : f32 = 10
	y : f32 = 10
	fs : f32 = 16
	line_h : f32 = fs + 4
	col := raylib.Color{255, 255, 0, 255}

	draw_line :: proc(text: string, x, y, fs: f32, col: raylib.Color) {
		raylib.DrawTextEx(
			constants.game_fonts.regular,
			strings.clone_to_cstring(text, context.temp_allocator),
			{x, y}, fs, 0, col,
		)
	}

	any_slot := false
	for i in i32(0) ..< GAMEPAD_MAX_SLOTS {
		avail := raylib.IsGamepadAvailable(i)
		if !avail { continue }
		any_slot = true
		name := raylib.GetGamepadName(i)
		draw_line(fmt.tprintf("Gamepad[%d]: %s", i, name), x, y, fs, col)
		y += line_h
	}
	if !any_slot {
		draw_line("Gamepad: ningún slot disponible (0..3)", x, y, fs, col)
		y += line_h
		return
	}
	if _gamepad_index < 0 {
		return
	}

	// Ejes crudos
	axes := [6]raylib.GamepadAxis{.LEFT_X, .LEFT_Y, .RIGHT_X, .RIGHT_Y, .LEFT_TRIGGER, .RIGHT_TRIGGER}
	axes_txt := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&axes_txt, "Ejes:")
	for a in axes {
		fmt.sbprintf(&axes_txt, " %v=%.2f", a, raylib.GetGamepadAxisMovement(_gamepad_index, a))
	}
	draw_line(strings.to_string(axes_txt), x, y, fs, col)
	y += line_h

	// Todos los botones actualmente "down" (recorre el enum entero salvo UNKNOWN)
	held := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&held, "Botones down:")
	any_held := false
	for b in raylib.GamepadButton {
		if b == .UNKNOWN { continue }
		if raylib.IsGamepadButtonDown(_gamepad_index, b) {
			fmt.sbprintf(&held, " %v", b)
			any_held = true
		}
	}
	if !any_held { fmt.sbprintf(&held, " (ninguno)") }
	draw_line(strings.to_string(held), x, y, fs, col)
	y += line_h

	draw_line(fmt.tprintf("gamepad_nav_active=%v  current_nav_dir=%v", app.gamepad_nav_active, current_nav_dir), x, y, fs, col)
}

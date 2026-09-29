package systems

import "vendor:raylib"
import "../entities"

// ─────────────────────────────────────────────────────────────────────────────
// Navegación de menús con mando — primera etapa (ver CLAUDE.md). Sólo lee el
// mando en índice GAMEPAD_INDEX (un jugador, un mando). Toda la lectura cruda
// de raylib vive acá; interface.odin/menus.odin/campaign.odin sólo consumen
// gamepad_nav_update/gamepad_confirm_pressed/gamepad_cancel_pressed.
// ─────────────────────────────────────────────────────────────────────────────

GAMEPAD_INDEX :: 0

GAMEPAD_DEADZONE             :: f32(0.35)
GAMEPAD_NAV_REPEAT_DELAY     :: f32(0.35)  // espera inicial antes de repetir
GAMEPAD_NAV_REPEAT_INTERVAL  :: f32(0.12)  // cada cuánto repite una vez pasado el delay

Gamepad_Nav_Dir :: enum { NONE, UP, DOWN, LEFT, RIGHT }

_GAMEPAD_NAV_DIRS :: [4]Gamepad_Nav_Dir{.UP, .DOWN, .LEFT, .RIGHT}

// Segundos que cada dirección lleva sostenida sin soltarse — static de
// paquete, persiste entre frames (0 = no sostenida este frame).
_gamepad_dir_held: [Gamepad_Nav_Dir]f32

// True si `dir` está siendo empujada ahora mismo (D-pad o stick izquierdo
// más allá del deadzone) — no aplica repeat, es el estado crudo "down".
_gamepad_dir_down :: proc(dir: Gamepad_Nav_Dir) -> bool {
	switch dir {
	case .NONE:
		return false
	case .UP:
		return raylib.IsGamepadButtonDown(GAMEPAD_INDEX, .LEFT_FACE_UP) ||
			raylib.GetGamepadAxisMovement(GAMEPAD_INDEX, .LEFT_Y) < -GAMEPAD_DEADZONE
	case .DOWN:
		return raylib.IsGamepadButtonDown(GAMEPAD_INDEX, .LEFT_FACE_DOWN) ||
			raylib.GetGamepadAxisMovement(GAMEPAD_INDEX, .LEFT_Y) > GAMEPAD_DEADZONE
	case .LEFT:
		return raylib.IsGamepadButtonDown(GAMEPAD_INDEX, .LEFT_FACE_LEFT) ||
			raylib.GetGamepadAxisMovement(GAMEPAD_INDEX, .LEFT_X) < -GAMEPAD_DEADZONE
	case .RIGHT:
		return raylib.IsGamepadButtonDown(GAMEPAD_INDEX, .LEFT_FACE_RIGHT) ||
			raylib.GetGamepadAxisMovement(GAMEPAD_INDEX, .LEFT_X) > GAMEPAD_DEADZONE
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

gamepad_confirm_pressed :: proc() -> bool {
	return raylib.IsGamepadAvailable(GAMEPAD_INDEX) && raylib.IsGamepadButtonPressed(GAMEPAD_INDEX, .RIGHT_FACE_DOWN)
}

gamepad_cancel_pressed :: proc() -> bool {
	return raylib.IsGamepadAvailable(GAMEPAD_INDEX) && raylib.IsGamepadButtonPressed(GAMEPAD_INDEX, .RIGHT_FACE_RIGHT)
}

// Actualiza el estado de navegación de mando y decide qué dispositivo está
// "activo" (el último que se usó — si hay input de mando, mando; si hay
// movimiento o click real de mouse, mouse). Llamar una sola vez por frame,
// desde input_handle, antes del switch por estado. Devuelve la dirección a
// mover en las listas de botones este frame (o .NONE).
gamepad_nav_update :: proc(app: ^entities.App_State, dt: f32) -> Gamepad_Nav_Dir {
	if !raylib.IsGamepadAvailable(GAMEPAD_INDEX) {
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

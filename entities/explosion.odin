package entities

import "core:math"
import "vendor:raylib"
import "../constants"

// Explosion structure
Explosion :: struct {
	x: f32,
	y: f32,
	radius: f32,
	max_radius: f32,
	life: f32,
	max_life: f32,
}

// Initialize explosion
explosion_init :: proc(x, y, max_radius: f32) -> Explosion {
	return Explosion{
		x = x,
		y = y,
		radius = 0,
		max_radius = max_radius,
		life = 0.3,
		max_life = 0.3,
	}
}

// Update explosion
explosion_update :: proc(e: ^Explosion, dt: f32) -> bool {
	e.life -= dt
	
	// Expand then fade
	progress := 1.0 - (e.life / e.max_life)
	e.radius = e.max_radius * math.sin(progress * math.PI)
	
	return e.life <= 0
}

// Damage number structure
Damage_Number :: struct {
	x: f32,
	y: f32,
	value: f32,
	life: f32,
	max_life: f32,
	color: raylib.Color,
	is_critical: bool,
	is_money: bool,   // true = mostrar como "+$X" en amarillo
}

// Initialize damage number
damage_number_init :: proc(x, y, value: f32, is_critical: bool) -> Damage_Number {
	color := raylib.WHITE
	if is_critical {
		color = constants.TOWER_LASER_COLOR // Red for critical (mismo rojo que el láser)
	}
	
	return Damage_Number{
		x = x,
		y = y,
		value = value,
		life = 1.0,
		max_life = 1.0,
		color = color,
		is_critical = is_critical,
	}
}

// Initialize money reward number (amarillo, formato +$X)
damage_number_money_init :: proc(x, y: f32, amount: i32) -> Damage_Number {
	return Damage_Number{
		x        = x,
		y        = y,
		value    = f32(amount),
		life     = 1.2,
		max_life = 1.2,
		color    = raylib.Color{255, 220, 60, 255},
		is_money = true,
	}
}

// Update damage number
damage_number_update :: proc(dn: ^Damage_Number, dt: f32) -> bool {
	dn.life -= dt
	// Float up
	dn.y -= 0.5 * dt
	return dn.life <= 0
}

// Ice pulse — expanding ring emitted when the ice tower pulses
Ice_Pulse :: struct {
	// Center in grid units (tower center)
	x: f32,
	y: f32,
	// How far the ring has expanded (grid units)
	radius: f32,
	// Maximum radius = tower range
	max_radius: f32,
	// Remaining lifetime (seconds); starts at max_life
	life: f32,
	max_life: f32,
}

ice_pulse_init :: proc(x, y, max_radius: f32) -> Ice_Pulse {
	return Ice_Pulse{
		x          = x,
		y          = y,
		radius     = 0,
		max_radius = max_radius,
		life       = 0.5,
		max_life   = 0.5,
	}
}

// Returns true when the pulse is finished and should be removed
ice_pulse_update :: proc(p: ^Ice_Pulse, dt: f32) -> bool {
	p.life -= dt
	// Progress 0→1 over lifetime; radius expands from 0 to max_radius
	progress := 1.0 - (p.life / p.max_life)
	p.radius  = p.max_radius * progress
	return p.life <= 0
}

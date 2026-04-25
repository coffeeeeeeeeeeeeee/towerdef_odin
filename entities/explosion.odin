package entities

import "core:math"
import "vendor:raylib"

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
}

// Initialize damage number
damage_number_init :: proc(x, y, value: f32, is_critical: bool) -> Damage_Number {
	color := raylib.WHITE
	if is_critical {
		color = raylib.Color{255, 68, 68, 255} // Red for critical
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

// Update damage number
damage_number_update :: proc(dn: ^Damage_Number, dt: f32) -> bool {
	dn.life -= dt
	// Float up
	dn.y -= 0.5 * dt
	return dn.life <= 0
}

package entities

import "core:math"
import "vendor:raylib"
import "../constants"

// Projectile structure
Projectile :: struct {
	// Position
	x: f32,
	y: f32,
	
	// Target
	target: ^Enemy,
	target_orig_x: f32,
	target_orig_y: f32,
	
	// Properties
	speed: f32,
	damage: f32,
	type: constants.Tower_Type,
	aoe: f32,
	critical_level: i32,
	
	// Rotation
	angle: f32,  // Direction of movement in radians
}

// Initialize a projectile
projectile_init :: proc(
	x, y: f32,
	target: ^Enemy,
	speed: f32,
	damage: f32,
	target_strategy: constants.Target_Strategy,
	type: constants.Tower_Type,
	aoe: f32,
	critical_level: i32,
) -> Projectile {
	return Projectile{
		x = x,
		y = y,
		target = target,
		target_orig_x = target.x,
		target_orig_y = target.y,
		speed = speed,
		damage = damage,
		type = type,
		aoe = aoe,
		critical_level = critical_level,
	}
}

// Move projectile towards target
projectile_move :: proc(p: ^Projectile, dt: f32) -> bool {
	// Calculate target position
	target_x := p.target_orig_x
	target_y := p.target_orig_y
	
	if p.target != nil {
		target_x = p.target.x
		target_y = p.target.y
	}
	
	dx := target_x - p.x
	dy := target_y - p.y
	dist := math.sqrt(dx * dx + dy * dy)
	
	// Update angle based on movement direction
	p.angle = math.atan2(dy, dx)
	
	if dist < 0.01 {
		return true // Reached target
	}
	
	move_dist := p.speed * dt
	
	if move_dist >= dist {
		p.x = target_x
		p.y = target_y
		return true
	} else {
		p.x += (dx / dist) * move_dist
		p.y += (dy / dist) * move_dist
		return false
	}
}

// Check if projectile hit its actual target (for accuracy checks)
projectile_check_hit :: proc(p: ^Projectile) -> bool {
	if p.target == nil {
		return true // Target dead, projectile should be removed
	}
	
	dx := p.target.x - p.x
	dy := p.target.y - p.y
	dist := math.sqrt(dx * dx + dy * dy)
	
	return dist < 0.3 // Within hit radius
}

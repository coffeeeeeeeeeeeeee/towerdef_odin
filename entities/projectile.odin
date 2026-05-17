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
	target_last_x: f32,  // Last known position (for when target dies)
	target_last_y: f32,  // Last known position (for when target dies)
	
	// Properties
	speed: f32,
	damage: f32,
	type: constants.Tower_Type,
	aoe: f32,

	// Source tower grid position (for damage stats attribution)
	source_r: i32,
	source_c: i32,

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
	source_r: i32 = -1,
	source_c: i32 = -1,
) -> Projectile {
	return Projectile{
		x = x,
		y = y,
		target = target,
		target_orig_x = target.x,
		target_orig_y = target.y,
		target_last_x = target.x,
		target_last_y = target.y,
		speed = speed,
		damage = damage,
		type = type,
		aoe = aoe,
		source_r = source_r,
		source_c = source_c,
	}
}

// Move projectile towards target
projectile_move :: proc(p: ^Projectile, dt: f32) -> bool {
	// Always travel to the position where the target was at fire time.
	// Never re-home onto the target's current position; this avoids
	// the projectile changing direction mid-flight.
	target_x := p.target_orig_x
	target_y := p.target_orig_y

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

	// Compare against the fire-time position, since the projectile travels
	// toward target_orig_x/y and never re-homes.
	dx := p.target_orig_x - p.x
	dy := p.target_orig_y - p.y
	dist := math.sqrt(dx * dx + dy * dy)

	return dist < 0.3 // Within hit radius
}

// Calculate the spawn position (in grid coords) for a missile pod.
// missile_side: 0 = left pod, 1 = right pod.
// cx, cy: tower center in grid coords.
// aim_angle: atan2(target_y - cy, target_x - cx).
// Offsets mirror the two pod positions from draw_tower_tile (.MISSILE):
//   left pod local (-r*1.4, -r*0.8), right pod local (r*0.6, -r*0.8), r ≈ 0.3 grid units.
missile_barrel_spawn_pos :: proc(cx, cy: f32, aim_angle: f32, missile_side: i32) -> (x, y: f32) {
	// Perpendicular direction (90° CCW from aim)
	perp_x := -math.sin(aim_angle)
	perp_y :=  math.cos(aim_angle)

	// Forward direction (toward target)
	fwd_x := math.cos(aim_angle)
	fwd_y := math.sin(aim_angle)

	// Perpendicular offsets in grid units (derived from pod local positions, r=0.3)
	perp_offset := f32(-0.42) if missile_side == 0 else f32(0.18)
	fwd_offset  := f32(0.24) // r * 0.8, tip of pod toward target

	x = cx + perp_x * perp_offset + fwd_x * fwd_offset
	y = cy + perp_y * perp_offset + fwd_y * fwd_offset
	return
}

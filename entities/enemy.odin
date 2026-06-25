package entities

import "core:math"
import "vendor:raylib"
import "../constants"

// Enemy behaviour flags — combinable via bit_set (e.g. mixed waves have two flags set).
Enemy_Flag :: enum u8 { BOSS, GREEN, BLUE, FLYING, SPLIT, BONUS }
Enemy_Flags :: bit_set[Enemy_Flag; u8]

// Enemy structure
Enemy :: struct {
	// Position (in grid units, can be fractional)
	x: f32,
	y: f32,

	// Path following
	path: [dynamic]Path_Node,
	path_idx: i32,

	// Stats
	hp: f32,
	max_hp: f32,
	speed: f32,

	// Type flags (combinable: a mixed-wave enemy can have e.g. GREEN|BLUE)
	flags: Enemy_Flags,

	// Healing (for blue enemies)
	heal_cooldown: f32,

	// Obstacle damage tracking (to prevent multiple hits from same obstacle).
	// Key es [row, col] como [2]i32 — NO usar string con tprintf (la memoria del
	// temp_allocator se libera al final del frame y deja las keys colgando).
	obstacle_damage: map[[2]i32]bool,

	// Slow effect (from ice tower)
	slow_factor: f32,  // Speed multiplier: 1.0 = normal, <1.0 = slowed
	slow_timer:  f32,  // Seconds remaining on the slow

	// CRYPTOBRO relic: last tower that dealt damage to this enemy (row/col, -1 = none)
	last_attacker_r: i32,
	last_attacker_c: i32,

}

// Path node for enemy movement
Path_Node :: struct {
	x: i32,
	y: i32,
}

// Initialize a new enemy
enemy_init :: proc(hp, speed: f32, flags: Enemy_Flags = {}) -> Enemy {
	return Enemy{
		x               = 0,
		y               = 0,
		path            = make([dynamic]Path_Node),
		path_idx        = 0,
		hp              = hp,
		max_hp          = hp,
		speed           = speed,
		flags           = flags,
		heal_cooldown   = constants.ENEMY_HEAL_COOLDOWN_BLUE,
		obstacle_damage = make(map[[2]i32]bool),
		slow_factor     = 1.0,
		slow_timer      = 0.0,
		last_attacker_r = -1,
		last_attacker_c = -1,
	}
}

// Destroy enemy and free resources
enemy_destroy :: proc(e: ^Enemy) {
	delete(e.path)
	delete(e.obstacle_damage)
}

// Set enemy path starting position
enemy_set_path :: proc(e: ^Enemy, path: [dynamic]Path_Node) {
	delete(e.path)
	// Clone the path so each enemy has its own copy
	e.path = make([dynamic]Path_Node, len(path))
	for node, i in path {
		e.path[i] = node
	}
	if len(path) > 0 {
		e.x = f32(path[0].x)
		e.y = f32(path[0].y)
	}
	e.path_idx = 0
}

// Set enemy path from a slice (for split children that resume partway through)
enemy_set_path_slice :: proc(e: ^Enemy, path: []Path_Node) {
	delete(e.path)
	e.path = make([dynamic]Path_Node, len(path))
	for node, i in path {
		e.path[i] = node
	}
	e.path_idx = 0
}

// Move enemy along path
// Grid cells are 1.0 units apart, so speed is in cells per second
enemy_move :: proc(e: ^Enemy, dt: f32) -> bool {
	next_idx := e.path_idx + 1
	
	// Reached end of path
	if next_idx >= i32(len(e.path)) {
		return true
	}
	
	target := e.path[next_idx]
	target_x := f32(target.x)
	target_y := f32(target.y)
	
	dx := target_x - e.x
	dy := target_y - e.y
	dist := math.sqrt(dx * dx + dy * dy)
	
	// If already at target, move to next node
	if dist < 0.001 {
		e.path_idx = next_idx
		return false
	}
	
	// Scale speed - cells per second (slow_factor reduces speed when ice tower is in range)
	GRID_SPEED_SCALE :: 2.0
	move_dist := e.speed * e.slow_factor * GRID_SPEED_SCALE * dt
	
	if move_dist >= dist {
		e.x = target_x
		e.y = target_y
		e.path_idx = next_idx
	} else {
		e.x += (dx / dist) * move_dist
		e.y += (dy / dist) * move_dist
	}
	
	return false
}

// Update blue enemy healing
enemy_update_healing :: proc(e: ^Enemy, dt: f32) {
	if !(.BLUE in e.flags) {
		return
	}
	
	e.heal_cooldown -= dt
	if e.heal_cooldown <= 0 {
		heal_amount := e.max_hp * constants.ENEMY_HEAL_RATE_BLUE
		e.hp = min(e.hp + heal_amount, e.max_hp)
		e.heal_cooldown = constants.ENEMY_HEAL_COOLDOWN_BLUE
	}
}

// Check and apply obstacle damage
enemy_apply_obstacle_damage :: proc(e: ^Enemy, grid_x, grid_y, obstacle_level: i32) -> f32 {
	if .FLYING in e.flags {
		return 0
	}
	
	// Key estable por posición — no depende del temp_allocator
	key := [2]i32{grid_y, grid_x}

	if e.obstacle_damage[key] {
		return 0 // Already damaged by this obstacle
	}

	// Daño lineal: base * level — escala suave y predecible
	damage := constants.OBSTACLE_DAMAGE_PER_LEVEL * f32(obstacle_level)
	e.hp -= damage
	e.obstacle_damage[key] = true

	return damage
}

// Get enemy color — bonus overrides all sub-types; bosses inherit sub-type color
enemy_get_color :: proc(e: ^Enemy) -> raylib.Color {
	switch {
	case .BONUS  in e.flags: return constants.COLOR_ENEMY_BONUS
	case .GREEN  in e.flags: return constants.ENEMY_GREEN
	case .BLUE   in e.flags: return constants.ENEMY_BLUE
	case .FLYING in e.flags: return constants.COLOR_ENEMY_FLYING
	case .SPLIT  in e.flags: return constants.COLOR_ENEMY_SPLIT
	case:                    return constants.COLOR_ENEMY
	}
}

// Apply a slow effect to an enemy.
// A stronger slow (lower factor) always wins.
// A weaker slow while a stronger one is active is silently ignored — it neither
// overwrites the slow_factor nor extends the duration.
enemy_apply_slow :: proc(e: ^Enemy, factor: f32, duration: f32) {
	if e.slow_timer <= 0 {
		// No active slow — apply fresh
		e.slow_factor = factor
		e.slow_timer  = duration
	} else if factor <= e.slow_factor {
		// New slow is at least as strong — apply and refresh
		e.slow_factor = factor
		e.slow_timer  = duration
	}
	// Weaker slow while a stronger one is active: do nothing
}

// Tick down slow timer and restore full speed when expired
enemy_update_slow :: proc(e: ^Enemy, dt: f32) {
	if e.slow_timer > 0 {
		e.slow_timer -= dt
		if e.slow_timer <= 0 {
			e.slow_timer  = 0
			e.slow_factor = 1.0
		}
	}
}

// Get enemy size — bosses are 75% larger than their sub-type base size
enemy_get_size :: proc(e: ^Enemy) -> f32 {
	boss_mult :: f32(1.75)
	if .BONUS in e.flags {
		base: f32 = constants.ENEMY_SIZE_BONUS
		if .BOSS in e.flags { return base * boss_mult }
		return base
	}
	base: f32
	switch {
	case .FLYING in e.flags: base = constants.ENEMY_SIZE_FLYING
	case .BLUE   in e.flags: base = constants.ENEMY_SIZE_BLUE
	case .GREEN  in e.flags: base = constants.ENEMY_SIZE_GREEN
	case:                    base = constants.ENEMY_SIZE_DEFAULT
	}
	if .BOSS in e.flags { return base * boss_mult }
	return base
}
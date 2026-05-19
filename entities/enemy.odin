package entities

import "core:math"
import "core:fmt"
import "vendor:raylib"
import "../constants"

// Enemy type
Enemy_Type :: enum {
	NORMAL,
	GREEN,
	BLUE,
	FLYING,
	BOSS,
}

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
	
	// Type flags
	is_boss: bool,
	is_flying: bool,
	is_green: bool,
	is_blue: bool,
	boss_color: raylib.Color,
	
	// Healing (for blue enemies)
	heal_cooldown: f32,
	
	// Obstacle damage tracking (to prevent multiple hits from same obstacle)
	obstacle_damage: map[string]bool,

	// True if this enemy belongs to a split-type wave (renders purple and splits on death).
	// Children spawned by splitting have is_split = false, so they don't split again.
	is_split: bool,

	// True if this enemy comes from a bonus wave. Renders gold and drops extra money.
	// Split children of a bonus enemy inherit sub-type flags but NOT is_bonus.
	is_bonus: bool,

	// Slow effect (from ice tower)
	slow_factor: f32,  // Speed multiplier: 1.0 = normal, <1.0 = slowed
	slow_timer:  f32,  // Seconds remaining on the slow

	// Temporary distance for targeting
	_tmp_dist: f32,
}

// Path node for enemy movement
Path_Node :: struct {
	x: i32,
	y: i32,
}

// Initialize a new enemy
enemy_init :: proc(
	hp: f32,
	speed: f32,
	is_boss: bool,
	is_flying: bool,
	is_green: bool,
	is_blue: bool,
	boss_color: raylib.Color,
	is_bonus: bool = false,
) -> Enemy {
	return Enemy{
		x = 0,
		y = 0,
		path = make([dynamic]Path_Node),
		path_idx = 0,
		hp = hp,
		max_hp = hp,
		speed = speed,
		is_boss = is_boss,
		is_flying = is_flying,
		is_green = is_green,
		is_blue = is_blue,
		boss_color = boss_color,
		heal_cooldown = constants.ENEMY_HEAL_COOLDOWN_BLUE,
		obstacle_damage = make(map[string]bool),
		is_split = false,
		is_bonus = is_bonus,
		slow_factor = 1.0,
		slow_timer = 0.0,
		_tmp_dist = 0,
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
	if !e.is_blue {
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
	if e.is_flying {
		return 0
	}
	
	// Create key for obstacle
	key := fmt.tprintf("%d,%d", grid_y, grid_x)
	
	if e.obstacle_damage[key] {
		return 0 // Already damaged by this obstacle
	}
	
	// Daño exponencial: base * 2^(level-1), igual que el upgrade de torres
	damage := constants.OBSTACLE_DAMAGE_PER_LEVEL * f32(i32(1) << uint(obstacle_level - 1))
	e.hp -= damage
	e.obstacle_damage[key] = true
	
	return damage
}

// Get enemy color — bonus overrides all sub-types; bosses inherit sub-type color
enemy_get_color :: proc(e: ^Enemy) -> raylib.Color {
	switch {
	case e.is_bonus:
		return constants.COLOR_ENEMY_BONUS
	case e.is_green:
		return constants.ENEMY_GREEN
	case e.is_blue:
		return constants.ENEMY_BLUE
	case e.is_flying:
		return constants.COLOR_ENEMY_FLYING
	case e.is_split:
		return constants.COLOR_ENEMY_SPLIT
	case:
		return constants.COLOR_ENEMY
	}
}

// Apply a slow effect to an enemy (refreshes duration if already slowed)
enemy_apply_slow :: proc(e: ^Enemy, factor: f32, duration: f32) {
	// Only apply if this is a stronger or fresh slow
	if factor < e.slow_factor || e.slow_timer <= 0 {
		e.slow_factor = factor
	}
	// Always refresh duration
	e.slow_timer = duration
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
	if e.is_bonus {
		base: f32 = constants.ENEMY_SIZE_BONUS
		if e.is_boss { return base * boss_mult }
		return base
	}
	base: f32
	switch {
	case e.is_flying:
		base = constants.ENEMY_SIZE_FLYING
	case e.is_blue:
		base = constants.ENEMY_SIZE_BLUE
	case e.is_green:
		base = constants.ENEMY_SIZE_GREEN
	case:
		base = constants.ENEMY_SIZE_DEFAULT
	}
	if e.is_boss {
		return base * boss_mult
	}
	return base
}
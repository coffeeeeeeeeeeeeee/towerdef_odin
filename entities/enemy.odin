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
		heal_cooldown = 0,
		obstacle_damage = make(map[string]bool),
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
	
	// Scale speed - cells per second
	GRID_SPEED_SCALE :: 2.0
	move_dist := e.speed * GRID_SPEED_SCALE * dt
	
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
		heal_amount := e.max_hp * 0.05
		e.hp = min(e.hp + heal_amount, e.max_hp)
		e.heal_cooldown = 1.0 // Reset to 1 second
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
	
	damage := f32(5 * obstacle_level)
	e.hp -= damage
	e.obstacle_damage[key] = true
	
	return damage
}

// Get enemy color
enemy_get_color :: proc(e: ^Enemy) -> raylib.Color {
	switch {
	case e.is_boss:
		return e.boss_color
	case e.is_green:
		return raylib.Color{0, 255, 0, 255}
	case e.is_blue:
		return raylib.Color{0, 0, 255, 255}
	case e.is_flying:
		return raylib.Color{255, 0, 0, 255}
	case:
		return constants.COLOR_ENEMY
	}
}

// Get enemy size
enemy_get_size :: proc(e: ^Enemy) -> f32 {
	switch {
	case e.is_boss:
		return 0.60
	case e.is_flying:
		return 0.25
	case e.is_blue:
		return 0.30
	case e.is_green:
		return 0.17
	case:
		return 0.30
	}
}

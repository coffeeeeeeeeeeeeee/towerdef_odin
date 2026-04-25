package entities

import "core:math"
import "../constants"

// Tower structure
Tower :: struct {
	// Position (grid coordinates)
	r: i32,
	c: i32,
	
	// Tower properties
	type: constants.tower_type,
	range: f32,
	damage: f32,
	cooldown: f32,
	aoe: f32,
	
	// Timers
	timer: f32,
	cooldown_timer: f32,
	firing_timer: f32,
	laser_beam_duration: f32,
	
	// Target
	target: ^Enemy,
	target_strategy: constants.Target_Strategy,
	
	// Visual
	angle: f32,
	turn_speed: f32,
	
	// Upgrade levels
	level: i32,
	damage_level: i32,
	rate_level: i32,
	critical_level: i32,
	
	// Missile system
	missile_side: i32,
	
	// Laser accumulation for damage display
	_laser_accum: f32,
	_laser_accum_timer: f32,
}

// Initialize a new tower
tower_init :: proc(tile: constants.Tile, row, col: i32) -> Tower {
	spec := constants.TOWER_SPECS[tile]
	return Tower{
		r = row,
		c = col,
		type = spec.type,
		range = spec.range,
		damage = spec.damage,
		cooldown = spec.cooldown,
		aoe = spec.aoe,
		timer = 0,
		cooldown_timer = 0,
		firing_timer = 0,
		laser_beam_duration = 0,
		target = nil,
		target_strategy = .FIRST,
		angle = 0,
		turn_speed = 6,
		level = 1,
		damage_level = 1,
		rate_level = 1,
		critical_level = 1,
		missile_side = 0,
		_laser_accum = 0,
		_laser_accum_timer = 0,
	}
}

// Get base cost of tower
tower_get_base_cost :: proc(t: ^Tower) -> i32 {
	for tile, spec in constants.TOWER_SPECS {
		if spec.type == t.type {
			return spec.cost
		}
	}
	return 0
}

// Get upgrade cost
tower_get_upgrade_cost :: proc(level: i32) -> i32 {
	if level <= 1 {
		return 0
	}
	return constants.UPGRADE_COST_PER_LEVEL * (level - 1) * level
}

// Calculate sell refund
tower_get_sell_refund :: proc(t: ^Tower) -> i32 {
	base_cost := tower_get_base_cost(t)
	
	upgrades_spent := tower_get_upgrade_cost(t.damage_level) +
		tower_get_upgrade_cost(t.rate_level) +
		tower_get_upgrade_cost(t.critical_level)
	
	return i32(f32(base_cost + upgrades_spent) * constants.SELL_REFUND)
}

// Upgrade damage
tower_upgrade_damage :: proc(t: ^Tower) -> bool {
	cost := constants.UPGRADE_BASE_COST + (t.damage_level - 1) * constants.UPGRADE_COST_PER_LEVEL
	// Money check should be done externally
	t.damage_level += 1
	t.damage *= (1.0 + constants.LASER_DAMAGE_MULTIPLIER_PER_LEVEL)
	return true
}

// Upgrade rate (cooldown reduction)
tower_upgrade_rate :: proc(t: ^Tower) -> bool {
	cost := constants.UPGRADE_BASE_COST + (t.rate_level - 1) * constants.UPGRADE_COST_PER_LEVEL
	// Money check should be done externally
	t.rate_level += 1
	return true
}

// Upgrade critical chance
tower_upgrade_critical :: proc(t: ^Tower) -> bool {
	cost := constants.UPGRADE_BASE_COST + (t.critical_level - 1) * constants.UPGRADE_COST_PER_LEVEL
	// Money check should be done externally
	t.critical_level += 1
	return true
}

// Get critical chance
tower_get_critical_chance :: proc(t: ^Tower) -> f32 {
	return constants.CRIT_BASE_CHANCE + f32(t.critical_level - 1) * constants.CRIT_PER_LEVEL
}

// Get damage multiplier from damage level
tower_get_damage_multiplier :: proc(t: ^Tower) -> f32 {
	return 1.0 + f32(t.damage_level - 1) * constants.LASER_DAMAGE_MULTIPLIER_PER_LEVEL
}

// Get cooldown with rate upgrade applied
tower_get_effective_cooldown :: proc(t: ^Tower) -> f32 {
	cooldown_reduction := 1.0 + f32(t.rate_level - 1) * constants.LASER_COOLDOWN_REDUCTION_PER_LEVEL
	return t.cooldown / cooldown_reduction
}

// Turn tower towards target
tower_turn_towards :: proc(t: ^Tower, target_angle: f32, dt: f32) {
	diff := target_angle - t.angle
	
	// Normalize angle difference
	for diff < -math.PI {
		diff += math.PI * 2
	}
	for diff > math.PI {
		diff -= math.PI * 2
	}
	
	step := t.turn_speed * dt
	if math.abs(diff) <= step {
		t.angle = target_angle
	} else {
		t.angle += math.sign(diff) * step
	}
	
	// Normalize final angle
	for t.angle < -math.PI {
		t.angle += math.PI * 2
	}
	for t.angle > math.PI {
		t.angle -= math.PI * 2
	}
}

// Check if tower is aligned with target (for firing)
tower_is_aligned :: proc(t: ^Tower, target_angle: f32) -> bool {
	diff := target_angle - t.angle
	for diff < -math.PI {
		diff += math.PI * 2
	}
	for diff > math.PI {
		diff -= math.PI * 2
	}
	return math.abs(diff) < 0.2
}

// Get cannon tip position for firing
tower_get_cannon_tip :: proc(t: ^Tower, cs: f32) -> (x, y: f32) {
	center_x := f32(t.c) * cs + cs / 2
	center_y := f32(t.r) * cs + cs / 2
	cannon_length := cs * 0.45
	return center_x + math.cos(t.angle) * cannon_length, center_y + math.sin(t.angle) * cannon_length
}

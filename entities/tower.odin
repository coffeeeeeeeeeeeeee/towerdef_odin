package entities

import "core:math"
import "vendor:raylib"
import "../constants"

// Tower structure
Tower :: struct {
	// Position (grid coordinates)
	r: i32,
	c: i32,
	
	// Tower properties
	type: constants.Tower_Type,
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
	
	// Upgrade level (empieza en 1, se incrementa con cada upgrade)
	level: i32,
	
	// Missile system
	missile_side: i32,
		
	// Laser accumulation for damage display
	_laser_accum: f32,
	_laser_accum_timer: f32,

	// Lifetime damage statistics
	total_damage: f32,
}

// Initialize a new tower
tower_init :: proc(tile_type: constants.Tower_Type, row, col: i32) -> Tower {
	spec := constants.TOWER_SPECS[tile_type]
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
		missile_side = 0,
		_laser_accum = 0,
		_laser_accum_timer = 0,
	}
}

// Get base cost of tower
tower_get_base_cost :: proc(t: ^Tower) -> i32 {
	spec := constants.TOWER_SPECS[t.type]
	return spec.cost
}

// Costo del próximo upgrade: base_cost * 2^(level-1)
tower_get_upgrade_cost :: proc(t: ^Tower) -> i32 {
	base_cost := tower_get_base_cost(t)
	multiplier := i32(1) << uint(t.level - 1) // 2^(level-1)
	return base_cost * multiplier
}

// Suma del dinero gastado en upgrades: base_cost * (2^(level-1) - 1)
// (suma geométrica: 1 + 2 + 4 + ... + 2^(level-2))
tower_get_total_upgrade_spent :: proc(t: ^Tower) -> i32 {
	if t.level <= 1 { return 0 }
	base_cost := tower_get_base_cost(t)
	multiplier := i32(1) << uint(t.level - 1) // 2^(level-1)
	return base_cost * (multiplier - 1)
}

// Sell refund: (base_cost + total_upgrades_spent) * TOWER_SELL_REFUND
tower_get_sell_refund :: proc(t: ^Tower) -> i32 {
	base_cost := tower_get_base_cost(t)
	upgrades_spent := tower_get_total_upgrade_spent(t)
	return i32(f32(base_cost + upgrades_spent) * constants.TOWER_SELL_REFUND)
}

// Upgrade: multiplica damage por TOWER_UPGRADE_MULTIPLIER; divide cooldown; incrementa level.
// Range y AoE nunca escalan con el nivel.
tower_upgrade :: proc(t: ^Tower) {
	t.damage   *= constants.TOWER_UPGRADE_MULTIPLIER
	t.cooldown /= constants.TOWER_UPGRADE_MULTIPLIER
	t.level += 1
}

// Get critical chance (fijo en base, no escala con upgrades)
tower_get_critical_chance :: proc(t: ^Tower) -> f32 {
	return constants.CRIT_BASE_CHANCE
}

// Get effective cooldown (t.cooldown ya refleja los upgrades aplicados)
tower_get_effective_cooldown :: proc(t: ^Tower) -> f32 {
	return t.cooldown
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
	cannon_length := cs * 0.55  // Increased to match visual cannon length
	return center_x + math.cos(t.angle) * cannon_length, center_y + math.sin(t.angle) * cannon_length
}
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

	// Base stats (immutable, from TOWER_SPECS at creation)
	base_damage:   f32,
	base_cooldown: f32,

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
	// Niveles otorgados por torres ENHANCE (recalculado cada frame)
	enhance_bonus: i32,

	// Missile system
	missile_side: i32,

	// Laser accumulation for damage display
	_laser_accum: f32,
	_laser_accum_timer: f32,

	// Cached formation flag — true when this tower is in a 3+ line of same type.
	// Recalculated by update_formation_cache whenever towers are added or removed.
	_in_formation: bool,

	// WARMED_UP relic: seconds this tower has continuously had a live target.
	// Reset to 0 when no target is found. Bonus kicks in at WARMED_UP_THRESHOLD.
	warm_timer: f32,

	// Lifetime damage statistics
	total_damage: f32,
}

// Initialize a new tower
tower_init :: proc(tile_type: constants.Tower_Type, row, col: i32) -> Tower {
	spec := constants.TOWER_SPECS[tile_type]
	return Tower{
		r             = row,
		c             = col,
		type          = spec.type,
		range         = spec.range,
		damage        = spec.damage,
		cooldown      = spec.cooldown,
		aoe           = spec.aoe,
		base_damage   = spec.damage,
		base_cooldown = spec.cooldown,
		timer         = 0,
		cooldown_timer = 0,
		firing_timer  = 0,
		laser_beam_duration = 0,
		target        = nil,
		target_strategy = .FIRST,
		angle         = 0,
		turn_speed    = 6,
		level         = 1,
		missile_side  = 0,
		_laser_accum  = 0,
		_laser_accum_timer = 0,
	}
}

// Recomputa damage y cooldown desde base stats según el nivel total (escalado lineal).
// damage   = base × (1 + TOWER_DAMAGE_PER_LEVEL × (level-1))
// cooldown = base / (1 + TOWER_SPEED_PER_LEVEL  × (level-1))
// Llamar siempre que level o enhance_bonus cambien.
tower_recompute_stats :: proc(t: ^Tower) {
	n := f32(t.level - 1)
	t.damage   = t.base_damage   * (1 + constants.TOWER_DAMAGE_PER_LEVEL * n)
	t.cooldown = t.base_cooldown / (1 + constants.TOWER_SPEED_PER_LEVEL  * n)
	min_cd := constants.TOWER_SPECS[t.type].min_cooldown
	if min_cd > 0 && t.cooldown < min_cd {
		t.cooldown = min_cd
	}
}

// Get base cost of tower
tower_get_base_cost :: proc(t: ^Tower) -> i32 {
	spec := constants.TOWER_SPECS[t.type]
	return spec.cost
}

// Costo del próximo upgrade: base_cost * base_level (lineal).
// El nivel de enhance no cuenta para el precio.
// Ejemplos arquera (base 20): Nv2→$20, Nv10→$180, Nv20→$380
tower_get_upgrade_cost :: proc(t: ^Tower) -> i32 {
	base_cost  := tower_get_base_cost(t)
	base_level := t.level - t.enhance_bonus
	return base_cost * base_level
}

// Total gastado en upgrades hasta el nivel actual: base_cost * level * (level-1) / 2
// (suma aritmética: 1 + 2 + ... + (level-1))
tower_get_total_upgrade_spent :: proc(t: ^Tower) -> i32 {
	if t.level <= 1 { return 0 }
	base_cost  := tower_get_base_cost(t)
	base_level := t.level - t.enhance_bonus
	return base_cost * base_level * (base_level - 1) / 2
}

// Sell refund: (base_cost + total_upgrades_spent) * TOWER_SELL_REFUND
tower_get_sell_refund :: proc(t: ^Tower) -> i32 {
	base_cost := tower_get_base_cost(t)
	upgrades_spent := tower_get_total_upgrade_spent(t)
	return i32(f32(base_cost + upgrades_spent) * constants.TOWER_SELL_REFUND)
}

// Upgrade manual: incrementa level y recomputa stats desde base.
// Respeta dos límites:
//   - base_level (level - enhance_bonus) < TOWER_MAX_MANUAL_LEVEL (20) para torres normales
//   - base_level < ENHANCE_MAX_LEVEL (5) para el potenciador
//   - level < TOWER_MAX_LEVEL (25) en cualquier caso
tower_upgrade :: proc(t: ^Tower) {
	if t.level >= constants.TOWER_MAX_LEVEL { return }
	manual_cap := constants.ENHANCE_MAX_LEVEL if t.type == .ENHANCE else constants.TOWER_MAX_MANUAL_LEVEL
	base_level := t.level - t.enhance_bonus
	if base_level >= manual_cap { return }
	t.level += 1
	tower_recompute_stats(t)
}

// Get critical chance: escala linealmente con el nivel
// crit = CRIT_BASE_CHANCE + TOWER_CRIT_PER_LEVEL × (level-1), máximo 75%
tower_get_critical_chance :: proc(t: ^Tower) -> f32 {
	n := f32(t.level - 1)
	chance := constants.CRIT_BASE_CHANCE + constants.TOWER_CRIT_PER_LEVEL * n
	if chance > 0.75 { chance = 0.75 }
	return chance
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
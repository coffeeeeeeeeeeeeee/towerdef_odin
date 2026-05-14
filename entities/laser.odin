package entities

import "core:math"
import "core:math/rand"
import "vendor:raylib"
import "../constants"

// Laser beam structure (for rendering)
Laser_Beam :: struct {
	start_x: f32,
	start_y: f32,
	end_x: f32,
	end_y: f32,
	duration: f32,
	max_duration: f32,
}

// Initialize laser beam
laser_beam_init :: proc(start_x, start_y, end_x, end_y: f32) -> Laser_Beam {
	return Laser_Beam{
		start_x = start_x,
		start_y = start_y,
		end_x = end_x,
		end_y = end_y,
		duration = 0.1,
		max_duration = 0.1,
	}
}

// Update laser beam
laser_beam_update :: proc(lb: ^Laser_Beam, dt: f32) -> bool {
	lb.duration -= dt
	return lb.duration <= 0
}

// Laser tower update logic
// This handles the burst firing and cooldown system
laser_tower_update :: proc(t: ^Tower, dt: f32) -> (damage_dealt: f32, beam_active: bool) {
	LASER_FIRING_DURATION :: constants.LASER_FIRING_DURATION
	
	// Decrement cooldown timer
	if t.cooldown_timer > 0 {
		t.cooldown_timer -= dt
	}
	
	// Decrement laser beam visual duration
	if t.laser_beam_duration > 0 {
		t.laser_beam_duration -= dt
	}
	
	// Start firing if not firing and not in cooldown
	if t.firing_timer <= 0 && t.cooldown_timer <= 0 && t.target != nil {
		t.firing_timer = constants.LASER_FIRING_DURATION
	}
	
	// While firing: apply damage and decrement firing timer
	if t.firing_timer > 0 {
		t.firing_timer -= dt
		
		// Calculate DPS based on damage level
		damage_multiplier := 1.0 + f32(t.damage_level - 1) * constants.LASER_DAMAGE_MULTIPLIER_PER_LEVEL
		dps := t.damage * damage_multiplier
		frame_damage := dps * dt
		
		// Keep beam visible while firing
		t.laser_beam_duration = 0.1
		
		// Accumulate damage for display numbers
		t._laser_accum += frame_damage
		t._laser_accum_timer += dt
		
		damage_dealt = frame_damage
		beam_active = true
		
		// Burst finished: enter cooldown
		if t.firing_timer <= 0 {
			t.firing_timer = 0
			// t.cooldown is already reduced by tower_upgrade_rate upgrades
			t.cooldown_timer = t.cooldown
		}
	}
	
	return
}

// Check if laser accumulated damage should be displayed
laser_should_show_damage :: proc(t: ^Tower) -> (should_show: bool, damage: f32, is_critical: bool) {
	if t._laser_accum_timer >= constants.LASER_ACCUMULATION_TIME {
		critical_chance := constants.CRIT_BASE_CHANCE + f32(t.damage_level - 1) * constants.CRIT_PER_LEVEL
		is_crit := rand.float32() < critical_chance
		
		final_damage := t._laser_accum
		if is_crit {
			bonus_damage := t._laser_accum * (constants.CRIT_DAMAGE_MULTIPLIER - 1.0)
			final_damage += bonus_damage
		}
		
		return true, final_damage, is_crit
	}
	return false, 0, false
}

// Reset laser accumulation
laser_reset_accumulation :: proc(t: ^Tower) {
	t._laser_accum = 0
	t._laser_accum_timer = 0
}
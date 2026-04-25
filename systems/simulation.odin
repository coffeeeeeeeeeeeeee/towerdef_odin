package systems

import "core:math"
import "core:fmt"
import "vendor:raylib"
import "../constants"
import "../entities"
import "../game"

// Update entire simulation
simulation_update :: proc(dt: f32) {
	if game.app.sim.paused {
		return
	}
	
	s_dt := dt * game.app.sim.speed
	
	// Update wave
	update_wave(s_dt)
	
	// Spawn enemies
	spawn_enemies(s_dt)
	
	// Update enemies
	update_enemies(s_dt)
	
	// Update towers
	update_towers(s_dt)
	
	// Update projectiles
	update_projectiles(s_dt)
	
	// Update explosions
	update_explosions(s_dt)
	
	// Update damage numbers
	update_damage_numbers(s_dt)
	
	// Update laser beams
	update_laser_beams(s_dt)
}

// Wave management
update_wave :: proc(dt: f32) {
	sim := &game.app.sim
	
	// Check if wave is complete
	if sim.enemies_spawned >= sim.enemies_to_spawn && len(sim.enemies) == 0 {
		// Start new wave
		start_next_wave()
	}
}

start_next_wave :: proc() {
	sim := &game.app.sim
	sim.wave_number += 1
	sim.enemies_spawned = 0
	sim.wave_time = 0
	
	// Determine wave type based on wave number
	sim.is_wave_boss = sim.wave_number % 5 == 0
	sim.is_wave_green = !sim.is_wave_boss && (sim.wave_number % 4 == 1)
	sim.is_wave_flying = !sim.is_wave_boss && (sim.wave_number % 4 == 2)
	sim.is_wave_blue = !sim.is_wave_boss && (sim.wave_number % 4 == 3)
	
	// Calculate enemies to spawn
	sim.enemies_to_spawn = 5 + sim.wave_number * 2
	if sim.is_wave_boss {
		sim.enemies_to_spawn = 1
	}
	
	// Reset spawn timers
	for &spawn in sim.spawns {
		spawn.enemies_spawned = 0
		spawn.enemies_to_spawn = sim.enemies_to_spawn / len(sim.spawns)
		if sim.is_wave_boss {
			spawn.enemies_to_spawn = 1
		}
		spawn.wave_time = 0
		spawn.next_spawn_delay = get_next_spawn_delay()
	}
}

get_next_spawn_delay :: proc() -> f32 {
	return 0.5 + math.rand_f32() * 1.0
}

// Spawn enemies
spawn_enemies :: proc(dt: f32) {
	sim := &game.app.sim
	
	for &spawn in sim.spawns {
		if spawn.enemies_spawned >= spawn.enemies_to_spawn {
			continue
		}
		
		spawn.wave_time += dt
		if spawn.wave_time >= spawn.next_spawn_delay {
			spawn.wave_time = 0
			spawn.next_spawn_delay = get_next_spawn_spawn_delay()
			spawn.enemies_spawned += 1
			
			is_last := spawn.enemies_spawned == spawn.enemies_to_spawn
			is_boss := sim.is_wave_boss && is_last
			
			// Calculate HP multiplier
			multiplier: f32 = 1.0
			if is_boss {
				multiplier = 10.0
			} else if sim.is_wave_green {
				multiplier = 0.5
			} else if sim.is_wave_flying {
				multiplier = 0.7
			} else if sim.is_wave_blue {
				multiplier = 1.2
			}
			
			hp := 10.0 * math.pow(constants.ENEMY_GROWTH_RATE, f32(sim.wave_number - 1)) * multiplier
			
			// Boss color cycle
			boss_color := raylib.WHITE
			if is_boss {
				boss_cycle := (sim.wave_number - 1) / 5 % 4
				switch boss_cycle {
				case 0: boss_color = constants.COLOR_ENEMY_GREEN
				case 1: boss_color = constants.COLOR_ENEMY
				case 2: boss_color = constants.COLOR_ENEMY_BOSS
				case 3: boss_color = constants.COLOR_ENEMY_BLUE
				}
			}
			
			// Speed
			speed: f32 = 1.5
			if is_boss {
				speed = 0.8
			} else if sim.is_wave_green {
				speed = 2.0
			} else if sim.is_wave_blue {
				speed = 1.3
			}
			
			enemy := entities.enemy_init(
				hp,
				speed,
				is_boss,
				sim.is_wave_flying,
				sim.is_wave_green,
				sim.is_wave_blue,
				boss_color,
			)
			
			// Copy path to enemy
			entities.enemy_set_path(&enemy, spawn.path)
			
			append(&sim.enemies, enemy)
		}
	}
}

get_next_spawn_spawn_delay :: proc() -> f32 {
	return 0.5 + math.rand_f32() * 1.0
}

// Update enemies
update_enemies :: proc(dt: f32) {
	sim := &game.app.sim
	
	for i := len(sim.enemies) - 1; i >= 0; i -= 1 {
		enemy := &sim.enemies[i]
		
		// Move along path
		reached_end := entities.enemy_move(enemy, dt)
		
		if reached_end {
			// Enemy reached goal
			damage := 1
			if enemy.is_boss {
				damage = 5
			}
			game.app_take_damage(damage)
			
			// Remove enemy
			entities.enemy_destroy(enemy)
			ordered_remove(&sim.enemies, i)
			continue
		}
		
		// Obstacle damage
		if !enemy.is_flying {
			grid_x := i32(enemy.x + 0.5)
			grid_y := i32(enemy.y + 0.5)
			
			if game.app.editor.map.obstacle_grid[grid_y][grid_x] == .OBSTACLE {
				level := entities.map_get_obstacle_level(&game.app.editor.map, grid_y, grid_x)
				damage := entities.enemy_apply_obstacle_damage(enemy, grid_x, grid_y, level)
				
				if damage > 0 {
					spawn_damage_number(enemy.x + 0.5, enemy.y + 0.5, damage, false)
				}
			}
		}
		
		// Blue enemy healing
		entities.enemy_update_healing(enemy, dt)
		
		// Check death
		if enemy.hp <= 0 {
			// Enemy died - give reward
			reward := 5
			if enemy.is_boss {
				reward = 50
			} else if enemy.is_green {
				reward = 3
			}
			game.app_add_money(reward)
			
			// Remove enemy
			entities.enemy_destroy(enemy)
			ordered_remove(&sim.enemies, i)
		}
	}
}

// Update towers
update_towers :: proc(dt: f32) {
	sim := &game.app.sim
	
	for &tower in sim.towers {
		// Update timers
		if tower.timer > 0 {
			tower.timer -= dt
		}
		
		// Find target
		target_enemy := find_target(&tower)
		tower.target = target_enemy
		
		if tower.target != nil {
			// Turn towards target
			target_angle := math.atan2(
				(tower.target.y + 0.5) - f32(tower.r + 0.5),
				(tower.target.x + 0.5) - f32(tower.c + 0.5),
			)
			entities.tower_turn_towards(&tower, target_angle, dt)
			
			// Check if aligned
			aligned := entities.tower_is_aligned(&tower, target_angle)
			
			if aligned {
				switch tower.type {
				case .LASER:
					update_laser_tower(&tower, dt)
				case .ARCHER, .CANNON, .SNIPER, .MISSILE:
					update_projectile_tower(&tower, dt)
				}
			}
		}
	}
}

// Update laser tower
update_laser_tower :: proc(tower: ^entities.Tower, dt: f32) {
	damage, beam_active := entities.laser_tower_update(tower, dt)
	
	if damage > 0 && tower.target != nil {
		tower.target.hp -= damage
		
		// Show accumulated damage
		should_show, display_damage, is_crit := entities.laser_should_show_damage(tower)
		if should_show {
			if is_crit {
				// Apply bonus critical damage
				bonus := display_damage * (constants.CRIT_DAMAGE_MULTIPLIER - 1.0)
				tower.target.hp -= bonus
			}
			spawn_damage_number(tower.target.x + 0.5, tower.target.y + 0.5, display_damage, is_crit)
			entities.laser_reset_accumulation(tower)
		}
	}
	
	if beam_active && tower.target != nil {
		// Add laser beam for rendering
		cs := f32(game.app.settings.cell_size)
		start_x, start_y := entities.tower_get_cannon_tip(tower, cs)
		end_x := tower.target.x * cs + cs / 2
		end_y := tower.target.y * cs + cs / 2
		
		beam := entities.laser_beam_init(start_x, start_y, end_x, end_y)
		append(&game.app.sim.laser_beams, beam)
	}
}

// Update projectile tower
update_projectile_tower :: proc(tower: ^entities.Tower, dt: f32) {
	sim := &game.app.sim
	
	if tower.timer <= 0 {
		tower.timer = entities.tower_get_effective_cooldown(tower)
		
		// Calculate fire position
		cs := f32(game.app.settings.cell_size)
		fire_x, fire_y := entities.tower_get_cannon_tip(tower, cs)
		
		// Adjust for different tower types
		switch tower.type {
		case .ARCHER, .CANNON, .SNIPER:
			// Standard firing
		case .MISSILE:
			// Alternate sides
			side_offset := f32(0.25 * cs)
			forward_offset := f32(0.25 * cs)
			side_angle := tower.angle
			if tower.missile_side == 0 {
				side_angle -= math.PI / 2
			} else {
				side_angle += math.PI / 2
			}
			fire_x += math.cos(side_angle) * side_offset + math.cos(tower.angle) * forward_offset
			fire_y += math.sin(side_angle) * side_offset + math.sin(tower.angle) * forward_offset
			tower.missile_side = 1 - tower.missile_side
		case .LASER:
			// Laser handled separately
		}
		
		// Create projectile
		proj_speed: f32 = 12.0
		if tower.type == .MISSILE {
			proj_speed = 5.0
		}
		
		proj := entities.projectile_init(
			fire_x / cs, fire_y / cs,  // Convert back to grid units
			tower.target,
			proj_speed,
			tower.damage,
			tower.type,
			tower.aoe,
			tower.critical_level,
		)
		
		append(&sim.projectiles, proj)
	}
}

// Find target for tower
find_target :: proc(tower: ^entities.Tower) -> ^entities.Enemy {
	sim := &game.app.sim
	
	// Build list of eligible enemies
	eligible: [dynamic]^entities.Enemy
	defer delete(eligible)
	
	for i in 0..<len(sim.enemies) {
		enemy := &sim.enemies[i]
		
		// Flying enemies can only be hit by laser and missile
		if enemy.is_flying && tower.type == .ARCHER {
			continue
		}
		
		// Check range
		dist := math.sqrt(
			math.pow(f32(tower.c) - enemy.x, 2) +
			math.pow(f32(tower.r) - enemy.y, 2),
		)
		
		if dist <= tower.range {
			append(&eligible, enemy)
			enemy._tmp_dist = dist
		}
	}
	
	if len(eligible) == 0 {
		return nil
	}
	
	// Apply targeting strategy
	target: ^entities.Enemy = nil
	
	switch tower.target_strategy {
	case .FIRST:
		target = eligible[0]
		for e in eligible[1:] {
			if e.path_idx > target.path_idx ||
			   (e.path_idx == target.path_idx && e._tmp_dist < target._tmp_dist) {
				target = e
			}
		}
	case .LAST:
		target = eligible[0]
		for e in eligible[1:] {
			if e.path_idx < target.path_idx ||
			   (e.path_idx == target.path_idx && e._tmp_dist > target._tmp_dist) {
				target = e
			}
		}
	case .MAX_HP:
		target = eligible[0]
		for e in eligible[1:] {
			if e.hp > target.hp {
				target = e
			}
		}
	case .MIN_HP:
		target = eligible[0]
		for e in eligible[1:] {
			if e.hp < target.hp {
				target = e
			}
		}
	}
	
	return target
}

// Update projectiles
update_projectiles :: proc(dt: f32) {
	sim := &game.app.sim
	
	for i := len(sim.projectiles) - 1; i >= 0; i -= 1 {
		proj := &sim.projectiles[i]
		
		// Move projectile
		hit := entities.projectile_move(proj, dt)
		
		if hit {
			// Apply damage
			if proj.target != nil {
				// Critical hit check
				is_crit := math.rand_f32() < (constants.CRIT_BASE_CHANCE + f32(proj.critical_level - 1) * constants.CRIT_PER_LEVEL)
				damage := proj.damage
				
				if is_crit {
					damage *= constants.CRIT_DAMAGE_MULTIPLIER
				}
				
				proj.target.hp -= damage
				spawn_damage_number(proj.target.x + 0.5, proj.target.y + 0.5, damage, is_crit)
				
				// AoE damage
				if proj.aoe > 0 {
					spawn_explosion(proj.x, proj.y, proj.aoe)
					
					// Damage nearby enemies
					for &enemy in sim.enemies {
						if &enemy == proj.target {
							continue
						}
						
						dist := math.sqrt(
							math.pow(enemy.x - proj.x, 2) +
							math.pow(enemy.y - proj.y, 2),
						)
						
						if dist <= proj.aoe {
							aoe_damage := proj.damage * 0.5
							if is_crit {
								aoe_damage *= constants.CRIT_DAMAGE_MULTIPLIER
							}
							enemy.hp -= aoe_damage
							spawn_damage_number(enemy.x + 0.5, enemy.y + 0.5, aoe_damage, is_crit)
						}
					}
				}
			}
			
			// Remove projectile
			ordered_remove(&sim.projectiles, i)
		}
	}
}

// Update explosions
update_explosions :: proc(dt: f32) {
	sim := &game.app.sim
	
	for i := len(sim.explosions) - 1; i >= 0; i -= 1 {
		if entities.explosion_update(&sim.explosions[i], dt) {
			ordered_remove(&sim.explosions, i)
		}
	}
}

// Update damage numbers
update_damage_numbers :: proc(dt: f32) {
	sim := &game.app.sim
	
	for i := len(sim.damage_numbers) - 1; i >= 0; i -= 1 {
		if entities.damage_number_update(&sim.damage_numbers[i], dt) {
			ordered_remove(&sim.damage_numbers, i)
		}
	}
}

// Update laser beams
update_laser_beams :: proc(dt: f32) {
	sim := &game.app.sim
	
	for i := len(sim.laser_beams) - 1; i >= 0; i -= 1 {
		if entities.laser_beam_update(&sim.laser_beams[i], dt) {
			ordered_remove(&sim.laser_beams, i)
		}
	}
}

// Spawn explosion
spawn_explosion :: proc(x, y, radius: f32) {
	explosion := entities.explosion_init(x, y, radius)
	append(&game.app.sim.explosions, explosion)
}

// Spawn damage number
spawn_damage_number :: proc(x, y, value: f32, is_critical: bool) {
	dn := entities.damage_number_init(x, y, value, is_critical)
	append(&game.app.sim.damage_numbers, dn)
}

// Toggle pause
simulation_toggle_pause :: proc() {
	game.app.sim.paused = !game.app.sim.paused
}

// Set simulation speed
simulation_set_speed :: proc(speed: f32) {
	game.app.sim.speed = speed
}

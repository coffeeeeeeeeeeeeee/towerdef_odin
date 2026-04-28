package systems

import "core:math"
import "core:math/rand"
import "core:fmt"
import "vendor:raylib"
import "../entities"
import "../constants"

// Forward declaration - App_State will be passed directly
simulation_update :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	if sim.paused {
		return
	}
	
	s_dt := dt * sim.speed
	
	// Update wave
	update_wave(app, s_dt)
	
	// Spawn enemies
	spawn_enemies(app, s_dt)
	
	// Update enemies
	update_enemies(app, s_dt)
	
	// Update towers
	update_towers(app, s_dt)
	
	// Update projectiles
	update_projectiles(app, s_dt)
	
	// Update explosions
	update_explosions(app, s_dt)
	
	// Update damage numbers
	update_damage_numbers(app, s_dt)
	
	// Update laser beams
	update_laser_beams(app, s_dt)
}

// Wave management
update_wave :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	
	// Check if wave is complete
	if sim.enemies_spawned >= sim.enemies_to_spawn && len(sim.enemies) == 0 {
		// Start new wave
		start_next_wave(app)
	}
}

start_next_wave :: proc(app: ^entities.App_State) {
	sim := &app.sim
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
		spawn.enemies_to_spawn = sim.enemies_to_spawn / i32(len(sim.spawns))
		if sim.is_wave_boss {
			spawn.enemies_to_spawn = 1
		}
		spawn.wave_time = 0
		spawn.next_spawn_delay = get_next_spawn_delay()
	}
}

get_next_spawn_delay :: proc() -> f32 {
	return 0.5 + rand.float32() * 1.0
}

// Spawn enemies
spawn_enemies :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	
	for &spawn in sim.spawns {
		if spawn.enemies_spawned >= spawn.enemies_to_spawn {
			continue
		}
		
		spawn.wave_time += dt
		if spawn.wave_time >= spawn.next_spawn_delay {
			spawn.wave_time = 0
			spawn.next_spawn_delay = get_next_spawn_spawn_delay()
			spawn.enemies_spawned += 1
			sim.enemies_spawned += 1  // Increment global counter
			
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
				case 0: 
					app.sim.money += constants.MONEY_WAVE_CLEAR
				case 1: boss_color = constants.COLOR_ENEMY
				case 2: boss_color = constants.COLOR_ENEMY_BOSS
				case 3: boss_color = constants.COLOR_ENEMY_BLUE
				}
			}
			
			// Speed
			speed: f32 = constants.ENEMY_SPEED_DEFAULT
			if is_boss {
				speed = constants.ENEMY_SPEED_BOSS
			} else if sim.is_wave_green {
				speed = constants.ENEMY_SPEED_GREEN
			} else if sim.is_wave_blue {
				speed = constants.ENEMY_SPEED_BLUE
			} else if sim.is_wave_flying {
				speed = constants.ENEMY_SPEED_FLYING
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
			
			// Set enemy path (this also sets initial position to spawn)
			entities.enemy_set_path(&enemy, spawn.path)
			
			append(&sim.enemies, enemy)
		}
	}
}

get_next_spawn_spawn_delay :: proc() -> f32 {
	return 0.5 + rand.float32() * 1.0
}

// Update enemies
update_enemies :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	
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
			entities.app_take_damage(app, i32(damage))
			
			// Remove enemy
			entities.enemy_destroy(enemy)
			ordered_remove(&sim.enemies, i)
			continue
		}
		
		// Obstacle damage
		if !enemy.is_flying {
			grid_x := i32(enemy.x + 0.5)
			grid_y := i32(enemy.y + 0.5)
			
			if app.editor.game_map.obstacle_grid[grid_y][grid_x] == .OBSTACLE {
				level := entities.map_get_obstacle_level(&app.editor.game_map, grid_y, grid_x)
				damage := entities.enemy_apply_obstacle_damage(enemy, grid_x, grid_y, level)
				
				if damage > 0 {
					spawn_damage_number(app, enemy.x + 0.5, enemy.y + 0.5, damage, false)
				}
			}
		}
		
		// Blue enemy healing
		entities.enemy_update_healing(enemy, dt)
		
		// Check death
		if enemy.hp <= 0 {
			// Enemy died - give reward
			reward := i32(5)
			if enemy.is_boss {
				reward = 50
			} else if enemy.is_green {
				reward = 3
			}
			entities.app_add_money(app, reward)
			
			// Remove enemy
			entities.enemy_destroy(enemy)
			ordered_remove(&sim.enemies, i)
		}
	}
}

// Update towers
update_towers :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	
	for &tower in sim.towers {
		_ = tower  // Use tower
		// Update timers
		if tower.timer > 0 {
			tower.timer -= dt
		}
		
		// Find target
		target_enemy := find_target(app, &tower)
		tower.target = target_enemy
		
		if tower.target != nil {
			// Turn towards target
			target_angle := math.atan2_f32(
				tower.target.y - f32(tower.r),
				tower.target.x - f32(tower.c),
			)
			entities.tower_turn_towards(&tower, target_angle, dt)
			
			// Check if aligned
			aligned := entities.tower_is_aligned(&tower, target_angle)
			
			if aligned {
				switch tower.type {
				case .LASER:
					update_laser_tower(app, &tower, dt)
				case .ARCHER, .CANNON, .SNIPER, .MISSILE:
					update_projectile_tower(app, &tower, dt)
				}
			}
		}
	}
}

// Update laser tower
update_laser_tower :: proc(app: ^entities.App_State, tower: ^entities.Tower, dt: f32) {
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
			spawn_damage_number(app, tower.target.x + 0.5, tower.target.y + 0.5, display_damage, is_crit)
			entities.laser_reset_accumulation(tower)
		}
	}
	
	if beam_active && tower.target != nil {
		// Add laser beam for rendering
		cs := f32(app.settings.cell_size)
		start_x, start_y := entities.tower_get_cannon_tip(tower, cs)
		end_x := tower.target.x * cs + cs / 2
		end_y := tower.target.y * cs + cs / 2
		
		beam := entities.laser_beam_init(start_x, start_y, end_x, end_y)
		append(&app.sim.laser_beams, beam)
	}
}

// Update projectile tower
update_projectile_tower :: proc(app: ^entities.App_State, tower: ^entities.Tower, dt: f32) {
	sim := &app.sim
	
	if tower.timer <= 0 {
		tower.timer = entities.tower_get_effective_cooldown(tower)
		
		// Calculate fire position
		cs := f32(app.settings.cell_size)
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
			fire_x += math.cos_f32(side_angle) * side_offset
			fire_y += math.sin_f32(side_angle) * side_offset
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
			.FIRST,  // target_strategy
			tower.type,
			tower.aoe,
			tower.critical_level,
		)
		
		append(&sim.projectiles, proj)
	}
}

// Find target for tower
find_target :: proc(app: ^entities.App_State, tower: ^entities.Tower) -> ^entities.Enemy {
	sim := &app.sim
	
	// Build list of eligible enemies
	eligible: [dynamic]^entities.Enemy
	defer delete(eligible)
	
	for i in 0..<len(sim.enemies) {
		enemy := &sim.enemies[i]
		
		// Check if enemy is in range
		dx := (enemy.x + 0.5) - (f32(tower.c) + 0.5)
		dy := (enemy.y + 0.5) - (f32(tower.r) + 0.5)
		dist := math.sqrt_f32(dx*dx + dy*dy)
		
		if dist <= tower.range {
			// CANNON and SNIPER cannot target flying enemies
			// Only ARCHER, MISSILE, and LASER can target flying enemies
			can_target_flying := tower.type == .ARCHER || tower.type == .MISSILE || tower.type == .LASER
			if !enemy.is_flying || can_target_flying {
				append(&eligible, enemy)
			}
		}
	}
	
	if len(eligible) == 0 {
		return nil
	}
	
	// Find enemy closest to tower
	best_enemy := eligible[0]
	best_dist := f32(i32(len(best_enemy.path)) - best_enemy.path_idx)
	
	// Calculate distance from tower to this enemy
	dx := (best_enemy.x + 0.5) - (f32(tower.c) + 0.5)
	dy := (best_enemy.y + 0.5) - (f32(tower.r) + 0.5)
	best_dist = math.sqrt_f32(dx*dx + dy*dy)
	
	for i in 1..<len(eligible) {
		enemy := eligible[i]
		// Calculate distance from tower to this enemy
		dx := (enemy.x + 0.5) - (f32(tower.c) + 0.5)
		dy := (enemy.y + 0.5) - (f32(tower.r) + 0.5)
		dist := math.sqrt_f32(dx*dx + dy*dy)
		
		if dist < best_dist {
			best_dist = dist
			best_enemy = enemy
		}
	}
	
	return best_enemy
}

// Update projectiles
update_projectiles :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	
	for i := len(sim.projectiles) - 1; i >= 0; i -= 1 {
		proj := &sim.projectiles[i]
		
		// Move projectile
		hit := entities.projectile_move(proj, dt)
		
		if hit {
			// Apply damage
			if proj.target != nil {
				// Critical hit check
				is_crit := rand.float32() < (constants.CRIT_BASE_CHANCE + f32(proj.critical_level - 1) * constants.CRIT_PER_LEVEL)
				damage := proj.damage
				
				if is_crit {
					damage *= constants.CRIT_DAMAGE_MULTIPLIER
				}
				
				proj.target.hp -= damage
				spawn_damage_number(app, proj.target.x + 0.5, proj.target.y + 0.5, damage, is_crit)
				
				// AoE damage
				if proj.aoe > 0 {
					spawn_explosion(app, proj.x, proj.y, proj.aoe)
					
					// Damage nearby enemies
					for &enemy in sim.enemies {
						if &enemy == proj.target {
							continue
						}
						
						dx := enemy.x - proj.x
						dy := enemy.y - proj.y
						dist := math.sqrt_f32(dx*dx + dy*dy)
						
						if dist <= proj.aoe {
							aoe_damage := proj.damage * 0.5
							if is_crit {
								bonus_damage := proj.damage * (constants.CRIT_DAMAGE_MULTIPLIER - 1.0)
								aoe_damage += bonus_damage
							}
							enemy.hp -= aoe_damage
							spawn_damage_number(app, enemy.x + 0.5, enemy.y + 0.5, aoe_damage, is_crit)
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
update_explosions :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	
	for i := len(sim.explosions) - 1; i >= 0; i -= 1 {
		if entities.explosion_update(&sim.explosions[i], dt) {
			ordered_remove(&sim.explosions, i)
		}
	}
}

// Update damage numbers
update_damage_numbers :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	
	for i := len(sim.damage_numbers) - 1; i >= 0; i -= 1 {
		if entities.damage_number_update(&sim.damage_numbers[i], dt) {
			ordered_remove(&sim.damage_numbers, i)
		}
	}
}

// Update laser beams
update_laser_beams :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	
	for i := len(sim.laser_beams) - 1; i >= 0; i -= 1 {
		if entities.laser_beam_update(&sim.laser_beams[i], dt) {
			ordered_remove(&sim.laser_beams, i)
		}
	}
}

// Spawn explosion
spawn_explosion :: proc(app: ^entities.App_State, x, y, radius: f32) {
	explosion := entities.explosion_init(x, y, radius)
	append(&app.sim.explosions, explosion)
}

// Spawn damage number
spawn_damage_number :: proc(app: ^entities.App_State, x, y, value: f32, is_critical: bool) {
	dn := entities.damage_number_init(x, y, value, is_critical)
	append(&app.sim.damage_numbers, dn)
}

// Toggle pause
simulation_toggle_pause :: proc(app: ^entities.App_State) {
	app.sim.paused = !app.sim.paused
}

// Cleanup simulation
simulation_cleanup :: proc(app: ^entities.App_State) {
	// Free enemies
	for &e in app.sim.enemies {
		entities.enemy_destroy(&e)
	}
	
	if len(app.sim.towers) > 0 {
		delete(app.sim.towers)
	}
	if len(app.sim.enemies) > 0 {
		delete(app.sim.enemies)
	}
	if len(app.sim.projectiles) > 0 {
		delete(app.sim.projectiles)
	}
	if len(app.sim.explosions) > 0 {
		delete(app.sim.explosions)
	}
	if len(app.sim.damage_numbers) > 0 {
		delete(app.sim.damage_numbers)
	}
	if len(app.sim.laser_beams) > 0 {
		delete(app.sim.laser_beams)
	}
	if len(app.sim.spawns) > 0 {
		delete(app.sim.spawns)
	}
}

// Reset simulation
simulation_reset :: proc(app: ^entities.App_State) {
	// Clear old data
	simulation_cleanup(app)
	
	// Initialize new simulation
	app.sim = entities.Simulation{
		towers = make([dynamic]entities.Tower),
		enemies = make([dynamic]entities.Enemy),
		projectiles = make([dynamic]entities.Projectile),
		explosions = make([dynamic]entities.Explosion),
		damage_numbers = make([dynamic]entities.Damage_Number),
		laser_beams = make([dynamic]entities.Laser_Beam),
		spawns = make([dynamic]entities.Spawn_Point),
		money = constants.DEFAULT_MONEY,
		health = constants.DEFAULT_HEALTH,
		wave_number = 1,
		speed = 1.0,
		paused = false,
		started = false,
		enemies_to_spawn = 0,
		enemies_spawned = 0,
		wave_time = 0,
		next_spawn_delay = 0,
		is_wave_boss = false,
		is_wave_green = false,
		is_wave_flying = false,
		is_wave_blue = false,
	}
}

// Set simulation speed
simulation_set_speed :: proc(app: ^entities.App_State, speed: f32) {
	app.sim.speed = speed
}

// Initialize simulation from editor map
simulation_init_from_editor :: proc(app: ^entities.App_State) -> bool {
	simulation_reset(app)
	
	// Copy towers from editor grid
	for row in 0..<constants.GRID_SIZE {
		for col in 0..<constants.GRID_SIZE {
			tile := app.editor.game_map.grid[row][col]
			
			#partial switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
				// Convert tile to tower type
				tower_type: constants.Tower_Type
				#partial switch tile {
				case .TOWER_ARCHER: tower_type = .ARCHER
				case .TOWER_CANNON: tower_type = .CANNON
				case .TOWER_SNIPER: tower_type = .SNIPER
				case .TOWER_MISSILE: tower_type = .MISSILE
				case .TOWER_LASER: tower_type = .LASER
				case: tower_type = .ARCHER
				}
				tower := entities.tower_init(tower_type, i32(row), i32(col))
				append(&app.sim.towers, tower)
				
			case .SPAWN:
				// Find path from spawn to goal
				goal_row, goal_col, found := entities.map_find_goal(&app.editor.game_map)
				if !found {
					return false
				}
				
				// Create spawn point
				spawn := entities.Spawn_Point{
					r = i32(row),
					c = i32(col),
					enemies_to_spawn = 0,
					enemies_spawned = 0,
					wave_time = 0,
					next_spawn_delay = 0,
				}
				
				// Calculate path using BFS
				spawn.path = entities.map_find_path_bfs(&app.editor.game_map, i32(row), i32(col), goal_row, goal_col, false)
				
				// Only add spawn if path was found
				if len(spawn.path) > 0 {
					append(&app.sim.spawns, spawn)
				}
			}
		}
	}
	
	return len(app.sim.spawns) > 0
}

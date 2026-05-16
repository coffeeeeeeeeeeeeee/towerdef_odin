package systems

import "../constants"
import "../entities"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "vendor:raylib"

// Forward declaration - App_State will be passed directly
simulation_update :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	if sim.paused {
		return
	}

	s_dt := dt * sim.speed

	// Track play time
	sim.play_time += s_dt

	// Sample data for game-over graph (~2 samples/sec)
	sim._sample_timer += s_dt
	if sim._sample_timer >= 0.5 {
		sim._sample_timer -= 0.5
		append(
			&sim.graph_samples,
			entities.Graph_Sample{time = sim.play_time, money = sim.money, health = sim.health},
		)
	}

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

	// Update ice pulses
	update_ice_pulses(app, s_dt)
}

// Wave management
update_wave :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim

	// Check if wave is complete: game must have started, all enemies spawned AND cleared,
	// and enemies_to_spawn > 0 to avoid triggering before the first wave is launched.
	if sim.started && sim.enemies_to_spawn > 0 &&
	   sim.enemies_spawned >= sim.enemies_to_spawn && len(sim.enemies) == 0 {
		if app.settings.auto_start_wave {
			start_next_wave(app)
		}
	}
}

start_next_wave :: proc(app: ^entities.App_State) {
	sim := &app.sim

	// Interest bonus: reward the player for saving money between waves
	if sim.wave_number > 0 {
		interest := i32(f32(sim.money) * constants.INTEREST_RATE)
		if interest > 0 {
			entities.app_add_money(app, interest)
			entities.add_toast(app, fmt.tprintf("+$%d interés", interest), .INFO)
		}
	}

	sim.started = true  // Mark game as started
	sim.wave_number += 1
	sim.enemies_spawned = 0
	sim.wave_time = 0

	// Determine wave type based on wave number.
	sim.is_wave_boss  = sim.wave_number % constants.BOSS_WAVE_INTERVAL == 0

	// Bonus wave: random chance on any non-boss wave (all sub-type abilities combined).
	sim.is_wave_bonus = !sim.is_wave_boss && rand.float32() < constants.BONUS_WAVE_CHANCE

	// Sub-types: on bonus waves all flags are active; on normal waves rotate by wave number.
	if sim.is_wave_bonus {
		sim.is_wave_green  = true
		sim.is_wave_flying = true
		sim.is_wave_blue   = true
		sim.is_wave_split  = true
	} else {
		sim.is_wave_green  = !sim.is_wave_boss && sim.wave_number % 4 == 1
		sim.is_wave_flying = !sim.is_wave_boss && sim.wave_number % 4 == 2
		sim.is_wave_blue   = !sim.is_wave_boss && sim.wave_number % 4 == 3
		sim.is_wave_split  = !sim.is_wave_boss && sim.wave_number % 4 == 0
	}

	// Record wave marker for graph
	append(
		&sim.wave_marks,
		entities.Wave_Mark {
			time      = sim.play_time,
			wave      = sim.wave_number,
			is_boss   = sim.is_wave_boss,
			is_green  = sim.is_wave_green,
			is_flying = sim.is_wave_flying,
			is_blue   = sim.is_wave_blue,
			is_split  = sim.is_wave_split,
			is_bonus  = sim.is_wave_bonus,
		},
	)

	// Calculate enemies to spawn
	if sim.is_wave_boss {
		sim.enemies_to_spawn = 1
	} else if sim.is_wave_bonus {
		sim.enemies_to_spawn = constants.BONUS_WAVE_ENEMY_COUNT
	} else {
		sim.enemies_to_spawn = 5 + sim.wave_number * 2
	}

	// Reset spawn timers
	for i in 0 ..< len(sim.spawns) {
		spawn := &sim.spawns[i]
		spawn.enemies_spawned = 0

		if sim.is_wave_boss {
			if i == 0 {
				spawn.enemies_to_spawn = 1
			} else {
				spawn.enemies_to_spawn = 0
			}
		} else {
			base := sim.enemies_to_spawn / i32(len(sim.spawns))
			extra: i32 = 0
			if i32(i) < sim.enemies_to_spawn % i32(len(sim.spawns)) {
				extra = 1
			}
			spawn.enemies_to_spawn = base + extra
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
			sim.enemies_spawned += 1 // Increment global counter

			is_last := spawn.enemies_spawned == spawn.enemies_to_spawn
			is_boss := sim.is_wave_boss && is_last

			// Calculate HP multiplier
			multiplier: f32
			if is_boss {
				multiplier = constants.ENEMY_HEALTH_BOSS
			} else if sim.is_wave_bonus {
				multiplier = constants.ENEMY_HEALTH_BONUS
			} else if sim.is_wave_green {
				multiplier = constants.ENEMY_HEALTH_GREEN
			} else if sim.is_wave_flying {
				multiplier = constants.ENEMY_HEALTH_FLYING
			} else if sim.is_wave_blue {
				multiplier = constants.ENEMY_HEALTH_BLUE
			} else {
				multiplier = constants.ENEMY_HEALTH_DEFAULT
			}

			hp :=
				constants.ENEMY_BASE_HP *
				math.pow(constants.ENEMY_GROWTH_RATE, f32(sim.wave_number - 1)) *
				multiplier *
				constants.ENEMY_GLOBAL_HP_MULTIPLIER

			// Speed — bonus enemies use their own speed constant
			speed: f32
			if sim.is_wave_bonus {
				speed = constants.ENEMY_SPEED_BONUS
			} else if sim.is_wave_green {
				speed = constants.ENEMY_SPEED_GREEN
			} else if sim.is_wave_blue {
				speed = constants.ENEMY_SPEED_BLUE
			} else if sim.is_wave_flying {
				speed = constants.ENEMY_SPEED_FLYING
			} else {
				speed = constants.ENEMY_SPEED_DEFAULT
			}

			speed *= constants.ENEMY_GLOBAL_SPEED_MULTIPLIER

			enemy := entities.enemy_init(
				hp,
				speed,
				is_boss,
				sim.is_wave_flying,
				sim.is_wave_green,
				sim.is_wave_blue,
				raylib.WHITE,
				sim.is_wave_bonus,
			)
			enemy.is_split = sim.is_wave_split

			// Set enemy path (this also sets initial position to spawn)
			entities.enemy_set_path(&enemy, spawn.path)

			append(&sim.enemies, enemy)
		}
	}
}

get_next_spawn_spawn_delay :: proc() -> f32 {
	return 0.5 + rand.float32() * 1.0
}

// Limpia las referencias de proyectiles que apuntaban a un enemigo que va a ser removido.
// Debe llamarse ANTES de ordered_remove para que el puntero siga siendo válido.
// El proyectil queda con target = nil y continúa hacia la última posición conocida.
nullify_projectile_targets :: proc(sim: ^entities.Simulation, dying_enemy: ^entities.Enemy) {
	for &proj in sim.projectiles {
		if proj.target == dying_enemy {
			// Captura la posición final antes de perder el puntero
			proj.target_last_x = dying_enemy.x
			proj.target_last_y = dying_enemy.y
			proj.target        = nil
		}
	}
}

// Update enemies
update_enemies :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim

	// Collect split children to spawn after the main loop to avoid invalidating indices
	split_children: [dynamic]entities.Enemy
	defer delete(split_children)

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

			// Invalida punteros de proyectiles antes de remover
			nullify_projectile_targets(sim, enemy)

			// Remove enemy
			entities.enemy_destroy(enemy)
			ordered_remove(&sim.enemies, i)
			continue
		}

		// Obstacle damage
		if !enemy.is_flying {
			grid_x := i32(enemy.x + 0.5)
			grid_y := i32(enemy.y + 0.5)

			if grid_x >= 0 && grid_x < app.editor.game_map.width &&
			   grid_y >= 0 && grid_y < app.editor.game_map.height &&
			   app.editor.game_map.obstacle_grid[grid_y][grid_x] == .OBSTACLE {
				level := entities.map_get_obstacle_level(&app.editor.game_map, grid_y, grid_x)
				damage := entities.enemy_apply_obstacle_damage(enemy, grid_x, grid_y, level)

				if damage > 0 {
					spawn_damage_number(app, enemy.x + 0.5, enemy.y + 0.5, damage, false)
				}
			}
		}

		// Blue enemy healing
		entities.enemy_update_healing(enemy, dt)

		// Slow effect tick
		entities.enemy_update_slow(enemy, dt)

		// Check death
		if enemy.hp <= 0 {
			// Enemy died - give reward
			reward := i32(5)
			if enemy.is_boss {
				reward = 50
			} else if enemy.is_green {
				reward = 3
			}
			if enemy.is_bonus {
				reward += constants.ENEMY_REWARD_BONUS
			}
			entities.app_add_money(app, reward)
			sim.enemies_killed += 1
			sim.money_earned += reward

			// Split: parent has is_split=true; children are created with is_split=false so they don't split again.
			// Children of bonus enemies keep sub-type flags but NOT is_bonus (no extra gold).
			if enemy.is_split && !enemy.is_boss {
				for _ in 0 ..< 2 {
					child_hp := enemy.max_hp * constants.SPLIT_HP_RATIO
					child := entities.enemy_init(
						child_hp,
						enemy.speed * constants.SPLIT_SPEED_MULT,
						false,
						enemy.is_flying,
						enemy.is_green,
						enemy.is_blue,
						enemy.boss_color,
						false, // is_bonus: children no dan gold extra
					)
					// Resume from where the parent is in the path
					child_path := enemy.path[int(enemy.path_idx):]
					entities.enemy_set_path_slice(&child, child_path)
					child.x = enemy.x
					child.y = enemy.y
					append(&split_children, child)
				}
			}

			// Invalida punteros de proyectiles antes de remover
			nullify_projectile_targets(sim, enemy)

			// Remove enemy
			entities.enemy_destroy(enemy)
			ordered_remove(&sim.enemies, i)
		}
	}

	// Append split children now that iteration is done
	// (wave completion uses len(sim.enemies)==0, so no counter adjustment needed)
	for child in split_children {
		append(&sim.enemies, child)
	}
}

// Update towers
update_towers :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim

	for &tower in sim.towers {
		_ = tower // Use tower
		// Update timers
		if tower.timer > 0 {
			tower.timer -= dt
		}

		// ICE tower: AoE pulse-based slow — no targeting or barrel rotation needed
		if tower.type == .ICE {
			update_ice_tower(app, &tower)
			continue
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
				case .ICE:
					// Handled above via continue
				}
			}
		}
	}
}

// Update ice tower — pulses AoE slow when cooldown expires
update_ice_tower :: proc(app: ^entities.App_State, tower: ^entities.Tower) {
	if tower.timer > 0 {
		return
	}
	tower.timer = entities.tower_get_effective_cooldown(tower)

	// Slow + damage all enemies in range (ground + flying)
	crit_chance := constants.CRIT_BASE_CHANCE + f32(tower.critical_level - 1) * constants.CRIT_PER_LEVEL
	for &enemy in app.sim.enemies {
		dx := (enemy.x + 0.5) - (f32(tower.c) + 0.5)
		dy := (enemy.y + 0.5) - (f32(tower.r) + 0.5)
		dist := math.sqrt_f32(dx * dx + dy * dy)
		if dist <= tower.range {
			entities.enemy_apply_slow(&enemy, constants.ICE_SLOW_FACTOR, constants.ICE_SLOW_DURATION)

			// Apply damage per pulse
			is_crit := rand.float32() < crit_chance
			dmg := tower.damage
			if is_crit {
				dmg *= constants.CRIT_DAMAGE_MULTIPLIER
			}
			enemy.hp -= dmg
			tower.total_damage += dmg
			spawn_damage_number(app, enemy.x + 0.5, enemy.y + 0.5, dmg, is_crit)
		}
	}

	// Spawn expanding ring visual at tower center
	pulse := entities.ice_pulse_init(
		f32(tower.c) + 0.5,
		f32(tower.r) + 0.5,
		tower.range,
	)
	append(&app.sim.ice_pulses, pulse)
}

// Update laser tower
update_laser_tower :: proc(app: ^entities.App_State, tower: ^entities.Tower, dt: f32) {
	damage, beam_active := entities.laser_tower_update(tower, dt)

	if damage > 0 && tower.target != nil {
		tower.target.hp -= damage
		tower.total_damage += damage

		// Show accumulated damage
		should_show, display_damage, is_crit := entities.laser_should_show_damage(tower)
		if should_show {
			if is_crit {
				// Apply bonus critical damage
				bonus := display_damage * (constants.CRIT_DAMAGE_MULTIPLIER - 1.0)
				tower.target.hp -= bonus
				tower.total_damage += bonus
			}
			spawn_damage_number(
				app,
				tower.target.x + 0.5,
				tower.target.y + 0.5,
				display_damage,
				is_crit,
			)
			entities.laser_reset_accumulation(tower)
		}
	}

	if beam_active && tower.target != nil {
		// Add laser beam for rendering (in grid coordinates)
		// Cannon tip in grid units
		cannon_length: f32 = 0.45 // Same as tower_get_cannon_tip but in grid units
		start_x := f32(tower.c) + 0.5 + math.cos(tower.angle) * cannon_length
		start_y := f32(tower.r) + 0.5 + math.sin(tower.angle) * cannon_length
		// Target center in grid units
		end_x := tower.target.x + 0.5
		end_y := tower.target.y + 0.5

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

		// Create projectile
		proj_speed: f32 = 12.0

		fire_gx, fire_gy: f32
		if tower.type == .MISSILE {
			proj_speed = 5.0
			// Alternate between left (0) and right (1) pod
			cx := f32(tower.c) + 0.5
			cy := f32(tower.r) + 0.5
			aim_angle := math.atan2(
				tower.target.y + 0.5 - cy,
				tower.target.x + 0.5 - cx,
			)
			fire_gx, fire_gy = entities.missile_barrel_spawn_pos(cx, cy, aim_angle, tower.missile_side)
			tower.missile_side = (tower.missile_side + 1) % 2
		} else {
			fire_x, fire_y := entities.tower_get_cannon_tip(tower, cs)
			fire_gx = fire_x / cs
			fire_gy = fire_y / cs
		}

		proj := entities.projectile_init(
			fire_gx,
			fire_gy,
			tower.target,
			proj_speed,
			tower.damage,
			.FIRST, // target_strategy
			tower.type,
			tower.aoe,
			tower.critical_level,
			tower.r,
			tower.c,
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

	for i in 0 ..< len(sim.enemies) {
		enemy := &sim.enemies[i]

		// Check if enemy is in range
		dx := (enemy.x + 0.5) - (f32(tower.c) + 0.5)
		dy := (enemy.y + 0.5) - (f32(tower.r) + 0.5)
		dist := math.sqrt_f32(dx * dx + dy * dy)

		if dist <= tower.range {
			// CANNON and SNIPER cannot target flying enemies
			// Only ARCHER, MISSILE, and LASER can target flying enemies
			can_target_flying :=
				tower.type == .ARCHER || tower.type == .MISSILE || tower.type == .LASER
			if !enemy.is_flying || can_target_flying {
				append(&eligible, enemy)
			}
		}
	}

	if len(eligible) == 0 {
		return nil
	}

	// Sort based on target strategy
	best_enemy := eligible[0]

	switch tower.target_strategy {
	case .FIRST:
		// Enemy closest to goal (furthest along path)
		best_progress := best_enemy.path_idx
		for i in 1 ..< len(eligible) {
			enemy := eligible[i]
			if enemy.path_idx > best_progress {
				best_progress = enemy.path_idx
				best_enemy = enemy
			}
		}

	case .LAST:
		// Enemy furthest from goal (least along path)
		best_progress := best_enemy.path_idx
		for i in 1 ..< len(eligible) {
			enemy := eligible[i]
			if enemy.path_idx < best_progress {
				best_progress = enemy.path_idx
				best_enemy = enemy
			}
		}

	case .MAX_HP:
		// Enemy with most HP
		best_hp := best_enemy.hp
		for i in 1 ..< len(eligible) {
			enemy := eligible[i]
			if enemy.hp > best_hp {
				best_hp = enemy.hp
				best_enemy = enemy
			}
		}

	case .MIN_HP:
		// Enemy with least HP
		best_hp := best_enemy.hp
		for i in 1 ..< len(eligible) {
			enemy := eligible[i]
			if enemy.hp < best_hp {
				best_hp = enemy.hp
				best_enemy = enemy
			}
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
			is_crit :=
				rand.float32() <
				(constants.CRIT_BASE_CHANCE + f32(proj.critical_level - 1) * constants.CRIT_PER_LEVEL)
			damage := proj.damage
			if is_crit {
				damage *= constants.CRIT_DAMAGE_MULTIPLIER
			}

			// Find source tower for damage attribution
			source_tower: ^entities.Tower = nil
			if proj.source_r >= 0 {
				for &t in sim.towers {
					if t.r == proj.source_r && t.c == proj.source_c {
						source_tower = &t
						break
					}
				}
			}

			if proj.target != nil {
				// Objetivo vivo: aplica daño directo
				proj.target.hp -= damage
				if source_tower != nil { source_tower.total_damage += damage }
				spawn_damage_number(app, proj.target.x + 0.5, proj.target.y + 0.5, damage, is_crit)
			}

			// AoE: se activa siempre al impactar, haya o no objetivo vivo.
			// Esto genera la explosión "en el suelo" cuando el objetivo murió antes de ser alcanzado.
			if proj.aoe > 0 {
				spawn_explosion(app, proj.x, proj.y, proj.aoe)

				for &enemy in sim.enemies {
					if proj.target != nil && &enemy == proj.target {
						continue // El objetivo principal ya recibió daño directo
					}

					dx := enemy.x - proj.x
					dy := enemy.y - proj.y
					dist := math.sqrt_f32(dx * dx + dy * dy)

					if dist <= proj.aoe {
						aoe_damage := proj.damage * 0.5
						if is_crit {
							aoe_damage *= constants.CRIT_DAMAGE_MULTIPLIER
						}
						enemy.hp -= aoe_damage
						if source_tower != nil { source_tower.total_damage += aoe_damage }
						spawn_damage_number(
							app,
							enemy.x + 0.5,
							enemy.y + 0.5,
							aoe_damage,
							is_crit,
						)
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

// Update ice pulses (expanding ring animation)
update_ice_pulses :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	for i := len(sim.ice_pulses) - 1; i >= 0; i -= 1 {
		if entities.ice_pulse_update(&sim.ice_pulses[i], dt) {
			ordered_remove(&sim.ice_pulses, i)
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

// Set pause state explicitly
simulation_set_pause :: proc(app: ^entities.App_State, paused: bool) {
	app.sim.paused = paused
}

// Remove tower at position and refund money
simulation_remove_tower_at :: proc(app: ^entities.App_State, row, col: i32) -> bool {
	for i := 0; i < len(app.sim.towers); i += 1 {
		tower := &app.sim.towers[i]
		if tower.r == row && tower.c == col {
			// Calculate refund
			refund := entities.tower_get_sell_refund(tower)
			app.sim.money += refund

			// Remove from grid
			app.editor.game_map.grid[row][col] = .EMPTY

			// Remove from towers array
			ordered_remove(&app.sim.towers, i)

			// Deselect tower
			entities.app_deselect_tower(app)

			return true
		}
	}
	return false
}

// Cleanup simulation
simulation_cleanup :: proc(app: ^entities.App_State) {
	// Free enemies
	for &e in app.sim.enemies {
		entities.enemy_destroy(&e)
	}

	delete(app.sim.towers)
	delete(app.sim.enemies)
	delete(app.sim.projectiles)
	delete(app.sim.explosions)
	delete(app.sim.damage_numbers)
	delete(app.sim.laser_beams)
	delete(app.sim.ice_pulses)
	for &spawn in app.sim.spawns {
		delete(spawn.path)
	}
	delete(app.sim.spawns)
	delete(app.sim.graph_samples)
	delete(app.sim.wave_marks)
}

// Reset simulation
simulation_reset :: proc(app: ^entities.App_State) {
	// Clear old data
	simulation_cleanup(app)

	// Clear selected tower so it doesn't point into freed memory (Bug #2)
	entities.app_deselect_tower(app)

	// Initialize new simulation
	app.sim = entities.Simulation {
		towers           = make([dynamic]entities.Tower),
		enemies          = make([dynamic]entities.Enemy),
		projectiles      = make([dynamic]entities.Projectile),
		explosions       = make([dynamic]entities.Explosion),
		damage_numbers   = make([dynamic]entities.Damage_Number),
		laser_beams      = make([dynamic]entities.Laser_Beam),
		ice_pulses       = make([dynamic]entities.Ice_Pulse),
		spawns           = make([dynamic]entities.Spawn_Point),
		money            = constants.DEFAULT_MONEY,
		health           = constants.DEFAULT_HEALTH,
		wave_number      = 0,
		speed            = 1.0,
		paused           = false,
		started          = false,
		enemies_to_spawn = 0,
		enemies_spawned  = 0,
		wave_time        = 0,
		next_spawn_delay = 0,
		is_wave_boss     = false,
		is_wave_green    = false,
		is_wave_flying   = false,
		is_wave_blue     = false,
		is_wave_split    = false,
		enemies_killed   = 0,
		money_earned     = 0,
		towers_built     = 0,
		upgrades_bought  = 0,
		play_time        = 0,
		graph_samples    = make([dynamic]entities.Graph_Sample),
		wave_marks       = make([dynamic]entities.Wave_Mark),
		_sample_timer    = 0,
	}
}

// Set simulation speed
simulation_set_speed :: proc(app: ^entities.App_State, speed: f32) {
	app.sim.speed = speed
}

// Initialize simulation from editor map
simulation_init_from_editor :: proc(app: ^entities.App_State) -> bool {
	simulation_reset(app)

	// Copy towers from editor grid (use actual map dimensions)
	for row in 0 ..< app.editor.game_map.height {
		for col in 0 ..< app.editor.game_map.width {
			tile := app.editor.game_map.grid[row][col]

			#partial switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER, .TOWER_ICE:
				// Convert tile to tower type
				tower_type: constants.Tower_Type
				#partial switch tile {
				case .TOWER_ARCHER:
					tower_type = .ARCHER
				case .TOWER_CANNON:
					tower_type = .CANNON
				case .TOWER_SNIPER:
					tower_type = .SNIPER
				case .TOWER_MISSILE:
					tower_type = .MISSILE
				case .TOWER_LASER:
					tower_type = .LASER
				case .TOWER_ICE:
					tower_type = .ICE
				case:
					tower_type = .ARCHER
				}
				tower := entities.tower_init(tower_type, i32(row), i32(col))
				append(&app.sim.towers, tower)
				app.sim.towers_built += 1

			case .SPAWN:
				// Find path from spawn to goal
				goal_row, goal_col, found := entities.map_find_goal(&app.editor.game_map)
				if !found {
					return false
				}

				// Create spawn point
				spawn := entities.Spawn_Point {
					r                = i32(row),
					c                = i32(col),
					enemies_to_spawn = 0,
					enemies_spawned  = 0,
					wave_time        = 0,
					next_spawn_delay = 0,
				}

				// Calculate path using BFS
				spawn.path = entities.map_find_path_bfs(
					&app.editor.game_map,
					i32(row),
					i32(col),
					goal_row,
					goal_col,
					false,
				)

				// Only add spawn if path was found
				if len(spawn.path) > 0 {
					append(&app.sim.spawns, spawn)
				}
			}
		}
	}

	return len(app.sim.spawns) > 0
}
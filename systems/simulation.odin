package systems

import "../constants"
import "../entities"
import "core:fmt"
import "core:math"
import "core:math/rand"

// Forward declaration - App_State will be passed directly
simulation_update :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	if sim.paused {
		return
	}

	s_dt := dt * sim.speed

	// Tick relic flash timers
	for kind in entities.Card_Kind {
		if sim.relic_flash_timers[kind] > 0 {
			sim.relic_flash_timers[kind] -= s_dt
			if sim.relic_flash_timers[kind] < 0 { sim.relic_flash_timers[kind] = 0 }
		}
	}

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

	// Recalcular bonus de torres ENHANCE (inmediato, aditivo, sin cooldown)
	update_enhance_bonuses(app)

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

	// Auto-upgrade: cada AUTO_UPGRADE_INTERVAL actualiza las torres más baratas
	if sim.relic_stacks[.AUTO_UPGRADE] > 0 && sim.started {
		sim.auto_upgrade_timer -= s_dt
		if sim.auto_upgrade_timer <= 0 {
			sim.auto_upgrade_timer = constants.AUTO_UPGRADE_INTERVAL
			update_auto_upgrade(app)
		}
	}
}

// Wave management
update_wave :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim

	// Check if wave is complete: game must have started, all enemies spawned AND cleared,
	// and enemies_to_spawn > 0 to avoid triggering before the first wave is launched.
	if sim.started && sim.enemies_to_spawn > 0 &&
	   sim.enemies_spawned >= sim.enemies_to_spawn && len(sim.enemies) == 0 {
		if sim.wave_number >= constants.MAX_WAVE {
			sim.is_victory = app.sim.health > 0
			entities.app_set_state(app, .GAME_OVER)
		} else {
			// STEAL: roba cartas al terminar la oleada, independientemente del auto_start.
			// steal_last_wave evita que se dispare más de una vez por oleada.
			if sim.relic_stacks[.STEAL] > 0 && sim.steal_last_wave < sim.wave_number {
				sim.steal_last_wave = sim.wave_number
				cards_stolen := sim.relic_stacks[.STEAL] * constants.STEAL_CARDS_PER_STACK
				for _ in 0 ..< cards_stolen {
					entities.deck_draw_one(sim)
				}
				entities.add_toast(app, fmt.tprintf("+%d carta(s) robada(s)", cards_stolen), .INFO)
				relic_flash(sim, .STEAL)
			}

			if app.settings.auto_start_wave && !sim.card_selection_active {
				// Esperar INTER_WAVE_DELAY segundos antes de iniciar la siguiente oleada.
				// La tienda abre su propio pausa — el timer se congela mientras está activa.
				if sim.inter_wave_timer <= 0 {
					sim.inter_wave_timer = constants.INTER_WAVE_DELAY
				}
				sim.inter_wave_timer -= dt
				if sim.inter_wave_timer <= 0 {
					sim.inter_wave_timer = 0
					start_next_wave(app)
				}
			}
		}
	}
}

start_next_wave :: proc(app: ^entities.App_State) {
	sim := &app.sim

	// Wave complete SFX (not on the very first wave start)
	if sim.wave_number > 0 {
		play_sound(.WAVE_COMPLETE, .SFX)
	}

	if sim.wave_number > 0 {
		// Dividend: devuelve un % del dinero gastado durante la oleada anterior
		if sim.relic_stacks[.DIVIDEND] > 0 {
			spent    := max(0, sim.wave_start_money - sim.money)
			dividend := i32(f32(spent) * constants.DIVIDEND_RATE * f32(sim.relic_stacks[.DIVIDEND]))
			if dividend > 0 {
				entities.app_add_money(app, dividend)
				entities.add_toast(app, fmt.tprintf("+$%d dividendo", dividend), .INFO)
				relic_flash(sim, .DIVIDEND)
			}
		}

		// Interest bonus: +INTEREST_RATE por cada stack de INTEREST_BOOST acumulado
		if sim.relic_stacks[.INTEREST_BOOST] > 0 {
			interest := i32(f32(sim.money) * constants.INTEREST_RATE * f32(sim.relic_stacks[.INTEREST_BOOST]))
			if interest > 0 {
				entities.app_add_money(app, interest)
				entities.add_toast(app, fmt.tprintf("+$%d interés (x%d)", interest, sim.relic_stacks[.INTEREST_BOOST]), .INFO)
				relic_flash(sim, .INTEREST_BOOST)
			}
		}

		// MEMENTO: +gold por stack por cada 10 oleadas completadas
		// sim.wave_number aquí es el ANTERIOR (antes del +=1), por lo que es el conteo de olas completadas
		if sim.relic_stacks[.MEMENTO] > 0 {
			memento_gold := i32(sim.wave_number / 10) * sim.relic_stacks[.MEMENTO]
			if memento_gold > 0 {
				entities.app_add_money(app, memento_gold)
				entities.add_toast(app, fmt.tprintf("+$%d recuerdo (ola %d)", memento_gold, sim.wave_number), .INFO)
				relic_flash(sim, .MEMENTO)
			}
		}
	}

	// Wave clear bonus: escala con el número de oleada completada
	if sim.wave_number > 0 {
		wave_reward := constants.MONEY_WAVE_CLEAR_BASE + sim.wave_number * constants.MONEY_WAVE_CLEAR_PER_WAVE
		entities.app_add_money(app, wave_reward)
		entities.add_toast(app, fmt.tprintf("+$%d oleada", wave_reward), .SUCCESS)
	}

	// Flawless: bono de oro si no se perdieron vidas en la oleada anterior
	if sim.wave_number > 0 && sim.relic_stacks[.FLAWLESS] > 0 {
		if sim.health == sim.wave_start_health {
			bonus := constants.FLAWLESS_BONUS * sim.relic_stacks[.FLAWLESS]
			entities.app_add_money(app, bonus)
			entities.add_toast(app, fmt.tprintf("+$%d oleada perfecta", bonus), .SUCCESS)
			relic_flash(sim, .FLAWLESS)
		}
	}

	// Snapshots al inicio de oleada (usados por Dividend y Flawless al terminar)
	sim.wave_start_money  = sim.money
	sim.wave_start_health = sim.health

	sim.started = true  // Mark game as started
	sim.wave_number += 1
	sim.enemies_spawned = 0
	sim.wave_time = 0

	// Determine wave type based on wave number.
	sim.wave_flags = {}
	is_boss := sim.wave_number % constants.BOSS_WAVE_INTERVAL == 0
	if is_boss { sim.wave_flags |= {.BOSS} }

	// Bonus wave: consume pre-rolled lookahead[0] (always false for boss waves), then shift
	// and roll a new value for wave N+3.
	is_bonus          := !is_boss && sim.wave_number >= constants.BONUS_WAVE_MIN_WAVE && sim.lookahead_bonus[0]
	sim.lookahead_bonus[0] = sim.lookahead_bonus[1]
	sim.lookahead_bonus[1] = sim.lookahead_bonus[2]
	next_preview_wave := sim.wave_number + 3
	sim.lookahead_bonus[2] = (next_preview_wave % constants.BOSS_WAVE_INTERVAL != 0) && next_preview_wave >= constants.BONUS_WAVE_MIN_WAVE && rand.float32() < constants.BONUS_WAVE_CHANCE
	if is_bonus { sim.wave_flags |= {.BONUS} }

	// SCOUT: anuncia el tipo de la PRÓXIMA oleada (wave_number+1).
	// Después del shift, lookahead_bonus[0] corresponde exactamente a wave_number+1.
	if sim.relic_stacks[.SCOUT] > 0 {
		next_wn := sim.wave_number + 1
		if next_wn <= constants.MAX_WAVE {
			next_is_boss  := next_wn % constants.BOSS_WAVE_INTERVAL == 0
			next_is_bonus := !next_is_boss && next_wn >= constants.BONUS_WAVE_MIN_WAVE && sim.lookahead_bonus[0]
			wave_type: string
			if next_is_boss {
				wave_type = "Jefe"
			} else if next_is_bonus {
				wave_type = "Bonus"
			} else {
				switch next_wn % 4 {
				case 1: wave_type = "Verde"
				case 2: wave_type = "Voladores"
				case 3: wave_type = "Azul"
				case 0: wave_type = "Divisores"
				}
			}
			entities.add_toast(app, fmt.tprintf("Scout: próx. oleada → %s", wave_type), .INFO)
			relic_flash(sim, .SCOUT)
		}
	}

	// Sub-types: on bonus waves all flags are active; on normal waves rotate by wave number.
	if is_bonus {
		sim.wave_flags |= {.GREEN, .FLYING, .BLUE, .SPLIT}
	} else if !is_boss {
		// Sub-tipo primario: rotación de 4 tipos
		primary := sim.wave_number % 4
		if primary == 1 { sim.wave_flags |= {.GREEN} }
		if primary == 2 { sim.wave_flags |= {.FLYING} }
		if primary == 3 { sim.wave_flags |= {.BLUE} }
		if primary == 0 { sim.wave_flags |= {.SPLIT} }

		// Oleadas mixtas (>= ola MIXED_WAVE_MIN_WAVE): añadir un segundo sub-tipo.
		// El secundario está desfasado 2 posiciones para que nunca coincida con el primario
		// ni con el tipo de la oleada anterior/siguiente.
		// Combos: green+blue, flying+split, blue+green, split+flying
		if sim.wave_number > constants.MIXED_WAVE_MIN_WAVE {
			secondary := (sim.wave_number + 2) % 4
			if secondary == 1 { sim.wave_flags |= {.GREEN} }
			if secondary == 2 { sim.wave_flags |= {.FLYING} }
			if secondary == 3 { sim.wave_flags |= {.BLUE} }
			if secondary == 0 { sim.wave_flags |= {.SPLIT} }
		}
	}

	// Record wave marker for graph
	append(
		&sim.wave_marks,
		entities.Wave_Mark{time = sim.play_time, wave = sim.wave_number, flags = sim.wave_flags},
	)

	// Calculate enemies to spawn
	if .BOSS in sim.wave_flags {
		sim.enemies_to_spawn = 1
	} else if .BONUS in sim.wave_flags {
		sim.enemies_to_spawn = constants.BONUS_WAVE_ENEMY_COUNT
	} else {
		sim.enemies_to_spawn = constants.WAVE_ENEMIES_BASE + sim.wave_number * constants.WAVE_ENEMIES_SCALE
	}

	// Reset spawn timers
	for i in 0 ..< len(sim.spawns) {
		spawn := &sim.spawns[i]
		spawn.enemies_spawned = 0

		if .BOSS in sim.wave_flags {
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

	// Shop al final de cada oleada (excepto la primera — el jugador ya tiene mano inicial)
	if sim.wave_number > 1 && sim.wave_number % constants.DECK_SELECTION_INTERVAL == 0 {
		generate_card_selection(sim)
		sim.card_selection_active = true
		simulation_set_pause(app, true)
	}
}

// Rellena sim.card_selection_choices con 3 cartas:
//   slot 0 — torre o obstáculo (al azar, sin pesos de rareza)
//   slot 1 — relicto (con pesos de rareza)
//   slot 2 — torre/obstáculo o relicto al 50%
// Puede llamarse desde start_next_wave o desde el botón de reroll.
generate_card_selection :: proc(sim: ^entities.Simulation) {
	sim.card_selection_bought = {}  // reinicia compras al generar nuevas cartas
	tower_pool := [9]entities.Card{
		{kind = .TOWER, tower_type = .ARCHER},
		{kind = .TOWER, tower_type = .CANNON},
		{kind = .TOWER, tower_type = .SNIPER},
		{kind = .TOWER, tower_type = .MISSILE},
		{kind = .TOWER, tower_type = .LASER},
		{kind = .TOWER, tower_type = .ICE},
		{kind = .TOWER, tower_type = .ENHANCE},
		{kind = .OBSTACLE},
		{kind = .OBSTACLE},
	}
	relic_pool := [16]entities.Card{
		{kind = .INTEREST_BOOST},
		{kind = .STEAL},
		{kind = .WEAKEN},
		{kind = .DIVIDEND},
		{kind = .AUTO_UPGRADE},
		{kind = .BLOODLUST},
		{kind = .FLAWLESS},
		{kind = .FORMATION},
		{kind = .FROZEN_AMP},
		{kind = .VETERAN},
		{kind = .LOOT},
		{kind = .SCOUT},
		{kind = .RECYCLER},
		{kind = .MEMENTO},
		{kind = .WARMED_UP},
		{kind = .CRYPTOBRO},
	}
	tower_used := [9]bool{}
	relic_used := [16]bool{}
	cands      : [16]int

	// helper: elige una torre al azar y la asigna al slot indicado
	pick_tower_slot(sim, &tower_pool, &tower_used, &cands, 0)
	// helper: elige un relicto ponderado y lo asigna al slot indicado
	pick_relic_slot(sim, &relic_pool, &relic_used, &cands, 1)
	// slot 2: torre o relicto al 50%
	if rand.float32() < 0.5 {
		if pick_tower_slot(sim, &tower_pool, &tower_used, &cands, 2) { return }
	}
	pick_relic_slot(sim, &relic_pool, &relic_used, &cands, 2)

	// VETERAN: aplica bonus_level a cartas de torre del shop según probabilidad por stack
	if sim.relic_stacks[.VETERAN] > 0 {
		chance := min(f32(1.0), f32(sim.relic_stacks[.VETERAN]) * constants.VETERAN_BOOST_CHANCE)
		for slot in 0 ..< 3 {
			card := &sim.card_selection_choices[slot]
			if card.kind == .TOWER && rand.float32() < chance {
				card.bonus_level = sim.relic_stacks[.VETERAN]
			}
		}
	}
}

pick_tower_slot :: proc(sim: ^entities.Simulation, pool: ^[9]entities.Card, used: ^[9]bool, buf: ^[16]int, slot: int) -> bool {
	n := 0
	for j in 0 ..< 9 { if !used[j] { buf[n] = j; n += 1 } }
	if n == 0 { return false }
	idx := buf[rand.int_max(n)]
	used[idx] = true
	sim.card_selection_choices[slot] = pool[idx]
	return true
}

pick_relic_slot :: proc(sim: ^entities.Simulation, pool: ^[16]entities.Card, used: ^[16]bool, buf: ^[16]int, slot: int) -> bool {
	rval := rand.float32()
	target: constants.Card_Rarity
	if rval < constants.RARITY_PROB_UNIQUE {
		target = .UNIQUE
	} else if rval < constants.RARITY_PROB_UNIQUE + constants.RARITY_PROB_RARE {
		target = .RARE
	} else if rval < constants.RARITY_PROB_UNIQUE + constants.RARITY_PROB_RARE + constants.RARITY_PROB_UNCOMMON {
		target = .UNCOMMON
	} else {
		target = .COMMON
	}
	n := 0
	for j in 0 ..< 16 {
		if !used[j] && entities.card_rarity(pool[j]) == target { buf[n] = j; n += 1 }
	}
	if n == 0 && target == .UNIQUE {
		for j in 0 ..< 16 { if !used[j] && entities.card_rarity(pool[j]) == .RARE     { buf[n] = j; n += 1 } }
	}
	if n == 0 {
		for j in 0 ..< 16 { if !used[j] && entities.card_rarity(pool[j]) == .UNCOMMON { buf[n] = j; n += 1 } }
	}
	if n == 0 {
		for j in 0 ..< 16 { if !used[j] { buf[n] = j; n += 1 } }
	}
	if n == 0 { return false }
	idx := buf[rand.int_max(n)]
	used[idx] = true
	sim.card_selection_choices[slot] = pool[idx]
	return true
}

get_next_spawn_delay :: proc() -> f32 {
	return 1.2 + rand.float32() * 1.5
}

// Dispara el flash visual de una reliquia en el tray.
relic_flash :: proc(sim: ^entities.Simulation, kind: entities.Card_Kind) {
	sim.relic_flash_timers[kind] = constants.RELIC_FLASH_DURATION
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
			spawn.next_spawn_delay = get_next_spawn_delay()
			spawn.enemies_spawned += 1
			sim.enemies_spawned += 1 // Increment global counter

			is_last := spawn.enemies_spawned == spawn.enemies_to_spawn
			is_boss := (.BOSS in sim.wave_flags) && is_last

			// Calculate HP multiplier
			multiplier: f32
			switch {
			case is_boss:                    multiplier = constants.ENEMY_HEALTH_BOSS
			case .BONUS  in sim.wave_flags:  multiplier = constants.ENEMY_HEALTH_BONUS
			case .GREEN  in sim.wave_flags:  multiplier = constants.ENEMY_HEALTH_GREEN
			case .FLYING in sim.wave_flags:  multiplier = constants.ENEMY_HEALTH_FLYING
			case .BLUE   in sim.wave_flags:  multiplier = constants.ENEMY_HEALTH_BLUE
			case:                            multiplier = constants.ENEMY_HEALTH_DEFAULT
			}

			weaken := max(0.1, 1.0 - constants.WEAKEN_HP_REDUCTION * f32(sim.relic_stacks[.WEAKEN]))
			hp :=
				constants.ENEMY_BASE_HP *
				math.pow(constants.ENEMY_GROWTH_RATE, f32(sim.wave_number - 1)) *
				multiplier *
				constants.ENEMY_GLOBAL_HP_MULTIPLIER *
				weaken

			// Speed — bonus enemies use their own speed constant
			speed: f32
			switch {
			case .BONUS  in sim.wave_flags: speed = constants.ENEMY_SPEED_BONUS
			case .GREEN  in sim.wave_flags: speed = constants.ENEMY_SPEED_GREEN
			case .BLUE   in sim.wave_flags: speed = constants.ENEMY_SPEED_BLUE
			case .FLYING in sim.wave_flags: speed = constants.ENEMY_SPEED_FLYING
			case:                           speed = constants.ENEMY_SPEED_DEFAULT
			}

			speed *= constants.ENEMY_GLOBAL_SPEED_MULTIPLIER
			// Escalado progresivo: +~1.2% de velocidad por oleada (igual que HP usa ENEMY_GROWTH_RATE)
			speed *= math.pow(constants.ENEMY_SPEED_GROWTH_RATE, f32(sim.wave_number - 1))

			// Build per-enemy flags: inherit wave subtypes; boss flag only for the last enemy
			enemy_flags := sim.wave_flags - {.BOSS}
			if is_boss { enemy_flags |= {.BOSS} }
			enemy := entities.enemy_init(hp, speed, enemy_flags)

			// Set enemy path (this also sets initial position to spawn)
			entities.enemy_set_path(&enemy, spawn.path)

			append(&sim.enemies, enemy)
			play_sound(.ENEMY_SPAWN, .SFX)
		}
	}
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
			damage := constants.ENEMY_GOAL_DAMAGE_DEFAULT
			if .BOSS in enemy.flags {
				damage = constants.ENEMY_GOAL_DAMAGE_BOSS
			}
			entities.app_take_damage(app, damage)
			play_sound(.ENEMY_REACH_GOAL, .SFX)

			// Invalida punteros de proyectiles antes de remover
			nullify_projectile_targets(sim, enemy)

			// Remove enemy
			entities.enemy_destroy(enemy)
			ordered_remove(&sim.enemies, i)
			continue
		}

		// Obstacle damage
		if !(.FLYING in enemy.flags) {
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
			play_sound(.ENEMY_DEATH, .SFX)

			// Enemy died - give reward
			reward := constants.ENEMY_REWARD_DEFAULT
			if .BOSS in enemy.flags {
				reward = constants.ENEMY_REWARD_BOSS
			} else if .GREEN in enemy.flags {
				reward = constants.ENEMY_REWARD_GREEN
			}
			if .BONUS in enemy.flags {
				reward += constants.ENEMY_REWARD_BONUS
			}
			entities.app_add_money(app, reward)
			sim.enemies_killed += 1
			sim.money_earned   += reward

			// Bloodlust: micro-bonus de daño por cada kill
			if sim.relic_stacks[.BLOODLUST] > 0 {
				sim.bloodlust_mult += constants.BLOODLUST_BONUS_PER_KILL * f32(sim.relic_stacks[.BLOODLUST])
				relic_flash(sim, .BLOODLUST)
			}

			// Carta aleatoria al matar — solo si el jugador tiene la reliquia LOOT
			if sim.relic_stacks[.LOOT] > 0 && rand.float32() < f32(sim.relic_stacks[.LOOT]) * constants.DECK_CARD_DROP_CHANCE {
				drop_pool := [24]entities.Card{
					{kind = .TOWER, tower_type = .ARCHER},
					{kind = .TOWER, tower_type = .CANNON},
					{kind = .TOWER, tower_type = .SNIPER},
					{kind = .TOWER, tower_type = .MISSILE},
					{kind = .TOWER, tower_type = .LASER},
					{kind = .TOWER, tower_type = .ICE},
					{kind = .OBSTACLE},
					{kind = .OBSTACLE},
					{kind = .INTEREST_BOOST},
					{kind = .STEAL},
					{kind = .WEAKEN},
					{kind = .DIVIDEND},
					{kind = .AUTO_UPGRADE},
					{kind = .BLOODLUST},
					{kind = .FLAWLESS},
					{kind = .FORMATION},
					{kind = .FROZEN_AMP},
					{kind = .VETERAN},
					{kind = .LOOT},
					{kind = .SCOUT},
					{kind = .RECYCLER},
					{kind = .MEMENTO},
					{kind = .WARMED_UP},
					{kind = .CRYPTOBRO},
				}
				dropped := drop_pool[rand.int_max(24)]
				entities.card_add_to_hand(sim, dropped)
				entities.add_toast(
					app,
					fmt.tprintf("¡Carta encontrada: %s!", entities.card_name(dropped)),
					.SUCCESS,
					4.0,
				)
				play_sound(.CARD_GAINED, .SFX)
				relic_flash(sim, .LOOT)
			}

			// CRYPTOBRO: la torre que mató al jefe gana +1 nivel permanente
			if .BOSS in enemy.flags && sim.relic_stacks[.CRYPTOBRO] > 0 && enemy.last_attacker_r >= 0 {
				for &t in sim.towers {
					if t.r == enemy.last_attacker_r && t.c == enemy.last_attacker_c {
						if t.level < constants.TOWER_MAX_LEVEL {
							entities.tower_upgrade(&t)
							entities.add_toast(app, fmt.tprintf("¡Cryptobro! Torre → Nv%d", t.level), .SUCCESS, 4.0)
							relic_flash(sim, .CRYPTOBRO)
						}
						break
					}
				}
			}

			// Split: parent has .SPLIT flag; children don't inherit SPLIT, BOSS, or BONUS.
			// Children keep sub-type flags (FLYING, GREEN, BLUE) so mixed-wave behavior is preserved.
			if (.SPLIT in enemy.flags) && !(.BOSS in enemy.flags) {
				for _ in 0 ..< 2 {
					child_hp    := enemy.max_hp * constants.SPLIT_HP_RATIO
					child_flags := enemy.flags - {.SPLIT, .BOSS, .BONUS}
					child := entities.enemy_init(child_hp, enemy.speed * constants.SPLIT_SPEED_MULT, child_flags)
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

		// ENHANCE tower: el bonus se recalcula en update_enhance_bonuses, no necesita update propio
		if tower.type == .ENHANCE {
			continue
		}

		// Find target
		target_enemy := find_target(app, &tower)
		tower.target = target_enemy

		// WARMED_UP: acumula tiempo con objetivo; reset si no hay objetivo
		if tower.target != nil {
			tower.warm_timer += dt
		} else {
			tower.warm_timer = 0
		}

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
				case .ICE, .ENHANCE:
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
	for &enemy in app.sim.enemies {
		dx := (enemy.x + 0.5) - (f32(tower.c) + 0.5)
		dy := (enemy.y + 0.5) - (f32(tower.r) + 0.5)
		dist := math.sqrt_f32(dx * dx + dy * dy)
		if dist <= tower.range {
			entities.enemy_apply_slow(&enemy, constants.ICE_SLOW_FACTOR, constants.ICE_SLOW_DURATION)

			// Apply damage per pulse
			is_crit := rand.float32() < constants.CRIT_BASE_CHANCE
			dmg := tower.damage
			if is_crit {
				dmg *= constants.CRIT_DAMAGE_MULTIPLIER
			}
			dmg = calc_damage(app, dmg, tower, &enemy)
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
	play_sound(.TOWER_ICE, .SFX)
}

// Recalcula el enhance_bonus de cada torre según los Potenciadores activos en rango.
// Se llama cada frame. El bonus es la suma de niveles de todos los ENHANCE en rango,
// acotado por ENHANCE_MAX_LEVEL y por el espacio hasta TOWER_MAX_LEVEL.
update_enhance_bonuses :: proc(app: ^entities.App_State) {
	for &t in app.sim.towers {
		if t.type == .ENHANCE { continue }

		new_bonus: i32 = 0
		for &et in app.sim.towers {
			if et.type != .ENHANCE { continue }
			dx := f32(t.c - et.c)
			dy := f32(t.r - et.r)
			dist := math.sqrt_f32(dx * dx + dy * dy)
			if dist <= et.range {
				new_bonus += et.level
			}
		}

		manual_level := t.level - t.enhance_bonus
		max_bonus    := constants.TOWER_MAX_LEVEL - manual_level
		if new_bonus > max_bonus                   { new_bonus = max_bonus }
		if new_bonus > constants.ENHANCE_MAX_LEVEL { new_bonus = constants.ENHANCE_MAX_LEVEL }
		if new_bonus < 0                           { new_bonus = 0 }

		if new_bonus != t.enhance_bonus {
			t.enhance_bonus = new_bonus
			t.level         = manual_level + new_bonus
			entities.tower_recompute_stats(&t)
		}
	}
}

// Update laser tower
update_laser_tower :: proc(app: ^entities.App_State, tower: ^entities.Tower, dt: f32) {
	damage, beam_active := entities.laser_tower_update(tower, dt)

	if damage > 0 && tower.target != nil {
		scaled := calc_damage(app, damage, tower, tower.target)
		tower.target.hp -= scaled
		tower.total_damage += scaled

		// Show accumulated damage
		should_show, display_damage, is_crit := entities.laser_should_show_damage(tower)
		if should_show {
			if is_crit {
				// Apply bonus critical damage
				bonus := display_damage * (constants.CRIT_DAMAGE_MULTIPLIER - 1.0)
				bonus  = calc_damage(app, bonus, tower, tower.target)
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
			play_sound(.TOWER_LASER, .SFX)
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
		proj_speed: f32 = constants.PROJECTILE_SPEED_DEFAULT

		fire_gx, fire_gy: f32
		if tower.type == .MISSILE {
			proj_speed = constants.PROJECTILE_SPEED_MISSILE
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
			tower.r,
			tower.c,
		)

		append(&sim.projectiles, proj)

		// SFX: play tower fire sound
		switch tower.type {
		case .ARCHER:  play_sound(.TOWER_ARCHER, .SFX)
		case .CANNON:  play_sound(.TOWER_CANNON, .SFX)
		case .SNIPER:  play_sound(.TOWER_SNIPER, .SFX)
		case .MISSILE: play_sound(.TOWER_MISSILE, .SFX)
		case .LASER, .ICE, .ENHANCE: // handled separately
		}
	}
}

// Find target for tower — uses a fixed-size stack buffer to avoid per-call heap allocation.
find_target :: proc(app: ^entities.App_State, tower: ^entities.Tower) -> ^entities.Enemy {
	sim := &app.sim

	// Fixed-size eligible list; 256 slots is well above any practical enemy count.
	MAX_ELIGIBLE :: 256
	eligible: [MAX_ELIGIBLE]^entities.Enemy
	n := 0

	for i in 0 ..< len(sim.enemies) {
		enemy := &sim.enemies[i]

		dx := (enemy.x + 0.5) - (f32(tower.c) + 0.5)
		dy := (enemy.y + 0.5) - (f32(tower.r) + 0.5)
		dist := math.sqrt_f32(dx * dx + dy * dy)

		if dist <= tower.range {
			// CANNON and SNIPER cannot target flying enemies
			// Only ARCHER, MISSILE, and LASER can target flying enemies
			can_target_flying :=
				tower.type == .ARCHER || tower.type == .MISSILE || tower.type == .LASER
			if !(.FLYING in enemy.flags) || can_target_flying {
				if n < MAX_ELIGIBLE {
					eligible[n] = enemy
					n += 1
				}
			}
		}
	}

	if n == 0 {
		return nil
	}

	// Pick best enemy according to strategy
	best_enemy := eligible[0]

	switch tower.target_strategy {
	case .FIRST:
		// Enemy closest to goal (furthest along path)
		best_progress := best_enemy.path_idx
		for i in 1 ..< n {
			enemy := eligible[i]
			if enemy.path_idx > best_progress {
				best_progress = enemy.path_idx
				best_enemy = enemy
			}
		}

	case .LAST:
		// Enemy furthest from goal (least along path)
		best_progress := best_enemy.path_idx
		for i in 1 ..< n {
			enemy := eligible[i]
			if enemy.path_idx < best_progress {
				best_progress = enemy.path_idx
				best_enemy = enemy
			}
		}

	case .MAX_HP:
		best_hp := best_enemy.hp
		for i in 1 ..< n {
			enemy := eligible[i]
			if enemy.hp > best_hp {
				best_hp = enemy.hp
				best_enemy = enemy
			}
		}

	case .MIN_HP:
		best_hp := best_enemy.hp
		for i in 1 ..< n {
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
			is_crit := rand.float32() < constants.CRIT_BASE_CHANCE
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
				scaled_dmg := calc_damage(app, damage, source_tower, proj.target)
				proj.target.hp -= scaled_dmg
				if source_tower != nil { source_tower.total_damage += scaled_dmg }
				spawn_damage_number(app, proj.target.x + 0.5, proj.target.y + 0.5, scaled_dmg, is_crit)
				play_sound(.PROJECTILE_HIT, .SFX)
			}

			// AoE: se activa siempre al impactar, haya o no objetivo vivo.
			// Esto genera la explosión "en el suelo" cuando el objetivo murió antes de ser alcanzado.
			if proj.aoe > 0 {
				spawn_explosion(app, proj.x, proj.y, proj.aoe)
				play_sound(.EXPLOSION, .SFX)

				for &enemy in sim.enemies {
					if proj.target != nil && &enemy == proj.target {
						continue // El objetivo principal ya recibió daño directo
					}

					dx := enemy.x - proj.x
					dy := enemy.y - proj.y
					dist := math.sqrt_f32(dx * dx + dy * dy)

					if dist <= proj.aoe {
						aoe_damage := proj.damage * constants.AOE_DAMAGE_MULTIPLIER
						if is_crit {
							aoe_damage *= constants.CRIT_DAMAGE_MULTIPLIER
						}
						aoe_damage = calc_damage(app, aoe_damage, source_tower, &enemy)
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
// Actualiza el auto-upgrade: mejora hasta relic_stacks[.AUTO_UPGRADE] torres en orden de upgrade más barato.
// Salta torres al nivel máximo o cuando no hay dinero suficiente.
// Cuenta cuántas torres del mismo tipo hay consecutivamente en una dirección (dr, dc).
tower_count_line :: proc(app: ^entities.App_State, tower: ^entities.Tower, dr, dc: i32) -> i32 {
	count := i32(0)
	r, c  := tower.r + dr, tower.c + dc
	for {
		found := false
		for &t in app.sim.towers {
			if t.r == r && t.c == c && t.type == tower.type {
				found = true
				break
			}
		}
		if !found { break }
		count += 1
		r += dr
		c += dc
	}
	return count
}

// Devuelve true si la torre pertenece a una línea de 3+ torres del mismo tipo (horizontal o vertical).
// Pura geometría — sin chequeo de reliquias. Usada por update_formation_cache.
tower_is_in_formation :: proc(app: ^entities.App_State, tower: ^entities.Tower) -> bool {
	h := 1 + tower_count_line(app, tower, 0, -1) + tower_count_line(app, tower, 0, 1)
	if h >= 3 { return true }
	v := 1 + tower_count_line(app, tower, -1, 0) + tower_count_line(app, tower, 1, 0)
	return v >= 3
}

// Recalcula _in_formation en todas las torres.
// Llamar cuando se construye o se vende una torre.
update_formation_cache :: proc(app: ^entities.App_State) {
	for &t in app.sim.towers {
		t._in_formation = tower_is_in_formation(app, &t)
	}
}

// Aplica los modificadores globales de daño: Bloodlust, Formation, Frozen Amp.
// source puede ser nil (p.ej. obstáculos). enemy puede ser nil (p.ej. AoE sin objetivo).
calc_damage :: proc(
	app:    ^entities.App_State,
	base:   f32,
	source: ^entities.Tower,
	enemy:  ^entities.Enemy,
) -> f32 {
	d := base * app.sim.bloodlust_mult

	if source != nil && app.sim.relic_stacks[.FORMATION] > 0 && source._in_formation {
		d *= 1.0 + constants.FORMATION_BONUS * f32(app.sim.relic_stacks[.FORMATION])
	}

	if enemy != nil && enemy.slow_timer > 0 && app.sim.relic_stacks[.FROZEN_AMP] > 0 {
		d *= 1.0 + constants.FROZEN_AMP_BONUS * f32(app.sim.relic_stacks[.FROZEN_AMP])
	}

	// WARMED_UP: bonus de daño si la torre lleva WARMED_UP_THRESHOLD segundos con objetivo
	if source != nil && app.sim.relic_stacks[.WARMED_UP] > 0 && source.warm_timer >= constants.WARMED_UP_THRESHOLD {
		d *= 1.0 + constants.WARMED_UP_BONUS * f32(app.sim.relic_stacks[.WARMED_UP])
	}

	// CRYPTOBRO: registra la última torre que dañó a este enemigo (para boss-kill level up)
	if source != nil && enemy != nil {
		enemy.last_attacker_r = source.r
		enemy.last_attacker_c = source.c
	}

	return d
}

update_auto_upgrade :: proc(app: ^entities.App_State) {
	sim := &app.sim

	// Collect all upgradeable candidates in one pass, then sort once and consume cheapest N.
	// This replaces relic_stacks[.AUTO_UPGRADE] separate full scans with a single O(N log N) pass.
	Auto_Candidate :: struct {
		cost:     i32,
		tower_i:  int,   // index in sim.towers, or -1 for obstacle
		row, col: i32,   // obstacle grid position (valid when tower_i < 0)
	}

	MAX_CANDS :: 256
	cands: [MAX_CANDS]Auto_Candidate
	nc := 0

	for i in 0 ..< len(sim.towers) {
		t := &sim.towers[i]
		if t.level >= constants.TOWER_MAX_LEVEL do continue
		manual_cap := constants.ENHANCE_MAX_LEVEL if t.type == .ENHANCE else constants.TOWER_MAX_MANUAL_LEVEL
		if t.level - t.enhance_bonus >= manual_cap do continue
		if nc < MAX_CANDS {
			cands[nc] = Auto_Candidate{entities.tower_get_upgrade_cost(t), i, -1, -1}
			nc += 1
		}
	}

	for row in 0 ..< app.editor.game_map.height {
		for col in 0 ..< app.editor.game_map.width {
			if app.editor.game_map.obstacle_grid[row][col] != .OBSTACLE do continue
			level := entities.map_get_obstacle_level(&app.editor.game_map, row, col)
			cost  := constants.OBSTACLE_UPGRADE_COST_BASE * i32(i32(1) << uint(level - 1))
			if nc < MAX_CANDS {
				cands[nc] = Auto_Candidate{cost, -1, row, col}
				nc += 1
			}
		}
	}

	if nc == 0 { return }

	// Insertion sort by cost ascending (nc is always small — ≤ 256)
	for i in 1 ..< nc {
		key := cands[i]
		j   := i - 1
		for j >= 0 && cands[j].cost > key.cost {
			cands[j + 1] = cands[j]
			j -= 1
		}
		cands[j + 1] = key
	}

	// Consume cheapest candidates up to relic_stacks[.AUTO_UPGRADE]
	upgrades_done := i32(0)
	for i in 0 ..< nc {
		if upgrades_done >= sim.relic_stacks[.AUTO_UPGRADE] { break }
		cand := cands[i]
		if sim.money < cand.cost { break } // sorted — nothing cheaper remains
		sim.money -= cand.cost
		if cand.tower_i >= 0 {
			entities.tower_upgrade(&sim.towers[cand.tower_i])
		} else {
			level := entities.map_get_obstacle_level(&app.editor.game_map, cand.row, cand.col)
			entities.map_set_obstacle_level(&app.editor.game_map, cand.row, cand.col, level + 1)
		}
		sim.upgrades_bought += 1
		upgrades_done += 1
	}

	if upgrades_done > 0 {
		entities.add_toast(app, fmt.tprintf("Auto-mejora x%d", upgrades_done), .INFO)
		relic_flash(sim, .AUTO_UPGRADE)
	}
}

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
			// RECYCLER: bonus de venta por stack
			if app.sim.relic_stacks[.RECYCLER] > 0 {
				bonus := i32(f32(refund) * constants.RECYCLER_SELL_BONUS * f32(app.sim.relic_stacks[.RECYCLER]))
				refund += bonus
			}
			app.sim.money += refund

			// Remove from grid
			app.editor.game_map.grid[row][col] = .EMPTY

			// Remove from towers array
			ordered_remove(&app.sim.towers, i)

			// Deselect tower
			entities.app_deselect_tower(app)

			// Invalidate formation cache
			update_formation_cache(app)

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
	delete(app.sim.deck)
	delete(app.sim.hand)
	delete(app.sim.discard)
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
		// Deck builder
		deck      = make([dynamic]entities.Card),
		hand      = make([dynamic]entities.Card),
		discard   = make([dynamic]entities.Card),
		hand_size = constants.DECK_HAND_SIZE,
		selected_card_idx = -1,
		card_selection_active  = false,
		card_selection_choices = {},
		card_selection_bought  = {},
		auto_upgrade_timer     = 0,
		wave_start_money       = 0,
		steal_last_wave        = 0,
		bloodlust_mult         = 1.0,
		wave_start_health      = 0,
		inter_wave_timer       = 0,

		enemies_killed   = 0,
		money_earned     = 0,
		towers_built     = 0,
		upgrades_bought  = 0,
		play_time        = 0,
		graph_samples    = make([dynamic]entities.Graph_Sample),
		wave_marks       = make([dynamic]entities.Wave_Mark),
		_sample_timer    = 0,
	}

	// Generar seed aleatorio y resetear el RNG global para determinismo
	app.sim.seed = rand.uint64()
	rand.reset(app.sim.seed)

	// Inicializar mazo inicial y mano de apertura garantizada
	// (build_starter_deck puebla sim.hand directamente con la composición garantizada)
	entities.build_starter_deck(&app.sim)

	// Pre-roll bonus status for the first 3 upcoming waves (waves 1, 2, 3).
	for i in 0 ..< 3 {
		wave_n := i32(i + 1)
		is_boss := wave_n % constants.BOSS_WAVE_INTERVAL == 0
		app.sim.lookahead_bonus[i] = !is_boss && wave_n >= constants.BONUS_WAVE_MIN_WAVE && rand.float32() < constants.BONUS_WAVE_CHANCE
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
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER, .TOWER_ICE, .TOWER_ENHANCE:
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
				case .TOWER_ENHANCE:
					tower_type = .ENHANCE
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

	update_formation_cache(app)
	return len(app.sim.spawns) > 0
}
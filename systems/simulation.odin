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

	// Update glow particles (solo avanza t; screen_dy se computa en el render)
	{
		i := 0
		for i < len(sim.glow_particles) {
			p := &sim.glow_particles[i]
			p.t += s_dt
			if p.t >= p.lifetime {
				unordered_remove(&sim.glow_particles, i)
			} else {
				i += 1
			}
		}
	}

	// Auto-upgrade: intervalo base que se divide a la mitad por cada stack adicional.
	// 1 stack = 30s, 2 stacks = 15s, 3 stacks = 7.5s, etc.
	if sim.relic_stacks[.AUTO_UPGRADE] > 0 && sim.started {
		sim.auto_upgrade_timer -= s_dt
		if sim.auto_upgrade_timer <= 0 {
			stacks := sim.relic_stacks[.AUTO_UPGRADE]
			sim.auto_upgrade_timer = constants.AUTO_UPGRADE_INTERVAL / math.pow(f32(2), f32(stacks - 1))
			update_auto_upgrade(app)
		}
	}

	// Airdrop: only while simulation has started and shop is not open
	if sim.started && !sim.shop.active {
		airdrop_update(app, dt)  // uses real dt (not s_dt) — visual effect
	}
}

// Devuelve el multiplicador de dificultad para el run actual.
// Si app.current_campaign_node >= 0, lee el difficulty_mult del nodo. Sino 1.0.
campaign_difficulty :: proc(app: ^entities.App_State) -> f32 {
	if app.current_campaign_node < 0 { return 1.0 }
	if app.current_campaign_node >= app.campaign.node_count { return 1.0 }
	mult := app.campaign.nodes[app.current_campaign_node].difficulty_mult
	if mult <= 0 { return 1.0 }
	return mult
}

// Devuelve el número máximo de waves para este run: override del nodo de
// campaña si > 0, sino constants.RUN_MAX_WAVES.
campaign_max_waves :: proc(app: ^entities.App_State) -> i32 {
	if app.current_campaign_node < 0 { return constants.RUN_MAX_WAVES }
	if app.current_campaign_node >= app.campaign.node_count { return constants.RUN_MAX_WAVES }
	override := app.campaign.nodes[app.current_campaign_node].waves_override
	if override > 0 { return override }
	return constants.RUN_MAX_WAVES
}

// Wave management
update_wave :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim

	// Check if wave is complete: game must have started, all enemies spawned AND cleared,
	// and enemies_to_spawn > 0 to avoid triggering before the first wave is launched.
	if sim.started && sim.enemies_to_spawn > 0 &&
	   sim.enemies_spawned >= sim.enemies_to_spawn && len(sim.enemies) == 0 {
		if sim.wave_number >= campaign_max_waves(app) {
			entities.app_finish_run(app, true)
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

			if app.settings.auto_start_wave && !sim.shop.active {
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

	// SCOUT: el panel de próximas oleadas se muestra en el HUD (menus.odin).
	if sim.relic_stacks[.SCOUT] > 0 {
		relic_flash(sim, .SCOUT)
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
		// Reset por-visita: reroll counter y purchases.
		// Los locks, el pity counter (shops_since_unique) y el skip streak persisten entre shops.
		sim.shop.rerolls_this_visit   = 0
		sim.shop.purchases_this_visit = 0
		generate_card_selection(app)
		sim.shop.active = true
		simulation_set_pause(app, true)

		// "Skip Shop" automático: cierra la tienda de inmediato, igual que si el
		// jugador presionara el botón Skip manualmente.
		if app.settings.auto_skip_shop {
			shop_perform_skip(app)
		}
	}
}

// Cierra la tienda aplicando el bonus de oro por skip (si no se compró nada),
// reseteando selección/locks y reanudando la simulación. Comparte lógica entre
// el botón Skip manual (menus.odin) y el auto-skip ("Skip Shop" toggle).
// ─────────────────────────────────────────────────────────────────────────────
// Acciones del shop — toda la mutación de sim/meta vive acá. Las procs de
// render emiten estas acciones; nunca tocan sim directamente. Esto desacopla
// la UI del estado y hace que cada acción sea testeable/replayable.
// ─────────────────────────────────────────────────────────────────────────────

// Devuelve true si el jugador NO puede comprar un relic de tipo 'kind' porque
// ya alcanzó el límite de tipos distintos y no tiene ningún stack de ese tipo.
// SHOPPING_CART siempre devuelve false (nunca está bloqueado — expande el cap).
shop_relic_cap_blocks :: proc(sim: ^entities.Simulation, kind: entities.Card_Kind) -> bool {
	if kind == .SHOPPING_CART { return false }
	// Si ya posee algún stack de este tipo, puede acumular más sin ocupar nuevo slot.
	if entities.relic_stacks(sim, kind) > 0 { return false }
	active_relic_types := 0
	for spec in entities.RELIC_SPECS {
		if spec.kind == .SHOPPING_CART { continue }
		if entities.relic_stacks(sim, spec.kind) > 0 {
			active_relic_types += 1
		}
	}
	relic_cap := constants.MAX_ACTIVE_RELICS + int(entities.relic_stacks(sim, .SHOPPING_CART))
	return active_relic_types >= relic_cap
}

// Compra el slot indicado: descuenta oro, marca bought, aplica el efecto
// (relic stack o añadir carta a la mano), y rompe el skip streak.
// El caller debe verificar que el slot sea comprable (no bought, plata suficiente).
shop_perform_buy :: proc(app: ^entities.App_State, slot_idx: int) {
	sim := &app.sim
	if slot_idx < 0 || slot_idx >= len(sim.shop.choices) { return }
	card := sim.shop.choices[slot_idx]
	if sim.shop.bought[slot_idx] { return }

	price := shop_price_for_card(app, card)
	if sim.money < price { return }

	// Bloquear compra de relic si ya se alcanzó el límite de tipos distintos.
	// Excepciones: cartas de acción con target (LUMBERJACK, OVERDRIVE) van a la mano, no al pool de relictos.
	is_action_relic := card.kind == .LUMBERJACK || card.kind == .OVERDRIVE || card.kind == .GARDENER || card.kind == .CRANE_KICK
	if entities.is_relic(card.kind) && !is_action_relic {
		if shop_relic_cap_blocks(sim, card.kind) { return }
	}

	sim.money -= price
	sim.shop.bought[slot_idx] = true
	sim.shop.locked[slot_idx] = false  // comprar libera el lock — ya no necesita persistir
	sim.shop.purchases_this_visit += 1
	sim.shop.skip_streak_count = 0     // comprar rompe el streak

	if entities.is_relic(card.kind) && !is_action_relic {
		apply_relic_card(app, card.kind)
	} else {
		entities.card_add_to_hand(&app.sim, card)
	}
	play_sound(.CONFIRMATION, .UI)
}

// Toggle del lock del slot indicado. El lock sobrevive al reroll.
shop_perform_toggle_lock :: proc(app: ^entities.App_State, slot_idx: int) {
	sim := &app.sim
	if slot_idx < 0 || slot_idx >= len(sim.shop.locked) { return }
	sim.shop.locked[slot_idx] = !sim.shop.locked[slot_idx]
	play_sound(.CLICK, .UI)
}

// Reroll: cobra el costo progresivo, incrementa el contador y regenera slots.
// Los slots locked se preservan; los demás se reemplazan.
shop_perform_reroll :: proc(app: ^entities.App_State) {
	sim         := &app.sim
	reroll_cost := shop_next_reroll_cost(app)
	if sim.money < reroll_cost { return }

	sim.money -= reroll_cost
	sim.shop.rerolls_this_visit += 1
	generate_card_selection(app)
	play_sound(.CLICK, .UI)
}

// Refund de 1 stack de la relic dada. Devuelve SHOP_RELIC_REFUND_PRICE.
shop_perform_refund :: proc(app: ^entities.App_State, kind: entities.Card_Kind) {
	sim := &app.sim
	if sim.relic_stacks[kind] <= 0 { return }
	sim.relic_stacks[kind] -= 1
	entities.app_add_money(app, constants.SHOP_RELIC_REFUND_PRICE)
	entities.add_toast(app,
		fmt.tprintf("+$%d refund", constants.SHOP_RELIC_REFUND_PRICE),
		.INFO)
	play_sound(.CONFIRMATION, .UI)
}

// Skip del shop: si no se compró nada, devuelve un bonus de oro escalado por
// el contador de skip streak. Cierra el shop y reanuda la simulación.
shop_perform_skip :: proc(app: ^entities.App_State) {
	sim := &app.sim
	if sim.shop.purchases_this_visit == 0 {
		sim.shop.skip_streak_count += 1
		bonus := sim.shop.skip_streak_count * constants.SHOP_SKIP_BONUS_PER_SKIP
		if bonus > constants.SHOP_SKIP_BONUS_CAP { bonus = constants.SHOP_SKIP_BONUS_CAP }
		entities.app_add_money(app, bonus)
		entities.add_toast(app, fmt.tprintf("+$%d skip racha x%d", bonus, sim.shop.skip_streak_count), .INFO)
	}
	sim.shop.active = false
	sim.shop.bought = {}
	simulation_set_pause(app, false)
}

// Rellena sim.shop.choices.
// Layout por slot:
//   slot 0           — torre o obstáculo (al azar, sin pesos de rareza)
//   slot 1           — relicto (con pesos de rareza, solo relictos desbloqueados)
//   slot 2 en adelante — torre/relicto al 50%
//
// Respeta sim.shop.locked: los slots con lock NO se regeneran y
// sus card_selection_bought se preservan.
//
// El número de slots activos viene del bioma (SHOP_BASE_SLOTS + extra_slots).
// Pity UNIQUE: si pasaron SHOP_PITY_UNIQUE_THRESHOLD shops sin ver UNIQUE,
// fuerza una en el primer slot relic no-locked.
//
// Puede llamarse desde start_next_wave o desde el botón de reroll.
generate_card_selection :: proc(app: ^entities.App_State) {
	sim := &app.sim

	// Determinar slot_count desde el bioma activo (mapa cargado)
	biome     := app.editor.game_map.biome
	biome_mod := constants.BIOME_SHOP_MODS[biome]
	slot_count := constants.SHOP_BASE_SLOTS + biome_mod.extra_slots
	if slot_count > constants.MAX_SHOP_SLOTS { slot_count = constants.MAX_SHOP_SLOTS }
	if slot_count < 1 { slot_count = 1 }
	sim.shop.slot_count = slot_count

	// Reset compras solo de slots no bloqueados — los bloqueados preservan su estado
	new_bought := [constants.MAX_SHOP_SLOTS]bool{}
	for i in 0 ..< constants.MAX_SHOP_SLOTS {
		if sim.shop.locked[i] {
			new_bought[i] = sim.shop.bought[i]
		}
	}
	sim.shop.bought = new_bought

	// Build tower pool from unlocked towers only + 2 obstacle slots.
	all_tower_cards := [9]entities.Card{
		{kind = .TOWER, tower_type = .ARCHER},
		{kind = .TOWER, tower_type = .CANNON},
		{kind = .TOWER, tower_type = .SNIPER},
		{kind = .TOWER, tower_type = .MISSILE},
		{kind = .TOWER, tower_type = .LASER},
		{kind = .TOWER, tower_type = .ICE},
		{kind = .TOWER, tower_type = .ENHANCE},
		{kind = .TOWER, tower_type = .TESLA},
		{kind = .TOWER, tower_type = .MORTAR},
	}
	tower_pool  := [11]entities.Card{}
	tower_count := 0
	for c in all_tower_cards {
		if entities.meta_is_tower_unlocked(&app.meta, c.tower_type) {
			tower_pool[tower_count] = c
			tower_count += 1
		}
	}
	tower_pool[tower_count]     = {kind = .OBSTACLE}
	tower_pool[tower_count + 1] = {kind = .OBSTACLE}
	tower_count += 2

	// Contar cuántos tipos distintos de reliquias ocupa el jugador.
	// SHOPPING_CART no cuenta contra el límite — expande el cap pero no ocupa slot.
	active_relic_types := 0
	for spec in entities.RELIC_SPECS {
		if spec.kind == .SHOPPING_CART { continue }
		if entities.relic_stacks(sim, spec.kind) > 0 {
			active_relic_types += 1
		}
	}
	relic_cap    := constants.MAX_ACTIVE_RELICS + int(entities.relic_stacks(sim, .SHOPPING_CART))
	at_relic_cap := active_relic_types >= relic_cap

	// Build the relic pool from RELIC_SPECS — solo desbloqueados y sin stack máximo.
	// Si el jugador alcanzó el límite de tipos distintos, solo se ofrecen reliquias que ya posee.
	// Al agregar un relic a RELIC_SPECS queda automáticamente disponible en el shop.
	relic_pool  := make([dynamic]entities.Card, context.temp_allocator)
	for spec in entities.RELIC_SPECS {
		already_has  := entities.relic_stacks(sim, spec.kind) > 0
		expands_cap  := spec.kind == .SHOPPING_CART  // siempre disponible — expande el cap
		if at_relic_cap && !already_has && !expands_cap { continue }
		if entities.meta_is_relic_unlocked(&app.meta, spec.kind) && !entities.relic_is_maxed(&app.sim, spec.kind) {
			append(&relic_pool, entities.Card{kind = spec.kind})
		}
	}
	relic_count := len(relic_pool)

	tower_used := [11]bool{}
	relic_used := make([]bool, relic_count, context.temp_allocator)
	cands      : [16]int

	// Pity counter — sube siempre; si rolamos un UNIQUE abajo, se resetea
	sim.shop.shops_since_unique += 1

	// Generar cada slot según su patrón. Locked slots se saltan.
	for slot in 0 ..< int(slot_count) {
		if sim.shop.locked[slot] { continue }

		switch slot {
		case 0:
			pick_tower_slot(sim, &tower_pool, &tower_used, &cands, slot, tower_count)
		case 1:
			if relic_count == 0 {
				pick_tower_slot(sim, &tower_pool, &tower_used, &cands, slot, tower_count)
			} else {
				pick_relic_slot(sim, relic_pool[:], relic_count, relic_used, &cands, slot)
			}
		case:
			// 50/50 torre o relicto, con fallback
			if relic_count == 0 || rand.float32() < 0.5 {
				if !pick_tower_slot(sim, &tower_pool, &tower_used, &cands, slot, tower_count) {
					pick_relic_slot(sim, relic_pool[:], relic_count, relic_used, &cands, slot)
				}
			} else {
				if !pick_relic_slot(sim, relic_pool[:], relic_count, relic_used, &cands, slot) {
					pick_tower_slot(sim, &tower_pool, &tower_used, &cands, slot, tower_count)
				}
			}
		}
	}

	// Pity UNIQUE: si pasó el threshold y no rolamos UNIQUE, forzamos una
	has_unique := false
	for slot in 0 ..< int(slot_count) {
		if entities.card_rarity(sim.shop.choices[slot]) == .UNIQUE {
			has_unique = true
			break
		}
	}
	if has_unique {
		sim.shop.shops_since_unique = 0
	} else if sim.shop.shops_since_unique >= constants.SHOP_PITY_UNIQUE_THRESHOLD && relic_count > 0 {
		// Buscar la primera UNIQUE en el pool de relics
		unique_idx := -1
		for i in 0 ..< relic_count {
			if entities.card_rarity(relic_pool[i]) == .UNIQUE {
				unique_idx = i
				break
			}
		}
		if unique_idx >= 0 {
			// Colocarla en el primer slot relic no-locked, no-tower-only
			for slot in 0 ..< int(slot_count) {
				if sim.shop.locked[slot] { continue }
				if slot == 0 { continue } // slot 0 es siempre torre
				sim.shop.choices[slot] = relic_pool[unique_idx]
				sim.shop.shops_since_unique = 0
				break
			}
		}
	}

	// VETERAN: aplica bonus_level a cartas de torre del shop según probabilidad por stack
	if sim.relic_stacks[.VETERAN] > 0 {
		chance := min(f32(1.0), f32(sim.relic_stacks[.VETERAN]) * constants.VETERAN_BOOST_CHANCE)
		for slot in 0 ..< int(slot_count) {
			if sim.shop.locked[slot] { continue }
			card := &sim.shop.choices[slot]
			if card.kind == .TOWER && rand.float32() < chance {
				card.bonus_level = sim.relic_stacks[.VETERAN]
			}
		}
	}
}

pick_tower_slot :: proc(sim: ^entities.Simulation, pool: ^[11]entities.Card, used: ^[11]bool, buf: ^[16]int, slot: int, count: int = 11) -> bool {
	n := 0
	for j in 0 ..< count { if !used[j] { buf[n] = j; n += 1 } }
	if n == 0 { return false }
	idx := buf[rand.int_max(n)]
	used[idx] = true
	sim.shop.choices[slot] = pool[idx]
	return true
}

pick_relic_slot :: proc(sim: ^entities.Simulation, pool: []entities.Card, count: int, used: []bool, buf: ^[16]int, slot: int) -> bool {
	rval := rand.float32()
	target: constants.Card_Rarity
	if rval < constants.RARITY_PROB_UNIQUE {
		target = .UNIQUE
	} else if rval < constants.RARITY_PROB_UNIQUE + constants.RARITY_PROB_EPIC {
		target = .EPIC
	} else if rval < constants.RARITY_PROB_UNIQUE + constants.RARITY_PROB_EPIC + constants.RARITY_PROB_RARE {
		target = .RARE
	} else if rval < constants.RARITY_PROB_UNIQUE + constants.RARITY_PROB_EPIC + constants.RARITY_PROB_RARE + constants.RARITY_PROB_UNCOMMON {
		target = .UNCOMMON
	} else {
		target = .COMMON
	}
	n := 0
	for j in 0 ..< count {
		if !used[j] && entities.card_rarity(pool[j]) == target { buf[n] = j; n += 1 }
	}
	// Fallback chain: UNIQUE → EPIC → RARE → UNCOMMON → any
	if n == 0 && target == .UNIQUE {
		for j in 0 ..< count { if !used[j] && entities.card_rarity(pool[j]) == .EPIC     { buf[n] = j; n += 1 } }
	}
	if n == 0 && (target == .UNIQUE || target == .EPIC) {
		for j in 0 ..< count { if !used[j] && entities.card_rarity(pool[j]) == .RARE     { buf[n] = j; n += 1 } }
	}
	if n == 0 {
		for j in 0 ..< count { if !used[j] && entities.card_rarity(pool[j]) == .UNCOMMON { buf[n] = j; n += 1 } }
	}
	if n == 0 {
		for j in 0 ..< count { if !used[j] { buf[n] = j; n += 1 } }
	}
	if n == 0 { return false }
	idx := buf[rand.int_max(n)]
	used[idx] = true
	sim.shop.choices[slot] = pool[idx]
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
			diff_mult := campaign_difficulty(app)
			hp :=
				constants.ENEMY_BASE_HP *
				math.pow(constants.ENEMY_GROWTH_RATE, f32(sim.wave_number - 1)) *
				multiplier *
				constants.ENEMY_GLOBAL_HP_MULTIPLIER *
				weaken *
				diff_mult

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
			speed *= diff_mult

			// Build per-enemy flags: inherit wave subtypes; boss flag only for the last enemy
			enemy_flags := sim.wave_flags - {.BOSS}
			if is_boss { enemy_flags |= {.BOSS} }
			enemy := entities.enemy_init(hp, speed, enemy_flags)

			// Set enemy path (this also sets initial position to spawn)
			entities.enemy_set_path(&enemy, spawn.path)

			append(&sim.enemies, enemy)
			play_sound_at(.ENEMY_SPAWN, .SFX, enemy.x, enemy.y, app)
			spawn_glow_particles(sim, enemy.x, enemy.y, entities.enemy_get_size(&enemy), .SPAWN)
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
			play_sound_at(.ENEMY_REACH_GOAL, .SFX, enemy.x, enemy.y, app)
			spawn_glow_particles(sim, enemy.x, enemy.y, entities.enemy_get_size(enemy), .GOAL_REACH)

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
			play_sound_at(.ENEMY_DEATH, .SFX, enemy.x, enemy.y, app)

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

			// Número flotante amarillo con el dinero obtenido
			if app.settings.show_damage_numbers && reward > 0 {
				mn := entities.damage_number_money_init(enemy.x, enemy.y, reward)
				append(&sim.damage_numbers, mn)
			}

			// Bloodlust: micro-bonus de daño por cada kill
			if sim.relic_stacks[.BLOODLUST] > 0 {
				sim.bloodlust_mult += constants.BLOODLUST_BONUS_PER_KILL * f32(sim.relic_stacks[.BLOODLUST])
				relic_flash(sim, .BLOODLUST)
			}

			// Carta aleatoria al matar — solo si el jugador tiene la reliquia LOOT
			if sim.relic_stacks[.LOOT] > 0 && rand.float32() < f32(sim.relic_stacks[.LOOT]) * constants.DECK_CARD_DROP_CHANCE {
				// Build drop pool: unlocked towers + obstacles + unlocked non-maxed relics
				all_loot_towers := [9]entities.Card{
					{kind = .TOWER, tower_type = .ARCHER},
					{kind = .TOWER, tower_type = .CANNON},
					{kind = .TOWER, tower_type = .SNIPER},
					{kind = .TOWER, tower_type = .MISSILE},
					{kind = .TOWER, tower_type = .LASER},
					{kind = .TOWER, tower_type = .ICE},
					{kind = .TOWER, tower_type = .ENHANCE},
					{kind = .TOWER, tower_type = .TESLA},
					{kind = .TOWER, tower_type = .MORTAR},
				}
				all_loot_relics := [16]entities.Card{
					{kind = .INTEREST_BOOST}, {kind = .STEAL},     {kind = .WEAKEN},
					{kind = .DIVIDEND},       {kind = .AUTO_UPGRADE}, {kind = .BLOODLUST},
					{kind = .FLAWLESS},       {kind = .FORMATION},  {kind = .FROZEN_AMP},
					{kind = .VETERAN},        {kind = .LOOT},       {kind = .SCOUT},
					{kind = .RECYCLER},       {kind = .MEMENTO},    {kind = .WARMED_UP},
					{kind = .CRYPTOBRO},
				}

				MAX_DROP :: 28
				drop_pool: [MAX_DROP]entities.Card
				drop_count := 0

				for c in all_loot_towers {
					if entities.meta_is_tower_unlocked(&app.meta, c.tower_type) && drop_count < MAX_DROP {
						drop_pool[drop_count] = c
						drop_count += 1
					}
				}
				// Two obstacle slots
				if drop_count < MAX_DROP { drop_pool[drop_count] = {kind = .OBSTACLE}; drop_count += 1 }
				if drop_count < MAX_DROP { drop_pool[drop_count] = {kind = .OBSTACLE}; drop_count += 1 }
				for c in all_loot_relics {
					if entities.meta_is_relic_unlocked(&app.meta, c.kind) && !entities.relic_is_maxed(sim, c.kind) && drop_count < MAX_DROP {
						drop_pool[drop_count] = c
						drop_count += 1
					}
				}

				if drop_count > 0 {
					dropped := drop_pool[rand.int_max(drop_count)]
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
			}

			// CRYPTOBRO: la torre que mató al jefe gana tantos niveles permanentes como
			// stacks tenga la reliquia. Estos niveles son adicionales a los manuales y
			// al bonus de Potenciador — no respetan el tope manual, solo TOWER_MAX_LEVEL.
			if .BOSS in enemy.flags && sim.relic_stacks[.CRYPTOBRO] > 0 && enemy.last_attacker_r >= 0 {
				for &t in sim.towers {
					if t.r == enemy.last_attacker_r && t.c == enemy.last_attacker_c {
						stacks := sim.relic_stacks[.CRYPTOBRO]
						room   := constants.TOWER_MAX_LEVEL - t.level
						gained := stacks
						if gained > room { gained = room }
						if gained > 0 {
							t.cryptobro_bonus += gained
							t.level           += gained
							entities.tower_recompute_stats(&t)
							entities.add_toast(app, fmt.tprintf("¡Cryptobro! Torre +%d Nv → Nv%d", gained, t.level), .SUCCESS, 4.0)
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

		// TESLA: instant chain lightning — no barrel rotation needed
		if tower.type == .TESLA {
			update_tesla_tower(app, &tower)
			continue
		}

		// MORTAR: fires without alignment (ballistic, indirect fire)
		if tower.type == .MORTAR {
			update_mortar_tower(app, &tower)
			continue
		}

		// Find target
		target_enemy := find_target(app, &tower)
		tower.target = target_enemy

		// CRANE_KICK: si hay cargas pendientes y hay objetivo, mata instantáneamente.
		if tower.crane_kick_charges > 0 && tower.target != nil {
			target := tower.target
			dmg    := target.hp
			tower.total_damage        += dmg
			target.hp                  = 0
			tower.crane_kick_charges  -= 1
			spawn_damage_number(app, target.x + 0.5, target.y + 0.5, dmg, true)
			play_sound_at(.EXPLOSION, .SFX, target.x, target.y, app)
		}

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
				case .ICE, .ENHANCE, .TESLA, .MORTAR:
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
	play_sound_at(.TOWER_ICE, .SFX, f32(tower.c), f32(tower.r), app)
}

// Update TESLA tower — instant chain lightning hitting up to TESLA_CHAIN_COUNT enemies
update_tesla_tower :: proc(app: ^entities.App_State, tower: ^entities.Tower) {
	if tower.timer > 0 { return }

	// Find primary target
	primary := find_target(app, tower)
	if primary == nil { return }

	tower.timer = entities.tower_get_effective_cooldown(tower)
	sim        := &app.sim

	// Chain: track which enemy indices have already been hit
	MAX_CHAIN :: constants.TESLA_CHAIN_COUNT
	hit_idx   : [MAX_CHAIN]int
	hit_count := 0

	cur_x  := f32(tower.c) + 0.5
	cur_y  := f32(tower.r) + 0.5
	cur_dmg := tower.damage

	for chain in 0 ..< MAX_CHAIN {
		// Slot 0 = primary target; later slots = nearest unhit within chain range
		next  : ^entities.Enemy = nil
		next_i    := -1

		if chain == 0 {
			next = primary
			for i in 0 ..< len(sim.enemies) {
				if &sim.enemies[i] == primary { next_i = i; break }
			}
		} else {
			best_dist := constants.TESLA_CHAIN_RANGE
			for i in 0 ..< len(sim.enemies) {
				already := false
				for j in 0 ..< hit_count {
					if hit_idx[j] == i { already = true; break }
				}
				if already { continue }
				e  := &sim.enemies[i]
				dx := (e.x + 0.5) - cur_x
				dy := (e.y + 0.5) - cur_y
				d  := math.sqrt_f32(dx*dx + dy*dy)
				if d <= best_dist {
					best_dist = d
					next      = e
					next_i    = i
				}
			}
		}

		if next == nil { break }

		if hit_count < MAX_CHAIN {
			hit_idx[hit_count] = next_i
			hit_count += 1
		}

		// Apply damage
		is_crit := rand.float32() < entities.tower_get_critical_chance(tower)
		dmg := cur_dmg
		if is_crit { dmg *= constants.CRIT_DAMAGE_MULTIPLIER }
		dmg = calc_damage(app, dmg, tower, next)
		next.hp -= dmg
		tower.total_damage += dmg
		spawn_damage_number(app, next.x + 0.5, next.y + 0.5, dmg, is_crit)

		// Spawn lightning arc (reuse laser_beam with TESLA color and arc duration)
		beam := entities.laser_beam_init(
			cur_x, cur_y,
			next.x + 0.5, next.y + 0.5,
			constants.TOWER_TESLA_ARC,
			constants.TESLA_ARC_DURATION,
		)
		append(&sim.laser_beams, beam)

		cur_x   = next.x + 0.5
		cur_y   = next.y + 0.5
		cur_dmg *= constants.TESLA_CHAIN_FALLOFF
	}

	play_sound_at(.TOWER_ICE, .SFX, f32(tower.c), f32(tower.r), app)
}

// Update MORTAR tower — fires a slow ballistic shell without waiting for alignment
update_mortar_tower :: proc(app: ^entities.App_State, tower: ^entities.Tower) {
	if tower.timer > 0 { return }

	target := find_target(app, tower)
	if target == nil { return }

	tower.timer = entities.tower_get_effective_cooldown(tower)
	sim        := &app.sim

	cx := f32(tower.c) + 0.5
	cy := f32(tower.r) + 0.5

	proj := entities.projectile_init(
		cx, cy,
		target,
		constants.PROJECTILE_SPEED_MORTAR,
		tower.damage,
		.FIRST,
		tower.type,
		tower.aoe,
		tower.r,
		tower.c,
	)
	append(&sim.projectiles, proj)
	play_sound_at(.TOWER_CANNON, .SFX, f32(tower.c), f32(tower.r), app)
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

		manual_level := t.level - t.enhance_bonus - t.cryptobro_bonus
		max_bonus    := constants.TOWER_MAX_LEVEL - manual_level - t.cryptobro_bonus
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
			play_sound_at(.TOWER_LASER, .SFX, f32(tower.c), f32(tower.r), app)
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
		case .ARCHER:  play_sound_at(.TOWER_ARCHER,  .SFX, f32(tower.c), f32(tower.r), app)
		case .CANNON:  play_sound_at(.TOWER_CANNON,  .SFX, f32(tower.c), f32(tower.r), app)
		case .SNIPER:  play_sound_at(.TOWER_SNIPER,  .SFX, f32(tower.c), f32(tower.r), app)
		case .MISSILE: play_sound_at(.TOWER_MISSILE, .SFX, f32(tower.c), f32(tower.r), app)
		case .LASER, .ICE, .ENHANCE, .TESLA, .MORTAR: // handled separately
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
			// CANNON, SNIPER, MORTAR cannot target flying enemies
			// Only ARCHER, MISSILE, LASER, TESLA can target flying enemies
			can_target_flying :=
				tower.type == .ARCHER || tower.type == .MISSILE ||
				tower.type == .LASER  || tower.type == .TESLA
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
				play_sound_at(.PROJECTILE_HIT, .SFX, proj.target.x, proj.target.y, app)
			}

			// AoE: se activa siempre al impactar, haya o no objetivo vivo.
			// Esto genera la explosión "en el suelo" cuando el objetivo murió antes de ser alcanzado.
			if proj.aoe > 0 {
				spawn_explosion(app, proj.x, proj.y, proj.aoe)
				play_sound_at(.EXPLOSION, .SFX, proj.x, proj.y, app)

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

			// REBOUND: rebotar a enemigo cercano si la reliquia está activa
			bounced := false
			if sim.relic_stacks[.REBOUND] > 0 {
				// Inicializar bounces_left al primer impacto
				if proj.bounces_left < 0 {
					proj.bounces_left = sim.relic_stacks[.REBOUND] / constants.REBOUND_STACKS_PER_BOUNCE
				}
				if proj.bounces_left > 0 {
					hit_x := proj.x
					hit_y := proj.y
					exclude := proj.last_hit_enemy
					if proj.target != nil { exclude = proj.target }

					bounce_target : ^entities.Enemy = nil
					best_dist     := constants.REBOUND_RANGE + 1
					for &enemy in sim.enemies {
						if &enemy == exclude { continue }
						if enemy.hp <= 0 { continue }
						dx := enemy.x - hit_x
						dy := enemy.y - hit_y
						d  := math.sqrt_f32(dx*dx + dy*dy)
						if d <= constants.REBOUND_RANGE && d < best_dist {
							bounce_target = &enemy
							best_dist = d
						}
					}

					if bounce_target != nil {
						proj.last_hit_enemy  = exclude
						proj.target          = bounce_target
						proj.target_orig_x   = bounce_target.x
						proj.target_orig_y   = bounce_target.y
						proj.target_last_x   = bounce_target.x
						proj.target_last_y   = bounce_target.y
						proj.bounces_left   -= 1
						bounced = true
					}
				}
			}

			// Remove projectile si no rebotó
			if !bounced {
				ordered_remove(&sim.projectiles, i)
			}
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
		if t.level - t.enhance_bonus - t.cryptobro_bonus >= manual_cap do continue
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

// Emite N partículas de glow en la posición dada.
// kind == .SPAWN  → círculos blancos que suben
// kind == .GOAL_REACH → círculos rojo oscuro que bajan
spawn_glow_particles :: proc(sim: ^entities.Simulation, gx, gy: f32, enemy_radius: f32, kind: entities.Glow_Particle_Kind) {
	// Mismo lifetime para todos → equidistancia garantizada con easing cuadrático idéntico.
	// Cada anillo i viaja (i+1)*RING_STEP celdas: separación constante = RING_STEP*progress².
	RING_STEP :: f32(0.45)   // distancia entre anillos consecutivos, en fracciones de celda
	LIFETIME  :: f32(0.50)

	// 0.4 = radio del círculo de spawn/goal (render_spawn / render_goal usan cs * 0.4)
	circle_r :: f32(0.4)

	for i in 0 ..< 4 {
		dist := f32(i + 1) * RING_STEP  // distancia total que recorre este anillo
		// SPAWN: parte del centro (dy=0), sube (dy negativo al final)
		// GOAL:  parte desplazado arriba (dy negativo), llega al centro (dy=0)
		dy_s := f32(0)
		dy_e := -dist

		// SPAWN:      empieza en el círculo verde (circle_r=0.4) → se achica al tamaño del enemigo
		// GOAL_REACH: empieza en el círculo rojo (circle_r=0.4, desde arriba) → se achica al tamaño del enemigo
		//             Los anillos caen grandes y se contraen al llegar al centro — espejo del spawn.
		r_start := circle_r
		r_end   := enemy_radius

		append(&sim.glow_particles, entities.Glow_Particle{
			grid_x       = gx + 0.5,
			grid_y       = gy + 0.5,
			t            = 0,
			lifetime     = LIFETIME,
			radius_start = r_start,
			radius_end   = r_end,
			dy_start     = dy_s,
			dy_end       = dy_e,
			kind         = kind,
		})
	}
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
	delete(app.sim.glow_particles)
	delete(app.sim.cards.deck)
	delete(app.sim.cards.hand)
	delete(app.sim.cards.discard)
	delete(app.sim.airdrops)
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
		glow_particles   = make([dynamic]entities.Glow_Particle),
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
		cards = entities.Card_State{
			deck              = make([dynamic]entities.Card),
			hand              = make([dynamic]entities.Card),
			discard           = make([dynamic]entities.Card),
			hand_size         = constants.DECK_HAND_SIZE,
			selected_card_idx = -1,
		},
		// Shop
		shop = entities.Shop_State{
			active               = false,
			choices              = {},
			bought               = {},
			locked               = {},
			slot_count           = constants.SHOP_BASE_SLOTS,
			rerolls_this_visit   = 0,
			shops_since_unique   = 0,
			skip_streak_count    = 0,
			purchases_this_visit = 0,
		},
		auto_upgrade_timer     = 0,
		wave_start_money       = 0,
		steal_last_wave        = 0,
		bloodlust_mult         = 1.0,
		wave_start_health      = 0,
		inter_wave_timer       = 0,

		airdrops         = make([dynamic]entities.Airdrop),
		airdrop_timer    = constants.AIRDROP_SPAWN_INTERVAL_MIN + rand.float32() * (constants.AIRDROP_SPAWN_INTERVAL_MAX - constants.AIRDROP_SPAWN_INTERVAL_MIN),
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
	// (build_starter_deck puebla sim.cards.hand directamente con la composición garantizada)
	entities.build_starter_deck(&app.sim, &app.meta)

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
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER,
			     .TOWER_ICE, .TOWER_ENHANCE, .TOWER_TESLA, .TOWER_MORTAR:
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
				case .TOWER_TESLA:
					tower_type = .TESLA
				case .TOWER_MORTAR:
					tower_type = .MORTAR
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

// Ajusta zoom y cámara para que la grilla del editor quepa centrada en pantalla.
// Llamar después de simulation_init_from_editor, desde un sitio que tenga acceso al screen size.
simulation_fit_camera :: proc(app: ^entities.App_State, screen_w, screen_h: f32) {
	MARGIN :: f32(24)
	m  := &app.editor.game_map
	cs := f32(app.settings.cell_size)

	zoom_x := (screen_w - MARGIN * 2) / (f32(m.width)  * cs)
	zoom_y := (screen_h - MARGIN * 2) / (f32(m.height) * cs)
	zoom   := clamp(min(zoom_x, zoom_y), constants.ZOOM_MIN, constants.ZOOM_MAX)

	grid_w := f32(m.width)  * cs * zoom
	grid_h := f32(m.height) * cs * zoom

	app.zoom                   = zoom
	app.target_zoom            = zoom
	app.camera_offset_x        = i32((screen_w - grid_w) / 2)
	app.camera_offset_y        = i32((screen_h - grid_h) / 2)
	app.target_camera_offset_x = app.camera_offset_x
	app.target_camera_offset_y = app.camera_offset_y
}
// =============================================================================
// Airdrop
// =============================================================================

// Elige un tile EMPTY (no camino, no torre, no agua, no obstáculo) aleatorio.
// Devuelve false si no hay ninguno disponible.
airdrop_pick_tile :: proc(app: ^entities.App_State) -> (row, col: i32, ok: bool) {
	m := &app.editor.game_map
	candidates : [dynamic]struct{r, c: i32}
	defer delete(candidates)

	for r in 0 ..< m.height {
		for c in 0 ..< m.width {
			tile     := m.grid[r][c]
			is_empty := tile == .EMPTY
			no_obs   := m.obstacle_grid[r][c] == .EMPTY
			no_water := !m.water_grid[r][c]
			if is_empty && no_obs && no_water {
				append(&candidates, struct{r, c: i32}{r, c})
			}
		}
	}
	if len(candidates) == 0 { return 0, 0, false }
	idx := rand.int_max(len(candidates))
	return candidates[idx].r, candidates[idx].c, true
}

// Spawnea un nuevo airdrop con trayectoria angular aleatoria que pasa por el tile destino.
airdrop_spawn :: proc(app: ^entities.App_State) {
	r, c, ok := airdrop_pick_tile(app)
	if !ok { return }

	m  := &app.editor.game_map
	cs := f32(app.settings.cell_size)

	// Centro del tile destino en world space
	target_wx := (f32(c) + 0.5) * cs
	target_wy := (f32(r) + 0.5) * cs

	// Ángulo aleatorio (evitamos ángulos casi perpendiculares al grid que quedan raros)
	angle := rand.float32() * (math.PI * 2)
	dir_x := math.cos_f32(angle)
	dir_y := math.sin_f32(angle)

	// Calcular punto de entrada: retroceder desde el tile destino a lo largo de (-dir)
	// hasta salir del mapa con margen de 80 world px
	MARGIN :: f32(80)
	map_w  := f32(m.width)  * cs
	map_h  := f32(m.height) * cs

	// Intersección del rayo (target - dir*t) con cada borde extendido por MARGIN
	t_entry := f32(1e9)
	if dir_x > 0.0001 {
		t := (target_wx - (-MARGIN)) / dir_x
		if t > 0 && t < t_entry { t_entry = t }
	} else if dir_x < -0.0001 {
		t := (target_wx - (map_w + MARGIN)) / dir_x
		if t > 0 && t < t_entry { t_entry = t }
	}
	if dir_y > 0.0001 {
		t := (target_wy - (-MARGIN)) / dir_y
		if t > 0 && t < t_entry { t_entry = t }
	} else if dir_y < -0.0001 {
		t := (target_wy - (map_h + MARGIN)) / dir_y
		if t > 0 && t < t_entry { t_entry = t }
	}

	plane_x := target_wx - dir_x * t_entry
	plane_y := target_wy - dir_y * t_entry

	drop := entities.Airdrop{
		plane_x     = plane_x,
		plane_y     = plane_y,
		plane_dir_x = dir_x,
		plane_dir_y = dir_y,
		target_row  = r,
		target_col  = c,
		target_wx   = target_wx,
		target_wy   = target_wy,
		phase       = .PLANE_FLYING,
		chute_t     = 1.0,
		dropped     = false,
	}
	append(&app.sim.airdrops, drop)
}

// Actualiza todos los airdrops activos y el timer de spawn.
airdrop_update :: proc(app: ^entities.App_State, dt: f32) {
	sim := &app.sim
	m   := &app.editor.game_map
	cs  := f32(app.settings.cell_size)

	// Spawn timer
	sim.airdrop_timer -= dt
	if sim.airdrop_timer <= 0 {
		airdrop_spawn(app)
		// Reliquia AIRDROP: divide el intervalo por (1 + stacks * factor) → nunca llega a 0
		base_interval := constants.AIRDROP_SPAWN_INTERVAL_MIN +
		                 rand.float32() * (constants.AIRDROP_SPAWN_INTERVAL_MAX - constants.AIRDROP_SPAWN_INTERVAL_MIN)
		speed_factor  := 1.0 + constants.AIRDROP_RELIC_SPEED_PER_STACK * f32(sim.relic_stacks[.AIRDROP])
		sim.airdrop_timer = base_interval / speed_factor
	}

	// Update each airdrop
	i := 0
	for i < len(sim.airdrops) {
		drop := &sim.airdrops[i]

		switch drop.phase {
		case .PLANE_FLYING:
			// Mover avión a lo largo de su dirección
			speed := constants.AIRDROP_PLANE_SPEED
			drop.plane_x += drop.plane_dir_x * speed * dt
			drop.plane_y += drop.plane_dir_y * speed * dt

			// Samplear estela jet
			drop.trail_timer += dt
			if drop.trail_timer >= constants.AIRDROP_TRAIL_INTERVAL {
				drop.trail_timer = 0
				idx := (drop.trail_head + drop.trail_len) % i32(len(drop.trail))
				drop.trail[idx] = {drop.plane_x, drop.plane_y}
				if drop.trail_len < i32(len(drop.trail)) {
					drop.trail_len += 1
				} else {
					drop.trail_head = (drop.trail_head + 1) % i32(len(drop.trail))
				}
			}

			// Soltar caja cuando el avión supera el tile destino (producto punto >= 0)
			to_target_x := drop.target_wx - drop.plane_x
			to_target_y := drop.target_wy - drop.plane_y
			passed := (to_target_x * drop.plane_dir_x + to_target_y * drop.plane_dir_y) <= 0

			if !drop.dropped && passed {
				drop.dropped = true
				drop.chute_t = 1.0
				drop.phase   = .BOX_FALLING
			}

			// Eliminar avión cuando sale de la PANTALLA (igual que los pájaros)
			sw     := f32(raylib.GetScreenWidth())
			sh     := f32(raylib.GetScreenHeight())
			screen_x := drop.plane_x * app.zoom + f32(app.camera_offset_x)
			screen_y := drop.plane_y * app.zoom + f32(app.camera_offset_y)
			MARGIN :: f32(100)
			out := screen_x < -MARGIN || screen_x > sw + MARGIN ||
			       screen_y < -MARGIN || screen_y > sh + MARGIN
			if out && drop.dropped {
				// El avión salió de pantalla tras soltar la carga — lo eliminamos
				// La caja sigue en su propio ciclo (phase BOX_FALLING/LANDED)
				drop.plane_x = -99999 // marca invisible para el renderer
			}
			if out && !drop.dropped {
				// Nunca soltó (caso extremo): eliminar todo
				ordered_remove(&sim.airdrops, i)
				continue
			}

		case .BOX_FALLING:
			// chute_t shrinks from 1.0 to 0.0 over AIRDROP_BOX_FALL_SPEED seconds
			drop.chute_t -= dt / constants.AIRDROP_BOX_FALL_SPEED
			if drop.chute_t <= 0 {
				drop.chute_t = 0
				drop.phase   = .BOX_LANDED
			}
			airdrop_update_ping(drop, dt)

		case .BOX_LANDED:
			// Waiting for player click
			airdrop_update_ping(drop, dt)
		}

		i += 1
	}
}

// Recoge una caja en (row, col). Aplica loot y devuelve true si había una caja.
airdrop_collect :: proc(app: ^entities.App_State, row, col: i32) -> bool {
	sim := &app.sim
	for i in 0 ..< len(sim.airdrops) {
		drop := &sim.airdrops[i]
		if drop.phase != .BOX_LANDED { continue }
		if drop.target_row != row || drop.target_col != col { continue }

		// ── Loot ─────────────────────────────────────────────────────────────
		// 1. Dinero
		money := constants.AIRDROP_MONEY_MIN +
		         i32(rand.float32() * f32(constants.AIRDROP_MONEY_MAX - constants.AIRDROP_MONEY_MIN + 1))
		entities.app_add_money(app, money)

		// 2. Carta de reliquia aleatoria a la mano (de las desbloqueadas y no maxeadas).
		// Con la reliquia AIRDROP, las rarezas más altas tienen más peso.
		relic_given  := false
		airdrop_stacks := sim.relic_stacks[.AIRDROP]

		// Pesos por rareza: base + bonus por stack de AIRDROP
		// Con 0 stacks: Common=40, Uncommon=15, Rare=4, Epic=1 → ~67/25/7/2%
		// Con 20 stacks: Common=40, Uncommon=55, Rare=64, Epic=41 → ~20/28/32/21%
		rarity_weight :: proc(rarity: constants.Card_Rarity, stacks: i32) -> int {
			switch rarity {
			case .COMMON:   return 40
			case .UNCOMMON: return 15 + int(stacks) * 2
			case .RARE:     return 4  + int(stacks) * 3
			case .EPIC:     return 1  + int(stacks) * 2
			case .UNIQUE:   return 0
			}
			return 0
		}

		// Construir pool con pesos
		pool_kinds:   [dynamic]entities.Card_Kind
		pool_weights: [dynamic]int
		defer delete(pool_kinds)
		defer delete(pool_weights)
		total_weight := 0
		for spec in entities.RELIC_SPECS {
			if entities.meta_is_relic_unlocked(&app.meta, spec.kind) && !entities.relic_is_maxed(sim, spec.kind) {
				w := rarity_weight(entities.card_rarity(entities.Card{kind = spec.kind}), airdrop_stacks)
				if w > 0 {
					append(&pool_kinds, spec.kind)
					append(&pool_weights, w)
					total_weight += w
				}
			}
		}
		if len(pool_kinds) > 0 {
			// Selección ponderada
			roll := rand.int_max(total_weight)
			cum  := 0
			kind := pool_kinds[0]
			for i in 0 ..< len(pool_kinds) {
				cum += pool_weights[i]
				if roll < cum {
					kind = pool_kinds[i]
					break
				}
			}
			card := entities.Card{kind = kind}
			entities.card_add_to_hand(sim, card)
			relic_given = true
			relic_name  := entities.card_name(card)
			entities.add_toast(app, fmt.tprintf("📦 %s + $%d", relic_name, money), .SUCCESS, 3.0)
		} else {
			entities.add_toast(app, fmt.tprintf("📦 $%d", money), .SUCCESS, 2.5)
		}

		// 3. Cristales (10% chance)
		if rand.float32() < constants.AIRDROP_CRYSTAL_CHANCE {
			crystals := constants.AIRDROP_CRYSTAL_MIN +
			            i32(rand.float32() * f32(constants.AIRDROP_CRYSTAL_MAX - constants.AIRDROP_CRYSTAL_MIN + 1))
			app.meta.cristales += crystals
			app.meta_dirty = true
			entities.add_toast(app, fmt.tprintf("+%d cristales!", crystals), .INFO, 2.5)
		}

		_ = relic_given
		ordered_remove(&sim.airdrops, i)
		play_sound(.CONFIRMATION, .UI)
		return true
	}
	return false
}

// Actualiza el estado del ping convergente de un airdrop.
// Llamar desde las fases BOX_FALLING y BOX_LANDED.
airdrop_update_ping :: proc(drop: ^entities.Airdrop, dt: f32) {
	if drop.ping_t > 0 {
		// Anillo activo: encoger hasta 0
		drop.ping_t -= dt / constants.AIRDROP_PING_DURATION
		if drop.ping_t <= 0 {
			drop.ping_t     = -1  // marcar inactivo
			drop.ping_timer = constants.AIRDROP_PING_INTERVAL
		}
	} else {
		// Esperar el intervalo antes del próximo ping
		drop.ping_timer -= dt
		if drop.ping_timer <= 0 {
			drop.ping_t = 1.0  // lanzar nuevo ping
		}
	}
}

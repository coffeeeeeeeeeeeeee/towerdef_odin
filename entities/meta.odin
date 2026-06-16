package entities

import "core:fmt"
import "core:os"
import "core:mem"
import "../constants"

// Version 1: original (cristales, unlocks).
// Version 2: agrega progreso de campaña (campaign_completed/best/stars).
//   Migración: archivos v1 se descartan y arrancan zero — los unlocks de
//   relics/towers y los cristales se pierden. Aceptable durante desarrollo;
//   para un release habría que hacer parsing v1 explícito y upgrade.
META_SAVE_VERSION :: u32(3)
META_SAVE_PATH    :: "savegame.bin"

// Persistent state across runs — saved to savegame.bin in the executable directory.
Meta_State :: struct {
	version:         u32,
	cristales:       i32,                    // total accumulated currency
	total_runs:      i32,                    // total runs completed
	best_score:      i32,                    // best run score ever
	unlocked_relics: [Card_Kind]bool,        // which relics are available in the shop
	unlocked_towers: [9]bool,                // indexed by Tower_Type value; base towers always unlocked

	// ── Campaña (v2) ────────────────────────────────────────────────────────
	// Indexados por nodo de Campaign_File. Si la campaña se rehace y los índices
	// cambian, el progreso queda corrupto — es responsabilidad del dev resetear
	// savegame.bin al cambiar la estructura de la campaña.
	campaign_completed: [constants.CAMPAIGN_MAX_NODES]bool,
	campaign_best:      [constants.CAMPAIGN_MAX_NODES]i32,  // mejor wave alcanzada por nodo
	campaign_stars:     [constants.CAMPAIGN_MAX_NODES]u8,   // 0-3 estrellas por nodo

	_pad: [16]u8,  // reserva para futuro (reducido de 55 al meter campaign_*)
}

// Towers that are always available without spending cristales.
meta_is_tower_unlocked :: proc(meta: ^Meta_State, t: constants.Tower_Type) -> bool {
	#partial switch t {
	case .ARCHER, .CANNON, .SNIPER:
		return true
	}
	return meta.unlocked_towers[int(t)]
}

// Cristal cost to unlock a tower (0 for always-free towers).
meta_tower_unlock_cost :: proc(t: constants.Tower_Type) -> i32 {
	#partial switch t {
	case .ICE:     return 5
	case .ENHANCE: return 5
	case .MISSILE: return 10
	case .LASER:   return 15
	case .TESLA:   return 20
	case .MORTAR:  return 20
	}
	return 0
}

// Tier of a relic — determines its unlock cost.
// Returns 0 for non-relics (TOWER, OBSTACLE).
meta_relic_tier :: proc(kind: Card_Kind) -> i32 {
	#partial switch kind {
	case .INTEREST_BOOST, .LOOT, .RECYCLER, .SCOUT, .WEAKEN, .LUMBERJACK:
		return 1
	case .DIVIDEND, .STEAL, .BLOODLUST, .FLAWLESS, .MEMENTO, .WARMED_UP:
		return 2
	case .AUTO_UPGRADE, .FORMATION, .FROZEN_AMP, .VETERAN, .CRYPTOBRO, .SHOPPING_CART:
		return 3
	}
	return 0
}

// Cristal cost to unlock a relic based on tier (Tier1=5, Tier2=10, Tier3=20).
meta_relic_unlock_cost :: proc(kind: Card_Kind) -> i32 {
	switch meta_relic_tier(kind) {
	case 1: return 5
	case 2: return 10
	case 3: return 20
	case: return 0
	}
}

// Per-component cristal contributions — used for the end-of-run breakdown.
meta_cristales_from_waves :: proc(waves: i32) -> i32  { return waves / 5 }
meta_cristales_from_kills :: proc(kills: i32) -> i32  { return kills / 200 }
meta_cristales_from_lives :: proc(lives: i32) -> i32  { return lives / 10 }

// Total cristales earned for a run. Min 1 if the player survived at least 5 waves.
meta_calc_cristales :: proc(kills, lives_remaining, waves_completed: i32) -> i32 {
	c := meta_cristales_from_waves(waves_completed) +
	     meta_cristales_from_kills(kills) +
	     meta_cristales_from_lives(lives_remaining)
	if c == 0 && waves_completed >= 5 {
		c = 1
	}
	return c
}

// ─────────────────────────────────────────────────────────────────────────────
// Campaña — cálculo de estrellas y registro de resultado de nodo
// ─────────────────────────────────────────────────────────────────────────────

// Calcula las estrellas obtenidas en un nodo de campaña.
//   0 = no completado
//   1 = completado (apenas)
//   2 = completado con vidas
//   3 = completado con la mayoría de las vidas intactas
meta_calc_campaign_stars :: proc(waves_completed, lives_remaining, waves_required: i32) -> u8 {
	if waves_completed < waves_required { return 0 }
	if lives_remaining <= 0 { return 1 }
	half : i32 = constants.DEFAULT_HEALTH / 2
	if lives_remaining < half { return 2 }
	return 3
}

// Registra el resultado de un run de campaña en el progreso del jugador.
// Solo MEJORA los campos — no degrada un mejor resultado previo.
meta_record_campaign_result :: proc(
	meta: ^Meta_State,
	node_idx: i32,
	waves_completed, lives_remaining, waves_required: i32,
	victory: bool,
) {
	if node_idx < 0 || node_idx >= i32(constants.CAMPAIGN_MAX_NODES) { return }
	if victory {
		meta.campaign_completed[node_idx] = true
	}
	if waves_completed > meta.campaign_best[node_idx] {
		meta.campaign_best[node_idx] = waves_completed
	}
	stars := meta_calc_campaign_stars(waves_completed, lives_remaining, waves_required)
	if stars > meta.campaign_stars[node_idx] {
		meta.campaign_stars[node_idx] = stars
	}
}

// Save meta state to savegame.bin.
meta_save :: proc(meta: ^Meta_State) {
	meta.version = META_SAVE_VERSION
	data := mem.ptr_to_bytes(meta)
	os.write_entire_file(META_SAVE_PATH, data)
}

// Load meta state from savegame.bin.
// Returns a zeroed Meta_State if the file is missing or the version mismatches.
// IMPORTANTE: hoy no hay migración entre versiones — un save de versión vieja
// se descarta (cristales y unlocks vuelven a 0). Esto sólo se acepta porque el
// juego está en desarrollo. Para release implementar parser por versión
// (ver auditoría issue #2).
meta_load :: proc() -> Meta_State {
	meta := Meta_State{}
	data, ok := os.read_entire_file_from_filename(META_SAVE_PATH)
	if !ok { return meta }
	defer delete(data)

	if len(data) != size_of(Meta_State) {
		fmt.printfln(
			"[meta_load] descartando savegame.bin: size=%d (esperado %d). Progreso reseteado.",
			len(data), size_of(Meta_State),
		)
		return Meta_State{}
	}

	meta = (cast(^Meta_State)raw_data(data))^
	if meta.version != META_SAVE_VERSION {
		fmt.printfln(
			"[meta_load] descartando savegame.bin: version=%d (esperado %d). Progreso reseteado.",
			meta.version, META_SAVE_VERSION,
		)
		return Meta_State{}
	}
	return meta
}

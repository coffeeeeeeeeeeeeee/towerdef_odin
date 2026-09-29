package entities

import "core:fmt"
import "core:os"
import "core:mem"
import "../constants"

// Version 1: original (cristales, unlocks).
// Version 2: agrega progreso de campaña (campaign_completed/best/stars).
// Version 3: agrega SHOPPING_CART/LUMBERJACK al enum (size change).
// Version 4: costos de reliquias por rareza (bool arrays, misma estructura que v3 pero distinto significado).
// Version 5: agrega REBOUND al enum Card_Kind; descarta saves anteriores para evitar bits stale.
// Version 6: agrega OVERDRIVE al enum Card_Kind; descarta saves anteriores para evitar bits stale.
//   Migración: archivos anteriores se descartan y arrancan zero. Aceptable durante desarrollo.
META_SAVE_VERSION :: u32(6)
GAME_SAVE_DIR     :: "towerdef"

// Devuelve la ruta al archivo de guardado según la plataforma.
// Usa context.temp_allocator — válido en el frame actual.
// Linux : ~/.local/share/towerdef/savegame.bin
// Windows: savegame.bin (directorio junto al ejecutable)
meta_save_path :: proc() -> string {
	when ODIN_OS == .Linux {
		home := os.get_env("HOME", context.temp_allocator)
		if home == "" { return "savegame.bin" }
		dir := fmt.tprintf("%s/.local/share/%s", home, GAME_SAVE_DIR)
		os.make_directory(dir)
		return fmt.tprintf("%s/savegame.bin", dir)
	} else {
		return "savegame.bin"
	}
}

// Persistent state across runs — saved to savegame.bin in the executable directory.
Meta_State :: struct {
	version:          u32,
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

// Towers always free — never require cristales.
meta_tower_is_free :: proc(t: constants.Tower_Type) -> bool {
	#partial switch t {
	case .ARCHER, .CANNON, .SNIPER:
		return true
	}
	return false
}

// Cristales necesarios para desbloquear cualquier carta (torre o reliquia)
// de esta rareza — un único precio por categoría, igual para todo lo que
// cae en esa fila de la Biblioteca (ver render_card_library_ui). Antes
// había un costo por torre y otro por rareza de reliquia, con valores muy
// dispares entre sí (una torre costaba mucho más que una reliquia de la
// "misma" rareza, y MISSILE/LASER —ambas RARE— ni siquiera coincidían
// entre sí) — no tenía sentido mostrar un solo precio por categoría con
// esa base, así que se unificó.
meta_rarity_unlock_cost :: proc(rarity: constants.Card_Rarity) -> i32 {
	switch rarity {
	case .COMMON:   return 1
	case .UNCOMMON: return 3
	case .RARE:     return 6
	case .EPIC:     return 10
	case .UNIQUE:   return 15
	}
	return 0
}

// Torre desbloqueada si es gratuita o si fue comprada con cristales.
meta_is_tower_unlocked :: proc(meta: ^Meta_State, t: constants.Tower_Type) -> bool {
	if meta_tower_is_free(t) { return true }
	return meta.unlocked_towers[int(t)]
}

// Reliquia desbloqueada si fue comprada con cristales.
meta_is_relic_unlocked :: proc(meta: ^Meta_State, kind: Card_Kind) -> bool {
	return meta.unlocked_relics[kind]
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

// Save meta state al archivo de guardado de la plataforma.
meta_save :: proc(meta: ^Meta_State) {
	meta.version = META_SAVE_VERSION
	data := mem.ptr_to_bytes(meta)
	_ = os.write_entire_file(meta_save_path(), data)
}

// Load meta state desde el archivo de guardado de la plataforma.
// Returns a zeroed Meta_State if the file is missing or the version mismatches.
// IMPORTANTE: hoy no hay migración entre versiones — un save de versión vieja
// se descarta (cristales y unlocks vuelven a 0). Esto sólo se acepta porque el
// juego está en desarrollo. Para release implementar parser por versión
// (ver auditoría issue #2).
meta_load :: proc() -> Meta_State {
	path := meta_save_path()
	meta := Meta_State{}
	data, read_err := os.read_entire_file_from_path(path, context.allocator)
	if read_err != nil { return meta }
	defer delete(data)

	if len(data) != size_of(Meta_State) {
		fmt.printfln(
			"[meta_load] descartando %s: size=%d (esperado %d). Progreso reseteado.",
			path, len(data), size_of(Meta_State),
		)
		return Meta_State{}
	}

	meta = (cast(^Meta_State)raw_data(data))^
	if meta.version != META_SAVE_VERSION {
		fmt.printfln(
			"[meta_load] descartando %s: version=%d (esperado %d). Progreso reseteado.",
			path, meta.version, META_SAVE_VERSION,
		)
		return Meta_State{}
	}
	return meta
}

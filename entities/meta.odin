package entities

import "core:os"
import "core:mem"
import "../constants"

META_SAVE_VERSION :: u32(1)
META_SAVE_PATH    :: "savegame.bin"

// Persistent state across runs — saved to savegame.bin in the executable directory.
Meta_State :: struct {
	version:         u32,
	cristales:       i32,          // total accumulated currency
	total_runs:      i32,          // total runs completed
	best_score:      i32,          // best run score ever
	unlocked_relics: [Card_Kind]bool,    // which relics are available in the shop
	unlocked_towers: [9]bool,            // indexed by Tower_Type value; base towers always unlocked
	_pad:            [55]u8,             // reserved for future expansion (was [64])
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
	case .INTEREST_BOOST, .LOOT, .RECYCLER, .SCOUT, .WEAKEN:
		return 1
	case .DIVIDEND, .STEAL, .BLOODLUST, .FLAWLESS, .MEMENTO, .WARMED_UP:
		return 2
	case .AUTO_UPGRADE, .FORMATION, .FROZEN_AMP, .VETERAN, .CRYPTOBRO:
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

// Save meta state to savegame.bin.
meta_save :: proc(meta: ^Meta_State) {
	meta.version = META_SAVE_VERSION
	data := mem.ptr_to_bytes(meta)
	os.write_entire_file(META_SAVE_PATH, data)
}

// Load meta state from savegame.bin.
// Returns a zeroed Meta_State if the file is missing or the version mismatches.
meta_load :: proc() -> Meta_State {
	meta := Meta_State{}
	data, ok := os.read_entire_file_from_filename(META_SAVE_PATH)
	if ok {
		defer delete(data)
		if len(data) == size_of(Meta_State) {
			meta = (cast(^Meta_State)raw_data(data))^
			if meta.version != META_SAVE_VERSION {
				meta = Meta_State{}
			}
		}
	}
	return meta
}

package entities

import "../constants"
import "core:math/rand"
import raylib "vendor:raylib"

// Tipo de carta
Card_Kind :: enum {
	TOWER,           // valor cero → compatible con código existente
	OBSTACLE,
	INTEREST_BOOST,  // +INTEREST_RATE de interés por oleada (acumulable)
	WEAKEN,          // enemigos con -WEAKEN_HP_REDUCTION × stacks de HP (acumulable)
	DIVIDEND,        // al final de cada oleada devuelve un % del dinero gastado (acumulable)
	STEAL,           // roba una carta del mazo al inicio de cada oleada (acumulable)
	AUTO_UPGRADE,    // cada AUTO_UPGRADE_INTERVAL actualiza las torres más baratas (acumulable)
	BLOODLUST,       // cada kill aumenta el multiplicador de daño de todas las torres (acumulable)
	FLAWLESS,        // +oro al final de oleadas sin perder vidas (acumulable)
	FORMATION,       // torres del mismo tipo en línea de 3+ reciben bonus de daño (acumulable)
	FROZEN_AMP,      // enemigos ralentizados reciben daño amplificado (acumulable)
	VETERAN,         // cartas de torre en el shop aparecen pre-niveladas según stacks (acumulable)
	LOOT,            // chance de obtener carta aleatoria al matar un enemigo (acumulable)
}

// Una carta del mazo
Card :: struct {
	kind:        Card_Kind,
	tower_type:  constants.Tower_Type, // solo válido si kind == .TOWER
	bonus_level: i32,                  // niveles extra pre-aplicados (solo torres del shop con VETERAN)
}

// ---------------------------------------------------------------------------
// Sistema de Relictos
//
// Los relictos son cartas con efecto permanente y acumulable.
// Se aplican inmediatamente al elegirlas (no van a la mano).
// Para agregar un nuevo relicto:
//   1. Añadir valor al enum Card_Kind arriba
//   2. Añadir campo <nombre>_stacks: i32 en Simulation (app.odin)
//   3. Inicializar el campo a 0 en simulation_init (simulation.odin)
//   4. Aplicar el efecto en start_next_wave (simulation.odin)
//   5. Agregar icono en Icons struct + load_icons (fonts.odin)
//   6. Agregar los tres casos en is_relic / relic_icon / relic_stacks / relic_apply abajo
//   7. Agregar traducción en translations.txt
// ---------------------------------------------------------------------------

// Devuelve true si la carta es un relicto (efecto permanente acumulable).
is_relic :: proc(kind: Card_Kind) -> bool {
	return kind == .INTEREST_BOOST || kind == .DIVIDEND    || kind == .STEAL       ||
	       kind == .WEAKEN         || kind == .AUTO_UPGRADE || kind == .BLOODLUST  ||
	       kind == .FLAWLESS       || kind == .FORMATION   || kind == .FROZEN_AMP  ||
	       kind == .VETERAN    || kind == .LOOT
}

// Devuelve el icono PNG asociado al relicto (Texture2D vacía si no existe).
relic_icon :: proc(kind: Card_Kind) -> raylib.Texture2D {
	#partial switch kind {
	case .INTEREST_BOOST: return constants.game_icons.interest
	case .DIVIDEND:       return constants.game_icons.dividend
	case .STEAL:          return constants.game_icons.steal
	case .WEAKEN:         return constants.game_icons.weaken
	case .AUTO_UPGRADE:   return constants.game_icons.auto
	case .BLOODLUST:      return constants.game_icons.bloodlust
	case .FLAWLESS:       return constants.game_icons.flawless
	case .FORMATION:      return constants.game_icons.formation
	case .FROZEN_AMP:     return constants.game_icons.frozen_amp
	case .VETERAN:    return constants.game_icons.veteran
	case .LOOT:           return constants.game_icons.loot
	}
	return {}
}

// Devuelve el número de stacks acumulados del relicto en la simulación dada.
relic_stacks :: proc(sim: ^Simulation, kind: Card_Kind) -> i32 {
	#partial switch kind {
	case .INTEREST_BOOST: return sim.interest_stacks
	case .DIVIDEND:       return sim.dividend_stacks
	case .STEAL:          return sim.steal_stacks
	case .WEAKEN:         return sim.weaken_stacks
	case .AUTO_UPGRADE:   return sim.auto_stacks
	case .BLOODLUST:      return sim.bloodlust_stacks
	case .FLAWLESS:       return sim.flawless_stacks
	case .FORMATION:      return sim.formation_stacks
	case .FROZEN_AMP:     return sim.frozen_amp_stacks
	case .VETERAN:    return sim.veteran_stacks
	case .LOOT:           return sim.loot_stacks
	}
	return 0
}

// Incrementa en 1 el stack del relicto.
relic_apply :: proc(sim: ^Simulation, kind: Card_Kind) {
	#partial switch kind {
	case .INTEREST_BOOST: sim.interest_stacks  += 1
	case .DIVIDEND:       sim.dividend_stacks  += 1
	case .STEAL:          sim.steal_stacks     += 1
	case .WEAKEN:         sim.weaken_stacks    += 1
	case .AUTO_UPGRADE:   sim.auto_stacks      += 1
	case .BLOODLUST:      sim.bloodlust_stacks += 1
	case .FLAWLESS:       sim.flawless_stacks  += 1
	case .FORMATION:      sim.formation_stacks += 1
	case .FROZEN_AMP:     sim.frozen_amp_stacks  += 1
	case .VETERAN:    sim.veteran_stacks += 1
	case .LOOT:           sim.loot_stacks        += 1
	}
}

// ---------------------------------------------------------------------------
// Operaciones de mazo
// ---------------------------------------------------------------------------

// Mezcla el mazo en el lugar usando Fisher-Yates
deck_shuffle :: proc(deck: ^[dynamic]Card) {
	n := len(deck)
	for i := n - 1; i > 0; i -= 1 {
		j := rand.int_max(i + 1)
		deck[i], deck[j] = deck[j], deck[i]
	}
}

// Roba una carta del tope del mazo a la mano.
// Si el mazo está vacío, rebaraja el descarte primero.
deck_draw_one :: proc(sim: ^Simulation) {
	if len(sim.deck) == 0 {
		for card in sim.discard {
			append(&sim.deck, card)
		}
		clear(&sim.discard)
		deck_shuffle(&sim.deck)
	}
	if len(sim.deck) == 0 {
		return // Sin cartas en ningún lado
	}
	card := pop(&sim.deck)
	append(&sim.hand, card)
}

// Descarta toda la mano y roba hand_size cartas nuevas.
hand_refresh :: proc(sim: ^Simulation) {
	for card in sim.hand {
		append(&sim.discard, card)
	}
	clear(&sim.hand)
	for _ in 0 ..< sim.hand_size {
		deck_draw_one(sim)
	}
}

// Devuelve las cartas de la mano al mazo, rebaraja y reparte de nuevo.
// Usado antes de la primera oleada para cambiar la mano inicial.
hand_redeal :: proc(sim: ^Simulation) {
	for card in sim.hand {
		append(&sim.deck, card)
	}
	clear(&sim.hand)
	deck_shuffle(&sim.deck)
	for _ in 0 ..< sim.hand_size {
		deck_draw_one(sim)
	}
}

// Consume una carta de la mano por índice al colocarla.
// La carta va al descarte para que pueda ser robada de nuevo (STEAL, hand_refresh, etc.).
card_play :: proc(sim: ^Simulation, hand_idx: int) {
	if hand_idx < 0 || hand_idx >= len(sim.hand) {
		return
	}
	card := sim.hand[hand_idx]
	append(&sim.discard, card)
	ordered_remove(&sim.hand, hand_idx)
}

// Vende una carta de la mano: la mueve al descarte y devuelve CARD_SELL_PRICE al jugador.
card_sell :: proc(sim: ^Simulation, hand_idx: int) {
	if hand_idx < 0 || hand_idx >= len(sim.hand) {
		return
	}
	card := sim.hand[hand_idx]
	append(&sim.discard, card)
	ordered_remove(&sim.hand, hand_idx)
}

// Añade una carta directamente a la mano.
card_add_to_hand :: proc(sim: ^Simulation, card: Card) {
	append(&sim.hand, card)
}

// Reparte una mano garantizada de 5 cartas y llena el mazo con el resto.
// Limpia mano y mazo antes de operar (sirve tanto para inicio como para reroll).
// Mano: 3 torres de daño (ARCHER/CANNON/SNIPER/MISSILE),
//       1 de utilidad (ICE o ENHANCE), 1 reliquia aleatoria.
// Mazo: las cartas restantes, mezcladas.
deal_guaranteed_hand :: proc(sim: ^Simulation) {
	clear(&sim.hand)
	clear(&sim.deck)

	// Pools — se eligen con índices aleatorios para evitar bias
	damage_kinds  := []constants.Tower_Type{.ARCHER, .ARCHER, .CANNON, .CANNON, .SNIPER, .MISSILE}
	utility_kinds := []constants.Tower_Type{.ICE, .ENHANCE}
	relic_kinds   := []Card_Kind{.INTEREST_BOOST, .WEAKEN, .BLOODLUST, .FLAWLESS}

	// Copias mutables para poder permutar in-place (Fisher-Yates)
	dmg  := [6]constants.Tower_Type{damage_kinds[0],  damage_kinds[1],  damage_kinds[2],
	                                  damage_kinds[3],  damage_kinds[4],  damage_kinds[5]}
	util := [2]constants.Tower_Type{utility_kinds[0], utility_kinds[1]}
	rel  := [4]Card_Kind{relic_kinds[0], relic_kinds[1], relic_kinds[2], relic_kinds[3]}

	shuffle_tower :: proc(arr: []constants.Tower_Type) {
		for i := len(arr) - 1; i > 0; i -= 1 {
			j := rand.int_max(i + 1)
			arr[i], arr[j] = arr[j], arr[i]
		}
	}
	shuffle_kind :: proc(arr: []Card_Kind) {
		for i := len(arr) - 1; i > 0; i -= 1 {
			j := rand.int_max(i + 1)
			arr[i], arr[j] = arr[j], arr[i]
		}
	}
	shuffle_tower(dmg[:])
	shuffle_tower(util[:])
	shuffle_kind(rel[:])

	// -- Mano garantizada --
	append(&sim.hand, Card{kind = .TOWER, tower_type = dmg[0]})
	append(&sim.hand, Card{kind = .TOWER, tower_type = dmg[1]})
	append(&sim.hand, Card{kind = .TOWER, tower_type = dmg[2]})
	append(&sim.hand, Card{kind = .TOWER, tower_type = util[0]})
	append(&sim.hand, Card{kind = rel[0]})

	// -- Resto al mazo --
	append(&sim.deck, Card{kind = .TOWER, tower_type = dmg[3]})
	append(&sim.deck, Card{kind = .TOWER, tower_type = dmg[4]})
	append(&sim.deck, Card{kind = .TOWER, tower_type = dmg[5]})
	append(&sim.deck, Card{kind = .TOWER, tower_type = util[1]})
	append(&sim.deck, Card{kind = .TOWER, tower_type = .LASER})
	append(&sim.deck, Card{kind = .OBSTACLE})
	append(&sim.deck, Card{kind = .OBSTACLE})
	deck_shuffle(&sim.deck)
}

// Construye el mazo inicial. Delega en deal_guaranteed_hand.
build_starter_deck :: proc(sim: ^Simulation) {
	deal_guaranteed_hand(sim)
}

// Devuelve el nombre traducido de una carta
card_name :: proc(card: Card) -> string {
	switch card.kind {
	case .OBSTACLE:       return constants.get_text("CARD_OBSTACLE_NAME")
	case .INTEREST_BOOST: return constants.get_text("CARD_INTEREST_BOOST_NAME")
	case .WEAKEN:         return constants.get_text("CARD_WEAKEN_NAME")
	case .DIVIDEND:       return constants.get_text("CARD_DIVIDEND_NAME")
	case .STEAL:          return constants.get_text("CARD_STEAL_NAME")
	case .AUTO_UPGRADE:   return constants.get_text("CARD_AUTO_UPGRADE_NAME")
	case .BLOODLUST:      return constants.get_text("CARD_BLOODLUST_NAME")
	case .FLAWLESS:       return constants.get_text("CARD_FLAWLESS_NAME")
	case .FORMATION:      return constants.get_text("CARD_FORMATION_NAME")
	case .FROZEN_AMP:     return constants.get_text("CARD_FROZEN_AMP_NAME")
	case .VETERAN:    return constants.get_text("CARD_VETERAN_NAME")
	case .LOOT:           return constants.get_text("CARD_LOOT_NAME")
	case .TOWER:
		switch card.tower_type {
		case .ARCHER:  return constants.get_text("TOWER_ARCHER_NAME")
		case .CANNON:  return constants.get_text("TOWER_CANNON_NAME")
		case .SNIPER:  return constants.get_text("TOWER_SNIPER_NAME")
		case .MISSILE: return constants.get_text("TOWER_MISSILE_NAME")
		case .LASER:   return constants.get_text("TOWER_LASER_NAME")
		case .ICE:     return constants.get_text("TOWER_ICE_NAME")
		case .ENHANCE: return constants.get_text("TOWER_ENHANCE_NAME")
		}
	}
	return "?"
}

// Alias para compatibilidad con código existente que pasa tower_type
card_tower_name :: proc(tower_type: constants.Tower_Type) -> string {
	return card_name(Card{kind = .TOWER, tower_type = tower_type})
}

// Convierte una carta al Tile correspondiente para selected_build_tower
card_to_tile :: proc(card: Card) -> constants.Tile {
	if card.kind == .OBSTACLE {
		return .OBSTACLE
	}
	// Relictos no se colocan en el mapa
	if is_relic(card.kind) {
		return .EMPTY
	}
	switch card.tower_type {
	case .ARCHER:  return .TOWER_ARCHER
	case .CANNON:  return .TOWER_CANNON
	case .SNIPER:  return .TOWER_SNIPER
	case .MISSILE: return .TOWER_MISSILE
	case .LASER:   return .TOWER_LASER
	case .ICE:     return .TOWER_ICE
	case .ENHANCE: return .TOWER_ENHANCE
	}
	return .EMPTY
}

// Devuelve la rareza de una carta (afecta probabilidad de aparición y precio en tienda).
card_rarity :: proc(card: Card) -> constants.Card_Rarity {
	if card.kind == .TOWER {
		switch card.tower_type {
		case .ARCHER, .CANNON:          return .COMMON
		case .SNIPER, .ICE, .ENHANCE:   return .UNCOMMON
		case .LASER, .MISSILE:          return .RARE
		}
	}
	switch card.kind {
	case .TOWER:                    return .COMMON
	case .OBSTACLE:                 return .COMMON
	case .AUTO_UPGRADE:             return .COMMON
	case .LOOT, .DIVIDEND:          return .UNCOMMON
	case .STEAL, .INTEREST_BOOST:   return .UNCOMMON
	case .FORMATION:                return .RARE
	case .WEAKEN, .FROZEN_AMP:      return .RARE
	case .VETERAN:              return .RARE
	case .BLOODLUST, .FLAWLESS:     return .UNIQUE
	}
	return .COMMON
}

// Devuelve el precio de tienda de una carta según su rareza.
card_shop_price :: proc(card: Card) -> i32 {
	switch card_rarity(card) {
	case .COMMON:   return constants.SHOP_PRICE_COMMON
	case .UNCOMMON: return constants.SHOP_PRICE_UNCOMMON
	case .RARE:     return constants.SHOP_PRICE_RARE
	case .UNIQUE:   return constants.SHOP_PRICE_UNIQUE
	}
	return constants.SHOP_PRICE_COMMON
}

// Alias original (compatibilidad)
card_tower_type_to_tile :: proc(tower_type: constants.Tower_Type) -> constants.Tile {
	return card_to_tile(Card{kind = .TOWER, tower_type = tower_type})
}

// Precio de venta de una carta desde la mano, según rareza.
// Aplica igual a torres, obstáculos y relictos.
card_sell_price :: proc(card: Card) -> i32 {
	switch card_rarity(card) {
	case .COMMON:   return constants.SELL_PRICE_COMMON
	case .UNCOMMON: return constants.SELL_PRICE_UNCOMMON
	case .RARE:     return constants.SELL_PRICE_RARE
	case .UNIQUE:   return constants.SELL_PRICE_UNIQUE
	}
	return constants.CARD_SELL_PRICE
}

// Costo de colocar una carta
card_cost :: proc(card: Card) -> i32 {
	if card.kind == .OBSTACLE {
		return constants.OBSTACLE_BASE_COST
	}
	// Relictos no tienen costo monetario
	if is_relic(card.kind) {
		return 0
	}
	return constants.TOWER_SPECS[card.tower_type].cost
}

package entities

import "../constants"
import "core:math/rand"

// Tipo de carta
Card_Kind :: enum {
	TOWER,    // valor cero → compatible con código existente
	OBSTACLE,
}

// Una carta del mazo
Card :: struct {
	kind:       Card_Kind,
	tower_type: constants.Tower_Type, // solo válido si kind == .TOWER
}

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
// La carta se elimina permanentemente.
card_play :: proc(sim: ^Simulation, hand_idx: int) {
	if hand_idx < 0 || hand_idx >= len(sim.hand) {
		return
	}
	ordered_remove(&sim.hand, hand_idx)
}

// Añade una carta directamente a la mano.
card_add_to_hand :: proc(sim: ^Simulation, card: Card) {
	append(&sim.hand, card)
}

// Construye y mezcla el mazo inicial.
build_starter_deck :: proc(sim: ^Simulation) {
	starter := []Card{
		{kind = .TOWER, tower_type = .ARCHER},
		{kind = .TOWER, tower_type = .ARCHER},
		{kind = .TOWER, tower_type = .ARCHER},
		{kind = .TOWER, tower_type = .CANNON},
		{kind = .TOWER, tower_type = .CANNON},
		{kind = .TOWER, tower_type = .SNIPER},
		{kind = .TOWER, tower_type = .MISSILE},
		{kind = .TOWER, tower_type = .LASER},
		{kind = .TOWER, tower_type = .ICE},
		{kind = .OBSTACLE},
		{kind = .OBSTACLE},
	}
	for c in starter {
		append(&sim.deck, c)
	}
	deck_shuffle(&sim.deck)
}

// Devuelve el nombre traducido de una carta
card_name :: proc(card: Card) -> string {
	if card.kind == .OBSTACLE {
		return constants.get_text("CARD_OBSTACLE_NAME")
	}
	switch card.tower_type {
	case .ARCHER:  return constants.get_text("TOWER_ARCHER_NAME")
	case .CANNON:  return constants.get_text("TOWER_CANNON_NAME")
	case .SNIPER:  return constants.get_text("TOWER_SNIPER_NAME")
	case .MISSILE: return constants.get_text("TOWER_MISSILE_NAME")
	case .LASER:   return constants.get_text("TOWER_LASER_NAME")
	case .ICE:     return constants.get_text("TOWER_ICE_NAME")
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
	switch card.tower_type {
	case .ARCHER:  return .TOWER_ARCHER
	case .CANNON:  return .TOWER_CANNON
	case .SNIPER:  return .TOWER_SNIPER
	case .MISSILE: return .TOWER_MISSILE
	case .LASER:   return .TOWER_LASER
	case .ICE:     return .TOWER_ICE
	}
	return .EMPTY
}

// Alias original (compatibilidad)
card_tower_type_to_tile :: proc(tower_type: constants.Tower_Type) -> constants.Tile {
	return card_to_tile(Card{kind = .TOWER, tower_type = tower_type})
}

// Costo de colocar una carta
card_cost :: proc(card: Card) -> i32 {
	if card.kind == .OBSTACLE {
		return constants.OBSTACLE_BASE_COST
	}
	return constants.TOWER_SPECS[card.tower_type].cost
}

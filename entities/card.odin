package entities

import "../constants"
import "core:fmt"
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
	SCOUT,           // revela el tipo de la próxima oleada al comenzar (informativo)
	RECYCLER,        // bonus de venta al retirar torres colocadas (acumulable)
	MEMENTO,         // oro extra escalando con oleadas completadas (acumulable)
	WARMED_UP,       // torres con objetivo continuo reciben +daño (acumulable)
	CRYPTOBRO,       // la torre que mata al jefe gana +1 nivel permanente (acumulable)
}

// Una carta del mazo
Card :: struct {
	kind:        Card_Kind,
	tower_type:  constants.Tower_Type, // solo válido si kind == .TOWER
	bonus_level: i32,                  // niveles extra pre-aplicados (solo torres del shop con VETERAN)
}

// ---------------------------------------------------------------------------
// Tabla declarativa de relictos — RELIC_SPECS
//
// Para agregar un nuevo relicto:
//   1. Añadir valor al enum Card_Kind arriba
//   2. Añadir entrada en RELIC_SPECS abajo (kind, rarity, keys, icon, procs)
//   3. Aplicar el efecto en start_next_wave / kill / etc. (simulation.odin)
//   4. Agregar traducción en translations.txt
//   5. Agregar imagen en images/icon_<nombre>.png
//
// Todo lo demás (is_relic, relic_icon, relic_stacks, relic_apply,
// card_name, card_rarity, tooltips, toasts, load/unload de iconos) se
// deriva automáticamente de la tabla.
// ---------------------------------------------------------------------------

Relic_Spec :: struct {
	kind:         Card_Kind,
	rarity:       constants.Card_Rarity,
	name_key:     string,
	desc_key:     string,
	icon_path:    cstring,
	stat_format:  proc() -> string,             // línea de stat en tooltip
	toast_format: proc(stacks: i32) -> string,  // mensaje al adquirir
}

RELIC_SPECS := []Relic_Spec{
	{
		kind         = .INTEREST_BOOST,
		rarity       = .UNCOMMON,
		name_key     = "CARD_INTEREST_BOOST_NAME",
		desc_key     = "TOOLTIP_INTEREST_BOOST_DESC",
		icon_path    = "images/icon_interest.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("+%.0f%% por stack/oleada", constants.INTEREST_RATE * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Interés x%d (%.0f%%/oleada)", stacks, f32(stacks) * constants.INTEREST_RATE * 100)
		},
	},
	{
		kind         = .WEAKEN,
		rarity       = .RARE,
		name_key     = "CARD_WEAKEN_NAME",
		desc_key     = "TOOLTIP_WEAKEN_DESC",
		icon_path    = "images/icon_weaken.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("-%.0f%% HP enemigo por stack", constants.WEAKEN_HP_REDUCTION * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Debilitar x%d (-%.0f%% HP enemigos)", stacks, f32(stacks) * constants.WEAKEN_HP_REDUCTION * 100)
		},
	},
	{
		kind         = .DIVIDEND,
		rarity       = .UNCOMMON,
		name_key     = "CARD_DIVIDEND_NAME",
		desc_key     = "TOOLTIP_DIVIDEND_DESC",
		icon_path    = "images/icon_dividend.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("+%.0f%% del oro ahorrado/stack", constants.DIVIDEND_RATE * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Dividendo x%d (%.0f%%/oleada)", stacks, f32(stacks) * constants.DIVIDEND_RATE * 100)
		},
	},
	{
		kind         = .STEAL,
		rarity       = .UNCOMMON,
		name_key     = "CARD_STEAL_NAME",
		desc_key     = "TOOLTIP_STEAL_DESC",
		icon_path    = "images/icon_steal.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("+%d carta(s) por stack/oleada", constants.STEAL_CARDS_PER_STACK)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Ladrón x%d (+%d carta/oleada)", stacks, stacks)
		},
	},
	{
		kind         = .AUTO_UPGRADE,
		rarity       = .COMMON,
		name_key     = "CARD_AUTO_UPGRADE_NAME",
		desc_key     = "TOOLTIP_AUTO_UPGRADE_DESC",
		icon_path    = "images/icon_auto.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("1 mejora cada %.0fs por stack", constants.AUTO_UPGRADE_INTERVAL)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Auto-mejora x%d (cada %.0fs)", stacks, constants.AUTO_UPGRADE_INTERVAL)
		},
	},
	{
		kind         = .BLOODLUST,
		rarity       = .UNIQUE,
		name_key     = "CARD_BLOODLUST_NAME",
		desc_key     = "TOOLTIP_BLOODLUST_DESC",
		icon_path    = "images/icon_bloodlust.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("+%.1f%% daño por kill/stack", constants.BLOODLUST_BONUS_PER_KILL * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Sed de sangre x%d (+%.1f%% daño/kill)", stacks, f32(stacks) * constants.BLOODLUST_BONUS_PER_KILL * 100)
		},
	},
	{
		kind         = .FLAWLESS,
		rarity       = .UNIQUE,
		name_key     = "CARD_FLAWLESS_NAME",
		desc_key     = "TOOLTIP_FLAWLESS_DESC",
		icon_path    = "images/icon_flawless.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("+$%d oro por stack (ola perfecta)", constants.FLAWLESS_BONUS)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Impecable x%d (+$%d/oleada perfecta)", stacks, constants.FLAWLESS_BONUS * stacks)
		},
	},
	{
		kind         = .FORMATION,
		rarity       = .RARE,
		name_key     = "CARD_FORMATION_NAME",
		desc_key     = "TOOLTIP_FORMATION_DESC",
		icon_path    = "images/icon_formation.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("+%.0f%% daño por stack (3+ iguales)", constants.FORMATION_BONUS * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Formación x%d (+%.0f%% daño en línea de 3+)", stacks, f32(stacks) * constants.FORMATION_BONUS * 100)
		},
	},
	{
		kind         = .FROZEN_AMP,
		rarity       = .RARE,
		name_key     = "CARD_FROZEN_AMP_NAME",
		desc_key     = "TOOLTIP_FROZEN_AMP_DESC",
		icon_path    = "images/icon_frozen_amp.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("+%.0f%% daño por stack vs lentos", constants.FROZEN_AMP_BONUS * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Crioamplificador x%d (+%.0f%% daño a ralentizados)", stacks, f32(stacks) * constants.FROZEN_AMP_BONUS * 100)
		},
	},
	{
		kind         = .VETERAN,
		rarity       = .RARE,
		name_key     = "CARD_VETERAN_NAME",
		desc_key     = "TOOLTIP_VETERAN_DESC",
		icon_path    = "images/icon_veteran.png",
		stat_format  = proc() -> string {
			return "+1 nivel inicial por stack"
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Veterano x%d (%.0f%% chance/carta pre-nivelada)", stacks, min(f32(100), f32(stacks) * constants.VETERAN_BOOST_CHANCE * 100))
		},
	},
	{
		kind         = .LOOT,
		rarity       = .UNCOMMON,
		name_key     = "CARD_LOOT_NAME",
		desc_key     = "TOOLTIP_LOOT_DESC",
		icon_path    = "images/icon_loot.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("%.1f%% chance/kill por stack", constants.DECK_CARD_DROP_CHANCE * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Saqueador x%d (%.1f%% chance/kill)", stacks, f32(stacks) * constants.DECK_CARD_DROP_CHANCE * 100)
		},
	},
	{
		kind         = .SCOUT,
		rarity       = .COMMON,
		name_key     = "CARD_SCOUT_NAME",
		desc_key     = "TOOLTIP_SCOUT_DESC",
		icon_path    = "images/icon_scout.png",
		stat_format  = proc() -> string {
			return "Anuncia el tipo de la próxima oleada"
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Explorador x%d (alerta de oleada)", stacks)
		},
	},
	{
		kind         = .RECYCLER,
		rarity       = .COMMON,
		name_key     = "CARD_RECYCLER_NAME",
		desc_key     = "TOOLTIP_RECYCLER_DESC",
		icon_path    = "images/icon_recycler.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("+%.0f%% de venta por stack", constants.RECYCLER_SELL_BONUS * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Reciclador x%d (+%.0f%% venta torres)", stacks, f32(stacks) * constants.RECYCLER_SELL_BONUS * 100)
		},
	},
	{
		kind         = .MEMENTO,
		rarity       = .COMMON,
		name_key     = "CARD_MEMENTO_NAME",
		desc_key     = "TOOLTIP_MEMENTO_DESC",
		icon_path    = "images/icon_memento.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("+$%d/stack/oleada cada 10 olas", constants.MEMENTO_GOLD_PER_10W)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Recuerdo x%d (+$%d cada 10 olas)", stacks, i32(stacks) * constants.MEMENTO_GOLD_PER_10W)
		},
	},
	{
		kind         = .WARMED_UP,
		rarity       = .UNCOMMON,
		name_key     = "CARD_WARMED_UP_NAME",
		desc_key     = "TOOLTIP_WARMED_UP_DESC",
		icon_path    = "images/icon_warmed_up.png",
		stat_format  = proc() -> string {
			return fmt.tprintf("+%.0f%% daño/stack (>%.0fs con objetivo)", constants.WARMED_UP_BONUS * 100, constants.WARMED_UP_THRESHOLD)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("En calor x%d (+%.0f%% daño continuo)", stacks, f32(stacks) * constants.WARMED_UP_BONUS * 100)
		},
	},
	{
		kind         = .CRYPTOBRO,
		rarity       = .UNCOMMON,
		name_key     = "CARD_CRYPTOBRO_NAME",
		desc_key     = "TOOLTIP_CRYPTOBRO_DESC",
		icon_path    = "images/icon_cryptobro.png",
		stat_format  = proc() -> string {
			return "+1 nivel permanente a la torre que mata al jefe"
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf("Cryptobro x%d (+1 nv al matar jefe)", stacks)
		},
	},
}

// Texturas de iconos de relictos, indexadas por Card_Kind.
// Cargadas por load_relic_icons() al inicio.
relic_icon_textures: [Card_Kind]raylib.Texture2D

// Carga, genera mipmaps y filtra los iconos de todos los relictos en RELIC_SPECS.
load_relic_icons :: proc() {
	for &spec in RELIC_SPECS {
		relic_icon_textures[spec.kind] = raylib.LoadTexture(spec.icon_path)
		raylib.GenTextureMipmaps(&relic_icon_textures[spec.kind])
		raylib.SetTextureFilter(relic_icon_textures[spec.kind], .TRILINEAR)
	}
}

// Libera los iconos cargados.
unload_relic_icons :: proc() {
	for spec in RELIC_SPECS {
		raylib.UnloadTexture(relic_icon_textures[spec.kind])
	}
}

// Devuelve el spec del relicto para el kind dado, o false si no es relicto.
relic_spec_for :: proc(kind: Card_Kind) -> (Relic_Spec, bool) {
	for spec in RELIC_SPECS {
		if spec.kind == kind { return spec, true }
	}
	return {}, false
}

// Devuelve true si la carta es un relicto (efecto permanente acumulable).
is_relic :: proc(kind: Card_Kind) -> bool {
	for spec in RELIC_SPECS {
		if spec.kind == kind { return true }
	}
	return false
}

// Devuelve el icono PNG asociado al relicto.
relic_icon :: proc(kind: Card_Kind) -> raylib.Texture2D {
	return relic_icon_textures[kind]
}

// Devuelve el número de stacks acumulados del relicto en la simulación dada.
relic_stacks :: proc(sim: ^Simulation, kind: Card_Kind) -> i32 {
	return sim.relic_stacks[kind]
}

// Incrementa en 1 el stack del relicto.
relic_apply :: proc(sim: ^Simulation, kind: Card_Kind) {
	sim.relic_stacks[kind] += 1
}

// ---------------------------------------------------------------------------
// Operaciones de mazo
// ---------------------------------------------------------------------------

// Generic Fisher-Yates shuffle for any slice type.
slice_shuffle :: proc(arr: []$T) {
	for i := len(arr) - 1; i > 0; i -= 1 {
		j := rand.int_max(i + 1)
		arr[i], arr[j] = arr[j], arr[i]
	}
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
// La carta va al descarte para que pueda ser robada de nuevo (STEAL, hand_refresh, etc.).
card_play :: proc(sim: ^Simulation, hand_idx: int) {
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

	slice_shuffle(dmg[:])
	slice_shuffle(util[:])
	slice_shuffle(rel[:])

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
	if card.kind == .TOWER {
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
	if card.kind == .OBSTACLE {
		return constants.get_text("CARD_OBSTACLE_NAME")
	}
	for spec in RELIC_SPECS {
		if spec.kind == card.kind { return constants.get_text(spec.name_key) }
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
	if card.kind == .OBSTACLE { return .COMMON }
	for spec in RELIC_SPECS {
		if spec.kind == card.kind { return spec.rarity }
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

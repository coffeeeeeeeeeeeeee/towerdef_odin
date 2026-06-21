package entities

import "../constants"
import "core:fmt"
import "core:math"
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
	LUMBERJACK,      // al comprar: otorga 1 carga para talar un árbol del mapa y obtener oro
	SHOPPING_CART,   // +1 slot de reliquia por stack (aumenta el límite de tipos distintos)
	REBOUND,         // proyectiles rebotan a enemigo cercano (+1 rebote por cada 2 stacks)
	OVERDRIVE,       // se aplica a una torre: +10% velocidad de ataque por stack (acumulable en torre)
	GARDENER,        // activa: mueve una torre de lugar conservando todos sus stats
	AIRDROP,         // pasiva: airdrops más frecuentes y cartas de mayor rareza por stack
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
//   5. Agregar imagen en images/relics/<nombre>.png
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
		icon_path    = "images/relics/interest.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_INTEREST_BOOST"), constants.INTEREST_RATE * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_INTEREST_BOOST"), stacks, f32(stacks) * constants.INTEREST_RATE * 100)
		},
	},
	{
		kind         = .WEAKEN,
		rarity       = .RARE,
		name_key     = "CARD_WEAKEN_NAME",
		desc_key     = "TOOLTIP_WEAKEN_DESC",
		icon_path    = "images/relics/weaken.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_WEAKEN"), constants.WEAKEN_HP_REDUCTION * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_WEAKEN"), stacks, f32(stacks) * constants.WEAKEN_HP_REDUCTION * 100)
		},
	},
	{
		kind         = .DIVIDEND,
		rarity       = .UNCOMMON,
		name_key     = "CARD_DIVIDEND_NAME",
		desc_key     = "TOOLTIP_DIVIDEND_DESC",
		icon_path    = "images/relics/dividend.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_DIVIDEND"), constants.DIVIDEND_RATE * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_DIVIDEND"), stacks, f32(stacks) * constants.DIVIDEND_RATE * 100)
		},
	},
	{
		kind         = .STEAL,
		rarity       = .UNCOMMON,
		name_key     = "CARD_STEAL_NAME",
		desc_key     = "TOOLTIP_STEAL_DESC",
		icon_path    = "images/relics/steal.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_STEAL"), constants.STEAL_CARDS_PER_STACK)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_STEAL"), stacks, stacks)
		},
	},
	{
		kind         = .AUTO_UPGRADE,
		rarity       = .COMMON,
		name_key     = "CARD_AUTO_UPGRADE_NAME",
		desc_key     = "TOOLTIP_AUTO_UPGRADE_DESC",
		icon_path    = "images/relics/auto.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_AUTO_UPGRADE"), constants.AUTO_UPGRADE_INTERVAL)
		},
		toast_format = proc(stacks: i32) -> string {
			interval := constants.AUTO_UPGRADE_INTERVAL / math.pow(f32(2), f32(stacks - 1))
			return fmt.tprintf(constants.get_text("TOAST_AUTO_UPGRADE"), stacks, interval)
		},
	},
	{
		kind         = .BLOODLUST,
		rarity       = .UNIQUE,
		name_key     = "CARD_BLOODLUST_NAME",
		desc_key     = "TOOLTIP_BLOODLUST_DESC",
		icon_path    = "images/relics/bloodlust.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_BLOODLUST"), constants.BLOODLUST_BONUS_PER_KILL * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_BLOODLUST"), stacks, f32(stacks) * constants.BLOODLUST_BONUS_PER_KILL * 100)
		},
	},
	{
		kind         = .FLAWLESS,
		rarity       = .UNIQUE,
		name_key     = "CARD_FLAWLESS_NAME",
		desc_key     = "TOOLTIP_FLAWLESS_DESC",
		icon_path    = "images/relics/flawless.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_FLAWLESS"), constants.FLAWLESS_BONUS)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_FLAWLESS"), stacks, constants.FLAWLESS_BONUS * stacks)
		},
	},
	{
		kind         = .FORMATION,
		rarity       = .RARE,
		name_key     = "CARD_FORMATION_NAME",
		desc_key     = "TOOLTIP_FORMATION_DESC",
		icon_path    = "images/relics/formation.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_FORMATION"), constants.FORMATION_BONUS * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_FORMATION"), stacks, f32(stacks) * constants.FORMATION_BONUS * 100)
		},
	},
	{
		kind         = .FROZEN_AMP,
		rarity       = .RARE,
		name_key     = "CARD_FROZEN_AMP_NAME",
		desc_key     = "TOOLTIP_FROZEN_AMP_DESC",
		icon_path    = "images/relics/frozen_amp.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_FROZEN_AMP"), constants.FROZEN_AMP_BONUS * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_FROZEN_AMP"), stacks, f32(stacks) * constants.FROZEN_AMP_BONUS * 100)
		},
	},
	{
		kind         = .VETERAN,
		rarity       = .RARE,
		name_key     = "CARD_VETERAN_NAME",
		desc_key     = "TOOLTIP_VETERAN_DESC",
		icon_path    = "images/relics/veteran.png",
		stat_format  = proc() -> string {
			return constants.get_text("STAT_VETERAN")
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_VETERAN"), stacks, min(f32(100), f32(stacks) * constants.VETERAN_BOOST_CHANCE * 100))
		},
	},
	{
		kind         = .LOOT,
		rarity       = .UNCOMMON,
		name_key     = "CARD_LOOT_NAME",
		desc_key     = "TOOLTIP_LOOT_DESC",
		icon_path    = "images/relics/loot.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_LOOT"), constants.DECK_CARD_DROP_CHANCE * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_LOOT"), stacks, f32(stacks) * constants.DECK_CARD_DROP_CHANCE * 100)
		},
	},
	{
		kind         = .SCOUT,
		rarity       = .COMMON,
		name_key     = "CARD_SCOUT_NAME",
		desc_key     = "TOOLTIP_SCOUT_DESC",
		icon_path    = "images/relics/scout.png",
		stat_format  = proc() -> string {
			return constants.get_text("STAT_SCOUT")
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_SCOUT"), stacks)
		},
	},
	{
		kind         = .RECYCLER,
		rarity       = .COMMON,
		name_key     = "CARD_RECYCLER_NAME",
		desc_key     = "TOOLTIP_RECYCLER_DESC",
		icon_path    = "images/relics/recycler.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_RECYCLER"), constants.RECYCLER_SELL_BONUS * 100)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_RECYCLER"), stacks, f32(stacks) * constants.RECYCLER_SELL_BONUS * 100)
		},
	},
	{
		kind         = .MEMENTO,
		rarity       = .COMMON,
		name_key     = "CARD_MEMENTO_NAME",
		desc_key     = "TOOLTIP_MEMENTO_DESC",
		icon_path    = "images/relics/memento.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_MEMENTO"), constants.MEMENTO_GOLD_PER_10W)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_MEMENTO"), stacks, i32(stacks) * constants.MEMENTO_GOLD_PER_10W)
		},
	},
	{
		kind         = .WARMED_UP,
		rarity       = .UNCOMMON,
		name_key     = "CARD_WARMED_UP_NAME",
		desc_key     = "TOOLTIP_WARMED_UP_DESC",
		icon_path    = "images/relics/warmed_up.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_WARMED_UP"), constants.WARMED_UP_BONUS * 100, constants.WARMED_UP_THRESHOLD)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_WARMED_UP"), stacks, f32(stacks) * constants.WARMED_UP_BONUS * 100)
		},
	},
	{
		kind         = .CRYPTOBRO,
		rarity       = .UNCOMMON,
		name_key     = "CARD_CRYPTOBRO_NAME",
		desc_key     = "TOOLTIP_CRYPTOBRO_DESC",
		icon_path    = "images/relics/cryptobro.png",
		stat_format  = proc() -> string {
			return constants.get_text("STAT_CRYPTOBRO")
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_CRYPTOBRO"), stacks, stacks)
		},
	},
	{
		kind         = .LUMBERJACK,
		rarity       = .COMMON,
		name_key     = "CARD_LUMBERJACK_NAME",
		desc_key     = "TOOLTIP_LUMBERJACK_DESC",
		icon_path    = "images/relics/lumberjack.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_LUMBERJACK"), constants.LUMBERJACK_TREE_GOLD)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_LUMBERJACK"), stacks)
		},
	},
	{
		kind         = .SHOPPING_CART,
		rarity       = .EPIC,
		name_key     = "CARD_SHOPPING_CART_NAME",
		desc_key     = "TOOLTIP_SHOPPING_CART_DESC",
		icon_path    = "images/relics/shopping_cart.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_SHOPPING_CART"), constants.MAX_ACTIVE_RELICS)
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_SHOPPING_CART"), stacks, constants.MAX_ACTIVE_RELICS + int(stacks))
		},
	},
	{
		kind         = .REBOUND,
		rarity       = .RARE,
		name_key     = "CARD_REBOUND_NAME",
		desc_key     = "TOOLTIP_REBOUND_DESC",
		icon_path    = "images/relics/rebound.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_REBOUND"), constants.REBOUND_STACKS_PER_BOUNCE, constants.REBOUND_RANGE)
		},
		toast_format = proc(stacks: i32) -> string {
			bounces := stacks / constants.REBOUND_STACKS_PER_BOUNCE
			return fmt.tprintf(constants.get_text("TOAST_REBOUND"), stacks, bounces)
		},
	},
	{
		kind         = .OVERDRIVE,
		rarity       = .UNCOMMON,
		name_key     = "CARD_OVERDRIVE_NAME",
		desc_key     = "TOOLTIP_OVERDRIVE_DESC",
		icon_path    = "images/relics/overdrive.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_OVERDRIVE"), i32(constants.OVERDRIVE_SPEED_PER_STACK * 100))
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_OVERDRIVE"), i32(constants.OVERDRIVE_SPEED_PER_STACK * 100))
		},
	},
	{
		kind         = .GARDENER,
		rarity       = .COMMON,
		name_key     = "CARD_GARDENER_NAME",
		desc_key     = "TOOLTIP_GARDENER_DESC",
		icon_path    = "images/relics/gardener.png",
		stat_format  = proc() -> string { return "" },
		toast_format = proc(stacks: i32) -> string {
			return constants.get_text("TOAST_GARDENER")
		},
	},
	{
		kind         = .AIRDROP,
		rarity       = .COMMON,
		name_key     = "CARD_AIRDROP_NAME",
		desc_key     = "TOOLTIP_AIRDROP_DESC",
		icon_path    = "images/relics/airdrop.png",
		stat_format  = proc() -> string {
			return fmt.tprintf(constants.get_text("STAT_AIRDROP"), i32(constants.AIRDROP_RELIC_SPEED_PER_STACK * 100))
		},
		toast_format = proc(stacks: i32) -> string {
			return fmt.tprintf(constants.get_text("TOAST_AIRDROP"), i32(constants.AIRDROP_RELIC_SPEED_PER_STACK * 100 * f32(stacks)))
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

// Incrementa en 1 el stack del relicto, respetando el máximo.
relic_apply :: proc(sim: ^Simulation, kind: Card_Kind) {
	if sim.relic_stacks[kind] < constants.MAX_RELIC_STACKS {
		sim.relic_stacks[kind] += 1
	}
}

// Devuelve true si el relicto ya alcanzó el máximo de stacks.
relic_is_maxed :: proc(sim: ^Simulation, kind: Card_Kind) -> bool {
	return sim.relic_stacks[kind] >= constants.MAX_RELIC_STACKS
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
	if len(sim.cards.deck) == 0 {
		for card in sim.cards.discard {
			append(&sim.cards.deck, card)
		}
		clear(&sim.cards.discard)
		deck_shuffle(&sim.cards.deck)
	}
	if len(sim.cards.deck) == 0 {
		return // Sin cartas en ningún lado
	}
	card := pop(&sim.cards.deck)
	append(&sim.cards.hand, card)
}

// Descarta toda la mano y roba hand_size cartas nuevas.
hand_refresh :: proc(sim: ^Simulation) {
	for card in sim.cards.hand {
		append(&sim.cards.discard, card)
	}
	clear(&sim.cards.hand)
	for _ in 0 ..< sim.cards.hand_size {
		deck_draw_one(sim)
	}
}

// Devuelve las cartas de la mano al mazo, rebaraja y reparte de nuevo.
// Usado antes de la primera oleada para cambiar la mano inicial.
hand_redeal :: proc(sim: ^Simulation) {
	for card in sim.cards.hand {
		append(&sim.cards.deck, card)
	}
	clear(&sim.cards.hand)
	deck_shuffle(&sim.cards.deck)
	for _ in 0 ..< sim.cards.hand_size {
		deck_draw_one(sim)
	}
}

// Consume una carta de la mano por índice al colocarla.
// La carta va al descarte para que pueda ser robada de nuevo (STEAL, hand_refresh, etc.).
card_play :: proc(sim: ^Simulation, hand_idx: int) {
	if hand_idx < 0 || hand_idx >= len(sim.cards.hand) {
		return
	}
	card := sim.cards.hand[hand_idx]
	append(&sim.cards.discard, card)
	ordered_remove(&sim.cards.hand, hand_idx)
}

// Añade una carta directamente a la mano.
card_add_to_hand :: proc(sim: ^Simulation, card: Card) {
	append(&sim.cards.hand, card)
}

// Reparte una mano garantizada de 5 cartas y llena el mazo con el resto.
// Limpia mano y mazo antes de operar (sirve tanto para inicio como para reroll).
// Mano: 3 torres de daño (ARCHER/CANNON/SNIPER/MISSILE),
//       1 de utilidad (ICE o ENHANCE), 1 reliquia aleatoria.
// Mazo: las cartas restantes, mezcladas.
deal_guaranteed_hand :: proc(sim: ^Simulation, meta: ^Meta_State) {
	clear(&sim.cards.hand)
	clear(&sim.cards.deck)

	// Base damage pool — always unlocked towers only
	dmg_base := [4]constants.Tower_Type{.ARCHER, .ARCHER, .CANNON, .SNIPER}
	// Premium damage candidates — only added if unlocked
	dmg_premium := [2]constants.Tower_Type{.MISSILE, .TESLA}

	dmg := make([dynamic]constants.Tower_Type, context.temp_allocator)
	for t in dmg_base { append(&dmg, t) }
	for t in dmg_premium {
		if meta_is_tower_unlocked(meta, t) { append(&dmg, t) }
	}
	slice_shuffle(dmg[:])

	// Utility pool — only include ICE/ENHANCE if unlocked
	util_candidates := [2]constants.Tower_Type{.ICE, .ENHANCE}
	util := make([dynamic]constants.Tower_Type, context.temp_allocator)
	for t in util_candidates {
		if meta_is_tower_unlocked(meta, t) { append(&util, t) }
	}
	slice_shuffle(util[:])

	// Relic pool — only include relics that are unlocked and not maxed
	rel_candidates := [4]Card_Kind{.INTEREST_BOOST, .WEAKEN, .BLOODLUST, .FLAWLESS}
	rel := make([dynamic]Card_Kind, context.temp_allocator)
	for k in rel_candidates {
		if meta_is_relic_unlocked(meta, k) && !relic_is_maxed(sim, k) { append(&rel, k) }
	}
	slice_shuffle(rel[:])

	// -- Mano garantizada: 3 daño + (1 utilidad si disponible) + (1 reliquia si disponible) --
	append(&sim.cards.hand, Card{kind = .TOWER, tower_type = dmg[0]})
	append(&sim.cards.hand, Card{kind = .TOWER, tower_type = dmg[1]})
	append(&sim.cards.hand, Card{kind = .TOWER, tower_type = dmg[2]})
	if len(util) > 0 {
		append(&sim.cards.hand, Card{kind = .TOWER, tower_type = util[0]})
	} else {
		// No utility towers unlocked — add an extra damage tower instead
		extra_idx := 0
		if len(dmg) > 3 { extra_idx = 3 }
		append(&sim.cards.hand, Card{kind = .TOWER, tower_type = dmg[extra_idx]})
	}
	if len(rel) > 0 {
		append(&sim.cards.hand, Card{kind = rel[0]})
	} else {
		// No relics unlocked — add an extra damage tower instead
		extra_idx := 0
		if len(dmg) > 3 { extra_idx = 3 }
		append(&sim.cards.hand, Card{kind = .TOWER, tower_type = dmg[extra_idx]})
	}

	// -- Resto al mazo --
	for i in 3 ..< len(dmg) {
		append(&sim.cards.deck, Card{kind = .TOWER, tower_type = dmg[i]})
	}
	if len(util) > 1 {
		append(&sim.cards.deck, Card{kind = .TOWER, tower_type = util[1]})
	}
	// Add a premium deck card only if at least one is unlocked
	if meta_is_tower_unlocked(meta, .LASER) {
		append(&sim.cards.deck, Card{kind = .TOWER, tower_type = .LASER})
	} else if meta_is_tower_unlocked(meta, .MORTAR) {
		append(&sim.cards.deck, Card{kind = .TOWER, tower_type = .MORTAR})
	}
	append(&sim.cards.deck, Card{kind = .OBSTACLE})
	append(&sim.cards.deck, Card{kind = .OBSTACLE})
	deck_shuffle(&sim.cards.deck)
}

// Construye el mazo inicial. Delega en deal_guaranteed_hand.
build_starter_deck :: proc(sim: ^Simulation, meta: ^Meta_State) {
	deal_guaranteed_hand(sim, meta)
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
		case .TESLA:   return constants.get_text("TOWER_TESLA_NAME")
		case .MORTAR:  return constants.get_text("TOWER_MORTAR_NAME")
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
	case .TESLA:   return .TOWER_TESLA
	case .MORTAR:  return .TOWER_MORTAR
	}
	return .EMPTY
}

// Devuelve la rareza de una carta (afecta probabilidad de aparición y precio en tienda).
card_rarity :: proc(card: Card) -> constants.Card_Rarity {
	if card.kind == .TOWER {
		switch card.tower_type {
		case .ARCHER, .CANNON:                  return .COMMON
		case .SNIPER, .ICE, .ENHANCE:           return .UNCOMMON
		case .LASER, .MISSILE: return .RARE
		case .TESLA, .MORTAR:  return .EPIC
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
	case .EPIC:     return constants.SHOP_PRICE_EPIC
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
	case .EPIC:     return constants.SELL_PRICE_EPIC
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

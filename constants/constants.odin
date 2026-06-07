package constants

// ─────────────────────────────────────────────────────────────────────────────
// Developer mode — set to false before shipping.
// When false, the compiler eliminates all `if DEVELOPER { }` blocks entirely.
// ─────────────────────────────────────────────────────────────────────────────
DEVELOPER :: true

import "vendor:raylib"

// =============================================================================
// Enums
// =============================================================================

Game_State :: enum {
	MENU,
	PLAYING,
	PAUSED,
	EDITOR,
	GAME_OVER,
	SETTINGS,
	RUN_COMPLETE,
	PROGRESSION,
}

// Rareza de carta — afecta probabilidad de aparición en tienda y precio
Card_Rarity :: enum {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	UNIQUE,
}

// Tile types
Tile :: enum i32 {
	EMPTY           = 0,
	PATH            = 1,
	SPAWN           = 2,
	GOAL            = 3,
	TOWER_ARCHER    = 4,
	TOWER_CANNON    = 5,
	TOWER_SNIPER    = 6,
	TOWER_MISSILE   = 7,
	TOWER_LASER     = 8,
	OBSTACLE        = 9,
	ACCESSORY_TREE  = 10,
	ACCESSORY_BLOCK  = 11,
	TOWER_ICE        = 12,
	TOWER_ENHANCE    = 13,
	TOWER_TESLA      = 14,
	TOWER_MORTAR     = 15,
	WATER            = 16, // Herramienta de editor; la capa real se guarda en Map.water_grid
}

Tower_Type :: enum {
	ARCHER,
	CANNON,
	SNIPER,
	MISSILE,
	LASER,
	ICE,
	ENHANCE,
	TESLA,
	MORTAR,
}

Target_Strategy :: enum {
	FIRST,
	LAST,
	MAX_HP,
	MIN_HP,
}

Biome :: enum {
	PLAIN,
	FOREST,
	DESERT,
	MOUNTAIN,
}

// =============================================================================
// Structs
// =============================================================================

Tower_Spec :: struct {
	type:        Tower_Type,
	range:       f32,
	damage:      f32,
	cooldown:    f32,
	aoe:         f32,
	cost:        i32,
	color:       raylib.Color,
	min_cooldown: f32,  // Floor for cooldown after upgrades (0 = no floor)
}

Tile_Data :: struct {
	level: i32,
}

Biome_Colors :: struct {
	bg:      raylib.Color,
	bg_grid: raylib.Color,
	path:    raylib.Color,
}

Biome_Tree_Colors :: struct {
	layer_dark:  raylib.Color,
	layer_mid:   raylib.Color,
	layer_light: raylib.Color,
	layer_tip:   raylib.Color,
	trunk:       raylib.Color,
}

// =============================================================================
// Game / Map settings
// =============================================================================

GRID_SIZE    :: 20
CELL_SIZE    :: 32
MAX_FPS      :: 60
DEFAULT_MONEY  :: 80
DEFAULT_HEALTH :: 10

PATH_WIDTH_RATIO :: 0.4  // Path draw width as a fraction of cell size

// =============================================================================
// Tower specs
// =============================================================================

TOWER_SPECS := [Tower_Type]Tower_Spec {
	.ARCHER = {
		type     = .ARCHER,
		range    = 2.5,
		damage   = 1.5,
		cooldown = 0.5,
		aoe      = 0,
		cost     = 20,
		color    = raylib.BROWN,
	},
	.CANNON = {
		type     = .CANNON,
		range    = 4.0,
		damage   = 8.0,
		cooldown = 0.9,
		aoe      = 0.6,
		cost     = 40,
		color    = raylib.DARKGRAY,
	},
	.SNIPER = {
		type     = .SNIPER,
		range    = 6.0,
		damage   = 18.0,
		cooldown = 2.0,
		aoe      = 0,
		cost     = 60,
		color    = raylib.GREEN,
	},
	.MISSILE = {
		type     = .MISSILE,
		range    = 3.0,
		damage   = 3.0,
		cooldown = 0.6,
		aoe      = 1.0,
		cost     = 35,
		color    = raylib.RED,
	},
	.LASER = {
		type     = .LASER,
		range    = 2.5,
		damage   = 8.0,
		cooldown = 0.7,
		aoe      = 0,
		cost     = 80,
		color    = raylib.MAGENTA,
	},
	.ICE = {
		type         = .ICE,
		range        = 2.5,
		damage       = 0.5,
		cooldown     = 3.0,
		aoe          = 0,
		cost         = 45,
		color        = raylib.SKYBLUE,
		min_cooldown = 0.5,
	},
	.ENHANCE = {
		type     = .ENHANCE,
		range    = 3.0,
		damage   = 0,
		cooldown = 10.0,  // seconds between boost pulses
		aoe      = 0,
		cost     = 90,
		color    = raylib.GOLD,
	},
	.TESLA = {
		type     = .TESLA,
		range    = 3.0,
		damage   = 6.0,
		cooldown = 1.5,
		aoe      = 0,
		cost     = 55,
		color    = raylib.Color{120, 70, 220, 255},
	},
	.MORTAR = {
		type         = .MORTAR,
		range        = 5.0,
		damage       = 14.0,
		cooldown     = 3.0,
		aoe          = 1.5,
		cost         = 65,
		color        = raylib.Color{70, 100, 55, 255},
		min_cooldown = 1.0,
	},
}

// =============================================================================
// Tower balance
// =============================================================================

// Escalado lineal por nivel: stat = base × (1 + FACTOR × (level-1))
// A nivel 20: daño ×3.85, velocidad ×2.52, críticos +9.5%
TOWER_DAMAGE_PER_LEVEL :: f32(0.15)   // +15% del daño base por nivel
TOWER_SPEED_PER_LEVEL  :: f32(0.08)   // +8% de la velocidad base por nivel
TOWER_CRIT_PER_LEVEL   :: f32(0.005)  // +0.5% de probabilidad de crítico por nivel
TOWER_SELL_REFUND        :: f32(0.75)  // Fraction of total investment returned when selling a tower
TOWER_MAX_MANUAL_LEVEL   :: i32(20)   // Max level reachable via manual upgrades alone
TOWER_MAX_LEVEL          :: i32(25)   // Absolute hard cap (manual + enhance combined)

ENHANCE_MAX_LEVEL :: i32(5)  // Maximum levels a tower can receive via ENHANCE boosts

WEAKEN_HP_REDUCTION      :: f32(0.10)   // HP reduction per WEAKEN stack (e.g. 2 stacks = -20% HP)
DIVIDEND_RATE            :: f32(0.15)   // Fraction of wave spending returned per DIVIDEND stack
AUTO_UPGRADE_INTERVAL    :: f32(2.0)    // Seconds between auto-upgrade ticks
BLOODLUST_BONUS_PER_KILL :: f32(0.001)  // Damage multiplier gained per kill per BLOODLUST stack (+0.1%)
FLAWLESS_BONUS           :: i32(75)     // Gold reward per FLAWLESS stack for a perfect wave (no lives lost)
FORMATION_BONUS          :: f32(0.25)   // Damage multiplier bonus per FORMATION stack for towers in a line of 3+
FROZEN_AMP_BONUS         :: f32(0.30)   // Extra damage multiplier per FROZEN_AMP stack on slowed enemies
STEAL_CARDS_PER_STACK    :: i32(1)      // Cards stolen per STEAL stack at end of each wave
VETERAN_BOOST_CHANCE     :: f32(0.35)   // Chance per stack that a tower card in the shop appears pre-leveled (1 stack=35%, 2=70%, 3=100%)
RELIC_FLASH_DURATION     :: f32(0.4)    // Seconds a relic icon flashes white when its effect triggers
MAX_RELIC_STACKS         :: i32(20)     // Maximum stack count for any relic

RECYCLER_SELL_BONUS  :: f32(0.10)  // Extra fraction of sell price per RECYCLER stack
MEMENTO_GOLD_PER_10W :: i32(1)     // Gold per stack per 10 completed waves
WARMED_UP_THRESHOLD  :: f32(15.0)  // Seconds of continuous targeting before warm bonus kicks in
WARMED_UP_BONUS      :: f32(0.03)  // Extra damage multiplier per WARMED_UP stack when active

CARD_REROLL_COST     :: i32(50)    // Gold cost to reroll the 3-card selection
CARD_SELL_PRICE      :: i32(25)    // Gold received when selling a non-relic card from hand
SELL_PRICE_COMMON    :: i32(20)    // Sell price for Common cards
SELL_PRICE_UNCOMMON  :: i32(30)    // Sell price for Uncommon cards
SELL_PRICE_RARE      :: i32(45)    // Sell price for Rare cards
SELL_PRICE_EPIC      :: i32(55)    // Sell price for Epic cards
SELL_PRICE_UNIQUE    :: i32(65)    // Sell price for Unique cards
HAND_REDEAL_COST     :: i32(40)    // Gold cost to redeal the hand once the game has started (free before first wave)

CRIT_BASE_CHANCE     :: f32(0.10)  // Base critical hit chance (10%) for all towers
CRIT_DAMAGE_MULTIPLIER :: f32(2.0) // Damage multiplier on a critical hit

// =============================================================================
// Laser tower
// =============================================================================

LASER_FIRING_DURATION :: f32(1.0)   // Seconds the laser beam stays active per firing cycle
LASER_ACCUMULATION_TIME :: f32(0.1) // Interval at which accumulated laser damage is displayed

// =============================================================================
// Ice tower / slow effect
// =============================================================================

ICE_SLOW_FACTOR   :: f32(0.4)  // Speed multiplier while slowed (40% of normal speed)
ICE_SLOW_DURATION :: f32(2.0)  // Seconds the slow effect lasts after a pulse

// =============================================================================
// Projectiles
// =============================================================================

PROJECTILE_SPEED_DEFAULT :: f32(12.0)  // Travel speed for Archer, Cannon, Sniper, Laser projectiles
PROJECTILE_SPEED_MISSILE :: f32(5.0)   // Slower travel speed for Missile projectiles
PROJECTILE_SPEED_MORTAR  :: f32(2.5)   // Very slow mortar shell

// TESLA chain lightning
TESLA_CHAIN_COUNT   :: 3        // Total enemies hit (primary + bounces)
TESLA_CHAIN_RANGE   :: f32(1.8) // Max grid-cell distance between chain targets
TESLA_CHAIN_FALLOFF :: f32(0.6) // Damage multiplier per bounce step
TESLA_ARC_DURATION  :: f32(0.18) // Seconds chain arcs remain visible

AOE_DAMAGE_MULTIPLIER :: f32(0.5)  // Splash damage is this fraction of the direct-hit damage

// =============================================================================
// Enemy base stats
// =============================================================================

ENEMY_BASE_HP             :: f32(10.0)
ENEMY_GROWTH_RATE         :: f32(1.07)    // HP multiplier per wave (exponential scaling)
ENEMY_SPEED_GROWTH_RATE   :: f32(1.012)   // Speed multiplier per wave (~+1.2% per wave)
ENEMY_GLOBAL_HP_MULTIPLIER    :: f32(0.85) // Global scalar applied to all enemy HP
ENEMY_GLOBAL_SPEED_MULTIPLIER :: f32(0.32) // Global scalar applied to all enemy speeds

// Enemy speed (cells per second, further scaled by ENEMY_GLOBAL_SPEED_MULTIPLIER)
ENEMY_SPEED_DEFAULT :: f32(1.0)  // Normal enemies
ENEMY_SPEED_BOSS    :: f32(0.4)  // Boss enemies (slow)
ENEMY_SPEED_GREEN   :: f32(1.8)  // Green (fast) enemies
ENEMY_SPEED_BLUE    :: f32(1.1)  // Blue (healer) enemies
ENEMY_SPEED_FLYING  :: f32(1.3)  // Flying enemies
ENEMY_SPEED_BONUS   :: f32(1.5)  // Bonus enemies (fast, but below green)

// Enemy size (radius as a fraction of cell size)
ENEMY_SIZE_DEFAULT :: f32(0.24)
ENEMY_SIZE_BOSS    :: f32(0.32)  // Large
ENEMY_SIZE_GREEN   :: f32(0.16)  // Tiny
ENEMY_SIZE_BLUE    :: f32(0.24)  // Same as default
ENEMY_SIZE_FLYING  :: f32(0.20)  // Small
ENEMY_SIZE_BONUS   :: f32(0.28)  // Slightly bigger than default

// Enemy HP multiplier relative to ENEMY_BASE_HP (scaled by wave growth)
ENEMY_HEALTH_DEFAULT :: f32(0.9)
ENEMY_HEALTH_BOSS    :: f32(10.0) // Very tanky
ENEMY_HEALTH_GREEN   :: f32(0.5)  // Fragile
ENEMY_HEALTH_BLUE    :: f32(1.2)  // Slightly tougher
ENEMY_HEALTH_FLYING  :: f32(0.6)  // Fragile
ENEMY_HEALTH_BONUS   :: f32(1.4)  // Tough (carries all sub-type abilities)

// =============================================================================
// Enemy behavior
// =============================================================================

// Blue enemy self-heal
ENEMY_HEAL_RATE_BLUE     :: f32(0.05)  // Fraction of max_hp restored per heal tick
ENEMY_HEAL_COOLDOWN_BLUE :: f32(1.0)   // Seconds between heal ticks

// Splitter enemy children
SPLIT_HP_RATIO   :: f32(0.30)  // Child HP = 30% of parent max_hp
SPLIT_SPEED_MULT :: f32(1.30)  // Child speed = parent speed × 1.30

// Obstacle damage
OBSTACLE_DAMAGE_PER_LEVEL :: f32(5.0)  // Base damage; actual = OBSTACLE_DAMAGE_PER_LEVEL × 2^(level-1)

// =============================================================================
// Enemy rewards and goal damage
// =============================================================================

ENEMY_REWARD_DEFAULT :: i32(3)   // Gold for killing a normal enemy
ENEMY_REWARD_BOSS    :: i32(35)  // Gold for killing a boss
ENEMY_REWARD_GREEN   :: i32(2)   // Gold for killing a green (fast) enemy
ENEMY_REWARD_BONUS   :: i32(15)  // Bonus gold added when killing a bonus enemy

ENEMY_GOAL_DAMAGE_DEFAULT :: i32(1)  // Lives lost when a normal enemy reaches the goal
ENEMY_GOAL_DAMAGE_BOSS    :: i32(5)  // Lives lost when a boss reaches the goal

// =============================================================================
// Wave system
// =============================================================================

// Normal wave enemy count: WAVE_ENEMIES_BASE + wave_number × WAVE_ENEMIES_SCALE
WAVE_ENEMIES_BASE  :: i32(5)
WAVE_ENEMIES_SCALE :: i32(2)

BOSS_WAVE_INTERVAL :: i32(10)  // A boss wave occurs every N waves (wave 10, 20, 30…)
MAX_WAVE           :: i32(100) // Legacy constant (kept for reference)
RUN_MAX_WAVES      :: i32(30)  // Waves per meta-progression run
INTER_WAVE_DELAY   :: f32(2.0) // Seconds between wave end and next wave auto-start

// Bonus waves
BONUS_WAVE_CHANCE      :: f32(0.25)  // Probability of a bonus wave on any non-boss wave
BONUS_WAVE_ENEMY_COUNT :: i32(5)     // Number of enemies spawned on a bonus wave
BONUS_WAVE_MIN_WAVE    :: i32(10)    // Earliest wave at which a bonus wave can occur

// Mixed waves (two sub-types simultaneously)
MIXED_WAVE_MIN_WAVE :: i32(20)  // Mixed waves begin at this wave number

// =============================================================================
// Deck builder
// =============================================================================

DECK_HAND_SIZE          :: i32(3)     // Cards dealt to hand at the start of each wave
DECK_CARD_DROP_CHANCE   :: f32(0.004) // Probability of a card drop on each enemy kill
DECK_SELECTION_INTERVAL :: i32(1)     // Every N waves the shop opens (1 = every wave)
SHOP_RELIC_PRICE        :: i32(75)    // Fallback price (kept for compatibility)

// ─────────────────────────────────────────────────────────────────────────────
// Shop — mecánicas extendidas (lock, reroll progresivo, pity, skip, biome)
// ─────────────────────────────────────────────────────────────────────────────

SHOP_BASE_SLOTS    :: 3  // Slots base del shop antes del modificador de bioma
MAX_SHOP_SLOTS     :: 5  // Tope físico de slots (limita arrays en Simulation)

// Costo de reroll dentro de una misma visita. Index = rerolls_this_shop.
// Más allá del último índice, se usa el último valor (150).
SHOP_REROLL_COSTS := [4]i32{0, 30, 75, 150}

// Skip sin comprar nada → +N oro por skip consecutivo, capeado.
// Reset al comprar cualquier cosa.
SHOP_SKIP_BONUS_PER_SKIP :: i32(15)
SHOP_SKIP_BONUS_CAP      :: i32(50)

// Pity: después de N shops sin ver UNIQUE, el próximo shop fuerza una UNIQUE.
SHOP_PITY_UNIQUE_THRESHOLD :: i32(8)

// Refund de stacks de relictos ya aplicados durante el shop.
SHOP_RELIC_REFUND_PRICE :: i32(40)

// Modificador de shop por bioma.
Shop_Biome_Mod :: struct {
	price_mult:        f32,    // multiplicador global de precios
	extra_slots:       i32,    // +N (o -N) slots respecto al base
	free_reroll:       bool,   // ignora SHOP_REROLL_COSTS, siempre gratis
	uncommon_discount: f32,    // descuento adicional a UNCOMMON (0.10 = -10%)
	label_key:         string, // clave de traducción del header
}

BIOME_SHOP_MODS := [Biome]Shop_Biome_Mod {
	.PLAIN    = {price_mult = 1.0,  extra_slots =  0, free_reroll = false, uncommon_discount = 0.0,  label_key = "SHOP_BIOME_PLAIN"},
	.FOREST   = {price_mult = 1.0,  extra_slots =  0, free_reroll = false, uncommon_discount = 0.10, label_key = "SHOP_BIOME_FOREST"},
	.DESERT   = {price_mult = 1.20, extra_slots =  1, free_reroll = false, uncommon_discount = 0.0,  label_key = "SHOP_BIOME_DESERT"},
	.MOUNTAIN = {price_mult = 1.0,  extra_slots = -1, free_reroll = true,  uncommon_discount = 0.0,  label_key = "SHOP_BIOME_MOUNTAIN"},
}

// ─────────────────────────────────────────────────────────────────────────────
// Heightmap del terreno — desniveles continuos vía shader (visual, sin gameplay)
// ─────────────────────────────────────────────────────────────────────────────

// Frecuencia del noise: 0.32 → "colinas" de ~3 celdas de ancho.
// Más alto = relieve más fino. Más bajo = colinas más grandes.
HEIGHTMAP_FREQUENCY :: f32(0.32)
HEIGHTMAP_OCTAVES   :: 3   // capas de noise para riqueza fractal

// Parámetros pasados al shader assets/heightmap.glsl.
//
// contrast_mult:    amplifica (h - 0.5). 1.0 lineal, 2-3 pronunciado.
// alpha_max:        alfa máxima del tinte en heights extremos [0..1].
// contour_steps:    número de isolíneas topográficas (cuanto más alto, más finas).
// contour_strength: alfa de las isolíneas [0..1].
// contour_width:    grosor de cada isolínea EN PIXELES de pantalla (1.0 = 1px).
//                   El shader usa fwidth() para mantenerlo constante con zoom.
Heightmap_Style :: struct {
	contrast_mult:    f32,
	alpha_max:        f32,
	contour_steps:    f32,
	contour_strength: f32,
	contour_width:    f32,
}

// Por bioma. Calibrado para "más contraste" — MOUNTAIN claramente relievado,
// PLAIN apenas visible pero presente. Líneas de contorno: 1 pixel de grosor.
BIOME_HEIGHTMAP_STYLES := [Biome]Heightmap_Style {
	.PLAIN    = {contrast_mult = 1.6, alpha_max = 0.14, contour_steps = 5.0, contour_strength = 0.090, contour_width = 1.0},
	.FOREST   = {contrast_mult = 2.0, alpha_max = 0.28, contour_steps = 7.0, contour_strength = 0.160, contour_width = 1.0},
	.DESERT   = {contrast_mult = 1.9, alpha_max = 0.24, contour_steps = 6.0, contour_strength = 0.140, contour_width = 1.0},
	.MOUNTAIN = {contrast_mult = 2.8, alpha_max = 0.50, contour_steps = 9.0, contour_strength = 0.275, contour_width = 1.0},
}

// Rarity system — probabilidades de aparición por slot de tienda (suman 1.0)
RARITY_PROB_COMMON   :: f32(0.60)
RARITY_PROB_UNCOMMON :: f32(0.25)
RARITY_PROB_RARE     :: f32(0.10)
RARITY_PROB_EPIC     :: f32(0.05)
RARITY_PROB_UNIQUE   :: f32(0.03)

// Precio de compra en la tienda por rareza (aplica a relictos y torres)
SHOP_PRICE_COMMON   :: i32(50)
SHOP_PRICE_UNCOMMON :: i32(75)
SHOP_PRICE_RARE     :: i32(110)
SHOP_PRICE_EPIC     :: i32(140)
SHOP_PRICE_UNIQUE   :: i32(160)

// Colores de rareza — usados como borde, badge y fondo de carta
RARITY_COLOR_COMMON   :: raylib.Color{160, 160, 160, 255}  // Gris
RARITY_COLOR_UNCOMMON :: raylib.Color{ 50, 200, 100, 255}  // Verde
RARITY_COLOR_RARE     :: raylib.Color{ 80, 130, 255, 255}  // Azul
RARITY_COLOR_EPIC     :: raylib.Color{180,  60, 255, 255}  // Morado
RARITY_COLOR_UNIQUE   :: raylib.Color{255, 160,  20, 255}  // Dorado

// Fondos de carta por rareza — versiones pastel/suaves para que el texto negro sea legible
RARITY_CARD_BG_COMMON   :: raylib.Color{222, 222, 226, 255}
RARITY_CARD_BG_UNCOMMON :: raylib.Color{190, 238, 205, 255}
RARITY_CARD_BG_RARE     :: raylib.Color{190, 210, 252, 255}
RARITY_CARD_BG_EPIC     :: raylib.Color{228, 190, 252, 255}
RARITY_CARD_BG_UNIQUE   :: raylib.Color{252, 228, 168, 255}

OBSTACLE_BASE_COST              :: i32(25)  // Gold cost to place an obstacle card from hand
OBSTACLE_UPGRADE_COST_BASE :: 50  // Base cost; doubles each level: 50, 100, 200, 400…

// =============================================================================
// Money
// =============================================================================

MONEY_WAVE_CLEAR_BASE     :: i32(30)   // Base gold per wave clear
MONEY_WAVE_CLEAR_PER_WAVE :: i32(2)    // Extra gold per wave number (ola 1→32, ola 50→130, ola 100→230)
INTEREST_RATE    :: f32(0.05)  // Fraction of current gold awarded as interest at wave start

// =============================================================================
// Environment colors
// =============================================================================

COLOR_GRID_LINE  :: raylib.Color{150, 150, 150, 100}
COLOR_PATH       :: raylib.Color{210, 180, 140, 255}
COLOR_SPAWN      :: raylib.Color{100, 200, 100, 255}
COLOR_GOAL       :: raylib.Color{200, 100, 100, 255}
COLOR_TREE_TRUNK :: raylib.Color{139,  69,  19, 255}
COLOR_TREE_LEAVES :: raylib.Color{ 34, 139,  34, 255}
COLOR_BLOCK    :: raylib.Color{128, 128, 128, 255}
COLOR_OBSTACLE :: raylib.Color{160,  82,  45, 255}
// COLOR_LASER_BEAM eliminado — usar TOWER_LASER_COLOR (mismo valor {255,68,68,255})

// Water
COLOR_WATER       :: raylib.Color{ 70, 130, 200, 220}  // Azul semitransparente
COLOR_WATER_EDGE  :: raylib.Color{ 50, 100, 170, 255}  // Borde/sombra del agua
WATER_CORNER_RADIUS_RATIO :: f32(0.32)                  // Radio de esquinas como fracción del tile

// Bridge (path over water)
COLOR_BRIDGE_RAILING  :: raylib.Color{ 80,  75,  70, 255}  // Barandas de cemento oscuro
BRIDGE_RAILING_THICK  :: f32(0.07)                          // Grosor de baranda como fracción del tile
BRIDGE_RAILING_SEGS   :: i32(4)                             // Segmentos para las puntas redondeadas

// =============================================================================
// Bird flock
// =============================================================================

BIRD_SPEED              :: f32(140.0)   // Pixels per second
BIRD_FLAP_FREQ          :: f32(3.2)    // Wing flap cycles per second
BIRD_WING_AMP           :: f32(5.0)    // Wing-tip vertical oscillation amplitude in pixels
BIRD_SIZE               :: f32(7.0)    // Half-wingspan in pixels (scales with zoom)
BIRD_COUNT_MIN          :: i32(5)
BIRD_COUNT_MAX          :: i32(12)
BIRD_SPAWN_INTERVAL_MIN :: f32(45.0)   // Seconds between flocks (min)
BIRD_SPAWN_INTERVAL_MAX :: f32(120.0)  // Seconds between flocks (max)
BIRD_SCATTER_RADIUS     :: f32(60.0)   // Max distance birds spread from flock center
COLOR_BIRD              :: raylib.Color{30, 30, 30, 200}

// =============================================================================
// Enemy colors
// =============================================================================

// HUD / wave-indicator colors — used in the wave preview UI
COLOR_ENEMY_DEFAULT :: raylib.Color{220,  60,  60, 255}  // Normal red enemy
COLOR_ENEMY_GREEN   :: raylib.Color{ 60, 180,  60, 255}  // Fast green enemy
COLOR_ENEMY_BLUE    :: raylib.Color{ 60, 100, 220, 255}  // Healer blue enemy
COLOR_ENEMY_BOSS    :: raylib.Color{220, 200,  60, 255}  // Boss (gold)
COLOR_ENEMY_FLYING  :: raylib.Color{255, 220,  60, 255}  // Flying (yellow)
COLOR_ENEMY_SPLIT   :: raylib.Color{180,  60, 210, 255}  // Splitter (purple)
COLOR_ENEMY_BONUS   :: raylib.Color{255, 140,   0, 255}  // Bonus (orange)
COLOR_ENEMY_SHADOW  :: raylib.Color{  0,   0,   0,  20}  // Drop shadow under enemies

// Enemy body fill colors — used when drawing enemies on the map.
// More saturated than the HUD colors above; kept separate because the values differ.
ENEMY_GREEN  :: raylib.Color{  0, 255,   0, 255}
ENEMY_BLUE   :: raylib.Color{  0,   0, 255, 255}

// Alias kept for code paths that reference the old name
COLOR_ENEMY :: COLOR_ENEMY_DEFAULT

ENEMY_BORDER_THICKNESS :: 3  // Stroke width used when drawing enemy outlines

// =============================================================================
// Obstacle rendering
// =============================================================================

OBSTACLE_BARRIER_THICKNESS     :: f32(0.16)  // Narrow dimension as a fraction of cell size
OBSTACLE_BARRIER_LENGTH        :: f32(0.86)  // Long dimension as a fraction of cell size
OBSTACLE_BARRIER_ROUNDNESS     :: f32(0.35)
OBSTACLE_BARRIER_SHADOW_OFFSET :: f32(3)
OBSTACLE_BARRIER_BORDER_THICK  :: f32(1.5)
COLOR_OBSTACLE_FILL   :: raylib.Color{145, 150, 158, 255}  // Blue-grey fill
COLOR_OBSTACLE_BORDER :: raylib.Color{ 85,  90,  98, 255}  // Dark border
COLOR_OBSTACLE_SHADOW :: raylib.Color{  0,   0,   0,  55}  // Drop shadow

// =============================================================================
// Biome colors
// =============================================================================

BIOME_COLORS := [Biome]Biome_Colors {
	.PLAIN = {
		bg      = raylib.Color{210, 215, 200, 255},
		bg_grid = raylib.Color{200, 205, 190, 255},
		path    = raylib.Color{185, 190, 175, 255},
	},
	.FOREST = {
		bg      = raylib.Color{170, 190, 170, 255},
		bg_grid = raylib.Color{155, 175, 155, 255},
		path    = raylib.Color{140, 160, 140, 255},
	},
	.DESERT = {
		bg      = raylib.Color{230, 215, 195, 255},
		bg_grid = raylib.Color{220, 205, 185, 255},
		path    = raylib.Color{205, 190, 170, 255},
	},
	.MOUNTAIN = {
		bg      = raylib.Color{190, 195, 200, 255},
		bg_grid = raylib.Color{175, 180, 185, 255},
		path    = raylib.Color{160, 165, 170, 255},
	},
}

BIOME_TREE_COLORS := [Biome]Biome_Tree_Colors {
	.PLAIN = {
		layer_dark  = raylib.Color{ 90, 130,  90, 255},
		layer_mid   = raylib.Color{110, 150, 110, 255},
		layer_light = raylib.Color{130, 170, 130, 255},
		layer_tip   = raylib.Color{150, 190, 150, 255},
		trunk       = raylib.Color{140, 110,  80, 255},
	},
	.FOREST = {
		layer_dark  = raylib.Color{ 60,  90,  70, 255},
		layer_mid   = raylib.Color{ 80, 115,  90, 255},
		layer_light = raylib.Color{100, 140, 110, 255},
		layer_tip   = raylib.Color{120, 165, 130, 255},
		trunk       = raylib.Color{100,  80,  65, 255},
	},
	.DESERT = {
		layer_dark  = raylib.Color{100, 140, 100, 255},
		layer_mid   = raylib.Color{120, 160, 120, 255},
		layer_light = raylib.Color{140, 180, 140, 255},
		layer_tip   = raylib.Color{160, 200, 160, 255},
		trunk       = raylib.Color{150, 120,  90, 255},
	},
	.MOUNTAIN = {
		layer_dark  = raylib.Color{ 90, 110,  90, 255},
		layer_mid   = raylib.Color{110, 130, 110, 255},
		layer_light = raylib.Color{130, 150, 130, 255},
		layer_tip   = raylib.Color{150, 170, 150, 255},
		trunk       = raylib.Color{115, 100,  85, 255},
	},
}

// =============================================================================
// Tower rendering
// =============================================================================

TOWER_CELL_SIZE_RATIO    :: f32(0.8)   // Tower body size as a fraction of cell size
TOWER_BORDER_THICKNESS   :: 3          // Outline stroke thickness in pixels
TOWER_ROUNDED_CORNER     :: f32(0.3)   // Rounded-rectangle corner radius (0 = sharp, 1 = full)
TOWER_CORNER_SEGMENTS    :: 8          // Segments used for rounded corner arcs
TOWER_INNER_SIZE_RATIO   :: f32(0.25)  // Center dot size as a fraction of tower size
TOWER_BARREL_WIDTH_RATIO :: f32(0.25)  // Barrel width as a fraction of tower size
TOWER_BARREL_LENGTH_RATIO :: f32(0.6)  // Barrel length as a fraction of tower size
TOWER_HATCH_RADIUS_RATIO :: f32(0.15)  // Hatch/circle size ratio

TOWER_RANGE_PREVIEW :: raylib.Color{255, 255, 255,  30}  // Range fill (very faint, used for all-towers overlay)
TOWER_RANGE_OUTLINE :: raylib.Color{255, 255, 255,  60}  // Range outline for the all-towers overlay setting

// =============================================================================
// Tower colors
// =============================================================================

TOWER_BORDER_COLOR      :: raylib.BLACK
TOWER_INNER_COLOR       :: raylib.DARKGRAY
TOWER_BASE_COLOR        :: raylib.Color{190, 190, 190, 255}
TOWER_SECONDARY_COLOR   :: raylib.Color{150, 150, 150, 255}
TOWER_HIGHLIGHT_COLOR   :: raylib.Color{230, 230, 230, 255}
TOWER_SHADOW            :: raylib.Color{  0,   0,   0,  30}

TOWER_BARREL            :: raylib.Color{100, 140, 180, 255}
TOWER_BARREL_OUTLINE    :: raylib.Color{ 40,  40,  50, 255}
TOWER_CANNON_COLOR      :: raylib.Color{ 70,  70,  80, 255}
TOWER_CANNON_BASE       :: raylib.Color{ 90, 110, 140, 255}
TOWER_CANNON_STROKE     :: raylib.Color{ 80,  90, 110, 255}
TOWER_LASER_COLOR       :: raylib.Color{255,  68,  68, 255}
TOWER_LASER_CORE        :: raylib.Color{100, 200, 255, 255}
TOWER_LASER_BASE        :: raylib.Color{ 80, 120, 160, 255}
TOWER_LASER_STROKE      :: raylib.Color{ 60, 100, 180, 255}
TOWER_MISSILE_BASE      :: raylib.Color{160, 100,  80, 255}
TOWER_MISSILE_POD       :: raylib.Color{120,  80,  60, 255}
TOWER_MISSILE_WARHEAD   :: raylib.Color{255,  60,  60, 255}
TOWER_MISSILE_STROKE    :: raylib.Color{180,  70,  60, 255}
TOWER_SNIPER_BASE       :: raylib.Color{ 40, 140,  60, 255}
TOWER_SNIPER_STROKE     :: raylib.Color{ 30, 100,  40, 255}
TOWER_ARCHER_BASE       :: raylib.Color{160, 110,  60, 255}
TOWER_ARCHER_STROKE     :: raylib.Color{120,  80,  40, 255}
TOWER_ARCHER_WOOD       :: raylib.Color{180, 110,  50, 255}
TOWER_ARCHER_STRING     :: raylib.Color{220, 220, 220, 255}
TOWER_ICE_BASE          :: raylib.Color{160, 220, 245, 255}
TOWER_ICE_STROKE        :: raylib.Color{ 70, 160, 210, 255}
TOWER_ENHANCE_BASE      :: raylib.Color{230, 180,  40, 255}
TOWER_ENHANCE_STROKE    :: raylib.Color{180, 130,  20, 255}
TOWER_ENHANCE_GLOW      :: raylib.Color{255, 230, 100, 200}
TOWER_TESLA_BASE        :: raylib.Color{ 85,  55, 175, 255}
TOWER_TESLA_STROKE      :: raylib.Color{120,  70, 220, 255}
TOWER_TESLA_ARC         :: raylib.Color{200, 230, 255, 255}
TOWER_MORTAR_BASE       :: raylib.Color{ 70, 100,  55, 255}
TOWER_MORTAR_STROKE     :: raylib.Color{ 45,  65,  30, 255}

// =============================================================================
// UI layout
// =============================================================================

UI_BUTTON_WIDTH        :: i32(80)
UI_BUTTON_HEIGHT       :: i32(24)
UI_BUTTON_FONT_SIZE    :: i32(16)
UI_BUTTON_SHADOW_OFFSET :: i32(2)
UI_BUTTON_ROUNDNESS    :: f32(0.3)

UI_DROPDOWN_WIDTH  :: i32(80)
UI_DROPDOWN_HEIGHT :: i32(24)
UI_INPUT_WIDTH     :: i32(80)
UI_INPUT_HEIGHT    :: i32(24)

UI_SEGMENTS      :: 8
UI_ROUNDNESS     :: f32(0.05)
UI_SHADOW_OFFSET :: 4

UI_PANEL_HEADER_SIZE :: 32  // Font size for the panel header/hero text
UI_PANEL_TITLE_SIZE  :: 22
UI_PANEL_LABEL_SIZE  :: 18
UI_PANEL_TEXT_SIZE   :: 14
UI_PANEL_WIDTH       :: 200
UI_PANEL_HEIGHT      :: 295
UI_PANEL_MARGIN      :: 10
UI_PANEL_Y_POSITION  :: 150
UI_PANEL_ROUNDNESS   :: 0.2

UI_MARGIN_X :: 10  // Screen-edge horizontal margin for panels
UI_MARGIN_Y :: 8   // Screen-edge vertical margin for panels
UI_PANEL_PADDING :: 14  // Internal padding inside panels (both axes)

TOOLTIP_MARGIN_X      :: i32(6)
TOOLTIP_MARGIN_Y      :: i32(4)
UI_TOOLTIP_FONT_SIZE  :: i32(12)
UI_TOOLTIP_PADDING_H  :: i32(8)
UI_TOOLTIP_PADDING_V  :: i32(5)
UI_TOOLTIP_OFFSET     :: i32(8)    // Distance above the trigger area
UI_TOOLTIP_SEGMENTS   :: f32(8)
UI_TOOLTIP_ROUNDNESS  :: f32(0.3)
UI_TOOLTIP_SHADOW_OFF :: f32(4)

UI_TOAST_FONT_SIZE     :: i32(16)
UI_TOAST_PADDING       :: i32(12)
UI_TOAST_SPACING       :: i32(8)
UI_TOAST_MARGIN_TOP    :: i32(80)  // Distance from top to avoid UI overlap
UI_TOAST_SHADOW_OFFSET :: i32(2)
UI_TOAST_ROUNDNESS     :: f32(0.3)

// =============================================================================
// UI colors
// =============================================================================

UI_BUTTON_COLOR         :: raylib.Color{255, 255, 255, 255}
UI_BUTTON_HOVER_COLOR   :: raylib.Color{220, 220, 220, 255}
UI_BUTTON_PRESSED_COLOR :: raylib.Color{255, 255,   0, 255}
UI_BUTTON_SHADOW_COLOR  :: raylib.Color{  0,   0,   0,  30}

// Botones de acción positiva (Iniciar oleada, velocidad activa)
UI_BUTTON_ACTION_COLOR  :: raylib.Color{ 40, 167,  69, 255}
UI_BUTTON_ACTION_HOVER  :: raylib.Color{ 30, 140,  55, 255}
UI_BUTTON_ACTION_PRESS  :: raylib.Color{ 20, 110,  40, 255}

// Botones de venta (vender carta, vender torre/obstáculo)
UI_BUTTON_SELL_COLOR    :: raylib.Color{180,  40,  40, 255}
UI_BUTTON_SELL_HOVER    :: raylib.Color{210,  60,  60, 255}
UI_BUTTON_SELL_PRESS    :: raylib.Color{150,  20,  20, 255}

// Botón de pausa activo (amarillo cuando el juego está pausado)
UI_BUTTON_PAUSE_COLOR   :: raylib.Color{220, 170,   0, 255}
UI_BUTTON_PAUSE_HOVER   :: raylib.Color{190, 145,   0, 255}
UI_BUTTON_PAUSE_PRESS   :: raylib.Color{160, 120,   0, 255}

// Transparente — usado como valor nulo en parámetros de color de botones
COLOR_NONE              :: raylib.Color{  0,   0,   0,   0}

UI_TEXT_COLOR            :: raylib.Color{ 20,  20,  20, 255}
UI_OVERLAY_COLOR         :: raylib.Color{  0,   0,   0, 200}
UI_SHADOW_COLOR          :: raylib.Color{  0,   0,   0,  30}
UI_EDITOR_HIGHLIGHT_COLOR :: raylib.Color{150, 150, 150, 255}

UI_PANEL_TITLE_COLOR :: raylib.GRAY
UI_PANEL_LABEL_COLOR :: raylib.DARKGRAY
UI_PANEL_TEXT_COLOR  :: raylib.BLACK
UI_PANEL_COLOR       :: raylib.RAYWHITE

UI_MODAL_CONFIRM_BUTTON_COLOR :: raylib.Color{0, 200, 0, 255}
UI_MODAL_CANCEL_BUTTON_COLOR  :: raylib.Color{200, 0, 0, 255}

UI_RETICLE_COLOR :: raylib.Color{255, 255, 255, 255}

UI_TOOLTIP_BG_COLOR     :: raylib.Color{ 28,  28,  32, 225}
UI_TOOLTIP_TEXT_COLOR   :: raylib.Color{230, 230, 230, 255}
UI_TOOLTIP_SHADOW_COLOR :: raylib.Color{  0,   0,   0,  70}

UI_TOAST_SUCCESS_COLOR       :: raylib.Color{ 50, 200,  50, 240}
UI_TOAST_SUCCESS_TEXT_COLOR  :: raylib.Color{255, 255, 255, 255}
UI_TOAST_INFO_COLOR          :: raylib.Color{ 50, 150, 200, 240}
UI_TOAST_INFO_TEXT_COLOR     :: raylib.Color{255, 255, 255, 255}
UI_TOAST_WARNING_COLOR       :: raylib.Color{200, 150,  50, 240}
UI_TOAST_WARNING_TEXT_COLOR  :: raylib.Color{255, 255, 255, 255}
UI_TOAST_ERROR_COLOR         :: raylib.Color{200,  50,  50, 240}
UI_TOAST_ERROR_TEXT_COLOR    :: raylib.Color{255, 255, 255, 255}

// =============================================================================
// Menu background
// =============================================================================

MENU_BG_TOP_COLOR    :: raylib.Color{15, 15, 35, 255}    // Dark blue
MENU_BG_BOTTOM_COLOR :: raylib.Color{30, 35, 50, 255}    // Dark purple
MENU_GRID_COLOR      :: raylib.Color{40, 40, 60,  80}
MENU_GRID_SPACING    :: i32(40)
MENU_GRID_SPEED      :: f32(10.0)  // Pixels per second for diagonal scroll animation

// =============================================================================
// Map browser panel
// =============================================================================

UI_MAP_BROWSER_WIDTH             :: i32(700)
UI_MAP_BROWSER_HEIGHT            :: i32(500)
UI_MAP_BROWSER_SHADOW_OFFSET     :: i32(4)
UI_MAP_BROWSER_TITLE_Y_OFFSET    :: i32(14)
UI_MAP_BROWSER_SEPARATOR_Y       :: i32(38)
UI_MAP_BROWSER_HEADER_HEIGHT     :: i32(46)
UI_MAP_BROWSER_FOOTER_HEIGHT     :: i32(52)
UI_MAP_BROWSER_ITEM_HEIGHT       :: i32(36)
UI_MAP_BROWSER_ITEM_SIDE_PADDING :: i32(8)
UI_MAP_BROWSER_ITEM_VERT_GAP     :: i32(4)
UI_MAP_BROWSER_ITEM_TEXT_INDENT  :: i32(10)
UI_MAP_BROWSER_ITEM_FONT_SIZE    :: i32(13)
UI_MAP_BROWSER_SCROLL_FONT_SIZE  :: i32(11)
UI_MAP_BROWSER_CLOSE_HEIGHT      :: i32(28)
UI_MAP_BROWSER_CLOSE_BTN_MARGIN  :: i32(12)
UI_MAP_BROWSER_TITLE_FONT_SIZE   :: i32(16)
UI_MAP_BROWSER_LIST_WIDTH        :: i32(230)
UI_MAP_BROWSER_INFO_HEIGHT       :: i32(48)
UI_MAP_BROWSER_INFO_FONT_SIZE    :: i32(12)
UI_MAP_BROWSER_PREVIEW_PAD       :: i32(12)

UI_MAP_BROWSER_OVERLAY_COLOR      :: raylib.Color{  0,   0,   0, 140}
UI_MAP_BROWSER_SHADOW_COLOR       :: raylib.Color{  0,   0,   0,  80}
UI_MAP_BROWSER_SEPARATOR_COLOR    :: raylib.Color{180, 180, 180, 200}
UI_MAP_BROWSER_MUTED_COLOR        :: raylib.Color{130, 130, 130, 255}
UI_MAP_BROWSER_LOADED_COLOR       :: raylib.Color{ 30, 120,  30, 255}
UI_MAP_BROWSER_SELECTED_BG_COLOR  :: raylib.Color{ 30, 120,  30,  45}

// =============================================================================
// Zoom
// =============================================================================

ZOOM_MIN         :: f32(0.4)
ZOOM_MAX         :: f32(3.0)
ZOOM_SPEED       :: f32(0.1)   // Zoom delta per mouse-wheel tick
ZOOM_SMOOTH_SPEED :: f32(8.0)  // Lerp factor per second for smooth zoom

ease_zoom :: proc(t: f32) -> f32 {
	return t * t * t  // Ease-in cubic
}


// =============================================================================
// Text input widget
// =============================================================================

MAX_INPUT_LEN            :: 64
INPUT_FONT_SIZE          :: f32(13)
INPUT_PAD_H              :: f32(5)       // Horizontal padding inside the input box
INPUT_BORDER_THICK       :: f32(1.0)
INPUT_BORDER_THICK_FOCUSED :: f32(2.0)
INPUT_BORDER_COLOR       :: raylib.Color{160, 160, 160, 255}
INPUT_BORDER_FOCUSED     :: raylib.Color{ 80, 130, 255, 255}
INPUT_BG_COLOR           :: raylib.Color{255, 255, 255, 255}
INPUT_SELECT_COLOR       :: raylib.Color{ 80, 130, 255,  80}
INPUT_PLACEHOLDER_COLOR  :: raylib.Color{160, 160, 160, 255}
INPUT_BLINK_HALF         :: f32(0.5)     // Cursor visible when blink < this
INPUT_CURSOR_WIDTH       :: f32(2.0)
INPUT_CURSOR_COLOR       :: raylib.Color{ 30,  30,  30, 255}


// =============================================================================
// Airdrop
// =============================================================================

AIRDROP_SPAWN_INTERVAL_MIN :: f32(20.0)  // Segundos mínimos entre drops
AIRDROP_SPAWN_INTERVAL_MAX :: f32(50.0)  // Segundos máximos entre drops
AIRDROP_PLANE_SPEED        :: f32(180.0) // Velocidad del avión (world px/s)
AIRDROP_PLANE_Y_OFFSET     :: f32(-60.0) // Y del avión relativo al borde superior del mapa
AIRDROP_BOX_FALL_SPEED     :: f32(2.2)   // Duración de la caída del paracaídas (segundos)
AIRDROP_CHUTE_RADIUS_MAX   :: f32(1.4)   // Radio inicial del círculo (multiplicador de cs)
AIRDROP_TRAIL_INTERVAL     :: f32(0.04)  // Segundos entre muestras de la estela
AIRDROP_TRAIL_MAX          :: i32(24)    // Máximo de puntos en la estela
AIRDROP_PING_INTERVAL      :: f32(3.5)   // Segundos entre pings convergentes
AIRDROP_PING_DURATION      :: f32(1.4)   // Duración del anillo encogiendo (segundos)
AIRDROP_PING_RADIUS        :: f32(2.8)   // Radio máximo del ping como múltiplo de cs
COLOR_AIRDROP_PING         :: raylib.Color{255, 220, 80, 180}  // Amarillo semitransparente
AIRDROP_MONEY_MIN          :: i32(30)    // Dinero mínimo contenido en la caja
AIRDROP_MONEY_MAX          :: i32(60)    // Dinero máximo contenido en la caja
AIRDROP_CRYSTAL_CHANCE     :: f32(0.10)  // Probabilidad de incluir cristales
AIRDROP_CRYSTAL_MIN        :: i32(5)     // Cristales mínimos en la caja
AIRDROP_CRYSTAL_MAX        :: i32(10)    // Cristales máximos en la caja
COLOR_AIRDROP_BOX          :: raylib.Color{210, 160,  40, 255}  // Marrón dorado
COLOR_AIRDROP_BOX_DARK     :: raylib.Color{150, 100,  20, 255}  // Borde de la caja
COLOR_AIRDROP_PLANE        :: raylib.Color{180, 180, 195, 255}  // Gris avión
COLOR_AIRDROP_CHUTE        :: raylib.Color{240, 240, 240, 200}  // Blanco paracaídas

// =============================================================================
// Editor
// =============================================================================

EDITOR_MAX_HISTORY :: 50  // Maximum undo/redo snapshots kept in memory

package constants

import "vendor:raylib"

// Game State
Game_State :: enum {
	MENU,
	PLAYING,
	PAUSED,
	EDITOR,
	GAME_OVER,
	SETTINGS,
}

UPGRADE_COST_BASE :: 50
UPGRADE_COST_INCREMENTVEL :: 25
GRID_SIZE_CHANCE :: 0.05
CRIT_BASE_CHANCE :: 0.05
CRIT_PER_LEVEL :: 0.03
SELL_REFUND :: 0.5
CRIT_DAMAGE_MULTIPLIER :: 2.0
LASER_FIRING_DURATION :: 1.0
LASER_ACCUMULATION_TIME :: 0.1
LASER_DAMAGE_MULTIPLIER_PER_LEVEL :: 1.5
LASER_COOLDOWN_REDUCTION_PER_LEVEL :: 0.15

// Money constants
MONEY_WAVE_CLEAR :: 100

// Tile types
Tile :: enum i32 {
	EMPTY = 0,
	PATH = 1,
	SPAWN = 2,
	GOAL = 3,
	TOWER_ARCHER = 4,
	TOWER_CANNON = 5,
	TOWER_SNIPER = 6,
	TOWER_MISSILE = 7,
	TOWER_LASER = 8,
	OBSTACLE = 9,
	ACCESSORY_TREE = 10,
	ACCESSORY_BLOCK = 11,
}

// Tower Types
Tower_Type :: enum {
	ARCHER,
	CANNON,
	SNIPER,
	MISSILE,
	LASER,
}

// Tower Target Strategies
Target_Strategy :: enum {
	FIRST,
	LAST,
	MAX_HP,
	MIN_HP,
}

// Biomes
Biome :: enum {
	PLAIN,
	FOREST,
	DESERT,
	MOUNTAIN,
}

// Tower Specifications
Tower_Spec :: struct {
	type: Tower_Type,
	range: f32,
	damage: f32,
	cooldown: f32,
	aoe: f32,
	cost: i32,
	color: raylib.Color,
}

// Tile data for extra properties
Tile_Data :: struct {
	level: i32,
}

// Tower specs lookup
TOWER_SPECS := [Tower_Type]Tower_Spec{
	.ARCHER = {
		type = .ARCHER,
		range = 2.5,
		damage = 2.5,
		cooldown = 0.2,
		aoe = 0,
		cost = 20,
		color = raylib.BROWN,
	},
	.CANNON = {
		type = .CANNON,
		range = 3.0,
		damage = 4.0,
		cooldown = 1.0,
		aoe = 1.0,
		cost = 40,
		color = raylib.DARKGRAY,
	},
	.SNIPER = {
		type = .SNIPER,
		range = 5.0,
		damage = 8.0,
		cooldown = 1.5,
		aoe = 0,
		cost = 60,
		color = raylib.GREEN,
	},
	.MISSILE = {
		type = .MISSILE,
		range = 4.0,
		damage = 6.0,
		cooldown = 0.8,
		aoe = 0.5,
		cost = 50,
		color = raylib.RED,
	},
	.LASER = {
		type = .LASER,
		range = 3.5,
		damage = 1.5,
		cooldown = 0.1,
		aoe = 0,
		cost = 80,
		color = raylib.MAGENTA,
	},
}

// Enemy constants
ENEMY_GROWTH_RATE :: 1.15

// Biome colors
Biome_Colors :: struct {
	bg: raylib.Color,
	bg_grid: raylib.Color,
	path: raylib.Color,
}

BIOME_COLORS := [Biome]Biome_Colors{
	.PLAIN = {
		bg = raylib.Color{200, 220, 180, 255},
		bg_grid = raylib.Color{190, 210, 170, 255},
		path = raylib.Color{175, 195, 155, 255},
	},
	.FOREST = {
		bg = raylib.Color{150, 200, 150, 255},
		bg_grid = raylib.Color{130, 180, 130, 255},
		path = raylib.Color{120, 160, 120, 255},
	},
	.DESERT = {
		bg = raylib.Color{240, 220, 170, 255},
		bg_grid = raylib.Color{230, 210, 160, 255},
		path = raylib.Color{200, 180, 130, 255},
	},
	.MOUNTAIN = {
		bg = raylib.Color{180, 190, 200, 255},
		bg_grid = raylib.Color{160, 170, 180, 255},
		path = raylib.Color{150, 155, 165, 255},
	},
}

// Biome tree colors (pine/tree layers)
Biome_Tree_Colors :: struct {
	layer_dark: raylib.Color,
	layer_mid: raylib.Color,
	layer_light: raylib.Color,
	layer_tip: raylib.Color,
	trunk: raylib.Color,
}

BIOME_TREE_COLORS := [Biome]Biome_Tree_Colors{
	.PLAIN = {
		layer_dark = raylib.Color{40, 130, 40, 255},
		layer_mid = raylib.Color{50, 150, 50, 255},
		layer_light = raylib.Color{60, 170, 60, 255},
		layer_tip = raylib.Color{70, 190, 70, 255},
		trunk = raylib.Color{139, 69, 19, 255},
	},
	.FOREST = {
		layer_dark = raylib.Color{10, 70, 30, 255},    // Pine dark
		layer_mid = raylib.Color{20, 90, 40, 255},     // Pine mid
		layer_light = raylib.Color{30, 110, 50, 255},  // Pine light
		layer_tip = raylib.Color{40, 130, 60, 255},    // Pine tip
		trunk = raylib.Color{80, 50, 30, 255},
	},
	.DESERT = {
		layer_dark = raylib.Color{20, 100, 20, 255},
		layer_mid = raylib.Color{34, 139, 34, 255},
		layer_light = raylib.Color{60, 180, 60, 255},
		layer_tip = raylib.Color{80, 220, 80, 255},
		trunk = raylib.Color{160, 82, 45, 255},
	},
	.MOUNTAIN = {
		layer_dark = raylib.Color{60, 80, 60, 255},
		layer_mid = raylib.Color{80, 100, 80, 255},
		layer_light = raylib.Color{100, 120, 100, 255},
		layer_tip = raylib.Color{120, 140, 120, 255},
		trunk = raylib.Color{101, 67, 33, 255},
	},
}

// Game constants
GRID_SIZE :: 20
CELL_SIZE :: 32
DEFAULT_MONEY :: 100
DEFAULT_HEALTH :: 20
MAX_FPS :: 60

// Colors
COLOR_ENEMY :: raylib.Color{220, 60, 60, 255}
COLOR_ENEMY_GREEN :: raylib.Color{60, 180, 60, 255}
COLOR_ENEMY_BLUE :: raylib.Color{60, 100, 220, 255}
COLOR_ENEMY_BOSS :: raylib.Color{220, 200, 60, 255}
COLOR_ENEMY_FLYING :: raylib.Color{255, 220, 60, 255}  // Yellow flying enemy

COLOR_GRID_LINE :: raylib.Color{150, 150, 150, 100}
COLOR_PATH :: raylib.Color{210, 180, 140, 255}
COLOR_SPAWN :: raylib.Color{100, 200, 100, 255}
COLOR_GOAL :: raylib.Color{200, 100, 100, 255}
COLOR_TREE_TRUNK :: raylib.Color{139, 69, 19, 255}
COLOR_TREE_LEAVES :: raylib.Color{34, 139, 34, 255}
COLOR_BLOCK :: raylib.Color{128, 128, 128, 255}
COLOR_OBSTACLE :: raylib.Color{160, 82, 45, 255}
COLOR_LASER_BEAM :: raylib.Color{255, 68, 68, 255}

// Enemy colors
ENEMY_GREEN :: raylib.Color{0, 255, 0, 255}
ENEMY_BLUE :: raylib.Color{0, 0, 255, 255}
ENEMY_FLYING :: raylib.Color{255, 220, 60, 255}  // Yellow flying enemy

// Tower stroke colors (for rendering)
TOWER_LASER_STROKE :: raylib.Color{80, 90, 100, 255}
TOWER_CANNON_STROKE :: raylib.Color{90, 100, 110, 255}
TOWER_MISSILE_STROKE :: raylib.Color{100, 90, 80, 255}
TOWER_SNIPER_BASE :: raylib.Color{100, 110, 120, 255}
TOWER_SNIPER_STROKE :: raylib.Color{70, 80, 90, 255}
TOWER_ARCHER_BASE :: raylib.Color{120, 100, 80, 255}
TOWER_ARCHER_STROKE :: raylib.Color{90, 70, 50, 255}

// UI Size Constants (raygui minimum sizes)
UI_BUTTON_WIDTH :: 80
UI_BUTTON_HEIGHT :: 24
UI_BUTTON_FONT_SIZE :: 16
UI_BUTTON_SHADOW_OFFSET :: 3

// UI Color Constants
UI_BUTTON_COLOR :: raylib.Color{255, 255, 255, 255}
UI_BUTTON_HOVER_COLOR :: raylib.Color{220, 220, 220, 255}
UI_BUTTON_PRESSED_COLOR :: raylib.Color{255, 255, 0, 255}
UI_BUTTON_SHADOW_COLOR :: raylib.Color{0, 0, 0, 20}

UI_TEXT_COLOR :: raylib.Color{20, 20, 20, 255}
UI_OVERLAY_COLOR :: raylib.Color{0, 0, 0, 200}

UI_DROPDOWN_WIDTH :: 80
UI_DROPDOWN_HEIGHT :: 24

UI_INPUT_WIDTH :: 80
UI_INPUT_HEIGHT :: 24

UI_TOOLBAR_HEIGHT :: 34
UI_PANEL_WIDTH :: 200
UI_PANEL_HEIGHT :: 295

PANEL_TEXT_COLOR :: raylib.GRAY

// Zoom Constants
ZOOM_MIN :: 0.5
ZOOM_MAX :: 3.0
ZOOM_SPEED :: 0.1  // Zoom speed per wheel tick (reduced for smoother feel)
ZOOM_SMOOTH_SPEED :: 8.0  // Speed of zoom smoothing (lerp factor per second)

// Easing function for zoom (ease-in: slow start, fast end)
ease_zoom :: proc(t: f32) -> f32 {
	// Ease-in cubic: t * t * t
	return t * t * t
}

// Tower Rendering Constants
TOWER_CELL_SIZE_RATIO :: 0.8           // Tower size as ratio of cell size
TOWER_BORDER_THICKNESS :: 3            // Border thickness in pixels
TOWER_BORDER_COLOR :: raylib.BLACK
TOWER_INNER_COLOR :: raylib.DARKGRAY   // Center dot color
TOWER_INNER_SIZE_RATIO :: 0.25         // Inner dot size as ratio of tower size
TOWER_ROUNDED_CORNER :: 0.3            // Rectangle rounded corners (0.0 to 1.0)
TOWER_CORNER_SEGMENTS :: 8             // Number of segments for rounded corners

// Tower Color Constants
TOWER_BASE_COLOR :: raylib.Color{180, 180, 180, 255}      // Base tower body color
TOWER_SECONDARY_COLOR :: raylib.Color{140, 140, 140, 255}   // Secondary/accent color
TOWER_CANNON_COLOR :: raylib.Color{60, 60, 60, 255}        // Cannon barrel color
TOWER_BARREL_OUTLINE :: raylib.Color{30, 30, 30, 255}       // Barrel outline color
TOWER_HIGHLIGHT_COLOR :: raylib.Color{220, 220, 220, 255}   // Highlight/bright areas

// Tower-specific Colors (JS Style)
TOWER_BARREL :: raylib.Color{143, 161, 179, 255}            // Tower barrel color (JS: #8fa1b3)
TOWER_LASER_CORE :: raylib.Color{170, 221, 255, 255}        // Laser center glow (JS: #aaddff)
TOWER_LASER_BASE :: raylib.Color{106, 122, 138, 255}        // Laser base (JS: #6a7a8a)
TOWER_CANNON_BASE :: raylib.Color{122, 138, 154, 255}       // Cannon base (JS: #7a8a9a for bullet)
TOWER_MISSILE_BASE :: raylib.Color{138, 122, 106, 255}      // Missile base (JS: #8a7a6a)
TOWER_MISSILE_POD :: raylib.Color{106, 90, 74, 255}         // Missile pods (JS: #6a5a4a)
TOWER_MISSILE_WARHEAD :: raylib.Color{255, 85, 85, 255}     // Missile warhead (JS: #ff5555)
TOWER_SHADOW :: raylib.Color{0, 0, 0, 20}                // Shadow color
TOWER_ARCHER_WOOD :: raylib.Color{139, 90, 43, 255}         // Archer bow wood
TOWER_ARCHER_STRING :: raylib.Color{200, 200, 200, 255}     // Archer bow string
TOWER_RANGE_OUTLINE :: raylib.Color{255, 255, 255, 60}      // Tower range area outline (semi-transparent white)
TOWER_RETICLE_COLOR :: raylib.Color{255, 255, 255, 160}      // Selected cell reticle color (white with 60% opacity)

// Tower Component Size Constants
TOWER_BARREL_WIDTH_RATIO :: 0.25       // Barrel width as ratio of tower size
TOWER_BARREL_LENGTH_RATIO :: 0.6     // Barrel length as ratio of tower size
TOWER_HATCH_RADIUS_RATIO :: 0.15     // Hatch/circle size ratio

// Enemy Speed Constants (cells per second, scaled by GRID_SPEED_SCALE)
ENEMY_SPEED_DEFAULT :: 1.2             // Normal enemies
ENEMY_SPEED_GREEN :: 1.8               // Fast green enemies (50% faster)
ENEMY_SPEED_BLUE :: 1.1                // Medium blue enemies
ENEMY_SPEED_BOSS :: 0.5                // Slow bosses
ENEMY_SPEED_FLYING :: 1.3              // Flying enemies

// Enemy Size Constants (as ratio of cell size)
ENEMY_SIZE_BOSS :: 0.40                // Boss enemies (large)
ENEMY_SIZE_FLYING :: 0.25              // Flying enemies (small)
ENEMY_SIZE_BLUE :: 0.30                // Blue enemies (medium)
ENEMY_SIZE_GREEN :: 0.20               // Green enemies (tiny)
ENEMY_SIZE_DEFAULT :: 0.30             // Normal enemies (medium)

ENEMY_STROKE_WIDTH :: 4
ENEMY_SHADOW_COLOR :: raylib.Color{0, 0, 0, 20}

PATH_WIDTH_RATIO :: 0.4
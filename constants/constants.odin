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
CRIT_BASE_CHANCE :: 0.10   // 10% base critical chance for all towers
CRIT_PER_LEVEL   :: 0.05   // +5% per critical upgrade
SELL_REFUND :: 0.75
CRIT_DAMAGE_MULTIPLIER :: 2.0
LASER_FIRING_DURATION :: 1.0
LASER_ACCUMULATION_TIME :: 0.1
LASER_DAMAGE_MULTIPLIER_PER_LEVEL :: 0.5
LASER_COOLDOWN_REDUCTION_PER_LEVEL :: 0.15

// Money constants
MONEY_WAVE_CLEAR :: 100
INTEREST_RATE    :: 0.05  // 5% of current money awarded at wave start

// Enemy split constants
SPLIT_HP_RATIO   :: 0.30  // Child enemy HP = 30% of parent max_hp
SPLIT_SPEED_MULT :: 1.30  // Child enemy speed = parent speed * 1.30

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
	ACCESSORY_BLOCK = 11,
	TOWER_ICE       = 12,
}

// Tower Types
Tower_Type :: enum {
	ARCHER,
	CANNON,
	SNIPER,
	MISSILE,
	LASER,
	ICE,
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
	type:     Tower_Type,
	range:    f32,
	damage:   f32,
	cooldown: f32,
	aoe:      f32,
	cost:     i32,
	color:    raylib.Color,
}

// Tile data for extra properties
Tile_Data :: struct {
	level: i32,
}

// Tower specs lookup
TOWER_SPECS := [Tower_Type]Tower_Spec {
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
	.ICE = {
		type = .ICE,
		range = 2.5,
		damage = 0.5,
		cooldown = 2.2,
		aoe = 0,
		cost = 45,
		color = raylib.SKYBLUE,
	},
}

// Enemy constants
ENEMY_GROWTH_RATE :: 1.15
ENEMY_BASE_HP :: 10.0
ENEMY_GLOBAL_SPEED_MULTIPLIER :: 0.5 // Use this to scale all enemy speeds
ENEMY_GLOBAL_HP_MULTIPLIER :: 1.0 // Use this to scale all enemy health

// Biome colors
Biome_Colors :: struct {
	bg:      raylib.Color,
	bg_grid: raylib.Color,
	path:    raylib.Color,
}

BIOME_COLORS := [Biome]Biome_Colors {
	.PLAIN = {
		bg = raylib.Color{210, 215, 200, 255},
		bg_grid = raylib.Color{200, 205, 190, 255},
		path = raylib.Color{185, 190, 175, 255},
	},
	.FOREST = {
		bg = raylib.Color{170, 190, 170, 255},
		bg_grid = raylib.Color{155, 175, 155, 255},
		path = raylib.Color{140, 160, 140, 255},
	},
	.DESERT = {
		bg = raylib.Color{230, 215, 195, 255},
		bg_grid = raylib.Color{220, 205, 185, 255},
		path = raylib.Color{205, 190, 170, 255},
	},
	.MOUNTAIN = {
		bg = raylib.Color{190, 195, 200, 255},
		bg_grid = raylib.Color{175, 180, 185, 255},
		path = raylib.Color{160, 165, 170, 255},
	},
}

// Biome tree colors (pine/tree layers)
Biome_Tree_Colors :: struct {
	layer_dark:  raylib.Color,
	layer_mid:   raylib.Color,
	layer_light: raylib.Color,
	layer_tip:   raylib.Color,
	trunk:       raylib.Color,
}

BIOME_TREE_COLORS := [Biome]Biome_Tree_Colors {
	.PLAIN = {
		layer_dark = raylib.Color{90, 130, 90, 255},
		layer_mid = raylib.Color{110, 150, 110, 255},
		layer_light = raylib.Color{130, 170, 130, 255},
		layer_tip = raylib.Color{150, 190, 150, 255},
		trunk = raylib.Color{140, 110, 80, 255},
	},
	.FOREST = {
		layer_dark  = raylib.Color{60, 90, 70, 255},
		layer_mid   = raylib.Color{80, 115, 90, 255},
		layer_light = raylib.Color{100, 140, 110, 255},
		layer_tip   = raylib.Color{120, 165, 130, 255},
		trunk       = raylib.Color{100, 80, 65, 255},
	},
	.DESERT = {
		layer_dark = raylib.Color{100, 140, 100, 255},
		layer_mid = raylib.Color{120, 160, 120, 255},
		layer_light = raylib.Color{140, 180, 140, 255},
		layer_tip = raylib.Color{160, 200, 160, 255},
		trunk = raylib.Color{150, 120, 90, 255},
	},
	.MOUNTAIN = {
		layer_dark = raylib.Color{90, 110, 90, 255},
		layer_mid = raylib.Color{110, 130, 110, 255},
		layer_light = raylib.Color{130, 150, 130, 255},
		layer_tip = raylib.Color{150, 170, 150, 255},
		trunk = raylib.Color{115, 100, 85, 255},
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
COLOR_ENEMY_FLYING :: raylib.Color{255, 220, 60, 255} // Yellow flying enemy
COLOR_ENEMY_SPLIT  :: raylib.Color{180, 60, 210, 255}  // Purple splitter enemy
COLOR_ENEMY_BONUS  :: raylib.Color{255, 140, 0, 255}  // Orange bonus enemy

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
ENEMY_FLYING :: raylib.Color{255, 220, 60, 255} // Yellow flying enemy

// Ice tower slow constants
ICE_SLOW_FACTOR   :: f32(0.4)  // Speed multiplier while slowed (40% of normal)
ICE_SLOW_DURATION :: f32(2.0)  // Seconds the slow lasts after pulse

// Tower stroke colors (for rendering) - saturated to stand out
TOWER_ICE_BASE   :: raylib.Color{160, 220, 245, 255}  // Pale cyan-blue base
TOWER_ICE_STROKE :: raylib.Color{ 70, 160, 210, 255}  // Deeper blue stroke
TOWER_LASER_STROKE :: raylib.Color{60, 100, 180, 255}
TOWER_CANNON_STROKE :: raylib.Color{80, 90, 110, 255}
TOWER_MISSILE_STROKE :: raylib.Color{180, 70, 60, 255}
TOWER_SNIPER_BASE :: raylib.Color{40, 140, 60, 255}
TOWER_SNIPER_STROKE :: raylib.Color{30, 100, 40, 255}
TOWER_ARCHER_BASE :: raylib.Color{160, 110, 60, 255}
TOWER_ARCHER_STROKE :: raylib.Color{120, 80, 40, 255}

// UI Size Constants (raygui minimum sizes)
UI_BUTTON_WIDTH :: 80
UI_BUTTON_HEIGHT :: 24
UI_BUTTON_FONT_SIZE :: 16
UI_BUTTON_SHADOW_OFFSET :: 2
UI_BUTTON_ROUNDNESS :: 0.3

// UI Color Constants
UI_BUTTON_COLOR :: raylib.Color{255, 255, 255, 255}
UI_BUTTON_HOVER_COLOR :: raylib.Color{220, 220, 220, 255}
UI_BUTTON_PRESSED_COLOR :: raylib.Color{255, 255, 0, 255}
UI_BUTTON_SHADOW_COLOR :: raylib.Color{0, 0, 0, 30}

UI_TEXT_COLOR :: raylib.Color{20, 20, 20, 255}
UI_OVERLAY_COLOR :: raylib.Color{0, 0, 0, 200}
UI_EDITOR_HIGHLIGHT_COLOR :: raylib.Color{150, 150, 150, 255}

UI_DROPDOWN_WIDTH :: 80
UI_DROPDOWN_HEIGHT :: 24

// Menu Background Constants
MENU_GRID_COLOR :: raylib.Color{40, 40, 60, 80}
MENU_GRID_SPACING :: 40
MENU_BG_TOP_COLOR :: raylib.Color{15, 15, 35, 255}      // Dark blue
MENU_BG_BOTTOM_COLOR :: raylib.Color{30, 35, 50, 255}   // Dark purple
MENU_GRID_SPEED :: f32(10.0)                            // Pixels per second for diagonal movement

UI_INPUT_WIDTH :: 80
UI_INPUT_HEIGHT :: 24

UI_SEGMENTS :: 8
UI_ROUNDNESS :: 0.05
UI_SHADOW_OFFSET :: 4
UI_SHADOW_COLOR :: raylib.Color{0, 0, 0, 30}

UI_PANEL_HERO_SIZE :: 32
UI_PANEL_TITLE_SIZE :: 22
UI_PANEL_LABEL_SIZE :: 18
UI_PANEL_TEXT_SIZE :: 14
UI_PANEL_WIDTH :: 200
UI_PANEL_HEIGHT :: 295
UI_PANEL_MARGIN :: 10
UI_PANEL_Y_POSITION :: 150
UI_PANEL_TITLE_COLOR :: raylib.GRAY 
UI_PANEL_LABEL_COLOR :: raylib.DARKGRAY 
UI_PANEL_TEXT_COLOR :: raylib.BLACK 
UI_PANEL_COLOR :: raylib.RAYWHITE

// Screen-edge margins for panels
UI_MARGIN_X :: 10
UI_MARGIN_Y :: 8

// Screen-edge margins for tooltips
TOOLTIP_MARGIN_X :: 6
TOOLTIP_MARGIN_Y :: 4

// Tooltip Constants
UI_TOOLTIP_FONT_SIZE   :: 12
UI_TOOLTIP_PADDING_H   :: 8    // Padding horizontal interior
UI_TOOLTIP_PADDING_V   :: 5    // Padding vertical interior
UI_TOOLTIP_OFFSET      :: 8    // Distancia fija por encima del área trigger
UI_TOOLTIP_SEGMENTS    :: f32(8)
UI_TOOLTIP_ROUNDNESS   :: f32(0.3)
UI_TOOLTIP_SHADOW_OFF  :: f32(4)
UI_TOOLTIP_BG_COLOR    :: raylib.Color{ 28,  28,  32, 225}
UI_TOOLTIP_TEXT_COLOR  :: raylib.Color{230, 230, 230, 255}
UI_TOOLTIP_SHADOW_COLOR :: raylib.Color{  0,   0,   0,  70}

// Toast System Constants
UI_TOAST_FONT_SIZE :: 16
UI_TOAST_PADDING :: 12
UI_TOAST_SPACING :: 8
UI_TOAST_MARGIN_TOP :: 80  // Space from top to avoid UI overlap
UI_TOAST_SHADOW_OFFSET :: 2
UI_TOAST_ROUNDNESS :: 0.3

// Toast Colors
UI_TOAST_SUCCESS_COLOR :: raylib.Color{50, 200, 50, 240}      // Green
UI_TOAST_SUCCESS_TEXT_COLOR :: raylib.Color{255, 255, 255, 255}
UI_TOAST_INFO_COLOR :: raylib.Color{50, 150, 200, 240}       // Blue
UI_TOAST_INFO_TEXT_COLOR :: raylib.Color{255, 255, 255, 255}
UI_TOAST_WARNING_COLOR :: raylib.Color{200, 150, 50, 240}    // Orange
UI_TOAST_WARNING_TEXT_COLOR :: raylib.Color{255, 255, 255, 255}
UI_TOAST_ERROR_COLOR :: raylib.Color{200, 50, 50, 240}       // Red
UI_TOAST_ERROR_TEXT_COLOR :: raylib.Color{255, 255, 255, 255}

UI_RETICLE_COLOR :: raylib.Color{255, 255, 255, 255} // Selected cell reticle color (white with 60% opacity)


// Zoom Constants
ZOOM_MIN :: 0.4
ZOOM_MAX :: 3.0
ZOOM_SPEED :: 0.1 // Zoom speed per wheel tick (reduced for smoother feel)
ZOOM_SMOOTH_SPEED :: 8.0 // Speed of zoom smoothing (lerp factor per second)

// Easing function for zoom (ease-in: slow start, fast end)
ease_zoom :: proc(t: f32) -> f32 {
	// Ease-in cubic: t * t * t
	return t * t * t
}

// Tower Rendering Constants
TOWER_CELL_SIZE_RATIO :: 0.8 // Tower size as ratio of cell size
TOWER_BORDER_THICKNESS :: 3 // Border thickness in pixels
TOWER_BORDER_COLOR :: raylib.BLACK
TOWER_INNER_COLOR :: raylib.DARKGRAY // Center dot color
TOWER_INNER_SIZE_RATIO :: 0.25 // Inner dot size as ratio of tower size
TOWER_ROUNDED_CORNER :: 0.3 // Rectangle rounded corners (0.0 to 1.0)
TOWER_CORNER_SEGMENTS :: 8 // Number of segments for rounded corners

// Tower Color Constants
TOWER_BASE_COLOR :: raylib.Color{190, 190, 190, 255} // Base tower body color
TOWER_SECONDARY_COLOR :: raylib.Color{150, 150, 150, 255} // Secondary/accent color
TOWER_CANNON_COLOR :: raylib.Color{70, 70, 80, 255} // Cannon barrel color
TOWER_BARREL_OUTLINE :: raylib.Color{40, 40, 50, 255} // Barrel outline color
TOWER_HIGHLIGHT_COLOR :: raylib.Color{230, 230, 230, 255} // Highlight/bright areas

// Tower-specific Colors (JS Style) - saturated for visibility
TOWER_BARREL :: raylib.Color{100, 140, 180, 255} // Tower barrel color - more saturated blue
TOWER_LASER_CORE :: raylib.Color{100, 200, 255, 255} // Laser center glow - brighter cyan
TOWER_LASER_BASE :: raylib.Color{80, 120, 160, 255} // Laser base - more saturated blue
TOWER_LASER_COLOR :: raylib.Color{255, 68, 68, 255}
TOWER_CANNON_BASE :: raylib.Color{90, 110, 140, 255} // Cannon base - more saturated blue-gray
TOWER_MISSILE_BASE :: raylib.Color{160, 100, 80, 255} // Missile base - more saturated brown-red
TOWER_MISSILE_POD :: raylib.Color{120, 80, 60, 255} // Missile pods - more saturated brown
TOWER_MISSILE_WARHEAD :: raylib.Color{255, 60, 60, 255} // Missile warhead - bright red
TOWER_SHADOW :: raylib.Color{0, 0, 0, 30} // Shadow color - slightly darker
TOWER_ARCHER_WOOD :: raylib.Color{180, 110, 50, 255} // Archer bow wood - more saturated orange-brown
TOWER_ARCHER_STRING :: raylib.Color{220, 220, 220, 255} // Archer bow string
TOWER_RANGE_OUTLINE :: raylib.Color{255, 255, 255, 60} // Tower range area outline (semi-transparent white)
TOWER_RANGE_PREVIEW :: raylib.Color{255, 255, 255, 30} // Tower range preview fill (transparent white)

// Tower Component Size Constants
TOWER_BARREL_WIDTH_RATIO :: 0.25 // Barrel width as ratio of tower size
TOWER_BARREL_LENGTH_RATIO :: 0.6 // Barrel length as ratio of tower size
TOWER_HATCH_RADIUS_RATIO :: 0.15 // Hatch/circle size ratio

// Enemy Speed Constants (cells per second, scaled by GRID_SPEED_SCALE)
ENEMY_SPEED_BOSS    :: 0.4  // Slow bosses
ENEMY_SPEED_FLYING  :: 1.3  // Flying enemies
ENEMY_SPEED_BLUE    :: 1.1  // Medium blue enemies
ENEMY_SPEED_GREEN   :: 1.8  // Fast green enemies
ENEMY_SPEED_DEFAULT :: 1.0  // Normal enemies
ENEMY_SPEED_BONUS   :: 1.5  // Bonus enemies (fast but not green-tier)

// Enemy Size Constants (as ratio of cell size)
ENEMY_SIZE_BOSS    :: 0.32  // Boss enemies (large)
ENEMY_SIZE_FLYING  :: 0.20  // Flying enemies (small)
ENEMY_SIZE_BLUE    :: 0.24  // Blue enemies (medium)
ENEMY_SIZE_GREEN   :: 0.16  // Green enemies (tiny)
ENEMY_SIZE_DEFAULT :: 0.24  // Normal enemies (medium)
ENEMY_SIZE_BONUS   :: 0.28  // Bonus enemies (slightly bigger)

// Enemy Health Multiplier Constants
ENEMY_HEALTH_BOSS    :: 10.0  // Boss enemies (very tanky)
ENEMY_HEALTH_FLYING  ::  0.6  // Flying enemies (fragile)
ENEMY_HEALTH_BLUE    ::  1.2  // Blue enemies (medium)
ENEMY_HEALTH_GREEN   ::  0.5  // Green enemies (tiny)
ENEMY_HEALTH_DEFAULT ::  0.9  // Normal enemies
ENEMY_HEALTH_BONUS   ::  2.0  // Bonus enemies (tough — all abilities combined)

// Bonus wave constants
BONUS_WAVE_CHANCE       :: f32(0.25)  // 25% chance of a bonus wave on any non-boss wave
BONUS_WAVE_ENEMY_COUNT  :: i32(5)     // Enemies per bonus wave
ENEMY_REWARD_BONUS      :: i32(25)    // Extra gold granted on bonus enemy kill
BOSS_WAVE_INTERVAL      :: i32(10)    // Boss appears every N waves

ENEMY_STROKE_WIDTH :: 3
ENEMY_SHADOW_COLOR :: raylib.Color{0, 0, 0, 20}

PATH_WIDTH_RATIO :: 0.4

// Obstacle barrier constants
OBSTACLE_BARRIER_THICKNESS     :: f32(0.16)  // fracción de cs para la dimensión estrecha
OBSTACLE_BARRIER_LENGTH        :: f32(0.86)  // fracción de cs para la dimensión larga
OBSTACLE_BARRIER_ROUNDNESS     :: f32(0.35)
OBSTACLE_BARRIER_SHADOW_OFFSET :: f32(3)
OBSTACLE_BARRIER_BORDER_THICK  :: f32(1.5)
COLOR_OBSTACLE_FILL            :: raylib.Color{145, 150, 158, 255}  // gris azulado
COLOR_OBSTACLE_BORDER          :: raylib.Color{ 85,  90,  98, 255}  // gris oscuro
COLOR_OBSTACLE_SHADOW          :: raylib.Color{  0,   0,   0,  55}

// Map Browser Panel Constants
UI_MAP_BROWSER_WIDTH              :: 420   // Panel width in pixels
UI_MAP_BROWSER_HEIGHT             :: 480   // Panel height in pixels
UI_MAP_BROWSER_SHADOW_OFFSET      :: 4     // Drop-shadow offset (larger than button shadow)
UI_MAP_BROWSER_TITLE_Y_OFFSET     :: 14   // Y offset from panel top to title text
UI_MAP_BROWSER_SEPARATOR_Y        :: 38   // Y offset from panel top to horizontal separator
UI_MAP_BROWSER_HEADER_HEIGHT      :: 46   // Space reserved for title + separator (list starts here)
UI_MAP_BROWSER_FOOTER_HEIGHT      :: 48   // Space reserved at the bottom for the Close button
UI_MAP_BROWSER_ITEM_HEIGHT        :: 36   // Height of each map list item
UI_MAP_BROWSER_ITEM_SIDE_PADDING  :: 8    // Horizontal inner padding for the item rect
UI_MAP_BROWSER_ITEM_VERT_GAP      :: 4    // Vertical gap between items (2px top + 2px bottom)
UI_MAP_BROWSER_ITEM_TEXT_INDENT   :: 10   // Left text indent inside item rect
UI_MAP_BROWSER_ITEM_FONT_SIZE     :: 13   // Font size for list items
UI_MAP_BROWSER_SCROLL_FONT_SIZE   :: 11   // Font size for scroll indicator text
UI_MAP_BROWSER_CLOSE_HEIGHT       :: 28   // Close-button height (slightly taller than standard)
UI_MAP_BROWSER_CLOSE_BTN_MARGIN   :: 10   // Margin from panel bottom to Close button
UI_MAP_BROWSER_TITLE_FONT_SIZE    :: 16   // Font size for panel title (same as UI_BUTTON_FONT_SIZE)

// Map Browser Colors
UI_MAP_BROWSER_OVERLAY_COLOR   :: raylib.Color{0,   0,   0,   140} // Semi-transparent screen dimmer
UI_MAP_BROWSER_SHADOW_COLOR    :: raylib.Color{0,   0,   0,   80}  // Panel drop shadow
UI_MAP_BROWSER_SEPARATOR_COLOR :: raylib.Color{180, 180, 180, 200} // Divider line under title
UI_MAP_BROWSER_MUTED_COLOR     :: raylib.Color{130, 130, 130, 255} // "No maps found" / scroll text
UI_MAP_BROWSER_LOADED_COLOR    :: raylib.Color{30,  120, 30,  255} // Currently-loaded map highlight

// Undo / Redo
EDITOR_MAX_HISTORY :: 50   // Maximum number of map snapshots to keep in the undo stack

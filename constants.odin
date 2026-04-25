package towerdef

import "vendor:raylib"

// Game State
game_state :: enum {
	MENU,
	PLAYING,
	PAUSED,
	EDITOR,
	GAME_OVER,
}

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
tower_type :: enum {
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
	type: tower_type,
	range: f32,
	damage: f32,
	cooldown: f32,
	aoe: f32,
	cost: i32,
	color: raylib.Color,
}

// Tower specs lookup
TOWER_SPECS := [Tile]Tower_Spec{
	.TOWER_ARCHER = {
		type = .ARCHER,
		range = 2.5,
		damage = 2.5,
		cooldown = 0.2,
		aoe = 0,
		cost = 20,
		color = raylib.BROWN,
	},
	.TOWER_CANNON = {
		type = .CANNON,
		range = 3.0,
		damage = 4.0,
		cooldown = 1.0,
		aoe = 1.0,
		cost = 40,
		color = raylib.DARKGRAY,
	},
	.TOWER_SNIPER = {
		type = .SNIPER,
		range = 5.0,
		damage = 8.0,
		cooldown = 1.5,
		aoe = 0,
		cost = 60,
		color = raylib.GREEN,
	},
	.TOWER_MISSILE = {
		type = .MISSILE,
		range = 4.0,
		damage = 3.5,
		cooldown = 0.9,
		aoe = 1.5,
		cost = 70,
		color = raylib.ORANGE,
	},
	.TOWER_LASER = {
		type = .LASER,
		range = 3.5,
		damage = 5.0,
		cooldown = 1.2,
		aoe = 0,
		cost = 50,
		color = raylib.RED,
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
		path = raylib.Color{210, 180, 140, 255},
	},
	.FOREST = {
		bg = raylib.Color{150, 200, 150, 255},
		bg_grid = raylib.Color{130, 180, 130, 255},
		path = raylib.Color{160, 140, 100, 255},
	},
	.DESERT = {
		bg = raylib.Color{240, 220, 170, 255},
		bg_grid = raylib.Color{230, 210, 160, 255},
		path = raylib.Color{220, 180, 130, 255},
	},
	.MOUNTAIN = {
		bg = raylib.Color{180, 190, 200, 255},
		bg_grid = raylib.Color{160, 170, 180, 255},
		path = raylib.Color{140, 140, 140, 255},
	},
}

// Game constants
GRID_SIZE :: 20
CELL_SIZE :: 32
DEFAULT_MONEY :: 100
DEFAULT_HEALTH :: 20
MAX_FPS :: 60

// Upgrade costs
UPGRADE_BASE_COST :: 50
UPGRADE_COST_PER_LEVEL :: 25

// Sell refund percentage
SELL_REFUND :: 0.7

// Critical hit constants
CRIT_BASE_CHANCE :: 0.05
CRIT_PER_LEVEL :: 0.03
CRIT_DAMAGE_MULTIPLIER :: 2.0

// Laser constants
LASER_FIRING_DURATION :: 1.0
LASER_ACCUMULATION_TIME :: 0.1
LASER_COOLDOWN_REDUCTION_PER_LEVEL :: 0.15
LASER_DAMAGE_MULTIPLIER_PER_LEVEL :: 0.5

// Colors
COLOR_ENEMY :: raylib.Color{220, 60, 60, 255}
COLOR_ENEMY_GREEN :: raylib.Color{60, 180, 60, 255}
COLOR_ENEMY_BLUE :: raylib.Color{60, 100, 220, 255}
COLOR_ENEMY_BOSS :: raylib.Color{220, 200, 60, 255}
COLOR_ENEMY_FLYING :: raylib.Color{180, 120, 220, 255}

COLOR_GRID_LINE :: raylib.Color{150, 150, 150, 100}
COLOR_PATH :: raylib.Color{210, 180, 140, 255}
COLOR_SPAWN :: raylib.Color{100, 200, 100, 255}
COLOR_GOAL :: raylib.Color{200, 100, 100, 255}
COLOR_OBSTACLE :: raylib.Color{120, 100, 80, 255}
COLOR_TREE_TRUNK :: raylib.Color{101, 67, 33, 255}
COLOR_TREE_LEAVES :: raylib.Color{34, 139, 34, 255}
COLOR_BLOCK :: raylib.Color{128, 128, 128, 255}
COLOR_LASER_BEAM :: raylib.Color{255, 68, 68, 255}

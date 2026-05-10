package entities

import "../constants"

// Game_State must be defined before App_State
// It's now defined in constants package as Game_State

// Simulation state
Simulation :: struct {
	// Entities
	towers: [dynamic]Tower,
	enemies: [dynamic]Enemy,
	projectiles: [dynamic]Projectile,
	explosions: [dynamic]Explosion,
	damage_numbers: [dynamic]Damage_Number,
	laser_beams: [dynamic]Laser_Beam,
	
	// Spawns
	spawns: [dynamic]Spawn_Point,
	
	// Game state
	money: i32,
	health: i32,
	wave_number: i32,
	
	// Control
	speed: f32,
	paused: bool,
	started: bool,
	
	// Tower building during gameplay
	selected_build_tower: constants.Tile,
	
	// Wave management
	enemies_to_spawn: i32,
	enemies_spawned: i32,
	wave_time: f32,
	next_spawn_delay: f32,
	
	// Wave type flags
	is_wave_boss: bool,
	is_wave_green: bool,
	is_wave_flying: bool,
	is_wave_blue: bool,
	
	// Stats
	enemies_killed: i32,
	money_earned: i32,
	towers_built: i32,
	upgrades_bought: i32,
	play_time: f32,
	
	// Time-series for graph
	graph_samples: [dynamic]Graph_Sample,
	wave_marks: [dynamic]Wave_Mark,
	_sample_timer: f32,
}

// Data point sampled periodically for the game-over graph
Graph_Sample :: struct {
	time: f32,
	money: i32,
	health: i32,
}

// Marks when a wave started, with its type for color/shape
Wave_Mark :: struct {
	time: f32,
	wave: i32,
	is_boss: bool,
	is_green: bool,
	is_blue: bool,
	is_flying: bool,
}

// Editor state
Editor :: struct {
	// Map
	game_map: Map,
	
	// Current tool
	current_tool: constants.Tile,
	show_grid: bool,
	
	// Editor settings
	current_biome: constants.Biome,
	
	// Debug visualization
	show_paths: bool,
	
	// Load map filename input
	load_map_filename: [64]u8,
	load_map_active: bool,
}

// Settings
Settings :: struct {
	grid_size: i32,
	cell_size: i32,
	show_grid: bool,
	show_fps: bool,
	language: constants.Language,
	
	// Audio
	master_volume: f32,
	
	// Display
	fullscreen: bool,
	vsync: bool,
	antialiasing: i32,
	
	// Gameplay
	show_damage_numbers: bool,
	show_tower_range: bool,
	auto_start_wave: bool,
}

// Spawn_Point and Path_Node are defined in map.odin and enemy.odin

// Global application state
App_State :: struct {
	// State
	state: constants.Game_State,
	previous_state: constants.Game_State,
	
	// Sub-systems
	sim: Simulation,
	editor: Editor,
	settings: Settings,
	
	// Camera/View
	camera_offset_x: i32,
	camera_offset_y: i32,
	target_camera_offset_x: i32,  // For smooth zoom animation
	target_camera_offset_y: i32,  // For smooth zoom animation
	zoom: f32,
	target_zoom: f32,  // For smooth zoom interpolation
	
	// Input state
	mouse_x: i32,
	mouse_y: i32,
	selected_tower: ^Tower,
	
	// Selected cell (for reticle display in editor and simulation)
	selected_cell: struct {
		row: i32,
		col: i32,
		valid: bool,  // true if mouse is over a valid grid cell
	},
	
	// Time
	last_frame_time: f64,
	delta_time: f32,
	
	// Quit flag
	should_quit: bool,
}

// Set game state
app_set_state :: proc(app: ^App_State, new_state: constants.Game_State) {
	app.previous_state = app.state
	app.state = new_state
}

// Take damage
app_take_damage :: proc(app: ^App_State, damage: i32) {
	app.sim.health -= damage
	if app.sim.health <= 0 {
		app.state = .GAME_OVER
	}
}

// Add money
app_add_money :: proc(app: ^App_State, amount: i32) {
	app.sim.money += amount
}

package game

import "../constants"
import "../entities"

// Simulation state
Simulation :: struct {
	// Entities
	towers: [dynamic]entities.Tower,
	enemies: [dynamic]entities.Enemy,
	projectiles: [dynamic]entities.Projectile,
	explosions: [dynamic]entities.Explosion,
	damage_numbers: [dynamic]entities.Damage_Number,
	laser_beams: [dynamic]entities.Laser_Beam,
	
	// Spawns
	spawns: [dynamic]entities.Spawn_Point,
	
	// Game state
	money: i32,
	health: i32,
	wave_number: i32,
	
	// Control
	speed: f32,
	paused: bool,
	started: bool,
	
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
}

// Editor state
Editor :: struct {
	// Map
	map: entities.Map,
	
	// Current tool
	current_tool: constants.Tile,
	show_grid: bool,
	
	// Editor settings
	current_biome: constants.Biome,
}

// Settings
Settings :: struct {
	grid_size: i32,
	cell_size: i32,
	show_grid: bool,
	show_fps: bool,
}

// Global application state
App_State :: struct {
	// State
	state: constants.game_state,
	previous_state: constants.game_state,
	
	// Sub-systems
	sim: Simulation,
	editor: Editor,
	settings: Settings,
	
	// Camera/View
	camera_offset_x: i32,
	camera_offset_y: i32,
	zoom: f32,
	
	// Input state
	mouse_x: i32,
	mouse_y: i32,
	selected_tower: ^entities.Tower,
	
	// Time
	last_frame_time: f64,
	delta_time: f32,
}

// Global app instance
app: App_State

// Initialize application
app_init :: proc() {
	app = App_State{
		state = .MENU,
		previous_state = .MENU,
		settings = Settings{
			grid_size = constants.GRID_SIZE,
			cell_size = constants.CELL_SIZE,
			show_grid = true,
			show_fps = true,
		},
		editor = Editor{
			map = entities.map_init(),
			current_tool = .EMPTY,
			show_grid = true,
			current_biome = .PLAIN,
		},
		zoom = 1.0,
	}
	
	simulation_reset()
}

// Destroy application and free resources
app_destroy :: proc() {
	entities.map_destroy(&app.editor.map)
	simulation_cleanup()
}

// Set game state
app_set_state :: proc(new_state: constants.game_state) {
	app.previous_state = app.state
	app.state = new_state
}

// Reset simulation
simulation_reset :: proc() {
	// Clear old data
	simulation_cleanup()
	
	// Initialize new simulation
	app.sim = Simulation{
		towers = make([dynamic]entities.Tower),
		enemies = make([dynamic]entities.Enemy),
		projectiles = make([dynamic]entities.Projectile),
		explosions = make([dynamic]entities.Explosion),
		damage_numbers = make([dynamic]entities.Damage_Number),
		laser_beams = make([dynamic]entities.Laser_Beam),
		spawns = make([dynamic]entities.Spawn_Point),
		money = constants.DEFAULT_MONEY,
		health = constants.DEFAULT_HEALTH,
		wave_number = 1,
		speed = 1.0,
		paused = false,
		started = false,
		enemies_to_spawn = 0,
		enemies_spawned = 0,
		wave_time = 0,
		next_spawn_delay = 0,
		is_wave_boss = false,
		is_wave_green = false,
		is_wave_flying = false,
		is_wave_blue = false,
	}
}

// Cleanup simulation resources
simulation_cleanup :: proc() {
	// Free enemies
	for &e in app.sim.enemies {
		entities.enemy_destroy(&e)
	}
	
	delete(app.sim.towers)
	delete(app.sim.enemies)
	delete(app.sim.projectiles)
	delete(app.sim.explosions)
	delete(app.sim.damage_numbers)
	delete(app.sim.laser_beams)
	delete(app.sim.spawns)
}

// Initialize simulation from editor map
simulation_init_from_editor :: proc() -> bool {
	simulation_reset()
	
	// Copy towers from editor grid
	for row in 0..<constants.GRID_SIZE {
		for col in 0..<constants.GRID_SIZE {
			tile := app.editor.map.grid[row][col]
			
			switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
				tower := entities.tower_init(tile, row, col)
				append(&app.sim.towers, tower)
				
			case .SPAWN:
				// Find path from spawn to goal
				goal_row, goal_col, found := entities.map_find_goal(&app.editor.map)
				if !found {
					return false
				}
				
				// Create spawn point
				spawn := entities.Spawn_Point{
					r = row,
					c = col,
					enemies_to_spawn = 0,
					enemies_spawned = 0,
					wave_time = 0,
					next_spawn_delay = 0,
				}
				
				// Calculate path (simplified - just store spawn/goal)
				// Full pathfinding would be implemented in simulation
				append(&spawn.path, entities.Path_Node{x = col, y = row})
				
				append(&app.sim.spawns, spawn)
			}
		}
	}
	
	return len(app.sim.spawns) > 0
}

// Add money
app_add_money :: proc(amount: i32) {
	app.sim.money += amount
}

// Spend money
app_spend_money :: proc(amount: i32) -> bool {
	if app.sim.money >= amount {
		app.sim.money -= amount
		return true
	}
	return false
}

// Take damage
app_take_damage :: proc(damage: i32) {
	app.sim.health -= damage
	if app.sim.health <= 0 {
		app.state = .GAME_OVER
	}
}

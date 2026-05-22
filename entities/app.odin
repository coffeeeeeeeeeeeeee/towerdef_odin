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
	ice_pulses:  [dynamic]Ice_Pulse,

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
	is_wave_boss:  bool,
	is_wave_green: bool,
	is_wave_flying: bool,
	is_wave_blue:  bool,
	is_wave_split: bool,
	is_wave_bonus: bool,

	// Pre-rolled bonus status for the next 3 upcoming waves (index 0 = wave+1).
	// Shifts forward each time start_next_wave is called.
	lookahead_bonus: [3]bool,
	
	// Deck builder
	deck:    [dynamic]Card,
	hand:    [dynamic]Card,
	discard: [dynamic]Card,
	hand_size:         i32,  // cartas robadas por refresco (empieza en DECK_HAND_SIZE)
	selected_card_idx: int,  // índice en hand, -1 = ninguna carta seleccionada

	// Selección de carta (cada DECK_SELECTION_INTERVAL oleadas)
	card_selection_active:  bool,
	card_selection_choices: [3]Card,
	card_selection_bought:  [3]bool, // slots ya comprados en esta visita al shop

	// Stacks permanentes de relictos (se acumulan toda la partida)
	interest_stacks:     i32,  // +INTEREST_RATE de interés por oleada × stacks
	steal_stacks:        i32,  // roba steal_stacks cartas adicionales al inicio de oleada
	weaken_stacks:       i32,  // enemigos tienen -WEAKEN_HP_REDUCTION × stacks de HP
	auto_stacks:         i32,  // auto-upgradea auto_stacks torres cada AUTO_UPGRADE_INTERVAL
	auto_upgrade_timer:  f32,  // tiempo restante hasta el próximo tick de auto-upgrade
	interest_multiplier: f32,  // legacy, ya no se usa — mantener para no romper init

	// DIVIDEND: stacks; wave_start_money = snapshot al inicio de oleada
	dividend_stacks:    i32,
	wave_start_money:   i32,

	// STEAL: última oleada en la que ya se robaron cartas (evita disparos múltiples entre oleadas)
	steal_last_wave: i32,

	// BLOODLUST: micro-bonus de daño por kill (multiplicador acumulado durante la partida)
	bloodlust_stacks: i32,
	bloodlust_mult:   f32,  // empieza en 1.0; cada kill += BLOODLUST_BONUS_PER_KILL × stacks

	// FLAWLESS: bono de oro por oleada sin perder vidas
	flawless_stacks:    i32,
	wave_start_health:  i32,  // salud al inicio de la oleada para comparar al final

	// FORMATION: bonus de daño para torres del mismo tipo en línea de 3+
	formation_stacks: i32,

	// FROZEN_AMP: enemigos ralentizados reciben daño amplificado
	frozen_amp_stacks: i32,

	// VETERAN: cartas de torre en el shop aparecen pre-niveladas según stacks
	veteran_stacks: i32,

	// LOOT: chance de obtener carta aleatoria al matar un enemigo
	loot_stacks: i32,

	// Flash animation timers — cuentan regresivo desde RELIC_FLASH_DURATION hasta 0
	relic_flash_timers: [Card_Kind]f32,

	// Deterministic RNG — seed guardado para reproducibilidad
	seed: u64,

	// Inter-wave delay timer (counts down from INTER_WAVE_DELAY before auto-starting next wave)
	inter_wave_timer: f32,

	// Victory flag (set when wave MAX_WAVE is cleared with health > 0)
	is_victory: bool,

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
	time:     f32,
	wave:     i32,
	is_boss:  bool,
	is_green: bool,
	is_blue:  bool,
	is_flying: bool,
	is_split: bool,
	is_bonus: bool,
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

	// Map save/load state
	current_map_name: string,         // Nombre del mapa cargado/guardado
	show_map_browser: bool,           // Si el browser de mapas está abierto
	map_browser_files: [dynamic]string, // Lista de archivos .map disponibles
	map_browser_scroll: i32,          // Scroll offset del browser

	// Undo / Redo
	undo_stack: [dynamic]Map_Snapshot, // Snapshots anteriores (el último es el más reciente)
	redo_stack: [dynamic]Map_Snapshot, // Snapshots para rehacer
	is_painting: bool,                 // True mientras el botón izquierdo está presionado (para capturar solo al inicio del trazo)
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
	ui_volume:     f32, // inicializar en 1.0
	sfx_volume:    f32, // inicializar en 1.0
	
	// Display
	fullscreen: bool,
	vsync: bool,
	antialiasing: i32,
	window_maximized: bool,
	
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
	
	// UI System
	toasts: [dynamic]Toast,
	
	// Camera/View
	camera_offset_x: i32,
	camera_offset_y: i32,
	target_camera_offset_x: i32,  // For smooth zoom animation
	target_camera_offset_y: i32,  // For smooth zoom interpolation
	zoom: f32,
	target_zoom: f32,  // For smooth zoom interpolation
	
	// Input state
	mouse_x: i32,
	mouse_y: i32,
	// Selected tower stored as grid position to avoid dangling pointers
	// when app.sim.towers reallocates. Use app_get_selected_tower() to get ^Tower.
	// -1 means no tower selected.
	selected_tower_r: i32,
	selected_tower_c: i32,
	selected_obstacle: struct {
		row: i32,
		col: i32,
		valid: bool,
	},
	
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

// Get selected tower by searching sim.towers for the stored (r, c).
// Returns nil if no tower is selected or the position no longer has a tower.
app_get_selected_tower :: proc(app: ^App_State) -> ^Tower {
	if app.selected_tower_r < 0 {
		return nil
	}
	for &t in app.sim.towers {
		if t.r == app.selected_tower_r && t.c == app.selected_tower_c {
			return &t
		}
	}
	return nil
}

// Deselect the currently selected tower.
app_deselect_tower :: proc(app: ^App_State) {
	app.selected_tower_r = -1
	app.selected_tower_c = -1
}

// Select tower at grid position (r, c).
app_select_tower :: proc(app: ^App_State, r, c: i32) {
	app.selected_tower_r = r
	app.selected_tower_c = c
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
		app_set_state(app, .GAME_OVER)
	}
}

// Add money
app_add_money :: proc(app: ^App_State, amount: i32) {
	app.sim.money += amount
}
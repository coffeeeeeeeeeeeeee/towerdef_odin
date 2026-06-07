package entities

import "../constants"
import "vendor:raylib"

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
	
	// Wave type flags (combinable Enemy_Flags — same flags as individual enemies)
	wave_flags: Enemy_Flags,

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
	card_selection_choices: [constants.MAX_SHOP_SLOTS]Card,
	card_selection_bought:  [constants.MAX_SHOP_SLOTS]bool, // slots ya comprados en esta visita al shop
	card_selection_locked:  [constants.MAX_SHOP_SLOTS]bool, // slots con lock — sobreviven al reroll
	shop_slot_count:        i32,                            // slots activos en el shop actual (depende del bioma)
	rerolls_this_shop:      i32,                            // contador para el costo progresivo de reroll
	shops_since_unique:     i32,                            // pity counter para forzar UNIQUE
	skip_streak_count:      i32,                            // skips consecutivos sin comprar (para bonus de oro)
	shop_purchases_this_visit: i32,                         // compras en la visita actual (para skip bonus)

	// Stacks permanentes de relictos — indexado por Card_Kind (ver RELIC_SPECS en card.odin).
	// Se inicializa a cero automáticamente; sim.relic_stacks[.INTEREST_BOOST], etc.
	relic_stacks:        [Card_Kind]i32,
	auto_upgrade_timer:  f32,  // tiempo restante hasta el próximo tick de auto-upgrade

	// Auxiliares por relicto (no son stacks, son estado derivado)
	wave_start_money:   i32,  // snapshot de dinero al inicio de oleada (DIVIDEND)
	steal_last_wave:    i32,  // última oleada en que STEAL ya robó (evita doble disparo)
	bloodlust_mult:     f32,  // multiplicador de daño acumulado por kills (BLOODLUST)
	wave_start_health:  i32,  // salud al inicio de oleada (FLAWLESS)

	// Flash animation timers — cuentan regresivo desde RELIC_FLASH_DURATION hasta 0
	relic_flash_timers: [Card_Kind]f32,

	// Deterministic RNG — seed guardado para reproducibilidad
	seed: u64,

	// Inter-wave delay timer (counts down from INTER_WAVE_DELAY before auto-starting next wave)
	inter_wave_timer: f32,

	// Victory flag (set when wave MAX_WAVE is cleared with health > 0)
	is_victory: bool,

	// Airdrop events
	airdrops:           [dynamic]Airdrop,
	airdrop_timer:      f32,  // cuenta regresiva hasta el próximo spawn

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
	time:  f32,
	wave:  i32,
	flags: Enemy_Flags,
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
	current_map_name: string,              // Nombre del mapa cargado/guardado
	show_map_browser: bool,               // Si el browser de mapas está abierto
	map_browser_entries:       [dynamic]Map_File_Entry, // Lista de archivos .map disponibles
	map_browser_scroll:        i32,       // Scroll offset del browser
	map_browser_play_mode:     bool,      // True cuando el browser fue abierto desde el menú Play
	map_browser_selected:      i32,       // Índice seleccionado en la lista (-1 = ninguno)
	map_browser_preview:           Map,             // Mapa cargado para vista previa
	map_browser_preview_valid:     bool,            // True cuando hay una vista previa válida
	map_browser_preview_tex:       raylib.RenderTexture2D, // Textura del preview renderizado
	map_browser_preview_tex_valid: bool,            // True cuando la textura es válida
	map_browser_renaming:          bool,            // True mientras el modo rename está activo
	map_browser_rename_input:      Input_State,     // Estado del campo de texto para renombrar

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
	auto_skip_shop: bool,
}

// Generic Sí/No confirmation modal — `action` tells the caller what to do on confirm.
Modal_Action :: enum {
	NONE,
	NEW_GAME,
	RESTART_RUN,
	EXIT_GAME,
}

Confirm_Modal :: struct {
	active: bool,
	text:   string,
	action: Modal_Action,
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

	// Developer mode: god mode toggle (no damage taken)
	dev_god_mode: bool,

	// Meta-progression (persisted to savegame.bin)
	meta: Meta_State,

	// Cristales earned in the last run — set when transitioning to .RUN_COMPLETE
	run_cristales: i32,

	// Tooltip layer — written during UI render, drawn last so it's always on top.
	// Only one tooltip can be visible per frame; first writer wins.
	pending_tooltip: Pending_Tooltip,

	// Ambient bird flock animation
	bird_flock: Bird_Flock,

	// Generic Sí/No confirmation modal (e.g. confirmar nueva campaña)
	confirm_modal: Confirm_Modal,
}


// Airdrop event — un avión cruza el mapa y suelta una caja con loot
Airdrop_Phase :: enum { PLANE_FLYING, BOX_FALLING, BOX_LANDED }

Airdrop :: struct {
	// Avión — posición y dirección en world space
	plane_x:     f32,
	plane_y:     f32,
	plane_dir_x: f32,   // dirección normalizada X
	plane_dir_y: f32,   // dirección normalizada Y

	// Tile destino (world center precalculado)
	target_row:  i32,
	target_col:  i32,
	target_wx:   f32,   // world x del centro del tile
	target_wy:   f32,   // world y del centro del tile

	// Estela jet (ring buffer de posiciones world)
	trail:       [24]raylib.Vector2,
	trail_len:   i32,
	trail_head:  i32,
	trail_timer: f32,   // acumula dt para samplear cada AIRDROP_TRAIL_INTERVAL

	// Paracaídas / caja
	phase:       Airdrop_Phase,
	chute_t:     f32,   // 1.0 = recién soltado, 0.0 = caja aparece
	dropped:     bool,

	// Ping convergente (círculo que se encoge hasta el centro de la caja)
	ping_timer:  f32,   // cuenta regresiva hasta el próximo ping
	ping_t:      f32,   // 1.0 = inicio del anillo grande, 0.0 = colapsó en centro; -1 = inactivo
}

// Bird flock ambient animation
Bird :: struct {
	pos:    raylib.Vector2,  // Current screen position
	offset: raylib.Vector2,  // Offset from flock center
	phase:  f32,             // Wing flap phase offset
}

Bird_Flock :: struct {
	active:      bool,
	spawn_timer: f32,        // Countdown to next flock spawn
	anim_time:   f32,        // Accumulated time for wing animation
	birds:       [12]Bird,
	bird_count:  i32,
	velocity:    raylib.Vector2,
}

Tooltip_Kind :: enum { NONE, LABEL, CARD }

Pending_Tooltip :: struct {
	kind:    Tooltip_Kind,
	trigger: raylib.Rectangle,
	label:   string,         // used when kind == .LABEL
	card:    Card,           // used when kind == .CARD
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

// Take damage — triggers RUN_COMPLETE (defeat) when health reaches zero.
app_take_damage :: proc(app: ^App_State, damage: i32) {
	if app.dev_god_mode { return }
	app.sim.health -= damage
	if app.sim.health <= 0 {
		app.sim.health = 0
		app_finish_run(app, false)
	}
}

// Finalize a run (victory or defeat), tally cristales, persist meta, then transition to RUN_COMPLETE.
app_finish_run :: proc(app: ^App_State, victory: bool) {
	app.sim.is_victory = victory
	lives := app.sim.health if victory else 0
	cristales := meta_calc_cristales(app.sim.enemies_killed, lives, app.sim.wave_number)
	app.run_cristales   = cristales
	app.meta.cristales  += cristales
	app.meta.total_runs += 1
	meta_save(&app.meta)
	clear(&app.toasts)
	app_set_state(app, .RUN_COMPLETE)
}

// Add money
app_add_money :: proc(app: ^App_State, amount: i32) {
	app.sim.money += amount
}

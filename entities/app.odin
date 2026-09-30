package entities

import "../constants"
import "vendor:raylib"

// Game_State must be defined before App_State
// It's now defined in constants package as Game_State

// Simulation state
// ─────────────────────────────────────────────────────────────────────────────
// Sub-state de Simulation — agrupados por concern para no inflar el god struct.
// Los nombres dentro de cada substruct evitan repetir el prefijo (ej. sim.shop.active
// en lugar de sim.shop.card_selection_active).
// ─────────────────────────────────────────────────────────────────────────────

// Estado del shop intra-oleada (selección, locks, rerolls, skip racha).
Shop_State :: struct {
	active:               bool,                              // El overlay del shop está abierto
	choices:              [constants.MAX_SHOP_SLOTS]Card,    // Cartas en venta este shop
	bought:               [constants.MAX_SHOP_SLOTS]bool,    // Slots ya comprados en esta visita
	locked:               [constants.MAX_SHOP_SLOTS]bool,    // Slots con lock — sobreviven al reroll
	slot_count:           i32,                               // Slots activos (depende del bioma)
	rerolls_this_visit:   i32,                               // Para el costo progresivo de reroll
	shops_since_unique:   i32,                               // Pity counter para forzar UNIQUE
	skip_streak_count:    i32,                               // Skips consecutivos sin comprar
	purchases_this_visit: i32,                               // Compras en la visita actual (para skip bonus)
}

// Estado del deck builder — mazo, mano, descarte, hand size.
Card_State :: struct {
	deck:              [dynamic]Card,
	hand:              [dynamic]Card,
	discard:           [dynamic]Card,
	hand_size:         i32,  // cartas robadas por refresco (empieza en DECK_HAND_SIZE)
	selected_card_idx: int,  // índice en hand, -1 = ninguna carta seleccionada
}

// Glow particle effect (enemy spawn = white circles rise; goal reach = dark red circles fall)
Glow_Particle_Kind :: enum { SPAWN, GOAL_REACH }

Glow_Particle :: struct {
	grid_x, grid_y: f32,   // world position (grid coords, cell-centered)
	t:              f32,   // time alive [0..lifetime]
	lifetime:       f32,
	radius_start:   f32,   // ring radius at t=0 (fraction of cell_size)
	radius_end:     f32,   // ring radius at t=lifetime (fraction of cell_size)
	dy_start:       f32,   // vertical offset at t=0        (cell fractions, up = negative)
	dy_end:         f32,   // vertical offset at t=lifetime (cell fractions, up = negative)
	kind:           Glow_Particle_Kind,
}

Simulation :: struct {
	// Entities
	towers: [dynamic]Tower,
	enemies: [dynamic]Enemy,
	projectiles: [dynamic]Projectile,
	explosions: [dynamic]Explosion,
	damage_numbers: [dynamic]Damage_Number,
	hit_particles: [dynamic]Hit_Particle,
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

	// Pre-rolled sub-type flags (GREEN/FLYING/BLUE/SPLIT/ARMORED/INVISIBLE) for
	// the next 3 upcoming waves — mismo esquema de índices que lookahead_bonus.
	// Necesario para que la reliquia SCOUT pueda mostrar el tipo real de las
	// próximas oleadas ahora que el sub-tipo se sortea con RNG (antes era
	// puramente determinístico por wave_number, así que no hacía falta).
	lookahead_subtype: [3]Enemy_Flags,

	// Subsistemas (cohesión por concern)
	cards: Card_State,
	shop:  Shop_State,

	// Stacks permanentes de relictos — indexado por Card_Kind (ver RELIC_SPECS en card.odin).
	// Se inicializa a cero automáticamente; sim.relic_stacks[.INTEREST_BOOST], etc.
	relic_stacks:        [Card_Kind]i32,
	auto_upgrade_timer:  f32,  // tiempo restante hasta el próximo tick de auto-upgrade
	crane_kick_timer:    f32,  // tiempo restante hasta la próxima carga de Crane Kick

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

	// Victory flag (set when the run's last wave is cleared with health > 0 — ver campaign_max_waves)
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

	// Glow particle effects (spawn / goal reach)
	glow_particles: [dynamic]Glow_Particle,
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

// ─────────────────────────────────────────────────────────────────────────────
// Sub-state del editor — agrupados por concern para que cada subsistema (Map
// Browser, Campaign Editor) tenga su propio struct cohesivo.
// ─────────────────────────────────────────────────────────────────────────────

// Estado del Map Browser modal — listado + preview + rename.
Map_Browser_State :: struct {
	entries:           [dynamic]Map_File_Entry,      // Lista de archivos .map disponibles
	scroll:            i32,                          // Scroll offset
	play_mode:         bool,                         // True cuando se abrió desde el menú Play
	selected:          i32,                          // Índice seleccionado (-1 = ninguno)
	preview:           Map,                          // Mapa cargado para vista previa
	preview_valid:     bool,                         // True si hay preview cargada
	preview_tex:       raylib.RenderTexture2D,       // Textura del preview renderizado
	preview_tex_valid: bool,                         // True si la textura GPU es válida
	renaming:          bool,                         // True mientras el modo rename está activo
	rename_input:      Input_State,                  // Campo de texto del rename
}

// Estado del Campaign Editor (sólo DEVELOPER) — reutiliza el browser modal.
// Opera directamente sobre app.campaign (single source of truth).
Campaign_Editor_State :: struct {
	active:        bool,  // El browser muestra UI de campaña en vez de preview
	selected_node: i32,   // Nodo seleccionado en la lista (-1 = ninguno)
	scroll:        i32,   // Scroll de la lista de nodos
	dirty:         bool,  // Tiene cambios sin guardar
}

// Editor state
Editor :: struct {
	// Map
	game_map: Map,

	// Current tool
	current_tool: constants.Tile,

	// Editor settings
	current_biome: constants.Biome,

	// Load map filename input
	load_map_filename: [64]u8,
	load_map_active: bool,

	// Map save/load state
	current_map_name: string,    // Nombre del mapa cargado/guardado
	show_map_browser: bool,      // Si el browser de mapas está abierto
	browser:          Map_Browser_State,
	campaign_editor:  Campaign_Editor_State,

	// Edición del nombre editable del mapa (Map.display_name), independiente
	// del nombre de archivo — ver botón "Nombre" en el toolbar del editor.
	map_name_editing: bool,
	map_name_input:   Input_State,

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
	music_volume:  f32, // inicializar en 1.0
	
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
	RESET_META,   // Wipe progresión (cristales + unlocks + campaign), keep current state
	PAUSE_TO_MENU, // Salir al menú principal desde pausa — pierde el progreso del mapa actual
}

Confirm_Modal :: struct {
	active: bool,
	text:   string,
	action: Modal_Action,
}

// Spawn_Point and Path_Node are defined in map.odin and enemy.odin

// Transición de pantalla completa a negro entre un estado y otro — ver
// app_begin_state_fade/app_screen_fade_update/app_screen_fade_alpha.
Screen_Fade :: struct {
	active:        bool,
	elapsed:       f32,
	revealing:     bool,                 // false = oscureciendo a negro; true = revelando pending_state
	pending_state: constants.Game_State, // estado al que saltar apenas la pantalla está en negro total
}

// Global application state
App_State :: struct {
	// State
	state: constants.Game_State,
	previous_state: constants.Game_State,
	screen_fade: Screen_Fade,

	// True mientras el último dispositivo de input usado fue el mando (no
	// el mouse) — gatea el anillo de foco de gamepad en los botones y
	// decide si render_button acepta gamepad_focused. Ver
	// systems/gamepad.odin, gamepad_nav_update.
	gamepad_nav_active: bool,

	// Sub-systems
	sim: Simulation,
	editor: Editor,
	settings: Settings,
	
	// UI System
	console: Console_State,
	
	// Camera/View
	camera_offset_x: i32,
	camera_offset_y: i32,
	target_camera_offset_x: i32,  // For smooth zoom animation
	target_camera_offset_y: i32,  // For smooth zoom interpolation
	zoom: f32,
	target_zoom: f32,  // For smooth zoom interpolation

	// Mapa 3D — cámara fija-isométrica (ver 3D_RENDER_PLAN.md, paso 1).
	// camera_focus es el punto del terreno mirado (unidades de mundo, plano XZ);
	// camera3d se deriva de él cada frame en update_camera3d, no se persiste.
	camera3d:            raylib.Camera3D,
	camera_focus:        raylib.Vector3,
	target_camera_focus: raylib.Vector3,

	// Yaw de la cámara alrededor de camera_focus, en radianes. Responde 1:1
	// al drag del botón central (sin lerp/target, a diferencia de zoom/
	// camera_focus) — ver input_handle_camera_orbit en input.odin. 0 = vista
	// original (mirando siempre hacia -Z, idéntica a la cámara fija de antes
	// de este cambio).
	camera_yaw: f32,

	// Screen shake — "trauma" en [0,1], decae con el tiempo. El offset visual
	// se calcula en render_game a partir de esto y se aplica solo por el
	// tiempo del frame (no persiste en camera_offset_x/y).
	screen_shake_trauma: f32,
	
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

	// Meta-progression (persisted to savegame.bin).
	// Mutar via app.meta.* y setear app.meta_dirty = true (o llamar app_meta_mark_dirty).
	// El flush real ocurre en app_meta_flush(app), llamada cada frame en el main loop
	// y antes de cerrar la ventana. Esto evita olvidos de meta_save al sumar nuevas
	// rutas que muten progresión.
	meta:       Meta_State,
	meta_dirty: bool,

	// Cristales earned in the last run — set when transitioning to .RUN_COMPLETE
	run_cristales: i32,

	// Campaña — single source of truth. Cargada desde campaign.bin la primera
	// vez que se entra al visualizador (CAMPAIGN_MAP) o al editor.
	// El editor de campaña opera sobre esta misma struct vía campaign_editor_*.
	campaign:               Campaign_File,
	campaign_loaded:        bool,
	current_campaign_node:  i32,   // -1 = el run actual no es de campaña; >=0 = índice del nodo
	// Copia de "¿el run que acaba de terminar era de campaña?" tomada ANTES
	// de que app_finish_run resetee current_campaign_node a -1 — las
	// pantallas de fin de partida (render_game_over_ui/render_run_complete_ui,
	// systems/menus.odin) la usan para decidir si mostrar "Volver a
	// Campaña" en vez de leer current_campaign_node directo (que para
	// entonces siempre da -1).
	last_run_was_campaign: bool,
	campaign_file_mtime:    i64,   // mtime de campaign.bin para hot-reload (DEVELOPER only)

	// Nombre editable (Map.display_name) del .map de cada nodo, cacheado al
	// cargar/recargar campaign.bin — ver campaign_refresh_map_display_names.
	// Vacío = el mapa no tiene nombre asignado (fallback a display_name del
	// nodo o al filename, ver render_campaign_map).
	campaign_map_display_names: [constants.CAMPAIGN_MAX_NODES]string,

	// Bioma del .map de cada nodo — mismo cacheo/momento que
	// campaign_map_display_names (un solo map_load por nodo, no por frame).
	// campaign_map_biome_valid[i] = false cuando el .map no se pudo cargar
	// (ej. archivo borrado) — evita mostrar un bioma inventado (PLAIN, el
	// zero value de Biome) para un nodo cuyo mapa ya no existe.
	campaign_map_biomes:     [constants.CAMPAIGN_MAX_NODES]constants.Biome,
	campaign_map_biome_valid: [constants.CAMPAIGN_MAX_NODES]bool,

	// Modo "seleccionar tile/torre" para cartas de acción con target.
	// .TOWER (zero value) = inactivo. Cualquier otro kind = carta esperando selección.
	// Lumberjack espera un árbol; Overdrive espera una torre.
	pending_tower_action: Card_Kind,

	// GARDENER: coordenadas de la torre seleccionada en Fase 1.
	// {-1, -1} = Fase 1 (esperando selección de torre origen).
	// Cualquier otro valor = Fase 2 (esperando tile destino).
	gardener_source: [2]i32,

	// Tooltip layer — written during UI render, drawn last so it's always on top.
	// Only one tooltip can be visible per frame; first writer wins.
	pending_tooltip: Pending_Tooltip,

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

Tooltip_Kind :: enum { NONE, LABEL, CARD }

Pending_Tooltip :: struct {
	kind:     Tooltip_Kind,
	trigger:  raylib.Rectangle,
	label:    string,         // used when kind == .LABEL
	sublabel: string,         // opcional, kind == .LABEL — segunda línea en gris (vacío = una sola línea)
	card:     Card,           // used when kind == .CARD
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

// Set game state.
// Flush de meta en cada transición — barata si meta_dirty=false, garantiza que
// los cambios persistan al cambiar de pantalla aunque el jugador cierre la
// ventana segundos después.
app_set_state :: proc(app: ^App_State, new_state: constants.Game_State) {
	app.previous_state = app.state
	app.state = new_state
	app_meta_flush(app)
}

// Inicia una transición a negro antes de cambiar de estado — usado en
// victoria/derrota para no cortar en seco a la pantalla de Ganaste/Perdiste.
// El cambio de estado real (app_set_state) ocurre recién cuando la pantalla
// llega a negro total (ver app_screen_fade_update), así el jugador nunca ve
// el salto directo, sólo negro → nueva pantalla.
app_begin_state_fade :: proc(app: ^App_State, new_state: constants.Game_State) {
	app.screen_fade = Screen_Fade{
		active        = true,
		elapsed       = 0,
		revealing     = false,
		pending_state = new_state,
	}
}

// Avanza la transición de fade activa, si hay alguna. Llamar una vez por
// frame, antes de renderizar. Cambia de estado en el instante exacto en que
// la pantalla llega a negro total.
app_screen_fade_update :: proc(app: ^App_State, dt: f32) {
	if !app.screen_fade.active { return }
	app.screen_fade.elapsed += dt
	if !app.screen_fade.revealing {
		if app.screen_fade.elapsed >= constants.SCREEN_FADE_OUT_DURATION {
			app_set_state(app, app.screen_fade.pending_state)
			app.screen_fade.revealing = true
			app.screen_fade.elapsed   = 0
		}
	} else {
		if app.screen_fade.elapsed >= constants.SCREEN_FADE_IN_DURATION {
			app.screen_fade.active = false
		}
	}
}

// Alpha actual (0..255) del velo negro de la transición — 0 = transparente,
// 255 = negro total. El render dibuja un rectángulo pantalla-completa con
// este alpha encima de absolutamente todo lo demás.
app_screen_fade_alpha :: proc(app: ^App_State) -> u8 {
	if !app.screen_fade.active { return 0 }
	if !app.screen_fade.revealing {
		t := clamp(app.screen_fade.elapsed / constants.SCREEN_FADE_OUT_DURATION, f32(0), f32(1))
		return u8(t * 255)
	}
	t := clamp(app.screen_fade.elapsed / constants.SCREEN_FADE_IN_DURATION, f32(0), f32(1))
	return u8((1 - t) * 255)
}

// Marca el meta como sucio. El próximo flush lo persistirá a disco.
app_meta_mark_dirty :: proc(app: ^App_State) {
	app.meta_dirty = true
}

// Persiste meta si está sucio y limpia el flag. Llamar al final del frame y
// en transiciones de estado. Idempotente y barata cuando no hay cambios.
app_meta_flush :: proc(app: ^App_State) {
	if app.meta_dirty {
		meta_save(&app.meta)
		app.meta_dirty = false
	}
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
	// Reentrancia: mientras dura el fade a negro, la simulación queda
	// congelada (ver main.odin), pero por las dudas evita procesar el
	// resultado dos veces si algo más dispara otro finish_run en el medio.
	if app.screen_fade.active { return }

	// Tomar la copia ANTES de que el path de campaña, más abajo, resetee
	// current_campaign_node a -1 — ver el comentario del campo.
	app.last_run_was_campaign = app.current_campaign_node >= 0

	app.sim.is_victory = victory
	lives := app.sim.health if victory else 0
	cristales := meta_calc_cristales(app.sim.enemies_killed, lives, app.sim.wave_number)
	cristales += app.sim.relic_stacks[.MEMENTO] * constants.MEMENTO_CRISTALES_PER_STACK
	app.run_cristales   = cristales
	app.meta.cristales  += cristales
	app.meta.total_runs += 1

	// Path de campaña: registrar progreso, sumar bonus opcional, volver al visualizador.
	if app.current_campaign_node >= 0 &&
	   app.current_campaign_node < i32(constants.CAMPAIGN_MAX_NODES) &&
	   app.current_campaign_node < app.campaign.node_count {
		node := &app.campaign.nodes[app.current_campaign_node]
		waves_required := node.waves_override
		if waves_required <= 0 { waves_required = constants.RUN_MAX_WAVES }
		meta_record_campaign_result(
			&app.meta, app.current_campaign_node,
			app.sim.wave_number, lives, waves_required, victory,
		)
		if victory && (.OPTIONAL in node.flags) && node.reward_cristales > 0 {
			app.meta.cristales += node.reward_cristales
		}
		app.meta_dirty = true
		app.current_campaign_node = -1
		app_begin_state_fade(app, .GAME_OVER)
		return
	}

	// Path no-campaña: comportamiento original.
	app.meta_dirty = true
	app_begin_state_fade(app, .RUN_COMPLETE)
}

// Add money
app_add_money :: proc(app: ^App_State, amount: i32) {
	app.sim.money += amount
}

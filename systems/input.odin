package systems

import "vendor:raylib"
import "../entities"
import "../constants"
import "core:fmt"
import "core:math"

// Dirección de navegación de mando resuelta este frame — cacheada acá
// porque input_handle la calcula una sola vez, y las pantallas de
// menus.odin/campaign.odin la leen (no la recalculan) para mover su
// índice de foco. Ver gamepad_nav_update en systems/gamepad.odin.
current_nav_dir: Gamepad_Nav_Dir

// Durante PLAYING, mano/tienda/fila de HUD (Comenzar, Skip Shop, Pausa,
// velocidades) pueden estar interactivas a la vez — X/Triángulo/Círculo no
// pueden significar dos cosas a la vez el mismo frame, así que hace falta
// saber cuál de las superficies "tiene el control" ahora mismo:
// - Arriba/abajo del D-pad CICLA entre HAND → SHOP (si la tienda está
//   abierta) → HUD → HAND… (`_playing_gamepad_cycle`) — EXCEPTO estando ya
//   en SHOP, que maneja arriba/abajo por su cuenta (ver abajo).
// - Si algo está "armado" (torre/obstáculo seleccionado o acción con
//   objetivo pendiente) el contexto pasa a CURSOR sí o sí — izq/der del
//   D-pad mueve el cursor real a pasos fijos (pedido explícito del
//   usuario: NO quiere apuntar con el stick para colocar torres,
//   `gamepad_snap_cursor_to_grid`) en vez de navegar mano/tienda.
// - Sin nada armado, el stick derecho sigue siendo la forma de entrar a
//   CURSOR libremente (para llegar al panel de una torre ya colocada,
//   por ejemplo) — ahí no compite con nada porque el D-pad no tiene otro
//   uso posible en ese momento salvo salir de CURSOR hacia HAND.
// - Dentro de SHOP: izq/der navegan/compran cartas leyendo SÓLO el stick
//   izquierdo (`gamepad_shop_stick_dir`, no el d-pad — pedido explícito
//   del usuario). Abajo baja de la fila de cartas a Saltar/Reroll; arriba
//   vuelve de esos botones a las cartas, o — si ya estaba en las cartas —
//   sale directo a HAND, SIN pasar por HUD (pedido explícito: no quiere
//   ciclar hacia el HUD estando en la tienda).
Playing_Gamepad_Context :: enum { HAND, SHOP, HUD, CURSOR }
playing_gamepad_context: Playing_Gamepad_Context = .HAND

// Arriba/abajo alterna entre los contextos "de navegación" disponibles
// este frame (HAND siempre, SHOP sólo con la tienda abierta, HUD
// siempre) — cíclico, ya que son pocos ítems y da la vuelta en cualquier
// sentido sin quedar trabado en una punta.
_playing_gamepad_cycle :: proc(app: ^entities.App_State, dir: Gamepad_Nav_Dir) {
	avail: [3]Playing_Gamepad_Context
	n := 0
	avail[n] = .HAND; n += 1
	if app.sim.shop.active { avail[n] = .SHOP; n += 1 }
	avail[n] = .HUD; n += 1

	cur_idx := 0
	for i in 0 ..< n {
		if avail[i] == playing_gamepad_context { cur_idx = i; break }
	}
	switch dir {
	case .UP:   cur_idx = (cur_idx - 1 + n) % n
	case .DOWN: cur_idx = (cur_idx + 1) % n
	case .NONE, .LEFT, .RIGHT: return
	}
	playing_gamepad_context = avail[cur_idx]
}

// Celda "recordada" del cursor de mando mientras algo está armado — NO se
// recalcula desde cero cada tap a partir del mouse real. Se sincroniza
// sola a la celda real bajo el mouse cuando esa celda es válida, pero si
// el mouse real arranca fuera de la grilla (ej. recién armada la torre
// desde una carta al pie de pantalla — el mouse real puede seguir ahí
// mismo, que no es ningún tile) sigue teniendo de dónde partir en vez de
// quedar trabada: bug real reportado por el usuario ("no puedo
// posicionar una torre con el joystick") — la versión anterior, que
// exigía una celda válida bajo el mouse ANTES de mover un solo paso, no
// hacía nada en ese caso y el D-pad quedaba sin efecto.
_gamepad_grid_cursor_row: i32 = -1
_gamepad_grid_cursor_col: i32 = -1

// Mueve el cursor real al centro de la celda de grilla vecina en la
// dirección pedida, en vez de un desplazamiento fijo en píxeles de
// pantalla — la grilla está en proyección 3D (perspectiva + rotación de
// cámara con L2/R2), así que "un paso" en píxeles no corresponde a un
// tile real según el zoom/ángulo (podía saltear celdas enteras o no
// alcanzar la siguiente). Entre las 4 celdas vecinas de
// `_gamepad_grid_cursor_row/col` (fila/columna ±1) se elige la que mejor
// se alinea en PANTALLA con la dirección pedida (mayor producto punto
// contra el vector de pantalla de esa dirección) — así respeta la
// rotación de cámara actual: "arriba" en el D-pad siempre mueve hacia
// donde se ve "arriba" en pantalla, sin importar hacia dónde mira la
// cámara en ese momento.
gamepad_snap_cursor_to_grid :: proc(app: ^entities.App_State, dir: Gamepad_Nav_Dir) {
	m := &app.editor.game_map

	// Sincronizar con la celda real bajo el mouse si es válida — así un
	// click/movimiento de mouse real de por medio no deja el cursor de
	// mando "desactualizado".
	mouse := raylib.GetMousePosition()
	if col, row := screen_to_grid(app, i32(mouse.x), i32(mouse.y)); col >= 0 && col < m.width && row >= 0 && row < m.height {
		_gamepad_grid_cursor_row = row
		_gamepad_grid_cursor_col = col
	}

	if dir == .NONE { return }

	// Nunca hubo una celda válida (mouse real arrancó fuera de la grilla)
	// — arrancamos del centro del mapa en vez de quedarnos sin poder
	// mover un solo paso.
	if _gamepad_grid_cursor_row < 0 || _gamepad_grid_cursor_col < 0 {
		_gamepad_grid_cursor_row = m.height / 2
		_gamepad_grid_cursor_col = m.width / 2
	}

	screen_dir: raylib.Vector2
	switch dir {
	case .UP:    screen_dir = {0, -1}
	case .DOWN:  screen_dir = {0, 1}
	case .LEFT:  screen_dir = {-1, 0}
	case .RIGHT: screen_dir = {1, 0}
	case .NONE:
	}

	cur_center, _ := tile_world_top(m, _gamepad_grid_cursor_row, _gamepad_grid_cursor_col)
	cur_screen := raylib.GetWorldToScreen(cur_center, app.camera3d)

	candidates := [4][2]i32{
		{_gamepad_grid_cursor_row - 1, _gamepad_grid_cursor_col},
		{_gamepad_grid_cursor_row + 1, _gamepad_grid_cursor_col},
		{_gamepad_grid_cursor_row, _gamepad_grid_cursor_col - 1},
		{_gamepad_grid_cursor_row, _gamepad_grid_cursor_col + 1},
	}
	best_score := f32(0)
	best_row, best_col := _gamepad_grid_cursor_row, _gamepad_grid_cursor_col
	best_pos := cur_screen
	found := false
	for c in candidates {
		nr, nc := c[0], c[1]
		if nr < 0 || nr >= m.height || nc < 0 || nc >= m.width { continue }
		center, _ := tile_world_top(m, nr, nc)
		screen := raylib.GetWorldToScreen(center, app.camera3d)
		delta := raylib.Vector2{screen.x - cur_screen.x, screen.y - cur_screen.y}
		length := math.sqrt(delta.x*delta.x + delta.y*delta.y)
		if length < 0.001 { continue }
		score := (delta.x*screen_dir.x + delta.y*screen_dir.y) / length
		if score > best_score {
			best_score = score
			best_row, best_col = nr, nc
			best_pos = screen
			found = true
		}
	}
	if found {
		_gamepad_grid_cursor_row = best_row
		_gamepad_grid_cursor_col = best_col
	}
	raylib.SetMousePosition(
		i32(clamp(best_pos.x, 0, f32(raylib.GetScreenWidth()))),
		i32(clamp(best_pos.y, 0, f32(raylib.GetScreenHeight()))),
	)
}

_update_playing_gamepad_context :: proc(app: ^entities.App_State) {
	armed := app.sim.selected_build_tower != .EMPTY || app.pending_tower_action != .TOWER

	if armed {
		playing_gamepad_context = .CURSOR
		gamepad_snap_cursor_to_grid(app, current_nav_dir)
	} else if !app.sim.shop.active && gamepad_virtual_mouse_update(app.delta_time) {
		// El stick derecho (mouse virtual) queda desactivado mientras la
		// tienda está abierta — pedido explícito del usuario: no quiere
		// que mover el stick derecho por error se lleve el contexto a
		// CURSOR y lo saque de la navegación de la tienda.
		playing_gamepad_context = .CURSOR
	} else if playing_gamepad_context == .SHOP {
		// La tienda no usa el ciclo genérico de contextos para
		// arriba/abajo — navega su propia fila cartas↔Saltar/Reroll y
		// sale directo a HAND desde arriba (nunca hacia HUD).
		n_cards := shop_card_slot_count(app)
		on_buttons := shop_gamepad_focus_idx >= n_cards
		switch current_nav_dir {
		case .DOWN:
			if !on_buttons { shop_gamepad_focus_idx = n_cards }
		case .UP:
			if on_buttons {
				shop_gamepad_focus_idx = 0
			} else {
				playing_gamepad_context = .HAND
			}
		case .NONE, .LEFT, .RIGHT:
		}
	} else {
		switch current_nav_dir {
		case .LEFT, .RIGHT:
			if playing_gamepad_context == .CURSOR {
				playing_gamepad_context = .HAND
			}
		case .UP, .DOWN:
			_playing_gamepad_cycle(app, current_nav_dir)
		case .NONE:
		}
	}
	// Self-heal: no quedarse en SHOP si la tienda ya cerró.
	if !app.sim.shop.active && playing_gamepad_context == .SHOP {
		playing_gamepad_context = .HAND
	}
}

// Handle all input
input_handle :: proc(app: ^entities.App_State) {
	// Fuera de PLAYING, playing_gamepad_context siempre vuelve a HAND —
	// evita que quede pegado en .CURSOR (ej. si se pausó con el cursor
	// libre activo) y ese estado colgado termine gatillando la rama
	// "hovered + confirm sin gamepad_focused explícito" de render_button
	// en una pantalla de menú donde no debería aplicar.
	if app.state != .PLAYING {
		playing_gamepad_context = .HAND
	}

	// Tab: abrir/cerrar la consola (siempre, en cualquier estado)
	if raylib.IsKeyPressed(.TAB) {
		app.console.open = !app.console.open
		// Auto-focus el campo de comandos al abrir; desfocar al cerrar
		app.console.cmd_input.focused = app.console.open
	}

	// F9: mostrar/ocultar el contador de FPS (siempre, en cualquier estado)
	// — mismo settings.show_fps que ya controla el toggle en el menú de
	// Settings, así que quedan en sync entre los dos (ver
	// render_ui/menus.odin, que ya lo suprime en EDITOR).
	if raylib.IsKeyPressed(.F9) {
		app.settings.show_fps = !app.settings.show_fps
	}

	// F10: mostrar/ocultar el overlay de diagnóstico de mando (siempre, en
	// cualquier estado, sin depender de constants.DEVELOPER — ver
	// render_gamepad_debug_overlay en systems/gamepad.odin).
	if raylib.IsKeyPressed(.F10) {
		gamepad_debug_active = !gamepad_debug_active
	}

	// No mover la cámara mientras el browser de mapas está abierto en el
	// editor, ni mientras el shop está abierto (overlay de PLAYING, no un
	// app.state propio — ver app.sim.shop.active).
	if !(app.state == .EDITOR && app.editor.show_map_browser) && !app.sim.shop.active {
		input_handle_camera(app)
	}

	// Navegación de menús con mando — una sola lectura por frame, cacheada
	// para que las pantallas de menus.odin/campaign.odin no la recalculen.
	// Ver systems/gamepad.odin.
	current_nav_dir = gamepad_nav_update(app, app.delta_time)

	#partial switch app.state {
	case .MENU:
		input_handle_menu(app)
	case .PLAYING:
		input_handle_playing(app)
	case .PAUSED:
		input_handle_paused(app)
	case .EDITOR:
		input_handle_editor(app)
	case .GAME_OVER:
		input_handle_game_over(app)
	case .SETTINGS:
		// Settings menu input is handled via render_button in render_settings_menu
		if raylib.IsKeyPressed(.ESCAPE) || gamepad_cancel_pressed() {
			entities.app_set_state(app, app.previous_state)
		}
	case .RUN_COMPLETE:
		// Input handled via render_button in render_run_complete_ui
	case .LIBRARY:
		// Input handled via render_button in render_card_library_ui
		if raylib.IsKeyPressed(.ESCAPE) || gamepad_cancel_pressed() {
			entities.app_set_state(app, app.previous_state)
		}
	case .CREDITS:
		// Input handled via render_button in render_credits_ui
		if raylib.IsKeyPressed(.ESCAPE) || gamepad_cancel_pressed() {
			entities.app_set_state(app, .MENU)
		}
	case .CAMPAIGN_MAP:
		// Input handled via render_button / inline node clicks in render_campaign_map.
		// Cancelar/ESC es de dos niveles: si hay un panel de detalle
		// abierto lo cierra primero (no sale de la pantalla), igual que
		// "atrás" en cualquier UI de consola.
		if raylib.IsKeyPressed(.ESCAPE) || gamepad_cancel_pressed() {
			if campaign_map_selected_node >= 0 {
				campaign_map_selected_node = -1
			} else {
				campaign_map_scroll        = 0
				campaign_map_gamepad_focus = -1
				entities.app_set_state(app, .MENU)
			}
		}
	}
}

// Menu input
input_handle_menu :: proc(app: ^entities.App_State) {
	// Si el browser de mapas está abierto (para seleccionar mapa al jugar),
	// manejar scroll y ESC igual que en el editor
	if app.editor.show_map_browser {
		if raylib.IsKeyPressed(.ESCAPE) {
			entities.map_destroy(&app.editor.browser.preview)
			app.editor.browser.preview_valid = false
			if app.editor.browser.preview_tex_valid {
				raylib.UnloadRenderTexture(app.editor.browser.preview_tex)
				app.editor.browser.preview_tex_valid = false
			}
			app.editor.show_map_browser = false
			app.editor.browser.play_mode = false
		}
		wheel := raylib.GetMouseWheelMove()
		if wheel != 0 {
			content_h     := constants.UI_MAP_BROWSER_HEIGHT - constants.UI_MAP_BROWSER_HEADER_HEIGHT - constants.UI_MAP_BROWSER_FOOTER_HEIGHT
			visible_items := content_h / constants.UI_MAP_BROWSER_ITEM_HEIGHT
			app.editor.browser.scroll -= i32(wheel)
			if app.editor.browser.scroll < 0 {
				app.editor.browser.scroll = 0
			}
			max_scroll := i32(len(app.editor.browser.entries)) - visible_items
			if max_scroll < 0 { max_scroll = 0 }
			if app.editor.browser.scroll > max_scroll {
				app.editor.browser.scroll = max_scroll
			}
		}
	}

	// ── Developer: Ctrl+Shift+R desde el menú principal → reset meta ────────
	// Útil para testear desde cero sin tocar savegame.bin a mano.
	when constants.DEVELOPER {
		ctrl   := raylib.IsKeyDown(.LEFT_CONTROL) || raylib.IsKeyDown(.RIGHT_CONTROL)
		shift  := raylib.IsKeyDown(.LEFT_SHIFT)   || raylib.IsKeyDown(.RIGHT_SHIFT)
		if ctrl && shift && raylib.IsKeyPressed(.R) && !app.confirm_modal.active {
			app.confirm_modal = entities.Confirm_Modal{
				active = true,
				text   = "[DEV] Resetear progreso?\nCristales, unlocks y campaña a cero.",
				action = .RESET_META,
			}
		}
	}
}

// Playing input
input_handle_playing :: proc(app: ^entities.App_State) {
	// Mando: mueve el cursor real con el stick derecho y resuelve qué
	// superficie (mano/tienda/cursor libre) controla X/Triángulo/Círculo
	// este frame — ver Playing_Gamepad_Context arriba.
	_update_playing_gamepad_context(app)

	// Mouse position for grid selection
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	// Convert to grid coordinates using helper function
	grid_x, grid_y := screen_to_grid(app, mouse_x, mouse_y)
	
	app.mouse_x = grid_x
	app.mouse_y = grid_y
	
	// Update selected cell for reticle display
	if is_valid_grid_pos(app, grid_x, grid_y) {
		app.selected_cell.row = grid_y
		app.selected_cell.col = grid_x
		app.selected_cell.valid = true
	} else {
		app.selected_cell.valid = false
	}
	
	// Left click to place tower — o Confirmar de mando (X) cuando el
	// cursor virtual tiene el control (playing_gamepad_context == .CURSOR;
	// en .HAND/.SHOP, X lo consume render_card_hand/render_card_selection_overlay).
	if raylib.IsMouseButtonPressed(.LEFT) ||
	   (playing_gamepad_context == .CURSOR && gamepad_confirm_pressed()) {
		// Don't process grid clicks if mouse is over any UI panel or button
		if ui_is_click_blocked(mouse_x, mouse_y) {
			return
		}

		// Check airdrop box first (highest priority click target)
		if is_valid_grid_pos(app, grid_x, grid_y) {
			if airdrop_collect(app, grid_y, grid_x) {
				return
			}
		}

		// Cartas de acción con target pendiente (LUMBERJACK, OVERDRIVE, …)
		if app.pending_tower_action != .TOWER && is_valid_grid_pos(app, grid_x, grid_y) {
			tile := app.editor.game_map.grid[grid_y][grid_x]
			#partial switch app.pending_tower_action {
			case .LUMBERJACK:
				if tile == .ACCESSORY_TREE {
					app.editor.game_map.grid[grid_y][grid_x] = .EMPTY
					entities.app_add_money(app, constants.LUMBERJACK_TREE_GOLD)
					entities.add_toast(app, fmt.tprintf("+$%d árbol talado", constants.LUMBERJACK_TREE_GOLD), .SUCCESS)
					entities.card_play(&app.sim, app.sim.cards.selected_card_idx)
					app.sim.cards.selected_card_idx = -1
					app.pending_tower_action = .TOWER
					play_sound(.CONFIRMATION, .UI)
					return
				}
			case .OVERDRIVE:
				is_tower_tile := tile == .TOWER_ARCHER || tile == .TOWER_CANNON ||
				                 tile == .TOWER_SNIPER  || tile == .TOWER_MISSILE ||
				                 tile == .TOWER_LASER   || tile == .TOWER_ICE ||
				                 tile == .TOWER_ENHANCE || tile == .TOWER_TESLA ||
				                 tile == .TOWER_MORTAR
				if is_tower_tile {
					for &t in app.sim.towers {
						if t.r == grid_y && t.c == grid_x {
							t.overdrive_stacks += 1
							entities.tower_recompute_stats(&t)
							entities.add_toast(app, fmt.tprintf("+%d%% vel. ataque", i32(constants.OVERDRIVE_SPEED_PER_STACK * 100)), .SUCCESS)
							break
						}
					}
					entities.card_play(&app.sim, app.sim.cards.selected_card_idx)
					app.sim.cards.selected_card_idx = -1
					app.pending_tower_action = .TOWER
					play_sound(.CONFIRMATION, .UI)
					return
				}
case .GARDENER:
				is_tower_tile := tile == .TOWER_ARCHER || tile == .TOWER_CANNON ||
				                 tile == .TOWER_SNIPER  || tile == .TOWER_MISSILE ||
				                 tile == .TOWER_LASER   || tile == .TOWER_ICE ||
				                 tile == .TOWER_ENHANCE || tile == .TOWER_TESLA ||
				                 tile == .TOWER_MORTAR
				if app.gardener_source == {-1, -1} {
					// Fase 1: seleccionar torre origen
					if is_tower_tile {
						app.gardener_source = {i32(grid_y), i32(grid_x)}
						play_sound(.SELECT, .UI)
						return
					}
				} else {
					// Fase 2: seleccionar tile destino vacío
					can_place := tile == .EMPTY &&
					             app.editor.game_map.obstacle_grid[grid_y][grid_x] == .EMPTY &&
					             !app.editor.game_map.water_grid[grid_y][grid_x]
					if can_place {
						src_r    := app.gardener_source[0]
						src_c    := app.gardener_source[1]
						src_tile := app.editor.game_map.grid[src_r][src_c]
						app.editor.game_map.grid[grid_y][grid_x] = src_tile
						app.editor.game_map.grid[src_r][src_c]   = .EMPTY
						for &t in app.sim.towers {
							if t.r == src_r && t.c == src_c {
								t.r = i32(grid_y)
								t.c = i32(grid_x)
								break
							}
						}
						update_formation_cache(app)
						entities.add_toast(app, constants.get_text("TOAST_GARDENER"), .SUCCESS)
						entities.card_play(&app.sim, app.sim.cards.selected_card_idx)
						app.sim.cards.selected_card_idx = -1
						app.pending_tower_action = .TOWER
						app.gardener_source      = {-1, -1}
						play_sound(.CONFIRMATION, .UI)
						return
					}
				}
			case:
				// Otro kind con target pendiente — no hacer nada
			}
		}

		if is_valid_grid_pos(app, grid_x, grid_y) {
			// Check if clicking on a tower
			tile := app.editor.game_map.grid[grid_y][grid_x]
			obstacle := app.editor.game_map.obstacle_grid[grid_y][grid_x]

			#partial switch tile {
			case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER,
			     .TOWER_ICE, .TOWER_ENHANCE, .TOWER_TESLA, .TOWER_MORTAR:
				// Si hay acción pendiente que necesita torre, no seleccionar — ya fue manejado arriba
				if app.pending_tower_action != .TOWER { break }
				// Select tower for upgrade
				select_tower_at(app, grid_y, grid_x)
				app.selected_obstacle.valid = false // Deselect obstacle
				play_sound(.SELECT, .UI)
			case:
				// Not a tower - check if it's an obstacle
				if obstacle == .OBSTACLE {
					// Select obstacle
					app.selected_obstacle.row = grid_y
					app.selected_obstacle.col = grid_x
					app.selected_obstacle.valid = true
					entities.app_deselect_tower(app) // Deselect tower
					play_sound(.SELECT, .UI)
				} else {
					// Deselect both tower and obstacle
					entities.app_deselect_tower(app)
					app.selected_obstacle.valid = false

					// Place selected card if one is selected
					if app.sim.selected_build_tower != .EMPTY {
						if app.sim.selected_build_tower == .OBSTACLE {
							// Colocar obstáculo — gratuito, ya se pagó en el shop
							is_forbidden := entities.map_is_path_corner_or_junction(&app.editor.game_map, grid_y, grid_x)
							if app.editor.game_map.obstacle_grid[grid_y][grid_x] == .EMPTY && !is_forbidden &&
							   !app.editor.game_map.water_grid[grid_y][grid_x] {
								app.editor.game_map.obstacle_grid[grid_y][grid_x] = .OBSTACLE
								entities.card_play(&app.sim, app.sim.cards.selected_card_idx)
								app.sim.selected_build_tower = .EMPTY
								app.sim.cards.selected_card_idx    = -1
								play_sound(.CLICK, .UI)
							}
						} else {
							// Colocar torre — gratuito, ya se pagó en el shop.
							// Se puede construir sobre árboles (ACCESSORY_TREE): el árbol se destruye.
							tower_type := tile_to_tower_type(app.sim.selected_build_tower)
							can_place  := (tile == .EMPTY || tile == .ACCESSORY_TREE) &&
							              app.editor.game_map.obstacle_grid[grid_y][grid_x] == .EMPTY &&
							              !app.editor.game_map.water_grid[grid_y][grid_x]
							if can_place {
								app.editor.game_map.grid[grid_y][grid_x] = app.sim.selected_build_tower
								tower := entities.tower_init(tower_type, grid_y, grid_x)
								selected_card := app.sim.cards.hand[app.sim.cards.selected_card_idx]
								for _ in 0 ..< selected_card.bonus_level {
									entities.tower_upgrade(&tower)
								}
								append(&app.sim.towers, tower)
								app.sim.towers_built += 1
								update_formation_cache(app)
								entities.card_play(&app.sim, app.sim.cards.selected_card_idx)
								app.sim.selected_build_tower = .EMPTY
								app.sim.cards.selected_card_idx    = -1
								play_sound(.CLICK, .UI)
							}
						}
					}
				}
			}
		}
	}
	
	// Right click to deselect or cancel — ignorado si cae sobre UI bloqueante
	// (p. ej. la mano de cartas, que usa el clic derecho para vender). El
	// Círculo del mando cuenta como este mismo gesto sólo con el cursor
	// libre (en .HAND, Círculo no existe hoy; en .SHOP alterna el lock) —
	// mismo chequeo de UI-bloqueada para ambos disparadores.
	right_pressed := raylib.IsMouseButtonPressed(.RIGHT) ||
		(playing_gamepad_context == .CURSOR && gamepad_cancel_pressed())
	if right_pressed && !ui_is_click_blocked(mouse_x, mouse_y) {
		if app.pending_tower_action != .TOWER {
			// Cancelar acción con target — la carta vuelve a la mano sin gastarse
			app.pending_tower_action = .TOWER
			app.sim.cards.selected_card_idx = -1
			app.gardener_source = {-1, -1}
		} else if app.sim.selected_build_tower != .EMPTY {
			app.sim.selected_build_tower = .EMPTY
			app.sim.cards.selected_card_idx    = -1
		} else {
			entities.app_deselect_tower(app)
			app.selected_obstacle.valid = false
		}
	}
	
	// Keyboard shortcuts
	if raylib.IsKeyPressed(.ESCAPE) {
		simulation_set_pause(app, true)
		entities.app_set_state(app, .PAUSED)
	}
	
	if raylib.IsKeyPressed(.SPACE) {
		simulation_toggle_pause(app)
	}
	
	// Number keys for speed
	if raylib.IsKeyPressed(.ONE) {
		simulation_set_speed(app, 1.0)
	}
	if raylib.IsKeyPressed(.TWO) {
		simulation_set_speed(app, 2.0)
	}

	// Grid toggle — mismo settings.show_grid que ya usa el editor (ver
	// input_handle_editor), así que queda en sync entre los dos estados.
	if raylib.IsKeyPressed(.G) {
		app.settings.show_grid = !app.settings.show_grid
	}

	// ── Developer hotkeys (compiled out when DEVELOPER == false) ─────────────
	when constants.DEVELOPER {
		// F1 — +$500
		if raylib.IsKeyPressed(.F1) {
			entities.app_add_money(app, 500)
			entities.add_toast(app, "[DEV] +$500", .INFO, 1.5)
		}
		// F2 — skip wave (clear all enemies, trigger end-of-wave)
		if raylib.IsKeyPressed(.F2) {
			clear(&app.sim.enemies)
			app.sim.enemies_to_spawn = 0
			entities.add_toast(app, "[DEV] Wave skipped", .INFO, 1.5)
		}
		// F3 — +50 health
		if raylib.IsKeyPressed(.F3) {
			app.sim.health += 50
			entities.add_toast(app, "[DEV] +50 health", .INFO, 1.5)
		}
		// F4 — toggle god mode
		if raylib.IsKeyPressed(.F4) {
			app.dev_god_mode = !app.dev_god_mode
			msg := "[DEV] God mode ON" if app.dev_god_mode else "[DEV] God mode OFF"
			entities.add_toast(app, msg, .INFO, 2.0)
		}
		// F5 — +100 cristales
		if raylib.IsKeyPressed(.F5) {
			app.meta.cristales += 100
			app.meta_dirty = true
			entities.add_toast(app, "[DEV] +100 cristales", .INFO, 1.5)
		}
	}
}

// Paused input
input_handle_paused :: proc(app: ^entities.App_State) {
	// PAUSED no pasa por input_handle_camera_3d (su zoom va por el path 2D
	// compartido de input_handle_camera) — la rotación se cablea acá aparte.
	input_handle_camera_orbit(app)

	// SPACE resumes the game
	if raylib.IsKeyPressed(.SPACE) {
		simulation_set_pause(app, false)
		entities.app_set_state(app, .PLAYING)
	}

	// ESCAPE goes back to main menu
	if raylib.IsKeyPressed(.ESCAPE) {
		simulation_set_pause(app, false)
		entities.app_set_state(app, .MENU)
	}

	// Right click to cancel selected build tower
	if raylib.IsMouseButtonPressed(.RIGHT) {
		if app.sim.selected_build_tower != .EMPTY {
			app.sim.selected_build_tower = .EMPTY
		} else {
			entities.app_deselect_tower(app)
			app.selected_obstacle.valid = false
		}
	}
}

// Editor input
input_handle_editor :: proc(app: ^entities.App_State) {
	// Shortcuts de teclado (siempre activos, sin importar posición del mouse)
	input_process_editor_shortcuts(app)

	// Reset paint flag whenever the left button is released, regardless of mouse position
	if raylib.IsMouseButtonReleased(.LEFT) {
		app.editor.is_painting = false
	}

	// Cuando el browser está abierto: manejar scroll/ESC y bloquear el resto del input
	if app.editor.show_map_browser {
		if raylib.IsKeyPressed(.ESCAPE) {
			if app.editor.browser.renaming {
				// Escape cancela el rename sin cerrar el browser
				app.editor.browser.renaming = false
			} else {
				entities.map_destroy(&app.editor.browser.preview)
				app.editor.browser.preview_valid = false
				if app.editor.browser.preview_tex_valid {
					raylib.UnloadRenderTexture(app.editor.browser.preview_tex)
					app.editor.browser.preview_tex_valid = false
				}
				app.editor.show_map_browser = false
				app.editor.browser.play_mode = false
			}
		}
		wheel := raylib.GetMouseWheelMove()
		if wheel != 0 {
			content_h     := constants.UI_MAP_BROWSER_HEIGHT - constants.UI_MAP_BROWSER_HEADER_HEIGHT - constants.UI_MAP_BROWSER_FOOTER_HEIGHT
			visible_items := content_h / constants.UI_MAP_BROWSER_ITEM_HEIGHT
			app.editor.browser.scroll -= i32(wheel)
			if app.editor.browser.scroll < 0 {
				app.editor.browser.scroll = 0
			}
			max_scroll := i32(len(app.editor.browser.entries)) - visible_items
			if max_scroll < 0 { max_scroll = 0 }
			if app.editor.browser.scroll > max_scroll {
				app.editor.browser.scroll = max_scroll
			}
		}
		return
	}

	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	// Convert to grid coordinates using helper function
	grid_x, grid_y := screen_to_grid(app, mouse_x, mouse_y)
	
	app.mouse_x = grid_x
	app.mouse_y = grid_y
	
	// Update selected cell for reticle display
	if is_valid_grid_pos(app, grid_x, grid_y) {
		app.selected_cell.row = grid_y
		app.selected_cell.col = grid_x
		app.selected_cell.valid = true
	} else {
		app.selected_cell.valid = false
	}
	
	// Bottom toolbars (build tools and menus)
	if mouse_y > raylib.GetScreenHeight() - 70 {
		return
	}
	
	// Check if valid grid position
	if !is_valid_grid_pos(app, grid_x, grid_y) {
		return
	}
	
	// Left click to place or erase (continuous with IsMouseButtonDown)
	if raylib.IsMouseButtonDown(.LEFT) {
		// Push undo snapshot only at the start of each paint stroke
		if !app.editor.is_painting {
			editor_push_undo(app)
			app.editor.is_painting = true
		}

		tool := app.editor.current_tool

		switch tool {
		case .EMPTY:
			// Erase
			editor_erase_cell(app, grid_y, grid_x)
		case .PATH, .SPAWN, .GOAL:
			// Place path elements
			app.editor.game_map.grid[grid_y][grid_x] = tool
		case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER,
		     .TOWER_ICE, .TOWER_ENHANCE, .TOWER_TESLA, .TOWER_MORTAR:
			// Place tower (only on empty cells)
			if app.editor.game_map.grid[grid_y][grid_x] == .EMPTY {
				app.editor.game_map.grid[grid_y][grid_x] = tool
			}
		case .OBSTACLE:
			// Place obstacle (in obstacle layer, not on water)
			if !app.editor.game_map.water_grid[grid_y][grid_x] {
				app.editor.game_map.obstacle_grid[grid_y][grid_x] = .OBSTACLE
			}
		case .ACCESSORY_TREE, .ACCESSORY_BLOCK:
			// Place accessories
			if app.editor.game_map.grid[grid_y][grid_x] == .EMPTY {
				app.editor.game_map.grid[grid_y][grid_x] = tool
			}
		case .WATER:
			// Water en cualquier celda excepto torres (path + water = puente automático)
			tile := app.editor.game_map.grid[grid_y][grid_x]
			is_tower := tile == .TOWER_ARCHER || tile == .TOWER_CANNON || tile == .TOWER_SNIPER ||
			            tile == .TOWER_MISSILE || tile == .TOWER_LASER  || tile == .TOWER_ICE   ||
			            tile == .TOWER_ENHANCE || tile == .TOWER_TESLA  || tile == .TOWER_MORTAR
			if !is_tower {
				app.editor.game_map.water_grid[grid_y][grid_x] = true
			}
		}

		// La malla 3D del terreno está cacheada (ver terrain_cache_ensure,
		// systems/rendering.odin) — invalidar en cada frame de pintado para
		// que el próximo render_map_3d la reconstruya con el tile nuevo.
		terrain_cache_invalidate()
	}

	// Right click to erase
	if raylib.IsMouseButtonPressed(.RIGHT) {
		editor_push_undo(app)
		editor_erase_cell(app, grid_y, grid_x)
		terrain_cache_invalidate()
	}
	
	// Keyboard shortcuts
	if raylib.IsKeyPressed(.ESCAPE) {
		entities.app_set_state(app, .MENU)
	}
	
	// Tool selection hotkeys
	if raylib.IsKeyPressed(.ONE) {
		app.editor.current_tool = .EMPTY
	}
	if raylib.IsKeyPressed(.TWO) {
		app.editor.current_tool = .PATH
	}
	if raylib.IsKeyPressed(.THREE) {
		app.editor.current_tool = .SPAWN
	}
	if raylib.IsKeyPressed(.FOUR) {
		app.editor.current_tool = .GOAL
	}
	if raylib.IsKeyPressed(.FIVE) {
		app.editor.current_tool = .TOWER_ARCHER
	}
	if raylib.IsKeyPressed(.SIX) {
		app.editor.current_tool = .TOWER_CANNON
	}
	if raylib.IsKeyPressed(.SEVEN) {
		app.editor.current_tool = .TOWER_SNIPER
	}
	if raylib.IsKeyPressed(.EIGHT) {
		app.editor.current_tool = .TOWER_MISSILE
	}
	if raylib.IsKeyPressed(.NINE) {
		app.editor.current_tool = .TOWER_LASER
	}
	if raylib.IsKeyPressed(.ZERO) {
		app.editor.current_tool = .OBSTACLE
	}
	
	// Grid toggle
	if raylib.IsKeyPressed(.G) {
		app.settings.show_grid = !app.settings.show_grid
	}
}



// Editor erase cell
editor_erase_cell :: proc(app: ^entities.App_State, row, col: i32) {
	if row < 0 || row >= constants.GRID_SIZE || col < 0 || col >= constants.GRID_SIZE {
		return
	}
	
	// Remove from main grid
	app.editor.game_map.grid[row][col] = .EMPTY

	// Also remove from obstacle grid
	app.editor.game_map.obstacle_grid[row][col] = .EMPTY

	// Also remove water
	app.editor.game_map.water_grid[row][col] = false

	// Remove tile data — also free the cloned key string
	if existing_key, ok := entities.map_get_existing_key(&app.editor.game_map, row, col); ok {
		delete_key(&app.editor.game_map.tile_data, existing_key)
		delete(existing_key)
	}
}

// Game over input
input_handle_game_over :: proc(app: ^entities.App_State) {
	// Handled by render_button in rendering.odin
}

// Helper to check if grid position is valid (uses actual map dimensions)
is_valid_grid_pos :: proc(app: ^entities.App_State, x, y: i32) -> bool {
	return x >= 0 && x < app.editor.game_map.width && y >= 0 && y < app.editor.game_map.height
}

// Convert screen coordinates to grid coordinates (accounts for camera offset and zoom).
// En PLAYING y EDITOR el mapa es 3D (ver 3D_RENDER_PLAN.md) — se resuelve con
// raycast contra el plano y=0 en vez de la fórmula 2D. PAUSED sigue 2D.
screen_to_grid :: proc(app: ^entities.App_State, screen_x, screen_y: i32) -> (grid_x, grid_y: i32) {
	if app.state == .PLAYING || app.state == .EDITOR {
		return screen_to_grid_3d(app, screen_x, screen_y)
	}
	cs := f32(app.settings.cell_size) * app.zoom
	grid_x = i32((f32(screen_x) - f32(app.camera_offset_x)) / cs)
	grid_y = i32((f32(screen_y) - f32(app.camera_offset_y)) / cs)
	return
}

// Raycast contra el plano y=0 del mundo 3D. Si el rayo no cruza el plano
// (mira hacia arriba, no debería pasar con la cámara fija-isométrica actual)
// devuelve una celda claramente inválida.
screen_to_grid_3d :: proc(app: ^entities.App_State, screen_x, screen_y: i32) -> (grid_x, grid_y: i32) {
	point, ok := raycast_terrain_point(app, screen_x, screen_y)
	if !ok {
		return -1, -1
	}
	cs := constants.WORLD_CELL_SIZE
	grid_x = i32(math.floor(point.x / cs))
	grid_y = i32(math.floor(point.z / cs))
	return
}

// Raycast contra la altura real del terreno (heightmap + agua a nivel fijo),
// no un plano y=0 puro — un plano fijo desalinea el picking en cualquier
// tile con desnivel o agua (más notorio ahora que la grilla del editor sigue
// la altura real del mesh, ver render_grid_lines_3d). Refinamiento
// iterativo: cada pasada intersecta el rayo contra un plano horizontal a la
// altura del tile encontrado en la pasada anterior — converge rápido porque
// la pendiente entre tiles vecinos está acotada (ver _terrain_corner).
raycast_terrain_point :: proc(app: ^entities.App_State, screen_x, screen_y: i32) -> (point: raylib.Vector3, ok: bool) {
	m := &app.editor.game_map
	ray := raylib.GetScreenToWorldRay({f32(screen_x), f32(screen_y)}, app.camera3d)
	if ray.direction.y >= -0.0001 {
		return {}, false
	}

	cs := constants.WORLD_CELL_SIZE
	biome_colors := constants.BIOME_COLORS[m.biome]

	y := f32(0)
	for _ in 0 ..< 4 {
		t := (y - ray.position.y) / ray.direction.y
		if t < 0 {
			return {}, false
		}
		point = ray.position + ray.direction * t

		col := i32(math.floor(point.x / cs))
		row := i32(math.floor(point.z / cs))
		if row < 0 || row >= m.height || col < 0 || col >= m.width {
			// Fuera del mapa — no hay altura de terreno que consultar, el
			// último plano probado ya es la mejor aproximación posible.
			break
		}
		next_y, _ := _terrain_tile_height_color(m, row, col, biome_colors)
		if next_y == y {
			break  // convergió, no hace falta seguir iterando
		}
		y = next_y
	}
	ok = true
	return
}

// Select tower at position
select_tower_at :: proc(app: ^entities.App_State, row, col: i32) {
	for &tower in app.sim.towers {
		if tower.r == row && tower.c == col {
			entities.app_select_tower(app, row, col)
			return
		}
	}
	entities.app_deselect_tower(app)
}

// Get hovered cell info
input_get_hovered_cell :: proc(app: ^entities.App_State) -> (row, col: i32, valid: bool) {
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	
	// Convert to grid coordinates using helper function
	col, row = screen_to_grid(app, mouse_x, mouse_y)
	
	valid = is_valid_grid_pos(app, col, row)
	return
}

// Process editor shortcuts
input_process_editor_shortcuts :: proc(app: ^entities.App_State) {
	ctrl := raylib.IsKeyDown(.LEFT_CONTROL) || raylib.IsKeyDown(.RIGHT_CONTROL)
	shift := raylib.IsKeyDown(.LEFT_SHIFT) || raylib.IsKeyDown(.RIGHT_SHIFT)

	// Undo (Ctrl+Z)
	if ctrl && raylib.IsKeyPressed(.Z) && !shift {
		editor_undo(app)
	}

	// Redo (Ctrl+Y  or  Ctrl+Shift+Z)
	if ctrl && (raylib.IsKeyPressed(.Y) || (shift && raylib.IsKeyPressed(.Z))) {
		editor_redo(app)
	}

	// Limpiar mapa (Ctrl+C)
	if ctrl && raylib.IsKeyPressed(.C) {
		editor_push_undo(app)
		entities.map_clear(&app.editor.game_map)
		terrain_cache_invalidate()
		entities.add_toast(app, "Map cleared", .INFO, 2.0)
	}

	// Guardar mapa (Ctrl+S) → guarda como last_saved.map
	if ctrl && raylib.IsKeyPressed(.S) {
		if entities.map_save(&app.editor.game_map, "last_saved.map") {
			entities.add_toast(app, "Map saved! (Ctrl+S)", .SUCCESS, 2.0)
		} else {
			entities.add_toast(app, "Failed to save map", .ERROR, 3.0)
		}
	}

	// Cargar mapa (Ctrl+O) → carga last_saved.map
	if ctrl && raylib.IsKeyPressed(.O) {
		editor_push_undo(app)
		if entities.map_load(&app.editor.game_map, "last_saved.map") {
			app.editor.current_biome = app.editor.game_map.biome
			simulation_fit_camera(app, f32(raylib.GetScreenWidth()), f32(raylib.GetScreenHeight()))
			entities.add_toast(app, "Map loaded! (Ctrl+O)", .SUCCESS, 2.0)
		} else {
			// Roll back the undo push since nothing changed
			if len(app.editor.undo_stack) > 0 {
				last := len(app.editor.undo_stack) - 1
				snap := app.editor.undo_stack[last]
				ordered_remove(&app.editor.undo_stack, last)
				entities.map_snapshot_destroy(&snap)
			}
			entities.add_toast(app, "No quick save found", .WARNING, 3.0)
		}
	}

	// Abrir/cerrar browser de mapas (Ctrl+B)
	if ctrl && raylib.IsKeyPressed(.B) {
		if app.editor.show_map_browser {
			entities.map_destroy(&app.editor.browser.preview)
			app.editor.browser.preview_valid = false
			if app.editor.browser.preview_tex_valid {
				raylib.UnloadRenderTexture(app.editor.browser.preview_tex)
				app.editor.browser.preview_tex_valid = false
			}
			app.editor.show_map_browser = false
		} else {
			entities.map_file_entries_destroy(&app.editor.browser.entries)
			app.editor.browser.entries = entities.map_list_saved_entries()
			app.editor.browser.scroll   = 0
			app.editor.browser.selected = -1
			app.editor.browser.preview  = entities.map_init()
			app.editor.browser.preview_valid = false
			app.editor.show_map_browser = true
		}
	}
}

// ─── Undo / Redo ─────────────────────────────────────────────────────────────

// Push the current map state onto the undo stack and clear the redo stack.
// Call this BEFORE making any change to the map (once per logical operation).
editor_push_undo :: proc(app: ^entities.App_State) {
	snap := entities.map_snapshot_save(&app.editor.game_map)
	append(&app.editor.undo_stack, snap)

	// Enforce history limit: drop the oldest entry
	if len(app.editor.undo_stack) > constants.EDITOR_MAX_HISTORY {
		entities.map_snapshot_destroy(&app.editor.undo_stack[0])
		ordered_remove(&app.editor.undo_stack, 0)
	}

	// Any new action invalidates the redo history
	for &s in app.editor.redo_stack {
		entities.map_snapshot_destroy(&s)
	}
	clear(&app.editor.redo_stack)
}

// Undo: restore the previous state.
editor_undo :: proc(app: ^entities.App_State) {
	if len(app.editor.undo_stack) == 0 {
		entities.add_toast(app, "Nothing to undo", .WARNING, 1.5)
		return
	}
	// Push current state onto redo stack before restoring
	redo_snap := entities.map_snapshot_save(&app.editor.game_map)
	append(&app.editor.redo_stack, redo_snap)

	// Pop from undo stack
	last := len(app.editor.undo_stack) - 1
	snap := app.editor.undo_stack[last]
	ordered_remove(&app.editor.undo_stack, last)

	entities.map_snapshot_restore(&app.editor.game_map, &snap)
	entities.map_snapshot_destroy(&snap)
	app.editor.current_biome = app.editor.game_map.biome
	terrain_cache_invalidate()
	entities.add_toast(app, "Undo", .INFO, 0.8)
	play_sound(.TICK, .UI)
}

// Redo: reapply the next state.
editor_redo :: proc(app: ^entities.App_State) {
	if len(app.editor.redo_stack) == 0 {
		entities.add_toast(app, "Nothing to redo", .WARNING, 1.5)
		return
	}
	// Push current state onto undo stack before restoring
	undo_snap := entities.map_snapshot_save(&app.editor.game_map)
	append(&app.editor.undo_stack, undo_snap)

	// Pop from redo stack
	last := len(app.editor.redo_stack) - 1
	snap := app.editor.redo_stack[last]
	ordered_remove(&app.editor.redo_stack, last)

	entities.map_snapshot_restore(&app.editor.game_map, &snap)
	entities.map_snapshot_destroy(&snap)
	app.editor.current_biome = app.editor.game_map.biome
	terrain_cache_invalidate()
	entities.add_toast(app, "Redo", .INFO, 0.8)
	play_sound(.TICK, .UI)
}

// ─────────────────────────────────────────────────────────────────────────────

// Convert tile type to tower type
tile_to_tower_type :: proc(tile: constants.Tile) -> constants.Tower_Type {
	#partial switch tile {
	case .TOWER_ARCHER:
		return .ARCHER
	case .TOWER_CANNON:
		return .CANNON
	case .TOWER_SNIPER:
		return .SNIPER
	case .TOWER_MISSILE:
		return .MISSILE
	case .TOWER_LASER:
		return .LASER
	case .TOWER_ICE:
		return .ICE
	case .TOWER_ENHANCE:
		return .ENHANCE
	case .TOWER_TESLA:
		return .TESLA
	case .TOWER_MORTAR:
		return .MORTAR
	case:
		return .ARCHER  // Default
	}
}

// Handle camera controls (zoom and pan)
input_handle_camera :: proc(app: ^entities.App_State) {
	if app.state == .PLAYING || app.state == .EDITOR {
		input_handle_camera_3d(app)
		return
	}

	// Zoom with mouse wheel (centered on mouse, continuous smooth zoom)
	wheel_movement := raylib.GetMouseWheelMove()
	if wheel_movement != 0 {
		mouse_x := raylib.GetMouseX()
		mouse_y := raylib.GetMouseY()

		// Use the current (interpolated) zoom and the current camera offset so that
		// the anchor cell is computed in the world that is actually being rendered.
		// This avoids the mismatch between app.zoom and app.target_zoom during animation.
		cs_cur := f32(app.settings.cell_size) * app.zoom

		// World position under mouse (fractional grid coordinates)
		world_x := (f32(mouse_x) - f32(app.camera_offset_x)) / cs_cur
		world_y := (f32(mouse_y) - f32(app.camera_offset_y)) / cs_cur

		// Update target zoom
		app.target_zoom += wheel_movement * constants.ZOOM_SPEED
		if app.target_zoom < constants.ZOOM_MIN { app.target_zoom = constants.ZOOM_MIN }
		if app.target_zoom > constants.ZOOM_MAX { app.target_zoom = constants.ZOOM_MAX }

		// Compute new camera offset so the same world position stays under the mouse
		cs_new := f32(app.settings.cell_size) * app.target_zoom
		app.target_camera_offset_x = i32(f32(mouse_x) - world_x * cs_new)
		app.target_camera_offset_y = i32(f32(mouse_y) - world_y * cs_new)
	}

	// Pan with middle mouse button
	if raylib.IsMouseButtonDown(.MIDDLE) {
		mouse_delta := raylib.GetMouseDelta()
		app.camera_offset_x += i32(mouse_delta.x)
		app.camera_offset_y += i32(mouse_delta.y)
		// Also update target offsets so they stay in sync during panning
		app.target_camera_offset_x = app.camera_offset_x
		app.target_camera_offset_y = app.camera_offset_y
	}
}

// Zoom + rotación para el mapa 3D (PLAYING/EDITOR). No hay pan ni
// zoom-to-cursor: camera_focus queda siempre en el centro del mapa
// (fijo salvo cuando simulation_fit_camera/default_focus lo recalculan al
// cargar un mapa) — el scroll solo achica/agranda la distancia, nunca
// desplaza el punto mirado. La rotación (botón central + drag) vive en
// input_handle_camera_orbit, llamada al final de esta función.
input_handle_camera_3d :: proc(app: ^entities.App_State) {
	wheel_movement := raylib.GetMouseWheelMove()
	if wheel_movement != 0 {
		app.target_zoom += wheel_movement * constants.ZOOM_SPEED
	}

	// Zoom continuo con los triggers del mando — LEFT_TRIGGER_1 acerca,
	// RIGHT_TRIGGER_1 aleja, mientras se mantienen apretados (más zoom =
	// más cerca, ver camera_distance_from_zoom).
	if _gamepad_index >= 0 {
		if raylib.IsGamepadButtonDown(_gamepad_index, .LEFT_TRIGGER_1) {
			app.target_zoom += constants.CAMERA_GAMEPAD_ZOOM_SPEED * app.delta_time
		}
		if raylib.IsGamepadButtonDown(_gamepad_index, .RIGHT_TRIGGER_1) {
			app.target_zoom -= constants.CAMERA_GAMEPAD_ZOOM_SPEED * app.delta_time
		}
	}

	if app.target_zoom < constants.ZOOM_MIN { app.target_zoom = constants.ZOOM_MIN }
	if app.target_zoom > constants.ZOOM_MAX { app.target_zoom = constants.ZOOM_MAX }

	input_handle_camera_orbit(app)
}

// Rotación de cámara por drag del botón central — gira app.camera_yaw en
// vivo mientras se mantiene apretado. El botón central no tiene ninguna
// acción de un solo click en este proyecto (a diferencia del derecho), así
// que no hace falta distinguir click de drag: cualquier movimiento con el
// botón apretado rota. Se llama desde PLAYING/EDITOR (acá arriba) y
// también desde PAUSED (input_handle_paused), que no pasa por
// input_handle_camera_3d.
input_handle_camera_orbit :: proc(app: ^entities.App_State) {
	mouse_x := raylib.GetMouseX()
	mouse_y := raylib.GetMouseY()
	if raylib.IsMouseButtonDown(.MIDDLE) && !ui_is_click_blocked(mouse_x, mouse_y) {
		app.camera_yaw -= raylib.GetMouseDelta().x * constants.CAMERA_ORBIT_SENSITIVITY
	}

	// Rotación continua con los triggers del mando — a diferencia del botón
	// central (que rota por delta de arrastre), acá se gira a velocidad
	// constante mientras el trigger sigue apretado.
	if _gamepad_index >= 0 {
		if raylib.IsGamepadButtonDown(_gamepad_index, .LEFT_TRIGGER_2) {
			app.camera_yaw -= constants.CAMERA_GAMEPAD_ORBIT_SPEED * app.delta_time
		}
		if raylib.IsGamepadButtonDown(_gamepad_index, .RIGHT_TRIGGER_2) {
			app.camera_yaw += constants.CAMERA_GAMEPAD_ORBIT_SPEED * app.delta_time
		}
	}
}
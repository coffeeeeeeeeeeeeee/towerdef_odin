package entities

import "core:mem"
import "core:os"
import "core:strings"
import "core:time"
import "../constants"

// ─────────────────────────────────────────────────────────────────────────────
// Campaña — definición autoría por el dev, distribuida con el juego.
//
// Sigue el mismo patrón que Meta_State / savegame.bin: una estructura de
// tamaño fijo, serializada directo a disco con mem.ptr_to_bytes. El header
// `version` permite migraciones futuras (bump CAMPAIGN_SAVE_VERSION y al
// cargar tratamos las versiones viejas como inválidas hasta que escribamos
// la migración explícita).
//
// Modelo: una secuencia lineal de nodos. Cada nodo apunta opcionalmente a
// un nodo predecesor vía `requires_node`. El nodo con `requires_node = -1`
// es el inicial. El flag .OPTIONAL marca nodos que cuelgan del main path
// sin gating: el siguiente nodo del main se desbloquea por su predecesor
// directo, no por sus opcionales.
// ─────────────────────────────────────────────────────────────────────────────

CAMPAIGN_SAVE_VERSION :: u32(1)
CAMPAIGN_SAVE_PATH    :: "campaign.bin"

// Flags por nodo — combinables vía bit_set. Se serializan como u32.
Campaign_Node_Flag :: enum u8 {
	BOSS,      // nodo de jefe (visual destacado, recompensa mayor)
	OPTIONAL,  // no bloquea el main path
	STORY,     // muestra texto/diálogo antes de jugar
	FINALE,    // último nodo de la campaña
}
Campaign_Node_Flags :: bit_set[Campaign_Node_Flag; u32]

// Un nodo de la campaña. Tamaño fijo para serialización directa.
Campaign_Node :: struct {
	map_filename:     [constants.CAMPAIGN_MAP_NAME_LEN]u8,  // sin extensión .map
	display_name:     [constants.CAMPAIGN_DISPLAY_LEN]u8,
	pos_x:            f32,                                   // [0..1] en el canvas del visualizador
	pos_y:            f32,
	flags:            Campaign_Node_Flags,
	difficulty_mult:  f32,                                   // multiplicador de HP/speed enemigo
	waves_override:   i32,                                   // 0 = usa RUN_MAX_WAVES
	requires_node:    i32,                                   // índice del nodo predecesor; -1 = inicial
	reward_cristales: i32,                                   // bonus al completar (encima del estándar)
	_pad:             [16]u8,                                // reserva para futuros campos sin bumpear versión
}

// Archivo completo de campaña. Tamaño fijo.
Campaign_File :: struct {
	version:    u32,
	_pad_head:  [4]u8,                                       // alineación
	name:       [constants.CAMPAIGN_DISPLAY_LEN]u8,
	node_count: i32,
	nodes:      [constants.CAMPAIGN_MAX_NODES]Campaign_Node,
	_pad:       [128]u8,                                     // reserva para futuro
}

// ─────────────────────────────────────────────────────────────────────────────
// Save / Load
// ─────────────────────────────────────────────────────────────────────────────

// Persiste la campaña al archivo CAMPAIGN_SAVE_PATH.
campaign_save :: proc(c: ^Campaign_File) -> bool {
	c.version = CAMPAIGN_SAVE_VERSION
	data := mem.ptr_to_bytes(c)
	return os.write_entire_file(CAMPAIGN_SAVE_PATH, data)
}

// Devuelve el mtime del archivo de campaña como i64 (nanosegundos desde el
// epoch) o 0 si el archivo no existe. Usado por el hot-reload en DEVELOPER.
campaign_file_mtime :: proc() -> i64 {
	fd, err := os.open(CAMPAIGN_SAVE_PATH)
	if err != os.ERROR_NONE { return 0 }
	defer os.close(fd)
	fi, fstat_err := os.fstat(fd)
	if fstat_err != os.ERROR_NONE { return 0 }
	defer delete(fi.fullpath)
	return time.time_to_unix_nano(fi.modification_time)
}

// Carga la campaña desde CAMPAIGN_SAVE_PATH. Devuelve la struct cargada y
// un bool ok=true si el archivo existe y su versión/tamaño matchean.
// En cualquier error devuelve una Campaign_File vacía y ok=false.
campaign_load :: proc() -> (Campaign_File, bool) {
	c := Campaign_File{}
	data, read_ok := os.read_entire_file_from_filename(CAMPAIGN_SAVE_PATH)
	if !read_ok { return c, false }
	defer delete(data)

	if len(data) != size_of(Campaign_File) { return c, false }
	c = (cast(^Campaign_File)raw_data(data))^
	if c.version != CAMPAIGN_SAVE_VERSION { return Campaign_File{}, false }
	if c.node_count < 0 || c.node_count > i32(constants.CAMPAIGN_MAX_NODES) {
		return Campaign_File{}, false
	}
	return c, true
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers — operan sobre Campaign_File / Campaign_Node
// ─────────────────────────────────────────────────────────────────────────────

// Lee un campo [N]u8 como string Odin (truncando en el primer NUL o llenando
// hasta el tope si no hay NUL). El resultado vive en el slice subyacente del
// buffer pasado, así que no necesita liberación.
campaign_bytes_to_string :: proc(buf: []u8) -> string {
	n := 0
	for b in buf {
		if b == 0 { break }
		n += 1
	}
	return string(buf[:n])
}

// Escribe un string en un buffer [N]u8 fijo, truncando al tamaño y rellenando
// con NUL. Devuelve la cantidad de bytes copiados.
campaign_string_to_bytes :: proc(buf: []u8, s: string) -> int {
	n := len(s)
	if n > len(buf) { n = len(buf) }
	for i in 0 ..< n { buf[i] = s[i] }
	for i in n ..< len(buf) { buf[i] = 0 }
	return n
}

// Devuelve el nombre del archivo del mapa de un nodo como string.
campaign_node_map_filename :: proc(node: ^Campaign_Node) -> string {
	return campaign_bytes_to_string(node.map_filename[:])
}

// Devuelve el display name de un nodo como string.
campaign_node_display_name :: proc(node: ^Campaign_Node) -> string {
	return campaign_bytes_to_string(node.display_name[:])
}

// Devuelve el nombre de la campaña como string.
campaign_name :: proc(c: ^Campaign_File) -> string {
	return campaign_bytes_to_string(c.name[:])
}

// Determina si un nodo está desbloqueado según el progreso del jugador.
// Reglas:
//   - El nodo inicial (requires_node = -1) siempre desbloqueado.
//   - Un nodo se desbloquea cuando su requires_node está completado.
//   - El completion array vive en Meta_State.campaign_completed.
campaign_is_node_unlocked :: proc(c: ^Campaign_File, completed: []bool, node_idx: int) -> bool {
	if node_idx < 0 || node_idx >= int(c.node_count) { return false }
	node := &c.nodes[node_idx]
	if node.requires_node < 0 { return true }  // inicial
	req := int(node.requires_node)
	if req < 0 || req >= len(completed) { return false }
	return completed[req]
}

// Devuelve true si todos los nodos NO opcionales del main path están completos.
campaign_is_complete :: proc(c: ^Campaign_File, completed: []bool) -> bool {
	for i in 0 ..< int(c.node_count) {
		if .OPTIONAL in c.nodes[i].flags { continue }
		if i >= len(completed) || !completed[i] { return false }
	}
	return true
}

// Cuenta nodos completados (incluyendo opcionales).
campaign_completed_count :: proc(c: ^Campaign_File, completed: []bool) -> i32 {
	n := i32(0)
	for i in 0 ..< int(c.node_count) {
		if i < len(completed) && completed[i] { n += 1 }
	}
	return n
}

// Cuenta nodos NO opcionales (tamaño del main path).
campaign_main_path_size :: proc(c: ^Campaign_File) -> i32 {
	n := i32(0)
	for i in 0 ..< int(c.node_count) {
		if !(.OPTIONAL in c.nodes[i].flags) { n += 1 }
	}
	return n
}

// Crea un nodo nuevo con defaults sanos. Usado por el campaign editor cuando
// el dev arrastra un mapa del browser al canvas.
campaign_node_init :: proc(map_filename: string, display: string, pos_x, pos_y: f32) -> Campaign_Node {
	node := Campaign_Node{
		pos_x            = pos_x,
		pos_y            = pos_y,
		flags            = {},
		difficulty_mult  = constants.CAMPAIGN_DEFAULT_DIFFICULTY,
		waves_override   = constants.CAMPAIGN_DEFAULT_WAVES,
		requires_node    = -1,
		reward_cristales = 0,
	}
	campaign_string_to_bytes(node.map_filename[:], map_filename)

	// Si no hay display name, usar el filename como fallback.
	display_to_use := display
	if len(strings.trim_space(display_to_use)) == 0 {
		display_to_use = map_filename
	}
	campaign_string_to_bytes(node.display_name[:], display_to_use)
	return node
}

// Agrega un nodo al final de la lista de la campaña. Retorna el índice del nodo
// añadido, o -1 si la campaña está llena.
campaign_append_node :: proc(c: ^Campaign_File, node: Campaign_Node) -> i32 {
	if c.node_count >= i32(constants.CAMPAIGN_MAX_NODES) { return -1 }
	idx := c.node_count
	c.nodes[idx] = node
	c.node_count += 1
	return idx
}

// Elimina un nodo por índice, deslizando los siguientes una posición hacia
// adelante. Reajusta los requires_node de todos los nodos para que apunten al
// índice correcto post-eliminación (los que dependían del nodo borrado pierden
// su predecesor — se setea a -1).
campaign_remove_node :: proc(c: ^Campaign_File, idx: i32) -> bool {
	if idx < 0 || idx >= c.node_count { return false }

	// Reajustar referencias en los nodos restantes
	for i in 0 ..< int(c.node_count) {
		if i32(i) == idx { continue }
		req := c.nodes[i].requires_node
		if req == idx {
			c.nodes[i].requires_node = -1  // perdió su predecesor
		} else if req > idx {
			c.nodes[i].requires_node = req - 1  // desplazado por la eliminación
		}
	}

	// Deslizar los nodos posteriores
	for i := idx; i < c.node_count - 1; i += 1 {
		c.nodes[i] = c.nodes[i + 1]
	}
	c.node_count -= 1
	// Limpiar el slot liberado al final
	c.nodes[c.node_count] = Campaign_Node{}
	return true
}

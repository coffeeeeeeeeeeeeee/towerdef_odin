Esta carpeta contiene los archivos necesarios para compilar un juego en el lenguaje Odin. El juego es un juego de defensa de torres minimalista con un sistema de mazo de cartas al estilo Balatro. Contiene un archivo constants.odin donde se encuentran las principales variables de márgenes, colores, timers, etc. Cada vez que agregues un texto que se lea en pantalla ten en cuenta que debes agregar una traducción en translations.txt

## Estructura de archivos de rendering (systems/)

El renderizado está dividido en tres archivos dentro de `systems/`, todos en `package systems`:

| Archivo | Responsabilidad |
|---|---|
| `rendering.odin` | Mundo y mapa: `render_game`, `render_map`, tiles, enemigos, proyectiles, torres, obstáculos |
| `interface.odin` | Widgets reutilizables: `render_button`, `render_card`, `render_panel`, `render_tooltip`, `render_select`, `render_slider`, gestión de `ui_click_blocks` / `ui_modal_blocks`, constantes `CARD_W/H/GAP`, helpers de rareza |
| `menus.odin` | Pantallas y HUD: `render_ui`, `render_game_ui`, `render_menu_ui`, `render_game_over_ui`, shop overlay, mano de cartas, paneles de control |

Al agregar una proc nueva, usar esta guía para decidir en qué archivo va:
- ¿Dibuja algo del mundo del juego (mapa, enemigos, torres)? → `rendering.odin`
- ¿Es un widget genérico reutilizable sin lógica de juego? → `interface.odin`
- ¿Es una pantalla, overlay o HUD con lógica de estado de juego? → `menus.odin`

## Sistema de UI blocking (ui_click_blocks / ui_modal_blocks)

`ui_blocks_clear()` se llama al inicio de cada frame desde `render_game`.

- **`ui_click_blocks`**: impide que los clicks lleguen a la grilla del mapa (chequeado en `input.odin`). Todos los botones y cartas se auto-registran al renderizarse.
- **`ui_modal_blocks`**: impide que botones de capas inferiores respondan. Se usa para el shop overlay: `render_ui` agrega un rect pantalla-completa a `ui_modal_blocks` cuando el shop está activo, bloqueando la UI de juego subyacente.

### ⚠️ Trampa conocida: modal blocks y el shop overlay

`render_card_selection_overlay` llama a `clear(&ui_modal_blocks)` al inicio porque:
1. `render_ui` ya agregó el rect pantalla-completa antes de renderizar la UI de juego.
2. Esa UI ya fue procesada (y bloqueada correctamente).
3. Sin el `clear`, los botones del propio shop también quedarían bloqueados.

No mover ni eliminar ese `clear(&ui_modal_blocks)` sin entender este flujo.

## Shop de cartas

El shop se abre automáticamente entre oleadas (`card_selection_active = true`).

- El jugador puede comprar **múltiples cartas** en una sola visita mientras tenga dinero.
- Hacer click directamente sobre una carta la compra (no hay botón "Comprar" separado).
- Las cartas ya compradas quedan en gris con etiqueta "Comprado" — no se pueden volver a comprar en esa visita.
- El shop se cierra solo con el botón **Skip** (llama a `hand_refresh` y resetea `card_selection_bought`).
- El reroll genera cartas nuevas y resetea `card_selection_bought` automáticamente (en `generate_card_selection`).
- **`card_selection_bought: [3]bool`** en `Simulation` rastrea qué slots fueron comprados en la visita actual.

## Conversión de strings a cstring (patrón estándar)

En Odin, Raylib requiere `cstring` en muchas APIs de dibujo/texto. El patrón estándar en este proyecto es usar **`context.temp_allocator`** para estas conversiones temporales — nunca se debe llamar a `strings.clone_to_cstring(s)` sin asignador, ya que eso requiere un `defer delete(...)` manual y lleva a memory leaks si se omite.

### Reglas

1. **String simple a cstring** → usar `strings.clone_to_cstring(s, context.temp_allocator)`
   ```odin
   // CORRECTO
   raylib.DrawTextEx(font, strings.clone_to_cstring(label, context.temp_allocator), pos, size, 0, color)

   // MAL — leak si no hay defer delete
   cstr := strings.clone_to_cstring(label)
   defer delete(cstr)
   ```

2. **String formateado a cstring** → usar `fmt.ctprintf(...)` directamente
   ```odin
   // CORRECTO — ctprintf usa context.temp_allocator internamente
   raylib.DrawTextEx(font, fmt.ctprintf("Wave: %d", wave), pos, size, 0, color)

   // MAL — dos allocations innecesarias
   s := fmt.tprintf("Wave: %d", wave)
   cstr := strings.clone_to_cstring(s)
   defer delete(cstr)
   ```

3. **Literal de string** → cast directo, sin allocation
   ```odin
   // CORRECTO — los string literals en Odin son null-terminated
   raylib.DrawTextEx(font, cstring("Hello"), pos, size, 0, color)
   ```

### Ciclo de vida

El `context.temp_allocator` (arena/ring-buffer) se limpia **una vez por frame** al final del game loop en `main.odin`:
```odin
raylib.EndDrawing()
free_all(context.temp_allocator)  // libera todo lo acumulado en el frame
```

Esto significa que cualquier cstring obtenido con `context.temp_allocator` es válido durante **todo el frame** en que fue creado. No se necesita `defer delete`.

### ⚠️ Regla crítica: strings que viven más que un frame

**NUNCA** usar `fmt.tprintf` o `context.temp_allocator` para strings que deben persistir más allá del frame actual (p. ej. claves de maps, buffers globales, campos de structs). Para esos casos usar:

- `fmt.aprintf(...)` — heap, persiste hasta `delete()` explícito
- `strings.clone(s)` — heap, persiste hasta `delete()` explícito

```odin
// MAL — la clave queda inválida después del primer free_all(context.temp_allocator)
compound_key := fmt.tprintf("%s|%s", lang, key)
my_map[compound_key] = value

// CORRECTO — vive en el heap hasta que se destruya el map
compound_key := fmt.aprintf("%s|%s", lang, key)
my_map[compound_key] = value
```

El `init_translations` en `translations.odin` sigue este patrón: usa `fmt.aprintf` para las claves del map `TRANSLATIONS` y `strings.clone` para los valores.

## render_tower_ranges (systems/rendering.odin)

Dibuja los círculos de rango de torres como capa separada, entre `render_map` y `render_map_objects`. Se llama desde `render_game` cada frame.

### Dos modos

1. **Todas las torres** (cuando `app.settings.show_tower_range` está activo): dibuja solo el relleno semitransparente (`TOWER_RANGE_PREVIEW`, alpha=30) para cada torre.

2. **Torre seleccionada** (siempre, independientemente del setting): dibuja relleno sutil + **outline nítido** (`DrawCircleLines`, alpha=200). El outline es la parte visualmente dominante — sin él, el rango es prácticamente invisible.

### ⚠️ Trampa conocida

Al editar el bloque de la torre seleccionada, es fácil perder el `DrawCircleLines` si se reemplaza solo parte del bloque. **Siempre verificar que existan ambas llamadas**:

```odin
// Torre seleccionada — ambas líneas son necesarias
raylib.DrawCircle(cx_i, cy_i, range_px, constants.TOWER_RANGE_PREVIEW)       // relleno (alpha=30, casi invisible solo)
raylib.DrawCircleLines(cx_i, cy_i, range_px, raylib.Color{255, 255, 255, 200}) // outline (es lo que el usuario ve)
```

Si solo queda `DrawCircle` con `TOWER_RANGE_PREVIEW`, el círculo existe pero el usuario no lo ve.

### Variables de color (constants.odin)

```odin
TOWER_RANGE_PREVIEW :: raylib.Color{255, 255, 255, 30}  // relleno muy tenue
TOWER_RANGE_OUTLINE :: raylib.Color{255, 255, 255, 60}  // outline para el modo "todas las torres" (no se usa en selección)
```

El modo selección usa `Color{255, 255, 255, 200}` directamente (más visible que `TOWER_RANGE_OUTLINE`).

## Sistema de reliquias

Las reliquias son cartas especiales (`is_relic = true`) que aplican efectos permanentes acumulables. Están definidas en `entities/card.odin`.

### Reliquias implementadas

| Relic Kind       | Campo en Simulation      | Efecto                                                              |
|------------------|--------------------------|---------------------------------------------------------------------|
| INTEREST_BOOST   | `interest_stacks`        | +interés por oleada × stacks                                        |
| DIVIDEND         | `dividend_stacks`        | bonificación al final de oleada basada en dinero guardado           |
| STEAL            | `steal_stacks`           | roba N cartas al terminar cada oleada (via `steal_last_wave`)       |
| WEAKEN           | `weaken_stacks`          | enemigos tienen -HP × stacks al spawnear                            |
| AUTO_UPGRADE     | `auto_stacks`            | auto-upgradea torres Y obstáculos cada AUTO_UPGRADE_INTERVAL        |
| BLOODLUST        | `bloodlust_stacks`       | cada kill suma BLOODLUST_BONUS_PER_KILL × stacks a `bloodlust_mult` |
| FLAWLESS         | `flawless_stacks`        | +FLAWLESS_BONUS × stacks por oleada completada sin perder vidas     |
| FORMATION        | `formation_stacks`       | +FORMATION_BONUS de daño si 3+ torres del mismo tipo en línea       |
| FROZEN_AMP       | `frozen_amp_stacks`      | +FROZEN_AMP_BONUS de daño contra enemigos ralentizados              |

### Iteración para renderizar el tray de reliquias

`RELIC_KINDS` en `rendering.odin` es un slice ordenado de `Card_Kind` usados para iterar las reliquias activas. Al agregar una nueva reliquia, añadirla a este slice.

### Prevención de activación múltiple

El flag `relic_activated_this_frame` (en el loop de render de la mano) evita que un solo click active varias reliquias si el cursor queda sobre otro ítem al remover una carta de la mano.

### STEAL — timing

STEAL se dispara en `update_wave` (cuando todos los enemigos mueren), **no** en `start_next_wave`. El campo `steal_last_wave` previene disparos duplicados por frame.

### Daño global — calc_damage

```odin
calc_damage :: proc(app, base, source_tower, enemy) -> f32
```

Aplica en orden: `bloodlust_mult`, Formation bonus (si `tower_is_in_formation`), Frozen Amp bonus (si enemigo tiene slow). Se llama en todos los sitios de daño: ICE, laser, proyectil directo, proyectil AoE.

## Obstáculos en el camino

### Orientación visual automática

`obstacle_bar_dims(m, row, col, cs)` determina las dimensiones de la barrera según si el camino en esa celda es horizontal o vertical. Esta función se usa tanto en `render_obstacles` (obstáculos reales) como en `draw_obstacle_preview` / `draw_obstacle_preview_invalid` (ghost al colocar), garantizando coherencia visual.

### Restricción de esquinas y uniones

`map_is_path_corner_or_junction(m, row, col)` devuelve `true` si la celda es una esquina o bifurcación del camino. Los obstáculos no se pueden colocar en esas celdas — el ghost se renderiza en rojo con una X.

Criterio: ≥ 3 vecinos path = junction; 2 vecinos no opuestos = corner.

## Sistema de victoria / derrota

- **Derrota**: `app.sim.health <= 0` → `app_set_state(.GAME_OVER)`, `sim.is_victory = false`
- **Victoria**: se completa la oleada `MAX_WAVE` con salud restante → `sim.is_victory = true`, `app_set_state(.GAME_OVER)`
- En `render_game_over_ui`: si `sim.is_victory`, el título usa la clave `GAME_VICTORY_TITLE` en verde; si no, `GAME_OVER_TITLE` en rojo.

## Botón "Siguiente Oleada"

`show_next_wave_button := !app.settings.auto_start_wave && can_start_wave`

Solo se renderiza cuando auto-oleada está desactivada **y** la oleada actual ya terminó. Desaparece mientras hay enemigos vivos.

## Stats de partida

- `towers_built` se incrementa en `input.odin` al colocar una torre (no en `simulation.odin`).
- `upgrades_bought` se incrementa al comprar un upgrade de torre.
- `money_earned` se acumula en `app_add_money`.
- Los stats se renderizan como un slice de `Stat_Row` en `render_game_over_ui`, por lo que agregar un nuevo stat no requiere actualizar un contador manual.

## Toasts

- Se posicionan con `margin_top = constants.UI_MARGIN_Y` (valor 8) en `entities/toast.odin`.
- Solo el primer toast de la cola (`toasts[0]`) se anima y renderiza. Los siguientes esperan con `creation_time = 0` como sentinel.

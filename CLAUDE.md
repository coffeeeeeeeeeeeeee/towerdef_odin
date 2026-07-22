# CLAUDE.md

> Este archivo es un resumen vivo del proyecto. Actualizarlo cada vez que se
> agreguen sistemas, se cambien mecánicas importantes, o se descubran trampas
> no obvias del código — no dejar que quede desactualizado.

## Qué es esto

Tower defense en **Odin + Raylib**, con un sistema de mazo de cartas /
reliquias al estilo roguelike deck-builder (Balatro). No es un TD clásico:
además de construir y mejorar torres, el jugador compra cartas entre oleadas
(shop), arma una mano de reliquias pasivas/activas, y progresa a través de un
sistema de campaña con meta-progresión persistente entre partidas.

El `README.md` describe una versión más simple/antigua del juego (sin modo
campaña, sin cartas) — está desactualizado. Este archivo refleja el estado
real del código.

## Compilar y correr

Requiere el compilador de Odin (trae Raylib vendorizada, no hace falta
instalar Raylib aparte).

```bash
# Desde la raíz del proyecto
odin run . -out:towerdef      # compila y corre
odin build . -out:towerdef    # solo compila
odin build . -out:towerdef -opt:3   # build de release
```

En Windows es el mismo comando, agregando `.exe` al `-out:`. Las APIs de
`core:os` usadas en el proyecto (`read_entire_file_from_path`, `read_dir`,
`fstat`, `write_entire_file`, `File_Info.type`) y los bindings de
`vendor:raylib` no están gateados por plataforma, así que el mismo código
compila igual en Linux/Windows/Mac.

**Nota de compatibilidad:** Odin es rolling-release sin versiones estables.
Si el compilador instalado es más nuevo que el último commit del proyecto,
pueden aparecer errores de compilación por APIs de `core:os` que cambiaron
de firma. Ver el commit `6f8034f` para un ejemplo de los parches típicos que
hacen falta (allocator explícito en `read_dir`/`fstat`, `Error` en vez de
`bool` en `write_entire_file`, etc).

## Estructura del proyecto

```
towerdef_odin/
├── main.odin              # Entry point, game loop, save/load de settings
├── constants/
│   ├── constants.odin      # Enums, specs de torres/enemigos, colores, timers, tamaños de grilla
│   ├── fonts.odin
│   └── translations.odin   # Carga translations.txt (i18n por clave)
├── entities/
│   ├── app.odin            # App_State global, Game_State (enum de pantallas)
│   ├── tower.odin           # Torres y specs
│   ├── enemy.odin           # Enemigos y pathfinding
│   ├── projectile.odin      # Proyectiles y misiles
│   ├── laser.odin           # Sistema de láser
│   ├── map.odin             # Grid, obstáculos, spawn points, save/load de mapas (.map)
│   ├── card.odin            # Card_Kind (torres, obstáculos, reliquias), RELIC_SPECS
│   ├── campaign.odin        # Nodos de campaña, save/load (campaign.bin)
│   ├── meta.odin            # Meta-progresión persistente (cristales, unlocks) entre runs
│   ├── explosion.odin       # Explosiones y números de daño
│   ├── toast.odin           # Notificaciones flotantes
│   ├── console.odin
│   └── input.odin
├── systems/
│   ├── simulation.odin      # updateSimulation, shop, oleadas, daño (calc_damage)
│   ├── rendering.odin       # Mundo/mapa: render_game, render_map, tiles, enemigos, torres
│   ├── interface.odin       # Widgets reutilizables: render_button, render_card, render_panel, tooltip
│   ├── menus.odin           # Pantallas y HUD: render_ui, shop overlay, mano de cartas
│   ├── input.odin           # Manejo de input
│   ├── audio.odin           # Carga dinámica de música/sfx desde music/ y audio/
│   ├── campaign.odin
│   ├── console.odin
│   └── ui.odin
├── maps/                    # Mapas guardados (.map)
├── images/, fonts/, audio/, music/  # Assets
├── translations.txt         # Strings de UI por idioma (clave → traducción)
├── docs/assets.md
├── campaign.bin, savegame.bin, settings.bin  # Estado persistido (no versionar cambios manuales)
└── towerdef_odin.exe / towerdef  # Binarios compilados (no trackeados en git salvo el .exe legacy)
```

## Convención de rendering (systems/)

Al agregar una proc nueva de dibujo, decidir el archivo según qué hace:
- ¿Dibuja algo del mundo (mapa, enemigos, torres)? → `rendering.odin`
- ¿Es un widget genérico sin lógica de juego? → `interface.odin`
- ¿Es una pantalla, overlay o HUD con lógica de estado? → `menus.odin`

## i18n

Cada texto nuevo que se muestre en pantalla necesita su traducción agregada
en `translations.txt` (formato clave por idioma). `init_translations`
(`constants/translations.odin`) carga esto una vez al inicio.

## Sistema de reliquias (cartas especiales)

Definidas en `entities/card.odin` (`Card_Kind`, `RELIC_SPECS`). Hay dos tipos:

- **Passive**: se aplican de inmediato al comprarlas, efecto permanente y
  global (stacks en `relic_stacks[.KIND]`), aparecen en la lista de
  reliquias pasivas a la izquierda de la pantalla. Ej: `CRYPTOBRO`.
- **Active**: van a la mano del jugador como carta (`card_add_to_hand`) y se
  aplican a un tile específico del mapa vía `pending_tower_action`. Ej:
  `LUMBERJACK`, `OVERDRIVE`, `GARDENER`.

En `shop_perform_buy` (`systems/simulation.odin`), las reliquias activas se
identifican con el flag `is_action_relic` y se rutean a la mano; las
pasivas llaman `apply_relic_card` directamente.

`RELIC_KINDS` en `rendering.odin` es el slice ordenado que itera las
reliquias activas para el tray — agregar ahí cualquier reliquia nueva.

Daño global pasa por `calc_damage(app, base, source_tower, enemy)`, que
aplica en orden: `bloodlust_mult`, bonus de Formation (si
`tower_is_in_formation`), bonus de Frozen Amp (si el enemigo está
ralentizado). Se llama en todos los sitios de daño (ICE, láser, proyectil
directo, proyectil AoE).

## Shop de cartas

Se abre automáticamente entre oleadas (`card_selection_active = true`).
- Se pueden comprar múltiples cartas en una visita mientras haya dinero.
- Click directo sobre la carta la compra (no hay botón "Comprar").
- Cartas ya compradas quedan en gris con "Comprado" (`card_selection_bought: [3]bool`).
- Se cierra solo con el botón **Skip** (llama `hand_refresh`, resetea `card_selection_bought`).
- El reroll genera cartas nuevas y resetea `card_selection_bought` (`generate_card_selection`).

## Sistema de UI blocking

`ui_blocks_clear()` se llama al inicio de cada frame desde `render_game`.
- **`ui_click_blocks`**: evita que los clicks lleguen a la grilla del mapa
  (chequeado en `input.odin`). Botones y cartas se auto-registran al
  renderizarse.
- **`ui_modal_blocks`**: evita que botones de capas inferiores respondan.
  Usado por el shop overlay (`render_ui` agrega un rect pantalla-completa
  cuando el shop está activo).

## Conversión string → cstring (patrón obligatorio)

Raylib requiere `cstring` en varias APIs de texto/dibujo. Usar siempre
`context.temp_allocator` para conversiones que solo viven el frame actual —
nunca `strings.clone_to_cstring(s)` sin allocator (leak si se olvida el
`defer delete`).

- String simple → `strings.clone_to_cstring(s, context.temp_allocator)`
- String formateado → `fmt.ctprintf(...)` (usa temp_allocator internamente)
- Literal → cast directo `cstring("Hello")`

`context.temp_allocator` se limpia una vez por frame en `main.odin`
(`free_all(context.temp_allocator)` después de `EndDrawing()`), así que
cualquier cstring de temp_allocator es válido durante todo el frame.

**Strings que viven más de un frame** (claves de maps, buffers globales,
campos de structs) → usar `fmt.aprintf(...)` o `strings.clone(s)` (heap,
requieren `delete()` explícito). Ver `init_translations` como ejemplo.

## Obstáculos en el camino

- `obstacle_bar_dims(m, row, col, cs)` determina dimensiones de la barrera
  según si el camino es horizontal o vertical en esa celda — se usa tanto
  para obstáculos reales como para el ghost de preview, para coherencia visual.
- `map_is_path_corner_or_junction(m, row, col)` — `true` si la celda es
  esquina o bifurcación del camino; ahí no se pueden colocar obstáculos (el
  ghost se pinta rojo con X). Criterio: ≥3 vecinos path = junction, 2
  vecinos no opuestos = corner.

## Victoria / derrota

- Derrota: `app.sim.health <= 0` → `app_set_state(.GAME_OVER)`, `is_victory = false`.
- Victoria: se completa la oleada `RUN_MAX_WAVES` con salud restante → `is_victory = true`.
- `render_game_over_ui` usa `GAME_VICTORY_TITLE` (verde) o `GAME_OVER_TITLE` (rojo) según `is_victory`.

## Trampas conocidas

### Card Hand: botón de vender vs. click handler (`systems/menus.odin`)

**Síntoma:** cartas de reliquia activa (LUMBERJACK, OVERDRIVE, GARDENER, y
cualquier futura reliquia activa) parecen no poder venderse desde la mano.

**Causa raíz:** en `render_card_hand` (pasada 2), el click handler de la
carta corre **antes** que `render_button` del botón de vender, en el mismo
frame. Si el mouse está sobre el botón de vender, el click handler dispara
primero y activa el modo pendiente de la carta (`pending_tower_action =
.KIND`, `selected_card_idx = i`), y entonces `card_is_pending` da `true` y
el botón de vender se salta. Además los 8px inferiores del botón de vender
caen fuera del rect de hover (`card_y` a `card_y + CARD_H`).

**Fix ya aplicado:** `sell_rect` se calcula antes del click handler; un
check `mouse_on_sell` guarda todo el bloque de activación (si el mouse está
sobre vender, se salta el click handler). Hover extendido con
`HOVER_DETECTION_EXTRA = 8` px hacia abajo.

**Regla para reliquias activas nuevas:** cualquier `Card_Kind` nuevo que
active vía `pending_tower_action` debe agregarse al chain `else if
card.kind == .X` dentro del guard `!mouse_on_sell`. No hace falta nada más
para compatibilidad con el botón de vender.

### render_tower_ranges (systems/rendering.odin)

Dibuja los círculos de rango de torres como capa separada entre `render_map`
y `render_map_objects`, llamado cada frame desde `render_game`.

- Modo "todas las torres" (`show_tower_range` activo): solo relleno
  semitransparente (`TOWER_RANGE_PREVIEW`, alpha=30).
- Torre seleccionada (siempre): relleno sutil + **outline nítido**
  (`DrawCircleLines`, alpha=200) — el outline es la parte que realmente se
  ve; sin él el rango es casi invisible.

**Trampa:** al editar el bloque de la torre seleccionada es fácil borrar el
`DrawCircleLines` si se reemplaza solo parte del bloque. Verificar que
ambas llamadas sigan presentes.

### Shop overlay y `ui_modal_blocks`

`render_card_selection_overlay` llama `clear(&ui_modal_blocks)` al empezar
porque `render_ui` ya agregó el rect pantalla-completa antes (bloqueando
correctamente la UI de juego subyacente); sin el `clear`, los botones del
propio shop también quedarían bloqueados. No tocar ese `clear` sin entender
el flujo completo.

## Otros detalles puntuales

- `towers_built` se incrementa en `input.odin` al colocar una torre (no en
  `simulation.odin`); `upgrades_bought` al comprar upgrade; `money_earned`
  en `app_add_money`. Los stats de fin de partida son un slice de
  `Stat_Row` en `render_game_over_ui` — agregar un stat nuevo no requiere
  tocar un contador manual aparte.
- STEAL se dispara en `update_wave` (cuando mueren todos los enemigos), no
  en `start_next_wave`; `steal_last_wave` evita disparos duplicados.
- Toasts: solo `toasts[0]` se anima/renderiza; el resto espera con
  `creation_time = 0` como sentinel.
- Botón "Siguiente Oleada" (`show_next_wave_button`) solo se renderiza si
  `!app.settings.auto_start_wave && can_start_wave` — desaparece mientras
  hay enemigos vivos.

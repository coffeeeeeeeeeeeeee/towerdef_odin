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
├── assets/                  # Shaders GLSL (water.glsl, path.glsl, nebula.glsl, ...)
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

El tray de reliquias pasivas (`systems/menus.odin`) itera directamente
`entities.RELIC_SPECS` y filtra por `entities.relic_stacks(&app.sim, kind)
> 0` — cualquier reliquia agregada a `RELIC_SPECS` (`entities/card.odin`)
aparece automáticamente ahí sin tocar el renderer.

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
- Costo de reroll: `shop_next_reroll_cost` (`systems/menus.odin`), progresivo según
  `constants.SHOP_REROLL_COSTS` (`[0, 30, 75, 150]`, index = `rerolls_this_visit`,
  clampeado al último valor). El bioma MOUNTAIN (`BIOME_SHOP_MODS.free_reroll`)
  da los primeros `constants.MOUNTAIN_FREE_REROLLS` (2) rerolls gratis por
  visita; de ahí en más cobra la misma curva que cualquier otro bioma.

### Venta de cartas de la mano

`card_sell_price` (`entities/card.odin`) devuelve el 100% del precio de
tienda (`card_shop_price`) — vender reintegra exactamente lo pagado. Se
vende con **clic derecho** sobre la carta en `render_card_hand`
(`systems/menus.odin`); no hay botón. Funciona incluso con el shop abierto
(el hover de la mano ignora `ui_modal_blocks`, solo respeta
`app.confirm_modal.active`).

**Trampa:** si el jugador tiene una carta "armada" (torre/obstáculo
seleccionado para colocar — `selected_build_tower != .EMPTY` — o una
reliquia activa con objetivo pendiente — `pending_tower_action != .TOWER`),
vender una carta **distinta** desincroniza `selected_card_idx`: `card_play`
hace `ordered_remove` sobre la mano, corriendo el índice de todo lo que
está después. Los sitios que consumen `selected_card_idx` más tarde
(`systems/input.odin`, casos LUMBERJACK/OVERDRIVE/GARDENER/torre/obstáculo)
no revalidan el índice — en el peor caso (`selected_card_idx` apuntaba a la
última carta) es un panic por índice fuera de rango; si no, consume la
carta equivocada. El guard en `render_card_hand` (`something_armed` +
`can_sell`) bloquea vender cualquier carta que no sea la armada mientras
algo esté pendiente — permite vender la carta armada misma (cancela y
reembolsa) pero no otra. No relajar ese guard sin resolver el problema de
raíz (usar un handle estable en vez de un índice crudo).

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

## Shaders de máscara + blur/threshold (agua y camino)

`assets/water.glsl` y `assets/path.glsl` comparten la misma técnica en dos
fases (ver `Water_Shader`/`Path_Shader` en `systems/rendering.odin`):

1. **Máscara** (`water_render_mask` / `path_render_mask`): dibuja rectángulos
   BLANCOS lisos (sin AA) para los tiles relevantes sobre un
   `RenderTexture2D` dedicado (`*_shader.mask_tex`), del tamaño de la
   pantalla (se redimensiona con `*_shader_resize` en cada resize de
   ventana). Debe llamarse **fuera** de cualquier `BeginTextureMode` activo.
2. **Apply** (`water_render_apply` / `path_render_apply`): dibuja esa máscara
   a pantalla a través del shader, que hace *box blur* (radio fijo, ver
   comentario "Phase 1" en `water.glsl`) y después `smoothstep` en el punto
   medio (~0.5) de los valores blureados — el blur+threshold redondea los
   bordes de la máscara binaria sin necesidad de geometría curva real.

**Preview de mapas** (`render_map_preview_to_texture`): la máscara no se
puede computar dentro del `BeginTextureMode` de la preview (raylib no
soporta texture-mode anidado), así que se precomputa ANTES, con el
`mask_tex` temporalmente intercambiado a la resolución 1:1 de la preview
(guardar/restaurar `tex_w/tex_h/mask_tex` de cada shader). Si se agrega un
shader nuevo con este patrón, replicar el mismo swap para agua Y camino.

`render_path_layer` además cachea los tiles de puente (PATH sobre agua) con
sus vecinos ya resueltos en `path_bridge_tiles` (poblado durante
`path_render_mask`) para que `render_path_railings` los dibuje sin volver a
recorrer la grilla ni recalcular `is_path_like`. Los railings se dibujan
**después** de aplicar el shader, sin blur (bordes nítidos a propósito).

## Fondo animado (nebula.glsl)

Desactivado por ahora vía `constants.NEBULA_BACKGROUND_ENABLED :: false`
(gatea la llamada a `nebula_draw()` en `render_game`, usado en MENU,
RUN_COMPLETE, CAMPAIGN_MAP, PROGRESSION). La infraestructura
(`nebula_init/unload/draw`) sigue cargada — solo hay que volver el flag a
`true` para reactivarlo.

## Nombre del juego

`constants.GAME_NAME` ("First Impact") es la única fuente de verdad — usado
en `WINDOW_TITLE` (`main.odin`) y el título del menú (`systems/menus.odin`).
Es un nombre propio: no tiene traducción en `translations.txt`.

## Tooltips multilínea (cartas y reliquias)

`render_tooltip_layer` (caso `.CARD`, `systems/interface.odin`) wrappea
automáticamente cualquier línea que exceda `constants.UI_TOOLTIP_MAX_TEXT_W`
(220px) vía `wrap_text_lines` (greedy word-wrap, `context.temp_allocator`).
El buffer de líneas es `[8]string` — suficiente para descripciones largas
(Crane Kick, Cryptobro) más las líneas de stats. El nombre y el badge de
rareza comparten la misma fila (badge alineado a la derecha vía
`render_rarity(..., right_align = true)`); `rarity_badge_width` mide el
badge sin dibujarlo, para poder calcular el ancho del tooltip antes de
layoutear.

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

### Card Hand: activar reliquia activa vs. vender (`systems/menus.odin`)

`render_card_hand` (pasada 2, carta hovereada) resuelve primero el clic
izquierdo (selecciona/activa la carta) y separado el clic derecho (vende,
ver sección de venta más arriba). Ambos comparten el guard `card_is_pending`
para no reactivar una carta que ya está con acción pendiente.

**Regla para reliquias activas nuevas:** cualquier `Card_Kind` nuevo que
active vía `pending_tower_action` debe agregarse al chain `else if
card.kind == .X` dentro del bloque de clic izquierdo.

Ver también la trampa de `selected_card_idx` en la sección de venta de
cartas más arriba — es la más importante de esta lista.

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

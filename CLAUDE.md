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

## Reliquias SABUESO y OVERKILL (RARE, pasivas)

- **SABUESO** (Bloodhound): cuando una torre que ve invisibles
  (`can_target_invisible_tower`) golpea a un enemigo `.INVISIBLE`, dispara
  `enemy.revealed_timer = SABUESO_REVEAL_DURATION_PER_STACK * stacks`
  (solo extiende, nunca acorta) dentro de `calc_damage`
  (`systems/simulation.odin`). Mientras `revealed_timer > 0`, ese enemigo es
  targeteable/dañable por **cualquier** torre — no solo ARCHER/LASER/SNIPER.
  Los 4 sitios que antes chequeaban solo `can_target_invisible_tower` ahora
  también aceptan `enemy.revealed_timer > 0`: `find_target`, el pulso de
  ICE, el chain-hop de TESLA y el splash AoE. El timer decae en
  `update_enemies` junto con `hit_squash`. El render de invisibles
  (`render_enemies`, `systems/rendering.odin`) también respeta el timer:
  no aplica el dimming de alpha mientras está revelado.
- **OVERKILL** (Desborde): al morir un enemigo, si el daño sobrante
  (`-enemy.hp`, negativo) es mayor a 0, salpica
  `-enemy.hp * OVERKILL_RATIO_PER_STACK * stacks` de daño al enemigo vivo
  más cercano dentro de `OVERKILL_RANGE` tiles (un solo salto, sin cadena;
  si esa salpicadura mata a la víctima, se procesa recién el próximo frame
  cuando el loop llegue a su índice). Lógica en el bloque de muerte de
  `update_enemies` (`systems/simulation.odin`).

Ambas se agregaron solo en `Card_Kind`/`RELIC_SPECS` (`entities/card.odin`)
+ sus constantes — no hubo que tocar ningún listado hardcodeado de
reliquias (shop pool, tray de pasivas, Biblioteca, progresión) porque todos
esos sitios iteran `RELIC_SPECS` dinámicamente.

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

## Biblioteca de cartas (`Game_State.LIBRARY`)

`render_card_library_ui` (`systems/menus.odin`), accesible desde el botón
"Biblioteca de Cartas" del menú principal. Catálogo de **todas** las torres
(`ALL_TOWERS`, 9) y reliquias (`entities.RELIC_SPECS`) del juego — no
incluye obstáculos. `library_row_cards(rarity)` arma cada fila (torres
primero, después reliquias, en su orden de declaración) en un array fijo
`[16]Card` — 16 alcanza de sobra (la fila más grande hoy, UNCOMMON, tiene
10). Una fila por rareza (`COMMON..UNIQUE`), con scroll vertical (mismo
patrón que `render_progression_ui`: `library_scroll`, clamp contra
`content_bottom`).

Cada fila reusa **el mismo mecanismo de abanico** que `render_card_hand`
(overlap por `step`/`card_draw_x`, dos pasadas — todas menos la hovereada,
después la hovereada levantada `hover_lift` px y sin overlap) en vez de
inventar un layout nuevo. Diferencia con la mano: usa casi todo el ancho de
pantalla (`max_w := sw * 0.92`, la mano usa 60% para dejarle sitio a otros
paneles del HUD que acá no existen).

`library_card_unlocked(app, card)` decide gris/color pasando el booleano de
"desbloqueado" al parámetro `can_afford` de `render_card` — ese parámetro
originalmente significa "¿el jugador puede pagarlo?" (uso en el shop), pero
la lógica de grayscale que dispara (`!can_afford → escala de grises`) es
exactamente la que hace falta acá, así que se reusa tal cual en vez de
tocar `render_card`.

## Sistema de oleadas y enemigos

`Enemy_Flag` (`entities/enemy.odin`) es un `bit_set` de 8 miembros (exacto
para el `u8` que lo respalda — no queda lugar para un noveno flag sin
cambiar el tipo base): `BOSS, GREEN, BLUE, FLYING, SPLIT, BONUS, ARMORED,
INVISIBLE`. Un enemigo puede combinar varios (oleadas mixtas, jefes con
variante, oleadas bonus con los 6 sub-tipos a la vez).

### Sub-tipos sorteados por seed (no determinísticos)

Antes, el sub-tipo de cada oleada salía de `wave_number % 4` — la secuencia
de oleadas era idéntica en todas las runs. Ahora `roll_wave_subtype`
(`systems/simulation.odin`) sortea con `core:math/rand`, que ya está
re-seedeado por run (`app.sim.seed = rand.uint64(); rand.reset(...)` en
`simulation_init`) — cada run tiene su propia secuencia, reproducible para
ese seed.

- **Pool de sub-tipos**: `ENEMY_SUBTYPE_POOL` = `{GREEN, FLYING, BLUE,
  SPLIT, ARMORED, INVISIBLE}` (6 flags). Bonus usa los 6 a la vez; boss
  sortea 1 (su "variante"); normal/mixta sortea 1 primario y, desde
  `MIXED_WAVE_MIN_WAVE`, un secundario.
- `pick_random_subtype_excluding(prev)` evita repetir el/los flag(s) de la
  oleada inmediatamente anterior (fallback al pool completo si `prev` lo
  cubre todo, no debería pasar con 1-2 excluidos).
- **Lookahead pre-rolleado**: igual que ya hacía `sim.lookahead_bonus[3]`
  para la reliquia SCOUT, ahora `sim.lookahead_subtype: [3]Enemy_Flags`
  guarda el sub-tipo de las próximas 3 oleadas, roleado con 3 de
  anticipación en `start_next_wave` (slot 0 = próxima oleada, shift al
  consumir). **Necesario** porque SCOUT necesita mostrar el tipo real de
  oleadas futuras antes de que existan — ya no se puede recalcular a partir
  de `wave_number` solo. `simulation_init` pre-rollea las primeras 3 al
  arrancar la run (las oleadas 1-3 nunca son boss/bonus/mixtas, así que ese
  pre-roll es más simple).
- El panel de próximas oleadas de SCOUT (`systems/menus.odin`,
  `render_game_ui`) lee `sim.lookahead_subtype[i]` directo — **no**
  recalcula con una fórmula. `enemy_subtype_color`/`enemy_subtype_label`
  (`systems/rendering.odin`) centralizan color/nombre por flag.

**Trampa:** si se agrega un sub-tipo nuevo, sumarlo a `ENEMY_SUBTYPE_POOL`
alcanza para que entre al sorteo — pero también hay que agregarle color
(`enemy_get_color`, `entities/enemy.odin`), tamaño si aplica
(`enemy_get_size`), entrada en `enemy_subtype_color`/`enemy_subtype_label`,
y decidir si necesita multiplicador de HP/velocidad propio en
`spawn_enemies` (`systems/simulation.odin`) — son switches por prioridad
(el primer caso que matchea gana), no se combinan aditivamente.

### Jefes con variante (BOSS + sub-tipo)

Antes, todo boss era `.BOSS` solo (sin combinar con GREEN/FLYING/BLUE/
SPLIT) — ahora `roll_wave_subtype` siempre les asigna una variante del
mismo pool de 6. Ejemplos: jefe volador (solo antiaéreo lo alcanza), jefe
que se divide al morir, jefe blindado, jefe invisible.

**Trampa ya resuelta:** el código de split-on-death excluía explícitamente
a los bosses (`!(.BOSS in enemy.flags)`), asumiendo que un boss nunca
tendría `.SPLIT`. Con jefes con variante eso ya no vale — se sacó esa
exclusión. Los hijos de un boss+SPLIT no heredan `BOSS`/`SPLIT`/`BONUS`
(quedan como tanques grandes normales, no mini-jefes que se multiplican).

### ARMORED e INVISIBLE

- **ARMORED**: solo `SNIPER`, `CANNON`, `MORTAR` (`is_armor_piercing_tower`,
  `systems/simulation.odin`) le hacen daño completo — el resto de las
  torres multiplican su daño por `constants.ARMORED_DAMAGE_MULT` (0.35).
  Esto vive en `calc_damage`, que ahora recibe un parámetro extra
  `source_type: constants.Tower_Type` **separado** del puntero `source:
  ^Tower` — en el splash de daño AoE la torre origen puede haber sido
  vendida antes de que el proyectil impacte (`source == nil`), pero
  `proj.type` (guardado en el proyectil, no en la torre) sigue siendo
  confiable. Los 6 call-sites de `calc_damage` pasan `tower.type` o
  `proj.type` según corresponda.
- **INVISIBLE**: solo `ARCHER`, `LASER`, `SNIPER`
  (`can_target_invisible_tower`) pueden detectarlo/dañarlo. Filtrado en
  **todos** los sitios que seleccionan o dañan enemigos, no solo
  `find_target`: `update_ice_tower` (pulso AoE), el chain-hop de
  `update_tesla_tower` (no pasa por `find_target` para los eslabones 2+),
  y el loop de splash de proyectiles con `proj.aoe > 0`. Si se agrega un
  nuevo lugar que itere `sim.enemies` para aplicar daño/efectos, hay que
  repetir el chequeo `.INVISIBLE in enemy.flags && !can_target_invisible_tower(...)`.
  Visualmente se dibuja con alpha reducido (`constants.ENEMY_INVISIBLE_ALPHA`).

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

### ⚠️ Trampa: `BeginTextureMode` no anida en raylib

`EndTextureMode()` siempre vuelve al framebuffer por defecto (pantalla), **no**
a un "anterior" en una pila — no existe tal pila. Si envolvés una secuencia de
render con `BeginTextureMode(mi_textura)` y en el medio se llama a algo que
internamente hace su propio `BeginTextureMode(...)/EndTextureMode()` (como
`water_render_mask` o `path_render_mask`), todo lo que se dibuje **después**
de ese `EndTextureMode()` interno se va derecho a pantalla en vez de a
`mi_textura` — la captura queda cortada a la mitad, sin error ni warning.

**Fix estándar** (ya usado dos veces: `render_map_preview_to_texture` y
`Pause_Blur`, ver más abajo): precomputar `water_render_mask`/
`path_render_mask` **antes** de entrar al `BeginTextureMode` propio, y
llamar a `render_map(app, m, for_preview = true)` para que
`render_water_layer`/`render_path_layer` solo apliquen la máscara ya
calculada en vez de recomputarla (evitando el `BeginTextureMode` interno).
Efecto colateral de `for_preview = true`: también saltea el overlay de
pasto (`render_grass_overlay`) — aceptable si lo que se está capturando va
a quedar blureado/tintado igual (como el vidrio de pausa), no si necesita
verse nítido.

## Vidrio esmerilado de la pantalla de Pausa (`Pause_Blur`)

`assets/blur.glsl`: blur separable de 1D (tent filter, radio fijo `R=6` en
el shader) en 2 pasadas — horizontal y vertical — controladas por el
uniform `direction`. `constants.PAUSE_BLUR_SPREAD` (3.0) multiplica el
texel step para separar las muestras y que el blur se note a simple vista
(6 texels de radio en una pantalla de 1920px sería casi imperceptible).

Flujo en `render_game` (`systems/rendering.odin`) cuando
`app.state == .PAUSED`:
1. Precomputar máscaras de agua/camino (ver trampa de arriba).
2. `BeginTextureMode(pause_blur.capture_tex)` → el mundo se renderiza ahí
   en vez de a pantalla, llamando a `render_map(..., for_preview = true)`.
3. `EndTextureMode()`, restaurar `camera_offset_x/y` (post screen-shake).
4. `pause_blur_draw()`: pasada horizontal `capture_tex → blur_tex`, pasada
   vertical `blur_tex → pantalla`, y encima un rect semitransparente
   (`constants.PAUSE_GLASS_TINT`) — el efecto "vidrio esmerilado".
5. `render_ui` (el menú de pausa) se dibuja después, sin blur.

Se recalcula todo esto **cada frame** mientras está pausado, no se cachea
un solo capture — el mundo está congelado (`simulation_update` no corre en
pausa) así que el resultado es idéntico frame a frame, pero cachear traería
complejidad de invalidación (resize de ventana, etc.) sin beneficio real:
redirigir el render normal a una textura + 2 pasadas de blur no es más caro
que lo que ya se dibuja hoy en pantalla.

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

## Visual juice (partículas, screen shake, recoil, squash, ballesta)

Todo 100% procedural/código — el juego no importa sprites. Las primeras
cuatro piezas comparten la misma forma: un campo de estado que decae con
el tiempo + un hook en el momento del evento que lo dispara.

- **Chispas de impacto/muerte** (`entities/explosion.odin`: `Hit_Particle`,
  `hit_particle_init/update`; spawn vía `spawn_hit_particles`, `systems/simulation.odin`):
  burst de círculos que salen disparados y frenan por drag exponencial.
  Se llama en cada instancia de daño "discreta" (pulso de ICE, eslabón de
  TESLA, impacto directo de proyectil, cada víctima del splash de AoE, y el
  bloque `should_show` throttled del LASER) — **no** en el tick continuo
  crudo del LASER (`calc_damage` corre ahí cada frame; spawnear ahí
  saturaría de partículas). Ráfaga más grande (`HIT_PARTICLE_COUNT_DEATH`)
  al morir un enemigo.
- **Screen shake** (`app.screen_shake_trauma`, `[0,1]`, decae en
  `simulation_update`; sumado vía `add_screen_shake`): se dispara solo en
  `spawn_explosion` (todas las AoE de CANNON/MISSILE/MORTAR, escalado por
  radio) y en la muerte de un boss. El offset visual es determinístico
  (`sin`/`cos` del tiempo, no random puro por frame — se ve suave, no
  "buzz") y se aplica temporalmente a `app.camera_offset_x/y` **solo**
  durante el bloque de render del mundo en `render_game`, restaurado antes
  de `render_ui` — la UI nunca tiembla.
- **Recoil de torres** (`tower.recoil`, `[0,1]`, decae en `update_towers`):
  se pone en `1.0` al disparar (proyectiles y MORTAR, no LASER/TESLA/ICE/
  ENHANCE que no tienen ese momento discreto). `draw_tower_tile` retrae
  solo el barril (no la base) a lo largo de `-cos(angle),-sin(angle)` — el
  MORTAR ignora `angle` (dispara siempre hacia arriba) así que su recoil va
  derecho hacia abajo.
- **Ballesta de ARCHER** (`draw_tower_components_archer`,
  `systems/rendering.odin`): antes era una barra rectangular genérica sin
  terminar. Ahora es riel + arco: el riel ("palito") es el mismo
  `DrawRectanglePro` original, apuntando hacia adelante desde el centro de
  la torre. El arco va montado cerca de la punta del riel (`mount`, a
  `cs*0.30` de distancia), dibujado con dos
  `raylib.DrawSplineSegmentBezierQuadratic` (mount → control que bulge
  hacia adelante → punta) más una cuerda de dos segmentos punta→mount→punta.
  El `recoil` de la torre (mismo campo que el punto anterior, ya retrae
  todo el conjunto vía el offset de `draw_tower_tile`) además aplica un
  **stretch anisotrópico** al arco, centrado en `mount`: ensancha en X
  (`sx = 1+stretch`) y aplana la profundidad del bulge en Y
  (`sy = 1-stretch`, `TOWER_ARCHER_BOW_STRETCH` = 0.45 máx) — simula el arco
  liberando tensión al disparar, vuelve a su curva de descanso a medida que
  decae. Todos los puntos están en espacio local con "adelante = -Y" (misma
  convención que el resto de los barriles) y se rotan a mano con `rot_pt`
  porque las specs de spline de raylib no tienen una variante con matriz de
  rotación como sí tiene `DrawRectanglePro`.
  **Trampa ya pisada:** la cuerda usaba `TOWER_SHADOW` (negro alpha=30,
  pensado para sombras) y quedaba invisible — tiene su propio color opaco
  (`string_color`, beige claro) definido inline.
- **Squash de enemigos** (`enemy.hit_squash`, `[0,1]`, decae en
  `update_enemies`; disparado dentro de `calc_damage` — corre en **todo**
  hit, incluido el tick continuo del láser, a propósito: es barato y
  representa "sigue bajo fuego"): `render_enemy_shape` ahora acepta
  `squash` y deforma anisotrópicamente (ancho×(1+squash), alto×(1-squash))
  las 3 formas base — círculo (ahora `DrawEllipse` en vez de `DrawCircle`),
  cuadrado de boss, triángulo de flying.

**Trampa:** los 4 dynamic arrays de efectos (`explosions`, `damage_numbers`,
`hit_particles`, `glow_particles`, ...) se liberan en `simulation_cleanup` —
si se agrega un array nuevo de este estilo, agregar su `delete()` ahí
también (se detectó y arregló un leak real: `hit_particles` no se liberaba).

## Obstáculos en el camino

- `obstacle_bar_dims(m, row, col, cs)` determina dimensiones de la barrera
  según si el camino es horizontal o vertical en esa celda — se usa tanto
  para obstáculos reales como para el ghost de preview, para coherencia visual.
- `map_is_path_corner_or_junction(m, row, col)` — `true` si la celda es
  esquina o bifurcación del camino; ahí no se pueden colocar obstáculos (el
  ghost se pinta rojo con X). Criterio: ≥3 vecinos path = junction, 2
  vecinos no opuestos = corner.

## Modal de confirmación Sí/No (`Confirm_Modal`)

`app.confirm_modal` (`entities/app.odin`, `Confirm_Modal{active, text, action}`)
es el mecanismo genérico para "¿estás seguro?" — `Modal_Action` (enum) más un
`switch` en `render_ui` (`systems/menus.odin`) que ejecuta la acción real
cuando el modal devuelve `.CONFIRMED`. Patrón para agregar una acción nueva:

1. Agregar el variant a `Modal_Action`.
2. En el botón que la dispara, en vez de ejecutar la acción directo, asignar
   `app.confirm_modal = entities.Confirm_Modal{active = true, text = "...",
   action = .MI_ACCION}`.
3. Agregar el `case .MI_ACCION:` al switch dentro del bloque
   `if app.confirm_modal.active { switch render_confirm_modal(...) { case
   .CONFIRMED: ... } }` en `render_ui`, con la lógica que antes estaba en el
   botón.

**Nota:** el texto de estos modales (`"¿Reiniciar la partida?..."`, etc.) va
hardcodeado en español directo, sin pasar por `constants.get_text`/
`translations.txt` — inconsistente con el resto de la UI (que sí está
traducida), pero es el patrón ya establecido en los modales existentes
(NEW_GAME, RESTART_RUN, EXIT_GAME, PAUSE_TO_MENU); no traducirlo solo por
consistencia interna si se toca este código, a menos que se traduzcan todos
a la vez.

Ejemplo real: el botón "Menú Principal" de pausa (`render_pause_menu`) antes
salía directo a `.MENU` perdiendo el mapa actual sin avisar — ahora abre
`Confirm_Modal{action = .PAUSE_TO_MENU}` con el aviso de pérdida de
progreso, y el `case .PAUSE_TO_MENU` hace la transición real.

## Animación de shaders: tiempo acumulado, no `GetTime()` de pared

`water.glsl` usaba `raylib.GetTime()` (reloj de pared, sigue corriendo
aunque la ventana esté minimizada/sin foco y el loop deje de renderizar
frames reales) directo como `u_time`. Al recuperar el foco, el salto de
reloj entre el último frame dibujado y el actual se leía como que la
animación "se acelera" de golpe.

**Fix:** `Water_Shader.anim_time` (`systems/rendering.odin`) se acumula a
mano cada vez que se llama `water_render_apply`, con `dt` clampeado
(`constants.WATER_ANIM_MAX_DT`, evita saltos por hitches o al recuperar
foco) y escalado por `constants.WATER_ANIM_SPEED` (0.4 — más lento que
antes). Si se agrega otro shader animado por tiempo, replicar este patrón
(acumular con dt clampeado) en vez de leer `GetTime()` directo.

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

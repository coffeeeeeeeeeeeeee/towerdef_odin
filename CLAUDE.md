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
odin build . -out:towerdef -o:speed # build de release (dev, con checks — ver abajo)
```

### Build de release real (shippear a itch, `constants.DEVELOPER :: false`)

Además de `-o:speed`, sumar los flags que desactivan los checks en runtime
— la wiki de Odin (`Compiler-Flags`) documenta un ~20% de mejora combinando
los tres. **Usar solo junto con `DEVELOPER :: false`**: mientras se itera
con `DEVELOPER :: true` estos checks valen la pena (un bounds-check roto
tira panic legible en vez de corromper memoria en silencio), así que no
conviene meterlos en el comando de build "de dev" de arriba.

```bash
odin build . -out:towerdef -o:speed -disable-assert -no-bounds-check -no-type-assert
```

- `-disable-assert`: saca la generación de código de `assert()` (define
  `ODIN_DISABLE_ASSERT`).
- `-no-bounds-check`: sin bounds-check en accesos a arrays/slices/etc en
  todo el programa.
- `-no-type-assert`: sin chequeo en type assertions (`x.(T)`).

Ninguno de los tres está probado a fondo contra este juego todavía — antes
de shippear un build con estos flags conviene una pasada de smoke-test
normal (jugar una run completa, entrar a todos los estados) para confirmar
que no hay ningún bug latente que dependía de un panic temprano para
notarse.

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
`bool` en `write_entire_file`, etc). El flag de optimización también cambió
de nombre en algún punto: `-opt:3` ya no existe, ahora es `-o:speed`
(opciones: `none`/`minimal`/`size`/`speed`).

### Cross-compilar a Windows desde Linux

`odin build . -out:towerdef.exe -target:windows_amd64` falla en el paso de
linkeo: el compilador imprime `Linking for cross compilation for this
platform is not yet supported (windows amd64)` y aborta, pero **sí** deja
un objeto intermedio (`keep_object_files` se activa automáticamente en ese
caso). En versiones recientes de Odin es un único `.obj` combinado en la
raíz del proyecto (`<out-name>.obj`), no uno por paquete en `/tmp` como en
versiones viejas — revisar cuál aparece antes de armar el comando de link.
Se puede linkear ese objeto a mano:

1. Si el objeto aparece en `/tmp` con prefijo `<out-name>-<paquete>-<hash>.obj`
   (versiones viejas de Odin), limpiar los de builds previos antes de
   compilar para no mezclar intentos distintos (los hashes no son
   puramente por contenido).
2. `sudo apt-get install mingw-w64 lld` — hacen falta el linker `ld.lld`
   (en modo mingw, `-m i386pep`) y los import libs de mingw
   (`/usr/x86_64-w64-mingw32/lib/*.a`). El `ld` de GNU (`x86_64-w64-mingw32-ld`,
   incluido en mingw-w64) **no sirve**: no resuelve los símbolos globales que
   LLVM/Odin emite como weak+COMDAT (`constants::TRANSLATIONS` y similares
   quedan indefinidos). `lld-link`/`ld.lld` sí entienden COMDAT.
3. Usar `raylibdll.lib` (vendor/raylib/windows), NO `raylib.lib` estático —
   el `.lib` estático fue compilado contra UCRT (`__stdio_common_vfprintf`,
   `fmaxf`, `roundf`, etc.) y mingw-w64 solo trae el runtime clásico
   `msvcrt.dll`, no UCRT. La versión dinámica evita ese problema porque esos
   símbolos quedan resueltos *dentro* de `raylib.dll` en tiempo de
   ejecución. Hay que shippear `raylib.dll` junto al `.exe`.
4. Dos símbolos que Odin/LLVM esperan con nombres al estilo MSVC y que
   mingw no provee así hacen falta como shims propios (compilarlos con
   `x86_64-w64-mingw32-gcc -c`):
   - `_fltused` (dato `int`, valor `0x9875` — marcador de "esta imagen usa
     floating point", no se llama, solo debe *existir*).
   - `__chkstk` (probe de stack; mingw solo trae `___chkstk`/`___chkstk_ms`
     con guiones bajos de más — un `jmp ___chkstk_ms` en asm alcanza).
5. Comando de link (ajustar rutas de gcc/mingw según la versión instalada —
   en esta máquina existe `13-posix`, no `13-win32`; el `.lib` de Windows de
   Raylib vive en `vendor/raylib/windows/` **dentro del install de Odin**
   (`$(odin root)/vendor/raylib/windows/raylibdll.lib`), no en el repo del
   proyecto):
   ```bash
   GCCDIR=/usr/lib/gcc/x86_64-w64-mingw32/13-posix
   RAYWIN=<odin-root>/vendor/raylib/windows
   ld.lld -m i386pep -o towerdef.exe --subsystem windows -e mainCRTStartup \
     /usr/x86_64-w64-mingw32/lib/crt2.o \
     $GCCDIR/crtbegin.o \
     towerdef.obj \
     shim_fltused.o shim_chkstk.o \
     $RAYWIN/raylibdll.lib \
     -L$GCCDIR -L/usr/x86_64-w64-mingw32/lib \
     -lmingw32 -lgcc -lgcc_eh -lmoldname -lmingwex -lmsvcrt \
     -lkernel32 -ladvapi32 -lshell32 -luser32 -lgdi32 -lwinmm -lopengl32 -lole32 -lbcrypt \
     $GCCDIR/crtend.o
   ```
   No olvidar copiar `$RAYWIN/raylib.dll` junto al `.exe` al empaquetar —
   el `.exe` la importa en tiempo de ejecución (ver paso 3).
6. El `.exe` resultante solo importa DLLs estándar de Windows +
   `raylib.dll` (comprobado con `objdump -p towerdef.exe | grep "DLL Name"`).
   No se probó corriéndolo (no hay Wine/Windows en esta máquina) — si falla
   algo en runtime, sospechar primero de la ABI/calling convention en el
   borde LLVM↔mingw antes que del código del juego en sí.

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
├── assets/                  # Shaders GLSL (lighting.vs/.fs, nebula.glsl, blur.glsl, ...)
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

## Reliquia RESONANCIA (EPIC, pasiva)

Da, por stack, `RESONANCIA_CHANCE_PER_STACK` (15%) de probabilidad de que
el efecto de una reliquia "de gatillo" se dispare una segunda vez. Helper
`resonance_proc(sim) -> bool` (`systems/simulation.odin`, junto a
`relic_flash`) hace la tirada y devuelve si duplica; se llama una vez por
cada disparo real, sin acumular entre reliquias. Cableado en los 5 sitios
de disparo:
- **BLOODLUST**: suma el incremento de `bloodlust_mult` una segunda vez.
- **OVERKILL**: repite la salpicadura de daño sobre la misma víctima.
- **CRYPTOBRO**: intenta sumar hasta `stacks` niveles extra a la torre
  (respetando el `room` restante hasta `TOWER_MAX_LEVEL`).
- **REBOUND**: revierte el `bounces_left -= 1` de ese rebote (no consume
  la carga).
- **SABUESO**: duplica la `duration` calculada antes de aplicarla al
  `revealed_timer` del enemigo.

Como con las demás reliquias, no requirió tocar ningún listado
hardcodeado — solo `Card_Kind`/`RELIC_SPECS` (`entities/card.odin`) y la
constante en `constants/constants.odin`.

## Fondo de carta UNIQUE

`images/cards/unique.png` ya existe — se agregó `card_bg_unique` en
`Game_Icons` (`constants/fonts.odin`, load/mipmap/filter/unload) y
`rarity_card_tex` (`systems/interface.odin`) ahora mapea `.UNIQUE` a esa
textura en vez de reusar `card_bg_epic` como fallback.

## Biblioteca de cartas: espaciado vertical

`render_card_library_ui` (`systems/menus.odin`) — el alto de cada fila
(`row_h`) se redujo agrupando los márgenes en variables nombradas
(`label_h`, `label_gap`, `row_gap`, `hover_lift`) en vez de constantes
mágicas sueltas, bajando el alto por fila de ~229px a ~197px para que
entren más filas en pantalla sin scroll.

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

## El mapa (terreno, agua, camino, biomas) es 100% 3D — no queda renderer 2D

El renderer 2D del mapa (`render_map`, `render_map_objects`,
`render_tower_ranges`, `render_gameplay`, y toda la maquinaria que
alimentaban — `Water_Shader`/`Path_Shader`/`Dune_Shader`/`Rock_Shader`/
`Heightmap_Shader`/grass/glow-circle, sus `*_render_mask`/`*_render_apply`
de dos fases, `render_grid_lines`, el sistema de pájaros ambiente — se
eliminó por completo. `PLAYING`, `EDITOR`, `PAUSED` **y** el thumbnail del
browser de mapas (`render_map_preview_to_texture`) usan todos el mismo
camino: `render_map_3d`/`render_map_objects_3d` con el terreno cacheado de
`terrain_cache_ensure` (máscaras de camino/agua horneadas en texturas del
material, ver "Iluminación 3D" en `systems/rendering.odin`) y el shader
`lighting.fs` (overlays de bioma: cáusticas de agua, dunas, pasto, roca
agrietada — todo dentro del mismo pase, ver comentarios en
`assets/lighting.fs`). No queda ningún `BeginTextureMode` propio en el
camino de dibujo del mapa — la vieja trampa de "`BeginTextureMode` no
anida" (`EndTextureMode()` siempre vuelve al framebuffer por defecto, no a
un "anterior" en una pila) ya no aplica a nada de esto; `BeginMode3D`/
`EndMode3D` sí puede correr sin problema dentro de un `BeginTextureMode`
activo (lo usa `Pause_Blur`, ver más abajo), que es un caso distinto.

Dos detalles visuales que el 2D tenía y no tenían equivalente al migrar se
portaron a geometría 3D real, ambos en `render_map_objects_3d`:
- **Puente** (`render_bridge_3d`, piso + barandas): en tiles de PATH sobre
  agua, el piso tiene el mismo ancho que la franja de camino embossed en
  tierra (`PATH_WIDTH_RATIO`) — un cuadrado central más un tablón por cada
  borde conectado, cada uno llegando justo hasta el borde del tile para
  empalmar sin hueco con el tablón del tile vecino. Altura: el heightmap del
  tile **ignorando el flag de agua** (el heightmap sigue teniendo un valor
  de "tierra" válido debajo de `water_grid`, continuo con los tiles vecinos
  por construcción del ruido — así el piso queda a nivel con la orilla en
  vez de a la altura fija y baja de `WORLD_WATER_HEIGHT`), más un `DrawCube`
  fino de baranda por cada borde que NO conecta con otro tile de camino
  (mismo criterio de vecinos que `is_path_like`), apoyada sobre el piso. El
  agua real sigue estando ahí debajo — la malla del terreno no se toca,
  sigue siendo agua a `WORLD_WATER_HEIGHT` (ver
  `_terrain_tile_height_color`); el puente es geometría aparte por encima.
- **Nenúfares** (`render_water_lily_3d`): árboles (`ACCESSORY_TREE`) que
  caen en un tile de agua ya no se dibujan como árbol — en su lugar, 2-4
  discos chatos (`DrawCylinder` muy bajo, raylib no tiene un círculo 3D
  relleno nativo) con deriva animada y flor opcional, apoyados en
  `WORLD_WATER_HEIGHT` (la altura fija del agua, no el heightmap — ver
  `_terrain_tile_height_color`).

`render_map_objects_3d` dibuja las torres reales buscando el `Tower` que
matchea en `app.sim.towers` — cuando no hay uno (EDITOR, o el preview de un
mapa que no tiene una simulación asociada) cae a un fallback: forma
genérica a partir del tipo de tile (`tile_to_tower_type` +
`draw_tower_shape_3d`), igual criterio que ya usaba el render 2D viejo.

### Camino "embossed" (hundido) — malla subdividida + desplazamiento en el VS

El camino no es solo color: la malla del terreno se genera subdividida
(`TERRAIN_MESH_SUBDIV` sub-quads por tile, `_terrain_corner_lerp` interpola
bilinealmente entre las 4 esquinas de `_terrain_corner` — sin camino cerca,
esto no cambia la forma del terreno, solo la hace más densa) y
`lighting.vs` hunde los vértices de una franja angosta (ancho
`PATH_WIDTH_RATIO`) restando `pathMaskTexel`/`pathEmbossDepth *
texture(texture0, uv).r` de `vertexPosition.y`, con la normal reperturbada
por diferencia central de la misma máscara (si no, la pared tallada se ve
"pintada" en vez de con relieve real). La máscara (`texture0`, slot ALBEDO)
ya no es 1 texel/tile con `POINT` — es supersampleada
(`PATH_MASK_SUBDIV` texels/tile, `BILINEAR`) y su forma de franja/cruz la
calcula `_path_strip_mask` en CPU (distancia del punto a los segmentos
centro-de-tile → punto-medio-de-cada-borde-conectado, mismo criterio
`is_path_like` que `render_bridge_3d` — PATH/SPAWN/GOAL cuentan
todos como camino, así que la franja hundida atraviesa entera la casilla de
spawn y la de meta también). Un solo dato (`texture0`)
sirve para pintar `pathColor` en el fragment shader **y** para hundir en el
vertex shader — eso es intencional, no hay dos máscaras separadas.

Un tile de camino sobre agua (puente) queda excluido del hundimiento
(`texture1`, la máscara de agua, actúa de guard en el VS) — el agua ya está
a su propia altura fija (`WORLD_WATER_HEIGHT`) y el puente debe quedar a
nivel de sus rieles, no tallado.

**Trampa:** `texture0`/`texture1` se declaran también en `lighting.vs` (no
solo en el `.fs`) para poder samplearlas ahí — `useTerrainMask` gatea el
hundimiento igual que ya gatea el color, así que formas inmediatas
(torres/enemigos) que comparten el shader nunca se hunden aunque su
material no tenga bindeada ninguna de las dos texturas.

**Trampa ya pisada:** unir las distancias a cada brazo de la cruz con `min()`
deja una cresta dura donde dos campos de distancia empatan (la bisectriz del
ángulo en curvas/T) — la normal recalculada por diferencia central pega un
salto ahí y desde ciertos ángulos de cámara se ve como un pliegue raro en la
esquina. Se probó "smooth minimum" (smin polinómico, IQ) para redondear esa
unión y **empeoró**: al encadenar smin sobre 3-4 segmentos (tiles T/cruz) el
hundimiento se cava de más, cada combinación sucesiva profundiza otro poco.
La solución que quedó es más simple y predecible: un blur en cruz (centro +
4 vecinos ortogonales, sin diagonales) aplicado a la textura de máscara ya
rasterizada (`terrain_cache_ensure`, justo antes de subirla a GPU) —
emprolija la cresta en la imagen en vez de tocar el campo de distancia
analítico, con una caja más chica que un 3x3 completo para no difuminar de
más el resto del borde.

**Spawn y goal se hunden con el camino** — la plataforma (`render_spawn_3d`/
`render_goal_3d`) se planta con `tile_world_top`, que no sabe nada del
hundimiento (es CPU, el hundimiento es puramente del shader). Para que no
quede flotando sobre la malla hundida, `_path_emboss_offset(m, row, col)`
recalcula cuánto baja el CENTRO del tile (mismo `_path_strip_mask` evaluado
en `u=v=0.5`, con guard de agua) y se lo resta a la `y` antes de dibujar.

## Vidrio esmerilado de la pantalla de Pausa (`Pause_Blur`)

`assets/blur.glsl`: blur separable de 1D (tent filter, radio fijo `R=6` en
el shader) en 2 pasadas — horizontal y vertical — controladas por el
uniform `direction`. `constants.PAUSE_BLUR_SPREAD` (3.0) multiplica el
texel step para separar las muestras y que el blur se note a simple vista
(6 texels de radio en una pantalla de 1920px sería casi imperceptible).

Flujo en `render_game` (`systems/rendering.odin`) cuando
`app.state == .PAUSED`: PAUSED comparte el mismo bloque de render 3D que
PLAYING/EDITOR (mapa/torres/enemigos vía `render_map_3d` y compañía, dentro
de `BeginMode3D`/`EndMode3D`) — lo único distinto es que ese bloque queda
redirigido a una textura en vez de a pantalla:
1. `BeginTextureMode(pause_blur.capture_tex)` → todo el bloque 3D
   (`render_map_3d`, `render_map_objects_3d`, `render_gameplay_3d`, etc.) se
   renderiza ahí en vez de a pantalla.
2. `EndTextureMode()`, restaurar `camera_offset_x/y` (post screen-shake).
3. `pause_blur_draw()`: pasada horizontal `capture_tex → blur_tex`, pasada
   vertical `blur_tex → pantalla`, y encima un rect semitransparente
   (`constants.PAUSE_GLASS_TINT`) — el efecto "vidrio esmerilado".
4. `render_ui` (el menú de pausa) se dibuja después, sin blur.

La cámara 3D queda congelada en pausa porque nada mueve `camera_focus`/
`app.zoom` mientras se está pausado (`input_handle_camera_3d` no corre —
ver el dispatch de input por estado), no por ningún mecanismo especial de
`Pause_Blur`.

Se recalcula todo esto **cada frame** mientras está pausado, no se cachea
un solo capture — el mundo está congelado (`simulation_update` no corre en
pausa) así que el resultado es idéntico frame a frame, pero cachear traería
complejidad de invalidación (resize de ventana, etc.) sin beneficio real:
redirigir el render normal a una textura + 2 pasadas de blur no es más caro
que lo que ya se dibuja hoy en pantalla.

## Control de cámara 3D — sin paneo, rotación con botón central

`camera3d_for_focus` (`rendering.odin`) toma `focus`/`zoom`/`yaw`. El
`yaw` es lo único nuevo: rota la cámara alrededor de `focus` en el eje Y,
ángulo de inclinación (`CAMERA_PITCH_DEG`) siempre fijo. En `yaw=0` da
exactamente la misma posición que la cámara vieja (antes de que existiera
rotación) — es el caso de regresión a no romper si se toca esta función.

**No hay paneo ni zoom-to-cursor.** `app.camera_focus` nunca se mueve en
vivo — queda fijo en lo que establecen `simulation_fit_camera`
(`systems/simulation.odin`) y `default_focus` (`main.odin`) al
cargar/ajustar un mapa (ambos calculan el centro del mapa), y es siempre
el pivote tanto del zoom como de la rotación: el scroll solo cambia
`target_zoom` (achica/agranda distancia, nunca desplaza el punto mirado)
y el botón central + drag solo cambia `app.camera_yaw` — ninguno de los
dos toca `camera_focus`. Hubo una versión anterior con zoom-to-cursor
(raycast contra el plano y=0 para mantener el mismo punto de suelo bajo
el cursor al hacer scroll, `raycast_ground_point`) que se sacó a pedido
explícito porque el zoom siempre debe apuntar al centro del mapa — no
reintroducir esa función sin que se pida de nuevo.
`input_handle_camera_orbit` (`systems/input.odin`) resuelve la rotación y
se llama tanto desde `input_handle_camera_3d` (PLAYING/EDITOR) como desde
`input_handle_paused` (PAUSED no pasa por `input_handle_camera_3d`, así
que necesita su propia llamada).

`camera_yaw` no tiene lerp/target a diferencia de `camera_focus`/`zoom` —
responde 1:1 al drag, no hay una versión "suavizada" que perseguir cada
frame.

**Por qué el botón central y no el derecho** (el pedido original era
click derecho + drag): el derecho ya dispara varias acciones de un solo
click en este proyecto (cancelar acción/torre seleccionada en
PLAYING/PAUSED, borrar celda en EDITOR, vender carta/torre en los menús —
todas vía `IsMouseButtonPressed(.RIGHT)`, que dispara en el mismo frame en
que se aprieta, antes de que se pueda saber si va a haber drag) — usarlo
para rotación hubiera necesitado distinguir click de drag en los 5 sitios
que ya lo usan. El botón central no tiene ninguna acción de un solo click
en el proyecto (solo tenía paneo, que se sacó), así que no hace falta
nada de eso: cualquier movimiento con el botón apretado rota, sin
threshold ni tracking de estado extra. Si en algún momento se le agrega
una acción de click al botón central, ahí sí hay que revisar
`input_handle_camera_orbit` para que no dispare junto con un drag.

## Iluminación 3D — especular, sombras de contacto, ciclo día/noche, sombra proyectada

Modelo base sigue siendo Lambertiano simple (`3D_RENDER_PLAN.md`), pero ya
no es 100% estático:

- **Valores base** (`LIGHT_SUN_DIR`/`LIGHT_SUN_COLOR`/`LIGHT_FILL_DIR`/
  `LIGHT_FILL_COLOR`/`LIGHT_AMBIENT` en `constants.odin`) centralizan lo que
  antes eran literales sueltos en `lighting_shader_init`. Estos 5 valores
  ahora también son el keyframe `.NOON` del ciclo día/noche (ver abajo) — no
  son solo "el valor fijo", son "el valor de referencia al mediodía".
- **Especular suave** (`viewDir`/`specularStrength` en `lighting.fs`): solo
  torres (bracket puntual alrededor de su draw en `render_map_objects_3d`,
  vía `LIGHT_SPECULAR_STRENGTH_TOWER`) y agua (siempre activo mientras
  `useTerrainMask`+`isWater`, multiplicador fijo `SPECULAR_STRENGTH_WATER`
  dentro del shader). `viewDir` es un uniform **por frame** (ya no una
  constante — la cámara rota, ver "Control de cámara 3D" más arriba),
  calculado en `render_map_3d` como
  `normalize(app.camera3d.position - app.camera3d.target)`. `lighting_shader_init`
  solo resuelve `loc_view_dir`, no sube ningún valor.
- **Ciclo día/noche**: `DAY_NIGHT_KEYFRAMES` (4 fases —
  DAWN/NOON/DUSK/NIGHT, `constants.odin`) interpoladas linealmente en
  `day_night_sample` (`rendering.odin`), evaluadas cada frame en
  `render_map_3d`. Rompe a propósito la asunción original de "sunDir/
  sunColor/fillColor/ambient se setean una vez en init y no cambian" — se
  actualizan por `SetShaderValue` cada frame. Acumulador
  `lighting_shader.day_night_anim_time`, dt-clampeado, mismo patrón que
  dune/caustics/grass, pero gateado a `app.state == .PLAYING` (el preview
  de miniatura de mapa fuerza `.EDITOR` temporalmente, así que ya queda
  excluido sin código extra). Sin toggle en Settings — siempre activo,
  `DAY_NIGHT_CYCLE_SPEED` bajo a propósito (~6-7 min por ciclo completo).
  El especular (arriba) se recalcula solo frame a frame porque `halfVec`
  depende de `sunDir` en el fragment shader, no de un valor cacheado — pero
  su intensidad no fue re-chequeada contra los keyframes NIGHT/DUSK más
  oscuros/saturados, solo contra NOON.
- **Fondo (cielo) = color del sol actual**, no un color fijo por bioma —
  `sky_color_from_sun()` (`rendering.odin`) samplea
  `day_night_sample(lighting_shader.day_night_anim_time).sun_color` y lo
  convierte a `raylib.Color` (×255, clamp [0,1]). La usan los dos
  `ClearBackground` antes de dibujar el mapa (`render_game` y
  `render_map_preview_to_texture`) en vez de
  `constants.BIOME_COLORS[m.biome].bg`. Ese campo `.bg` de
  `BIOME_COLORS` queda sin usar en estos dos call sites — no se borró
  la constante en sí por si se usa en otro lado.
- **Sombra proyectada real (shadow mapping)** — reemplazó a las sombras de
  contacto falsas que hubo antes (`draw_contact_shadow_3d`, discos planos
  sin dirección bajo torres/árboles/bloques/enemigos — eliminadas). `Shadow_Map` (`rendering.odin`):
  depth pre-pass desde el punto de vista del sol, a una textura de
  profundidad muestreable creada a mano vía el camino de bajo nivel de
  `rlgl` (`LoadTextureDepth` + `LoadFramebuffer` + `FramebufferAttach`) —
  `raylib.LoadRenderTexture` normal NO sirve para esto, su adjunto de
  profundidad es un renderbuffer, no una textura sampleable.
  `shadow_light_matrix` arma una cámara ortográfica centrada en el mapa
  actual (no en la cámara del jugador — el mapa tiene extensión de mundo
  fija) siguiendo el `sunDir` del ciclo día/noche, recalculada cada frame
  (mismo criterio que `Pause_Blur`: no vale la complejidad de cachear e
  invalidar para un mapa de este tamaño). `render_shadow_depth_pass`
  dibuja los casters — torres, árboles en tierra, bloques/barras de
  obstáculo, puente, enemigos — con `assets/shadow_depth.vs/.fs` (shader
  mínimo, solo transforma posición) en vez de `lighting_shader.shader`,
  reusando exactamente los mismos procs de dibujo (`render_tower_3d`,
  `render_tree_3d`, etc. — geometría idéntica, shader distinto). El
  terreno **no** proyecta sombra (solo la recibe) — es la única malla con
  desplazamiento de vértices (el hundimiento del camino embossed), así que
  excluirlo como caster evita duplicar esa lógica en el shader de
  profundidad. `lighting.vs` computa `fragPosLightSpace` DESPUÉS del
  hundimiento del camino, para que la sombra caiga alineada con la franja
  ya tallada. `lighting.fs` hace PCF manual 3×3 (no hay sampler de
  comparación por hardware en estos bindings) y el factor de sombra solo
  atenúa el término de **sol** de la fórmula de luz, nunca ambient/fill —
  un fragmento en sombra plena no baja de `SHADOW_MIN_FACTOR` de sol
  (nunca negro puro, misma disciplina que el keyframe NIGHT).
  `SHADOW_DEPTH_BIAS` es el valor a tunear a ojo si aparece "acné" (bias
  chico) o "peter-panning"/sombra despegada de la base (bias grande) —
  ajustar de a un síntoma por vez, tiran en direcciones opuestas.
  **Trampa de orden**: el `EnableFramebuffer`/`DisableFramebuffer` del
  shadow pass (nivel `rlgl`, no `BeginTextureMode`) tiene que completar
  ANTES de que arranque el `BeginTextureMode` de `Pause_Blur` — si no, el
  `DisableFramebuffer` del shadow pass pisa el framebuffer del blur en vez
  de dejarlo activo. Por eso el pase de sombra en `render_game` está
  *afuera* del bloque que arma `is_paused_glass`, no "justo antes de
  `BeginMode3D`" como el resto del pipeline 3D. `render_map_preview_to_texture`
  (miniatura de mapa) también corre su propio shadow pass, una vez por
  preview generado (no por frame) — costo irrelevante.
  **Trampa ya pisada — se rompió la UI la primera vez**: `rlgl.SetMatrixProjection`/
  `SetMatrixModelview` (usados para armar la cámara ortográfica de la luz)
  escriben directo sobre el mismo storage interno que usa
  `raylib.BeginMode3D`/`EndMode3D` para su propia cámara — la primera
  versión de `render_shadow_depth_pass` los llamaba sin guardar/restaurar
  nada, así que después de terminar el pase de sombra quedaba pisada la
  proyección 2D de pantalla (la que usa toda la UI) con la ortográfica de
  la luz por el resto del frame — la interfaz se "desaparecía" (en
  realidad se dibujaba, pero proyectada con la matriz equivocada). Fix:
  `render_shadow_depth_pass` ahora hace exactamente el mismo manejo de
  matrices que `BeginMode3D`/`EndMode3D` hacen internamente —
  `rlMatrixMode(PROJECTION)` + `PushMatrix` antes de `SetMatrixProjection`,
  `PopMatrix` después (la proyección SÍ se apila); el modelview NO se
  apila, se resetea a identidad después (mismo criterio que `EndMode3D`,
  que tampoco restaura un modelview previo — el modo 2D siempre usa
  identidad). Cualquier código nuevo que toque `rlgl.SetMatrixProjection`/
  `SetMatrixModelview` fuera de `BeginMode3D` tiene que replicar este mismo
  patrón, si no la UI se rompe de la misma forma.
  **Trampa ya pisada — no se veía ninguna sombra proyectada**: en
  `shadow_light_matrix`, el ojo de la cámara-luz se calculaba como
  `center - sun_dir * SHADOW_LIGHT_DISTANCE`. `sun_dir` sigue la misma
  convención que `lighting.fs` documenta para `sunDir` — apunta DESDE la
  superficie HACIA el sol (arriba) — así que el ojo tiene que ubicarse
  `center + sun_dir * distancia` (del lado del sol, mirando hacia abajo al
  mapa), no restando. Con el signo invertido la "luz" quedaba del lado
  opuesto al sol real, apuntando en la dirección equivocada — el depth
  pass seguía compilando y corriendo sin error, pero no producía ninguna
  sombra utilizable sobre el terreno. Ojo con este mismo error de signo si
  se toca `sun_dir`/`sunDir` en cualquier código nuevo — la convención
  "apunta HACIA el sol" es fácil de invertir sin que nada lo marque en
  compilación.
  **Segunda trampa del mismo bug — seguía sin verse sombra tras arreglar el
  signo**: `shadow_map.depth_tex` no es parte de un `Material` (es una
  textura suelta, creada a mano vía `rlgl.LoadTextureDepth`) —
  `raylib.SetShaderValueTexture` NO sirve para bindearla como uniform
  `sampler2D` en este caso (a diferencia de `texture0`/`texture1` del
  terreno, que SÍ van vía `material.maps[...]` y por eso raylib los rebindea
  solo en cada `DrawModel`). Usar `SetShaderValueTexture` para `shadowMap`
  competía por texture units con esos maps del terreno — compilaba y
  corría sin error, pero terminaba leyendo la textura equivocada (o una
  unidad que `DrawModel` pisaba después), dando profundidad sin sentido y
  cero sombra visible. Fix, calcado del ejemplo oficial de raylib
  (`shaders_shadowmap.c`): `shadow_map_bind_for_sampling` elige un texture
  slot propio y fijo (`constants.SHADOW_MAP_TEXTURE_SLOT`, `10` — el
  terreno ya usa 0/1), lo bindea a mano con
  `rlgl.ActiveTextureSlot`/`EnableTexture`, y sube el uniform como un
  **entero** (`SetShaderValue(..., .INT)`, el índice de unidad), no como
  una `Texture2D`. Cualquier textura suelta (no de un `Material`) que se
  necesite samplear desde un shader propio en este proyecto debe seguir
  este mismo patrón, no `SetShaderValueTexture`.
  **Tercera trampa del mismo bug — seguía sin verse sombra en las esquinas
  del mapa (y a veces en todo el mapa, según la fase del ciclo día/noche)**:
  `shadow_light_matrix` armaba el frustum ortográfico con un `half_extent`
  isotrópico (mismo radio en las 4 direcciones, basado solo en la diagonal
  X/Z del mapa). Eso alcanza cuando el sol está casi vertical (NOON), pero
  para un ángulo con componente horizontal grande (DAWN/DUSK, las fases con
  más "sombra larga") la proyección del mapa sobre los ejes de la
  cámara-luz NO es un círculo — es un rectángulo estirado, y un
  half-extent isotrópico subestima el ancho real: las esquinas del mapa
  (a veces zonas enteras, según qué tan oblicuo esté el sol en ese momento)
  quedaban literalmente afuera del frustum ortográfico y no había ningún
  dato de profundidad ahí — cero sombra, sin ningún error. Fix: en vez de
  un radio fijo, `shadow_light_matrix` proyecta los 8 vértices del AABB
  real del mundo (todo el ancho/alto del mapa, Y desde `SHADOW_WORLD_Y_MIN`
  hasta `SHADOW_WORLD_Y_MAX` — rango pensado para cubrir tanto el
  hundimiento del camino embossed como el caster más alto) a espacio de la
  cámara-luz vía `raylib.Vector3Transform(corner, view)`, y arma los 6
  planos del frustum (`MatrixOrtho` + near/far) con el min/max real de esas
  8 proyecciones. Cualquier frustum de cámara calculado a mano en este
  proyecto (no solo de sombra) debería preferir este método — un
  half-extent/radio fijo solo es válido si la orientación de la cámara no
  cambia, y acá sí cambia (con el sol en movimiento).
  **Cuarta trampa del mismo bug — la de raíz, la que hacía que
  `shadowDebugView` (F9) diera magenta en TODA la pantalla**: el orden de
  composición `light_space := shadow_map.view * shadow_map.proj` estaba
  invertido. Para transformar un punto de MUNDO a espacio de la luz hace
  falta aplicar `view` primero (mundo→vista) y `proj` después
  (vista→clip): `clip = proj*(view*punto) = (proj*view)*punto`. Con
  `view*proj` en cambio se computa `view*(proj*punto)` — proj aplicado
  primero a un punto que todavía está en espacio de MUNDO, sin sentido
  matemático. Se verificó a mano con un caso real (centro del mapa,
  `view_z=-30` exacto — confirmado con una transformación de `view` sola,
  por separado) y con un script standalone (no el juego) que probó las
  dos composiciones posibles: `view*proj` daba `clip.z≈-40` (muy afuera de
  `[-1,1]`) mientras que `proj*view` daba `clip.z≈0.045` (adentro,
  correcto). El script también confirmó que **`raylib.MatrixOrtho` en sí
  nunca fue el problema** — con el orden correcto (`proj*view`) da
  exactamente el mismo resultado que una matriz ortográfica armada a mano
  con la fórmula estándar de OpenGL; una hipótesis anterior (revertida)
  había sospechado de una inconsistencia entre `MatrixOrtho`/`MatrixLookAt`
  que en realidad no existe. **Antes de aceptar una hipótesis sobre una
  función de raylib/linalg "que no hace lo que dice", verificarla con un
  script standalone de pocas líneas** (como
  `/tmp/.../ortho_test_dir/ortho_test.odin` de esta sesión, ya descartable)
  en vez de solo derivarla a mano — ahorra exactamente este tipo de vuelta
  en U. Esto explica por qué las tres trampas anteriores (signo del sol,
  texture unit, half-extent isotrópico) eran todas reales y necesarias,
  pero ninguna alcanzaba sola — esta era la que de verdad impedía ver
  cualquier sombra, exactamente en el mismo lugar (`shadow_map_bind_for_sampling`)
  donde ya se habían corregido las otras.
  **Herramientas de debug usadas para encontrar esto, ya sacadas del
  código** una vez confirmado el fix: la tecla F9 (mostraba
  `shadow_factor()`/profundidad cruda en vez del color final — magenta =
  fuera del frustum de luz, gris = adentro), el recuadro en la esquina con
  el contenido crudo de `shadow_map.depth_tex`, y el `fmt.println` que
  imprimía la profundidad esperada del centro del mapa. Si hace falta
  volver a diagnosticar algo parecido, el patrón que funcionó fue: (1)
  visualizar la textura de profundidad cruda para confirmar que el depth
  pass en sí genera datos con sentido, (2) visualizar `shadow_factor()`
  como color plano para separar "problema en el cálculo de sombra" de
  "problema en cómo se mezcla con el resto de la iluminación", y (3) un
  `fmt.println` puntual con un caso numérico concreto (no solo mirar
  código) para confirmar o descartar una hipótesis de matriz antes de
  tocar nada — así se encontró que el bug real era el orden `proj*view`
  vs `view*proj`, no las dos hipótesis anteriores (que también eran reales
  pero no alcanzaban solas).

**Trampa real (no la de arriba) — `raylib.DrawCylinder`/`DrawCylinderEx` no
tienen normal real:** el comentario de `lighting.vs` sobre "locations
explícitas" solo resuelve que el atributo de normal aterrice en el slot
correcto (2) — nunca garantizó que `rlgl` tuviera un valor *distinto por
vértice* ahí adentro. `raylib.DrawCylinder`/`DrawCylinderEx` (a diferencia
de `DrawCube`, que sí llama `rlNormal3f` por cara) no llaman `rlNormal3f`
en absoluto: el atributo de normal que le llega al shader es el que haya
quedado de la última llamada a `rlNormal3f` en TODO el frame — constante
para el objeto entero. Efecto visible: el cuerpo/cañón de las torres (las
únicas formas del juego dibujadas con `DrawCylinder`/`DrawCylinderEx` bajo
el shader de iluminación) se veían como una silueta plana de un solo tono,
sin gradiente de luz/sombra, en vez de un cilindro tallado. Fix: dos
helpers nuevos en `rendering.odin` (`draw_cylinder_lit_3d` para el cuerpo,
`draw_cylinder_ex_lit_3d` para el cañón) que dibujan la misma geometría a
mano vía `rlgl.Begin/Normal3f/Vertex3f/End`, con normal radial real por
vértice (más plana en las tapas). `draw_tower_shape_3d` los usa en vez de
`raylib.DrawCylinder`/`DrawCylinderEx`. **No se tocó nada más** — el resto
de los `DrawCylinder` del proyecto (nenúfares, sombras de contacto,
spawn/goal, proyectiles, árboles/bloques que usan `DrawCube`) no se
corrigieron: o están fuera del shader de iluminación (no les importa la
normal) o son formas chicas/finas donde la falta de normal real no se nota
a simple vista. Si en algún momento se nota lo mismo en otro objeto bajo
`BeginShaderMode(lighting_shader...)` — confirmado que `DrawCube` sí llama
`rlNormal3f` por cara (no tiene este problema); no se verificó `DrawSphere`
(usada por enemigos) — el mismo patrón de helpers manuales por `rlgl`
aplicaría si hiciera falta.

## Overlays de bioma del terreno 3D (dunas, roca, pasto, cáusticas)

Viven todos dentro de `assets/lighting.fs` (`duneOverlay`/`rockOverlay`/
`grassOverlay`/`waterCausticsOverlay`), aplicados en un único pase de
fragment shader sobre la malla del terreno — no hay una capa/pasada de
render por overlay como en el viejo camino 2D (`assets/dune.glsl`/
`rock.glsl`/`grass.glsl` originales, cuya lógica se portó ahí adentro, ver
comentarios en el propio `lighting.fs`). Los uniforms por bioma
(seed/alpha/density/color, sacados de `BIOME_DUNE_STYLES`/
`BIOME_ROCK_STYLES`/`BIOME_GRASS_STYLES` en `constants.odin`) se hornean una
vez en `terrain_cache_ensure` (`systems/rendering.odin`) cuando se
(re)construye la malla del mapa, y el tiempo animado
(`lighting_shader.dune_anim_time`/`caustics_anim_time`/`grass_anim_time`) se
acumula en `render_map_3d` cada frame — mismo patrón dt-clampeado descrito
en "Animación de shaders" más abajo.

**Dunas** (`duneOverlay`, bioma DESERT): ruido 2D barato con **ridged
noise** (`1.0 - abs(n*2-1)`, técnica de Musgrave: pliega un value noise
sobre su punto medio y convierte colinas suaves en crestas afiladas) — 4
octavas dan la forma grande de la duna estirada a lo largo de un viento
fijo, más dos capas de estrías finas en frecuencias distintas cuya fase se
corre con la forma grande (para que trepen las crestas en vez de quedar
paralelas) y se afilan con `sign()*pow()`. Grano fino estático encima.
**No** depende de `m.heightmap` — el heightmap es desnivel de terreno, sin
relación real con dónde hay arena (dependencia sacada a pedido explícito
en su momento; no reintroducirla sin que el usuario lo pida de nuevo).

**Roca agrietada** (`rockOverlay`, bioma MOUNTAIN): **Voronoi F1/F2**
(distancia al punto-semilla más cercano y al segundo más cercano de una
grilla jitereada — ver iquilezles.org/articles/voronoilines). La
diferencia `F2-F1` da las líneas de grieta entre placas; el hash de la
celda ganadora varía el tono de cada placa; grano fino estático encima.
Voronoi es la técnica correcta para "placas separadas por grietas" (vs.
ridged noise, que es para "ondulación continua" como las dunas).

`BIOME_DUNE_STYLES`/`BIOME_ROCK_STYLES`/`BIOME_GRASS_STYLES` tienen
`alpha = 0.0` en cualquier bioma que no sea el suyo — mutuamente
excluyentes entre sí vía `groundMix` en `lighting.fs` (además de excluidos
de tiles de camino/agua).

## Anillos de brillo de spawn/goal-reach (glow_ring.vs/.fs)

La ráfaga de 4 anillos que sale al aparecer un enemigo (blancos, suben) o al
llegar al goal (rojo oscuro, caen y se contraen) — no es la ficha de spawn/
goal en sí (eso siempre fue un disco plano de color sólido, `render_spawn_3d`/
`render_goal_3d`, sin sombra ni animación, en 2D y en 3D por igual). La
lógica CPU (`Glow_Particle`, `spawn_glow_particles` en `simulation.odin`, 4
anillos por evento, `LIFETIME=0.5s`, easing cuadrático) nunca se tocó en la
migración a 3D — lo que se perdió fue el shader: el viejo `assets/glow_circle.glsl`
(2D, con falloff gaussiano centrado en `d=0.45` del UV) se borró junto con
el resto de los shaders 2D-only, y `render_glow_particles_3d` quedó
dibujando un `draw_ground_ring` de borde duro (`DrawCircle3D`) en su lugar.

`glow_ring.vs`/`glow_ring.fs` portan el mismo cálculo de anillo (mismo
falloff, mismos números) a una malla 3D real: `draw_glow_ring_3d` dibuja un
quad chato sobre el plano XZ en modo inmediato de rlgl (`rlgl.Begin(QUADS)`),
con UV (0,0)-(1,1) en las esquinas para que el fragment shader arme
`uv*2-1`. El color/alpha (tinte por `kind` + fade-out por vida) se resuelven
en Odin antes de dibujar y viajan por `fragColor` — el shader no tiene
uniform de tinte separado. `render_glow_particles_3d` ahora envuelve el
loop en un único `BeginShaderMode(glow_ring_shader)`/`EndShaderMode`, fuera
del shader de iluminación (sigue sin normales, mismo criterio que los
demás rings/líneas).

## Fondo animado (nebula.glsl)

Activado vía `constants.NEBULA_BACKGROUND_ENABLED :: true` (gatea la
llamada a `nebula_draw()` en `render_game`, usado en MENU, RUN_COMPLETE,
CAMPAIGN_MAP, PROGRESSION, LIBRARY). Poner el flag en `false` lo desactiva
sin tocar nada más — la infraestructura (`nebula_init/unload/draw`) queda
cargada igual.

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

`raylib.GetTime()` es reloj de pared — sigue corriendo aunque la ventana
esté minimizada/sin foco y el loop deje de renderizar frames reales. Al
recuperar el foco, el salto entre el último frame dibujado y el actual se
leía como que la animación "se acelera" de golpe (bug real de una versión
vieja de `water.glsl`, ya no existe ese archivo pero el patrón que lo
arregló sigue vigente).

**Patrón:** acumular el tiempo a mano con `dt` clampeado en vez de leer
`GetTime()` directo. Ejemplo vivo — `render_map_3d`
(`systems/rendering.odin`) acumula `lighting_shader.dune_anim_time`/
`caustics_anim_time`/`grass_anim_time` cada frame con
`min(raylib.GetFrameTime(), constants.WATER_ANIM_MAX_DT) *
<ESO>_ANIM_SPEED` (evita saltos por hitches o al recuperar foco). Si se
agrega otro shader animado por tiempo, replicar este mismo patrón.

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

### render_tower_ranges_3d (systems/rendering.odin)

Dibuja los círculos de rango de torres como capa separada entre
`render_map_3d` y `render_map_objects_3d`, llamado cada frame desde
`render_game`.

- Modo "todas las torres" (`show_tower_range` activo): un solo
  `draw_ground_ring` semitransparente (`TOWER_RANGE_PREVIEW`) por torre.
- Torre seleccionada (siempre): **dos** `draw_ground_ring` superpuestos —
  relleno sutil (`TOWER_RANGE_PREVIEW`) + outline nítido (blanco,
  alpha=200) — el outline es la parte que realmente se ve; sin él el rango
  es casi invisible.

**Trampa:** al editar el bloque de la torre seleccionada es fácil borrar
el segundo `draw_ground_ring` (el outline) si se reemplaza solo parte del
bloque. Verificar que ambas llamadas sigan presentes.

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

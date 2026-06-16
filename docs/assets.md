# Asset Pipeline

Documenta cómo se organizan los assets del juego, qué tipos viven dónde y cómo
agregar uno nuevo sin romper nada. Mantener este archivo actualizado cada vez
que se agregue un nuevo directorio o tipo de asset.

---

## Layout de directorios

```
towerdef_odin/
├── assets/        # Shaders GLSL (cargados en runtime via raylib)
├── audio/         # Efectos de sonido y música (.ogg)
├── fonts/         # Tipografías (.ttf / .otf)
├── images/        # Iconos y sprites (.png)
├── maps/          # Mapas guardados (.map, formato texto)
├── savegame.bin   # Progreso del jugador (binario)
├── campaign.bin   # Definición de la campaña (binario, autoría por dev)
└── settings.json  # Configuración del usuario (JSON)
```

Todos los paths que el juego usa son **relativos al ejecutable**. Si corrés
`towerdef_odin.exe` desde otro directorio, los assets no se encuentran.

---

## Shaders (`assets/*.glsl`)

GLSL 330 core. Cada shader corresponde a una capa visual:

| Archivo | Uso | Struct loader |
|---|---|---|
| `nebula.glsl` | Fondo animado de menú y juego | `Nebula_Shader` en `rendering.odin` |
| `clouds.glsl` | Capa de nubes con parallax sobre el mapa | `Cloud_Shader` |
| `water.glsl` | Blur + threshold para charcos de agua | `Water_Shader` |
| `heightmap.glsl` | Tinte continuo del terreno por altura | `Heightmap_Shader` |

### Agregar un nuevo shader

1. Crear `assets/mi_shader.glsl` siguiendo la convención de raylib: usar
   `fragTexCoord`, `fragColor` como inputs; `finalColor` como output; uniforms
   con prefijo `u_*`.
2. En `systems/rendering.odin`, agregar:
   - Struct `Mi_Shader :: struct { shader: raylib.Shader, loc_*: i32, ... }`
   - Global `mi_shader: Mi_Shader`
   - Proc `mi_shader_init :: proc()` que llama `raylib.LoadShader` y resuelve
     uniform locations con `raylib.GetShaderLocation`.
   - Proc `mi_shader_unload :: proc()` con `raylib.UnloadShader`.
3. En `main.odin`, después de los otros `*_shader_init()`:
   ```odin
   systems.mi_shader_init()
   defer systems.mi_shader_unload()
   ```
4. Usar el shader: `raylib.BeginShaderMode(mi_shader.shader); ...; raylib.EndShaderMode()`.

### Sanity check

`shader.id <= 1` significa que el load falló (raylib devuelve el shader default).
Hacer early-return en el `*_draw` proc para no corromper el rendering.

---

## Audio (`audio/*.ogg`)

Vorbis OGG. Cada SFX se carga al iniciar el juego en `systems/audio.odin` →
`audio_init()`. Las variantes se cargan en arrays (`tick_sounds[3]`,
`ice_sfx[3]`, `card_sfx[3]`) para variar aleatoriamente.

### Agregar un sonido nuevo

1. Copiar el `.ogg` a `audio/`. Convención de nombres: kebab-case
   (`zap_three_tone.ogg`) o el nombre original del pack si vino así.
2. En `audio.odin`, agregar al enum `Sound` el nuevo valor (ej. `MY_NEW_SOUND`).
3. En `audio_init`, cargarlo:
   ```odin
   audio_state.sounds[.MY_NEW_SOUND] = raylib.LoadSound("audio/mi_sonido.ogg")
   ```
4. En `audio_cleanup`, agregar `raylib.UnloadSound(audio_state.sounds[.MY_NEW_SOUND])`.
5. Reproducir con `play_sound(.MY_NEW_SOUND, .SFX)` (o `.UI` si va por el bus de UI).

### Layers de volumen

Hay dos buses: `.UI` y `.SFX`. Cada uno con su volumen aplicado encima del master.
Configurable desde `settings.json` (`ui_volume`, `sfx_volume`, `master_volume`).

---

## Fonts (`fonts/`)

Cargadas en `constants/fonts.odin` → `load_fonts()`. Hay 4 pesos:

- `game_fonts.light`
- `game_fonts.regular`
- `game_fonts.semibold`
- `game_fonts.bold`

Filtro: `TRILINEAR` con mipmaps para que se vean limpias a cualquier zoom.

### Cambiar la tipografía

Reemplazar los archivos en `fonts/` manteniendo los nombres. Si necesitás cambiar
el filename, editar `load_fonts()`. El font size se elige por uso (la fuente se
carga a 96px y raylib la reescala).

---

## Images (`images/*.png`)

Iconos de UI, principalmente. Dos cargadores:

- `constants/fonts.odin` → `load_icons()` carga los iconos genéricos
  (`damage.png`, `speed.png`, `crit.png`, etc.). Liberados en `unload_icons()`.
- `entities/card.odin` → `load_relic_icons()` carga los iconos de reliquias
  (`icon_<relic>.png`) y los indexa por `Card_Kind`. Configurado por la tabla
  `RELIC_SPECS` — cada entrada tiene un `icon_path`.

### Agregar un icono de relic

1. Diseñar 64×64 (o múltiplo de 16) PNG transparente. Convención de nombre:
   `images/icon_<relic_lowercase>.png`.
2. En `entities/card.odin`, agregar la entrada a `RELIC_SPECS` con
   `icon_path = "images/icon_mi_relic.png"`. El loader ya itera la tabla.
3. Verificar que el `Card_Kind` correspondiente existe en el enum.

### Agregar un icono de UI genérico

1. Copiar PNG a `images/`.
2. En `constants/fonts.odin`, agregar campo a `game_icons: Game_Icons` y un
   `LoadTexture` + `SetTextureFilter(.TRILINEAR)` en `load_icons()`. Liberar
   en `unload_icons()`.

---

## Maps (`maps/*.map`)

Formato de texto custom (parser en `entities/map.odin` → `map_load`/`map_save`).
Estructura por línea:

```
FIRST_IMPACT_MAP          # header magic
1                         # version
20                        # width
20                        # height
0                         # biome (Biome enum value)
12345                     # seed (i32, drives heightmap)
<grid 20×20 de tiles>     # tile values separados por espacio
<obstacle_grid 20×20>     # obstacle tiles
<water_grid 20×20>        # 0/1 por celda
```

### Agregar un mapa

Usar el editor en runtime (botón Editor en menú principal, sólo DEVELOPER).
Click derecho para pintar, `Ctrl+S` o el botón Save para guardar con timestamp.
El mapa se guarda como `map_<timestamp>.map` Y como `last_saved.map` (sobrescribe).

Renombrar desde el Map Browser ("Renombrar" en el footer).

---

## Persistence files (root)

| Archivo | Contenido | Formato | Versionado | Doc |
|---|---|---|---|---|
| `savegame.bin` | Meta_State (cristales, unlocks, campaign progress) | Binario raw (`mem.ptr_to_bytes(Meta_State)`) | `version: u32` en header. Versión vieja → save descartado con log. | `entities/meta.odin` |
| `campaign.bin` | Campaign_File (definición de la campaña por el dev) | Binario raw | Igual que meta. Versión vieja → load falla, campaña vacía. | `entities/campaign.odin` |
| `settings.json` | Configuración del usuario (volumen, idioma, fullscreen) | JSON | Sin versionado — fields nuevos = defaults | `main.odin` |

### Cambiar el schema de un binario

1. Bumpear la constante de versión (`META_SAVE_VERSION`, `CAMPAIGN_SAVE_VERSION`).
2. Cambiar el struct (agregar campos al final, reducir `_pad` si es necesario).
3. Si querés mantener saves viejos, implementar parser por versión (ver issue #2
   de la auditoría).

---

## Translations (`translations.txt`)

No es un asset binario pero vive en root y se carga al inicio. Formato
`KEY|LANG|texto`. 3 idiomas: ENGLISH, SPANISH, PORTUGUESE.

### Agregar una key

1. Editar `translations.txt` con las 3 líneas (una por idioma).
2. Usar en código: `constants.get_text("MI_KEY")` o `constants.get_text_f("MI_KEY", args...)`.

Convención de naming: `MODULE_SECTION_NAME` (ej. `CAMPAIGN_EDITOR_REMOVE`,
`SHOP_BIOME_FOREST`).

---

## Convenciones generales

- **Path absoluto vs relativo**: todo el código usa paths relativos al CWD del
  ejecutable. No hardcodear paths absolutos.
- **Lifecycle**: cada `Load*` tiene su `Unload*` en `main.odin` con `defer`.
  Si agregás un nuevo asset cargado en runtime, agregalo a este patrón.
- **Tamaños**: shaders <5KB cada uno, iconos 64×64, audio comprimido en .ogg.
  El binario final del juego debería poder shipear sin embedded resources
  (lee desde disco al iniciar).
- **Determinismo**: el seed del mapa determina el heightmap. Los assets no
  introducen randomness — eso vive en `core:math/rand` con seed controlado.

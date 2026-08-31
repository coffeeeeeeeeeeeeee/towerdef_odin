# Mapa 3D real en modo PLAYING (towerdef_odin)

## Contexto

El juego renderiza hoy el mapa 100% en 2D top-down, sin `Camera2D` ni ninguna
noción de cámara: cada función de `systems/rendering.odin` calcula
`screen_x = col*cs + camera_offset_x` a mano, y `screen_to_grid`
(`systems/input.odin`) hace la inversa exacta. El usuario pidió pasar el mapa
de la pantalla PLAYING a 3D real, con `raylib.Camera3D` de verdad (no un
efecto pseudo-3D con sprites). Se confirmaron estas decisiones de alcance:

- Cámara 3D real, pero **fija** en ángulo isométrico/top-down inclinado — el
  jugador no rota/orbita, solo pan+zoom como hoy.
- Torres, enemigos, obstáculos y proyectiles pasan a primitivas 3D simples de
  raylib (`DrawCube`, `DrawCylinder`, `DrawSphere`, etc.), reusando paletas de
  color ya existentes — sigue siendo 100% procedural, sin modelos externos.
- Los shaders de bioma actuales (agua/camino/dunas/rocas — todos post-proceso
  2D sobre `RenderTexture2D`) se desactivan en esta v1: color plano por tile.
  El `heightmap` que ya existe (hoy solo un overlay de sombreado 2D, sin
  desplazar geometría) pasa a dar altura real a los tiles.
- La UI/HUD se mantiene 100% 2D, dibujada como overlay después de
  `EndMode3D()` (raylib permite alternar 2D/3D libremente en el mismo frame).
- El thumbnail del selector de mapas (`render_map_preview_to_texture`) **se
  mantiene en 2D** — vista top-down limpia sin trabajo extra, conserva las
  funciones 2D de terreno solo para ese uso.
- El código 2D reemplazado (agua/camino/grilla/heightmap-overlay/dunas/rocas,
  variantes 2D de torres/enemigos/proyectiles) **se borra** una vez migrado y
  verificado — no queda detrás de un flag.

No hay ninguna API 3D de raylib usada hoy en el repo (grep confirmado) — es
una implementación desde cero.

## Diseño

### Coordenadas y voxel-grid (no malla continua)

`world_x = col*WORLD_CELL_SIZE`, `world_z = row*WORLD_CELL_SIZE`,
`world_y = heightmap[row][col]*WORLD_HEIGHT_SCALE`. Un tile = un `DrawCube`
con esa altura y color plano por bioma/tipo (agua/camino/pasto), en vez de
una malla continua — coherente con que el resto del juego ya es "un tile/
entidad = una primitiva simple", y con que los shaders de transición suave
quedan apagados (una malla continua no aportaría nada sin ellos). Además el
picking contra una grilla regular de AABBs es trivial (`GetRayCollisionBox`),
mientras que contra una malla heightmap requeriría raycast contra mesh.

Nuevas constantes en `constants/constants.odin`: `WORLD_CELL_SIZE`,
`WORLD_HEIGHT_SCALE`, `CAMERA_PITCH_DEG`, `CAMERA_FOVY`,
`CAMERA_DISTANCE_MIN/MAX`.

### Cámara fija-isométrica

`App_State` (`entities/app.odin`) gana `camera3d: raylib.Camera3D` y
`camera_focus`/`target_camera_focus: raylib.Vector3` (reemplazan
conceptualmente `camera_offset_x/y` en unidades de mundo, no píxeles). Cada
frame:

```
camera.target   = camera_focus
camera.position = camera_focus + offset_dir_fijo * distance(app.zoom)
camera.up       = {0,1,0}
```

`offset_dir_fijo` sale del ángulo fijo (`CAMERA_PITCH_DEG`); `distance(zoom)`
mapea el zoom actual a distancia de cámara (zoom in = más cerca). El easing
de `main.odin:184-245` se mantiene estructuralmente, solo cambian los campos
que interpola (de `i32` píxeles a `Vector3` mundo).

**Pan y zoom-to-cursor** (`systems/input.odin`, `input_handle_camera`): en
vez de sumar deltas de píxeles directo, raycastear el punto bajo el cursor
contra el plano `y=0` antes/después del delta y mover `camera_focus` por la
diferencia en mundo — generaliza el zoom-to-cursor actual al caso 3D.

### Picking: `screen_to_grid` por raycast

Misma firma pública (no tocar los ~20 call-sites que la consumen). Nueva
implementación: `raylib.GetScreenToWorldRay` + intersección contra el plano
`y=0` (más simple, arrancar por acá) → `(col, row) = (point.x, point.z) /
WORLD_CELL_SIZE`. Si en la práctica hay descalce notorio de picking en tiles
con heightmap alto, pasar a `GetRayCollisionBox` contra AABBs reales por tile
(marcado como posible ajuste, no bloqueante).

### Terreno y objetos del mundo

`render_map_3d` (nueva, en `systems/rendering.odin`) reemplaza `render_map`
para PLAYING/PAUSED/EDITOR: un `DrawCube` por tile con altura del heightmap y
color plano (bioma/agua/camino, tablero de ajedrez sutil como reemplazo
barato de las líneas de grilla). Los shaders de bioma dejan de invocarse
desde este camino.

Tabla de reemplazo 2D→3D en `systems/rendering.odin` (misma organización de
archivo, `rendering.odin` sigue siendo "todo lo que dibuja el mundo"):

| 2D actual | 3D nuevo |
|---|---|
| `draw_tower_tile`/`render_tower` | `DrawCylinder`/`DrawCube` por tipo + barril orientado con `angle`, recoil a lo largo del eje |
| `render_spawn`/`render_goal` | Primitivas simples (cubo/cono) |
| `render_obstacles`/árboles/bloques | `DrawCube`/`DrawCylinder` según altura/tipo |
| `render_laser_beams` | `DrawLine3D`/`DrawCylinderEx` entre torre y objetivo |
| `render_enemy_shape` | `DrawSphere` (normal), cubo (boss), cono (flying); squash anisotrópico pasa a escalar X/Z |
| `render_projectiles` | `DrawSphere`/`DrawCylinderEx` orientado, arco parabólico como offset en Y |
| `render_explosions`/`hit_particles`/`glow_particles` | Esferas/`DrawCircle3D` planos sobre el suelo |
| `render_tower_ranges` | `DrawCircle3D` sobre el tile de la torre |
| `render_damage_numbers` | Se queda 2D — reproyectar con `raylib.GetWorldToScreen`, dibujar fuera de `BeginMode3D` |

Todo el bloque `render_map`+`render_tower_ranges`+`render_map_objects`+
`render_gameplay` (salvo `render_damage_numbers`) queda envuelto en
`BeginMode3D(app.camera3d)/EndMode3D()` dentro de `render_game`.

**Overlays de acción por tile** (reticles de LUMBERJACK/GARDENER, hoy
`CheckCollisionPointRec` en coordenadas de pantalla): reemplazar por comparar
`(row,col)` contra el resultado de `screen_to_grid`, ya no tiene sentido un
rect-collision de pantalla con cámara en perspectiva.

### PAUSED / EDITOR

Comparten el mismo `render_map`/`render_map_objects` que PLAYING vía el mismo
check de estado — quedan en 3D automáticamente, sin trabajo extra aparte del
ya descrito. El vidrio esmerilado de PAUSED (`Pause_Blur`) sigue funcionando
igual: `BeginMode3D`/`EndMode3D` puede correr dentro de un `BeginTextureMode`
activo sin problema; como ya no se llaman `water_render_mask`/
`path_render_mask` desde el camino 3D, se puede simplificar ese precómputo.

### Preview de mapas — se mantiene en 2D

`render_map_preview_to_texture` sigue llamando a las funciones 2D de
terreno, renombradas (p. ej. `render_map` → `render_map_2d_legacy` antes de
que la 3D tome su lugar) para que sobrevivan solo para este uso.

## Pasos de implementación (cada uno debe compilar con
`odin build . -out:<scratch>` antes de seguir — nunca ejecutar el binario)

1. Cámara 3D fija + terreno voxel con heightmap y color plano, sin input
   (foco de cámara hardcodeado al centro del mapa). Envolver en
   `BeginMode3D`/`EndMode3D`.
2. Picking por raycast (plano `y=0`) reemplazando `screen_to_grid`; conectar
   pan/zoom-to-cursor.
3. Torres/obstáculos/spawn/goal/árboles/bloques en 3D, ghost de construcción,
   `render_tower_ranges`, overlays de acción por tile vía `screen_to_grid`.
4. Enemigos/proyectiles/explosiones/partículas en 3D.
5. Verificar que la UI 2D (HUD, mano de cartas, tooltips, números de daño
   reproyectados) sigue funcionando igual sobre el mundo 3D.
6. Limpieza: borrar las funciones 2D reemplazadas (agua, camino, grilla,
   heightmap-overlay, dunas, rocas, variantes 2D de torres/enemigos/
   proyectiles), conservando únicamente las renombradas para el preview de
   mapas del paso "Terreno y objetos del mundo".

## Riesgos señalados (no resueltos de antemano)

- **Costo de geometría inmediata por frame**: ~400 `DrawCube` de terreno +
  torres/enemigos/proyectiles con `rlgl` en modo inmediato podría pesar en
  oleadas grandes. No optimizar de entrada — medir en el paso 1; si hace
  falta, cachear el terreno como `Mesh`/`Model` estático regenerado solo al
  cambiar de mapa.
- **Escala del heightmap**: fue pensado para un shading 2D sutil, no para
  desplazar geometría real — `WORLD_HEIGHT_SCALE` (y posiblemente
  `HEIGHTMAP_FREQUENCY`/octavas) van a necesitar ajuste visual iterativo en
  el paso 1, no hay forma de calcularlo a priori.
- **Precisión del picking en tiles altos**: el raycast contra plano `y=0`
  puede desfasarse en tiles con heightmap pronunciado — revisar tras el paso
  2, fix conocido si hace falta (AABB real por tile).
- **Sensación de zoom-to-cursor en perspectiva**: el algoritmo de doble
  raycast debería replicar la sensación actual pero no es garantía
  matemática 1:1 con el comportamiento 2D — validar visualmente en el paso 2.

## Archivos críticos

- `systems/rendering.odin` — grueso del trabajo (terreno, torres, enemigos,
  proyectiles, partículas, rangos)
- `systems/input.odin` — `screen_to_grid`, `input_handle_camera`
- `entities/app.odin` — `camera3d`, `camera_focus`/`target_camera_focus`
- `main.odin` — interpolación de cámara, handler de resize
- `entities/map.odin` — sin cambios funcionales (se reutiliza `heightmap`)
- `constants/constants.odin` — constantes nuevas de mundo/cámara

## Verificación

`odin build . -out:<scratch>` limpio después de cada paso (patrón ya
establecido del proyecto: solo compilar, nunca correr el binario). Al cierre
del plan, el plan completo se guarda en `3D_RENDER_PLAN.md` dentro de
`~/dev/towerdef_odin` (pedido explícito del usuario), no solo en el archivo
de plan de la sesión.

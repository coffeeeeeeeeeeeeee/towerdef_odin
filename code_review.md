# Code review — towerdef_odin

Auditoría general de un proyecto Odin / Raylib de ~11k líneas (20 archivos). Foco solicitado: escalabilidad (torres, cartas, reliquias, enemigos), manejo de memoria y código redundante. El reporte separa lo que **ya quedó arreglado en esta pasada** de lo que **conviene atacar después**.

## Estado general

Diseño limpio en arquitectura (entities / systems / constants), buen comentario en español, CLAUDE.md actualizado y útil. El motor de simulación, mazo, oleadas y reliquias funcionan. Los problemas que aparecen son los típicos de un juego que creció rápido: añadir cosas nuevas requiere tocar 10–15 lugares y eso ya empezó a generar bugs por omisión.

Veredicto: **necesita refactor para seguir escalando, pero no hay nada estructural irrecuperable**.

## Fixes aplicados ahora

| # | Archivo | Cambio |
|---|---------|--------|
| 1 | `systems/rendering.odin:35-46` | Restaurar `DrawCircleLines` en el outline de rango de la torre seleccionada. Sin esto el rango era prácticamente invisible (bug documentado en CLAUDE.md). |
| 2 | `constants/fonts.odin` | `SetTextureFilter` y `UnloadTexture` para `veteran` y `loot` (estaban siendo cargados pero no filtrados ni liberados). |
| 3 | `entities/enemy.odin` | `obstacle_damage` ahora es `map[[2]i32]bool` en lugar de `map[string]bool` con keys de `fmt.tprintf`. Las keys vivían en `context.temp_allocator` y se liberaban al final del frame — lectura de memoria dangling. |
| 4 | `entities/map.odin` | `map_destroy`, `map_clear` y `map_load` ahora liberan las strings clonadas del `tile_data` antes de borrar el map. Antes leakeaban keys cada vez que el editor limpiaba o cargaba un mapa. |
| 5 | `main.odin:app_destroy` | Libera `app.toasts` y los `message` clonados de los toasts pendientes al cerrar la app. |

## Bugs serios pendientes

**1. La opción "Play" del menú principal no funciona.** `menus.odin:145` setea `app.state = .PLAYING` pero no llama `simulation_init_from_editor` ni carga un mapa por defecto. Sólo el botón "Test" del editor inicia bien la simulación. Recomendación: si no hay mapa cargado, el botón Play del menú debería abrir el browser de mapas o cargar `default.map`.

**2. "Game Over → Menú" no resetea la simulación.** `menus.odin:1217` sólo cambia estado. Si después se vuelve a `.PLAYING` por cualquier vía sin pasar por `simulation_init_from_editor`, se hereda `health=0` y la partida termina en el primer frame.

**3. Performance: `tower_count_line` corre por cada evento de daño.** `calc_damage` → `tower_is_in_formation` → `tower_count_line` × 4 direcciones × scaneo lineal de todas las torres. Con 40 torres y 100 enemigos hay miles de operaciones por frame. Cachéa el flag `_in_formation` por torre y recalculá cuando se construye/vende una torre.

**4. `update_auto_upgrade` cuando `auto_stacks` es alto.** En cada tick (cada 2s) hace `auto_stacks` pasadas completas sobre torres + obstáculos buscando el más barato. Con 5 stacks y un mapa lleno es notable. Solución: ordenar candidatos una vez por tick y consumir el ranking.

**5. `find_target` y `nullify_projectile_targets`.** El primero hace `make/delete` de un dynamic array por torre por frame. El segundo es O(proyectiles × enemigos\_muriendo) y se llama dos veces por enemigo (goal + death). Reemplazar el dynamic por un buffer fijo en la torre o usar índice estable en vez de puntero al enemy resuelve ambos.

**6. `enemy_apply_slow` tiene una condición sospechosa.**
```odin
if factor < e.slow_factor || e.slow_timer <= 0 {
    e.slow_factor = factor
}
```
Si llega un slow más débil (factor mayor) cuando ya hay uno activo, no debería sobreescribir. Pero `slow_timer` siempre se refresca abajo, así que un slow débil **extiende** la duración del slow fuerte vigente. Probablemente no es lo que se quiere; lo natural es que un slow más débil ni siquiera refresque.

## Escalabilidad — el tema central

### Torres

Bastante data-driven gracias a `TOWER_SPECS[Tower_Type]`. Lo que no escala:

- **Mapeo `Tile ↔ Tower_Type`** duplicado en `tile_to_tower_type` (`input.odin:521`), `card_to_tile` (`card.odin:281`), el switch de `simulation_init_from_editor` y los tres switch grandes en `rendering.odin` (línea 1098, 1162, 1162). Cada torre nueva exige ≥6 ediciones.
- **Comportamiento hard-coded** en `update_towers`: switch por `tower.type` para LASER / ICE / ENHANCE / proyectil. La forma escalable es asociar un puntero a `proc(app, ^Tower, dt)` dentro del spec.
- **Render** está hecho con un switch monolítico en `draw_tower_tile`. Considerar mover la receta visual al spec (campos `barrel_w`, `barrel_h`, shape kind) o, mínimo, registrar un proc por tipo.

### Cartas y reliquias — el peor offender

Hoy agregar una reliquia toca **15+ lugares**:

```
1. enum Card_Kind        (card.odin)
2. campo *_stacks        (app.odin)
3. init en simulation_reset
4. lógica de efecto      (simulation.odin: start_next_wave / kill / etc.)
5. campo en Icons        (fonts.odin)
6. load_icons + GenMipmaps + SetTextureFilter + UnloadTexture  (4 lugares en fonts.odin)
7. is_relic              (card.odin)
8. relic_icon            (card.odin)
9. relic_stacks          (card.odin)
10. relic_apply          (card.odin)
11. card_name            (card.odin)
12. card_rarity          (card.odin)
13. RELIC_KINDS slice    (interface.odin)
14. tooltip desc + stat  (interface.odin × 2)
15. render_card switch   (interface.odin)
16. apply_relic_card toast (menus.odin)
17. relic_pool en generate_card_selection
18. drop_pool en LOOT roll
19. traducciones
```

Eso explica los bugs por omisión: `veteran` y `loot` no estaban en `SetTextureFilter` ni `UnloadTexture`, `frozen_amp` queda como último elemento "completo" porque añadirlos rompió el patrón.

**Refactor propuesto** — una tabla declarativa estilo `TOWER_SPECS`:

```odin
Relic_Spec :: struct {
    kind:        Card_Kind,
    rarity:      Card_Rarity,
    icon_name:   string,                    // p.ej. "interest"
    desc_key:    string,                    // "TOOLTIP_INTEREST_BOOST_DESC"
    name_key:    string,
    stat_format: proc(stacks: i32) -> string, // genera la línea numérica
    apply:       proc(sim: ^Simulation),      // suma stack
    get_stacks:  proc(sim: ^Simulation) -> i32,
}

RELIC_SPECS := []Relic_Spec{ ... }
```

Con esto:
- `is_relic` colapsa a `_, ok := RELIC_BY_KIND[kind]; return ok`.
- El tray de reliquias itera `RELIC_SPECS` y todo aparece solo.
- `load_icons` / `unload_icons` se vuelven loops sobre los specs.
- Agregar una reliquia es **una sola línea** + el proc de efecto.

Para los stacks, dos opciones: (a) seguir con campos discretos pero generar el getter/setter desde el enum con un `[Card_Kind]i32` array, (b) usar `relic_stacks: [Card_Kind]i32` en `Simulation` (waste de memoria mínimo y borra `relic_stacks` / `relic_apply` enteros).

### Enemigos — usar enum, no flags

Hoy un enemigo se identifica por `is_boss`, `is_green`, `is_blue`, `is_flying`, `is_split`, `is_bonus` — seis bools que se combinan ad-hoc en `enemy_get_color`, `enemy_get_size`, `spawn_enemies`, el tray de "next waves" y el campo `Wave_Mark`. Es propenso a estados imposibles (ej.: `is_boss && is_green` "funciona" pero nadie lo definió). Reemplazar por un `Enemy_Spec` con campos (color, size, speed, hp_mult, reward, goal_dmg, behavior_flags) y un array `ENEMY_SPECS[Enemy_Type]` elimina otras 6+ duplicaciones. Las oleadas mixtas pueden expresarse como dos `Enemy_Type` en vez de cuatro flags.

## Misceláneo / código redundante

- `card_play` y `card_sell` (`card.odin:163` y `:173`) hacen **exactamente lo mismo**. Sólo el call site agrega el oro. Eliminar `card_sell` y dejar el crédito explícito donde se usa.
- En `deal_guaranteed_hand` (`card.odin:207-220`) hay dos `shuffle_tower` / `shuffle_kind` casi idénticos — un solo proc genérico con `$T` ahorra ~10 líneas.
- `interest_multiplier` en `Simulation` está marcado como legacy y nadie lo usa — borrarlo.
- `BFS` en `map_find_path_bfs` usa `ordered_remove(&queue, 0)` (O(n)) como dequeue. Para 20×20 no importa, pero si vas a permitir mapas grandes cambialo por índice de cabeza.
- `_tmp_dist` en `Enemy` no se referencia en ningún lado — quitarlo.
- `app_init` construye `app.sim` a mano con dynamic arrays y luego llama `simulation_reset` que descarta todo y reconstruye. Inicializar a cero y dejar el reset hace el mismo trabajo.
- Los switches `tower.type == .X` con tres tipos especiales (`LASER`, `ICE`, `ENHANCE`) que rompen el flujo de `update_towers` se leerían mejor si esos tipos tuvieran su propio `behavior_kind` en el spec.

## Prioridad sugerida

1. **Esta semana**: arreglar el flujo Menu → Play y Game Over → Menu (puntos 1 y 2 de "pendientes"). Sin esto el juego sólo se juega desde el editor.
2. **Próximo refactor**: tabla `RELIC_SPECS` + `relic_stacks: [Card_Kind]i32`. Saca docenas de líneas y todos los bugs por omisión.
3. **Después**: pasar enemigos a `Enemy_Spec`. Es más invasivo pero te ahorra dolor cuando agregues tipos nuevos.
4. **Performance**: cachear `tower_is_in_formation` y reusar buffers en `find_target`. Sólo si notás caídas de FPS con muchas torres.

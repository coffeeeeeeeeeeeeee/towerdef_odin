Esta carpeta contiene los archivos necesarios para compilar un juego en el lenguaje Odin. El juego es un juego de defensa de torres minimalista. Contiene un archivo constants.odin donde se encuentran las principales variables de márgenes, colores, timers, etc. El juego se renderiza a través de rendering.odin y el audio desde audio.odin. Cada vez que agregues un texto que se lea en pantalla ten en cuenta que debes agregar una traducción en translations.txt

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
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
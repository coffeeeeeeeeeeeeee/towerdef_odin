# First Impact

Tower defense en **Odin + Raylib** con un sistema de mazo de cartas y
reliquias al estilo roguelike deck-builder (Balatro). Además de construir y
mejorar torres, el jugador compra cartas entre oleadas, arma reliquias
pasivas/activas, y progresa por un modo de campaña con meta-progresión
persistente entre partidas.

## Características

- **9 tipos de torre**: Archer, Cannon, Sniper, Missile, Laser, Ice, Enhance, Tesla, Mortar
- **Sistema de niveles**: cada torre escala daño, velocidad de ataque y probabilidad de crítico por nivel, hasta un cap manual y un cap absoluto (con boosts de la torre Enhance)
- **Enemigos combinables**: flags de comportamiento (BOSS, GREEN, BLUE, FLYING, SPLIT, BONUS) que se combinan entre sí para oleadas mixtas
- **Mazo de cartas y reliquias**: shop entre oleadas, cartas de torre/obstáculo, y ~25 reliquias acumulables con efectos pasivos o activos
- **Modo campaña**: nodos de campaña con meta-progresión persistente (cristales, desbloqueos) entre runs
- **Editor de mapas**: spawn, goal, caminos, obstáculos, undo/redo, guardado/carga de mapas
- **Biomas**: Llanura, Bosque, Desierto, Montaña
- **Efectos visuales**: shaders de agua/nubes/heightmap/pasto, explosiones, números de daño, rayos láser

## Estructura del Proyecto

```
towerdef_odin/
├── main.odin                # Entry point, game loop, save/load de settings
├── constants/
│   ├── constants.odin       # Enums, specs de torres/enemigos, colores, timers, GAME_NAME
│   ├── fonts.odin
│   └── translations.odin    # Carga translations.txt (i18n por clave)
├── entities/
│   ├── app.odin              # App_State global, Game_State (enum de pantallas)
│   ├── tower.odin            # Torres y specs
│   ├── enemy.odin            # Enemigos y pathfinding
│   ├── projectile.odin       # Proyectiles y misiles
│   ├── laser.odin            # Sistema de láser
│   ├── map.odin               # Grid, obstáculos, spawn points, save/load de mapas
│   ├── card.odin              # Card_Kind (torres, obstáculos, reliquias), RELIC_SPECS
│   ├── campaign.odin          # Nodos de campaña, save/load
│   ├── meta.odin               # Meta-progresión persistente entre runs
│   ├── explosion.odin, toast.odin, console.odin, input.odin
├── systems/
│   ├── simulation.odin        # Lógica de juego: oleadas, shop, daño
│   ├── rendering.odin          # Mundo/mapa: enemigos, torres, obstáculos
│   ├── interface.odin           # Widgets reutilizables (botones, cartas, paneles, tooltips)
│   ├── menus.odin                # Pantallas y HUD (menú, shop, mano de cartas, game over)
│   ├── input.odin, audio.odin, campaign.odin, console.odin, ui.odin
├── maps/                       # Mapas guardados (.map)
├── images/, fonts/, audio/, music/, assets/   # Assets y shaders
└── translations.txt            # Strings de UI por idioma (ENGLISH/SPANISH/PORTUGUESE)
```

Ver `CLAUDE.md` para el detalle de sistemas internos y trampas conocidas del código.

## Requisitos

- [Odin](https://odin-lang.org/) instalado (trae Raylib vendorizada — no hace falta instalarla aparte)

Odin es rolling-release sin versiones estables: si el compilador instalado
es más nuevo que el último commit del proyecto, pueden aparecer errores de
compilación por cambios de API en `core:os`. Ver `CLAUDE.md` para más detalle.

## Compilación

### Windows

```powershell
odin run . -out:towerdef.exe
odin build . -out:towerdef.exe
odin build . -out:towerdef.exe -opt:3   # release
```

### Linux/Mac

```bash
odin run . -out:towerdef
odin build . -out:towerdef
odin build . -out:towerdef -opt:3   # release
```

## Controles

### Menú
- **Click**: Seleccionar opciones

### Editor de Mapas
- **Click Izquierdo**: Colocar elemento seleccionado
- **Click Derecho**: Borrar
- **Teclas 0-9**: Seleccionar herramienta rápidamente
- **G**: Toggle grid
- **Ctrl+Z / Ctrl+Y (o Ctrl+Shift+Z)**: Undo / Redo
- **Ctrl+C**: Copiar
- **Ctrl+S**: Guardar
- **Ctrl+O**: Abrir
- **Ctrl+B**: Abrir/cerrar browser de mapas guardados
- **ESC**: Volver al menú

### En el Juego
- **Click Izquierdo**: Seleccionar torre / comprar carta / abrir menú de mejora
- **Click Derecho**: Cancelar selección
- **SPACE**: Pausar/Resumir
- **1**: Velocidad 1x
- **2**: Velocidad 2x
- **ESC**: Pausar / Volver al editor

## Sistema de Torres

Specs base (antes de niveles/reliquias) — ver `constants.TOWER_SPECS`:

| Torre | Rango | Daño | Cooldown | AoE | Costo | Especial |
|-------|-------|------|----------|-----|-------|----------|
| Archer | 2.5 | 1.5 | 0.5s | – | $20 | Básica, barata |
| Cannon | 4.0 | 8.0 | 0.9s | 0.6 | $40 | Área de efecto |
| Sniper | 6.0 | 18.0 | 2.0s | – | $60 | Alto daño, larguísimo alcance |
| Missile | 3.0 | 3.0 | 0.6s | 1.0 | $35 | AoE, anti-aéreo |
| Laser | 2.5 | 8.0 | 0.7s | – | $80 | Daño continuo |
| Ice | 2.5 | 0.5 | 3.0s | – | $45 | Ralentiza enemigos |
| Enhance | 3.0 | – | 10.0s | – | $90 | Potencia torres cercanas (no ataca) |
| Tesla | 3.0 | 6.0 | 1.5s | – | $55 | — |
| Mortar | 5.0 | 14.0 | 3.0s | 1.5 | $65 | AoE de largo alcance |

Cada torre escala por nivel: +15% daño, +8% velocidad de ataque, +0.5%
probabilidad de crítico por nivel (hasta nivel 20 manual, 25 absoluto con
boosts de Enhance). Vender una torre reintegra el 75% de lo invertido.

## Sistema de Enemigos

Los enemigos se definen por flags combinables (`Enemy_Flag`), no tipos
fijos — una oleada puede generar enemigos con varias flags a la vez:

| Flag | Efecto |
|------|--------|
| BOSS | Mucha vida, daño alto al goal |
| GREEN | Rápido, menos vida |
| BLUE | Regenera HP con el tiempo |
| FLYING | Ignora obstáculos, solo alcanzable por torres específicas |
| SPLIT | Se divide en enemigos más chicos al morir |
| BONUS | Otorga recompensa extra al matarlo |

## Sistema de cartas y reliquias

Entre oleadas se abre un shop de 3 cartas (torres, obstáculos o reliquias).
Reroll cuesta $50; vender una carta de la mano da $25. Hasta 5 tipos de
reliquia distinta activos a la vez (`MAX_ACTIVE_RELICS`, ampliable con la
reliquia SHOPPING_CART). Las reliquias son pasivas (efecto inmediato y
global) o activas (van a la mano y se aplican a un tile del mapa). Ver
`entities/card.odin` (`RELIC_SPECS`) y `CLAUDE.md` para el detalle completo.

## Modo campaña

Los nodos de campaña (`entities/campaign.odin`) definen runs con objetivos
propios; el resultado de cada run alimenta la meta-progresión persistente
(`entities/meta.odin`): cristales y desbloqueos que sobreviven entre
partidas, guardados en `savegame.bin`.

## Licencia

Ver licencia del repositorio.

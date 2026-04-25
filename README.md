# Tower Defense - Odin + Raylib

Un port completo del juego Tower Defense original (JavaScript/HTML5) a Odin con Raylib.

## Características

- **5 tipos de torres**: Archer (Arquero), Cannon (Cañón), Sniper (Francotirador), Missile (Misiles), Laser (Láser)
- **Sistema de upgrades**: Mejora daño, velocidad de ataque y probabilidad de crítico
- **4 tipos de enemigos**: Normal, Verde (rápido), Azul (curativo), Volador, Jefe
- **Editor de mapas**: Crea tus propios mapas con spawn, goal, caminos y obstáculos
- **Sistema de oleadas**: Enemigos cada vez más difíciles
- **Biomas**: Llanura, Bosque, Desierto, Montaña
- **Efectos visuales**: Explosiones, números de daño, rayos láser

## Estructura del Proyecto

```
towerdef_odin/
├── main.odin              # Entry point
├── constants.odin         # Constantes, enums, especificaciones
├── game/
│   └── app.odin          # Estado global del juego
├── entities/
│   ├── tower.odin        # Torres y especificaciones
│   ├── enemy.odin        # Enemigos y pathfinding
│   ├── projectile.odin   # Proyectiles y misiles
│   ├── laser.odin        # Sistema de láser
│   ├── map.odin          # Grid, obstáculos, spawn points
│   └── explosion.odin    # Explosiones y números de daño
├── systems/
│   ├── simulation.odin   # Lógica del juego (updateSimulation)
│   ├── rendering.odin    # Dibujado de todo
│   └── input.odin        # Manejo de input
└── README.md
```

## Requisitos

- [Odin](https://odin-lang.org/) instalado
- [Raylib](https://www.raylib.com/) instalado

## Compilación

### Windows

```powershell
# Desde el directorio del proyecto
odin run . -out:towerdef.exe

# Para compilar sin ejecutar
odin build . -out:towerdef.exe

# Para release
odin build . -out:towerdef.exe -opt:3
```

### Linux/Mac

```bash
# Desde el directorio del proyecto
odin run . -out:towerdef

# Para compilar sin ejecutar
odin build . -out:towerdef

# Para release
odin build . -out:towerdef -opt:3
```

## Controles

### Menú
- **Click**: Seleccionar opciones

### Editor de Mapas
- **Click Izquierdo**: Colocar elemento seleccionado
- **Click Derecho**: Borrar
- **Teclas 1-9**: Seleccionar herramienta rápidamente
- **G**: Toggle grid
- **ESC**: Volver al menú

### En el Juego
- **Click Izquierdo**: Seleccionar torre / Abrir menú de mejora
- **Click Derecho**: Cancelar selección
- **SPACE**: Pausar/Resumir
- **1**: Velocidad 1x
- **2**: Velocidad 2x
- **ESC**: Pausar / Volver al editor

## Sistema de Torres

| Torre | Rango | Daño | Cooldown | Costo | Especial |
|-------|-------|------|----------|-------|----------|
| Archer | 2.5 | 2.5 | 0.2s | $20 | Rápido, básico |
| Cannon | 3.0 | 4.0 | 1.0s | $40 | Área de efecto (AoE) |
| Sniper | 5.0 | 8.0 | 1.5s | $60 | Alto daño, largo alcance |
| Missile | 4.0 | 3.5 | 0.9s | $70 | Misiles guiados, AoE, anti-aéreo |
| Laser | 3.5 | 5.0 DPS | 1.2s cooldown | $50 | Daño continuo con burst-fire |

## Sistema de Upgrades

Cada torre puede mejorarse en 3 categorías:

- **Daño** (puntos rojos): +50% daño por nivel
- **Velocidad** (puntos amarillos): -15% cooldown por nivel
- **Crítico** (puntos azules): +3% chance de crítico por nivel

Costo de upgrade: $50 + $25 × (nivel - 1)

## Sistema de Enemigos

| Tipo | Vida | Velocidad | Especial |
|------|------|-----------|----------|
| Normal | 100% | 1.5x | Básico |
| Verde | 50% | 2.0x | Rápido, menos vida |
| Azul | 120% | 1.3x | Regenera 5% HP/s |
| Volador | 70% | 1.5x | Ignora obstáculos, solo láser/misiles |
| Jefe | 1000% | 0.8x | Mucha vida, daño 5× al goal |

## Diferencias con la versión JavaScript

1. **Single executable**: No requiere navegador
2. **Mejor rendimiento**: Compilado nativamente
3. **Input simplificado**: Menos dependencia de UI HTML
4. **Sin modo campaña**: Solo modo supervivencia (como en el código actual)

## Créditos

Port a Odin basado en el juego Tower Defense original en JavaScript/HTML5.

## Licencia

Misma licencia que el proyecto original.

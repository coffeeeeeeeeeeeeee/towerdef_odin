#+feature dynamic-literals
package constants

import "core:fmt"
import "core:os"
import "core:strings"
import "core:bufio"

// Language definitions
Language :: enum {
	ENGLISH,
	SPANISH,
	PORTUGUESE,
}

// Dynamic translation system - keys are loaded from translations.txt
// No static enum needed - use strings directly

// No key mapping needed - use strings directly

// Translations table (loaded from file) - flat map with compound keys "LANGUAGE|KEY"
TRANSLATIONS: map[string]string

// Default translations (fallback)
DEFAULT_TRANSLATIONS: map[Language]map[string]string = {
	.ENGLISH = {
		// Menu
		"MENU_TITLE" = "First Impact",
		"MENU_BUTTON_PLAY" = "Play",
		"MENU_BUTTON_EDITOR" = "Editor",
		"MENU_BUTTON_SETTINGS" = "Settings",
		"MENU_BUTTON_EXIT" = "Exit",
		
		// Settings Menu
		"SETTINGS_TITLE" = "Settings",
		"SETTINGS_VOLUME" = "Volume",
		"SETTINGS_LANGUAGE" = "Language",
		"SETTINGS_LANGUAGE_ENGLISH" = "English",
		"SETTINGS_LANGUAGE_SPANISH" = "Spanish",
		"SETTINGS_LANGUAGE_PORTUGUESE" = "Portuguese",
		"SETTINGS_SHOW_GRID" = "Show Grid",
		"SETTINGS_SHOW_DAMAGE_NUMBERS" = "Show Damage Numbers",
		"SETTINGS_SHOW_TOWER_RANGE" = "Show Tower Range",
		"SETTINGS_SHOW_FPS" = "Show FPS",
		"SETTINGS_AUTO_WAVE" = "Auto Wave",
		"SETTINGS_ANTIALIASING" = "Antialiasing",
		"SETTINGS_FULLSCREEN" = "Fullscreen",
		"SETTINGS_VSYNC" = "V-Sync",
		"SETTINGS_BACK_TO_MENU" = "Back to Menu",
		"UI_ON" = "On",
		"UI_OFF" = "Off",
		
		// Game UI
		"UI_MONEY" = "Money",
		"UI_HEALTH" = "Health",
		"UI_WAVE" = "Wave",
		"UI_ENEMIES" = "Enemies",
		"TOOLTIP_UPGRADES" = "Upgrades",
		"TOOLTIP_LEVEL"    = "Level",
		"UI_BUTTON_PAUSE" = "Pause",
		"UI_BUTTON_RESUME" = "Resume",
		"UI_BUTTON_SPEED_1X" = "1x",
		"UI_BUTTON_SPEED_2X" = "2x",
		"UI_NEXT_WAVE" = "Next Wave",
		"UI_START" = "Start",
		
		// Pause Menu
		"PAUSE_TITLE" = "Paused",
		"PAUSE_RESUME" = "Resume",
		"PAUSE_MENU" = "Menu",
		
		// Tower Types
		"TOWER_ARCHER_NAME" = "Archer",
		"TOWER_CANNON_NAME" = "Cannon",
		"TOWER_SNIPER_NAME" = "Sniper",
		"TOWER_MISSILE_NAME" = "Missile",
		"TOWER_LASER_NAME" = "Laser",
		
		// Tower Panel
		"PANEL_TOWER_INFO" = "%s (Lvl %d)",
		"PANEL_BUTTON_DAMAGE" = "Damage ($%d)",
		"PANEL_BUTTON_SPEED" = "Speed ($%d)",
		"PANEL_BUTTON_CRITICAL" = "Critical ($%d)",
		"PANEL_BUTTON_SELL" = "Sell ($%d)",
		"PANEL_STRATEGY_LABEL" = "Target:",
		"PANEL_STRATEGY_FIRST" = "First",
		"PANEL_STRATEGY_LAST" = "Last",
		"PANEL_STRATEGY_STRONG" = "Strong",
		"PANEL_STRATEGY_WEAK" = "Weak",
		
		// Editor
		"EDITOR_TOOL_EMPTY" = "Empty",
		"EDITOR_TOOL_PATH" = "Path",
		"EDITOR_TOOL_SPAWN" = "Spawn",
		"EDITOR_TOOL_GOAL" = "Goal",
		"EDITOR_TOOL_OBSTACLE" = "Obstacle",
		"EDITOR_TOOL_TREE" = "Tree",
		"EDITOR_TOOL_BLOCK" = "Block",
		"EDITOR_BUTTON_SAVE" = "Save",
		"EDITOR_BUTTON_LOAD" = "Load",
		"EDITOR_BUTTON_SHOW_PATHS" = "Show Paths",
		"EDITOR_BUTTON_HIDE_PATHS" = "Hide Paths",
		"EDITOR_BIOME_LABEL" = "Biome:",
		"EDITOR_BUTTON_SAVE_MAP" = "Save Map",
		"EDITOR_BUTTON_QUICK_LOAD" = "Quick Load",
		"EDITOR_BUTTON_TEST_MAP" = "Test Map",
		"EDITOR_BUTTON_MENU" = "Menu",
		"EDITOR_BUTTON_BROWSE_MAPS" = "Browse Maps",
		"EDITOR_MAP_BROWSER_TITLE" = "Saved Maps",
		"EDITOR_BIOME_PLAIN" = "Plain",
		"EDITOR_BIOME_FOREST" = "Forest",
		"EDITOR_BIOME_DESERT" = "Desert",
		"EDITOR_BIOME_MOUNTAIN" = "Mountain",
		
		// Game Over
		"GAME_OVER_TITLE" = "Game Over",
		"GAME_OVER_WAVES_SURVIVED" = "You survived %d waves",
		"GAME_OVER_BUTTON_MENU" = "Menu",
		"GAME_OVER_TIME" = "Play Time",
		"GAME_OVER_ENEMIES_KILLED" = "Enemies Killed",
		"GAME_OVER_MONEY_EARNED" = "Money Earned",
		"GAME_OVER_TOWERS_BUILT" = "Towers Built",
		"GAME_OVER_UPGRADES" = "Upgrades",
		
		// Biomes
		"BIOME_PLAIN" = "Plain",
		"BIOME_FOREST" = "Forest",
		"BIOME_DESERT" = "Desert",
		"BIOME_MOUNTAIN" = "Mountain",
	},
	.SPANISH = {
		// Menu
		"MENU_TITLE" = "Primer Impacto",
		"MENU_BUTTON_PLAY" = "Jugar",
		"MENU_BUTTON_EDITOR" = "Editor",
		"MENU_BUTTON_SETTINGS" = "Configuración",
		"MENU_BUTTON_EXIT" = "Salir",
		
		// Settings Menu
		"SETTINGS_TITLE" = "Configuración",
		"SETTINGS_VOLUME" = "Volumen",
		"SETTINGS_LANGUAGE" = "Idioma",
		"SETTINGS_LANGUAGE_ENGLISH" = "Inglés",
		"SETTINGS_LANGUAGE_SPANISH" = "Español",
		"SETTINGS_LANGUAGE_PORTUGUESE" = "Portugués",
		"SETTINGS_SHOW_GRID" = "Mostrar Cuadrícula",
		"SETTINGS_SHOW_DAMAGE_NUMBERS" = "Mostrar Números de Daño",
		"SETTINGS_SHOW_TOWER_RANGE" = "Mostrar Rango de Torre",
		"SETTINGS_SHOW_FPS" = "Mostrar FPS",
		"SETTINGS_AUTO_WAVE" = "Ola Automática",
		"SETTINGS_ANTIALIASING" = "Antialiasing",
		"SETTINGS_FULLSCREEN" = "Pantalla Completa",
		"SETTINGS_VSYNC" = "V-Sync",
		"SETTINGS_BACK_TO_MENU" = "Volver al Menú",
		"UI_ON" = "Activado",
		"UI_OFF" = "Desactivado",
		
		// Game UI
		"UI_MONEY" = "Dinero",
		"UI_HEALTH" = "Vida",
		"UI_WAVE" = "Ola",
		"UI_ENEMIES" = "Enemigos",
		"TOOLTIP_UPGRADES" = "Mejoras",
		"TOOLTIP_LEVEL"    = "Nivel",
		"UI_BUTTON_PAUSE" = "Pausar",
		"UI_BUTTON_RESUME" = "Reanudar",
		"UI_BUTTON_SPEED_1X" = "1x",
		"UI_BUTTON_SPEED_2X" = "2x",
		"UI_NEXT_WAVE" = "Siguiente Ola",
		"UI_START" = "Comenzar",
		
		// Pause Menu
		"PAUSE_TITLE" = "Pausado",
		"PAUSE_RESUME" = "Reanudar",
		"PAUSE_MENU" = "Menú",
		
		// Tower Types
		"TOWER_ARCHER_NAME" = "Arquero",
		"TOWER_CANNON_NAME" = "Cañón",
		"TOWER_SNIPER_NAME" = "Francotirador",
		"TOWER_MISSILE_NAME" = "Misil",
		"TOWER_LASER_NAME" = "Láser",
		
		// Tower Panel
		"PANEL_TOWER_INFO" = "%s (Nv %d)",
		"PANEL_BUTTON_DAMAGE" = "Daño ($%d)",
		"PANEL_BUTTON_SPEED" = "Velocidad ($%d)",
		"PANEL_BUTTON_CRITICAL" = "Crítico ($%d)",
		"PANEL_BUTTON_SELL" = "Vender ($%d)",
		"PANEL_STRATEGY_LABEL" = "Objetivo:",
		"PANEL_STRATEGY_FIRST" = "Primero",
		"PANEL_STRATEGY_LAST" = "Último",
		"PANEL_STRATEGY_STRONG" = "Fuerte",
		"PANEL_STRATEGY_WEAK" = "Débil",
		
		// Editor
		"EDITOR_TOOL_EMPTY" = "Vacío",
		"EDITOR_TOOL_PATH" = "Camino",
		"EDITOR_TOOL_SPAWN" = "Aparición",
		"EDITOR_TOOL_GOAL" = "Meta",
		"EDITOR_TOOL_OBSTACLE" = "Obstáculo",
		"EDITOR_TOOL_TREE" = "Árbol",
		"EDITOR_TOOL_BLOCK" = "Bloque",
		"EDITOR_BUTTON_SAVE" = "Guardar",
		"EDITOR_BUTTON_LOAD" = "Cargar",
		"EDITOR_BUTTON_SHOW_PATHS" = "Mostrar Rutas",
		"EDITOR_BUTTON_HIDE_PATHS" = "Ocultar Rutas",
		"EDITOR_BIOME_LABEL" = "Bioma:",
		"EDITOR_BUTTON_SAVE_MAP" = "Guardar Mapa",
		"EDITOR_BUTTON_QUICK_LOAD" = "Carga Rápida",
		"EDITOR_BUTTON_TEST_MAP" = "Probar Mapa",
		"EDITOR_BUTTON_MENU" = "Menú",
		"EDITOR_BUTTON_BROWSE_MAPS" = "Ver Mapas",
		"EDITOR_MAP_BROWSER_TITLE" = "Mapas Guardados",
		"EDITOR_BIOME_PLAIN" = "Llanura",
		"EDITOR_BIOME_FOREST" = "Bosque",
		"EDITOR_BIOME_DESERT" = "Desierto",
		"EDITOR_BIOME_MOUNTAIN" = "Montaña",
		
		// Game Over
		"GAME_OVER_TITLE" = "Fin del Juego",
		"GAME_OVER_WAVES_SURVIVED" = "Sobreviviste %d oleadas",
		"GAME_OVER_BUTTON_MENU" = "Menú",
		"GAME_OVER_TIME" = "Tiempo de Juego",
		"GAME_OVER_ENEMIES_KILLED" = "Enemigos Eliminados",
		"GAME_OVER_MONEY_EARNED" = "Dinero Obtenido",
		"GAME_OVER_TOWERS_BUILT" = "Torres Construidas",
		"GAME_OVER_UPGRADES" = "Mejoras",
		
		// Biomes
		"BIOME_PLAIN" = "Llanura",
		"BIOME_FOREST" = "Bosque",
		"BIOME_DESERT" = "Desierto",
		"BIOME_MOUNTAIN" = "Montaña",
	},
	.PORTUGUESE = {
		// Menu
		"MENU_TITLE" = "Primeiro Impacto",
		"MENU_BUTTON_PLAY" = "Jogar",
		"MENU_BUTTON_EDITOR" = "Editor",
		"MENU_BUTTON_SETTINGS" = "Configurações",
		"MENU_BUTTON_EXIT" = "Sair",
		
		// Settings Menu
		"SETTINGS_TITLE" = "Configurações",
		"SETTINGS_VOLUME" = "Volume",
		"SETTINGS_LANGUAGE" = "Idioma",
		"SETTINGS_LANGUAGE_ENGLISH" = "Inglês",
		"SETTINGS_LANGUAGE_SPANISH" = "Espanhol",
		"SETTINGS_LANGUAGE_PORTUGUESE" = "Português",
		"SETTINGS_SHOW_GRID" = "Mostrar Grade",
		"SETTINGS_SHOW_DAMAGE_NUMBERS" = "Mostrar Números de Dano",
		"SETTINGS_SHOW_TOWER_RANGE" = "Mostrar Alcance da Torre",
		"SETTINGS_SHOW_FPS" = "Mostrar FPS",
		"SETTINGS_AUTO_WAVE" = "Onda Automática",
		"SETTINGS_ANTIALIASING" = "Antialiasing",
		"SETTINGS_FULLSCREEN" = "Tela Cheia",
		"SETTINGS_VSYNC" = "V-Sync",
		"SETTINGS_BACK_TO_MENU" = "Voltar ao Menu",
		"UI_ON" = "Ligado",
		"UI_OFF" = "Desligado",
		
		// Game UI
		"UI_MONEY" = "Dinheiro",
		"UI_HEALTH" = "Vida",
		"UI_WAVE" = "Onda",
		"UI_ENEMIES" = "Inimigos",
		"TOOLTIP_UPGRADES" = "Melhorias",
		"TOOLTIP_LEVEL"    = "Nível",
		"UI_BUTTON_PAUSE" = "Pausar",
		"UI_BUTTON_RESUME" = "Retomar",
		"UI_BUTTON_SPEED_1X" = "1x",
		"UI_BUTTON_SPEED_2X" = "2x",
		"UI_NEXT_WAVE" = "Próxima Onda",
		"UI_START" = "Começar",
		
		// Pause Menu
		"PAUSE_TITLE" = "Pausado",
		"PAUSE_RESUME" = "Retomar",
		"PAUSE_MENU" = "Menu",
		
		// Tower Types
		"TOWER_ARCHER_NAME" = "Arqueiro",
		"TOWER_CANNON_NAME" = "Canhão",
		"TOWER_SNIPER_NAME" = "Atirador",
		"TOWER_MISSILE_NAME" = "Míssil",
		"TOWER_LASER_NAME" = "Laser",
		
		// Tower Panel
		"PANEL_TOWER_INFO" = "%s (Nv %d)",
		"PANEL_BUTTON_DAMAGE" = "Dano ($%d)",
		"PANEL_BUTTON_SPEED" = "Velocidade ($%d)",
		"PANEL_BUTTON_CRITICAL" = "Crítico ($%d)",
		"PANEL_BUTTON_SELL" = "Vender ($%d)",
		"PANEL_STRATEGY_LABEL" = "Alvo:",
		"PANEL_STRATEGY_FIRST" = "Primeiro",
		"PANEL_STRATEGY_LAST" = "Último",
		"PANEL_STRATEGY_STRONG" = "Forte",
		"PANEL_STRATEGY_WEAK" = "Fraco",
		
		// Editor
		"EDITOR_TOOL_EMPTY" = "Vazio",
		"EDITOR_TOOL_PATH" = "Caminho",
		"EDITOR_TOOL_SPAWN" = "Spawn",
		"EDITOR_TOOL_GOAL" = "Objetivo",
		"EDITOR_TOOL_OBSTACLE" = "Obstáculo",
		"EDITOR_TOOL_TREE" = "Árvore",
		"EDITOR_TOOL_BLOCK" = "Bloco",
		"EDITOR_BUTTON_SAVE" = "Salvar",
		"EDITOR_BUTTON_LOAD" = "Carregar",
		"EDITOR_BUTTON_SHOW_PATHS" = "Mostrar Caminhos",
		"EDITOR_BUTTON_HIDE_PATHS" = "Ocultar Caminhos",
		"EDITOR_BIOME_LABEL" = "Bioma:",
		"EDITOR_BUTTON_SAVE_MAP" = "Salvar Mapa",
		"EDITOR_BUTTON_QUICK_LOAD" = "Carregamento Rápido",
		"EDITOR_BUTTON_TEST_MAP" = "Testar Mapa",
		"EDITOR_BUTTON_MENU" = "Menu",
		"EDITOR_BUTTON_BROWSE_MAPS" = "Ver Mapas",
		"EDITOR_MAP_BROWSER_TITLE" = "Mapas Salvos",
		"EDITOR_BIOME_PLAIN" = "Planície",
		"EDITOR_BIOME_FOREST" = "Floresta",
		"EDITOR_BIOME_DESERT" = "Deserto",
		"EDITOR_BIOME_MOUNTAIN" = "Montanha",
		
		// Game Over
		"GAME_OVER_TITLE" = "Fim de Jogo",
		"GAME_OVER_WAVES_SURVIVED" = "Você sobreviveu %d ondas",
		"GAME_OVER_BUTTON_MENU" = "Menu",
		"GAME_OVER_TIME" = "Tempo de Jogo",
		"GAME_OVER_ENEMIES_KILLED" = "Inimigos Eliminados",
		"GAME_OVER_MONEY_EARNED" = "Dinheiro Obtido",
		"GAME_OVER_TOWERS_BUILT" = "Torres Construídas",
		"GAME_OVER_UPGRADES" = "Melhorias",
		
		// Biomes
		"BIOME_PLAIN" = "Planície",
		"BIOME_FOREST" = "Floresta",
		"BIOME_DESERT" = "Deserto",
		"BIOME_MOUNTAIN" = "Montanha",
	},
}

// Current language (default to English)
current_language: Language = .ENGLISH

// Set current language
set_language :: proc(lang: Language) {
	current_language = lang
}

// Get translated text
get_text :: proc(key: string) -> string {
	// Try current language from loaded translations
	compound_key := fmt.tprintf("%v|%s", current_language, key)
	if text, ok := TRANSLATIONS[compound_key]; ok {
		return text
	}
	
	// Fallback to English
	english_key := fmt.tprintf("ENGLISH|%s", key)
	if text, ok := TRANSLATIONS[english_key]; ok {
		return text
	}
	
	return key // Fallback to key itself
}

// Get tower name based on type
get_tower_name :: proc(tower_type: Tower_Type) -> string {
	switch tower_type {
	case .ARCHER:
		return get_text("TOWER_ARCHER_NAME")
	case .CANNON:
		return get_text("TOWER_CANNON_NAME")
	case .SNIPER:
		return get_text("TOWER_SNIPER_NAME")
	case .MISSILE:
		return get_text("TOWER_MISSILE_NAME")
	case .LASER:
		return get_text("TOWER_LASER_NAME")
	case:
		return "Unknown"
	}
}

// Get formatted translation
get_text_f :: proc(key: string, args: ..any) -> string {
	base_text := get_text(key)
	return fmt.tprintf(base_text, ..args)
}

// Map language string to Language enum
language_from_string :: proc(s: string) -> (Language, bool) {
	switch s {
	case "ENGLISH": return .ENGLISH, true
	case "SPANISH": return .SPANISH, true
	case "PORTUGUESE": return .PORTUGUESE, true
	}
	return .ENGLISH, false
}

// Initialize translations - call this at game start
init_translations :: proc() {
	// Create the TRANSLATIONS map (flat map with compound keys)
	TRANSLATIONS = make(map[string]string)
	
	// Read translations.txt file
	data, read_ok := os.read_entire_file("translations.txt")
	if !read_ok {
		fmt.println("WARNING: Could not read translations.txt")
		return
	}
	defer delete(data)
	
	content := string(data)
	loaded_count := 0
	
	// Parse line by line
	remaining := content
	for len(remaining) > 0 {
		// Find end of line
		line_end := strings.index(remaining, "\n")
		line: string
		if line_end == -1 {
			line = remaining
			remaining = ""
		} else {
			line = remaining[:line_end]
			remaining = remaining[line_end + 1:]
		}
		
		// Trim carriage return (Windows line endings)
		line = strings.trim_right(line, "\r")
		// Trim whitespace
		line = strings.trim_space(line)
		
		// Skip empty lines and comments
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		
		// Parse KEY|LANGUAGE|VALUE
		first_sep := strings.index(line, "|")
		if first_sep == -1 {
			continue
		}
		
		rest := line[first_sep + 1:]
		second_sep := strings.index(rest, "|")
		if second_sep == -1 {
			continue
		}
		
		key_str := line[:first_sep]
		lang_str := rest[:second_sep]
		value_str := rest[second_sep + 1:]
		
		// Store translation using compound key: "LANGUAGE|KEY"
		compound_key := fmt.tprintf("%s|%s", lang_str, key_str)
		TRANSLATIONS[compound_key] = strings.clone(value_str)
		loaded_count += 1
	}
	
	fmt.printf("Loaded %d translations from translations.txt\n", loaded_count)
}

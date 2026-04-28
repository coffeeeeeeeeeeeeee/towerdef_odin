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

// Translation keys
TranslationKey :: enum {
	// Menu
	MENU_TITLE,
	MENU_BUTTON_PLAY,
	MENU_BUTTON_EDITOR,
	MENU_BUTTON_SETTINGS,
	MENU_BUTTON_EXIT,
	
	// Game UI
	UI_MONEY,
	UI_HEALTH,
	UI_WAVE,
	UI_ENEMIES,
	UI_BUTTON_PAUSE,
	UI_BUTTON_RESUME,
	UI_BUTTON_SPEED_1X,
	UI_BUTTON_SPEED_2X,
	
	// Tower Types
	TOWER_ARCHER_NAME,
	TOWER_CANNON_NAME,
	TOWER_SNIPER_NAME,
	TOWER_MISSILE_NAME,
	TOWER_LASER_NAME,
	
	// Tower Panel
	PANEL_TOWER_INFO,
	PANEL_BUTTON_DAMAGE,
	PANEL_BUTTON_SPEED,
	PANEL_BUTTON_CRITICAL,
	PANEL_BUTTON_SELL,
	PANEL_STRATEGY_LABEL,
	PANEL_STRATEGY_FIRST,
	PANEL_STRATEGY_LAST,
	PANEL_STRATEGY_STRONG,
	PANEL_STRATEGY_WEAK,
	
	// Editor
	EDITOR_TOOL_EMPTY,
	EDITOR_TOOL_PATH,
	EDITOR_TOOL_SPAWN,
	EDITOR_TOOL_GOAL,
	EDITOR_TOOL_OBSTACLE,
	EDITOR_TOOL_TREE,
	EDITOR_TOOL_BLOCK,
	EDITOR_BUTTON_SAVE,
	EDITOR_BUTTON_LOAD,
	EDITOR_BUTTON_SHOW_PATHS,
	EDITOR_BUTTON_HIDE_PATHS,
	EDITOR_BIOME_PLAIN,
	EDITOR_BIOME_FOREST,
	EDITOR_BIOME_DESERT,
	EDITOR_BIOME_MOUNTAIN,
	
	// Game Over
	GAME_OVER_TITLE,
	GAME_OVER_WAVES_SURVIVED,
	GAME_OVER_BUTTON_MENU,
	
	// Biomes
	BIOME_PLAIN,
	BIOME_FOREST,
	BIOME_DESERT,
	BIOME_MOUNTAIN,
}

// Map for key string to enum conversion
KEY_STRING_MAP: map[string]TranslationKey = {
	"MENU_TITLE" = .MENU_TITLE,
	"MENU_BUTTON_PLAY" = .MENU_BUTTON_PLAY,
	"MENU_BUTTON_EDITOR" = .MENU_BUTTON_EDITOR,
	"MENU_BUTTON_SETTINGS" = .MENU_BUTTON_SETTINGS,
	"MENU_BUTTON_EXIT" = .MENU_BUTTON_EXIT,
	"UI_MONEY" = .UI_MONEY,
	"UI_HEALTH" = .UI_HEALTH,
	"UI_WAVE" = .UI_WAVE,
	"UI_ENEMIES" = .UI_ENEMIES,
	"UI_BUTTON_PAUSE" = .UI_BUTTON_PAUSE,
	"UI_BUTTON_RESUME" = .UI_BUTTON_RESUME,
	"UI_BUTTON_SPEED_1X" = .UI_BUTTON_SPEED_1X,
	"UI_BUTTON_SPEED_2X" = .UI_BUTTON_SPEED_2X,
	"TOWER_ARCHER_NAME" = .TOWER_ARCHER_NAME,
	"TOWER_CANNON_NAME" = .TOWER_CANNON_NAME,
	"TOWER_SNIPER_NAME" = .TOWER_SNIPER_NAME,
	"TOWER_MISSILE_NAME" = .TOWER_MISSILE_NAME,
	"TOWER_LASER_NAME" = .TOWER_LASER_NAME,
	"PANEL_TOWER_INFO" = .PANEL_TOWER_INFO,
	"PANEL_BUTTON_DAMAGE" = .PANEL_BUTTON_DAMAGE,
	"PANEL_BUTTON_SPEED" = .PANEL_BUTTON_SPEED,
	"PANEL_BUTTON_CRITICAL" = .PANEL_BUTTON_CRITICAL,
	"PANEL_BUTTON_SELL" = .PANEL_BUTTON_SELL,
	"PANEL_STRATEGY_LABEL" = .PANEL_STRATEGY_LABEL,
	"PANEL_STRATEGY_FIRST" = .PANEL_STRATEGY_FIRST,
	"PANEL_STRATEGY_LAST" = .PANEL_STRATEGY_LAST,
	"PANEL_STRATEGY_STRONG" = .PANEL_STRATEGY_STRONG,
	"PANEL_STRATEGY_WEAK" = .PANEL_STRATEGY_WEAK,
	"EDITOR_TOOL_EMPTY" = .EDITOR_TOOL_EMPTY,
	"EDITOR_TOOL_PATH" = .EDITOR_TOOL_PATH,
	"EDITOR_TOOL_SPAWN" = .EDITOR_TOOL_SPAWN,
	"EDITOR_TOOL_GOAL" = .EDITOR_TOOL_GOAL,
	"EDITOR_TOOL_OBSTACLE" = .EDITOR_TOOL_OBSTACLE,
	"EDITOR_TOOL_TREE" = .EDITOR_TOOL_TREE,
	"EDITOR_TOOL_BLOCK" = .EDITOR_TOOL_BLOCK,
	"EDITOR_BUTTON_SAVE" = .EDITOR_BUTTON_SAVE,
	"EDITOR_BUTTON_LOAD" = .EDITOR_BUTTON_LOAD,
	"EDITOR_BUTTON_SHOW_PATHS" = .EDITOR_BUTTON_SHOW_PATHS,
	"EDITOR_BUTTON_HIDE_PATHS" = .EDITOR_BUTTON_HIDE_PATHS,
	"EDITOR_BIOME_PLAIN" = .EDITOR_BIOME_PLAIN,
	"EDITOR_BIOME_FOREST" = .EDITOR_BIOME_FOREST,
	"EDITOR_BIOME_DESERT" = .EDITOR_BIOME_DESERT,
	"EDITOR_BIOME_MOUNTAIN" = .EDITOR_BIOME_MOUNTAIN,
	"GAME_OVER_TITLE" = .GAME_OVER_TITLE,
	"GAME_OVER_WAVES_SURVIVED" = .GAME_OVER_WAVES_SURVIVED,
	"GAME_OVER_BUTTON_MENU" = .GAME_OVER_BUTTON_MENU,
	"BIOME_PLAIN" = .BIOME_PLAIN,
	"BIOME_FOREST" = .BIOME_FOREST,
	"BIOME_DESERT" = .BIOME_DESERT,
	"BIOME_MOUNTAIN" = .BIOME_MOUNTAIN,
}

// Translations table (loaded from file)
TRANSLATIONS: map[Language]map[TranslationKey]string

// Default translations (fallback)
DEFAULT_TRANSLATIONS: map[Language]map[TranslationKey]string = {
	.ENGLISH = {
		// Menu
		.MENU_TITLE = "First Impact",
		.MENU_BUTTON_PLAY = "Play",
		.MENU_BUTTON_EDITOR = "Editor",
		.MENU_BUTTON_SETTINGS = "Settings",
		.MENU_BUTTON_EXIT = "Exit",
		
		// Game UI
		.UI_MONEY = "Money",
		.UI_HEALTH = "Health",
		.UI_WAVE = "Wave",
		.UI_ENEMIES = "Enemies",
		.UI_BUTTON_PAUSE = "PAUSE",
		.UI_BUTTON_RESUME = "RESUME",
		.UI_BUTTON_SPEED_1X = "1x",
		.UI_BUTTON_SPEED_2X = "2x",
		
		// Tower Types
		.TOWER_ARCHER_NAME = "Archer",
		.TOWER_CANNON_NAME = "Cannon",
		.TOWER_SNIPER_NAME = "Sniper",
		.TOWER_MISSILE_NAME = "Missile",
		.TOWER_LASER_NAME = "Laser",
		
		// Tower Panel
		.PANEL_TOWER_INFO = "%s (Lvl %d)",
		.PANEL_BUTTON_DAMAGE = "Damage ($%d)",
		.PANEL_BUTTON_SPEED = "Speed ($%d)",
		.PANEL_BUTTON_CRITICAL = "Critical ($%d)",
		.PANEL_BUTTON_SELL = "Sell ($%d)",
		.PANEL_STRATEGY_LABEL = "Target Strategy",
		.PANEL_STRATEGY_FIRST = "First",
		.PANEL_STRATEGY_LAST = "Last",
		.PANEL_STRATEGY_STRONG = "Strong",
		.PANEL_STRATEGY_WEAK = "Weak",
		
		// Editor
		.EDITOR_TOOL_EMPTY = "Empty",
		.EDITOR_TOOL_PATH = "Path",
		.EDITOR_TOOL_SPAWN = "Spawn",
		.EDITOR_TOOL_GOAL = "Goal",
		.EDITOR_TOOL_OBSTACLE = "Obstacle",
		.EDITOR_TOOL_TREE = "Tree",
		.EDITOR_TOOL_BLOCK = "Block",
		.EDITOR_BUTTON_SAVE = "Save Map",
		.EDITOR_BUTTON_LOAD = "Load Map",
		.EDITOR_BUTTON_SHOW_PATHS = "Show Paths",
		.EDITOR_BUTTON_HIDE_PATHS = "Hide Paths",
		.EDITOR_BIOME_PLAIN = "Plain",
		.EDITOR_BIOME_FOREST = "Forest",
		.EDITOR_BIOME_DESERT = "Desert",
		.EDITOR_BIOME_MOUNTAIN = "Mountain",
		
		// Game Over
		.GAME_OVER_TITLE = "GAME OVER",
		.GAME_OVER_WAVES_SURVIVED = "You survived %d waves",
		.GAME_OVER_BUTTON_MENU = "Main Menu",
		
		// Biomes
		.BIOME_PLAIN = "Plain",
		.BIOME_FOREST = "Forest",
		.BIOME_DESERT = "Desert",
		.BIOME_MOUNTAIN = "Mountain",
	},
}

// Current language (default to English)
current_language: Language = .ENGLISH

// Set current language
set_language :: proc(lang: Language) {
	current_language = lang
}

// Get translation for a key
get_text :: proc(key: TranslationKey) -> string {
	if translations, ok := TRANSLATIONS[current_language]; ok {
		if text, ok2 := translations[key]; ok2 {
			return text
		}
	}
	// Fallback to English
	if translations, ok := TRANSLATIONS[.ENGLISH]; ok {
		if text, ok2 := translations[key]; ok2 {
			return text
		}
	}
	return "MISSING"
}

// Get formatted translation
get_text_f :: proc(key: TranslationKey, args: ..any) -> string {
	base_text := get_text(key)
	return fmt.tprintf(base_text, ..args)
}

// Initialize translations - call this at game start
init_translations :: proc() {
	// Copy defaults to TRANSLATIONS
	TRANSLATIONS = make(map[Language]map[TranslationKey]string)
	
	// Copy English defaults first
	if english_map, ok := DEFAULT_TRANSLATIONS[.ENGLISH]; ok {
		TRANSLATIONS[.ENGLISH] = make(map[TranslationKey]string)
		english_ref := &TRANSLATIONS[.ENGLISH]
		for key, value in english_map {
			english_ref[key] = value
		}
	}
	
	// Try to load from file
	data, success := os.read_entire_file("translations.txt")
	if !success {
		fmt.println("translations.txt not found, using defaults")
		return
	}
	defer delete(data)
	
	content := string(data)
	lines := strings.split(content, "\n")
	for line in lines {
		line_clean := strings.trim_space(line)
		if len(line_clean) == 0 || strings.has_prefix(line_clean, "#") {
			continue
		}
		
		// Parse: KEY|LANGUAGE|VALUE
		parts := strings.split(line_clean, "|")
		if len(parts) != 3 {
			continue
		}
		
		key_str := strings.trim_space(parts[0])
		lang_str := strings.trim_space(parts[1])
		value := strings.trim_space(parts[2])
		
		// Convert language string to enum
		lang: Language
		switch lang_str {
		case "ENGLISH": lang = .ENGLISH
		case "SPANISH": lang = .SPANISH
		case "PORTUGUESE": lang = .PORTUGUESE
		case: continue
		}
		
		// Create language map if not exists
		if _, exists := TRANSLATIONS[lang]; !exists {
			TRANSLATIONS[lang] = make(map[TranslationKey]string)
		}
		
		// Convert key string to enum using map
		key, ok := KEY_STRING_MAP[key_str]
		if !ok {
			continue
		}
		
		// Store translation using pointer reference
		lang_ref := &TRANSLATIONS[lang]
		lang_ref[key] = value
	}
	
	fmt.println("Translations loaded from translations.txt")
}

package constants

import "core:fmt"
import "core:os"
import "core:strings"

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
// Fuente de verdad única: translations.txt
TRANSLATIONS: map[string]string

// Current language (default to English)
current_language: Language = .ENGLISH

// Set current language
set_language :: proc(lang: Language) {
	current_language = lang
}

// Get translated text for the current language.
// Si la clave no existe en translations.txt, retorna la clave tal cual — sin fallback a otros idiomas.
get_text :: proc(key: string) -> string {
	compound_key := fmt.tprintf("%v|%s", current_language, key)
	if text, ok := TRANSLATIONS[compound_key]; ok {
		return text
	}
	return key
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
	case .ICE:
		return get_text("TOWER_ICE_NAME")
	case .ENHANCE:
		return get_text("TOWER_ENHANCE_NAME")
	case .TESLA:
		return get_text("TOWER_TESLA_NAME")
	case .MORTAR:
		return get_text("TOWER_MORTAR_NAME")
	}
	return "Unknown"
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
		// IMPORTANTE: usar fmt.aprintf (heap) — no fmt.tprintf (temp_allocator).
		// Las claves del mapa deben vivir indefinidamente; el temp_allocator
		// se limpia al final de cada frame y al final de audio_init.
		compound_key := fmt.aprintf("%s|%s", lang_str, key_str)
		TRANSLATIONS[compound_key] = strings.clone(value_str)
		loaded_count += 1
	}
	
	fmt.printf("Loaded %d translations from translations.txt\n", loaded_count)
}

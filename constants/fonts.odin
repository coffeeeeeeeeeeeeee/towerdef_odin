package constants

import raylib "vendor:raylib"

// Font resources
Fonts :: struct {
	regular: raylib.Font,
	light: raylib.Font,
	bold: raylib.Font,
}

// Global fonts instance
game_fonts: Fonts

// Font paths
FONT_REGULAR_PATH :: "fonts/Inter_18pt-Regular.ttf"
FONT_LIGHT_PATH :: "fonts/Inter_18pt-Light.ttf"
FONT_BOLD_PATH :: "fonts/Inter_24pt-Bold.ttf"

// Load all fonts
load_fonts :: proc() {
	game_fonts.regular = raylib.LoadFont(FONT_REGULAR_PATH)
	game_fonts.light = raylib.LoadFont(FONT_LIGHT_PATH)
	game_fonts.bold = raylib.LoadFont(FONT_BOLD_PATH)
}

// Unload all fonts
unload_fonts :: proc() {
	raylib.UnloadFont(game_fonts.regular)
	raylib.UnloadFont(game_fonts.light)
	raylib.UnloadFont(game_fonts.bold)
}

// Get font size based on scale factor
get_font_size :: proc(base_size: f32, scale: f32) -> f32 {
	return base_size * scale
}

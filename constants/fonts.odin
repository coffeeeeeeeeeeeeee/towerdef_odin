package constants

import raylib "vendor:raylib"

// Font resources
Fonts :: struct {
	regular: raylib.Font,
	light: raylib.Font,
	semibold: raylib.Font,
	bold: raylib.Font,
}

// Global fonts instance
game_fonts: Fonts

// Font paths
FONT_REGULAR_PATH :: "fonts/Orbitron-SemiBold.ttf"
FONT_LIGHT_PATH :: "fonts/Orbitron-Regular.ttf"
FONT_SEMIBOLD_PATH :: "fonts/Orbitron-Medium.ttf"
FONT_BOLD_PATH :: "fonts/Orbitron-Bold.ttf"

// Font base sizes (larger for better quality when scaling)
FONT_BASE_SIZE :: 256

// Latin-1 codepoints count for Spanish/Portuguese support
LATIN1_CODEPOINT_COUNT :: 191

// Load all fonts with high quality settings
load_fonts :: proc() {
	// Generate Latin-1 codepoints (32-126 and 160-255)
	codepoints := make([]i32, LATIN1_CODEPOINT_COUNT)
	defer delete(codepoints)
	
	idx := 0
	// ASCII printable range (32-126)
	for i := 32; i <= 126; i += 1 {
		codepoints[idx] = i32(i)
		idx += 1
	}
	// Latin-1 Supplement (160-255)
	for i := 160; i <= 255; i += 1 {
		codepoints[idx] = i32(i)
		idx += 1
	}
	
	// Load fonts with larger base size and Latin-1 characters for Spanish/Portuguese
	game_fonts.regular = raylib.LoadFontEx(FONT_REGULAR_PATH, FONT_BASE_SIZE, cast([^]rune)raw_data(codepoints), i32(len(codepoints)))
	game_fonts.light = raylib.LoadFontEx(FONT_LIGHT_PATH, FONT_BASE_SIZE, cast([^]rune)raw_data(codepoints), i32(len(codepoints)))
	game_fonts.semibold = raylib.LoadFontEx(FONT_SEMIBOLD_PATH, FONT_BASE_SIZE, cast([^]rune)raw_data(codepoints), i32(len(codepoints)))
	game_fonts.bold = raylib.LoadFontEx(FONT_BOLD_PATH, FONT_BASE_SIZE, cast([^]rune)raw_data(codepoints), i32(len(codepoints)))
	
	// Generate mipmaps for smoother scaling
	raylib.GenTextureMipmaps(&game_fonts.regular.texture)
	raylib.GenTextureMipmaps(&game_fonts.light.texture)
	raylib.GenTextureMipmaps(&game_fonts.semibold.texture)
	raylib.GenTextureMipmaps(&game_fonts.bold.texture)
	
	// Enable trilinear filtering with mipmaps for best quality
	raylib.SetTextureFilter(game_fonts.regular.texture, .TRILINEAR)
	raylib.SetTextureFilter(game_fonts.light.texture, .TRILINEAR)
	raylib.SetTextureFilter(game_fonts.semibold.texture, .TRILINEAR)
	raylib.SetTextureFilter(game_fonts.bold.texture, .TRILINEAR)
}

// Unload all fonts
unload_fonts :: proc() {
	raylib.UnloadFont(game_fonts.regular)
	raylib.UnloadFont(game_fonts.light)
	raylib.UnloadFont(game_fonts.semibold)
	raylib.UnloadFont(game_fonts.bold)
}

// Get font size based on scale factor
get_font_size :: proc(base_size: f32, scale: f32) -> f32 {
	return base_size * scale
}

package constants

import raylib "vendor:raylib"

// Font resources
Fonts :: struct {
	regular:  raylib.Font,
	light:    raylib.Font,
	semibold: raylib.Font,
	bold:     raylib.Font,
}

// Icon textures (UI / HUD icons — los iconos de relictos se gestionan en entities/card.odin)
Icons :: struct {
	damage:        raylib.Texture2D,
	speed:         raylib.Texture2D,
	crit:          raylib.Texture2D,
	health:        raylib.Texture2D,
	wave:          raylib.Texture2D,
	money:         raylib.Texture2D,
	lock_locked:   raylib.Texture2D,
	lock_unlocked: raylib.Texture2D,

	// Card background images per rarity
	card_bg_common:   raylib.Texture2D,
	card_bg_uncommon: raylib.Texture2D,
	card_bg_rare:     raylib.Texture2D,
	card_bg_epic:     raylib.Texture2D,
}

// Global fonts instance
game_fonts: Fonts

// Global icons instance
game_icons: Icons

// Font paths
FONT_REGULAR_PATH :: "fonts/Orbitron-SemiBold.ttf"
FONT_LIGHT_PATH :: "fonts/Orbitron-Regular.ttf"
FONT_SEMIBOLD_PATH :: "fonts/Orbitron-Medium.ttf"
FONT_BOLD_PATH :: "fonts/Orbitron-Bold.ttf"

// Font base sizes (larger for better quality when scaling)
FONT_BASE_SIZE :: 128

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

// Load all icon textures
load_icons :: proc() {
	game_icons.damage = raylib.LoadTexture("images/icon_damage.png")
	game_icons.speed  = raylib.LoadTexture("images/icon_speed.png")
	game_icons.crit   = raylib.LoadTexture("images/icon_crit.png")
	game_icons.health = raylib.LoadTexture("images/icon_health.png")
	game_icons.wave   = raylib.LoadTexture("images/icon_wave.png")
	game_icons.money         = raylib.LoadTexture("images/icon_money.png")
	game_icons.lock_locked   = raylib.LoadTexture("images/icon_lock_locked.png")
	game_icons.lock_unlocked = raylib.LoadTexture("images/icon_lock_unlocked.png")

	game_icons.card_bg_common   = raylib.LoadTexture("images/cards/common.png")
	game_icons.card_bg_uncommon = raylib.LoadTexture("images/cards/uncommon.png")
	game_icons.card_bg_rare     = raylib.LoadTexture("images/cards/rare.png")
	game_icons.card_bg_epic     = raylib.LoadTexture("images/cards/epic.png")

	// Generate mipmaps and enable trilinear filtering for smooth downscaling
	raylib.GenTextureMipmaps(&game_icons.damage)
	raylib.GenTextureMipmaps(&game_icons.speed)
	raylib.GenTextureMipmaps(&game_icons.crit)
	raylib.GenTextureMipmaps(&game_icons.health)
	raylib.GenTextureMipmaps(&game_icons.wave)
	raylib.GenTextureMipmaps(&game_icons.money)
	raylib.GenTextureMipmaps(&game_icons.lock_locked)
	raylib.GenTextureMipmaps(&game_icons.lock_unlocked)

	raylib.SetTextureFilter(game_icons.damage,        .TRILINEAR)
	raylib.SetTextureFilter(game_icons.speed,         .TRILINEAR)
	raylib.SetTextureFilter(game_icons.crit,          .TRILINEAR)
	raylib.SetTextureFilter(game_icons.health,        .TRILINEAR)
	raylib.SetTextureFilter(game_icons.wave,          .TRILINEAR)
	raylib.SetTextureFilter(game_icons.money,         .TRILINEAR)
	raylib.SetTextureFilter(game_icons.lock_locked,   .TRILINEAR)
	raylib.SetTextureFilter(game_icons.lock_unlocked, .TRILINEAR)

	raylib.GenTextureMipmaps(&game_icons.card_bg_common)
	raylib.GenTextureMipmaps(&game_icons.card_bg_uncommon)
	raylib.GenTextureMipmaps(&game_icons.card_bg_rare)
	raylib.GenTextureMipmaps(&game_icons.card_bg_epic)

	raylib.SetTextureFilter(game_icons.card_bg_common,   .TRILINEAR)
	raylib.SetTextureFilter(game_icons.card_bg_uncommon, .TRILINEAR)
	raylib.SetTextureFilter(game_icons.card_bg_rare,     .TRILINEAR)
	raylib.SetTextureFilter(game_icons.card_bg_epic,     .TRILINEAR)
}

// Unload all icon textures
unload_icons :: proc() {
	raylib.UnloadTexture(game_icons.damage)
	raylib.UnloadTexture(game_icons.speed)
	raylib.UnloadTexture(game_icons.crit)
	raylib.UnloadTexture(game_icons.health)
	raylib.UnloadTexture(game_icons.wave)
	raylib.UnloadTexture(game_icons.money)
	raylib.UnloadTexture(game_icons.lock_locked)
	raylib.UnloadTexture(game_icons.lock_unlocked)

	raylib.UnloadTexture(game_icons.card_bg_common)
	raylib.UnloadTexture(game_icons.card_bg_uncommon)
	raylib.UnloadTexture(game_icons.card_bg_rare)
	raylib.UnloadTexture(game_icons.card_bg_epic)
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

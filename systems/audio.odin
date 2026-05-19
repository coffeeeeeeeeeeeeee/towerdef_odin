package systems

import "../constants"
import "../entities"
import "core:fmt"
import "vendor:raylib"

// Audio layer — determines which volume setting applies
Audio_Layer :: enum {
	UI,
	SFX,
}

// Unified sound enum (UI + gameplay)
Sound :: enum {
	NONE,
	// UI sounds
	CLICK,
	SELECT,
	TOGGLE,
	SWITCH,
	SCROLL,
	OPEN,
	CLOSE,
	MAXIMIZE,
	MINIMIZE,
	CONFIRMATION,
	ERROR,
	QUESTION,
	BACK,
	DROP,
	GLASS,
	GLITCH,
	PLUCK,
	SCRATCH,
	TICK,
	// SFX gameplay sounds
	TOWER_ARCHER,
	TOWER_CANNON,
	TOWER_SNIPER,
	TOWER_MISSILE,
	TOWER_LASER,
	TOWER_ICE,
	PROJECTILE_HIT,
	EXPLOSION,
	ENEMY_DEATH,
	ENEMY_REACH_GOAL,
	ENEMY_SPAWN,
	WAVE_COMPLETE,
	CARD_GAINED,
}

// Audio system state
Audio_State :: struct {
	click_sounds:        [5]raylib.Sound,
	select_sounds:       [8]raylib.Sound,
	toggle_sounds:       [4]raylib.Sound,
	switch_sounds:       [7]raylib.Sound,
	scroll_sounds:       [5]raylib.Sound,
	open_sounds:         [4]raylib.Sound,
	close_sounds:        [4]raylib.Sound,
	maximize_sounds:     [9]raylib.Sound,
	minimize_sounds:     [9]raylib.Sound,
	confirmation_sounds: [4]raylib.Sound,
	error_sounds:        [8]raylib.Sound,
	question_sounds:     [4]raylib.Sound,
	back_sounds:         [4]raylib.Sound,
	drop_sounds:         [4]raylib.Sound,
	glass_sounds:        [6]raylib.Sound,
	glitch_sounds:       [4]raylib.Sound,
	pluck_sounds:        [2]raylib.Sound,
	scratch_sounds:      [5]raylib.Sound,
	tick_sounds:         [3]raylib.Sound,

	// SFX gameplay sounds
	tower_fire_sfx:    [2]raylib.Sound,  // zap1-2
	ice_sfx:           [3]raylib.Sound,  // phaserDown1-3
	hit_sfx:           [1]raylib.Sound,  // tone1
	explosion_sfx:     [4]raylib.Sound,  // zapThreeToneDown/Up, zapTwoTone/2
	death_sfx:         [2]raylib.Sound,  // threeTone1-2
	goal_sfx:          [2]raylib.Sound,  // bong_001, lowDown
	spawn_sfx:         [1]raylib.Sound,  // lowRandom
	wave_complete_sfx: [12]raylib.Sound, // powerUp1-12
	card_sfx:          [3]raylib.Sound,  // twoTone1-2, highUp

	initialized: bool,
}

audio_state: Audio_State

// Per-layer volume (pre-multiplied with master: master * layer_slider)
layer_volumes: [Audio_Layer]f32 = {.UI = 1.0, .SFX = 1.0}

// Set volume for a specific layer (pass master * layer_slider as volume)
set_volume :: proc(layer: Audio_Layer, volume: f32) {
	layer_volumes[layer] = volume
}

// Initialize audio system
audio_init :: proc() {
	if audio_state.initialized {
		return
	}

	raylib.InitAudioDevice()

	for i in 0 ..< 5  { audio_state.click_sounds[i]        = raylib.LoadSound(fmt.ctprintf("audio/click_%03d.ogg",        i + 1)) }
	for i in 0 ..< 8  { audio_state.select_sounds[i]       = raylib.LoadSound(fmt.ctprintf("audio/select_%03d.ogg",       i + 1)) }
	for i in 0 ..< 4  { audio_state.toggle_sounds[i]       = raylib.LoadSound(fmt.ctprintf("audio/toggle_%03d.ogg",       i + 1)) }
	for i in 0 ..< 7  { audio_state.switch_sounds[i]       = raylib.LoadSound(fmt.ctprintf("audio/switch_%03d.ogg",       i + 1)) }
	for i in 0 ..< 5  { audio_state.scroll_sounds[i]       = raylib.LoadSound(fmt.ctprintf("audio/scroll_%03d.ogg",       i + 1)) }
	for i in 0 ..< 4  { audio_state.open_sounds[i]         = raylib.LoadSound(fmt.ctprintf("audio/open_%03d.ogg",         i + 1)) }
	for i in 0 ..< 4  { audio_state.close_sounds[i]        = raylib.LoadSound(fmt.ctprintf("audio/close_%03d.ogg",        i + 1)) }
	for i in 0 ..< 9  { audio_state.maximize_sounds[i]     = raylib.LoadSound(fmt.ctprintf("audio/maximize_%03d.ogg",     i + 1)) }
	for i in 0 ..< 9  { audio_state.minimize_sounds[i]     = raylib.LoadSound(fmt.ctprintf("audio/minimize_%03d.ogg",     i + 1)) }
	for i in 0 ..< 4  { audio_state.confirmation_sounds[i] = raylib.LoadSound(fmt.ctprintf("audio/confirmation_%03d.ogg", i + 1)) }
	for i in 0 ..< 8  { audio_state.error_sounds[i]        = raylib.LoadSound(fmt.ctprintf("audio/error_%03d.ogg",        i + 1)) }
	for i in 0 ..< 4  { audio_state.question_sounds[i]     = raylib.LoadSound(fmt.ctprintf("audio/question_%03d.ogg",     i + 1)) }
	for i in 0 ..< 4  { audio_state.back_sounds[i]         = raylib.LoadSound(fmt.ctprintf("audio/back_%03d.ogg",         i + 1)) }
	for i in 0 ..< 4  { audio_state.drop_sounds[i]         = raylib.LoadSound(fmt.ctprintf("audio/drop_%03d.ogg",         i + 1)) }
	for i in 0 ..< 6  { audio_state.glass_sounds[i]        = raylib.LoadSound(fmt.ctprintf("audio/glass_%03d.ogg",        i + 1)) }
	for i in 0 ..< 4  { audio_state.glitch_sounds[i]       = raylib.LoadSound(fmt.ctprintf("audio/glitch_%03d.ogg",       i + 1)) }
	for i in 0 ..< 2  { audio_state.pluck_sounds[i]        = raylib.LoadSound(fmt.ctprintf("audio/pluck_%03d.ogg",        i + 1)) }
	for i in 0 ..< 5  { audio_state.scratch_sounds[i]      = raylib.LoadSound(fmt.ctprintf("audio/scratch_%03d.ogg",      i + 1)) }

	// tick_003.ogg no existe — usar 001, 002, 004
	audio_state.tick_sounds[0] = raylib.LoadSound("audio/tick_001.ogg")
	audio_state.tick_sounds[1] = raylib.LoadSound("audio/tick_002.ogg")
	audio_state.tick_sounds[2] = raylib.LoadSound("audio/tick_004.ogg")

	for i in 0 ..< 2  { audio_state.tower_fire_sfx[i]    = raylib.LoadSound(fmt.ctprintf("audio/zap%d.ogg",        i + 1)) }
	for i in 0 ..< 3  { audio_state.ice_sfx[i]           = raylib.LoadSound(fmt.ctprintf("audio/phaserDown%d.ogg", i + 1)) }
	audio_state.hit_sfx[0]        = raylib.LoadSound("audio/tone1.ogg")
	audio_state.explosion_sfx[0]  = raylib.LoadSound("audio/zapThreeToneDown.ogg")
	audio_state.explosion_sfx[1]  = raylib.LoadSound("audio/zapThreeToneUp.ogg")
	audio_state.explosion_sfx[2]  = raylib.LoadSound("audio/zapTwoTone.ogg")
	audio_state.explosion_sfx[3]  = raylib.LoadSound("audio/zapTwoTone2.ogg")
	for i in 0 ..< 2  { audio_state.death_sfx[i]         = raylib.LoadSound(fmt.ctprintf("audio/threeTone%d.ogg",  i + 1)) }
	audio_state.goal_sfx[0]       = raylib.LoadSound("audio/bong_001.ogg")
	audio_state.goal_sfx[1]       = raylib.LoadSound("audio/lowDown.ogg")
	audio_state.spawn_sfx[0]      = raylib.LoadSound("audio/lowRandom.ogg")
	for i in 0 ..< 12 { audio_state.wave_complete_sfx[i] = raylib.LoadSound(fmt.ctprintf("audio/powerUp%d.ogg",    i + 1)) }
	audio_state.card_sfx[0]       = raylib.LoadSound("audio/twoTone1.ogg")
	audio_state.card_sfx[1]       = raylib.LoadSound("audio/twoTone2.ogg")
	audio_state.card_sfx[2]       = raylib.LoadSound("audio/highUp.ogg")

	audio_state.initialized = true
}

// Play a sound on the given audio layer
play_sound :: proc(sound: Sound, layer: Audio_Layer) {
	if !audio_state.initialized {
		return
	}

	vol := layer_volumes[layer]

	_play :: proc(s: raylib.Sound, v: f32) {
		raylib.SetSoundVolume(s, v)
		raylib.PlaySound(s)
	}

	switch sound {
	case .NONE:
		// nothing
	case .CLICK:
		_play(audio_state.click_sounds[raylib.GetRandomValue(0, 4)], vol)
	case .SELECT:
		_play(audio_state.select_sounds[raylib.GetRandomValue(0, 7)], vol)
	case .TOGGLE:
		_play(audio_state.toggle_sounds[raylib.GetRandomValue(0, 3)], vol)
	case .SWITCH:
		_play(audio_state.switch_sounds[raylib.GetRandomValue(0, 6)], vol)
	case .SCROLL:
		_play(audio_state.scroll_sounds[raylib.GetRandomValue(0, 4)], vol)
	case .OPEN:
		_play(audio_state.open_sounds[raylib.GetRandomValue(0, 3)], vol)
	case .CLOSE:
		_play(audio_state.close_sounds[raylib.GetRandomValue(0, 3)], vol)
	case .MAXIMIZE:
		_play(audio_state.maximize_sounds[raylib.GetRandomValue(0, 8)], vol)
	case .MINIMIZE:
		_play(audio_state.minimize_sounds[raylib.GetRandomValue(0, 8)], vol)
	case .CONFIRMATION:
		_play(audio_state.confirmation_sounds[raylib.GetRandomValue(0, 3)], vol)
	case .ERROR:
		_play(audio_state.error_sounds[raylib.GetRandomValue(0, 7)], vol)
	case .QUESTION:
		_play(audio_state.question_sounds[raylib.GetRandomValue(0, 3)], vol)
	case .BACK:
		_play(audio_state.back_sounds[raylib.GetRandomValue(0, 3)], vol)
	case .DROP:
		_play(audio_state.drop_sounds[raylib.GetRandomValue(0, 3)], vol)
	case .GLASS:
		_play(audio_state.glass_sounds[raylib.GetRandomValue(0, 5)], vol)
	case .GLITCH:
		_play(audio_state.glitch_sounds[raylib.GetRandomValue(0, 3)], vol)
	case .PLUCK:
		_play(audio_state.pluck_sounds[raylib.GetRandomValue(0, 1)], vol)
	case .SCRATCH:
		_play(audio_state.scratch_sounds[raylib.GetRandomValue(0, 4)], vol)
	case .TICK:
		_play(audio_state.tick_sounds[raylib.GetRandomValue(0, 2)], vol)
	case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
		_play(audio_state.tower_fire_sfx[raylib.GetRandomValue(0, 1)], vol)
	case .TOWER_ICE:
		_play(audio_state.ice_sfx[raylib.GetRandomValue(0, 2)], vol)
	case .PROJECTILE_HIT:
		_play(audio_state.hit_sfx[0], vol)
	case .EXPLOSION:
		_play(audio_state.explosion_sfx[raylib.GetRandomValue(0, 3)], vol)
	case .ENEMY_DEATH:
		_play(audio_state.death_sfx[raylib.GetRandomValue(0, 1)], vol)
	case .ENEMY_REACH_GOAL:
		_play(audio_state.goal_sfx[raylib.GetRandomValue(0, 1)], vol)
	case .ENEMY_SPAWN:
		_play(audio_state.spawn_sfx[0], vol)
	case .WAVE_COMPLETE:
		_play(audio_state.wave_complete_sfx[raylib.GetRandomValue(0, 11)], vol)
	case .CARD_GAINED:
		_play(audio_state.card_sfx[raylib.GetRandomValue(0, 2)], vol)
	}
}

// Cleanup audio system
audio_cleanup :: proc() {
	if !audio_state.initialized {
		return
	}

	raylib.CloseAudioDevice()

	for i in 0 ..< 5  { raylib.UnloadSound(audio_state.click_sounds[i]) }
	for i in 0 ..< 8  { raylib.UnloadSound(audio_state.select_sounds[i]) }
	for i in 0 ..< 4  { raylib.UnloadSound(audio_state.toggle_sounds[i]) }
	for i in 0 ..< 7  { raylib.UnloadSound(audio_state.switch_sounds[i]) }
	for i in 0 ..< 5  { raylib.UnloadSound(audio_state.scroll_sounds[i]) }
	for i in 0 ..< 4  { raylib.UnloadSound(audio_state.open_sounds[i]) }
	for i in 0 ..< 4  { raylib.UnloadSound(audio_state.close_sounds[i]) }
	for i in 0 ..< 9  { raylib.UnloadSound(audio_state.maximize_sounds[i]) }
	for i in 0 ..< 9  { raylib.UnloadSound(audio_state.minimize_sounds[i]) }
	for i in 0 ..< 4  { raylib.UnloadSound(audio_state.confirmation_sounds[i]) }
	for i in 0 ..< 8  { raylib.UnloadSound(audio_state.error_sounds[i]) }
	for i in 0 ..< 4  { raylib.UnloadSound(audio_state.question_sounds[i]) }
	for i in 0 ..< 4  { raylib.UnloadSound(audio_state.back_sounds[i]) }
	for i in 0 ..< 4  { raylib.UnloadSound(audio_state.drop_sounds[i]) }
	for i in 0 ..< 6  { raylib.UnloadSound(audio_state.glass_sounds[i]) }
	for i in 0 ..< 4  { raylib.UnloadSound(audio_state.glitch_sounds[i]) }
	for i in 0 ..< 2  { raylib.UnloadSound(audio_state.pluck_sounds[i]) }
	for i in 0 ..< 5  { raylib.UnloadSound(audio_state.scratch_sounds[i]) }
	for i in 0 ..< 3  { raylib.UnloadSound(audio_state.tick_sounds[i]) }

	for i in 0 ..< 2  { raylib.UnloadSound(audio_state.tower_fire_sfx[i]) }
	for i in 0 ..< 3  { raylib.UnloadSound(audio_state.ice_sfx[i]) }
	raylib.UnloadSound(audio_state.hit_sfx[0])
	for i in 0 ..< 4  { raylib.UnloadSound(audio_state.explosion_sfx[i]) }
	for i in 0 ..< 2  { raylib.UnloadSound(audio_state.death_sfx[i]) }
	for i in 0 ..< 2  { raylib.UnloadSound(audio_state.goal_sfx[i]) }
	raylib.UnloadSound(audio_state.spawn_sfx[0])
	for i in 0 ..< 12 { raylib.UnloadSound(audio_state.wave_complete_sfx[i]) }
	for i in 0 ..< 3  { raylib.UnloadSound(audio_state.card_sfx[i]) }

	audio_state.initialized = false
}

package systems

import "../constants"
import "../entities"
import "core:fmt"
import "core:strings"
import "vendor:raylib"

// Sound type enumeration
Sound_Type :: enum {
	NONE,
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
}

// Audio system state
Audio_State :: struct {
	click_sounds: [5]raylib.Sound,
	select_sounds: [8]raylib.Sound,
	toggle_sounds: [4]raylib.Sound,
	switch_sounds: [7]raylib.Sound,
	scroll_sounds: [5]raylib.Sound,
	open_sounds: [4]raylib.Sound,
	close_sounds: [4]raylib.Sound,
	maximize_sounds: [9]raylib.Sound,
	minimize_sounds: [9]raylib.Sound,
	confirmation_sounds: [4]raylib.Sound,
	error_sounds: [8]raylib.Sound,
	question_sounds: [4]raylib.Sound,
	back_sounds: [4]raylib.Sound,
	drop_sounds: [4]raylib.Sound,
	glass_sounds: [6]raylib.Sound,
	glitch_sounds: [4]raylib.Sound,
	pluck_sounds: [2]raylib.Sound,
	scratch_sounds: [5]raylib.Sound,
	tick_sounds: [3]raylib.Sound,
	
	initialized: bool,
}

audio_state: Audio_State

// UI volume (can be updated from settings)
ui_volume: f32 = 1.0

// Set UI volume from settings (combined with master volume)
set_ui_volume :: proc(master_volume: f32, ui_vol: f32) {
	ui_volume = master_volume * ui_vol
}

// Initialize audio system
audio_init :: proc() {
	if audio_state.initialized {
		return
	}

	raylib.InitAudioDevice()

	// Load click sounds
	for i in 0 ..< 5 {
		audio_state.click_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/click_%03d.ogg", i + 1)))
	}

	// Load select sounds
	for i in 0 ..< 8 {
		audio_state.select_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/select_%03d.ogg", i + 1)))
	}

	// Load toggle sounds
	for i in 0 ..< 4 {
		audio_state.toggle_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/toggle_%03d.ogg", i + 1)))
	}

	// Load switch sounds
	for i in 0 ..< 7 {
		audio_state.switch_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/switch_%03d.ogg", i + 1)))
	}

	// Load scroll sounds
	for i in 0 ..< 5 {
		audio_state.scroll_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/scroll_%03d.ogg", i + 1)))
	}

	// Load open sounds
	for i in 0 ..< 4 {
		audio_state.open_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/open_%03d.ogg", i + 1)))
	}

	// Load close sounds
	for i in 0 ..< 4 {
		audio_state.close_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/close_%03d.ogg", i + 1)))
	}

	// Load maximize sounds
	for i in 0 ..< 9 {
		audio_state.maximize_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/maximize_%03d.ogg", i + 1)))
	}

	// Load minimize sounds
	for i in 0 ..< 9 {
		audio_state.minimize_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/minimize_%03d.ogg", i + 1)))
	}

	// Load confirmation sounds
	for i in 0 ..< 4 {
		audio_state.confirmation_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/confirmation_%03d.ogg", i + 1)))
	}

	// Load error sounds
	for i in 0 ..< 8 {
		audio_state.error_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/error_%03d.ogg", i + 1)))
	}

	// Load question sounds
	for i in 0 ..< 4 {
		audio_state.question_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/question_%03d.ogg", i + 1)))
	}

	// Load back sounds
	for i in 0 ..< 4 {
		audio_state.back_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/back_%03d.ogg", i + 1)))
	}

	// Load drop sounds
	for i in 0 ..< 4 {
		audio_state.drop_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/drop_%03d.ogg", i + 1)))
	}

	// Load glass sounds
	for i in 0 ..< 6 {
		audio_state.glass_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/glass_%03d.ogg", i + 1)))
	}

	// Load glitch sounds
	for i in 0 ..< 4 {
		audio_state.glitch_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/glitch_%03d.ogg", i + 1)))
	}

	// Load pluck sounds
	for i in 0 ..< 2 {
		audio_state.pluck_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/pluck_%03d.ogg", i + 1)))
	}

	// Load scratch sounds
	for i in 0 ..< 5 {
		audio_state.scratch_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/scratch_%03d.ogg", i + 1)))
	}

	// Load tick sounds
	for i in 0 ..< 3 {
		audio_state.tick_sounds[i] = raylib.LoadSound(strings.clone_to_cstring(fmt.tprintf("audio/tick_%03d.ogg", i + 1)))
	}
	
	audio_state.initialized = true
}

// Play a sound by type (random variant)
play_sound :: proc(sound_type: Sound_Type) {
	if !audio_state.initialized {
		return
	}

	// Check if audio is enabled in settings
	// TODO: Add audio enabled check from settings

	switch sound_type {
	case .NONE:
		// Do nothing
	case .CLICK:
		idx := raylib.GetRandomValue(0, 4)
		sound := audio_state.click_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)
	
	case .SELECT:
		idx := raylib.GetRandomValue(0, 7)
		sound := audio_state.select_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .TOGGLE:
		idx := raylib.GetRandomValue(0, 3)
		sound := audio_state.toggle_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .SWITCH:
		idx := raylib.GetRandomValue(0, 6)
		sound := audio_state.switch_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .SCROLL:
		idx := raylib.GetRandomValue(0, 4)
		sound := audio_state.scroll_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .OPEN:
		idx := raylib.GetRandomValue(0, 3)
		sound := audio_state.open_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .CLOSE:
		idx := raylib.GetRandomValue(0, 3)
		sound := audio_state.close_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .MAXIMIZE:
		idx := raylib.GetRandomValue(0, 8)
		sound := audio_state.maximize_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .MINIMIZE:
		idx := raylib.GetRandomValue(0, 8)
		sound := audio_state.minimize_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .CONFIRMATION:
		idx := raylib.GetRandomValue(0, 3)
		sound := audio_state.confirmation_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .ERROR:
		idx := raylib.GetRandomValue(0, 7)
		sound := audio_state.error_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .QUESTION:
		idx := raylib.GetRandomValue(0, 3)
		sound := audio_state.question_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .BACK:
		idx := raylib.GetRandomValue(0, 3)
		sound := audio_state.back_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .DROP:
		idx := raylib.GetRandomValue(0, 3)
		sound := audio_state.drop_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .GLASS:
		idx := raylib.GetRandomValue(0, 5)
		sound := audio_state.glass_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .GLITCH:
		idx := raylib.GetRandomValue(0, 3)
		sound := audio_state.glitch_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .PLUCK:
		idx := raylib.GetRandomValue(0, 1)
		sound := audio_state.pluck_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .SCRATCH:
		idx := raylib.GetRandomValue(0, 4)
		sound := audio_state.scratch_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)

	case .TICK:
		idx := raylib.GetRandomValue(0, 2)
		sound := audio_state.tick_sounds[idx]
		raylib.SetSoundVolume(sound, ui_volume)
		raylib.PlaySound(sound)
	
	case:
		// Do nothing for NONE or unknown types
	}
}

// Cleanup audio system
audio_cleanup :: proc() {
	if !audio_state.initialized {
		return
	}

	raylib.CloseAudioDevice()

	// Unload all sounds
	for i in 0 ..< 5 {
		raylib.UnloadSound(audio_state.click_sounds[i])
	}
	for i in 0 ..< 8 {
		raylib.UnloadSound(audio_state.select_sounds[i])
	}
	for i in 0 ..< 4 {
		raylib.UnloadSound(audio_state.toggle_sounds[i])
	}
	for i in 0 ..< 7 {
		raylib.UnloadSound(audio_state.switch_sounds[i])
	}
	for i in 0 ..< 5 {
		raylib.UnloadSound(audio_state.scroll_sounds[i])
	}
	for i in 0 ..< 4 {
		raylib.UnloadSound(audio_state.open_sounds[i])
	}
	for i in 0 ..< 4 {
		raylib.UnloadSound(audio_state.close_sounds[i])
	}
	for i in 0 ..< 9 {
		raylib.UnloadSound(audio_state.maximize_sounds[i])
	}
	for i in 0 ..< 9 {
		raylib.UnloadSound(audio_state.minimize_sounds[i])
	}
	for i in 0 ..< 4 {
		raylib.UnloadSound(audio_state.confirmation_sounds[i])
	}
	for i in 0 ..< 8 {
		raylib.UnloadSound(audio_state.error_sounds[i])
	}
	for i in 0 ..< 4 {
		raylib.UnloadSound(audio_state.question_sounds[i])
	}
	for i in 0 ..< 4 {
		raylib.UnloadSound(audio_state.back_sounds[i])
	}
	for i in 0 ..< 4 {
		raylib.UnloadSound(audio_state.drop_sounds[i])
	}
	for i in 0 ..< 6 {
		raylib.UnloadSound(audio_state.glass_sounds[i])
	}
	for i in 0 ..< 4 {
		raylib.UnloadSound(audio_state.glitch_sounds[i])
	}
	for i in 0 ..< 2 {
		raylib.UnloadSound(audio_state.pluck_sounds[i])
	}
	for i in 0 ..< 5 {
		raylib.UnloadSound(audio_state.scratch_sounds[i])
	}
	for i in 0 ..< 3 {
		raylib.UnloadSound(audio_state.tick_sounds[i])
	}
	
	audio_state.initialized = false
}

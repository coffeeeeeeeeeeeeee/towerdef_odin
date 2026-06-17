package systems

import "../constants"
import "../entities"
import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "vendor:raylib"

// Audio layer — determines which volume setting applies
Audio_Layer :: enum {
	UI,
	SFX,
	MUSIC,
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
layer_volumes: [Audio_Layer]f32 = {.UI = 1.0, .SFX = 1.0, .MUSIC = 1.0}

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

// Play a positional SFX — volume is attenuated and stereo pan is set based on
// the sound source's grid position relative to the screen center.
//
//   grid_x = column coordinate  (same convention as enemy.x or f32(tower.c))
//   grid_y = row    coordinate  (same convention as enemy.y or f32(tower.r))
//
// UI sounds that somehow end up here fall through to play_sound (centered, full vol).
// Requires Raylib ≥ 4.2 (SetSoundPan).
play_sound_at :: proc(
	sound:  Sound,
	layer:  Audio_Layer,
	grid_x: f32,
	grid_y: f32,
	app:    ^entities.App_State,
) {
	if !audio_state.initialized { return }

	// Grid-cell center → screen pixels
	cs := f32(app.settings.cell_size) * app.zoom
	sx := f32(app.camera_offset_x) + (grid_x + 0.5) * cs
	sy := f32(app.camera_offset_y) + (grid_y + 0.5) * cs

	screen_w := f32(raylib.GetScreenWidth())
	screen_h := f32(raylib.GetScreenHeight())
	cx       := screen_w * 0.5
	cy       := screen_h * 0.5

	dx := sx - cx
	dy := sy - cy

	// Half-diagonal of the screen — sounds at the corner reach 0 volume
	max_dist := math.sqrt_f32(cx*cx + cy*cy)
	if max_dist <= 0 { max_dist = 1 }

	dist        := math.sqrt_f32(dx*dx + dy*dy)
	attenuation := f32(1.0) / (f32(1.0) + dist / max_dist)

	// Pan: 0 = full left, 0.5 = centre, 1 = full right
	pan: f32 = 0.5
	if cx > 0 {
		pan = clamp(0.5 + 0.5 * dx / cx, 0.0, 1.0)
	}

	vol := layer_volumes[layer] * attenuation

	_play_pos :: proc(s: raylib.Sound, v: f32, p: f32) {
		raylib.SetSoundVolume(s, v)
		raylib.SetSoundPan(s, p)
		raylib.PlaySound(s)
	}

	#partial switch sound {
	case .TOWER_ARCHER, .TOWER_CANNON, .TOWER_SNIPER, .TOWER_MISSILE, .TOWER_LASER:
		_play_pos(audio_state.tower_fire_sfx[raylib.GetRandomValue(0, 1)], vol, pan)
	case .TOWER_ICE:
		_play_pos(audio_state.ice_sfx[raylib.GetRandomValue(0, 2)], vol, pan)
	case .PROJECTILE_HIT:
		_play_pos(audio_state.hit_sfx[0], vol, pan)
	case .EXPLOSION:
		_play_pos(audio_state.explosion_sfx[raylib.GetRandomValue(0, 3)], vol, pan)
	case .ENEMY_DEATH:
		_play_pos(audio_state.death_sfx[raylib.GetRandomValue(0, 1)], vol, pan)
	case .ENEMY_REACH_GOAL:
		_play_pos(audio_state.goal_sfx[raylib.GetRandomValue(0, 1)], vol, pan)
	case .ENEMY_SPAWN:
		_play_pos(audio_state.spawn_sfx[0], vol, pan)
	case: // UI sounds / anything not positional: fall through to centered playback
		play_sound(sound, layer)
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Music system — streaming tracks that rotate sequentially during gameplay.
// Plays during PLAYING and PAUSED states; stops in all other states.
// ─────────────────────────────────────────────────────────────────────────────

MAX_MUSIC_TRACKS    :: 8
MUSIC_FADE_OUT_SECS :: f32(1.5)  // duración del fade-out al salir del juego
MUSIC_FADE_IN_SECS  :: f32(2.0)  // duración del fade-in al entrar al juego

// ── Low-pass filter ───────────────────────────────────────────────────────────
// Estado persistente del filtro — accedido desde el thread de audio.
// cutoff = 70 Hz → efecto "amortiguado detrás de una puerta".
_lpf_low: [2]f32

_audio_effect_lpf :: proc "c" (buffer: rawptr, frames: c.uint) {
	LPF_CUTOFF :: f32(100.0 / 44100.0)
	K          :: LPF_CUTOFF / (LPF_CUTOFF + 0.1591549431)
	data := cast([^]f32)buffer
	for i := c.uint(0); i < frames * 2; i += 2 {
		_lpf_low[0] += K * (data[i]     - _lpf_low[0])
		_lpf_low[1] += K * (data[i + 1] - _lpf_low[1])
		data[i]     = _lpf_low[0]
		data[i + 1] = _lpf_low[1]
	}
}

Music_State :: struct {
	tracks:      [MAX_MUSIC_TRACKS]raylib.Music,
	count:       int,
	current:     int,
	playing:     bool,
	fading_out:  bool,
	fading_in:   bool,
	fade_volume: f32,  // multiplicador de fade [0..1], 1 = volumen completo
	lpf_active:  bool,
}

music_state: Music_State

// Load all music tracks from the music/ folder dynamically.
// Supports .mp3, .ogg, and .wav. Tracks are sorted alphabetically.
// Call once after audio_init.
music_init :: proc() {
	MUSIC_DIR :: "music"
	AUDIO_EXTS := [?]string{".mp3", ".ogg", ".wav"}

	fd, err := os.open(MUSIC_DIR)
	if err != os.ERROR_NONE {
		fmt.printfln("[music_init] no se pudo abrir la carpeta '%s': %v", MUSIC_DIR, err)
		return
	}
	defer os.close(fd)

	infos, read_err := os.read_dir(fd, -1)
	if read_err != os.ERROR_NONE {
		fmt.printfln("[music_init] error leyendo '%s': %v", MUSIC_DIR, read_err)
		return
	}
	defer os.file_info_slice_delete(infos)

	// Collect matching file names, sort alphabetically for consistent order
	names := make([dynamic]string, context.temp_allocator)
	for info in infos {
		if info.is_dir { continue }
		for ext in AUDIO_EXTS {
			if strings.has_suffix(info.name, ext) {
				append(&names, info.name)
				break
			}
		}
	}
	slice.sort(names[:])

	for name in names {
		if music_state.count >= MAX_MUSIC_TRACKS { break }
		path := fmt.ctprintf("%s/%s", MUSIC_DIR, name)
		track := raylib.LoadMusicStream(path)
		if track.stream.buffer != nil {
			track.looping = false
			music_state.tracks[music_state.count] = track
			music_state.count += 1
			fmt.printfln("[music_init] cargado: %s", name)
		} else {
			fmt.printfln("[music_init] no se pudo cargar: %s", name)
		}
	}

	fmt.printfln("[music_init] %d pista(s) cargadas", music_state.count)
}

// Update music each frame. Must be called from the main loop with the current dt.
// Starts/stops playback based on game state, fades out smoothly on stop,
// and advances to the next track when the current one finishes.
// muffled=true activa el low-pass filter (PAUSED, shop abierto, etc.)
music_update :: proc(state: constants.Game_State, dt: f32, muffled: bool = false) {
	if music_state.count == 0 { return }

	should_play := state == .PLAYING || state == .PAUSED

	if !should_play {
		if music_state.playing && !music_state.fading_out {
			// Iniciar fade-out
			music_state.fading_out  = true
			music_state.fade_volume = 1.0
		}
		if music_state.fading_out {
			music_state.fade_volume -= dt / MUSIC_FADE_OUT_SECS
			if music_state.fade_volume <= 0 {
				// Fade completado — detener stream
				raylib.StopMusicStream(music_state.tracks[music_state.current])
				music_state.playing     = false
				music_state.fading_out  = false
				music_state.fade_volume = 0
				return
			}
			raylib.SetMusicVolume(
				music_state.tracks[music_state.current],
				layer_volumes[.MUSIC] * music_state.fade_volume,
			)
			raylib.UpdateMusicStream(music_state.tracks[music_state.current])
		}
		return
	}

	// Si estaba en fade-out pero vuelve a should_play, cancelar y arrancar fade-in
	if music_state.fading_out {
		music_state.fading_out = false
		music_state.fading_in  = true
		// fade_volume ya tiene el valor parcial del fade-out — arranca el fade-in desde ahí
	}

	if !music_state.playing {
		music_state.fade_volume = 0
		music_state.fading_in   = true
		raylib.PlayMusicStream(music_state.tracks[music_state.current])
		raylib.SetMusicVolume(music_state.tracks[music_state.current], 0)
		music_state.playing = true
	}

	// Fade-in en curso
	if music_state.fading_in {
		music_state.fade_volume += dt / MUSIC_FADE_IN_SECS
		if music_state.fade_volume >= 1.0 {
			music_state.fade_volume = 1.0
			music_state.fading_in   = false
		}
		raylib.SetMusicVolume(
			music_state.tracks[music_state.current],
			layer_volumes[.MUSIC] * music_state.fade_volume,
		)
	}

	// Aplicar / quitar LPF según estado
	music_set_lpf(muffled)

	// Debe llamarse cada frame para mantener el buffer del stream
	raylib.UpdateMusicStream(music_state.tracks[music_state.current])

	// Avanzar a la siguiente pista cuando la actual termina
	if !raylib.IsMusicStreamPlaying(music_state.tracks[music_state.current]) {
		// Desadjuntar LPF de la pista que termina
		if music_state.lpf_active {
			raylib.DetachAudioStreamProcessor(
				music_state.tracks[music_state.current].stream, _audio_effect_lpf,
			)
		}
		music_state.current = (music_state.current + 1) % music_state.count
		raylib.PlayMusicStream(music_state.tracks[music_state.current])
		raylib.SetMusicVolume(music_state.tracks[music_state.current], layer_volumes[.MUSIC])
		// Re-adjuntar LPF en la nueva pista si sigue activo
		if music_state.lpf_active {
			_lpf_low = {}
			raylib.AttachAudioStreamProcessor(
				music_state.tracks[music_state.current].stream, _audio_effect_lpf,
			)
		}
	}
}

// Set music volume and apply immediately to the current track.
// Respeta el fade_volume actual para no romper ningún fade en curso.
music_set_volume :: proc(volume: f32) {
	layer_volumes[.MUSIC] = volume
	if music_state.count > 0 && (music_state.playing || music_state.fading_out) {
		in_fade := music_state.fading_out || music_state.fading_in
		effective := volume * music_state.fade_volume if in_fade else volume
		raylib.SetMusicVolume(music_state.tracks[music_state.current], effective)
	}
}

// Activa o desactiva el low-pass filter en la pista actual.
// Si el estado no cambia, no hace nada (evita attach/detach redundantes).
music_set_lpf :: proc(enabled: bool) {
	if music_state.count == 0 || enabled == music_state.lpf_active { return }
	music_state.lpf_active = enabled
	if !music_state.playing { return }
	stream := music_state.tracks[music_state.current].stream
	if enabled {
		_lpf_low = {}  // resetear estado del filtro al activarlo
		raylib.AttachAudioStreamProcessor(stream, _audio_effect_lpf)
	} else {
		raylib.DetachAudioStreamProcessor(stream, _audio_effect_lpf)
	}
}

// Unload all music tracks.
music_cleanup :: proc() {
	if music_state.playing && music_state.count > 0 {
		raylib.StopMusicStream(music_state.tracks[music_state.current])
	}
	for i in 0 ..< music_state.count {
		raylib.UnloadMusicStream(music_state.tracks[i])
	}
	music_state = {}
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

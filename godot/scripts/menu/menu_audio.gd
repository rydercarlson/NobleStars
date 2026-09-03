class_name MenuAudio
extends Node
## The web menu's WebAudio SFX engine (web-menu/src/audio.js) rebuilt on
## AudioStreamWAV: every sound is synthesized into a buffer the first time it
## plays, so the menu still ships with zero audio files. Same sound names, same
## shapes — click, back, open, purchase, error, play, hit, reward, tick, found
## — plus the procedural chord-pad music loop.
##
## `main.gd` uses the same engine for the match (see `play_at`), so the combat
## table below is synthesized exactly like the menu's and the game still ships
## no audio files at all. Combat names are prefixed by what they are rather
## than by who plays them — `shot_*`, `melee_*`, `cup_*` — so a new kit picks an
## existing shape off `_attack_sound` instead of needing its own.

const RATE := 22050
## A match is far busier than a menu: a nine-pellet shotgun, its impacts and a
## bot firing across the map can all land inside one frame, and at 8 voices the
## round-robin was cutting sounds off part-way through.
const VOICES := 16

enum Wave { SINE, TRIANGLE, SQUARE, SAW, NOISE }

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _music: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	_music.volume_db = -14.0
	add_child(_music)

func play(sound: String = "click") -> void:
	if not SaveGame.sfx_on:
		return
	var stream: AudioStreamWAV = _stream(sound)
	if stream == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = -6.0
	p.pitch_scale = 1.0   # a voice reused after play_at would keep its pitch
	p.play()

## The match's entry point: same table, but the caller sets the level and the
## pitch. Both matter in a way they never did in a menu — a shot from the far
## corner of the view must not arrive at the level of one under the camera, and
## a burst of identical samples reads as a loop rather than as gunfire, which is
## what the pitch jitter breaks up.
func play_at(sound: String, volume_db: float, pitch := 1.0) -> void:
	if not SaveGame.sfx_on:
		return
	var stream: AudioStreamWAV = _stream(sound)
	if stream == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.1, 4.0)
	p.play()

## The lobby track if one shipped, else the synthesized chord pad. Keeping the
## fallback means the menu still has music in a build without the audio file.
const MUSIC_TRACK := "res://assets/menu/audio/lobby_vibes.mp3"

func set_music(on: bool) -> void:
	if on:
		if not _music.playing:
			var track: AudioStream = null
			if ResourceLoader.exists(MUSIC_TRACK):
				track = load(MUSIC_TRACK) as AudioStream
			if track != null:
				if track is AudioStreamMP3:
					track.loop = true
				_music.volume_db = -11.0
				_music.stream = track
			else:
				_music.volume_db = -14.0
				_music.stream = _stream("music")
			_music.play()
	else:
		_music.stop()

func _stream(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var buf: PackedFloat32Array = _render(sound)
	if buf.is_empty():
		_cache[sound] = null
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var v: int = int(clampf(buf[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	if sound == "music":
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = buf.size()
	_cache[sound] = wav
	return wav

func _render(sound: String) -> PackedFloat32Array:
	match sound:
		"click":
			var b: PackedFloat32Array = _buffer(0.16)
			_tone(b, 0.0, 0.12, 720.0, 380.0, Wave.TRIANGLE, 0.5, 0.004, 0.09)
			_tone(b, 0.0, 0.04, 0.0, 0.0, Wave.NOISE, 0.18, 0.002, 0.03)
			return b
		"back":
			var b: PackedFloat32Array = _buffer(0.2)
			_tone(b, 0.0, 0.16, 420.0, 220.0, Wave.TRIANGLE, 0.5, 0.004, 0.12)
			return b
		"open":
			var b: PackedFloat32Array = _buffer(0.5)
			_tone(b, 0.0, 0.22, 0.0, 0.0, Wave.NOISE, 0.22, 0.02, 0.16)
			_tone(b, 0.08, 0.34, 1046.0, 1046.0, Wave.SINE, 0.3, 0.005, 0.25)
			return b
		"purchase":
			var b: PackedFloat32Array = _buffer(0.5)
			var notes: Array = [880.0, 1174.0, 1568.0]
			for i in notes.size():
				_tone(b, i * 0.07, 0.25, notes[i], notes[i], Wave.SQUARE, 0.16, 0.004, 0.18)
			return b
		"error":
			var b: PackedFloat32Array = _buffer(0.3)
			_tone(b, 0.0, 0.24, 220.0, 160.0, Wave.SAW, 0.24, 0.005, 0.2)
			return b
		"play":
			var b: PackedFloat32Array = _buffer(0.75)
			_tone(b, 0.0, 0.35, 140.0, 70.0, Wave.SAW, 0.5, 0.006, 0.3)
			var rise: Array = [523.0, 659.0, 784.0, 1046.0]
			for i in rise.size():
				_tone(b, 0.05 + i * 0.05, 0.35, rise[i], rise[i], Wave.TRIANGLE, 0.17, 0.005, 0.28)
			return b
		"hit":
			var b: PackedFloat32Array = _buffer(0.3)
			_tone(b, 0.0, 0.25, 180.0, 50.0, Wave.SINE, 0.7, 0.004, 0.2)
			_tone(b, 0.0, 0.08, 0.0, 0.0, Wave.NOISE, 0.24, 0.002, 0.07)
			return b
		"reward":
			var b: PackedFloat32Array = _buffer(0.75)
			var arp: Array = [659.0, 784.0, 988.0, 1318.0, 1568.0]
			for i in arp.size():
				_tone(b, i * 0.06, 0.4, arp[i], arp[i], Wave.SINE, 0.2, 0.004, 0.32)
			return b
		"tick":
			var b: PackedFloat32Array = _buffer(0.06)
			_tone(b, 0.0, 0.05, 1500.0, 1500.0, Wave.SQUARE, 0.09, 0.002, 0.03)
			return b
		"found":
			var b: PackedFloat32Array = _buffer(1.0)
			var fanfare: Array = [[392.0, 0.0], [523.0, 0.12], [659.0, 0.24],
					[784.0, 0.36], [1046.0, 0.5]]
			for n in fanfare:
				_tone(b, n[1], 0.35, n[0], n[0], Wave.SQUARE, 0.15, 0.005, 0.28)
			return b
		"music":
			return _render_music()
	return _render_combat(sound)

# MARK: combat table
#
# Shapes, not instruments. A weapon sound here is a transient (noise), a body
# (a falling sine or triangle) and sometimes a top edge (a square), because that
# is what still reads as an impact through a phone speaker, where everything
# below ~150 Hz is gone. The durations are short on purpose: these fire several
# times a second and a long tail turns a firefight into mush.
func _render_combat(sound: String) -> PackedFloat32Array:
	match sound:
		# -- weapons -------------------------------------------------------
		"shot_shotgun":
			var b: PackedFloat32Array = _buffer(0.3)
			_tone(b, 0.0, 0.10, 0.0, 0.0, Wave.NOISE, 0.34, 0.001, 0.055)
			_tone(b, 0.0, 0.22, 220.0, 70.0, Wave.SINE, 0.5, 0.002, 0.09)
			_tone(b, 0.0, 0.06, 1400.0, 600.0, Wave.SQUARE, 0.1, 0.001, 0.03)
			return b
		"shot_single":
			var b: PackedFloat32Array = _buffer(0.28)
			_tone(b, 0.0, 0.06, 0.0, 0.0, Wave.NOISE, 0.22, 0.001, 0.03)
			_tone(b, 0.0, 0.18, 900.0, 180.0, Wave.SQUARE, 0.26, 0.001, 0.07)
			_tone(b, 0.0, 0.22, 160.0, 60.0, Wave.SINE, 0.4, 0.002, 0.1)
			return b
		"shot_lob":
			var b: PackedFloat32Array = _buffer(0.36)
			_tone(b, 0.0, 0.28, 260.0, 620.0, Wave.TRIANGLE, 0.22, 0.03, 0.16)
			_tone(b, 0.0, 0.16, 0.0, 0.0, Wave.NOISE, 0.1, 0.03, 0.1)
			return b
		"shot_button":
			var b: PackedFloat32Array = _buffer(0.2)
			_tone(b, 0.0, 0.12, 880.0, 1320.0, Wave.SQUARE, 0.16, 0.002, 0.05)
			_tone(b, 0.0, 0.05, 0.0, 0.0, Wave.NOISE, 0.06, 0.001, 0.03)
			return b
		"shot_boomerang":
			var b: PackedFloat32Array = _buffer(0.44)
			# Five clipped pulses climbing in pitch: a spin you can count.
			for i in 5:
				_tone(b, i * 0.055, 0.08, 520.0 + i * 45.0, 700.0 + i * 45.0,
						Wave.TRIANGLE, 0.12, 0.004, 0.04)
			_tone(b, 0.0, 0.3, 300.0, 480.0, Wave.SINE, 0.1, 0.02, 0.2)
			return b
		"shot_sack":
			var b: PackedFloat32Array = _buffer(0.24)
			_tone(b, 0.0, 0.14, 320.0, 120.0, Wave.TRIANGLE, 0.34, 0.002, 0.07)
			_tone(b, 0.0, 0.05, 0.0, 0.0, Wave.NOISE, 0.14, 0.001, 0.03)
			return b
		"shot_curve":
			var b: PackedFloat32Array = _buffer(0.38)
			_tone(b, 0.0, 0.3, 700.0, 1150.0, Wave.SINE, 0.16, 0.03, 0.2)
			_tone(b, 0.0, 0.12, 0.0, 0.0, Wave.NOISE, 0.07, 0.02, 0.08)
			return b
		"melee_swing":
			var b: PackedFloat32Array = _buffer(0.32)
			_tone(b, 0.0, 0.22, 0.0, 0.0, Wave.NOISE, 0.2, 0.05, 0.1)
			_tone(b, 0.0, 0.2, 520.0, 150.0, Wave.TRIANGLE, 0.16, 0.04, 0.1)
			return b
		"shockwave":
			var b: PackedFloat32Array = _buffer(0.58)
			_tone(b, 0.0, 0.45, 120.0, 34.0, Wave.SINE, 0.75, 0.004, 0.22)
			_tone(b, 0.0, 0.22, 0.0, 0.0, Wave.NOISE, 0.24, 0.004, 0.13)
			_tone(b, 0.0, 0.3, 240.0, 60.0, Wave.TRIANGLE, 0.24, 0.006, 0.16)
			return b
		# -- connections ---------------------------------------------------
		"impact":
			var b: PackedFloat32Array = _buffer(0.22)
			_tone(b, 0.0, 0.14, 420.0, 120.0, Wave.TRIANGLE, 0.34, 0.001, 0.055)
			_tone(b, 0.0, 0.05, 0.0, 0.0, Wave.NOISE, 0.16, 0.001, 0.03)
			return b
		"melee_hit":
			var b: PackedFloat32Array = _buffer(0.3)
			_tone(b, 0.0, 0.22, 200.0, 48.0, Wave.SINE, 0.62, 0.002, 0.1)
			_tone(b, 0.0, 0.06, 0.0, 0.0, Wave.NOISE, 0.26, 0.001, 0.04)
			return b
		"box_break":
			var b: PackedFloat32Array = _buffer(0.5)
			_tone(b, 0.0, 0.3, 0.0, 0.0, Wave.NOISE, 0.34, 0.002, 0.14)
			_tone(b, 0.0, 0.26, 300.0, 70.0, Wave.SAW, 0.3, 0.003, 0.13)
			for i in 3:   # splinters falling away after the crack
				_tone(b, 0.06 + i * 0.05, 0.1, 700.0 - i * 120.0, 400.0 - i * 100.0,
						Wave.TRIANGLE, 0.12, 0.002, 0.05)
			return b
		"wall_break":
			var b: PackedFloat32Array = _buffer(0.46)
			_tone(b, 0.0, 0.3, 0.0, 0.0, Wave.NOISE, 0.3, 0.003, 0.15)
			_tone(b, 0.0, 0.25, 180.0, 50.0, Wave.SINE, 0.4, 0.003, 0.12)
			return b
		# -- feedback ------------------------------------------------------
		"super_ready":
			var b: PackedFloat32Array = _buffer(0.7)
			var notes: Array = [523.0, 784.0, 1046.0]
			for i in notes.size():
				_tone(b, i * 0.08, 0.42, notes[i], notes[i], Wave.SINE, 0.22, 0.005, 0.3)
			_tone(b, 0.0, 0.5, 130.0, 260.0, Wave.TRIANGLE, 0.12, 0.05, 0.35)
			return b
		"super_fire":
			var b: PackedFloat32Array = _buffer(0.72)
			_tone(b, 0.0, 0.3, 90.0, 320.0, Wave.SAW, 0.34, 0.02, 0.2)
			_tone(b, 0.06, 0.45, 180.0, 45.0, Wave.SINE, 0.7, 0.004, 0.25)
			_tone(b, 0.0, 0.25, 0.0, 0.0, Wave.NOISE, 0.24, 0.01, 0.16)
			return b
		"elimination":
			var b: PackedFloat32Array = _buffer(0.6)
			_tone(b, 0.0, 0.45, 440.0, 110.0, Wave.SQUARE, 0.22, 0.004, 0.3)
			_tone(b, 0.0, 0.4, 220.0, 55.0, Wave.SINE, 0.4, 0.006, 0.26)
			return b
		"cube_pickup":
			var b: PackedFloat32Array = _buffer(0.36)
			_tone(b, 0.0, 0.22, 1046.0, 1046.0, Wave.SINE, 0.22, 0.003, 0.16)
			_tone(b, 0.05, 0.24, 1568.0, 1568.0, Wave.SINE, 0.18, 0.003, 0.17)
			return b
		"gas_tick":
			var b: PackedFloat32Array = _buffer(0.24)
			_tone(b, 0.0, 0.18, 0.0, 0.0, Wave.NOISE, 0.13, 0.02, 0.1)
			_tone(b, 0.0, 0.12, 300.0, 180.0, Wave.TRIANGLE, 0.08, 0.01, 0.07)
			return b
		"low_health":
			var b: PackedFloat32Array = _buffer(0.5)
			for i in 2:
				_tone(b, i * 0.18, 0.14, 880.0, 880.0, Wave.SQUARE, 0.14, 0.004, 0.08)
			return b
		"reload_tick":
			var b: PackedFloat32Array = _buffer(0.12)
			_tone(b, 0.0, 0.08, 1200.0, 1600.0, Wave.SQUARE, 0.1, 0.002, 0.04)
			return b
		"empty_click":
			var b: PackedFloat32Array = _buffer(0.14)
			_tone(b, 0.0, 0.05, 0.0, 0.0, Wave.NOISE, 0.14, 0.001, 0.025)
			_tone(b, 0.0, 0.06, 300.0, 160.0, Wave.SQUARE, 0.1, 0.001, 0.03)
			return b
		# -- match flow ----------------------------------------------------
		"count_beep":
			var b: PackedFloat32Array = _buffer(0.3)
			_tone(b, 0.0, 0.2, 660.0, 660.0, Wave.SQUARE, 0.18, 0.004, 0.12)
			return b
		"count_go":
			var b: PackedFloat32Array = _buffer(0.7)
			_tone(b, 0.0, 0.4, 1046.0, 1046.0, Wave.SQUARE, 0.24, 0.004, 0.3)
			_tone(b, 0.0, 0.35, 130.0, 65.0, Wave.SAW, 0.4, 0.005, 0.25)
			return b
		"victory":
			var b: PackedFloat32Array = _buffer(1.5)
			var fanfare: Array = [[523.0, 0.0], [659.0, 0.12], [784.0, 0.24],
					[1046.0, 0.36], [1318.0, 0.52]]
			for n in fanfare:
				_tone(b, n[1], 0.5, n[0], n[0], Wave.SQUARE, 0.17, 0.005, 0.4)
			_tone(b, 0.0, 0.9, 130.0, 130.0, Wave.TRIANGLE, 0.16, 0.02, 0.6)
			return b
		"defeat":
			var b: PackedFloat32Array = _buffer(1.3)
			var fall: Array = [[392.0, 0.0], [349.0, 0.18], [294.0, 0.36], [233.0, 0.54]]
			for n in fall:
				_tone(b, n[1], 0.55, n[0], n[0], Wave.TRIANGLE, 0.2, 0.008, 0.45)
			return b
		# -- Nobles Cup ----------------------------------------------------
		"cup_kick":
			var b: PackedFloat32Array = _buffer(0.3)
			_tone(b, 0.0, 0.2, 260.0, 70.0, Wave.SINE, 0.6, 0.002, 0.09)
			_tone(b, 0.0, 0.06, 0.0, 0.0, Wave.NOISE, 0.2, 0.001, 0.035)
			return b
		"cup_goal":
			var b: PackedFloat32Array = _buffer(1.4)
			# Two-tone air horn, the third note late so it reads as a stadium
			# horn rather than as a chord.
			_tone(b, 0.0, 1.0, 392.0, 392.0, Wave.SAW, 0.2, 0.03, 0.9)
			_tone(b, 0.0, 1.0, 523.0, 523.0, Wave.SAW, 0.16, 0.03, 0.9)
			_tone(b, 0.35, 0.85, 659.0, 659.0, Wave.SAW, 0.14, 0.04, 0.8)
			return b
		"cup_whistle":
			var b: PackedFloat32Array = _buffer(0.62)
			_tone(b, 0.0, 0.45, 2200.0, 2350.0, Wave.SINE, 0.16, 0.01, 0.35)
			_tone(b, 0.0, 0.45, 2900.0, 3050.0, Wave.SINE, 0.08, 0.01, 0.3)
			_tone(b, 0.0, 0.12, 0.0, 0.0, Wave.NOISE, 0.06, 0.01, 0.08)
			return b
	return _render("click")

## Slow major-key pad with a pulsing bass — one four-chord loop, then repeat.
func _render_music() -> PackedFloat32Array:
	var chords: Array = [
		[261.6, 329.6, 392.0], [293.7, 349.2, 440.0],
		[329.6, 392.0, 493.9], [349.2, 440.0, 523.3],
	]
	var bar := 2.4
	var b: PackedFloat32Array = _buffer(bar * chords.size())
	for i in chords.size():
		var t0: float = i * bar
		var chord: Array = chords[i]
		for f in chord:
			_tone(b, t0, 2.5, f, f, Wave.SAW, 0.055, 0.4, 1.6)
		for beat in 4:
			_tone(b, t0 + beat * 0.6, 0.35, chord[0] * 0.5, chord[0] * 0.5,
					Wave.SQUARE, 0.09, 0.02, 0.22)
	return b

func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	b.fill(0.0)
	return b

## One voice mixed into buf: freq glides f0 -> f1, amplitude attacks then decays.
func _tone(buf: PackedFloat32Array, start: float, dur: float, f0: float,
		f1: float, wave: int, amp: float, attack: float, decay: float) -> void:
	var i0: int = int(start * RATE)
	var n: int = int(dur * RATE)
	var phase: float = 0.0
	for i in n:
		var idx: int = i0 + i
		if idx < 0 or idx >= buf.size():
			continue
		var t: float = float(i) / RATE
		var k: float = t / maxf(dur, 0.0001)
		var freq: float = f0 * pow(maxf(f1, 1.0) / maxf(f0, 1.0), k) if f0 > 0.0 else 0.0
		phase += TAU * freq / RATE
		var s: float = 0.0
		match wave:
			Wave.SINE:
				s = sin(phase)
			Wave.TRIANGLE:
				s = asin(sin(phase)) * 0.6366
			Wave.SQUARE:
				s = 1.0 if sin(phase) >= 0.0 else -1.0
			Wave.SAW:
				s = fmod(phase / TAU, 1.0) * 2.0 - 1.0
			Wave.NOISE:
				s = randf() * 2.0 - 1.0
		var env: float = 1.0
		if t < attack:
			env = t / maxf(attack, 0.0001)
		else:
			env = exp(-(t - attack) / maxf(decay, 0.0001) * 2.5)
		buf[idx] = buf[idx] + s * amp * env

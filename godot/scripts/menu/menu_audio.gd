class_name MenuAudio
extends Node
## The web menu's WebAudio SFX engine (web-menu/src/audio.js) rebuilt on
## AudioStreamWAV: every sound is synthesized into a buffer the first time it
## plays, so the menu still ships with zero audio files. Same sound names, same
## shapes — click, back, open, purchase, error, play, hit, reward, tick, found
## — plus the procedural chord-pad music loop.

const RATE := 22050
const VOICES := 8

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
	p.play()

func set_music(on: bool) -> void:
	if on:
		if not _music.playing:
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

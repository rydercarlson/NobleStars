class_name Haptics
## Phone haptics: one call per game event, mapped through the vocabulary below
## to a short SCORE — a handful of timed segments — played out over the next
## tenth of a second or two. Static, because `Input.vibrate_handheld` is global
## and there is nothing per-scene to own: `main.gd`, `cup_mode.gd` and the menu
## all call `Haptics.fire()` directly, the same way they all call `SaveGame`.
##
## ## Why a score and not a single buzz
##
## **Godot's iOS backend emits exactly one thing.** `Input.vibrate_handheld`
## reaches `AppleEmbedded::vibrate_haptic_engine`
## (`drivers/apple_embedded/apple_embedded.mm`), which builds a Core Haptics
## pattern holding a single `CHHapticEventTypeHapticContinuous` event with only
## `HapticIntensity` set — never `CHHapticEventTypeHapticTransient`, never
## `HapticSharpness`. The engine can therefore express duration and strength and
## nothing else, so a table of fourteen duration/amplitude pairs is fourteen
## lengths of ONE sensation. That, not the contents of the table, is why the
## first pass read as undifferentiated: a menu tap and a goal had the same
## texture because there is only one texture.
##
## Core Haptics does mix concurrent players, though, and GDScript can schedule
## calls. So the missing axis is bought back as **rhythm**: a hard 20 ms segment
## followed by a soft 60 ms one reads as an impact where one 80 ms block reads
## as a hum, and a goal is three rising thumps rather than a longer buzz. Every
## shape in SCORES is built out of that one idea, because it is the only
## expressive axis this API has. The real fix — transient events and a sharpness
## parameter — needs a native plugin, and is written up in todo.md.
##
## The cost is worth stating: the queue drains in `_process`, so a segment's
## start carries up to a frame of jitter — measured over a full Nobles Cup
## match, 36 tail segments landed 0-8 ms late with a median of 4, and on a phone
## held to 60 fps the ceiling is a frame, ~16 ms. Nothing here places two
## segments closer than about 40 ms, because below that the jitter IS the
## pattern.
##
## ## Three device classes, not two
##
## The old code gated on `OS.has_feature("mobile")`, which is also true on an
## iPad — a device with no haptic engine at all. The real probe is on the
## `AppleEmbedded` singleton, which binds `supports_haptic_engine()` into
## ClassDB, so `_device()` can tell a Taptic iPhone from a fallback device from
## a desktop and the vocabulary no longer has to be designed for the worst of
## the three. That matters because the FALLBACK path
## (`AudioServicesPlaySystemSound`) ignores both duration and amplitude and
## always fires the same ~0.4 s buzz — a real constraint, but one this build
## never meets, since it side-loads onto a modern iPhone.
##
## ## Priority, not just spacing
##
## The old throttle was purely temporal: anything inside `MIN_GAP` of the last
## tap was dropped, first-come-first-served, so a menu tap could swallow a
## death. Concretely: the killing blow fires `hit` from the health watch in
## `main.gd:_update_status` and `death` fires from `_eliminate` in the same
## frame, and which one survived depended on frame ordering rather than on which
## mattered. Every entry now carries a `Tier`, and a higher tier preempts a
## lower one — clearing whatever is still queued — instead of losing to it.
##
## Haptics are **invisible on the desktop this is developed on**, so there are
## two instruments. `NS3_HAPTIC_LOG=1` prints every tap as it fires with its
## score and the gap since the last, and prints the drops too, which is how you
## tell a throttle from a missing hook. `NS3_HAPTIC_AUDIO=1` renders each score
## as a low tone burst through a plain AudioStreamPlayer, so the RHYTHM — the
## only thing being designed here — can be judged without an install per change.
## `NS3_HAPTIC_DEMO=<name>` loops one entry, for tuning on the device itself.

## What the phone under this build can actually do.
enum Device {
	NONE,     ## desktop, or anything else that cannot vibrate
	BUZZ,     ## a handheld with no haptic engine: every tap is a fixed ~0.4s buzz
	TAPTIC,   ## Core Haptics: duration and amplitude are both real
}

## Which taps get to interrupt which. A higher tier preempts a lower one and
## clears whatever it had queued; an equal or lower one is dropped.
## The axis is WHAT HAPPENED IN THE MATCH, not what it cost you — which is why
## firing your Super is an EVENT and the elimination it produced is a CEREMONY,
## even though the Super is the more expensive of the two. The kill is the thing
## you cannot see coming; the Super you pressed yourself. Ranking them the other
## way round measurably ate the elimination, since a Super that kills lands both
## inside 160 ms.
enum Tier {
	PICKUP,     ## incidental, and the first thing to lose: a cube, a pip, a menu press
	EVENT,      ## what you did: damage, a connect, the Super, a kick
	CEREMONY,   ## the match turning: GO, a goal, an elimination, your death
	MATCH,      ## the match ending, which outranks anything that happened inside it
}

## name -> [[offset ms, duration ms, amplitude 0..1], ...]. Offsets are from the
## start of the score. The rules the shapes follow, since they look arbitrary
## written out: a leading edge is what makes something read as an impact rather
## than a hum, so the loud segment goes FIRST and short; separate beats are
## never closer than ~40 ms, because the frame quantisation eats anything
## tighter; and the pickup tier is a single segment, so it can never compete
## with something that matters.
const SCORES := {
	# --- PICKUP. The floor. One segment, quiet, over before you notice it. ---
	"ui_tap":       [[0, 14, 0.32]],
	"cube":         [[0, 12, 0.34]],
	"ball_get":     [[0, 14, 0.38]],
	# The aim stick's detent, both ways across TAP_THRESHOLD. The lightest pair
	# in the vocabulary, because they fire while you are aiming rather than when
	# something happens, and asymmetric on purpose: sliding OFF centre commits
	# the stick to a manual lane and sliding back on hands it to the auto-aim,
	# so the commit is the firmer of the two. Both sit under BUZZ_MIN_AMP, which
	# means a fallback device never gets them at all — correct, since a 0.4 s
	# buzz every time a thumb crosses a line is unusable.
	"aim_on":       [[0, 10, 0.30]],
	"aim_off":      [[0, 8, 0.20]],
	# Not every pip returning — only the one that takes you from empty to able
	# to shoot again. That is the state change you would otherwise have to look
	# at the screen for; the other three pips you can wait for.
	"ammo_ready":   [[0, 12, 0.26]],

	# --- EVENT. The fight. ---
	"ui_reward":    [[0, 16, 0.50], [70, 34, 0.78]],
	# Two identical flat ticks: deliberately the only shape here that does not
	# rise or fall, because it is the one that means "nothing happened".
	"empty":        [[0, 10, 0.22], [60, 10, 0.22]],
	"kick":         [[0, 20, 0.60], [22, 34, 0.30]],
	# The same launch-and-decay as a Super, because that is what it is: the
	# ball leaves at twice the speed and the Super is spent doing it.
	"super_shot":   [[0, 26, 1.00], [30, 46, 0.58], [80, 70, 0.30]],
	# The bar filling is the only cue you get that the Super is up without
	# looking away from the fight, so it is the one entry that earns a full
	# three-beat rise on argument alone.
	"super_ready":  [[0, 14, 0.42], [60, 20, 0.68], [125, 30, 0.92]],
	"count_beep":   [[0, 14, 0.34]],

	# --- CEREMONY. Only these are allowed to be long. ---
	"count_go":     [[0, 24, 0.78], [40, 60, 0.95]],
	"elimination":  [[0, 20, 0.78], [55, 44, 0.92]],
	"death":        [[0, 34, 1.00], [44, 90, 0.62], [150, 130, 0.30]],
	"goal_for":     [[0, 22, 0.70], [78, 26, 0.86], [165, 70, 1.00]],
	# Conceding is one dull segment that neither rises nor resolves. Scoring and
	# conceding must not be the same event at different volumes.
	"goal_against": [[0, 74, 0.38]],
	"victory":      [[0, 18, 0.58], [70, 18, 0.74], [140, 18, 0.88], [210, 80, 1.00]],
	"defeat":       [[0, 50, 0.70], [115, 95, 0.34]],
}

## Anything not named here is EVENT.
const TIERS := {
	"ui_tap": Tier.PICKUP, "cube": Tier.PICKUP, "ball_get": Tier.PICKUP,
	"ammo_ready": Tier.PICKUP, "aim_on": Tier.PICKUP, "aim_off": Tier.PICKUP,
	"count_go": Tier.CEREMONY, "elimination": Tier.CEREMONY, "death": Tier.CEREMONY,
	"goal_for": Tier.CEREMONY, "goal_against": Tier.CEREMONY,
	# Above the rest, because the match ending lands in the SAME FRAME as the
	# elimination that ended it. At an equal tier the win would be swallowed by
	# the kill that won it, which is the exact failure the tiers exist to stop.
	"victory": Tier.MATCH, "defeat": Tier.MATCH,
}

## Where the damage curve starts and where it saturates, as a fraction of max
## health. MEASURED, not picked, and re-measured after the first pass got it
## wrong: over full matches with NS3_HAPTIC_LOG on, damage dealt runs 8–28% of
## the target's max with a median of 14%, a gas tick is a flat 17%, and a
## fighter's shot lands for 9–29% depending on the kit and the range. So
## essentially everything that ever happens lives between 6% and a third, and
## the first pass at 0.05–0.45 spent over half the amplitude range on damage
## that does not occur — every real hit came out between 0.36 and 0.61 of a
## scale that runs to 0.98. The band below is the band the game actually plays
## in, which puts a gas tick mid-scale and a solid shot near the top.
##
## The old code had a single 0.22 threshold here and two fixed entries either
## side of it. The fraction is a real number the game already computes, and
## throwing it away to keep a binary was the second-biggest thing wrong with
## the first table.
const HIT_SOFT := 0.06
const HIT_HARD := 0.34

## A `landed` tap never reaches what a `hit` tap reaches at the same fraction.
## What is happening TO you always has to outweigh what you are doing to
## somebody else, or a firefight is two indistinguishable streams.
const LANDED_QUIET := 0.28
const LANDED_LOUD := 0.62

## On a fallback device every tap is the same fixed buzz whatever it asks for,
## so a score is meaningless there and a quiet score is worse than nothing:
## `ui_tap` would arrive as a 0.4 s buzz on every menu press. BUZZ therefore
## fires only scores that peak at or above this, collapsed to one segment.
##
## The effect on damage is worth knowing, since it is the entry that fires most:
## against the curve below, a `hit` reaches 0.6 at about 18% of max health, so a
## fallback device feels roughly what the old `HEAVY_FRACTION` binary let
## through and nothing else. That is not an exact match for the old 0.22 and is
## not meant to be — that threshold was measured against a different shape —
## but it lands in the same neighbourhood, which is the sanity check.
const BUZZ_MIN_AMP := 0.60

## Nothing fires twice inside this, whatever it is — unless it outranks what
## fired last, which is the whole point of the tier. TAPTIC can afford a short
## floor because its taps are short; a fallback device cannot, because two of
## its 0.4 s buzzes inside 0.4 s are one long buzz.
const MIN_GAP := {Device.TAPTIC: 0.05, Device.BUZZ: 0.40, Device.NONE: 0.05}

## Taps that arrive as a STREAM rather than as an event get their own floor on
## top of MIN_GAP, keyed by name. A gas burn ticks about twice a second for as
## long as you stand in it, a sustained magazine lands two to five connects a
## second, and a contested ball changes hands repeatedly — at the global floor
## all three come through as a rattle, which reads as a fault, not as feedback.
const REPEAT_GAP := {
	"hit": 0.22,
	"landed": 0.16,
	"ball_get": 0.50,
	"ammo_ready": 0.60,
	# Far longer than the SOUND's own 0.3 s gate, deliberately. Held fire on a
	# dry magazine clicks two and a half times a second, which is fine to hear
	# and a rattle to feel — measured over a match, that gate alone produced
	# three or four taps per dry spell. A dry spell is worth one tap, and the
	# pip coming back is worth the other: `empty` then `ammo_ready` is the pair.
	"empty": 1.20,
	"count_beep": 0.40,
	"kick": 0.20,
	# The backstop under the detent's dwell in main.gd. A thumb parked exactly
	# on the threshold is the one input that can cross it over and over, and the
	# dwell only rejects crossings that do not hold — a deliberate wiggle still
	# gets through, so the rate is capped here as well.
	"aim_on": 0.25,
	"aim_off": 0.25,
}

## How long a Super that carries the fighter somewhere rumbles for after the
## launch thump. A dash is the one thing in the game a continuous-only API is
## actually the right tool for, so it gets a bed instead of a second beat.
const RIDE_BED := [[0, 26, 1.00], [30, 55, 0.50], [90, 220, 0.26]]
const SUPER_HIT := [[0, 26, 1.00], [30, 46, 0.55], [80, 60, 0.28]]

const DEMO_GAP := 1.2

static var _device_cache := -1
static var _pump: Node = null
## [[due seconds, duration ms, amplitude], ...] — the tail of the score in flight.
static var _queue: Array = []
static var _playing_tier := -1
static var _playing_until := 0.0
static var _last_at := -1.0
static var _last_tier := -1
static var _last_by_name: Dictionary = {}
static var _log := OS.get_environment("NS3_HAPTIC_LOG") != ""
static var _audio := OS.get_environment("NS3_HAPTIC_AUDIO") != ""
static var _demo := OS.get_environment("NS3_HAPTIC_DEMO")

# MARK: the calls

## One tap by name. Unknown names warn rather than falling through to a default,
## unlike `MenuAudio._render` — a haptic you cannot hear has no "close enough".
static func fire(tap: String, note: String = "") -> void:
	var score: Array = SCORES.get(tap, [])
	if score.is_empty():
		push_warning("Haptics: no entry for '%s'" % tap)
		return
	_play(tap, score, int(TIERS.get(tap, Tier.EVENT)), note)

## Damage TAKEN, scaled continuously by how much of your health one frame took.
## Kept here rather than at the call site so the curve lives beside the two
## constants that shape it. Reads a FRAME, not a pellet: the health watch in
## main.gd compares frame to frame, so a nine-pellet shotgun arrives as one
## exchange rather than as nine taps.
static func hit(amount: float, max_health: float) -> void:
	var frac: float = amount / maxf(1.0, max_health)
	var k: float = smoothstep(HIT_SOFT, HIT_HARD, frac)
	# Loud and short first, soft and long behind it. One 80 ms block at the same
	# energy reads as a hum; the leading edge is the whole of what makes this an
	# impact, and it is the only impact cue this API can produce.
	var lead_ms: int = int(lerpf(14.0, 28.0, k))
	var lead_amp: float = lerpf(0.34, 0.98, k)
	var score: Array = [
		[0, lead_ms, lead_amp],
		[lead_ms + 4, int(lerpf(24.0, 80.0, k)), lead_amp * 0.42],
	]
	_play("hit", score, Tier.EVENT,
			"%.0f dmg, %.0f%% of max" % [amount, frac * 100.0])

## Damage DEALT — your shot arriving on somebody. The single biggest gap in the
## first pass: you felt what was done to you and never what you did, which in a
## shooter is the one thing you genuinely cannot read off the screen mid-fight.
##
## Deliberately a different RHYTHM and not merely a quieter `hit`: two short
## even ticks against that shape's thump-and-tail. Since rhythm is the only
## texture this API has, two things that must never be confused in a firefight
## have to differ in it rather than in level.
static func landed(amount: float, max_health: float) -> void:
	var frac: float = amount / maxf(1.0, max_health)
	var k: float = smoothstep(HIT_SOFT, HIT_HARD, frac)
	var amp: float = lerpf(LANDED_QUIET, LANDED_LOUD, k)
	_play("landed", [[0, 11, amp], [46, 13, amp * 1.1]], Tier.EVENT,
			"%.0f dmg, %.0f%% of their max" % [amount, frac * 100.0])

## Your Super going off. A Super that carries you somewhere gets a launch thump
## and then a bed under the ride; everything else gets a thump and a decay.
static func super_fired(style: int) -> void:
	var ride: bool = _is_ride(style)
	_play("super_fire", RIDE_BED if ride else SUPER_HIT, Tier.EVENT,
			"ride" if ride else "hit")

## The styles that carry the fighter somewhere rather than sending something at
## somebody. A function rather than a const array of `Kits.Style` members, since
## a const initialised from another script is exactly the cross-script inference
## GDScript is unreliable about.
static func _is_ride(style: int) -> bool:
	return style == Kits.Style.DASH or style == Kits.Style.JUMP_SMASH \
			or style == Kits.Style.POP_OFF or style == Kits.Style.DOWNHILL

# MARK: the engine

## Handhelds only, and only ones that can actually do something. Kept as the
## public name because CLAUDE.md documents it.
static func supported() -> bool:
	return _device() != Device.NONE

## What the phone under this build can do, probed once. `OS.has_feature`
## separates handheld from desktop and nothing more — an iPad answers true and
## has no haptic engine — so the second half asks the platform singleton, which
## binds `supports_haptic_engine()` into ClassDB on every Apple embedded target.
## Android reaches BUZZ and stays there: `createOneShot` does honour amplitude,
## but this game ships iOS, and guessing generously about a platform nobody has
## run is how a table gets tuned for a device that does not exist.
static func _device() -> int:
	if _device_cache >= 0:
		return _device_cache
	_device_cache = Device.NONE
	if OS.has_feature("mobile"):
		_device_cache = Device.BUZZ
		var apple: Object = _apple()
		if apple != null and apple.has_method("supports_haptic_engine"):
			if bool(apple.call("supports_haptic_engine")):
				_device_cache = Device.TAPTIC
	return _device_cache

## The platform singleton, under either name it has had. 4.6 renamed the iOS
## singleton to `AppleEmbedded` when the driver moved to `drivers/apple_embedded`;
## older templates still register `iOS`.
static func _apple() -> Object:
	for name in ["AppleEmbedded", "iOS"]:
		if Engine.has_singleton(name):
			return Engine.get_singleton(name)
	return null

## Spin the haptic engine up ahead of the first tap. Godot creates it with
## `setAutoShutdownEnabled:true`, so it idles down between taps — and a Showdown
## lull is easily ten seconds, which means the taps that matter most (the first
## hit taken, the Super filling) are exactly the ones that pay the start-up cost
## and arrive late. Called at match start and on entering the menu.
static func warm() -> void:
	_ensure_pump()
	var apple: Object = _apple()
	if apple != null and apple.has_method("start_haptic_engine"):
		apple.call("start_haptic_engine")

## Let it go again. Wired to the app being backgrounded rather than called by
## hand — a match does not have a moment where haptics are finished with.
static func cool() -> void:
	_queue.clear()
	_playing_tier = -1
	_playing_until = 0.0
	var apple: Object = _apple()
	if apple != null and apple.has_method("stop_haptic_engine"):
		apple.call("stop_haptic_engine")

# MARK: playback

static func _play(name: String, score: Array, tier: int, note: String) -> void:
	if not SaveGame.haptics_on or score.is_empty():
		return
	var device: int = _device()
	var at: float = Time.get_ticks_msec() / 1000.0

	var own: float = float(REPEAT_GAP.get(name, 0.0))
	if own > 0.0 and at - float(_last_by_name.get(name, -999.0)) < own:
		_drop(name, "repeat")
		return
	# A score still in flight owns the actuator: interleaving a second shape
	# into one that is halfway through does not read as two taps, it reads as
	# one wrong one. Only a strictly higher tier takes it over, and when it does
	# it clears the rest rather than queueing behind it.
	if at < _playing_until and tier <= _playing_tier:
		_drop(name, "busy")
		return
	# The global floor, which a higher tier is likewise allowed through. This is
	# the line the old code did not have, and the reason a menu tap could
	# swallow a death.
	if at - _last_at < float(MIN_GAP[device]) and tier <= _last_tier:
		_drop(name, "gap")
		return

	var play: Array = score if device != Device.BUZZ else _collapse(score)
	if play.is_empty():
		_drop(name, "buzz-quiet")
		return

	_queue.clear()
	var span: float = 0.0
	for seg: Array in play:
		span = maxf(span, (float(seg[0]) + float(seg[1])) / 1000.0)
	var gap: float = at - _last_at if _last_at >= 0.0 else 0.0
	_playing_tier = tier
	_playing_until = at + span
	_last_at = at
	_last_tier = tier
	_last_by_name[name] = at

	if _log:
		print("[haptic] %-12s %-8s %-34s +%.2fs  %s"
				% [name, Tier.keys()[tier].to_lower(), _print_score(play), gap, note])
	if _audio:
		_ensure_pump()
		if _pump != null and _pump.has_method("audition"):
			_pump.call("audition", play)

	# The head of the score goes out on this frame; the tail is queued, because
	# there is no way to ask Core Haptics for a pattern through this API — only
	# for one event at a time.
	_emit(int(play[0][1]), float(play[0][2]))
	if play.size() > 1:
		_ensure_pump()
		for i in range(1, play.size()):
			var seg: Array = play[i]
			_queue.append([at + float(seg[0]) / 1000.0, int(seg[1]), float(seg[2])])

## Called every frame by the pump. Anything due goes out; a segment that missed
## its slot by a frame still fires rather than being skipped, since dropping the
## tail of a shape is worse than delivering it a frame late.
static func _drain() -> void:
	if _queue.is_empty():
		return
	var at: float = Time.get_ticks_msec() / 1000.0
	while not _queue.is_empty() and float(_queue[0][0]) <= at:
		var seg: Array = _queue.pop_front()
		_emit(int(seg[1]), float(seg[2]))

static func _emit(duration_ms: int, amplitude: float) -> void:
	if _device() == Device.NONE:
		return
	Input.vibrate_handheld(duration_ms, clampf(amplitude, 0.0, 1.0))

## A fallback device answers every request with the same fixed buzz, so a score
## has to become the ONE segment that best represents it — the loudest — and a
## score with no loud segment has to become nothing at all.
static func _collapse(score: Array) -> Array:
	var best: Array = []
	for seg: Array in score:
		if best.is_empty() or float(seg[2]) > float(best[2]):
			best = seg
	if best.is_empty() or float(best[2]) < BUZZ_MIN_AMP:
		return []
	return [[0, int(best[1]), float(best[2])]]

static func _drop(name: String, why: String) -> void:
	if _log:
		print("[haptic] %-12s dropped (%s)" % [name, why])

static func _print_score(score: Array) -> String:
	var parts: PackedStringArray = []
	for seg: Array in score:
		parts.append("%d:%dms@%.2f" % [int(seg[0]), int(seg[1]), float(seg[2])])
	return "[" + ", ".join(parts) + "]"

## The queue needs a frame signal and nothing in this file has one, so a single
## hidden node is parked on the scene root — under the root rather than under a
## scene, so it survives the match/menu swap the way an autoload would without
## having to become one and rename every call site.
static func _ensure_pump() -> void:
	if _pump != null and is_instance_valid(_pump):
		return
	var loop: MainLoop = Engine.get_main_loop()
	if not loop is SceneTree:
		return
	_pump = Pump.new()
	_pump.name = "HapticsPump"
	# Deferred because the commonest caller is a signal or a physics callback,
	# and the root is busy setting up children at both.
	(loop as SceneTree).root.add_child.call_deferred(_pump)

# MARK: the pump

class Pump extends Node:
	## Auditioning a score as sound. Haptics cannot be felt on a desktop at all,
	## and the thing being designed here is rhythm — which survives the
	## translation to a low tone burst perfectly well. Without this every change
	## to a shape costs a device install, which is how the first pass ended up
	## with fourteen numbers nobody had ever compared.
	const RATE := 8000
	const HZ := 120.0

	var _voice: AudioStreamPlayer
	var _demo_at := 0.0

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		Haptics._drain()
		if Haptics._demo == "":
			return
		var at: float = Time.get_ticks_msec() / 1000.0
		if at - _demo_at < Haptics.DEMO_GAP:
			return
		_demo_at = at
		Haptics.fire(Haptics._demo, "demo")

	func _notification(what: int) -> void:
		# The engine is stopped rather than left running behind a backgrounded
		# app, and the queue is dropped so a shape interrupted by the home
		# button does not finish itself off on the way back in.
		if what == NOTIFICATION_APPLICATION_PAUSED:
			Haptics.cool()

	func audition(score: Array) -> void:
		if _voice == null:
			_voice = AudioStreamPlayer.new()
			_voice.bus = "Master"
			add_child(_voice)
		var end_ms: float = 0.0
		for seg: Array in score:
			end_ms = maxf(end_ms, float(seg[0]) + float(seg[1]))
		var frames: int = int((end_ms + 40.0) / 1000.0 * RATE)
		if frames <= 0:
			return
		var buf: PackedFloat32Array = PackedFloat32Array()
		buf.resize(frames)
		buf.fill(0.0)
		for seg: Array in score:
			var start: int = int(float(seg[0]) / 1000.0 * RATE)
			var count: int = maxi(1, int(float(seg[1]) / 1000.0 * RATE))
			for i in count:
				var t: float = float(i) / RATE
				# 2 ms attack and 6 ms release, so even a 10 ms segment reads as
				# a tick rather than as a click of the buffer starting.
				var env: float = minf(minf(1.0, t / 0.002),
						minf(1.0, float(count - i) / RATE / 0.006))
				var j: int = start + i
				if j < frames:
					buf[j] += sin(TAU * HZ * t) * float(seg[2]) * env
		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(frames * 2)
		for i in frames:
			bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
		var wav: AudioStreamWAV = AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = RATE
		wav.stereo = false
		wav.data = bytes
		_voice.stream = wav
		_voice.play()

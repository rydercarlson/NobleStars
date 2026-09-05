class_name Haptics
## Phone haptics: one call per game event, mapped through the table below to a
## duration and an intensity. Static, because `Input.vibrate_handheld` is global
## and there is nothing per-scene to own — `main.gd`, `cup_mode.gd` and the menu
## all call `Haptics.fire()` directly, the same way they all call `SaveGame`.
##
## **Godot routes this through Core Haptics on iOS 13+**, which honours both the
## duration and the amplitude. Anything older falls back to
## `AudioServicesPlaySystemSound`, which ignores both and always fires the same
## ~0.4s buzz. That fallback is the real reason this table is short and hard
## throttled: every entry has to still be tolerable when it arrives as a fixed
## buzz, so nothing here fires per pellet, per frame, or per bot. The rule the
## table follows is that a tap marks a change of state you would otherwise have
## to look at the screen to notice — not every event that makes a sound.
##
## Haptics are **invisible on the desktop this is developed on**, so
## `NS3_HAPTIC_LOG=1` prints every tap as it fires with the gap since the last
## one. That is the same instrument as `NS3_SFX_LOG` and exists for the same
## reason: without it there is no way to tell "the hook never ran" from "the
## phone was in your pocket". It prints on desktop too, where nothing can be
## felt, which is the point — it reports what a phone WOULD have done.

## name -> [duration in ms, amplitude 0..1].
const TAPS := {
	# The menu. By far the most-fired entry, so it is the lightest thing here.
	"ui_tap": [12, 0.30],
	"ui_reward": [45, 0.65],

	# Taking damage, as two steps rather than a scale: the fallback devices
	# cannot express a scale, and at speed you cannot feel one either.
	"hit_taken": [18, 0.45],
	"hit_heavy": [45, 0.80],

	# Your Super, both halves. The bar filling is the only cue you get that it
	# is available without looking away from the fight, which makes it the one
	# tap that earns its place on argument alone.
	"super_ready": [40, 0.60],
	"super_fire": [70, 0.90],

	# Match events. Only ever your own — a bot dying across the map is a sound,
	# not something your hand should know about.
	"cube": [14, 0.35],
	"elimination": [55, 0.75],
	"death": [150, 1.00],
	"count_go": [50, 0.70],

	# Nobles Cup. Scoring is the loudest thing that happens in the game and
	# conceding deliberately does not feel like it.
	"goal_for": [180, 1.00],
	"goal_against": [70, 0.45],
	"ball_get": [20, 0.40],
}

## How much of your health one frame has to take to be the heavy tap, MEASURED
## rather than picked: with NS3_HAPTIC_LOG over full matches, a bot's shot
## landing on you is 29% of max health and a gas tick is 17%, so 0.22 is the
## only place a threshold can sit and still mean anything. The first pass at
## 0.12 classified every single hit as heavy, gas included, which is the same as
## having one entry. Late gas ramps past it and starts to thump, which is honest.
##
## It reads a FRAME, not a pellet: the health watch in main.gd compares
## frame to frame, so a nine-pellet shotgun arrives as one exchange.
const HEAVY_FRACTION := 0.22

## Nothing fires twice inside this, whatever it is. The floor is set by the
## fallback devices, where two taps in quick succession simply run into each
## other and read as one long buzz.
const MIN_GAP := 0.09

## Taps that can arrive as a STREAM rather than as an event get their own floor
## on top of MIN_GAP. A gas burn ticks about twice a second for as long as you
## stand in it and a contested ball changes hands repeatedly — at MIN_GAP both
## come through as a rattle, which reads as a fault rather than as feedback.
const REPEAT_GAP := {
	"hit_taken": 0.30,
	"hit_heavy": 0.30,
	"ball_get": 0.50,
}

static var _last_at := -1.0
static var _last_by_name: Dictionary = {}
static var _log := OS.get_environment("NS3_HAPTIC_LOG") != ""

## One tap by name. Unknown names warn rather than falling through to a default,
## unlike `MenuAudio._render` — a haptic you cannot hear has no "close enough".
static func fire(tap: String, note: String = "") -> void:
	if not SaveGame.haptics_on:
		return
	var spec: Array = TAPS.get(tap, [])
	if spec.is_empty():
		push_warning("Haptics: no entry for '%s'" % tap)
		return
	var at: float = Time.get_ticks_msec() / 1000.0
	var own: float = REPEAT_GAP.get(tap, 0.0)
	if own > 0.0 and at - float(_last_by_name.get(tap, -999.0)) < own:
		return
	if at - _last_at < MIN_GAP:
		return
	var gap: float = at - _last_at if _last_at >= 0.0 else 0.0
	_last_at = at
	_last_by_name[tap] = at
	if _log:
		print("[haptic] %-13s %3d ms  %.2f   +%.2fs  %s"
				% [tap, int(spec[0]), float(spec[1]), gap, note])
	if not supported():
		return
	Input.vibrate_handheld(int(spec[0]), float(spec[1]))

## Handhelds only. Desktop Godot's `vibrate_handheld` is already a no-op, but
## gating explicitly keeps the intent readable and stops a future platform
## quietly buzzing a laptop.
static func supported() -> bool:
	return OS.has_feature("mobile")

## The damage tap for a hit of `amount` on a fighter with `max_health`. Kept
## here rather than at the call site so the threshold lives beside the two
## entries it chooses between.
static func hit(amount: float, max_health: float) -> void:
	# The fraction goes into the log because HEAVY_FRACTION is the one number
	# here that cannot be reasoned to — it has to be read off real matches, and
	# a first pass at 0.12 turned out to classify EVERY hit as heavy.
	var frac: float = amount / maxf(1.0, max_health)
	fire("hit_heavy" if frac >= HEAVY_FRACTION else "hit_taken",
			"%.0f dmg, %.0f%% of max" % [amount, frac * 100.0])

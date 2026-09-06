extends SceneTree
## Verifies the join-code codec round-trips, in the engine that ships it.
## The seven-character width multiplies a 35-bit number by a 35-bit constant,
## which is the one place GDScript's 64-bit ints could silently wrap — so this
## is checked here rather than trusted from a scratch script in another language.
##
##   Godot --path godot --headless --script res://tools/code_probe.gd
##
## The script is preloaded rather than reached through the `Net` autoload:
## autoloads are not registered when Godot is run with --script, so the
## singleton's name does not resolve here. The codec is static for this reason
## among others; `local_ip()` is not, hence the bare instance below (never added
## to the tree, so its _ready never runs and no multiplayer signal is touched).
const NetPlay = preload("res://scripts/net_play.gd")

func _init() -> void:
	var bad := 0
	var checked := 0
	# Exhaustive over every 192.168.* address: the common case, and the only
	# width small enough to enumerate completely.
	for a in 256:
		for b in 256:
			var ip := "192.168.%d.%d" % [a, b]
			checked += 1
			if NetPlay.code_to_ip(NetPlay.ip_to_code(ip)) != ip:
				bad += 1
				if bad < 5:
					print("  MISMATCH %s -> %s -> %s" % [ip, NetPlay.ip_to_code(ip),
							NetPlay.code_to_ip(NetPlay.ip_to_code(ip))])
	print("192.168.*      exhaustive: %d checked, %d bad" % [checked, bad])

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260906
	var families := {"10.*": 0, "172.16-31.*": 0, "public": 0}
	var fam_bad := {"10.*": 0, "172.16-31.*": 0, "public": 0}
	for _i in 60000:
		var kind: String = ["10.*", "172.16-31.*", "public"][rng.randi() % 3]
		var ip := ""
		match kind:
			"10.*":
				ip = "10.%d.%d.%d" % [rng.randi() % 256, rng.randi() % 256, rng.randi() % 256]
			"172.16-31.*":
				ip = "172.%d.%d.%d" % [16 + rng.randi() % 16, rng.randi() % 256, rng.randi() % 256]
			_:
				# Anything that is not one of the encoded private ranges.
				ip = "%d.%d.%d.%d" % [128 + rng.randi() % 60, rng.randi() % 256,
						rng.randi() % 256, rng.randi() % 256]
		families[kind] += 1
		if NetPlay.code_to_ip(NetPlay.ip_to_code(ip)) != ip:
			fam_bad[kind] += 1
			if fam_bad[kind] < 3:
				print("  MISMATCH %s -> %s -> %s" % [ip, NetPlay.ip_to_code(ip),
						NetPlay.code_to_ip(NetPlay.ip_to_code(ip))])
	for kind in families:
		print("%-14s random   : %d checked, %d bad" % [kind, families[kind], fam_bad[kind]])

	# A mistyped code must decode to nothing rather than to a stranger's machine.
	for width in [4, 5, 7]:
		var rejected := 0
		for _i in 20000:
			var s := ""
			for _c in width:
				s += NetPlay.CODE_ALPHABET[rng.randi() % 32]
			if NetPlay.code_to_ip(s) == "":
				rejected += 1
		print("%d-char random string rejected: %.1f%%" % [width, rejected / 200.0])

	print("worked examples:")
	for ip in ["192.168.1.24", "10.24.5.31", "172.16.3.9", "128.114.55.2", "10.0.0.1"]:
		print("  %-16s -> %s" % [ip, NetPlay.ip_to_code(ip)])
	var probe: Node = NetPlay.new()
	print("this machine: ip=%s code=%s" % [probe.local_ip(), probe.join_code()])
	probe.free()
	quit(1 if bad > 0 else 0)

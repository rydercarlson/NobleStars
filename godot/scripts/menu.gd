class_name MenuShell
extends Control
## Menu shell: shared chrome (background, 3D fighter stage) plus screen
## switching between lobby / fighters / modes / shop / road / settings.

var screens: Dictionary = {}
var stage: MenuStage
var lobby: LobbyScreen
var _navy: ColorRect

func _ready() -> void:
	SaveGame.ensure_loaded()
	# Debug: NS3_MENU_SHOT=/path.png screenshots the menu and quits.
	# Combine with NS3_MENU_SCREEN=lobby|fighters|modes|shop|road|settings.
	if OS.get_environment("NS3_MENU_SHOT") != "":
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			get_viewport().get_texture().get_image().save_png(OS.get_environment("NS3_MENU_SHOT"))
			get_tree().quit())
	# Net debug hooks: NS3_HOST=<n> hosts and auto-starts once n players are in
	# the room; NS3_JOIN=<ip> joins that host. Both skip the menu UI, and they
	# beat the single-player hooks so NS3_AUTOFIRE etc. can combine with them.
	elif OS.get_environment("NS3_HOST") != "":
		var want := int(OS.get_environment("NS3_HOST"))
		Net.host_game(SaveGame.player_name, SaveGame.selected_kit)
		Net.roster_changed.connect(func() -> void:
			if Net.active and Net.players.size() >= want and not Net.locked:
				Net.start_game())
		return
	elif OS.get_environment("NS3_JOIN") != "":
		Net.join_game(OS.get_environment("NS3_JOIN"), SaveGame.player_name, SaveGame.selected_kit)
		return
	# Debug hooks jump straight into a match.
	elif OS.get_environment("NS3_KIT") != "" or OS.get_environment("NS3_AUTOFIRE") != "" \
			or OS.get_environment("NS3_SIM") != "":
		Session.kit = Kits.named(OS.get_environment("NS3_KIT"))
		Session.mode = "showdown"
		get_tree().change_scene_to_file.call_deferred("res://game.tscn")
		return

	# The painted assembly-hall artwork is the lobby's backdrop; the flat navy
	# sits above it for every other screen, which was designed against it.
	var art := TextureRect.new()
	art.texture = load("res://assets/menu_bg.png")
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	_navy = ColorRect.new()
	_navy.color = UIKit.NAVY
	_navy.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_navy)

	stage = MenuStage.new()
	add_child(stage)
	place_stage_center()

	lobby = LobbyScreen.new()
	_add_screen("lobby", lobby)
	_add_screen("fighters", FighterSelect.new())
	_add_screen("modes", ModeSelect.new())
	_add_screen("shop", ShopScreen.new())
	_add_screen("road", TrophyRoadScreen.new())
	_add_screen("settings", SettingsScreen.new())
	_add_screen("friends", RoomScreen.new())

	var start: String = OS.get_environment("NS3_MENU_SCREEN")
	show_screen(start if screens.has(start) else "lobby")

func _add_screen(screen_name: String, screen: Control) -> void:
	screen.set("menu", self)
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.visible = false
	add_child(screen)
	screens[screen_name] = screen

func show_screen(screen_name: String) -> void:
	for s in screens.values():
		s.visible = false
	var screen: Control = screens[screen_name]
	screen.visible = true
	_navy.visible = screen_name != "lobby"
	stage.visible = screen_name == "lobby"
	if screen_name == "lobby":
		place_stage_center()
		stage.show_kit(Kits.named(SaveGame.selected_kit))
	if screen.has_method("refresh"):
		screen.refresh()

## Centered on the artwork's stage: the camera projects the fighter's feet
## ~84% down the viewport, so a 0.40 vertical anchor plants them on the
## painted boards (~0.70 of screen height).
func place_stage_center() -> void:
	stage.anchor_left = 0.5
	stage.anchor_right = 0.5
	stage.anchor_top = 0.40
	stage.anchor_bottom = 0.40
	stage.offset_left = -MenuStage.STAGE_SIZE.x / 2
	stage.offset_right = MenuStage.STAGE_SIZE.x / 2
	stage.offset_top = -MenuStage.STAGE_SIZE.y / 2
	stage.offset_bottom = MenuStage.STAGE_SIZE.y / 2

## Fighter-detail view parks the stage on the left half.
func place_stage_left() -> void:
	stage.anchor_left = 0.0
	stage.anchor_right = 0.0
	stage.anchor_top = 0.5
	stage.anchor_bottom = 0.5
	stage.offset_left = 60
	stage.offset_right = 60 + MenuStage.STAGE_SIZE.x
	stage.offset_top = -MenuStage.STAGE_SIZE.y / 2
	stage.offset_bottom = MenuStage.STAGE_SIZE.y / 2

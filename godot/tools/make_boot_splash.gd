extends SceneTree
## Renders the engine's boot splash: a PNG of the game loading screen's own
## first frame.
##
## The engine paints the splash before a line of our code has run, so it can
## only ever be a still image — but there is no reason for it to be a SECOND
## design. `loading_screen.gd:compose()` builds the screen as a detached Control
## tree, this shoots that tree, and `application/boot_splash/*` in project.godot
## points at the result. Boot and every transition after it are then the same
## screen, and changing the screen means re-running this rather than redrawing
## anything.
##
## Needs a real renderer, so DO NOT pass --headless (the dummy driver renders
## nothing and the PNG comes out empty):
##   /Applications/Godot.app/Contents/MacOS/Godot --path godot \
##       --script res://tools/make_boot_splash.gd
##
## Env:
##   NS3_SPLASH_OUT=res://some/file.png     (default: OUT below)

const LoadingScreen := preload("res://scripts/loading_screen.gd")

const OUT := "res://assets/menu/background/boot_splash.png"

## The splash is composed at the loading screen's authored 1280x720 and shot at
## this width. It is not the resolution of any screen it lands on — the engine
## scales it to fit — so the only number that matters is the keyart's own 1920,
## past which a bigger render invents no detail and costs real megabytes (the
## same frame at 2560 is a 4 MB PNG against a 500 KB source JPEG).
##
## `size_2d_override` is what buys the extra pixels: the layout stays in
## authored coordinates while the fonts rasterize at the larger size, exactly as
## the game's own `canvas_items` stretch does on a phone. Scaling the Control
## tree instead would upscale the glyph bitmaps and lose the point.
const OUT_WIDTH := 1920

var _started := false
var _finished := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished


func _run() -> void:
	var out := OS.get_environment("NS3_SPLASH_OUT")
	if out == "":
		out = OUT

	var base: Vector2i = LoadingScreen.BOOT_SIZE
	var scale: float = float(OUT_WIDTH) / float(base.x)
	var view := SubViewport.new()
	view.size = Vector2i(Vector2(base) * scale)
	view.size_2d_override = base
	view.size_2d_override_stretch = true
	view.disable_3d = true
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)

	# No kit: at a cold start nobody has picked one, which is also the frame the
	# lobby-bound transition uses.
	var parts: Dictionary = LoadingScreen.compose(
			LoadingScreen.BOOT_TITLE, LoadingScreen.BOOT_SUBTITLE, "")
	view.add_child(parts["root"] as Control)

	# Fonts and the keyart both land a frame or two after they are asked for.
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw

	var img: Image = view.get_texture().get_image()
	# Nothing here is transparent, and the alpha channel is a quarter of the file.
	img.convert(Image.FORMAT_RGB8)
	var err: int = img.save_png(out)
	if err == OK:
		print("boot splash -> %s (%dx%d)" % [out, img.get_width(), img.get_height()])
		print("  project.godot wants application/boot_splash/image=\"%s\"" % out)
	else:
		push_error("make_boot_splash: could not write %s (error %d)" % [out, err])
	_finished = true

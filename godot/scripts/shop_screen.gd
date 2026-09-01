class_name ShopScreen
extends Control
## Placeholder shop: dummy offer cards, nothing purchasable yet.

const OFFERS: Array = [
	{"name": "MEGA BOX", "art": "?", "price": "199 COINS"},
	{"name": "COIN DOUBLER", "art": "x2", "price": "50 GEMS"},
	{"name": "CHEF TONY SKIN", "art": "?", "price": "79 GEMS"},
	{"name": "GEM PACK", "art": "+80", "price": "$1.99"},
]

var menu: MenuShell
var coin_pill: PanelContainer

func _ready() -> void:
	var back := UIKit.back_button()
	back.pressed.connect(func() -> void: menu.show_screen("lobby"))
	add_child(back)

	var title := UIKit.label("SHOP", 40, UIKit.GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(title)

	coin_pill = UIKit.pill("", UIKit.PLAY_YELLOW)
	coin_pill.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	coin_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(coin_pill)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BOTH

	for offer in OFFERS:
		var panel := UIKit.panel()
		row.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		box.custom_minimum_size = Vector2(210, 260)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(box)
		var offer_name := UIKit.label(str(offer.name), 20, Color.WHITE)
		offer_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(offer_name)
		var art := UIKit.label(str(offer.art), 64, UIKit.GOLD)
		art.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(art)
		var price := UIKit.label(str(offer.price), 18, UIKit.MUTED)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(price)
		var buy := UIKit.button("COMING SOON", 16, UIKit.NAVY_DEEP)
		buy.disabled = true
		buy.add_theme_stylebox_override("disabled", UIKit.flat(UIKit.NAVY_DEEP, 14, 1, UIKit.FAINT))
		buy.add_theme_color_override("font_disabled_color", UIKit.MUTED)
		box.add_child(buy)

func refresh() -> void:
	UIKit.set_pill_text(coin_pill, "$ %d" % SaveGame.coins)

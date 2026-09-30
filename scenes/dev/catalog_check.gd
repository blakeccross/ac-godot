extends Control

## Renders the catalog (`CatalogOverlay`) for a visual check: the furniture page with a
## few collected pieces, a page turn caught half way, the wallpaper page, and the
## "Order / Quit" tag. Run headed:
##   Godot --path . res://scenes/dev/catalog_check.tscn
## Writes user://catalog_*.png.


func _ready() -> void:
	await get_tree().process_frame
	var bg := ColorRect.new()
	bg.color = Color(0.30, 0.45, 0.28)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var book := CatalogBook.new()
	for i: int in [214, 215, 218, 25, 12, 216, 341, 217, 219, 2, 86, 96]:
		book.record(FtrCatalog.item_id(i))
	for i: int in [0, 1, 2]:
		book.record(InteriorStyleCatalog.wall_style_id(i))
	book.record(ShopGoods.PAPER)
	var ui: CatalogOverlay = load("res://scenes/ui/catalog_overlay.tscn").instantiate()
	add_child(ui)
	await get_tree().process_frame
	ui.open(book)
	await _wait(0.8)
	_shot("1_furniture")
	for _i in 8:
		_key(ui, KEY_DOWN)
	await _wait(0.6)
	_shot("2_scrolled")
	_key(ui, KEY_RIGHT)
	_key(ui, KEY_DOWN)
	await _wait(0.4)
	_shot("3_tab_name")
	_key(ui, KEY_ENTER)
	await _wait(0.2)
	_shot("4_turning")
	await _wait(1.0)
	_shot("5_wallpaper")
	_key(ui, KEY_DOWN)
	_key(ui, KEY_DOWN)
	_key(ui, KEY_DOWN)
	_key(ui, KEY_DOWN)
	_key(ui, KEY_ENTER)
	await _wait(1.2)
	_key(ui, KEY_LEFT)
	_key(ui, KEY_ENTER)
	await _wait(0.4)
	_shot("6_order_tag")
	get_tree().quit()


func _key(ui: CatalogOverlay, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ui._unhandled_input(ev)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://catalog_%s.png" % name)
	print("catalog_check: wrote ", name)

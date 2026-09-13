extends Control

## Dev harness: open the pockets overlay, hop the fish / bug encyclopedia tabs,
## snapshot each page to user://inventory_proof_*.png.
## SideTab enum in inventory_overlay.gd: FISH = 0, POCKETS = 1, BUG = 2.

var _overlay: CanvasLayer = null
var _letter_reader: CanvasLayer = null
var _shots: Array = [["0_pockets", 1], ["1_fish", 0], ["2_bug", 2], ["3_back", 1]]
var _i: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.55, 0.25)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	Game.player_name = "Nintendo"
	Game.town_name = "Villager"
	Game.inventory.set_wallet(99289)
	Game.inventory.add(ItemCatalog.get_item(&"fishing_rod"))
	Game.inventory.add(ItemCatalog.get_item(&"net"))
	Game.inventory.equip_slot(0)
	for id in ["crucian_carp", "koi", "sea_bass", "eel", "common_butterfly", "firefly", "giant_beetle", "ladybug"]:
		Game.species_log.record(StringName(id))

	Game.inventory.add(ItemCatalog.get_item(&"apple"), 3)
	var mail := MailData.new()
	mail.font = MailData.LetterFont.RECV
	mail.sender_name = "Copper"
	mail.header = "Dear Nintendo,"
	mail.body = "Welcome to town! I hope you're settling in okay. Let me know if you need anything!"
	mail.footer = "Copper"
	mail.paper_type = 9
	Game.inventory.add_mail(mail)
	_overlay = load("res://scenes/ui/inventory_overlay.tscn").instantiate()
	add_child(_overlay)
	_letter_reader = load("res://scenes/ui/letter_reader_overlay.tscn").instantiate()
	add_child(_letter_reader)
	await get_tree().process_frame
	await get_tree().process_frame
	_overlay.open()
	await get_tree().process_frame
	## Select the apple and open its verb menu.
	Game.inventory.select(2)
	_overlay._activate_cursor()
	await get_tree().create_timer(0.6).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://inventory_proof_tagmenu.png")
	print("inventory_proof: wrote tagmenu")
	_overlay._tag_mode = false
	_overlay._hide_tag_popup()
	_overlay._refresh()
	await get_tree().process_frame
	_run()


func _run() -> void:
	if _i >= _shots.size():
		await _extra_checks()
		print("inventory_proof: done")
		get_tree().quit()
		return
	_overlay._select_side_tab(_shots[_i][1])
	await get_tree().create_timer(0.7).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://inventory_proof_%s.png" % _shots[_i][0])
	print("inventory_proof: wrote ", _shots[_i][0])
	_i += 1
	_run()


## Marked slots + the wallet/background chrome added for the full-original pockets pass.
func _extra_checks() -> void:
	Game.inventory.add(ItemCatalog.get_item(&"wall_blue"), 1)
	Game.inventory.select(0)
	Game.inventory.toggle_mark(0)
	Game.inventory.select(2)
	Game.inventory.toggle_mark(2)
	Game.inventory.select(3) ## wall_blue slot
	_overlay._run_tag("Set Background")
	_overlay._refresh()
	await get_tree().create_timer(0.4).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://inventory_proof_4_marked.png")
	print("inventory_proof: wrote 4_marked")

	_overlay._open_wallet_popup()
	await get_tree().create_timer(0.4).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("user://inventory_proof_5_wallet_popup.png")
	print("inventory_proof: wrote 5_wallet_popup")
	_overlay._tag_mode = false
	_overlay._wallet_tag_mode = false
	_overlay._hide_tag_popup()

	## Cursor reaching the player doll (`mTG_TABLE_PLAYER`) + the Unequip popup on it.
	Game.inventory.equip_slot(1) ## net, added in _ready()
	_overlay._focus_player = true
	_overlay._activate_player_cursor()
	_overlay._refresh()
	await get_tree().create_timer(0.4).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("user://inventory_proof_6_player_slot.png")
	print("inventory_proof: wrote 6_player_slot")

	## Read a letter: the real stationery paper window, not a text toast.
	_overlay._focus_player = false
	Game.inventory.select_mail(0)
	_letter_reader.open(Game.inventory.mail_at(0))
	await get_tree().create_timer(0.45).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("user://inventory_proof_7_letter.png")
	print("inventory_proof: wrote 7_letter")

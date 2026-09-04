extends CanvasLayer

## Counter paper UI. Buy today's goods; sell pockets at Nook only (`SELL_BUY_RATIO`).

@onready var _root: Control = %Root
@onready var _paper: PanelContainer = %Paper
@onready var _title: Label = %Title
@onready var _wallet: Label = %WalletLabel
@onready var _list: VBoxContainer = %ItemList
@onready var _name: Label = %ItemNameLabel
@onready var _desc: Label = %ItemDescLabel
@onready var _tags: Label = %TagLabel
@onready var _hint: Label = %HintLabel

var _open: bool = false
var _shop_id: StringName = &""
var _mode: StringName = Interaction.BUY
var _cursor: int = 0
var _rows: Array[Dictionary] = []
var _tag_mode: bool = false
var _tag_choices: PackedStringArray = []
var _tag_index: int = 0
var _buttons: Array[Button] = []


func _ready() -> void:
	layer = 21
	add_to_group("shop_ui")
	_root.visible = false
	if _paper != null:
		_paper.self_modulate = Color(0.96, 0.9, 0.78, 1)
	Game.inventory.changed.connect(_refresh)
	Game.inventory.wallet_changed.connect(func(_a: int) -> void: _refresh())
	_refresh()


func is_open() -> bool:
	return _open


func open(shop_id: StringName, mode: StringName = Interaction.BUY) -> void:
	if shop_id == &"":
		return
	_shop_id = shop_id
	_mode = Interaction.SELL if mode == Interaction.SELL and Game.shops.allows_sell(shop_id) else Interaction.BUY
	_open = true
	_tag_mode = false
	_cursor = 0
	_root.visible = true
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_tag_mode = false
	_root.visible = false
	_shop_id = &""


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel"):
		if _tag_mode:
			_tag_mode = false
			_refresh()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		return
	if _tag_mode:
		_handle_tag_input(event)
		return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		_move_cursor(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		_move_cursor(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_set_mode(Interaction.BUY)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		if Game.shops.allows_sell(_shop_id):
			_set_mode(Interaction.SELL)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_activate()
		get_viewport().set_input_as_handled()


func _handle_tag_input(event: InputEvent) -> void:
	if _tag_choices.is_empty():
		_tag_mode = false
		_refresh()
		return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		_tag_index = (_tag_index - 1 + _tag_choices.size()) % _tag_choices.size()
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		_tag_index = (_tag_index + 1) % _tag_choices.size()
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_run_tag(_tag_choices[_tag_index])
		get_viewport().set_input_as_handled()


func _set_mode(mode: StringName) -> void:
	if _mode == mode:
		return
	_mode = mode
	_cursor = 0
	_tag_mode = false
	_refresh()


func _move_cursor(delta: int) -> void:
	if _rows.is_empty():
		_cursor = 0
		return
	_cursor = clampi(_cursor + delta, 0, _rows.size() - 1)
	_refresh()


func _activate() -> void:
	if _rows.is_empty() or _cursor < 0 or _cursor >= _rows.size():
		return
	if _mode == Interaction.BUY:
		var item_id: StringName = _rows[_cursor].get("id", &"") as StringName
		var msg: String = Game.shops.buy(_shop_id, item_id, Game.inventory)
		Game.post_notice(msg)
		Game.call_deferred("refresh_shop_set")
		_tag_mode = false
		_refresh()
		return
	var count: int = int(_rows[_cursor].get("count", 1))
	if count > 1:
		_tag_choices = PackedStringArray(["Sell 1", "Sell all"])
		_tag_mode = true
		_tag_index = 0
		_refresh()
		return
	_sell(1)


func _run_tag(tag: String) -> void:
	if tag == "Sell all":
		_sell(int(_rows[_cursor].get("count", 1)) if _cursor < _rows.size() else 1)
	else:
		_sell(1)
	_tag_mode = false
	_refresh()


func _sell(count: int) -> void:
	if _rows.is_empty() or _cursor < 0 or _cursor >= _rows.size():
		return
	var item_id: StringName = _rows[_cursor].get("id", &"") as StringName
	var msg: String = Game.shops.sell(_shop_id, item_id, Game.inventory, count)
	Game.post_notice(msg)


func _on_row_pressed(index: int) -> void:
	if not _open:
		return
	_cursor = index
	_activate()


func _refresh() -> void:
	_rebuild_rows()
	if _cursor >= _rows.size():
		_cursor = maxi(_rows.size() - 1, 0)
	var shop_name: String = "Shop"
	var room: Room = InteriorCatalog.room_template(_shop_id)
	if room != null:
		shop_name = room.display_name
	var tab: String = "Buy"
	if _mode == Interaction.SELL:
		tab = "Sell"
	_title.text = "%s — %s" % [shop_name, tab]
	_wallet.text = "%d Bells" % Game.inventory.wallet
	for child: Node in _list.get_children():
		child.queue_free()
	_buttons.clear()
	if _rows.is_empty():
		var empty := Label.new()
		empty.text = "Nothing for sale." if _mode == Interaction.BUY else "Nothing to sell."
		_list.add_child(empty)
		_name.text = ""
		_desc.text = ""
	else:
		for i: int in _rows.size():
			var row: Dictionary = _rows[i]
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.text = str(row.get("label", ""))
			btn.modulate = Color(1, 1, 1, 1) if i == _cursor else Color(1, 1, 1, 0.7)
			btn.pressed.connect(_on_row_pressed.bind(i))
			_list.add_child(btn)
			_buttons.append(btn)
		var sel: Dictionary = _rows[_cursor]
		_name.text = str(sel.get("name", ""))
		_desc.text = str(sel.get("desc", ""))
	if _tag_mode and not _tag_choices.is_empty():
		var lines: PackedStringArray = []
		for i: int in _tag_choices.size():
			var prefix: String = ">" if i == _tag_index else " "
			lines.append("%s %s" % [prefix, _tag_choices[i]])
		_tags.text = "\n".join(lines)
		_hint.text = "↑↓ choose  E confirm  Esc back"
	else:
		_tags.text = ""
		if Game.shops.allows_sell(_shop_id):
			_hint.text = "↑↓ list  ← Buy  → Sell  E confirm  Esc close"
		else:
			_hint.text = "↑↓ list  E buy  Esc close"


func _rebuild_rows() -> void:
	_rows.clear()
	if _shop_id == &"":
		return
	if _mode == Interaction.BUY:
		for item_id: StringName in Game.shops.goods(_shop_id):
			var data: ItemData = ItemCatalog.get_item(item_id)
			if data == null:
				continue
			var price: int = ShopBook.buy_price(data)
			_rows.append({
				"id": item_id,
				"name": data.display_name,
				"label": "%s  %d Bells" % [data.display_name, price],
				"desc": data.description,
				"price": price,
				"count": 1,
			})
		return
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = Game.inventory.slot_at(i)
		if slot == null or slot.is_empty():
			continue
		var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
		if data == null:
			continue
		var unit: int = ShopBook.sell_price(data)
		if unit <= 0:
			continue
		var count: int = slot.item.count
		var label: String = "%s  %d Bells" % [data.display_name, unit]
		if count > 1:
			label = "%s ×%d  %d Bells each" % [data.display_name, count, unit]
		_rows.append({
			"id": data.id,
			"name": data.display_name,
			"label": label,
			"desc": "Nook pays %d Bells." % unit,
			"price": unit,
			"count": count,
		})

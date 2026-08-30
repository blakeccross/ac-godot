extends CanvasLayer

## Pocket submenu. Layout from `m_inventory_ovl` (5×3) + tag verbs from `m_tag_ovl`.

const ITEM_SCENE := "res://scenes/world/item_pickup.tscn"

@onready var _root: Control = %Root
@onready var _paper: PanelContainer = %Paper
@onready var _grid: GridContainer = %SlotGrid
@onready var _wallet: Label = %WalletLabel
@onready var _name: Label = %ItemNameLabel
@onready var _desc: Label = %ItemDescLabel
@onready var _tags: Label = %TagLabel
@onready var _equip: Label = %EquipLabel
@onready var _hint: Label = %HintLabel

var _open: bool = false
var _slot_buttons: Array[Button] = []
var _tag_choices: PackedStringArray = []
var _tag_index: int = 0
var _tag_mode: bool = false


func _ready() -> void:
	layer = 20
	add_to_group("inventory_ui")
	_build_slots()
	_root.visible = false
	if _paper != null:
		_paper.self_modulate = Color(0.96, 0.9, 0.78, 1)
	Game.inventory.changed.connect(_refresh)
	Game.inventory.selection_changed.connect(_on_selection)
	Game.inventory.wallet_changed.connect(func(_a: int) -> void: _refresh())
	Game.inventory.equipment_changed.connect(func(_id: StringName) -> void: _refresh())
	_refresh()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_tag_mode = false
	_root.visible = true
	Game.inventory.clear_hand()
	_refresh()
	get_tree().paused = false


func close() -> void:
	if not _open:
		return
	_open = false
	_tag_mode = false
	_root.visible = false
	Game.inventory.clear_hand()
	_refresh()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func _build_slots() -> void:
	for child: Node in _grid.get_children():
		child.queue_free()
	_slot_buttons.clear()
	_grid.columns = Inventory.COLUMNS
	for i: int in Inventory.POCKET_SLOTS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(72, 72)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_slot_pressed.bind(i))
		_grid.add_child(btn)
		_slot_buttons.append(btn)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		var talk: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
		if talk != null and talk.has_method("is_open") and bool(talk.call("is_open")):
			get_viewport().set_input_as_handled()
			return
		var shop: Node = get_tree().get_first_node_in_group("shop_ui") if get_tree() != null else null
		if shop != null and shop.has_method("is_open") and bool(shop.call("is_open")):
			get_viewport().set_input_as_handled()
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
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
	if _tag_mode:
		_handle_tag_input(event)
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		Game.inventory.move_cursor(-1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		Game.inventory.move_cursor(1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		Game.inventory.move_cursor(0, -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		Game.inventory.move_cursor(0, 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_activate_cursor()
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


func _on_slot_pressed(index: int) -> void:
	if not _open:
		return
	Game.inventory.select(index)
	_activate_cursor()


func _on_selection(_index: int) -> void:
	_tag_mode = false
	_refresh()


func _activate_cursor() -> void:
	var inv: Inventory = Game.inventory
	var idx: int = inv.selected_index
	if inv.hand_index >= 0:
		inv.place_hand(idx)
		_refresh()
		return
	var slot: InventorySlot = inv.slot_at(idx)
	if slot == null or slot.is_empty():
		return
	_tag_choices = inv.tags_for_slot(idx)
	if _tag_choices.is_empty():
		return
	_tag_mode = true
	_tag_index = 0
	_refresh()


func _run_tag(tag: String) -> void:
	var inv: Inventory = Game.inventory
	var idx: int = inv.selected_index
	match tag:
		"Place":
			var player := get_tree().get_first_node_in_group("player") as Node3D
			if player != null:
				Game.try_place_furniture(player)
			close()
		"Hang", "Lay":
			var slot: InventorySlot = inv.slot_at(idx)
			if slot != null and not slot.is_empty():
				Game.try_apply_cover(ItemCatalog.get_item(slot.item.item_id))
			close()
		"Drop":
			_drop_selected()
		"Equip":
			if inv.equip_slot(idx):
				var data: ItemData = ItemCatalog.get_item(inv.equipment_id)
				if data != null:
					Game.post_notice("Equipped %s" % data.display_name)
		"Move":
			inv.pick_hand(idx)
		"Open":
			var slot: InventorySlot = inv.slot_at(idx)
			if slot != null and not slot.is_empty():
				slot.item.condition = InventoryItem.Condition.NORMAL
				inv.changed.emit()
				Game.post_notice("Opened present")
		"Plant":
			var msg: String = PlantGrowth.plant_from_slot(_field_context(), idx)
			if msg != "":
				Game.post_notice(msg)
		_:
			var msg: String = inv.use_slot(idx)
			if msg != "":
				Game.post_notice(msg)
	_tag_mode = false
	_refresh()


func _drop_selected() -> void:
	var inv: Inventory = Game.inventory
	var removed: InventoryItem = inv.drop_slot(inv.selected_index, 1)
	if removed.is_empty():
		return
	var data: ItemData = ItemCatalog.get_item(removed.item_id)
	if data == null:
		return
	if not _spawn_pickup(data):
		inv.add(data, removed.count, removed.condition)
		Game.post_notice("Can't drop here")
		return
	Game.post_notice("Dropped %s" % data.display_name)


func _spawn_pickup(item: ItemData) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var player := tree.get_first_node_in_group("player") as Node3D
	var world := tree.get_first_node_in_group("world") as Node
	if player == null or world == null:
		return false
	var packed: PackedScene = load(ITEM_SCENE) as PackedScene
	if packed == null:
		return false
	var node: Node = packed.instantiate()
	if not (node is Node3D):
		node.queue_free()
		return false
	var pickup := node as Node3D
	pickup.set("item", item)
	var pid := StringName("drop_%s_%d" % [String(item.id), Time.get_ticks_msec()])
	pickup.set("persist_id", pid)
	pickup.set("occupy_grid", false)
	var objects: Node = world.get_node_or_null("Objects")
	if objects == null:
		world.add_child(pickup)
	else:
		objects.add_child(pickup)
	var yaw: float = 0.0
	if player.has_method("facing_yaw"):
		yaw = float(player.call("facing_yaw"))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	pickup.global_position = player.global_position + forward * 1.1 + Vector3(0.0, 0.05, 0.0)
	return true


func _field_context() -> InteractionContext:
	var ctx := InteractionContext.new()
	ctx.inventory = Game.inventory
	var tree := get_tree()
	if tree != null:
		ctx.actor = tree.get_first_node_in_group("player") as Node3D
		ctx.world = tree.get_first_node_in_group("world")
	return ctx


func _refresh() -> void:
	var inv: Inventory = Game.inventory
	_wallet.text = "%d Bells" % inv.wallet
	var eq: ItemData = ItemCatalog.get_item(inv.equipment_id)
	_equip.text = "Held: %s" % (eq.display_name if eq != null else "—")
	for i: int in _slot_buttons.size():
		var btn: Button = _slot_buttons[i]
		var slot: InventorySlot = inv.slot_at(i)
		var selected: bool = i == inv.selected_index
		var in_hand: bool = i == inv.hand_index
		if slot == null or slot.is_empty():
			btn.text = ""
			btn.icon = null
			btn.modulate = Color(1, 1, 1, 0.55 if selected else 0.35)
		else:
			var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
			var label: String = data.display_name if data != null else String(slot.item.item_id)
			if slot.item.count > 1:
				label = "%s×%d" % [label.substr(0, mini(6, label.length())), slot.item.count]
			elif label.length() > 8:
				label = label.substr(0, 8)
			btn.text = label
			if data != null and data.icon != null:
				btn.icon = data.icon
				btn.expand_icon = true
			else:
				btn.icon = null
			var tint: Color = data.icon_color if data != null else Color.WHITE
			if selected:
				btn.modulate = tint.lightened(0.15)
			elif in_hand:
				btn.modulate = tint.darkened(0.2)
			else:
				btn.modulate = tint
		btn.disabled = false
	var sel: InventorySlot = inv.selected_slot()
	if sel == null or sel.is_empty():
		_name.text = ""
		_desc.text = ""
	else:
		var data: ItemData = ItemCatalog.get_item(sel.item.item_id)
		if data == null:
			_name.text = String(sel.item.item_id)
			_desc.text = ""
		else:
			_name.text = data.display_name
			_desc.text = data.description
			if sel.item.condition == InventoryItem.Condition.PRESENT:
				_name.text = "Present"
				_desc.text = "A wrapped gift."
			elif sel.item.condition == InventoryItem.Condition.QUEST:
				_name.text = "%s (quest)" % data.display_name
	if _tag_mode and not _tag_choices.is_empty():
		var lines: PackedStringArray = []
		for i: int in _tag_choices.size():
			var prefix: String = ">" if i == _tag_index else " "
			lines.append("%s %s" % [prefix, _tag_choices[i]])
		_tags.text = "\n".join(lines)
		_hint.text = "↑↓ choose  E confirm  Esc back"
	else:
		_tags.text = ""
		_hint.text = "X close  Arrows move  E tags  (hand: E empty slot)"

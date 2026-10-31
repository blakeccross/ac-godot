class_name MobileInventory
extends Control

signal slot_pressed(index: int)
signal action_pressed(action: String)
signal actions_cancelled
signal more_pressed
signal wallet_pressed
signal close_pressed

const COLUMNS := 4
const ACTION_SCENE := preload("res://scenes/ui/mobile_inventory_action.tscn")

@onready var _safe_area: Control = $SafeArea
@onready var _sheet: PanelContainer = $SafeArea/Sheet
@onready var _grid: GridContainer = %Grid
@onready var _scroll: ScrollContainer = %Scroll
@onready var _capacity: Label = %Capacity
@onready var _wallet: Button = %Wallet
@onready var _actions: Control = %Actions
@onready var _action_name: Label = %ActionName
@onready var _action_list: HFlowContainer = %ActionList

var _shown_actions := PackedStringArray()
var _selected_name: String = ""


func _ready() -> void:
	TouchSafeArea.fit(_safe_area)
	_safe_area.resized.connect(_fit)
	for i: int in _grid.get_child_count():
		(_grid.get_child(i) as Button).pressed.connect(func() -> void: slot_pressed.emit(i))
	%More.pressed.connect(func() -> void: more_pressed.emit())
	%Wallet.pressed.connect(func() -> void: wallet_pressed.emit())
	%Close.pressed.connect(func() -> void: close_pressed.emit())
	%Cancel.pressed.connect(func() -> void: actions_cancelled.emit())
	_fit()


func _fit() -> void:
	var width := maxf(_safe_area.size.x - 32.0, 0.0)
	width = minf(880.0, width)
	_sheet.offset_left = -width * 0.5
	_sheet.offset_right = width * 0.5
	var gaps := _grid.get_theme_constant("h_separation") * (COLUMNS - 1)
	var card_height := maxf(148.0, (width - 32.0 - gaps) / COLUMNS * 0.7)
	for card: Control in _grid.get_children():
		card.custom_minimum_size.y = card_height


func refresh(inv: Inventory) -> void:
	_capacity.text = "%d / %d pockets" % [inv.count_of_occupied(), Inventory.POCKET_SLOTS]
	_wallet.text = "%d Bells" % inv.wallet
	_selected_name = ""
	for i: int in _grid.get_child_count():
		var card := _grid.get_child(i) as Button
		var icon := card.get_node("Content/Icon") as TextureRect
		var item_name := card.get_node("Content/Name") as Label
		var quantity := card.get_node("Content/Quantity") as Label
		var slot: InventorySlot = inv.slot_at(i)
		var empty := slot == null or slot.is_empty()
		card.set_pressed_no_signal(i == inv.selected_index and not empty)
		card.modulate = Color(1, 1, 1, 0.45) if empty else Color.WHITE
		icon.texture = null
		item_name.text = "Empty"
		quantity.text = "-"
		card.tooltip_text = "Empty pocket"
		if empty:
			continue
		var data := ItemCatalog.get_item(slot.item.item_id)
		var wrapped := slot.item.condition == InventoryItem.Condition.PRESENT
		item_name.text = "Wrapped present" if wrapped else (
			data.display_name if data != null else String(slot.item.item_id)
		)
		icon.texture = InventoryChrome.icon_for_item(data, slot.item.condition)
		quantity.text = str(slot.item.count)
		if inv.equipment_id == slot.item.item_id:
			quantity.text += "  Held"
		if inv.is_marked(i):
			quantity.text += "  Marked"
		card.tooltip_text = "%s (%d)" % [item_name.text, slot.item.count]
		if i == inv.selected_index:
			_selected_name = item_name.text
		if i == inv.hand_index:
			card.modulate = Color(0.65, 0.75, 0.65, 1)


func show_actions(title: String, choices: PackedStringArray, selected: int) -> void:
	_action_name.text = _selected_name if title.is_empty() else title
	_actions.visible = true
	if choices != _shown_actions:
		for child: Node in _action_list.get_children():
			_action_list.remove_child(child)
			child.queue_free()
		_shown_actions = choices.duplicate()
		for choice: String in choices:
			var button := ACTION_SCENE.instantiate() as Button
			button.text = choice
			button.toggle_mode = true
			button.pressed.connect(func() -> void: action_pressed.emit(choice))
			_action_list.add_child(button)
	for i: int in _action_list.get_child_count():
		(_action_list.get_child(i) as Button).set_pressed_no_signal(i == selected)


func hide_actions() -> void:
	_actions.visible = false


func reveal_slot(index: int) -> void:
	_scroll.ensure_control_visible(_grid.get_child(index) as Control)

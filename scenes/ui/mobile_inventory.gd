class_name MobileInventory
extends Control

signal slot_pressed(index: int)
signal mail_pressed(index: int)
signal page_pressed(page: String)
signal designs_pressed
signal action_pressed(action: String)
signal actions_cancelled
signal wallet_pressed
signal close_pressed

const COLUMNS := 4
const ACTION_SCENE := preload("res://scenes/ui/mobile_inventory_action.tscn")
const LETTER_SCENE := preload("res://scenes/ui/mobile_letter_card.tscn")
const SPECIES_SCENE := preload("res://scenes/ui/mobile_inventory_slot.tscn")

@onready var _safe_area: Control = $SafeArea
@onready var _sheet: PanelContainer = $SafeArea/Sheet
@onready var _title: Label = %Title
@onready var _wallet: Button = %Wallet
@onready var _grid: GridContainer = %Grid
@onready var _scroll: ScrollContainer = %Scroll
@onready var _letters_scroll: ScrollContainer = %LettersScroll
@onready var _letter_list: VBoxContainer = %LetterList
@onready var _collection_scroll: ScrollContainer = %CollectionScroll
@onready var _collection_count: Label = %CollectionCount
@onready var _collection_grid: GridContainer = %CollectionGrid
@onready var _capacity: Label = %Capacity
@onready var _actions: Control = %Actions
@onready var _action_name: Label = %ActionName
@onready var _action_list: HFlowContainer = %ActionList
@onready var _pages: Dictionary = {
	"items": %PageItems,
	"letters": %PageLetters,
	"fish": %PageFish,
	"insects": %PageInsects,
}

var _shown_actions := PackedStringArray()
var _selected_name: String = ""
var _page: String = "items"
var _letters: Array[Button] = []
var _species: Array[Button] = []
var _collection_index: int = 0


func _ready() -> void:
	TouchSafeArea.fit(_safe_area)
	_safe_area.resized.connect(_fit)
	for i: int in _grid.get_child_count():
		(_grid.get_child(i) as Button).pressed.connect(func() -> void: slot_pressed.emit(i))
	for page: String in _pages:
		(_pages[page] as Button).pressed.connect(func() -> void: page_pressed.emit(page))
	%Designs.pressed.connect(func() -> void: designs_pressed.emit())
	%Wallet.pressed.connect(func() -> void: wallet_pressed.emit())
	%Close.pressed.connect(func() -> void: close_pressed.emit())
	%Cancel.pressed.connect(func() -> void: actions_cancelled.emit())
	for i: int in Inventory.MAIL_SLOTS:
		var card := LETTER_SCENE.instantiate() as Button
		var index := i
		card.pressed.connect(func() -> void: mail_pressed.emit(index))
		_letter_list.add_child(card)
		_letters.append(card)
	for i: int in EncyclopediaCatalog.COLLECT_NUM:
		var card := SPECIES_SCENE.instantiate() as Button
		var index := i
		card.pressed.connect(func() -> void: _select_species(index))
		_collection_grid.add_child(card)
		_species.append(card)
	_fit()


func _fit() -> void:
	## Only used in portrait (landscape keeps the desktop windows): edge to edge in the safe area.
	var width := _safe_area.size.x
	_sheet.offset_left = -width * 0.5
	_sheet.offset_right = width * 0.5
	_sheet.offset_bottom = -16.0
	var gaps := _grid.get_theme_constant("h_separation") * (COLUMNS - 1)
	var card_height := maxf(148.0, (width - 32.0 - gaps) / COLUMNS * 0.7)
	for card: Control in _grid.get_children():
		card.custom_minimum_size.y = card_height
	for card: Control in _collection_grid.get_children():
		card.custom_minimum_size.y = card_height


func page() -> String:
	return _page


func show_page(page: String) -> void:
	_page = page if _pages.has(page) else "items"
	_scroll.visible = _page == "items"
	_letters_scroll.visible = _page == "letters"
	_collection_scroll.visible = _page == "fish" or _page == "insects"
	_wallet.visible = _page == "items" or _page == "letters"
	_capacity.visible = _page == "items" or _page == "letters"
	match _page:
		"letters":
			_title.text = "Letters"
		"fish":
			_title.text = "Fish"
		"insects":
			_title.text = "Insects"
		_:
			_title.text = "Inventory"
	for id: String in _pages:
		(_pages[id] as Button).set_pressed_no_signal(id == _page)


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


func refresh_letters(inv: Inventory) -> void:
	_capacity.text = "%d / %d letters" % [inv.count_mail(), Inventory.MAIL_SLOTS]
	_wallet.text = "%d Bells" % inv.wallet
	_selected_name = ""
	for i: int in _letters.size():
		var card := _letters[i]
		var name_label := card.get_node("Content/Name") as Label
		var detail := card.get_node("Content/Detail") as Label
		var mail := inv.mail_at(i)
		var empty := mail == null or mail.is_empty()
		card.set_pressed_no_signal(i == inv.selected_mail_index and not empty)
		card.modulate = Color(1, 1, 1, 0.45) if empty else Color.WHITE
		if empty:
			name_label.text = "Empty"
			detail.text = "Tap to write"
			continue
		name_label.text = mail.label()
		var note := mail.preview()
		if mail.is_received() and mail.font in [MailData.LetterFont.RECV, MailData.LetterFont.RECV_PRESENT]:
			note = "New  ·  " + note
		if mail.has_enclosure():
			note += "  ·  Gift"
		detail.text = note
		if i == inv.selected_mail_index:
			_selected_name = name_label.text


func refresh_collection(kind: StringName) -> void:
	var book: SpeciesLog = Game.species_log if Game != null else null
	var have: int = book.page_count(kind) if book != null else 0
	_collection_count.text = "%d / %d" % [have, EncyclopediaCatalog.COLLECT_NUM]
	for slot: int in _species.size():
		var card := _species[slot]
		var icon := card.get_node("Content/Icon") as TextureRect
		var item_name := card.get_node("Content/Name") as Label
		var quantity := card.get_node("Content/Quantity") as Label
		var id := EncyclopediaCatalog.id_for(kind, slot)
		var caught := book != null and book.has(id)
		var data := ItemCatalog.get_item(id)
		icon.texture = InventoryChrome.load_tex(EncyclopediaCatalog.icon_for(kind, slot))
		icon.modulate = Color.WHITE if caught else Color(0.05, 0.06, 0.09, 0.45)
		item_name.text = data.display_name if caught and data != null else "???"
		quantity.text = ""
		card.modulate = Color.WHITE if caught else Color(1, 1, 1, 0.7)
		card.set_pressed_no_signal(slot == _collection_index)
		card.tooltip_text = item_name.text


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


func reveal_letter(index: int) -> void:
	if index >= 0 and index < _letters.size():
		_letters_scroll.ensure_control_visible(_letters[index])


func collection_index() -> int:
	return _collection_index


func select_collection(index: int) -> void:
	_collection_index = clampi(index, 0, _species.size() - 1)
	for i: int in _species.size():
		_species[i].set_pressed_no_signal(i == _collection_index)
	_collection_scroll.ensure_control_visible(_species[_collection_index])


func _select_species(index: int) -> void:
	select_collection(index)

extends CanvasLayer

## Pocket submenu. Layout from `m_inventory_ovl` / baked `window_shell` + `catalog.json`.
## Top-left circle shows a live 3D player preview (`mIV_set_player`).

const ITEM_SCENE := "res://scenes/world/item_pickup.tscn"
const PLAYER_GLB := "res://assets/generated/characters/player/boy_1.glb"
const DISPLAY_SCALE := 0.78

const COL_ITEM_RING := Color("70c0ff")
const COL_ITEM_RING_SEL := Color("a0d8ff")
const COL_ITEM_FILL := Color(0.28, 0.22, 0.3, 1)
const COL_MAIL_RING := Color("ff4040")
const COL_MAIL_RING_SEL := Color("ff8080")
const COL_MAIL_EMPTY := Color(0.9, 0.28, 0.22, 1)
const COL_MAIL_FILL := Color(0.35, 0.18, 0.2, 1)

@onready var _root: Control = %Root
@onready var _shell_stack: Control = %ShellStack
@onready var _shell_shadow: TextureRect = %ShellShadow
@onready var _window_shell: TextureRect = %WindowShell
@onready var _slot_layer: Control = %SlotLayer
@onready var _detail: Control = %Detail
@onready var _wallet: Label = %WalletLabel
@onready var _bells_pill: PanelContainer = %BellsPill
@onready var _player_name: Label = %PlayerName
@onready var _town_name: Label = %TownName
@onready var _player_bar: TextureRect = %PlayerBar
@onready var _town_bar: TextureRect = %TownBar
@onready var _name: Label = %ItemNameLabel
@onready var _desc: Label = %ItemDescLabel
@onready var _tags: Label = %TagLabel
@onready var _equip: Label = %EquipLabel
@onready var _hint: Label = %HintLabel
@onready var _items_label: TextureRect = %ItemsLabel
@onready var _letters_label: TextureRect = %LettersLabel
@onready var _bells_label: TextureRect = %BellsLabel
@onready var _portrait_clip: Panel = %PortraitClip
@onready var _portrait_frame: TextureRect = %PortraitFrame
@onready var _portrait_viewport: SubViewport = %SubViewport
@onready var _tab_pencil: PanelContainer = %TabPencil
@onready var _tab_fish: PanelContainer = %TabFish
@onready var _tab_face: PanelContainer = %TabFace
@onready var _tab_bug: PanelContainer = %TabBug
@onready var _tab_axe_icon: TextureRect = %TabAxeIcon
@onready var _tab_fish_icon: TextureRect = %TabFishIcon
@onready var _tab_scoop_icon: TextureRect = %TabScoopIcon
@onready var _tab_bug_icon: TextureRect = %TabBugIcon

var _open: bool = false
var _focus_mail: bool = false
var _slot_buttons: Array[Button] = []
var _mail_buttons: Array[Button] = []
var _tag_choices: PackedStringArray = []
var _tag_index: int = 0
var _tag_mode: bool = false
var _style_item: StyleBox
var _style_item_sel: StyleBox
var _style_mail: StyleBox
var _style_mail_sel: StyleBox
var _style_mail_empty: StyleBox
var _tex_letter: Texture2D
var _tex_letter_present: Texture2D
var _layout_scale: float = DISPLAY_SCALE
var _portrait_ready: bool = false
var _portrait_pivot: Node3D = null
var _portrait_anim: AnimationPlayer = null
var _portrait_equipment_id: StringName = &""


func _ready() -> void:
	layer = 20
	add_to_group("inventory_ui")
	_build_styles()
	_apply_chrome_and_layout()
	_setup_player_portrait()
	_root.visible = false
	Game.inventory.changed.connect(_refresh)
	Game.inventory.selection_changed.connect(_on_selection)
	Game.inventory.mail_changed.connect(_on_mail_changed)
	Game.inventory.wallet_changed.connect(func(_a: int) -> void: _refresh())
	Game.inventory.equipment_changed.connect(func(_id: StringName) -> void: _refresh())
	_refresh()


func _apply_chrome_and_layout() -> void:
	InventoryChrome.clear_cache()
	var catalog: Dictionary = InventoryChrome.load_catalog()
	var bake_w: float = float(catalog.get("bake_size", [960, 720])[0])
	var bake_h: float = float(catalog.get("bake_size", [960, 720])[1])
	_layout_scale = DISPLAY_SCALE
	_shell_stack.custom_minimum_size = Vector2(bake_w, bake_h) * _layout_scale

	var shell_tex: Texture2D = InventoryChrome.load_tex("window_shell")
	if shell_tex != null:
		_window_shell.texture = shell_tex
		_shell_shadow.texture = shell_tex
		_window_shell.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_window_shell.visible = true
	elif _hint != null:
		_hint.text = "Run: python3 tools/build_assets.py --step convert --kind inventory-ui"

	_set_tex(_items_label, "items_label")
	_set_tex(_letters_label, "letters_label")
	_set_tex(_bells_label, "bells_label")
	_set_tex(_portrait_frame, "portrait_frame")
	_set_tex(_town_bar, "name_bar")
	_set_tex(_player_bar, "name_bar")
	_tex_letter = InventoryChrome.load_tex("letter")
	_tex_letter_present = InventoryChrome.load_tex("letter_present")
	if _tex_letter == null:
		_tex_letter = InventoryChrome.load_tex("letter_envelope")

	## Side tabs: fish/bug use ACHD discs; pencil/face stay custom on colored circles.
	_set_tex(_tab_axe_icon, "tab_pencil")
	if _tab_axe_icon.texture == null:
		_set_tex(_tab_axe_icon, "tab_axe")
	_set_tex(_tab_fish_icon, "tab_fish")
	_set_tex(_tab_scoop_icon, "tab_face")
	if _tab_scoop_icon.texture == null:
		_set_tex(_tab_scoop_icon, "tab_scoop")
	_set_tex(_tab_bug_icon, "tab_bug")
	_style_tabs_as_discs()

	_place_catalog_chrome(catalog)
	_rebuild_slots(catalog)
	_place_tabs()
	_place_detail(catalog)


func _setup_player_portrait() -> void:
	if _portrait_ready or _portrait_viewport == null:
		return
	_portrait_ready = true
	_portrait_viewport.transparent_bg = true
	_portrait_viewport.own_world_3d = true
	_portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_portrait_viewport.size = Vector2i(160, 160)

	var world := Node3D.new()
	world.name = "PortraitWorld"
	_portrait_viewport.add_child(world)

	## Light matches `mSM_change_view` Lights0 (warm key from above-front).
	var light := DirectionalLight3D.new()
	light.light_color = Color(1.0, 1.0, 0.96)
	light.light_energy = 1.2
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	world.add_child(light)

	var fill := OmniLight3D.new()
	fill.light_color = Color(0.85, 0.8, 0.8)
	fill.light_energy = 0.25
	fill.omni_range = 8.0
	fill.position = Vector3(-0.8, 1.4, 1.6)
	world.add_child(fill)

	## `mIV_set_player` → `mSM_change_view(330, 25, …, angle=0x900, 256²)`.
	## Distances are post-`Matrix_scale(0.01)` GX (= actor world GX) → meters via GX_TO_METERS.
	## FOV 20° when width==256; elev = 0x900 short-angle ≈ 12.656°.
	var look_y: float = 25.0 * FieldCatalog.GX_TO_METERS
	var eye_dist: float = 330.0 * FieldCatalog.GX_TO_METERS
	var elev: float = deg_to_rad(360.0 * float(0x900) / 65536.0)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 20.0
	cam.position = Vector3(0.0, look_y + eye_dist * sin(elev), eye_dist * cos(elev))
	world.add_child(cam)
	cam.look_at(Vector3(0.0, look_y, 0.0), Vector3.UP)

	if not ResourceLoader.exists(PLAYER_GLB):
		return
	var packed: PackedScene = load(PLAYER_GLB) as PackedScene
	if packed == null:
		return
	var body: Node = packed.instantiate()
	if not (body is Node3D):
		body.queue_free()
		return
	_portrait_pivot = body as Node3D
	world.add_child(_portrait_pivot)
	GeneratedVisual.apply_actor_scale(_portrait_pivot, &"boy_1")
	GeneratedVisual.apply_preview_materials(_portrait_pivot)
	GeneratedVisual.stop_autoplay_keep_rest(_portrait_pivot)
	## Decomp: identity model Y under the 0.01 scale — face the +Z eye.
	_portrait_pivot.rotation.y = 0.0
	_portrait_pivot.position = Vector3.ZERO
	_portrait_anim = GeneratedVisual.find_animation_player(_portrait_pivot)
	_sync_portrait_equipment(true)


## Mirror field equipment: bind held tool mesh + hold/wait pose (`mIV_get_player_item_anime_id`).
func _sync_portrait_equipment(force: bool = false) -> void:
	if _portrait_pivot == null:
		return
	var eq_id: StringName = &""
	if Game.inventory != null:
		eq_id = Game.inventory.equipment_id
	if not force and eq_id == _portrait_equipment_id:
		return
	_portrait_equipment_id = eq_id
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_portrait_pivot)
	HeldTool.unbind(skeleton)
	var hold_clip := "ply_1_wait1"
	var tool_hold: StringName = &""
	var tool: ToolData = ItemCatalog.get_item(eq_id) as ToolData
	if tool != null and tool.visual_id != &"":
		HeldTool.bind(skeleton, tool.visual_id)
		if tool.hold_anim != &"":
			hold_clip = String(tool.hold_anim)
		tool_hold = tool.visual_hold_anim
		HeldTool.play(skeleton, tool_hold, true)
	_play_portrait_clip(hold_clip)


func _play_portrait_clip(suffix: String) -> void:
	if _portrait_anim == null or suffix.is_empty():
		return
	var clip := _resolve_portrait_clip(suffix)
	if clip.is_empty():
		clip = _resolve_portrait_clip("ply_1_wait1")
	if clip.is_empty():
		return
	var animation: Animation = _portrait_anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
	_portrait_anim.play(clip)


func _resolve_portrait_clip(suffix: String) -> String:
	if _portrait_anim == null or suffix.is_empty():
		return ""
	if _portrait_anim.has_animation(suffix):
		return suffix
	for anim_name: String in _portrait_anim.get_animation_list():
		if anim_name.ends_with("/" + suffix) or anim_name.ends_with(suffix):
			return anim_name
	return ""


func _set_tex(node: TextureRect, name: String) -> void:
	if node == null:
		return
	var tex: Texture2D = InventoryChrome.load_tex(name)
	if tex != null:
		node.texture = tex
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		node.visible = true
	else:
		node.visible = node.texture != null


func _px_rect(entry: Variant) -> Rect2:
	if entry is Dictionary and entry.has("px"):
		var p: Dictionary = entry["px"]
		return Rect2(
			float(p.get("x", 0.0)) * _layout_scale,
			float(p.get("y", 0.0)) * _layout_scale,
			float(p.get("w", 0.0)) * _layout_scale,
			float(p.get("h", 0.0)) * _layout_scale
		)
	return Rect2()


func _place_rect(node: Control, rect: Rect2) -> void:
	if node == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	node.position = rect.position
	node.size = rect.size


func _place_catalog_chrome(catalog: Dictionary) -> void:
	var portrait: Rect2 = _px_rect(catalog.get("portrait", {}))
	_place_rect(_portrait_clip, portrait.grow(-2.0 * _layout_scale))
	## Soft radial sky behind the 3D player (WW portrait window).
	var bg: Texture2D = InventoryChrome.load_tex("portrait_bg")
	if bg != null and _portrait_clip != null:
		var style := StyleBoxTexture.new()
		style.texture = bg
		_portrait_clip.add_theme_stylebox_override("panel", style)
	_place_rect(_portrait_frame, portrait)
	_place_rect(_items_label, _px_rect(catalog.get("items_label", {})))
	_place_rect(_letters_label, _px_rect(catalog.get("letters_label", {})))
	_place_rect(_bells_label, _px_rect(catalog.get("bells_label", {})))

	var bells: Rect2 = _px_rect(catalog.get("bells_frame", {}))
	## Wallet pill is wider than the raw suuji frame — match the WW capsule.
	var pill := Rect2(
		bells.position.x - 10.0 * _layout_scale,
		bells.position.y - 2.0 * _layout_scale,
		maxi(bells.size.x, 120.0 * _layout_scale),
		maxi(bells.size.y, 36.0 * _layout_scale)
	)
	_place_rect(_bells_pill, pill)

	if portrait.size.x > 0.0:
		var name_x: float = portrait.end.x + 10.0 * _layout_scale
		var name_w: float = 150.0 * _layout_scale
		_town_name.position = Vector2(name_x, portrait.position.y + 4.0 * _layout_scale)
		_town_name.size = Vector2(name_w, 24.0 * _layout_scale)
		_town_bar.position = Vector2(name_x + 8.0 * _layout_scale, _town_name.position.y + 22.0 * _layout_scale)
		_town_bar.size = Vector2(name_w - 16.0 * _layout_scale, 10.0 * _layout_scale)
		_player_name.position = Vector2(name_x, _town_bar.position.y + 14.0 * _layout_scale)
		_player_name.size = Vector2(name_w, 24.0 * _layout_scale)
		_player_bar.position = Vector2(name_x + 8.0 * _layout_scale, _player_name.position.y + 22.0 * _layout_scale)
		_player_bar.size = Vector2(name_w - 16.0 * _layout_scale, 10.0 * _layout_scale)


func _style_tabs_as_discs() -> void:
	## Drop square panel chrome — icons (or a circular StyleBox) form the tab.
	var empty := StyleBoxEmpty.new()
	for panel: PanelContainer in [_tab_pencil, _tab_fish, _tab_face, _tab_bug]:
		if panel == null:
			continue
		panel.add_theme_stylebox_override("panel", empty)
	## Custom pencil/face sprites lack a disc — wrap them in a colored circle.
	_ensure_disc_backdrop(_tab_pencil, Color(1.0, 0.85, 0.05, 1.0), _tab_axe_icon)
	_ensure_disc_backdrop(_tab_face, Color(0.45, 0.45, 0.5, 1.0), _tab_scoop_icon)


func _ensure_disc_backdrop(panel: PanelContainer, color: Color, icon: TextureRect) -> void:
	if panel == null or icon == null:
		return
	## Generated fish/bug already paint their own disc; only pad custom 32×32 sprites.
	var tex: Texture2D = icon.texture
	if tex != null and tex.get_width() >= 64:
		return
	var disc := StyleBoxFlat.new()
	disc.bg_color = color
	disc.set_corner_radius_all(999)
	disc.content_margin_left = 8
	disc.content_margin_top = 8
	disc.content_margin_right = 8
	disc.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", disc)


func _place_tabs() -> void:
	## Organic WW tabs: round discs peeking past the scalloped paper edge.
	var tab: float = 58.0 * _layout_scale
	var h: float = _shell_stack.custom_minimum_size.y
	var w: float = _shell_stack.custom_minimum_size.x
	_place_rect(_tab_pencil, Rect2(Vector2(-tab * 0.55, h * 0.42), Vector2(tab, tab)))
	_place_rect(_tab_fish, Rect2(Vector2(w - tab * 0.45, h * 0.24), Vector2(tab, tab)))
	_place_rect(_tab_face, Rect2(Vector2(w - tab * 0.45, h * 0.40), Vector2(tab, tab)))
	_place_rect(_tab_bug, Rect2(Vector2(w - tab * 0.45, h * 0.56), Vector2(tab, tab)))
	for icon: TextureRect in [_tab_axe_icon, _tab_fish_icon, _tab_scoop_icon, _tab_bug_icon]:
		if icon != null:
			icon.custom_minimum_size = Vector2(tab * 0.78, tab * 0.78)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


func _place_detail(catalog: Dictionary) -> void:
	var items: Array = catalog.get("items", [])
	var bottom: float = 0.0
	var left: float = 40.0 * _layout_scale
	for entry: Variant in items:
		var r: Rect2 = _px_rect(entry)
		bottom = maxf(bottom, r.end.y)
		if int(entry.get("i", 0)) == 0:
			left = r.position.x
	_detail.position = Vector2(left, bottom + 6.0 * _layout_scale)
	_detail.size = Vector2(340.0 * _layout_scale, 100.0 * _layout_scale)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_tag_mode = false
	_focus_mail = false
	_root.visible = true
	if _portrait_viewport != null:
		_portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Game.inventory.clear_hand()
	_sync_portrait_equipment(true)
	_refresh()
	get_tree().paused = false


func close() -> void:
	if not _open:
		return
	_open = false
	_tag_mode = false
	_focus_mail = false
	_root.visible = false
	if _portrait_viewport != null:
		_portrait_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Game.inventory.clear_hand()
	_refresh()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func _build_styles() -> void:
	var item_tex: Texture2D = InventoryChrome.load_tex("slot_item")
	var letter_tex: Texture2D = InventoryChrome.load_tex("slot_letter")
	if item_tex != null:
		_style_item = _tex_style(item_tex)
		_style_item_sel = _tex_style(item_tex, 1.15)
	else:
		_style_item = _circle_style(COL_ITEM_FILL, COL_ITEM_RING, 4)
		_style_item_sel = _circle_style(COL_ITEM_FILL.lightened(0.12), COL_ITEM_RING_SEL, 5)
	if letter_tex != null:
		_style_mail = _tex_style(letter_tex)
		_style_mail_sel = _tex_style(letter_tex, 1.15)
		_style_mail_empty = _tex_style(letter_tex, 1.0, Color(1, 0.7, 0.65, 1))
	else:
		_style_mail = _circle_style(COL_MAIL_FILL, COL_MAIL_RING, 4)
		_style_mail_sel = _circle_style(COL_MAIL_FILL.lightened(0.12), COL_MAIL_RING_SEL, 5)
		_style_mail_empty = _circle_style(COL_MAIL_EMPTY, COL_MAIL_RING, 4)


func _tex_style(tex: Texture2D, scale: float = 1.0, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.modulate_color = modulate
	var pad: float = 1.0 * scale
	s.texture_margin_left = pad
	s.texture_margin_top = pad
	s.texture_margin_right = pad
	s.texture_margin_bottom = pad
	s.content_margin_left = 8
	s.content_margin_top = 8
	s.content_margin_right = 8
	s.content_margin_bottom = 8
	return s


func _circle_style(fill: Color, ring: Color, border: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = ring
	s.set_border_width_all(border)
	s.set_corner_radius_all(999)
	s.content_margin_left = 4
	s.content_margin_top = 4
	s.content_margin_right = 4
	s.content_margin_bottom = 4
	return s


func _rebuild_slots(catalog: Dictionary) -> void:
	for btn: Button in _slot_buttons:
		btn.queue_free()
	for btn: Button in _mail_buttons:
		btn.queue_free()
	_slot_buttons.clear()
	_mail_buttons.clear()
	_build_item_slots(catalog)
	_build_mail_slots(catalog)


func _build_item_slots(catalog: Dictionary) -> void:
	var entries: Array = catalog.get("items", [])
	if entries.is_empty():
		for i: int in Inventory.POCKET_SLOTS:
			var btn := _make_slot_button(Vector2(48, 48), _style_item)
			btn.position = Vector2(80 + (i % 5) * 56, 260 + int(i / 5) * 56) * _layout_scale
			btn.pressed.connect(_on_item_pressed.bind(i))
			_slot_layer.add_child(btn)
			_slot_buttons.append(btn)
		return
	for entry: Variant in entries:
		var i: int = int(entry.get("i", 0))
		var rect: Rect2 = _px_rect(entry)
		var btn := _make_slot_button(rect.size, _style_item)
		btn.position = rect.position
		btn.size = rect.size
		btn.pressed.connect(_on_item_pressed.bind(i))
		_slot_layer.add_child(btn)
		_slot_buttons.append(btn)


func _build_mail_slots(catalog: Dictionary) -> void:
	var entries: Array = catalog.get("mail", [])
	if entries.is_empty():
		for i: int in Inventory.MAIL_SLOTS:
			var btn := _make_slot_button(Vector2(40, 40), _style_mail_empty)
			btn.position = Vector2(520 + (i % 2) * 48, 120 + int(i / 2) * 48) * _layout_scale
			btn.pressed.connect(_on_mail_pressed.bind(i))
			_slot_layer.add_child(btn)
			_mail_buttons.append(btn)
		return
	for entry: Variant in entries:
		var i: int = int(entry.get("i", 0))
		var rect: Rect2 = _px_rect(entry)
		var btn := _make_slot_button(rect.size, _style_mail_empty)
		btn.position = rect.position
		btn.size = rect.size
		btn.pressed.connect(_on_mail_pressed.bind(i))
		_slot_layer.add_child(btn)
		_mail_buttons.append(btn)


func _make_slot_button(min_size: Vector2, style: StyleBox) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_text = true
	btn.expand_icon = true
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.add_theme_stylebox_override("focus", style)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.95))
	btn.add_theme_font_size_override("font_size", 11)
	return btn


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
		var map_ui: Node = get_tree().get_first_node_in_group("map_ui") if get_tree() != null else null
		if map_ui != null and map_ui.has_method("is_open") and bool(map_ui.call("is_open")):
			get_viewport().set_input_as_handled()
			return
		var console: Node = get_tree().get_first_node_in_group("debug_console_ui") if get_tree() != null else null
		if console != null and console.has_method("is_open") and bool(console.call("is_open")):
			get_viewport().set_input_as_handled()
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event.is_action_pressed("ui_focus_next") or (
		event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB
	):
		_focus_mail = not _focus_mail
		_tag_mode = false
		_refresh()
		get_viewport().set_input_as_handled()
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
		if _focus_mail:
			Game.inventory.move_mail_cursor(-1, 0)
		else:
			Game.inventory.move_cursor(-1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		if _focus_mail:
			Game.inventory.move_mail_cursor(1, 0)
		else:
			Game.inventory.move_cursor(1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		if _focus_mail:
			Game.inventory.move_mail_cursor(0, -1)
		else:
			Game.inventory.move_cursor(0, -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		if _focus_mail:
			Game.inventory.move_mail_cursor(0, 1)
		else:
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


func _on_item_pressed(index: int) -> void:
	if not _open:
		return
	_focus_mail = false
	Game.inventory.select(index)
	_activate_cursor()


func _on_mail_pressed(index: int) -> void:
	if not _open:
		return
	_focus_mail = true
	Game.inventory.select_mail(index)
	_activate_cursor()


func _on_selection(_index: int) -> void:
	_tag_mode = false
	_refresh()


func _on_mail_changed() -> void:
	if _focus_mail:
		_tag_mode = false
	_refresh()


func _activate_cursor() -> void:
	if _focus_mail:
		_activate_mail_cursor()
		return
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


func _activate_mail_cursor() -> void:
	var inv: Inventory = Game.inventory
	var idx: int = inv.selected_mail_index
	var mail: MailData = inv.mail_at(idx)
	_tag_choices = PackedStringArray()
	if mail == null or mail.is_empty():
		_tag_choices.append("Write")
	else:
		_tag_choices.append("Discard")
	_tag_mode = true
	_tag_index = 0
	_refresh()


func _run_tag(tag: String) -> void:
	if _focus_mail:
		_run_mail_tag(tag)
		return
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


func _run_mail_tag(tag: String) -> void:
	var inv: Inventory = Game.inventory
	var idx: int = inv.selected_mail_index
	match tag:
		"Write":
			close()
			_open_write_letter()
		"Discard":
			inv.remove_mail(idx)
			Game.post_notice("Discarded letter")
		_:
			pass
	_tag_mode = false
	_refresh()


func _open_write_letter() -> void:
	var data: DialogueData = PostUse.write_letter_conversation()
	if data == null:
		return
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui == null or not ui.has_method("play"):
		PostUse.write_letter(&"filbert", 0)
		return
	var ctx: DialogueContext = DialogueContext.from_game()
	ui.call("play", data, ctx)


func _drop_selected() -> void:
	var inv: Inventory = Game.inventory
	var removed: InventoryItem = inv.drop_slot(inv.selected_index, 1)
	if removed.is_empty():
		return
	var data: ItemData = ItemCatalog.get_item(removed.item_id)
	if data == null:
		return
	close()
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
	var land: Vector3 = player.global_position + forward * 1.1
	var layout: Variant = world.get("layout")
	var grid: Variant = world.get("grid")
	if layout is WorldData and grid is WorldGrid:
		land.y = FieldCollision.ground_y_at(
			layout as WorldData, grid as WorldGrid, land, FieldCollision.FG_GROUND_DIST
		)
	else:
		land.y = player.global_position.y + FieldCatalog.GX_TO_METERS
	var start: Vector3 = player.global_position + Vector3(0.0, 50.0 * FieldCatalog.GX_TO_METERS, 0.0)
	if pickup.has_method("begin_fall"):
		pickup.call("begin_fall", start, land, 0.55)
	else:
		pickup.global_position = land
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
	if _player_name != null:
		_player_name.text = Game.player_name
	if _town_name != null:
		_town_name.text = Game.town_name
	_wallet.text = _format_bells(inv.wallet)
	var eq: ItemData = ItemCatalog.get_item(inv.equipment_id)
	_equip.text = "Held: %s" % (eq.display_name if eq != null else "—")
	_sync_portrait_equipment()
	_refresh_items(inv)
	_refresh_mail(inv)
	if _focus_mail:
		_refresh_mail_detail(inv)
		_refresh_tags_hint("X close  Tab items  Arrows move  E write/discard")
	else:
		_refresh_item_detail(inv)
		_refresh_tags_hint("X close  Tab letters  Arrows move  E tags")


func _format_bells(amount: int) -> String:
	var s: String = str(maxi(amount, 0))
	var out: String = ""
	var i: int = s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	return s.substr(0, i) + out


func _refresh_items(inv: Inventory) -> void:
	for i: int in _slot_buttons.size():
		var btn: Button = _slot_buttons[i]
		var slot: InventorySlot = inv.slot_at(i)
		var selected: bool = (not _focus_mail) and i == inv.selected_index
		var in_hand: bool = i == inv.hand_index
		var style: StyleBox = _style_item_sel if selected else _style_item
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("disabled", style)
		btn.add_theme_stylebox_override("focus", style)
		if slot == null or slot.is_empty():
			btn.text = ""
			btn.icon = null
			btn.modulate = Color(1, 1, 1, 1)
		else:
			var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
			var label: String = ""
			if slot.item.count > 1:
				label = "×%d" % slot.item.count
			btn.text = label
			if data != null and data.icon != null:
				btn.icon = data.icon
				btn.expand_icon = true
			else:
				btn.icon = null
				if data != null:
					btn.text = data.display_name.substr(0, mini(5, data.display_name.length()))
					if slot.item.count > 1:
						btn.text = "%s×%d" % [btn.text, slot.item.count]
			var tint: Color = data.icon_color if data != null else Color.WHITE
			if in_hand:
				btn.modulate = tint.darkened(0.25)
			else:
				btn.modulate = tint
		btn.disabled = false


func _refresh_mail(inv: Inventory) -> void:
	for i: int in _mail_buttons.size():
		var btn: Button = _mail_buttons[i]
		var mail: MailData = inv.mail_at(i)
		var selected: bool = _focus_mail and i == inv.selected_mail_index
		var empty: bool = mail == null or mail.is_empty()
		var style: StyleBox
		if empty:
			style = _style_mail_sel if selected else _style_mail_empty
		else:
			style = _style_mail_sel if selected else _style_mail
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("disabled", style)
		btn.add_theme_stylebox_override("focus", style)
		btn.text = ""
		if empty:
			btn.icon = null
			btn.modulate = Color(1, 1, 1, 1)
		else:
			var has_present: bool = mail.present_item_id != &""
			btn.icon = _tex_letter_present if has_present and _tex_letter_present != null else _tex_letter
			btn.expand_icon = true
			btn.modulate = Color(1, 1, 1, 1)
		btn.disabled = false


func _refresh_item_detail(inv: Inventory) -> void:
	var sel: InventorySlot = inv.selected_slot()
	if sel == null or sel.is_empty():
		_name.text = ""
		_desc.text = ""
		return
	var data: ItemData = ItemCatalog.get_item(sel.item.item_id)
	if data == null:
		_name.text = String(sel.item.item_id)
		_desc.text = ""
		return
	_name.text = data.display_name
	_desc.text = data.description
	if sel.item.condition == InventoryItem.Condition.PRESENT:
		_name.text = "Present"
		_desc.text = "A wrapped gift."
	elif sel.item.condition == InventoryItem.Condition.QUEST:
		_name.text = "%s (quest)" % data.display_name


func _refresh_mail_detail(inv: Inventory) -> void:
	var sel: MailData = inv.mail_at(inv.selected_mail_index)
	if sel == null or sel.is_empty():
		_name.text = "Empty"
		_desc.text = "Write a letter for the post office."
	else:
		_name.text = sel.label()
		_desc.text = sel.preview()


func _refresh_tags_hint(default_hint: String) -> void:
	if _tag_mode and not _tag_choices.is_empty():
		var lines: PackedStringArray = []
		for i: int in _tag_choices.size():
			var prefix: String = ">" if i == _tag_index else " "
			lines.append("%s %s" % [prefix, _tag_choices[i]])
		_tags.text = "\n".join(lines)
		_hint.text = "↑↓ choose  E confirm  Esc back"
	else:
		_tags.text = ""
		_hint.text = default_hint

extends CanvasLayer

## Pocket submenu. Scene-first layout + textures in `inventory_overlay.tscn`.
## Runtime fills missing chrome via `InventoryChrome` and wires pocket/mail buttons.
## Top-left circle shows a live 3D player preview (`mIV_set_player`).
## Selection cursor is skinned `hnd.glb` (`m_hand_ovl` / `hnd_sasu`).

const ITEM_SCENE := "res://scenes/world/item_pickup.tscn"
const PLAYER_GLB := "res://assets/generated/characters/player/boy_1.glb"
const HND_GLB := "res://assets/generated/characters/other/hnd.glb"
const HAND_SIZE := 100.0
## The ROM UI font (`FONT_nes_tex_font1`, `mFont_SetLineStrings`), same as the
## dialogue window; Rodin `.otf` is the vector fallback.
const UI_FONT_PATHS := [
	"res://assets/generated/ui/message/msg_font.fnt",
	"res://assets/custom/ui/message/msg_font.fnt",
	"res://assets/fonts/fot_rodin_pro_db.otf",
]

## `mIV_PAGE_*` (`m_inventory_ovl.c`): the three horizontally-scrolling pages.
## FISH ← POCKETS → BUG, flipped with the two right-edge folder tabs or `[` `]`.
enum SideTab { FISH, POCKETS, BUG }
const PAGE_ORDER: Array = [SideTab.FISH, SideTab.POCKETS, SideTab.BUG]

## `mIV_ANIM_*` (`m_inventory_ovl.c`): the portrait player marches in place (WALK1)
## and reacts once to equipping (CHANGE1 + sparkles), eating (EAT1), or opening a
## collection page (CATCH1 hold), then falls back to WALK.
enum PortraitAnim { WALK, CHANGE, EAT, CATCH }
const PORTRAIT_CLIPS := {
	PortraitAnim.WALK: "ply_1_walk1",
	PortraitAnim.CHANGE: "ply_1_menu_change1",
	PortraitAnim.EAT: "ply_1_eat1",
	PortraitAnim.CATCH: "ply_1_menu_catch1",
}

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
@onready var _wallet: Label = %WalletLabel
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
@onready var _portrait_frame: TextureRect = %PortraitFrame
@onready var _portrait_viewport: SubViewport = %SubViewport
## Page tabs — style / position / glyphs are all authored in `inventory_overlay.tscn`
## (nodes `TabFish` / `TabPockets` / `TabBug` / `TabDesign` under `ChromeLayer`).
@onready var _tab_fish: Panel = %TabFish
@onready var _tab_pockets: Panel = %TabPockets
@onready var _tab_bug: Panel = %TabBug
@onready var _tab_design: Panel = %TabDesign

var _open: bool = false
var _focus_mail: bool = false
var _side_tab: SideTab = SideTab.POCKETS
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
var _portrait_ready: bool = false
var _portrait_pivot: Node3D = null
var _portrait_anim: AnimationPlayer = null
var _portrait_equipment_id: StringName = &""
var _portrait_rest: PortraitAnim = PortraitAnim.WALK
var _hand_root: Control = null
var _hand_viewport: SubViewport = null
var _hand_anim: AnimationPlayer = null
var _hand_tween: Tween = null
var _hand_ready: bool = false
var _open_tween: Tween = null
## Fish / insect encyclopedia page (`mIV_set_collect_dl`): one 8×5 grid, reused.
var _collect_root: Control = null
var _collect_slots: Array[TextureRect] = []
var _collect_title: Label = null
var _collect_count: Label = null
var _pocket_chrome: Array[CanvasItem] = []
## `m_tag_ovl` verb window (`sen_itemw_*`): frame + shadow + pointer, verbs stacked.
var _tag_popup: Control = null
var _tag_frame: PanelContainer = null
var _tag_rows: VBoxContainer = null
var _tag_arrow: Polygon2D = null
var _ui_font: Font = null


func _ready() -> void:
	layer = 20
	add_to_group("inventory_ui")
	_load_ui_font()
	_wire_slot_buttons()
	_wire_side_tabs()
	_build_styles()
	_apply_chrome()
	_build_encyclopedia_grid()
	_build_tag_popup()
	_setup_player_portrait()
	_setup_hand_cursor()
	## The GC pockets screen has no bottom text block — the verb window and the
	## slot cards carry everything. Hide the invented name/desc/hint labels.
	var detail: Control = _shell_stack.get_node_or_null("Detail") as Control
	if detail != null:
		detail.visible = false
	## All live text uses the ROM font (`mFont`), not the .tscn's Rodin fallback.
	## `mIV_SetLineStrings_centering`: land name scale 0.875, player name 0.9375 of
	## an ~18 px cell -> ~16/17 px; wallet digits sit in the `suujiwaku` box.
	if _player_name != null:
		_font_label(_player_name, 17, Color(0.27, 0.27, 0.39))
	if _town_name != null:
		_font_label(_town_name, 16, Color(0.23, 0.31, 0.43))
	if _wallet != null:
		_font_label(_wallet, 18, _wallet.get_theme_color("font_color"))
	_root.visible = false
	Game.inventory.changed.connect(_refresh)
	Game.inventory.selection_changed.connect(_on_selection)
	Game.inventory.mail_changed.connect(_on_mail_changed)
	Game.inventory.wallet_changed.connect(func(_a: int) -> void: _refresh())
	Game.inventory.equipment_changed.connect(func(_id: StringName) -> void: _refresh())
	_refresh()


func _load_ui_font() -> void:
	for path: String in UI_FONT_PATHS:
		if ResourceLoader.exists(path):
			_ui_font = load(path) as Font
			if _ui_font != null:
				return


func _font_label(lbl: Label, px: int, col: Color) -> void:
	if _ui_font != null:
		lbl.add_theme_font_override("font", _ui_font)
	lbl.add_theme_font_size_override("font_size", px)
	lbl.add_theme_color_override("font_color", col)


func _wire_slot_buttons() -> void:
	_slot_buttons.clear()
	_mail_buttons.clear()
	for i: int in Inventory.POCKET_SLOTS:
		## `%%` → literal `%` for unique-name paths (`%ItemSlot0`); bare `%I…` breaks formatting.
		var btn: Button = get_node_or_null("%%ItemSlot%d" % i) as Button
		if btn == null:
			continue
		btn.pressed.connect(_on_item_pressed.bind(i))
		btn.add_theme_constant_override("icon_max_width", 52)
		_ensure_slot_icon_rect(btn)
		_slot_buttons.append(btn)
	for i: int in Inventory.MAIL_SLOTS:
		var btn: Button = get_node_or_null("%%MailSlot%d" % i) as Button
		if btn == null:
			continue
		btn.pressed.connect(_on_mail_pressed.bind(i))
		btn.add_theme_constant_override("icon_max_width", 52)
		_ensure_slot_icon_rect(btn)
		_mail_buttons.append(btn)


func _ensure_slot_icon_rect(btn: Button) -> void:
	## Button.icon is easy to lose under theme/stylebox layout; draw the picture explicitly.
	if btn.get_node_or_null("ItemIcon") != null:
		return
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 10
	icon.offset_top = 10
	icon.offset_right = -10
	icon.offset_bottom = -10
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.visible = false
	btn.add_child(icon)


func _set_slot_picture(btn: Button, tex: Texture2D) -> void:
	btn.icon = null
	var icon: TextureRect = btn.get_node_or_null("ItemIcon") as TextureRect
	if icon == null:
		_ensure_slot_icon_rect(btn)
		icon = btn.get_node_or_null("ItemIcon") as TextureRect
	if icon == null:
		btn.icon = tex
		btn.expand_icon = true
		return
	icon.texture = tex
	icon.visible = tex != null


## Small "pull out" when a tab is the active page — toward the paper on the left
## tab, away on the right ones. Everything else about the tabs is in the .tscn.
const TAB_ACTIVE_NUDGE := 8.0

var _tab_home: Dictionary = {}


func _wire_side_tabs() -> void:
	if _slot_layer != null:
		_slot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mid: float = _shell_stack.custom_minimum_size.x * 0.5 if _shell_stack != null else 374.0
	for entry: Array in [
		[_tab_fish, SideTab.FISH], [_tab_pockets, SideTab.POCKETS],
		[_tab_bug, SideTab.BUG], [_tab_design, -1],
	]:
		var tab: Panel = entry[0]
		if tab == null:
			continue
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		if not tab.gui_input.is_connected(_on_side_tab_gui):
			tab.gui_input.connect(_on_side_tab_gui.bind(tab))
		## Home position + which way it slides when active (left tab -> right/into paper).
		_tab_home[tab] = {
			"pos": tab.position,
			"dir": TAB_ACTIVE_NUDGE if tab.position.x < mid else -TAB_ACTIVE_NUDGE,
			"page": entry[1],
		}


func _on_side_tab_gui(event: InputEvent, tab: Panel) -> void:
	if not _open:
		return
	var hit: bool = (
		(event is InputEventMouseButton and (event as InputEventMouseButton).pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	)
	if not hit:
		return
	get_viewport().set_input_as_handled()
	var page: int = _tab_home.get(tab, {}).get("page", SideTab.POCKETS)
	if page < 0:
		Audio.play_se(&"cursol")
		var list_ui: Node = get_tree().get_first_node_in_group("design_list_ui") if get_tree() != null else null
		if list_ui != null and list_ui.has_method("open"):
			list_ui.call("open", "manage", Callable())
		else:
			Game.post_notice("The design book isn't available here.")
	else:
		_select_side_tab(page)


func _cycle_side_tab(delta: int) -> void:
	var idx: int = PAGE_ORDER.find(_side_tab)
	if idx < 0:
		idx = PAGE_ORDER.find(SideTab.POCKETS)
	_select_side_tab(PAGE_ORDER[clampi(idx + delta, 0, PAGE_ORDER.size() - 1)])


func _select_side_tab(page: SideTab) -> void:
	if page == _side_tab:
		return
	_tag_mode = false
	_hide_tag_popup()
	_side_tab = page
	if page != SideTab.POCKETS:
		_focus_mail = false
	Audio.play_se(&"cursol")
	## `mIV_ANIM_CATCH` on a collection page; WALK back on the pockets.
	_set_portrait_anim(PortraitAnim.CATCH if page != SideTab.POCKETS else PortraitAnim.WALK)
	_show_page(page)
	_refresh()
	_update_hand_cursor(true)


func _apply_chrome() -> void:
	## Fill missing textures only — assigned `.tscn` textures stay editable in the editor.
	InventoryChrome.clear_cache()
	## Project default filter is nearest; shell / labels need linear for smooth scallops.
	for node: CanvasItem in [_window_shell, _shell_shadow, _items_label, _letters_label, _bells_label, _portrait_frame, _town_bar, _player_bar]:
		if node != null:
			node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if _window_shell.texture == null:
		var shell_tex: Texture2D = InventoryChrome.load_tex("window_shell")
		if shell_tex != null:
			_window_shell.texture = shell_tex
			_shell_shadow.texture = shell_tex
			_window_shell.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			_window_shell.visible = true
		elif _hint != null:
			_hint.text = "Run: python3 tools/build_assets.py --step convert --kind inventory-ui"
	elif _shell_shadow.texture == null:
		_shell_shadow.texture = _window_shell.texture

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

	## `mIV_set_player` → `mSM_change_view(330, 25, …, angle=0x900, 256²)`: FOV 20°,
	## eye 0x900 short-angle (~12.66°) above `y_lookAt`. `eye_dist` / `y_lookAt` are
	## set from the player AABB below so the framing matches whatever `actor_scale` is.
	var elev: float = deg_to_rad(360.0 * float(0x900) / 65536.0)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 20.0
	world.add_child(cam)

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
	_portrait_pivot.rotation.y = 0.0
	_portrait_pivot.position = Vector3.ZERO
	_portrait_anim = GeneratedVisual.find_animation_player(_portrait_pivot)
	_sync_portrait_equipment(true)

	## Frame head → mid-thigh in the circle (`inv_mwin_3Dma` window): the player fills
	## ~78% of the RT height, look-at at ~62% of body height.
	await get_tree().process_frame
	var aabb := _visual_aabb(_portrait_pivot)
	var ph: float = maxf(aabb.size.y, 0.1)
	var look_y: float = aabb.position.y + ph * 0.60
	var eye_dist: float = (ph / 0.70) / (2.0 * tan(deg_to_rad(10.0)))
	cam.position = Vector3(0.0, look_y + eye_dist * sin(elev), eye_dist * cos(elev))
	cam.look_at(Vector3(0.0, look_y, 0.0), Vector3.UP)


func _visual_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			merged = box
			first = false
		else:
			merged = merged.merge(box)
	return merged


func _setup_hand_cursor() -> void:
	## `m_hand_ovl`: skinned `cKF_bs_r_hnd` drawn over the active slot (`hnd_sasu` point).
	if _hand_ready or _slot_layer == null:
		return
	_hand_ready = true
	_hand_root = Control.new()
	_hand_root.name = "HandCursor"
	_hand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_root.z_index = 30
	_hand_root.size = Vector2(HAND_SIZE, HAND_SIZE)
	_hand_root.clip_contents = false
	_hand_root.visible = false
	## Parent to shell (not SlotLayer) so the tip can overhang slot edges without clipping.
	var hand_host: Control = _shell_stack if _shell_stack != null else _slot_layer
	hand_host.clip_contents = false
	hand_host.add_child(_hand_root)

	var host := SubViewportContainer.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.stretch = true
	host.clip_contents = false
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hand_root.add_child(host)

	_hand_viewport = SubViewport.new()
	_hand_viewport.transparent_bg = true
	_hand_viewport.own_world_3d = true
	## Roomy RT so the whole hand + cuff fits the frustum (was cropping the wrist).
	_hand_viewport.size = Vector2i(224, 224)
	_hand_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(_hand_viewport)

	var world := Node3D.new()
	world.name = "HandWorld"
	_hand_viewport.add_child(world)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.15
	light.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	world.add_child(light)

	var cam := Camera3D.new()
	cam.current = true
	## Pull back + a touch wider so the whole hand (finger to cuff) sits inside the RT.
	cam.fov = 38.0
	cam.position = Vector3(0.0, 0.5, 4.6)
	world.add_child(cam)
	cam.look_at(Vector3(0.05, 0.28, 0.0), Vector3.UP)

	if not ResourceLoader.exists(HND_GLB):
		return
	var packed: PackedScene = load(HND_GLB) as PackedScene
	if packed == null:
		return
	var body: Node = packed.instantiate()
	if not (body is Node3D):
		body.queue_free()
		return
	var pivot := body as Node3D
	world.add_child(pivot)
	GeneratedVisual.apply_actor_scale(pivot, &"hnd")
	GeneratedVisual.apply_preview_materials(pivot)
	GeneratedVisual.stop_autoplay_keep_rest(pivot)
	pivot.scale *= 1
	pivot.rotation_degrees = Vector3(-30.0, -113.0, 0.0)
	_hand_anim = GeneratedVisual.find_animation_player(pivot)
	_play_hand_clip("hnd_sasu", true)


func _play_hand_clip(suffix: String, loop: bool) -> void:
	if _hand_anim == null or suffix.is_empty():
		return
	var clip := ""
	if _hand_anim.has_animation(suffix):
		clip = suffix
	else:
		for anim_name: String in _hand_anim.get_animation_list():
			if anim_name.ends_with(suffix) or suffix in anim_name:
				clip = anim_name
				break
	if clip.is_empty():
		return
	var animation: Animation = _hand_anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_hand_anim.play(clip)


func _selected_slot_button() -> Button:
	if _focus_mail:
		var mi: int = Game.inventory.selected_mail_index
		if mi >= 0 and mi < _mail_buttons.size():
			return _mail_buttons[mi]
	else:
		var ii: int = Game.inventory.selected_index
		if ii >= 0 and ii < _slot_buttons.size():
			return _slot_buttons[ii]
	return null


func _update_hand_cursor(animate: bool = true) -> void:
	if _hand_root == null:
		return
	var on_pockets: bool = _side_tab == SideTab.POCKETS
	var btn: Button = _selected_slot_button() if on_pockets else null
	if btn == null or not _open:
		_hand_root.visible = false
		if _hand_viewport != null:
			_hand_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_hand_root.visible = true
	if _hand_viewport != null:
		_hand_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	## Tip of `hnd_sasu` sits toward the lower-left of the viewport card.
	var slot_pos: Vector2 = btn.position
	if btn.get_parent() != null and _hand_root.get_parent() != null:
		slot_pos = _hand_root.get_parent().get_global_transform_with_canvas().affine_inverse() * (
			btn.get_global_transform_with_canvas().origin
		)
	## Finger tip aims near slot center; hand body sits slightly above so it isn't sunk.
	var target: Vector2 = (
		slot_pos + btn.size * Vector2(0.52, 0.28) - Vector2(HAND_SIZE * 0.3, HAND_SIZE * 0.55)
	)
	if animate and _hand_root.visible:
		if _hand_tween != null:
			_hand_tween.kill()
		_hand_tween = create_tween()
		_hand_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hand_tween.tween_property(_hand_root, "position", target, 0.12)
	else:
		_hand_root.position = target


## `mIV_set_collect_dl`: `{ 8, 5, mTG_collect_col_pos, mTG_collect_line_pos }` — one
## 8×5 grid for all 40 species, no in-page scroll. Built once, retargeted per page.
func _build_encyclopedia_grid() -> void:
	if _collect_root != null or _shell_stack == null:
		return
	_collect_root = Control.new()
	_collect_root.name = "EncyclopediaPage"
	_collect_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collect_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_collect_root.visible = false
	_shell_stack.add_child(_collect_root)

	const CELL := 46.0
	const SEP := 6
	var grid_w: float = 8.0 * CELL + 7.0 * float(SEP)
	var left: float = (_shell_stack.custom_minimum_size.x - grid_w) * 0.5
	var top: float = 174.0

	_collect_title = Label.new()
	_collect_title.position = Vector2(left, 96.0)
	_font_label(_collect_title, 26, Color(0.30, 0.24, 0.16))
	_collect_root.add_child(_collect_title)

	_collect_count = Label.new()
	_collect_count.position = Vector2(left, 132.0)
	_font_label(_collect_count, 16, Color(0.42, 0.34, 0.24))
	_collect_root.add_child(_collect_count)

	var grid := GridContainer.new()
	grid.columns = 8
	grid.name = "Grid"
	grid.position = Vector2(left, top)
	grid.add_theme_constant_override("h_separation", SEP)
	grid.add_theme_constant_override("v_separation", SEP)
	_collect_root.add_child(grid)

	var ring := StyleBoxFlat.new()
	ring.bg_color = Color(1.0, 0.99, 0.92, 0.45)
	ring.set_corner_radius_all(999)
	ring.set_border_width_all(2)
	ring.border_color = Color(0.66, 0.55, 0.38, 0.6)

	for i: int in EncyclopediaCatalog.COLLECT_NUM:
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(CELL, CELL)
		cell.add_theme_stylebox_override("panel", ring)
		grid.add_child(cell)
		var pic := TextureRect.new()
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 5)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(pic)
		_collect_slots.append(pic)


func _populate_encyclopedia(kind: StringName) -> void:
	if _collect_root == null:
		return
	var log: SpeciesLog = Game.species_log
	_collect_title.text = "Fish" if kind == &"fish" else "Insects"
	var have: int = log.page_count(kind) if log != null else 0
	_collect_count.text = "%d / %d" % [have, EncyclopediaCatalog.COLLECT_NUM]
	for slot: int in _collect_slots.size():
		var pic: TextureRect = _collect_slots[slot]
		var id: StringName = EncyclopediaCatalog.id_for(kind, slot)
		var caught: bool = log != null and log.has(id)
		pic.texture = InventoryChrome.load_tex(EncyclopediaCatalog.icon_for(kind, slot))
		## Caught: full colour `inv_mwin_NN` card. Uncaught: a dark silhouette.
		pic.modulate = Color.WHITE if caught else Color(0.05, 0.06, 0.09, 0.32)


## `m_tag_ovl` verb window: `sen_itemw_kage` shadow + `sen_itemw_wakuT` frame +
## `sen_itemw_yajirushi` pointer, verb strings stacked 16 px apart with a row cursor.
func _build_tag_popup() -> void:
	if _tag_popup != null or _shell_stack == null:
		return
	_tag_popup = Control.new()
	_tag_popup.name = "TagPopup"
	_tag_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_popup.z_index = 40
	_tag_popup.visible = false
	_shell_stack.add_child(_tag_popup)

	## Base at x=0 (flush to the frame edge), apex at x=-13 (points toward the slot).
	## `scale.x` flips it to point the other way when the window sits on the left.
	_tag_arrow = Polygon2D.new()
	_tag_arrow.color = Color(0.99, 0.96, 0.86, 1.0)
	_tag_arrow.polygon = PackedVector2Array([Vector2(1, -10), Vector2(-13, 0), Vector2(1, 10)])
	_tag_popup.add_child(_tag_arrow)

	_tag_frame = PanelContainer.new()
	_tag_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.99, 0.96, 0.86, 1.0)
	box.set_corner_radius_all(10)
	box.set_border_width_all(2)
	box.border_color = Color(0.62, 0.47, 0.30, 1.0)
	box.shadow_color = Color(0, 0, 0, 0.22)
	box.shadow_size = 5
	box.shadow_offset = Vector2(3, 4)
	box.content_margin_left = 16
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	_tag_frame.add_theme_stylebox_override("panel", box)
	_tag_popup.add_child(_tag_frame)

	_tag_rows = VBoxContainer.new()
	_tag_rows.add_theme_constant_override("separation", 3)
	_tag_frame.add_child(_tag_rows)


func _hide_tag_popup() -> void:
	if _tag_popup != null:
		_tag_popup.visible = false


## Verb list beside the selected slot. `mTG_set_tag_win`: the window sits to the item's
## right with a left-pointing arrow, flipping left when it would run off the paper.
func _show_tag_popup() -> void:
	if _tag_popup == null or _tag_choices.is_empty():
		_hide_tag_popup()
		return
	var btn: Button = _selected_slot_button()
	if btn == null:
		_hide_tag_popup()
		return
	for child: Node in _tag_rows.get_children():
		child.queue_free()
	var cursor := StyleBoxFlat.new()
	cursor.bg_color = Color(0.90, 0.55, 0.20, 0.30)
	cursor.set_corner_radius_all(5)
	cursor.content_margin_left = 6
	cursor.content_margin_right = 10
	cursor.content_margin_top = 1
	cursor.content_margin_bottom = 1
	var blank := StyleBoxEmpty.new()
	blank.content_margin_left = 6
	blank.content_margin_right = 10
	for i: int in _tag_choices.size():
		var row := Label.new()
		row.text = _tag_choices[i]
		var on: bool = i == _tag_index
		_font_label(row, 17, Color(0.12, 0.09, 0.05) if on else Color(0.46, 0.40, 0.32))
		row.add_theme_stylebox_override("normal", cursor if on else blank)
		_tag_rows.add_child(row)
	_tag_frame.reset_size()
	await get_tree().process_frame
	if _tag_popup == null or not _tag_mode:
		return
	var fsize: Vector2 = _tag_frame.get_combined_minimum_size()
	var slot_c: Vector2 = btn.position + btn.size * 0.5
	var gap: float = btn.size.x * 0.5 + 20.0
	var right: bool = slot_c.x + gap + fsize.x < _shell_stack.custom_minimum_size.x - 8.0
	var fx: float = (slot_c.x + gap) if right else (slot_c.x - gap - fsize.x)
	var fy: float = clampf(
		slot_c.y - fsize.y * 0.5, 12.0, _shell_stack.custom_minimum_size.y - fsize.y - 12.0
	)
	_tag_frame.position = Vector2(fx, fy)
	_tag_frame.size = fsize
	_tag_arrow.position = Vector2(fx if right else fx + fsize.x, slot_c.y)
	_tag_arrow.scale.x = 1.0 if right else -1.0
	_tag_popup.visible = true


## Toggle the pockets chrome (portrait / bells / labels / slots / mail) against the
## encyclopedia grid. `mIV_set_normal_dl` draws the former, `mIV_set_collect_dl` the latter.
func _show_page(page: SideTab) -> void:
	var pockets: bool = page == SideTab.POCKETS
	if _pocket_chrome.is_empty():
		for n: CanvasItem in [
			_slot_layer, _items_label, _letters_label, _bells_label, _portrait_frame,
			_town_bar, _player_bar, _town_name, _player_name,
		]:
			if n != null:
				_pocket_chrome.append(n)
	for n: CanvasItem in _pocket_chrome:
		n.visible = pockets
	var pc: Control = _portrait_viewport.get_parent() if _portrait_viewport != null else null
	if pc != null:
		pc.visible = pockets
	if _wallet != null and _wallet.get_parent() is CanvasItem:
		(_wallet.get_parent() as CanvasItem).visible = pockets
	if _hand_root != null:
		_hand_root.visible = pockets and _hand_root.visible
	if _collect_root != null:
		_collect_root.visible = not pockets
		if not pockets:
			_populate_encyclopedia(&"fish" if page == SideTab.FISH else &"insect")


func _refresh_side_tab_visuals() -> void:
	## Active page's tab brightens and slides out a touch from its authored home.
	for tab: Panel in _tab_home:
		var home: Dictionary = _tab_home[tab]
		var on: bool = int(home["page"]) == int(_side_tab)
		tab.position = home["pos"] + Vector2(float(home["dir"]) if on else 0.0, 0.0)
		tab.modulate = Color(1.12, 1.12, 1.12) if on else Color(0.86, 0.86, 0.86)


## Mirror field equipment: bind the held tool mesh; the portrait body keeps its
## `mIV_ANIM_*` clip (WALK by default) and the tool follows the hand joint.
func _sync_portrait_equipment(force: bool = false) -> void:
	if _portrait_pivot == null:
		return
	var eq_id: StringName = &""
	if Game.inventory != null:
		eq_id = Game.inventory.equipment_id
	if not force and eq_id == _portrait_equipment_id:
		return
	var equip_changed: bool = (not force) and eq_id != _portrait_equipment_id
	_portrait_equipment_id = eq_id
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_portrait_pivot)
	HeldTool.unbind(skeleton)
	var tool: ToolData = ItemCatalog.get_item(eq_id) as ToolData
	if tool != null and tool.visual_id != &"":
		HeldTool.bind(skeleton, tool.visual_id)
		HeldTool.play(skeleton, tool.visual_hold_anim, true)
	## `mIV_pl_check_anm_change`: an equip swap plays CHANGE1, everything else rests.
	if equip_changed:
		_set_portrait_anim(PortraitAnim.CHANGE)
	else:
		_set_portrait_anim(_portrait_rest)


## `mIV_ANIM_WALK` loops; CHANGE / EAT play once and fall back to the rest clip;
## CATCH holds while a collection page is open (`_portrait_rest`).
func _set_portrait_anim(state: PortraitAnim) -> void:
	if _portrait_anim == null:
		return
	if state == PortraitAnim.WALK or state == PortraitAnim.CATCH:
		_portrait_rest = state
	var clip := _resolve_portrait_clip(String(PORTRAIT_CLIPS.get(state, "ply_1_walk1")))
	if clip.is_empty():
		clip = _resolve_portrait_clip("ply_1_walk1")
	if clip.is_empty():
		return
	var looping: bool = state == PortraitAnim.WALK or state == PortraitAnim.CATCH
	var animation: Animation = _portrait_anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	_portrait_anim.play(clip)
	if not looping:
		if not _portrait_anim.animation_finished.is_connected(_on_portrait_react_done):
			_portrait_anim.animation_finished.connect(_on_portrait_react_done, CONNECT_ONE_SHOT)


func _on_portrait_react_done(_clip: StringName) -> void:
	_set_portrait_anim(_portrait_rest)


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
	if node == null or node.texture != null:
		return
	var tex: Texture2D = InventoryChrome.load_tex(name)
	if tex != null:
		node.texture = tex
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		node.visible = true
	else:
		node.visible = false


func is_open() -> bool:
	return _open


## Open straight to the Letters page (mailbox / "you've got mail").
func open_letters() -> void:
	open()
	if _open:
		_focus_mail = true
		_side_tab = SideTab.POCKETS
		Game.inventory.select_mail(0)
		_refresh()


func open() -> void:
	if _open:
		return
	_open = true
	_tag_mode = false
	_focus_mail = false
	_side_tab = SideTab.POCKETS
	_portrait_rest = PortraitAnim.WALK
	_show_page(SideTab.POCKETS)
	Audio.play_se(&"menu_pause")
	_root.visible = true
	_root.modulate = Color(1, 1, 1, 0)
	if _shell_stack != null:
		_shell_stack.scale = Vector2(0.94, 0.94)
		_shell_stack.pivot_offset = _shell_stack.size * 0.5
	if _portrait_viewport != null:
		_portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _hand_viewport != null:
		_hand_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Game.inventory.clear_hand()
	_sync_portrait_equipment(true)
	_play_hand_clip("hnd_sasu", true)
	_refresh()
	_update_hand_cursor(false)
	if _open_tween != null:
		_open_tween.kill()
	_open_tween = create_tween()
	_open_tween.set_parallel(true)
	_open_tween.tween_property(_root, "modulate:a", 1.0, 0.14)
	if _shell_stack != null:
		_open_tween.tween_property(_shell_stack, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(
			Tween.EASE_OUT
		)
	get_tree().paused = false


func close() -> void:
	if not _open:
		return
	Audio.play_se(&"menu_exit")
	_open = false
	_tag_mode = false
	_hide_tag_popup()
	_focus_mail = false
	_side_tab = SideTab.POCKETS
	## Closing the pockets during the intro payment without handing anything over is
	## Nook's "pay it all back" nag (`aNRG_menu_close_wait_talk_proc` empty branch).
	if Game.intro_payment_pending:
		Game.notify_intro_payment_declined()
	if Game.museum_donate_pending:
		Game.cancel_museum_donation()
	if _hand_root != null:
		_hand_root.visible = false
	if _portrait_viewport != null:
		_portrait_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _hand_viewport != null:
		_hand_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Game.inventory.clear_hand()
	_root.visible = false
	_root.modulate = Color.WHITE
	if _shell_stack != null:
		_shell_stack.scale = Vector2.ONE
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
		## Tab = items ↔ letters (pencil / face). Shift+Tab / [ ] cycle all four side tabs.
		var shift: bool = event is InputEventKey and (event as InputEventKey).shift_pressed
		if shift:
			_cycle_side_tab(-1)
		else:
			_focus_mail = not _focus_mail
			_side_tab = SideTab.POCKETS
			_tag_mode = false
			_refresh()
			_update_hand_cursor(true)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_BRACKETLEFT:
			_cycle_side_tab(-1)
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_BRACKETRIGHT:
			_cycle_side_tab(1)
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
	if _side_tab != SideTab.POCKETS:
		## Encyclopedia pages are read-only — only page flips and close.
		if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
			_cycle_side_tab(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
			_cycle_side_tab(1)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		if _focus_mail:
			Game.inventory.move_mail_cursor(-1, 0)
		else:
			Game.inventory.move_cursor(-1, 0)
		_update_hand_cursor(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		if _focus_mail:
			Game.inventory.move_mail_cursor(1, 0)
		else:
			Game.inventory.move_cursor(1, 0)
		_update_hand_cursor(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		if _focus_mail:
			Game.inventory.move_mail_cursor(0, -1)
		else:
			Game.inventory.move_cursor(0, -1)
		_update_hand_cursor(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		if _focus_mail:
			Game.inventory.move_mail_cursor(0, 1)
		else:
			Game.inventory.move_cursor(0, 1)
		_update_hand_cursor(true)
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
	if _open:
		Audio.play_se(&"cursol")
	_tag_mode = false
	_refresh()
	_update_hand_cursor(true)


func _on_mail_changed() -> void:
	if _focus_mail:
		_tag_mode = false
	_refresh()
	_update_hand_cursor(true)


func _activate_cursor() -> void:
	if _focus_mail:
		_activate_mail_cursor()
		return
	var inv: Inventory = Game.inventory
	var idx: int = inv.selected_index
	if inv.hand_index >= 0:
		inv.place_hand(idx)
		Audio.play_se(&"60")
		_play_hand_clip("hnd_catch", false)
		_refresh()
		_update_hand_cursor(true)
		## Return to pointing pose after the catch beat.
		get_tree().create_timer(0.35).timeout.connect(func() -> void: _play_hand_clip("hnd_sasu", true))
		return
	var slot: InventorySlot = inv.slot_at(idx)
	if slot == null or slot.is_empty():
		return
	_tag_choices = inv.tags_for_slot(idx)
	if _tag_choices.is_empty():
		return
	_tag_mode = true
	_tag_index = 0
	Audio.play_se(&"41c")
	_refresh()


func _activate_mail_cursor() -> void:
	var inv: Inventory = Game.inventory
	var idx: int = inv.selected_mail_index
	var mail: MailData = inv.mail_at(idx)
	_tag_choices = PackedStringArray()
	if mail == null or mail.is_empty():
		_tag_choices.append("Write")
	elif mail.is_received():
		_tag_choices.append("Read")
		if mail.has_enclosure():
			_tag_choices.append("Take")
		_tag_choices.append("Discard")
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
		"Wear":
			if Game.wear_cloth_from_slot(idx):
				var worn: ItemData = ItemCatalog.get_item(Game.cloth_id)
				if worn != null:
					Game.post_notice("Wearing %s" % worn.display_name)
				if (
					Game.first_job != null
					and Game.first_job.cloth_job_finished()
				):
					Game.set_interact_prompt("Talk to Tom Nook")
				close()
		"Hand over":
			## Intro down payment — Nook's director plays the hand-over and books it.
			Game.notify_intro_payment_made()
			close()
		"Donate":
			## Blathers is waiting — book the outcome and let his dialogue respond.
			var slot: InventorySlot = inv.slot_at(idx)
			if slot != null and not slot.is_empty():
				Game.take_museum_donation(slot.item.item_id)
			close()
		"Move":
			inv.pick_hand(idx)
			_play_hand_clip("hnd_catch", false)
			get_tree().create_timer(0.35).timeout.connect(func() -> void: _play_hand_clip("hnd_side", true))
		"Open":
			var slot: InventorySlot = inv.slot_at(idx)
			if slot != null and not slot.is_empty():
				slot.item.condition = InventoryItem.Condition.NORMAL
				inv.changed.emit()
				Game.post_notice("Opened present")
		"Plant":
			## `mTG_plant_proc`: shovel+hole → putin scoop; else throw-put on the facing unit.
			var taken: Dictionary = PlantGrowth.take_plant_from_slot(_field_context(), idx)
			if not bool(taken.get("ok", false)):
				var fail: String = str(taken.get("msg", ""))
				if fail != "":
					Game.post_notice(fail)
			else:
				close()
				var player := get_tree().get_first_node_in_group("player") as Node
				if player != null and player.has_method("plant_from_submenu"):
					player.call(
						"plant_from_submenu",
						taken.get("plant"),
						taken.get("cell"),
						bool(taken.get("use_scoop", false)),
						taken.get("item"),
						taken.get("condition"),
						str(taken.get("msg", ""))
					)
				else:
					var ctx: InteractionContext = _field_context()
					var plant: PlantData = taken.get("plant") as PlantData
					var cell: Vector2i = taken.get("cell") as Vector2i
					var pid: StringName = PlantGrowth.plant(ctx, plant, cell)
					if pid == &"":
						var item: ItemData = taken.get("item") as ItemData
						if item != null:
							Game.inventory.add(
								item, 1, taken.get("condition") as InventoryItem.Condition
							)
						Game.post_notice("Can't plant here.")
					else:
						PlantGrowth.play_grow_in(PlantGrowth.host_at(ctx.world, pid))
						Game.post_notice(str(taken.get("msg", "")))
				if Game.first_job != null and Game.first_job.plant_job_finished(Game.inventory):
					Game.first_job.mark_plant_finished()
					Game.set_interact_prompt("Talk to Tom Nook")
		_:
			## `mIV_ANIM_EAT`: eating fruit / food plays EAT1 in the portrait.
			if tag == "Eat":
				_set_portrait_anim(PortraitAnim.EAT)
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
		"Read":
			_read_letter(inv.mail_at(idx))
		"Take":
			_take_letter_enclosure(idx)
		"Discard":
			inv.remove_mail(idx)
			Game.post_notice("Discarded letter")
		_:
			pass
	_tag_mode = false
	_refresh()


func _read_letter(mail: MailData) -> void:
	if mail == null or mail.is_empty():
		return
	mail.mark_read()
	var parts: PackedStringArray = PackedStringArray()
	for line: String in [mail.header, mail.body, mail.footer]:
		if line.strip_edges() != "":
			parts.append(line)
	Game.post_notice("\n".join(parts))


func _take_letter_enclosure(idx: int) -> void:
	var inv: Inventory = Game.inventory
	var mail: MailData = inv.mail_at(idx)
	if mail == null or not mail.has_enclosure():
		return
	var item: ItemData = ItemCatalog.get_item(mail.present_item_id)
	if item == null:
		Game.post_notice("The enclosure is missing.")
		return
	if not inv.has_space_for(item, 1):
		Game.post_notice("Your pockets are full.")
		return
	inv.add(item, 1)
	mail.present_item_id = &""
	mail.mark_read()
	inv.mail_changed.emit()
	Game.post_notice("You took the %s." % item.display_name)


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
	_refresh_side_tab_visuals()
	_refresh_items(inv)
	_refresh_mail(inv)
	if _side_tab != SideTab.POCKETS:
		_populate_encyclopedia(&"fish" if _side_tab == SideTab.FISH else &"insect")
	if _tag_mode and _side_tab == SideTab.POCKETS and not _tag_choices.is_empty():
		_show_tag_popup()
	else:
		_hide_tag_popup()
	if _open:
		_update_hand_cursor(false)


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
			_set_slot_picture(btn, null)
			btn.modulate = Color(1, 1, 1, 1)
		else:
			var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
			var label: String = ""
			if slot.item.count > 1:
				label = "×%d" % slot.item.count
			btn.text = label
			var icon: Texture2D = InventoryChrome.icon_for_item(data, slot.item.condition)
			if icon != null:
				_set_slot_picture(btn, icon)
				## Real sprites carry their own colors; only dim while held.
				btn.modulate = Color(0.72, 0.72, 0.72, 1) if in_hand else Color.WHITE
			else:
				_set_slot_picture(btn, null)
				if data != null:
					btn.text = data.display_name.substr(0, mini(5, data.display_name.length()))
					if slot.item.count > 1:
						btn.text = "%s×%d" % [btn.text, slot.item.count]
				var tint: Color = data.icon_color if data != null else Color.WHITE
				btn.modulate = tint.darkened(0.25) if in_hand else tint
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
			_set_slot_picture(btn, null)
			btn.modulate = Color(1, 1, 1, 1)
		else:
			var has_present: bool = mail.present_item_id != &""
			var letter_tex: Texture2D = (
				_tex_letter_present if has_present and _tex_letter_present != null else _tex_letter
			)
			_set_slot_picture(btn, letter_tex)
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

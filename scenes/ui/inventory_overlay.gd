extends CanvasLayer

## Pocket submenu. Scene-first layout + textures in `inventory_overlay.tscn`.
## Runtime fills missing chrome via `InventoryChrome` and wires pocket/mail buttons.
## Top-left circle shows a live 3D player preview (`mIV_set_player`).
## Selection cursor is skinned `hnd.glb` (`m_hand_ovl` / `hnd_sasu`).

const ITEM_SCENE := "res://scenes/world/item_pickup.tscn"
const PLAYER_GLB := "res://assets/generated/characters/player/boy_1.glb"
const HND_GLB := "res://assets/generated/characters/other/hnd.glb"
const HAND_SIZE := 56.0

enum SideTab { POCKETS, FISH, FACE, BUG }

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
var _hand_root: Control = null
var _hand_viewport: SubViewport = null
var _hand_anim: AnimationPlayer = null
var _hand_tween: Tween = null
var _hand_ready: bool = false
var _open_tween: Tween = null


func _ready() -> void:
	layer = 20
	add_to_group("inventory_ui")
	_wire_slot_buttons()
	_wire_side_tabs()
	_build_styles()
	_apply_chrome()
	_setup_player_portrait()
	_setup_hand_cursor()
	_root.visible = false
	Game.inventory.changed.connect(_refresh)
	Game.inventory.selection_changed.connect(_on_selection)
	Game.inventory.mail_changed.connect(_on_mail_changed)
	Game.inventory.wallet_changed.connect(func(_a: int) -> void: _refresh())
	Game.inventory.equipment_changed.connect(func(_id: StringName) -> void: _refresh())
	_refresh()


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


func _wire_side_tabs() -> void:
	## Full-rect slot host must not steal clicks meant for the side tabs.
	if _slot_layer != null:
		_slot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Lift tabs above SlotLayer so edge hits are reliable (slots used to cover them).
	var tab_host: Control = _shell_stack if _shell_stack != null else null
	var tabs: Array = [
		[_tab_pencil, SideTab.POCKETS],
		[_tab_fish, SideTab.FISH],
		[_tab_face, SideTab.FACE],
		[_tab_bug, SideTab.BUG],
	]
	for entry: Variant in tabs:
		var panel: PanelContainer = entry[0]
		var page: SideTab = entry[1]
		if panel == null:
			continue
		if tab_host != null and panel.get_parent() != tab_host:
			var local: Vector2 = panel.position
			panel.reparent(tab_host)
			panel.position = local
			panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.z_index = 12
		panel.gui_input.connect(_on_side_tab_gui.bind(page))
		panel.pivot_offset = panel.size * 0.5


func _on_side_tab_gui(event: InputEvent, page: SideTab) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_select_side_tab(page)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_select_side_tab(page)
			get_viewport().set_input_as_handled()


func _cycle_side_tab(delta: int) -> void:
	var order: Array[SideTab] = [SideTab.POCKETS, SideTab.FISH, SideTab.FACE, SideTab.BUG]
	var cur: SideTab = SideTab.FACE if _focus_mail else _side_tab
	var idx: int = order.find(cur)
	if idx < 0:
		idx = 0
	var next: SideTab = order[(idx + delta + order.size()) % order.size()]
	_select_side_tab(next)


func _select_side_tab(page: SideTab) -> void:
	_tag_mode = false
	_side_tab = page
	match page:
		SideTab.POCKETS:
			_focus_mail = false
		SideTab.FACE:
			## Closest in-scope page: letters on the same pockets paper.
			_focus_mail = true
			_side_tab = SideTab.POCKETS
		SideTab.FISH:
			Game.post_notice("Fish collection coming soon.")
		SideTab.BUG:
			Game.post_notice("Insect collection coming soon.")
	_pulse_side_tab(page)
	_refresh()
	_update_hand_cursor(true)


func _pulse_side_tab(page: SideTab) -> void:
	var panel: PanelContainer = _tab_panel(page)
	if panel == null:
		return
	panel.pivot_offset = panel.size * 0.5
	var tw := create_tween()
	tw.tween_property(panel, "scale", Vector2(1.12, 1.12), 0.08)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)


func _tab_panel(page: SideTab) -> PanelContainer:
	match page:
		SideTab.POCKETS:
			return _tab_pencil
		SideTab.FISH:
			return _tab_fish
		SideTab.FACE:
			return _tab_face
		SideTab.BUG:
			return _tab_bug
	return null


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

	## WW side tabs: colored discs + pencil / fish / face / butterfly glyphs.
	_set_tex(_tab_axe_icon, "tab_pencil")
	_set_tex(_tab_fish_icon, "tab_fish")
	_set_tex(_tab_scoop_icon, "tab_face")
	_set_tex(_tab_bug_icon, "tab_bug")
	_style_tabs_as_discs()


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
	_hand_viewport.size = Vector2i(160, 160)
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
	## Pull back so `hnd_sasu` fits inside the RT without fingertip crop.
	cam.fov = 32.0
	cam.position = Vector3(0.0, 0.5, 3.35)
	world.add_child(cam)
	cam.look_at(Vector3(0.0, 0.32, 0.0), Vector3.UP)

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
	pivot.rotation_degrees = Vector3(12.0, 18.0, 0.0)
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
	var on_pockets: bool = _side_tab == SideTab.POCKETS or _side_tab == SideTab.FACE
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


func _refresh_side_tab_visuals() -> void:
	var active: SideTab = SideTab.POCKETS if _side_tab == SideTab.FACE else _side_tab
	if _focus_mail and active == SideTab.POCKETS:
		## Letters focus still on pockets paper — highlight face tab as the letters affordance.
		pass
	for page: SideTab in [SideTab.POCKETS, SideTab.FISH, SideTab.FACE, SideTab.BUG]:
		var panel: PanelContainer = _tab_panel(page)
		if panel == null:
			continue
		var selected: bool = false
		if page == SideTab.POCKETS and not _focus_mail and (_side_tab == SideTab.POCKETS or _side_tab == SideTab.FACE):
			selected = true
		elif page == SideTab.FACE and _focus_mail:
			selected = true
		elif page == _side_tab and page != SideTab.POCKETS and page != SideTab.FACE:
			selected = true
		panel.modulate = Color(1.15, 1.15, 1.15, 1.0) if selected else Color(0.85, 0.85, 0.85, 1.0)
		panel.scale = Vector2(1.06, 1.06) if selected else Vector2.ONE
		panel.pivot_offset = panel.size * 0.5


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


func _style_tabs_as_discs() -> void:
	## WW tabs: yellow / blue / grey / red discs with glyph icons on top.
	_ensure_disc_backdrop(_tab_pencil, Color(1.0, 0.85, 0.05, 1.0), _tab_axe_icon)
	_ensure_disc_backdrop(_tab_fish, Color(0.3, 0.45, 1.0, 1.0), _tab_fish_icon)
	_ensure_disc_backdrop(_tab_face, Color(0.45, 0.45, 0.48, 1.0), _tab_scoop_icon)
	_ensure_disc_backdrop(_tab_bug, Color(0.85, 0.18, 0.18, 1.0), _tab_bug_icon)


func _ensure_disc_backdrop(panel: PanelContainer, color: Color, icon: TextureRect) -> void:
	if panel == null:
		return
	var disc := StyleBoxFlat.new()
	disc.bg_color = color
	disc.set_corner_radius_all(999)
	disc.content_margin_left = 10
	disc.content_margin_top = 10
	disc.content_margin_right = 10
	disc.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", disc)
	if icon != null:
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color(0.08, 0.08, 0.1, 1.0) if panel == _tab_pencil else Color(1, 1, 1, 1)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_tag_mode = false
	_focus_mail = false
	_side_tab = SideTab.POCKETS
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
	_focus_mail = false
	_side_tab = SideTab.POCKETS
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
	_refresh_side_tab_visuals()
	_refresh_items(inv)
	_refresh_mail(inv)
	if _side_tab == SideTab.FISH:
		_name.text = "Fish"
		_desc.text = "Fish collection coming soon."
		_tags.text = ""
	elif _side_tab == SideTab.BUG:
		_name.text = "Insects"
		_desc.text = "Insect collection coming soon."
		_tags.text = ""
	elif _focus_mail:
		_refresh_mail_detail(inv)
		_refresh_tags_hint("X close  Tab items  [ ] tabs  Arrows move  E write/discard")
	else:
		_refresh_item_detail(inv)
		_refresh_tags_hint("X close  Tab letters  [ ] tabs  Arrows move  E tags")
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

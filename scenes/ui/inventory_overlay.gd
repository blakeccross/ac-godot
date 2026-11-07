class_name InventoryOverlay
extends MenuOverlay

## Pocket submenu. Scene-first layout + textures in `inventory_overlay.tscn`.
## Runtime fills missing chrome via `InventoryChrome` and wires pocket/mail buttons.
## Top-left circle shows a live 3D player preview (`mIV_set_player`).
## Selection cursor is skinned `hnd.glb` (`m_hand_ovl` / `hnd_sasu`).

const GROUP := &"inventory_ui"

## `aMBX_pl_close` waits for this to play the mailbox's closing beat.
signal closed

const HND_GLB := "res://assets/generated/characters/other/hnd.glb"
## `m_hand_ovl`: the glove is drawn in its own 64 x 64 view (320 x 240 screen units; the
## shell stack is 3.12 px per unit), `mSM_change_view(80, 0, ..., 64, 64)`: FOV 35, the model
## 3 units in front of the eye; the model scale is measured off the reference frame (half
## of what the raw-size arithmetic gives for our GLB).
const HAND_VIEW_UNITS := 64.0
const HAND_FOV := 35.0
const HAND_EYE_DISTANCE := 3.0
const HAND_MODEL_SCALE := 0.215
## `mHD_hand_shape_draw` shadow pass: 1.05x, flattened, 0.6 behind, black at alpha 128.
const HAND_SHADOW_SCALE := 1.05
const HAND_SHADOW_DEPTH := 0.6
## `mHD_ROT_X/Y/Z`, applied X then Y then Z. X is +135 here (the decomp's -135): our GLB's
## axes are mirrored against the ROM's.
const HAND_ROTATION := Vector3(135.0, 0.0, 70.3125)
## In-plane roll of the whole glove, measured off the reference frame (cuff upper right, index
## pointing left, the curled fingers stacked beneath it toward the lower left).
const HAND_VIEW_ROLL := 232.0
## Hand view centre from the slot centre (screen units, y up): `mHD_hand_offset*_table`
## (16, 6) turned by `mHD_ROT`, +(4, -4), then the view's own (+12 + 4, -16); a hand carrying
## an item also moves (-5, +12) (`mHD_hand_pos_get`). The x is 14.4 units less
## than that arithmetic: the pose is matched to the reference frame, not the ROM's origin.
const HAND_CENTER_FREE := Vector2(15.7, -3.4)
const HAND_CENTER_CARRYING := Vector2(10.7, 8.6)
## The ROM UI font (`FONT_nes_tex_font1`, `mFont_SetLineStrings`), same as the
## dialogue window; Rodin `.otf` is the vector fallback.
const UI_FONT_PATHS := [
	"res://assets/ui/msg_font.fnt",
	"res://assets/custom/ui/message/msg_font.fnt",
	"res://assets/fonts/fot_rodin_pro_db.otf",
]

## `mIV_PAGE_*` (`m_inventory_ovl.c`): the three horizontally-scrolling pages.
## FISH ← POCKETS → BUG, flipped with the two right-edge folder tabs or `[` `]`.
enum SideTab { FISH, POCKETS, BUG }
const PAGE_ORDER: Array = [SideTab.FISH, SideTab.POCKETS, SideTab.BUG]
## The order the shoulder button turns the pages in (`mTG_move_change`).
const PAGE_TURN: Array = [SideTab.POCKETS, SideTab.FISH, SideTab.BUG]

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

## `page_move_timer` (`m_inventory_ovl.c`): a sine-eased vertical swing over 40 frames
## when flipping pages, not a hard cut.
## Item (5x3) and mail (2x5) grids are bottom-aligned in `.tscn` (both grids' last row
## shares y=424.32-499.2) — mail row `r` lines up with item row `r - MAIL_ROW_OFFSET`.
const MAIL_ROW_OFFSET := 2

## `page_move_timer` (`m_inventory_ovl.c`): 40 ticks. The page coming up rises and the rest drop by
## `100 * sin(timer * pi / 40)` units; the stacking order flips when the timer reaches 20.
const PAGE_MOVE_TICKS := 40
const PAGE_MOVE_SWAP_TICK := 20
const PAGE_MOVE_UNITS := 100.0
const PAGE_MOVE_DURATION := float(PAGE_MOVE_TICKS) / DecompTime.TICK_HZ
## `mTG_wchange_col_pos` / `mTG_wchange_line_pos`: where the hand sits on each page's tab (y up).
## The hand rests this far (units, y up) above-left of where the table puts it: measured off the
## reference frames (fish and insect pages), not derived.
const TAB_HAND_SHIFT := Vector2(-1.0, 13.4)
const TAB_HAND_UNITS := {
	SideTab.FISH: Vector2(105.0, 37.0),
	SideTab.POCKETS: Vector2(105.0, 0.0),
	SideTab.BUG: Vector2(105.0, -37.0),
}

@onready var _root: Control = %Root
@onready var _mobile: MobileInventory = $Root/MobileInventory
@onready var _classic: Control = $Root/Center
@onready var _back_to_items: Button = $Root/BackToItems
@onready var _shell_stack: Control = %ShellStack
@onready var _shell_shadow: TextureRect = %ShellShadow
@onready var _window_shell: TextureRect = %WindowShell
@onready var _slot_layer: Control = %SlotLayer
@onready var _wallet: Label = %WalletLabel
@onready var _player_name: Label = %PlayerName
@onready var _town_name: Label = %TownName
@onready var _page_overlay: TextureRect = %PageOverlay
@onready var _name: Label = %ItemNameLabel
@onready var _equip: Label = %EquipLabel
@onready var _hint: Label = %HintLabel
@onready var _items_label: TextureRect = %ItemsLabel
@onready var _letters_label: TextureRect = %LettersLabel
@onready var _bells_label: TextureRect = %BellsLabel
@onready var _portrait_frame: TextureRect = %PortraitFrame
@onready var _portrait_viewport: SubViewport = %SubViewport
## The three stacked pages (`mIV_set_dl` draws them back to front): the pockets are `ShellStack`,
## the encyclopedia pages their own scenes. Their tabs are authored in the scenes.
@onready var _pages: Control = %Pages
@onready var _fish_page: InventoryCollectPage = %FishPage
@onready var _bug_page: InventoryCollectPage = %BugPage
@onready var _tab_pockets: Panel = %TabPockets
@onready var _tab_design: Panel = %TabDesign

var _open: bool = false
## The tap that opens the down-payment pockets can also hit Close on the next frame.
## Ignore that one press; a later Close still declines the payment.
var _ignore_close_once: bool = false
## Layer while the down-payment sheet must sit above the talk window (layer 25).
var _restore_layer: int = -1
var _focus_mail: bool = false
## `mTG_TABLE_PLAYER`: the cursor can move onto the player doll from the top row of the
## item grid, same continuous navigable space as items/mail/wallet/background.
var _focus_player: bool = false
var _side_tab: SideTab = SideTab.POCKETS
var _slot_buttons: Array[Button] = []
var _mail_buttons: Array[Button] = []
var _tag_choices: PackedStringArray = []
var _tag_index: int = 0
var _tag_mode: bool = false
## Which one applies (selected/marked/empty) is runtime state, but the resources
## themselves are authored in `inventory_overlay.tscn` — assign there, not in code.
@export var style_item: StyleBox
@export var style_item_selected: StyleBox
@export var style_item_marked: StyleBox
@export var style_mail: StyleBox
@export var style_mail_selected: StyleBox
var _tex_letter: Texture2D
var _tex_letter_present: Texture2D
var _tex_letter_open: Texture2D
var _tex_letter_open_present: Texture2D
var _portrait_ready: bool = false
var _portrait_pivot: Node3D = null
var _portrait_anim: AnimationPlayer = null
var _portrait_equipment_id: StringName = &""
var _portrait_rest: PortraitAnim = PortraitAnim.WALK
var _hand_root: Control = null
var _hand_viewport: SubViewport = null
var _hand_anim: AnimationPlayer = null
var _hand_shadow_anim: AnimationPlayer = null
var _hand_tween: Tween = null
var _hand_ready: bool = false
## `mSM_move_Move`: the pockets slide in from the right and out to the right.
var _slide: MenuSlide = null
## What the pockets page draws only while it is up: portrait, names, Bells, item pictures.
var _pocket_contents: Array[CanvasItem] = []
## `page_order`: the page on top first. `_page_moving` blocks input while the pages shuffle.
var _page_order: Array = [SideTab.POCKETS, SideTab.FISH, SideTab.BUG]
var _page_moving: bool = false
var _page_swapped: bool = false
var _page_next: SideTab = SideTab.POCKETS
var _page_tween: Tween = null
## Mail slot index awaiting a Yes/No discard confirmation, or -1 when none is pending.
var _pending_mail_discard: int = -1
## `mTG_TABLE_MONEY`: the wallet's own verb popup (denomination picker), not an item slot.
var _wallet_tag_mode: bool = false
## `mTG_TABLE_BG`: the background slot's own verb popup ("Remove").
var _background_tag_mode: bool = false
var _background_slot: Control = null
var _background_icon: TextureRect = null
## The item name plate (`sen_itemw_*`, tag 0) and the verb window (`sen_win_*`, tag 1), both
## laid out by `TagLayout` and drawn by `TagWindowView` (`m_tag_ovl.c`).
var _name_tag: TagWindowView = null
var _tag_popup: TagWindowView = null
var _name_layout: TagLayout.Tag = null
var _name_key: String = ""
var _name_wait: int = 0
var _name_open: float = 0.0
var _verb_open: float = 0.0
var _verb_closing: bool = false
var _tag_accum: float = 0.0
## `mSM_OVL_HANIWA` (`m_haniwa_ovl`): the house gyroid's 4-slot table beside the pockets.
## `_gyroid_house` is set while the pockets were opened from the gyroid; `_gyroid_owner` is
## entrust mode (`mSM_IV_OPEN_HANIWA_ENTRUST`), else visitor take mode.
var _gyroid_house: House = null
var _gyroid_owner: bool = true
var _focus_gyroid: bool = false
var _gyroid_sel: int = 0
@onready var _gyroid_root: Control = %HaniwaTable
var _gyroid_buttons: Array[Button] = []
@onready var _gyroid_status: Label = %HaniwaTable.get_node("HaniwaStatus")
var _gyroid_tag_mode: bool = false
## Pocket slot being put in (hand held over an empty gyroid slot), −1 = setting terms on an
## item already there.
var _gyroid_put_pocket: int = -1
## `mTG_mv_priceSet`: digit cursor 0..4 over a 5-digit price.
var _price_mode: bool = false
var _price: int = 0
var _price_digit: int = 4
## `mHW_set_interrupt_message`: a status line held for 120 frames.
var _gyroid_interrupt: String = ""
var _gyroid_interrupt_left: float = 0.0
var _ui_font: Font = null

## `mTG_select_col_type_on/off[mTG_TAG_COLOR_NORMAL]` + `cursol_color[NORMAL]`.
const _TAG_TEXT_ON := Color8(120, 35, 255)
const _TAG_TEXT_OFF := Color8(140, 150, 190)


## The one in `tree`, or null.
static func find(tree: SceneTree) -> InventoryOverlay:
	return tree.get_first_node_in_group(GROUP) as InventoryOverlay if tree != null else null


func _ready() -> void:
	layer = 20
	add_to_group(GROUP)
	add_to_group(WindowDismiss.GROUP)
	_slide = MenuSlide.attach(self)
	_load_ui_font()
	_wire_slot_buttons()
	_mobile.slot_pressed.connect(_on_item_pressed)
	_mobile.mail_pressed.connect(_on_mail_pressed)
	_mobile.page_pressed.connect(_on_mobile_page)
	_mobile.designs_pressed.connect(_open_design_book)
	_mobile.action_pressed.connect(_run_tag)
	_mobile.actions_cancelled.connect(_cancel_mobile_actions)
	_mobile.wallet_pressed.connect(_open_wallet_popup)
	_mobile.close_pressed.connect(close)
	if not InputDeviceTracker.layout_changed.is_connected(_on_layout_changed):
		InputDeviceTracker.layout_changed.connect(_on_layout_changed)
	_wire_side_tabs()
	_apply_chrome()
	_build_tag_popup()
	_build_name_tag()
	_build_background_slot()
	_setup_player_portrait()
	_setup_hand_cursor()
	## The GC pockets screen has no bottom text block — the verb window and the
	## slot cards carry everything. Hide the invented name/desc/hint labels.
	var detail: Control = _shell_stack.get_node_or_null("Detail") as Control
	if detail != null:
		detail.visible = false
	## Font/size/color for name/town/wallet labels are authored directly on the nodes
	## in `inventory_overlay.tscn` (ROM font `mFont`, not Rodin) — nothing to set here.
	## `mIV_SetLineStrings_centering`: land name scale 0.875, player name 0.9375 of
	## an ~18 px cell -> ~16/17 px; wallet digits sit in the `suujiwaku` box.
	var bells_pill: Control = _wallet.get_parent() as Control if _wallet != null else null
	if bells_pill != null:
		bells_pill.mouse_filter = Control.MOUSE_FILTER_STOP
		bells_pill.gui_input.connect(_on_wallet_gui)
	_root.visible = false
	Game.inventory.changed.connect(_refresh)
	Game.inventory.selection_changed.connect(_on_selection)
	Game.inventory.mail_changed.connect(_on_mail_changed)
	Game.inventory.wallet_changed.connect(func(_a: int) -> void: _refresh())
	Game.inventory.equipment_changed.connect(func(_id: StringName) -> void: _refresh())
	Game.inventory.background_changed.connect(func(_id: StringName) -> void: _refresh_background())
	Game.cloth_changed.connect(func(_id: StringName) -> void: _sync_portrait_cloth())
	Game.design_changed.connect(_sync_portrait_cloth)
	_refresh_background()
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
		_slot_buttons.append(btn)
	for i: int in Inventory.MAIL_SLOTS:
		var btn: Button = get_node_or_null("%%MailSlot%d" % i) as Button
		if btn == null:
			continue
		btn.pressed.connect(_on_mail_pressed.bind(i))
		_mail_buttons.append(btn)
	_gyroid_buttons.clear()
	for i: int in GyroidStore.SLOTS:
		var btn: Button = _gyroid_root.get_node("HaniwaSlot%d" % i) as Button
		btn.pressed.connect(_on_gyroid_pressed.bind(i))
		_gyroid_buttons.append(btn)
	if _ui_font != null:
		_gyroid_status.add_theme_font_override("font", _ui_font)


func _set_slot_picture(btn: Button, tex: Texture2D) -> void:
	## `ItemIcon` is an authored child node in the .tscn on every slot button, not
	## `Button.icon` — that's easy to lose under theme/stylebox layout.
	btn.icon = null
	var icon: TextureRect = btn.get_node_or_null("ItemIcon") as TextureRect
	if icon == null:
		btn.icon = tex
		btn.expand_icon = true
		return
	icon.texture = tex
	icon.visible = tex != null


## Small "pull out" when a tab is the active page — toward the paper on the left
## tab, away on the right ones. Everything else about the tabs is in the .tscn.
## Figure height over the portrait box; the box is ~1.6x the ring, the figure ~1.3x.
const PORTRAIT_FIGURE_FILL := 0.70
## Shadow disc diameter over the figure's height (reference frame).
const PORTRAIT_SHADOW_SPAN := 0.65

## Tab -> the page it opens (`-1`: the design book).
var _tab_pages: Dictionary = {}


func _wire_side_tabs() -> void:
	if _slot_layer != null:
		_slot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry: Array in [[_tab_pockets, SideTab.POCKETS], [_tab_design, -1]]:
		var tab: Panel = entry[0]
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		_tab_pages[tab] = entry[1]
		tab.gui_input.connect(_on_side_tab_gui.bind(entry[1]))
	_fish_page.tab_input.connect(_on_side_tab_gui.bind(SideTab.FISH))
	_bug_page.tab_input.connect(_on_side_tab_gui.bind(SideTab.BUG))


func _on_side_tab_gui(event: InputEvent, page: int) -> void:
	if not _open or _page_moving or not _click_event(event):
		return
	get_viewport().set_input_as_handled()
	if page < 0:
		_open_design_book()
	else:
		_select_side_tab(page)


## `mSM_OVL_NEEDLEWORK` / `mNW_OPEN_INV`: the book opens over the pockets.
func _open_design_book() -> void:
	Audio.play_se(&"cursol")
	var list_ui: DesignListOverlay = DesignListOverlay.find(get_tree())
	if list_ui == null:
		Game.post_notice("The design book isn't available here.")
		return
	list_ui.open(DesignListOverlay.ListMode.MANAGE, Callable(), true)
	if list_ui.is_open():
		_set_design_book_open(true)
		list_ui.closed.connect(_set_design_book_open.bind(false), CONNECT_ONE_SHOT)


func _set_design_book_open(on: bool) -> void:
	for btn: Button in _mail_buttons:
		btn.visible = not on
	if _letters_label != null:
		_letters_label.visible = not on and _side_tab == SideTab.POCKETS
	if _hand_root != null:
		if on:
			_hand_root.visible = false
		else:
			_update_hand_cursor(false)


func _cycle_side_tab(delta: int) -> void:
	var idx: int = PAGE_ORDER.find(_side_tab)
	if idx < 0:
		idx = PAGE_ORDER.find(SideTab.POCKETS)
	_select_side_tab(PAGE_ORDER[clampi(idx + delta, 0, PAGE_ORDER.size() - 1)])


## The R button (`mTG_move_change`): pockets -> fish -> insects -> pockets.
func _turn_page(step: int) -> void:
	var idx: int = PAGE_TURN.find(_side_tab)
	_select_side_tab(PAGE_TURN[posmod(idx + step, PAGE_TURN.size())])


func _select_side_tab(page: SideTab) -> void:
	if page == _side_tab or _page_moving:
		return
	_tag_mode = false
	_pending_mail_discard = -1
	_wallet_tag_mode = false
	_background_tag_mode = false
	_hide_tag_popup()
	## `mTG_mark_main_CLR`: marks don't survive a page flip.
	Game.inventory.clear_marks()
	_side_tab = page
	if page != SideTab.POCKETS:
		_focus_mail = false
		_focus_player = false
	Audio.play_se(&"cursol")
	## `mIV_ANIM_CATCH` on a collection page; WALK back on the pockets.
	_set_portrait_anim(PortraitAnim.CATCH if page != SideTab.POCKETS else PortraitAnim.WALK)
	_start_page_move(page)
	_refresh()


func _apply_chrome() -> void:
	## Fill missing textures only — assigned `.tscn` textures stay editable in the editor.
	InventoryChrome.clear_cache()
	## Project default filter is nearest; shell / labels need linear for smooth scallops.
	for node: CanvasItem in [_window_shell, _shell_shadow, _page_overlay, _items_label, _letters_label, _bells_label, _portrait_frame]:
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
	_apply_paper_scroll_shader()

	_set_tex(_items_label, "items_label")
	_set_tex(_letters_label, "letters_label")
	_set_tex(_bells_label, "bells_label")
	_set_tex(_portrait_frame, "portrait_frame")
	_tex_letter = InventoryChrome.load_tex("letter")
	_tex_letter_present = InventoryChrome.load_tex("letter_present")
	_tex_letter_open = InventoryChrome.load_tex("letter_open")
	_tex_letter_open_present = InventoryChrome.load_tex("letter_open_present")
	if _tex_letter == null:
		_tex_letter = InventoryChrome.load_tex("letter_envelope")


## `mSM_scroll_move` (`m_submenu_ovl.c`): every full-screen menu's paper fill
## slides diagonally, not just a static print. Re-samples a paper texture over
## the baked shell's alpha so the silhouette/border stay put. `override` swaps
## in the player's chosen `backgound_texture` shirt pattern (`_refresh_background`);
## omitted/null falls back to the default paper (`ITM_CLOTH226`).
func _apply_paper_scroll_shader(override: Texture2D = null) -> void:
	if _window_shell == null or _window_shell.texture == null:
		return
	var paper_tex: Texture2D = override if override != null else InventoryChrome.load_tex("paper")
	if paper_tex == null:
		return
	var mat := _window_shell.material as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = load("res://shaders/inventory_shell_paper.gdshader")
		_window_shell.material = mat
	mat.set_shader_parameter("paper_tex", paper_tex)


func _setup_player_portrait() -> void:
	if _portrait_ready or _portrait_viewport == null:
		return
	_portrait_ready = true
	_portrait_viewport.transparent_bg = true
	_portrait_viewport.own_world_3d = true
	_portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var world := Node3D.new()
	world.name = "PortraitWorld"
	_portrait_viewport.add_child(world)

	_add_menu_lights(world)

	## `mIV_set_player` → `mSM_change_view(330, 25, …, angle=0x900, 256²)`: FOV 20°,
	## eye 0x900 short-angle (~12.66°) above `y_lookAt`. `eye_dist` / `y_lookAt` are
	## set from the player AABB below so the framing matches whatever `actor_scale` is.
	var elev: float = float(0x900) * MathUtil.S16
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 20.0
	world.add_child(cam)

	var player_glb := Player.visual_path()
	if not ResourceLoader.exists(player_glb):
		return
	var packed: PackedScene = load(player_glb) as PackedScene
	if packed == null:
		return
	var body: Node = packed.instantiate()
	if not (body is Node3D):
		body.queue_free()
		return
	_portrait_pivot = body as Node3D
	world.add_child(_portrait_pivot)
	VisualFit.apply_actor_scale(_portrait_pivot, Player.visual_id())
	GeneratedVisual.apply_preview_materials(_portrait_pivot)
	VisualAnimation.stop_autoplay_keep_rest(_portrait_pivot)
	_portrait_pivot.rotation.y = 0.0
	_portrait_pivot.position = Vector3.ZERO

	_portrait_anim = VisualAnimation.find_animation_player(_portrait_pivot)
	_sync_portrait_equipment(true)
	_sync_portrait_cloth()

	## The whole figure is drawn over the `inv_mwin_3Dma` ring, not clipped to it: head and
	## horns stand above the circle and the feet below (reference frame: ~1.3x the ring).
	await get_tree().process_frame
	var aabb := _visual_aabb(_portrait_pivot)
	var ph: float = maxf(aabb.size.y, 0.1)
	var look_y: float = aabb.position.y + ph * 0.50
	var eye_dist: float = (ph / PORTRAIT_FIGURE_FILL) / (2.0 * tan(deg_to_rad(10.0)))
	cam.position = Vector3(0.0, look_y + eye_dist * sin(elev), eye_dist * cos(elev))
	cam.look_at(Vector3(0.0, look_y, 0.0), Vector3.UP)
	_add_portrait_shadow(cam.get_parent(), aabb.position.y, ph)


## `mIV_pl_shadow_draw`: the player's round ground shadow (`ef_shadow_in_modelT`), drawn
## under the feet before the figure. About 0.65 of the figure's height across.
func _add_portrait_shadow(world: Node, ground_y: float, figure_height: float) -> void:
	var tex: Texture2D = InventoryChrome.load_tex("portrait_shadow")
	if tex == null:
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * figure_height * PORTRAIT_SHADOW_SPAN
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.no_depth_test = false
	var shadow := MeshInstance3D.new()
	shadow.name = "PortraitShadow"
	shadow.mesh = quad
	shadow.material_override = mat
	shadow.position = Vector3(0.0, ground_y + figure_height * 0.004, 0.0)
	world.add_child(shadow)


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
	var view: float = HAND_VIEW_UNITS * _units_to_px()
	_hand_root = Control.new()
	_hand_root.name = "HandCursor"
	_hand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Above the verb window (z 40) so the kage shadow never paints over the glove.
	_hand_root.z_index = 55
	_hand_root.size = Vector2(view, view)
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
	_hand_viewport.size = Vector2i(256, 256)
	_hand_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(_hand_viewport)

	var world := Node3D.new()
	world.name = "HandWorld"
	_hand_viewport.add_child(world)
	_add_menu_lights(world)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = HAND_FOV
	cam.near = 0.1
	cam.far = 50.0
	cam.position = Vector3(0.0, 0.0, HAND_EYE_DISTANCE)
	world.add_child(cam)

	if not ResourceLoader.exists(HND_GLB):
		return
	var packed: PackedScene = load(HND_GLB) as PackedScene
	if packed == null:
		return
	## Shadow first (it is the farther, flattened copy), then the glove.
	var shadow_root := Node3D.new()
	shadow_root.name = "HandShadow"
	shadow_root.scale = Vector3(HAND_MODEL_SCALE * HAND_SHADOW_SCALE, HAND_MODEL_SCALE * HAND_SHADOW_SCALE, 0.001)
	shadow_root.position = Vector3(0.0, 0.0, -HAND_SHADOW_DEPTH)
	shadow_root.rotation_degrees = Vector3(0.0, 0.0, HAND_VIEW_ROLL)
	world.add_child(shadow_root)
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, 128.0 / 255.0)
	shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hand_shadow_anim = _make_hand_model(packed, shadow_root, shadow_mat)

	var hand_root := Node3D.new()
	hand_root.name = "HandModel"
	hand_root.scale = Vector3.ONE * HAND_MODEL_SCALE
	hand_root.rotation_degrees = Vector3(0.0, 0.0, HAND_VIEW_ROLL)
	world.add_child(hand_root)
	_hand_anim = _make_hand_model(packed, hand_root, null)
	_play_hand_clip("hnd_sasu", true)


## One copy of the glove under `parent`, turned by `mHD_ROT`. `override` replaces its
## materials (the flat shadow); otherwise they are the model's own, with back faces culled
## (`G_CULL_BACK`: the finger-line texture sits on the inside faces).
func _make_hand_model(packed: PackedScene, parent: Node3D, override: Material) -> AnimationPlayer:
	var body: Node = packed.instantiate()
	if not (body is Node3D):
		body.queue_free()
		return null
	var pivot := body as Node3D
	pivot.rotation_order = EULER_ORDER_XYZ
	pivot.rotation_degrees = HAND_ROTATION
	parent.add_child(pivot)
	GeneratedVisual.apply_preview_materials(pivot)
	VisualAnimation.stop_autoplay_keep_rest(pivot)
	for node: Node in pivot.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if override != null:
			mi.material_override = override
			continue
		for surface: int in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(surface) as BaseMaterial3D
			if mat == null:
				continue
			mat = mat.duplicate() as BaseMaterial3D
			mat.cull_mode = BaseMaterial3D.CULL_BACK
			mi.set_surface_override_material(surface, mat)
	return VisualAnimation.find_animation_player(pivot)


## Screen units (320 x 240) to shell-stack pixels.
func _units_to_px() -> float:
	return _shell_stack.custom_minimum_size.x / 240.0 if _shell_stack != null else 3.12


## `mSM_change_view` Lights0 for the menu's 3D pieces (portrait, glove): ambient (105, 90,
## 90) and a white-ish key (255, 255, 245) whose vector (0, 60, 60) points up and toward
## the camera.
func _add_menu_lights(world: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color8(105, 90, 90)
	env.ambient_light_energy = 1.0
	var env_node := WorldEnvironment.new()
	env_node.environment = env
	world.add_child(env_node)
	var light := DirectionalLight3D.new()
	light.light_color = Color8(255, 255, 245)
	light.light_energy = 1.0
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-45.0, 0.0, 0.0)
	world.add_child(light)


func _play_hand_clip(suffix: String, loop: bool) -> void:
	_play_hand_clip_on(_hand_anim, suffix, loop)
	_play_hand_clip_on(_hand_shadow_anim, suffix, loop)


func _play_hand_clip_on(player: AnimationPlayer, suffix: String, loop: bool) -> void:
	if player == null or suffix.is_empty():
		return
	var clip := ""
	if player.has_animation(suffix):
		clip = suffix
	else:
		for anim_name: String in player.get_animation_list():
			if anim_name.ends_with(suffix) or suffix in anim_name:
				clip = anim_name
				break
	if clip.is_empty():
		return
	var animation: Animation = player.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	player.play(clip)


## The verb popup anchors on whatever's under the cursor — usually a pocket/mail slot,
## but the wallet and background slots have their own popups too (`mTG_TABLE_MONEY`/`BG`).
func _tag_anchor_control() -> Control:
	if _wallet_tag_mode:
		return _wallet.get_parent() as Control
	if _background_tag_mode:
		return _background_slot
	if _focus_player:
		return _portrait_frame
	return _selected_slot_button()


func _selected_slot_button() -> Button:
	if _focus_gyroid:
		if _gyroid_sel >= 0 and _gyroid_sel < _gyroid_buttons.size():
			return _gyroid_buttons[_gyroid_sel]
		return null
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
	if uses_mobile_layout():
		_hand_root.visible = false
		if _hand_viewport != null:
			_hand_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var on_pockets: bool = _side_tab == SideTab.POCKETS
	var btn: Control = (_portrait_frame if _focus_player else _selected_slot_button()) if on_pockets else null
	if _page_moving or not _open or (btn == null and on_pockets):
		_hand_root.visible = false
		if _hand_viewport != null:
			_hand_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_hand_root.visible = true
	if _hand_viewport != null:
		_hand_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	## The 64-unit view is centred up and right of the slot (`HAND_CENTER_*`).
	var slot_center: Vector2
	if btn == null:
		## An encyclopedia page: the hand rests on that page's tab (`mTG_TABLE_WCHANGE`).
		var tab_at: Vector2 = TAB_HAND_UNITS[_side_tab]
		tab_at += TAB_HAND_SHIFT
		slot_center = (Vector2(120.0, 90.0) + Vector2(tab_at.x, -tab_at.y)) * _units_to_px()
	else:
		slot_center = btn.position + btn.size * 0.5
		if btn.get_parent() != null and _hand_root.get_parent() != null:
			slot_center = _hand_root.get_parent().get_global_transform_with_canvas().affine_inverse() * (
				btn.get_global_transform_with_canvas() * (btn.size * 0.5)
			)
	var carrying: bool = btn != null and _hand_carrying()
	var shift: Vector2 = HAND_CENTER_CARRYING if carrying else HAND_CENTER_FREE
	var target: Vector2 = (
		slot_center + Vector2(shift.x, -shift.y) * _units_to_px() - _hand_root.size * 0.5
	)
	if animate and _hand_root.visible:
		if _hand_tween != null:
			_hand_tween.kill()
		_hand_tween = create_tween()
		_hand_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hand_tween.tween_property(_hand_root, "position", target, 0.12)
	else:
		_hand_root.position = target


## `mHD_hand_pos_get`: the (-5, +12) lift follows `info.item`, the item the hand is carrying,
## not whatever sits under it, so hovering a filled slot leaves the hand level with its row.
func _hand_carrying() -> bool:
	return Game.inventory.hand_index >= 0


## `mTG_TABLE_BG` is navigable in decomp, but the GC pockets screen does **not** draw a
## square chip beside the wallet — the backdrop is only the scrolling paper
## (`backgound_texture`). Keep a hidden hit target so "Remove" still works when a
## custom paper is set; never show invented chrome next to Bells.
func _build_background_slot() -> void:
	if _background_slot != null or _shell_stack == null:
		return
	var slot := Panel.new()
	slot.name = "BackgroundSlot"
	slot.visible = false
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.position = Vector2(452.0, 226.0)
	slot.size = Vector2(1.0, 1.0)
	_shell_stack.add_child(slot)
	_background_slot = slot
	_background_icon = null


## Decomp `backgound_texture`: swaps the shader's scrolling paper for the chosen
## shirt's real pattern (`shirt_NNN.png`, same asset the worn cloth uses), falling
## back to the default paper when nothing is set or the pattern PNG is missing.
func _refresh_background() -> void:
	var inv: Inventory = Game.inventory
	var data: ItemData = ItemCatalog.get_item(inv.background_id) if inv.background_id != &"" else null
	var paper_tex: Texture2D = null
	if data != null and data.cloth_index >= 0:
		var path: String = FieldCatalog.cloth_albedo(data.cloth_index)
		if path != "":
			paper_tex = load(path) as Texture2D
	_apply_paper_scroll_shader(paper_tex)


## The two tag windows. Built once; `_refresh_name_tag` / `_show_tag_popup` lay them out.
func _build_name_tag() -> void:
	if _name_tag != null or _shell_stack == null:
		return
	_name_tag = _new_tag_view(35)


func _build_tag_popup() -> void:
	if _tag_popup != null or _shell_stack == null:
		return
	_tag_popup = _new_tag_view(40)


func _new_tag_view(z: int) -> TagWindowView:
	var view := TagWindowView.new()
	view.z_index = z
	view.px_per_unit = _units_to_px()
	view.font = _ui_font
	view.set_centre(_shell_stack.custom_minimum_size)
	_shell_stack.add_child(view)
	return view


## Screen units (about the centre, y up) for the middle of `ctrl`, which lives in the stack.
func _units_of(ctrl: Control) -> Vector2:
	var k: float = _units_to_px()
	var centre: Vector2 = (ctrl.position + ctrl.size * 0.5) / k
	return Vector2(centre.x - 120.0, 90.0 - centre.y)


## The ROM font's width of `text` at its native 16-unit size (`mFont_GetStringWidth`).
func _text_units(text: String) -> float:
	if _ui_font == null:
		return float(text.length()) * 7.0
	return _ui_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x


const _TAG_NAME_TEXT := Color8(90, 60, 50)
const _NAME_MODELS := {
	"frame": "tag_name_frame", "shadow": "tag_name_shadow", "arrow": "tag_name_arrow", "cursor": ""
}
const _NAME_MODELS_RIGHT := {
	"frame": "tag_name_frame", "shadow": "tag_name_shadow", "arrow": "tag_name_arrow_r", "cursor": ""
}
const _VERB_MODELS := {
	"frame": "tag_frame", "shadow": "tag_shadow", "arrow": "", "cursor": "tag_cursor"
}


func _refresh_name_tag(inv: Inventory) -> void:
	if _name_tag == null:
		return
	## The name plate stays up while the verb window is open (both are drawn together).
	if not _open or _side_tab != SideTab.POCKETS or _focus_player or _focus_gyroid:
		_name_tag.visible = false
		_name_layout = null
		_name_key = ""
		return
	var text := ""
	var anchor: Control = null
	var row: int = 0
	if _focus_mail:
		var mail: MailData = inv.mail_at(inv.selected_mail_index)
		if mail == null or mail.is_empty():
			_hide_name_tag()
			return
		text = mail.label()
		if inv.selected_mail_index >= 0 and inv.selected_mail_index < _mail_buttons.size():
			anchor = _mail_buttons[inv.selected_mail_index]
			@warning_ignore("integer_division")
			row = inv.selected_mail_index / Inventory.MAIL_COLUMNS
	else:
		var slot: InventorySlot = inv.selected_slot()
		if slot == null or slot.is_empty():
			_hide_name_tag()
			return
		var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
		if slot.item.condition == InventoryItem.Condition.PRESENT:
			text = "present"
		elif data != null:
			text = data.display_name.to_lower()
		else:
			text = String(slot.item.item_id)
		if inv.selected_index >= 0 and inv.selected_index < _slot_buttons.size():
			anchor = _slot_buttons[inv.selected_index]
			@warning_ignore("integer_division")
			row = inv.selected_index / Inventory.COLUMNS
	if anchor == null or text.is_empty():
		_hide_name_tag()
		return
	_name_layout = TagLayout.item_tag(_units_of(anchor), row, _text_units(text))
	var key: String = "%s/%s/%s" % [text, _focus_mail, row]
	key += "/%d" % (inv.selected_mail_index if _focus_mail else inv.selected_index)
	if key != _name_key:
		## `mTG_get_item_name_wait_time`: the plate pops up a moment after the cursor lands.
		_name_key = key
		_name_wait = TagLayout.NAME_WAIT_FRAMES
		_name_open = 0.0
	var models: Dictionary = _NAME_MODELS if _name_layout.arrow_dir == 1 else _NAME_MODELS_RIGHT
	_name_tag.show_tag(_name_layout, models, PackedStringArray([text]), [_TAG_NAME_TEXT], -1)
	_name_tag.set_open_scale(_name_open)


func _hide_name_tag() -> void:
	_name_tag.visible = false
	_name_layout = null
	_name_key = ""


## `mTG_normal_move`: the name plate opens 0.125 per game frame after its wait; the verb
## window opens 0.185 per frame once the plate is up (0.125 otherwise) and closes 0.125.
func _step_tags(delta: float) -> void:
	_tag_accum += delta
	var step: float = 1.0 / DecompTime.FRAME_HZ
	var steps: int = 0
	while _tag_accum >= step and steps < 8:
		_tag_accum -= step
		steps += 1
		if _name_layout != null:
			if _name_wait > 0:
				_name_wait -= 1
			elif _name_open < 1.0:
				_name_open = minf(_name_open + 0.125, 1.0)
		if _tag_popup != null and _tag_popup.visible:
			if _verb_closing:
				_verb_open -= 0.125
				if _verb_open <= 0.0:
					_verb_open = 0.0
					_tag_popup.visible = false
			elif _verb_open < 1.0:
				_verb_open = minf(_verb_open + (0.185 if _name_layout != null else 0.125), 1.0)
	if steps > 0:
		if _name_tag != null and _name_layout != null:
			_name_tag.set_open_scale(_name_open)
		if _tag_popup != null and _tag_popup.visible:
			_tag_popup.set_open_scale(_verb_open)


func _hide_tag_popup() -> void:
	_mobile.hide_actions()
	if _tag_popup != null and _tag_popup.visible:
		_verb_closing = true


## The verb window (`mTG_init_tag_data_select_win_after_item`): hangs off the name plate,
## selected verb in violet, the rest muted, the magenta cursor on the selected row.
func _show_tag_popup() -> void:
	if uses_mobile_layout():
		if _tag_popup != null:
			_tag_popup.visible = false
		var title: String = "Bells" if _wallet_tag_mode else ""
		_mobile.show_actions(title, _tag_choices, _tag_index)
		return
	if _tag_popup == null or _tag_choices.is_empty():
		_hide_tag_popup()
		return
	var btn: Control = _tag_anchor_control()
	if btn == null:
		_hide_tag_popup()
		return
	var parent: TagLayout.Tag = _name_layout
	if parent == null:
		## No name plate to hang from (player picture, wallet): the window stands alone.
		parent = TagLayout.Tag.new()
		parent.base = _units_of(btn)
		parent.arrow_dir = 0
	var widest := 0.0
	for verb: String in _tag_choices:
		widest = maxf(widest, _text_units(verb))
	var layout: TagLayout.Tag = TagLayout.verb_tag(parent, _tag_choices.size(), widest)
	var colors: Array[Color] = []
	for i: int in _tag_choices.size():
		colors.append(_TAG_TEXT_ON if i == _tag_index else _TAG_TEXT_OFF)
	var fresh: bool = not _tag_popup.visible or _verb_closing
	_verb_closing = false
	if fresh:
		_verb_open = 0.0
	_tag_popup.show_tag(layout, _VERB_MODELS, _tag_choices, colors, _tag_index)
	_tag_popup.set_open_scale(_verb_open)


## `mIV_set_dl` draws all three pages every frame, back to front. A page that is up draws in full
## (`mIV_up_page_draw_check`); the others draw only their frame: the pockets' empty rings and
## labels, an encyclopedia page's tab (`inv_*_part_model`).
func _show_pages(up: Array) -> void:
	var pockets_up: bool = up.has(SideTab.POCKETS)
	if _pocket_contents.is_empty():
		for n: CanvasItem in [_town_name, _player_name, _wallet.get_parent() as CanvasItem]:
			_pocket_contents.append(n)
		if _portrait_viewport != null:
			_pocket_contents.append(_portrait_viewport.get_parent() as CanvasItem)
	for n: CanvasItem in _pocket_contents:
		n.visible = pockets_up
	for btn: Button in _slot_buttons + _mail_buttons + _gyroid_buttons:
		var icon: TextureRect = btn.get_node_or_null("ItemIcon") as TextureRect
		if icon != null:
			icon.self_modulate.a = 1.0 if pockets_up else 0.0
	if _portrait_viewport != null and _open:
		_portrait_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if pockets_up else SubViewport.UPDATE_DISABLED
		)
	for page: SideTab in [SideTab.FISH, SideTab.BUG]:
		var node: InventoryCollectPage = _collect_page(page)
		node.set_full(up.has(page))
		if up.has(page):
			node.populate(Game.species_log)


func _collect_page(page: SideTab) -> InventoryCollectPage:
	return _fish_page if page == SideTab.FISH else _bug_page


func _page_node(page: SideTab) -> Control:
	return _shell_stack if page == SideTab.POCKETS else _collect_page(page)


## Back to the pockets on top, every page home.
func _reset_pages() -> void:
	if _page_tween != null:
		_page_tween.kill()
	_page_moving = false
	_page_order = [SideTab.POCKETS, SideTab.FISH, SideTab.BUG]
	_restack_pages()
	for page: SideTab in PAGE_ORDER:
		_page_node(page).position.y = 0.0
	_show_pages([SideTab.POCKETS])


## `page_order[2]` is drawn first, `page_order[0]` last.
func _restack_pages() -> void:
	for i: int in _page_order.size():
		_pages.move_child(_page_node(_page_order[_page_order.size() - 1 - i]), i)


## `mIV_move_Play` with `page_move_timer` = 40: the page coming up rises and the others drop, the
## order flips at the midpoint, then everything settles. The hand is gone until it ends.
func _start_page_move(next: SideTab) -> void:
	if _page_tween != null:
		_page_tween.kill()
	if uses_mobile_layout():
		## The phone sheet has its own pages; nothing shuffles.
		_bring_page_up(next)
		_show_pages([next])
		return
	_page_moving = true
	_page_swapped = false
	_page_next = next
	if _hand_tween != null:
		_hand_tween.kill()
	if _hand_root != null:
		_hand_root.visible = false
	_page_tween = create_tween()
	_page_tween.tween_method(_step_page_move, float(PAGE_MOVE_TICKS), 0.0, PAGE_MOVE_DURATION)
	_page_tween.tween_callback(_finish_page_move)


## `page_order` after the flip: the new page on top, the others keep their relative order.
func _bring_page_up(page: SideTab) -> void:
	if _page_order[2] == page:
		_page_order[2] = _page_order[1]
	_page_order[1] = _page_order[0]
	_page_order[0] = page
	_restack_pages()


func _step_page_move(timer: float) -> void:
	var y: float = PAGE_MOVE_UNITS * sin(timer * PI / float(PAGE_MOVE_TICKS)) * _units_to_px()
	for page: SideTab in PAGE_ORDER:
		_page_node(page).position.y = -y if page == _page_next else y
	if not _page_swapped and timer <= PAGE_MOVE_SWAP_TICK:
		_page_swapped = true
		_bring_page_up(_page_next)
	if timer > PAGE_MOVE_SWAP_TICK:
		_show_pages([_page_next, _page_order[0]])
	else:
		_show_pages([_page_order[0], _page_order[1]])


func _finish_page_move() -> void:
	for page: SideTab in PAGE_ORDER:
		_page_node(page).position.y = 0.0
	_show_pages([_page_order[0]])
	_page_moving = false
	_update_hand_cursor(false)


## Mirror field equipment: bind the held tool mesh; the portrait body keeps its
## `mIV_ANIM_*` clip (WALK by default) and the tool follows the hand joint.
func _sync_portrait_equipment(force: bool = false) -> void:
	if _portrait_pivot == null:
		return
	var eq_id: StringName = &""
	eq_id = Game.inventory.equipment_id
	if not force and eq_id == _portrait_equipment_id:
		return
	var equip_changed: bool = (not force) and eq_id != _portrait_equipment_id
	_portrait_equipment_id = eq_id
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_portrait_pivot)
	HeldTool.unbind(skeleton)
	var tool: ToolData = ItemCatalog.get_item(eq_id) as ToolData
	if tool != null and tool.visual_id != &"":
		var attach: Node3D = HeldTool.bind(skeleton, tool.visual_id)
		HeldTool.play(skeleton, tool.visual_hold_anim, true)
		## `mIV_umbrella_data`: the doll holds the umbrella open (handle + canopy split).
		if tool.kind == ToolData.Kind.UMBRELLA and attach != null and attach.get_child_count() > 0:
			HeldUmbrella.new().setup(attach.get_child(0) as Node3D, HeldUmbrella.Action.OPEN_NOW)
			HeldUmbrella.paint_canopy(attach.get_child(0) as Node3D, HeldUmbrella.design_texture(tool))
	## `mIV_pl_check_anm_change`: an equip swap plays CHANGE1, everything else rests.
	if equip_changed:
		_set_portrait_anim(PortraitAnim.CHANGE)
	else:
		_set_portrait_anim(_portrait_rest)


## Mirror the field player's worn top (`player.gd::_apply_worn_cloth`) onto the
## portrait doll — previously the doll only ever wore its base skin, regardless of
## what shirt/design the player actually had on.
func _sync_portrait_cloth() -> void:
	if _portrait_pivot == null:
		return
	if Game.resident.worn_design_slot >= 0:
		var design: DesignPattern = Game.designs.resolved(Game.resident.worn_design_slot)
		if design != null:
			VisualCloth.apply_design(_portrait_pivot, DesignTexture.build(design))
			return
	var data: ItemData = ItemCatalog.get_item(Game.resident.cloth_id)
	var index: int = data.cloth_index if data != null else -1
	if index < 0 and Game.resident.cloth_id != &"":
		var raw := String(Game.resident.cloth_id)
		if raw.begins_with("shirt_"):
			index = int(raw.substr(6))
	if index < 0:
		return
	VisualCloth.apply_cloth(_portrait_pivot, index)


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


func menu_rect() -> Rect2:
	var rect: Rect2 = MenuFrame.rect_of(_shell_stack)
	return rect


func dismiss() -> void:
	if is_open():
		_unhandled_input(WindowDismiss.escape_key())


func uses_mobile_layout() -> bool:
	return InputDeviceTracker.uses_mobile_ui() and _gyroid_house == null


func _mobile_page() -> String:
	if _focus_mail:
		return "letters"
	match _side_tab:
		SideTab.FISH:
			return "fish"
		SideTab.BUG:
			return "insects"
		_:
			return "items"


func _on_layout_changed() -> void:
	if _open:
		_refresh()


func _refresh_mobile_layout() -> void:
	var mobile := uses_mobile_layout()
	_mobile.visible = mobile
	_classic.visible = not mobile
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE if mobile else Control.MOUSE_FILTER_STOP
	_back_to_items.visible = false
	if mobile:
		var page := _mobile_page()
		_mobile.show_page(page)
		match page:
			"letters":
				_mobile.refresh_letters(Game.inventory)
			"fish":
				_mobile.refresh_collection(&"fish")
			"insects":
				_mobile.refresh_collection(&"insect")
			_:
				_mobile.refresh(Game.inventory)
	if _portrait_viewport != null:
		_portrait_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if _open and not mobile else SubViewport.UPDATE_DISABLED
		)


func _on_mobile_page(page: String) -> void:
	_cancel_mobile_actions()
	_focus_player = false
	_focus_gyroid = false
	match page:
		"letters":
			if _side_tab != SideTab.POCKETS:
				_select_side_tab(SideTab.POCKETS)
			_focus_mail = true
			_focus_player = false
		"fish":
			_focus_mail = false
			_select_side_tab(SideTab.FISH)
		"insects":
			_focus_mail = false
			_select_side_tab(SideTab.BUG)
		_:
			_focus_mail = false
			if _side_tab != SideTab.POCKETS:
				_select_side_tab(SideTab.POCKETS)
	_refresh()


func _cancel_mobile_actions() -> void:
	_tag_mode = false
	_wallet_tag_mode = false
	_background_tag_mode = false
	_refresh()


## Open straight to the Letters page (mailbox / "you've got mail").
func open_letters() -> void:
	open()
	if _open:
		_focus_mail = true
		_side_tab = SideTab.POCKETS
		Game.inventory.select_mail(Game.inventory.last_used_mail_index())
		_refresh()


## Intro down payment: open on the money bag with Hand over already showing.
func present_handover(item_id: StringName) -> bool:
	open()
	if not _open:
		return false
	_ignore_close_once = true
	call_deferred("_release_close_guard")
	if _restore_layer < 0:
		_restore_layer = layer
	layer = 30
	var idx := -1
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = Game.inventory.slot_at(i)
		if slot != null and not slot.is_empty() and slot.item.item_id == item_id:
			idx = i
			break
	if idx >= 0:
		Game.inventory.select(idx)
		_tag_choices = Game.inventory.tags_for_slot(idx)
		if not _tag_choices.is_empty():
			_tag_mode = true
			_tag_index = 0
			_focus_mail = false
			_focus_player = false
			_mobile.reveal_slot(idx)
	_refresh()
	return true


func _release_close_guard() -> void:
	_ignore_close_once = false


func open() -> void:
	if _open:
		return
	_open = true
	_tag_mode = false
	_focus_mail = false
	_focus_player = false
	_side_tab = SideTab.POCKETS
	_portrait_rest = PortraitAnim.WALK
	_reset_pages()
	Audio.play_se(&"menu_pause")
	## `mBGMPsComp_pause(PAUSE_1)` (`m_inventory_ovl`).
	Audio.set_music_pause(Audio.PAUSE_POCKETS)
	_root.visible = true
	_slide.cover_viewport = uses_mobile_layout()
	_slide.slide_in(MenuSlide.Dir.IN_BOTTOM if uses_mobile_layout() else MenuSlide.Dir.IN_RIGHT)
	if _portrait_viewport != null:
		_portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _hand_viewport != null:
		_hand_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Game.inventory.clear_hand()
	Game.inventory.bury_ready = PlantGrowth.scoop_plant_ready(_field_context())
	_find_release_water()
	_sync_portrait_equipment(true)
	_sync_portrait_cloth()
	_play_hand_clip("hnd_sasu", true)
	_refresh()
	_update_hand_cursor(false)
	get_tree().paused = false


## Open the pockets with the house gyroid's table (`mSM_OVL_HANIWA`). `owner`: the house's
## owner consigning items; else a visitor taking them.
func open_gyroid(house: House, owner: bool) -> void:
	if house == null:
		return
	GyroidStore.ensure(house)
	open()
	if not _open:
		return
	_gyroid_house = house
	_gyroid_owner = owner
	_focus_gyroid = false
	_gyroid_sel = 0
	_set_gyroid_visible(true)
	_refresh()


func close() -> void:
	if _ignore_close_once:
		_ignore_close_once = false
		return
	if not _open:
		return
	if _restore_layer >= 0:
		layer = _restore_layer
		_restore_layer = -1
	var mobile := uses_mobile_layout()
	Audio.play_se(&"menu_exit")
	Audio.set_music_pause(1.0)
	_gyroid_house = null
	_focus_gyroid = false
	_gyroid_tag_mode = false
	_price_mode = false
	_gyroid_interrupt = ""
	_set_gyroid_visible(false)
	closed.emit()
	_open = false
	_tag_mode = false
	_pending_mail_discard = -1
	_wallet_tag_mode = false
	_background_tag_mode = false
	_hide_tag_popup()
	_focus_mail = false
	_focus_player = false
	_side_tab = SideTab.POCKETS
	## Closing the pockets during the intro payment without handing anything over is
	## Nook's "pay it all back" nag (`aNRG_menu_close_wait_talk_proc` empty branch).
	Game.intro.payment_declined()
	Game.pocket_requests.cancel_all()
	if _hand_root != null:
		_hand_root.visible = false
	if _portrait_viewport != null:
		_portrait_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Game.inventory.clear_hand()
	## Classic pockets use `mSM_MOVE_OUT_RIGHT`; the mobile sheet leaves downward.
	_slide.cover_viewport = mobile
	_slide.slide_out(MenuSlide.Dir.OUT_BOTTOM if mobile else MenuSlide.Dir.OUT_RIGHT, _on_slid_out)
	_refresh()


func _on_slid_out() -> void:
	if _open:
		return
	_root.visible = false
	if _hand_viewport != null:
		_hand_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		var talk := DialogueOverlay.find(get_tree())
		if talk != null and talk.is_open():
			get_viewport().set_input_as_handled()
			return
		if Menus.is_open(get_tree(), &"shop_ui"):
			get_viewport().set_input_as_handled()
			return
		var map_ui: MapOverlay = MapOverlay.find(get_tree())
		if map_ui != null and bool(map_ui.is_open()):
			get_viewport().set_input_as_handled()
			return
		var console: DebugConsoleOverlay = DebugConsoleOverlay.find(get_tree())
		if console != null and console.is_open():
			get_viewport().set_input_as_handled()
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if _page_moving:
		## `page_move_timer != 0`: the menu does nothing until the pages settle.
		if event.is_pressed():
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_focus_next") or (
		event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB
	):
		## Tab = items ↔ letters (pencil / face). Shift+Tab / [ ] cycle all four side tabs.
		var shift: bool = event is InputEventKey and (event as InputEventKey).shift_pressed
		if shift:
			_cycle_side_tab(-1)
		elif _gyroid_house != null:
			## The gyroid table stands in for the letters while it's open.
			_focus_gyroid = not _focus_gyroid
			_tag_mode = false
			_gyroid_tag_mode = false
			_refresh()
			_update_hand_cursor(true)
		else:
			_focus_mail = not _focus_mail
			_focus_player = false
			_side_tab = SideTab.POCKETS
			_tag_mode = false
			_pending_mail_discard = -1
			_wallet_tag_mode = false
			_background_tag_mode = false
			## Switching between the item table and the mail table clears marks too.
			Game.inventory.clear_marks()
			_refresh()
			_update_hand_cursor(true)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_BRACKETLEFT:
			_turn_page(-1)
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_BRACKETRIGHT:
			_turn_page(1)
			get_viewport().set_input_as_handled()
			return
	if _price_mode:
		_handle_price_input(event)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel"):
		if _tag_mode:
			_gyroid_tag_mode = false
			_tag_mode = false
			_pending_mail_discard = -1
			_wallet_tag_mode = false
			_background_tag_mode = false
			_refresh()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	if _tag_mode:
		_handle_tag_input(event)
		return
	if uses_mobile_layout() and _handle_mobile_navigation(event):
		get_viewport().set_input_as_handled()
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
	if _focus_player:
		## The player doll is a single 1×1 slot — only "down" leads back to the grid,
		## matching how `mTG_move_cursol_between_table_inventory` re-enters the item table.
		if event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
			_focus_player = false
			_update_hand_cursor(true)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
			_activate_cursor()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("inventory_quick_grab"):
			_quick_grab_drop()
			get_viewport().set_input_as_handled()
		return
	if _focus_gyroid:
		_gyroid_navigate(event)
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		if _focus_mail:
			var col: int = Game.inventory.selected_mail_index % Inventory.MAIL_COLUMNS
			@warning_ignore("integer_division")
			var row: int = Game.inventory.selected_mail_index / Inventory.MAIL_COLUMNS
			## The item (5x3) and mail (2x5) grids sit side by side, bottom-aligned — mail
			## row `r` lines up with item row `r - MAIL_ROW_OFFSET`. Off the mail grid's
			## left edge on an aligned row steps straight into the item grid, same as the
			## original's single shared cursor (no Tab needed).
			if col == 0 and row >= MAIL_ROW_OFFSET:
				_focus_mail = false
				Game.inventory.select((row - MAIL_ROW_OFFSET) * Inventory.COLUMNS + (Inventory.COLUMNS - 1))
			else:
				Game.inventory.move_mail_cursor(-1, 0)
		else:
			Game.inventory.move_cursor(-1, 0)
		_update_hand_cursor(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		if _focus_mail:
			Game.inventory.move_mail_cursor(1, 0)
		else:
			var col: int = Game.inventory.selected_index % Inventory.COLUMNS
			@warning_ignore("integer_division")
			var row: int = Game.inventory.selected_index / Inventory.COLUMNS
			if col == Inventory.COLUMNS - 1 and _gyroid_house != null:
				## `mTG_move_cursol_between_table_haniwa`: off the pockets' right edge.
				_focus_gyroid = true
				_gyroid_sel = clampi(row, 0, GYROID_ROWS - 1) * GYROID_COLS
			elif col == Inventory.COLUMNS - 1:
				_focus_mail = true
				Game.inventory.select_mail((row + MAIL_ROW_OFFSET) * Inventory.MAIL_COLUMNS)
			else:
				Game.inventory.move_cursor(1, 0)
		_update_hand_cursor(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		if _focus_mail:
			if Game.inventory.selected_mail_index < Inventory.MAIL_COLUMNS:
				## Top row — the player doll sits above both grids (`mTG_TABLE_PLAYER`).
				_focus_player = true
			else:
				Game.inventory.move_mail_cursor(0, -1)
		elif Game.inventory.selected_index < Inventory.COLUMNS:
			## Top row — the player doll sits above the grid (`mTG_TABLE_PLAYER`).
			_focus_player = true
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
	elif event.is_action_pressed("inventory_quick_grab") and not _focus_mail:
		## `mTG_move_catch` (L): grab/drop in one press, skipping the verb popup.
		_quick_grab_drop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory_mark") and not _focus_mail:
		## `mTG_mark_proc` (X): toggle multi-select on the slot under the cursor.
		_toggle_mark()
		get_viewport().set_input_as_handled()


func _handle_mobile_navigation(event: InputEvent) -> bool:
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if _mobile.page() == "fish" or _mobile.page() == "insects":
			return true
		_activate_cursor()
		return true
	var step := Vector2i.ZERO
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		step.x = -1
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		step.x = 1
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		step.y = -1
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		step.y = 1
	else:
		return false
	var page := _mobile.page()
	if page == "letters":
		var index := clampi(Game.inventory.selected_mail_index + step.x + step.y, 0, Inventory.MAIL_SLOTS - 1)
		Game.inventory.select_mail(index)
		_mobile.reveal_letter(index)
		return true
	if page == "fish" or page == "insects":
		var index := _mobile.collection_index()
		var column := clampi(index % MobileInventory.COLUMNS + step.x, 0, MobileInventory.COLUMNS - 1)
		@warning_ignore("integer_division")
		var row := maxi(index / MobileInventory.COLUMNS + step.y, 0)
		var target := mini(row * MobileInventory.COLUMNS + column, EncyclopediaCatalog.COLLECT_NUM - 1)
		_mobile.select_collection(target)
		return true
	var slot := Game.inventory.selected_index
	var column := clampi(slot % MobileInventory.COLUMNS + step.x, 0, MobileInventory.COLUMNS - 1)
	@warning_ignore("integer_division")
	var row := maxi(slot / MobileInventory.COLUMNS + step.y, 0)
	var target := mini(row * MobileInventory.COLUMNS + column, Inventory.POCKET_SLOTS - 1)
	Game.inventory.select(target)
	_mobile.reveal_slot(target)
	return true


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
	_focus_player = false
	_wallet_tag_mode = false
	_background_tag_mode = false
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


## `mTG_move_catch` (L quick grab/drop): pick straight into the hand, or place/swap
## whatever's held — the verb popup never opens. Only meaningful on the pockets grid;
## mail and the read-only collection pages have their own gestures.
func _quick_grab_drop() -> void:
	var inv: Inventory = Game.inventory
	var idx: int = inv.selected_index
	if inv.hand_index >= 0:
		inv.place_hand(idx)
		Audio.play_se(&"60")
		_play_hand_clip("hnd_catch", false)
		get_tree().create_timer(0.35).timeout.connect(func() -> void: _play_hand_clip("hnd_sasu", true))
	else:
		if not inv.pick_hand(idx):
			return
		_play_hand_clip("hnd_catch", false)
		get_tree().create_timer(0.35).timeout.connect(func() -> void: _play_hand_clip("hnd_side", true))
	_refresh()
	_update_hand_cursor(true)


## `mTG_mark_proc` (X): toggle the multi-select mark on whatever's under the cursor.
func _toggle_mark() -> void:
	var inv: Inventory = Game.inventory
	if inv.slot_at(inv.selected_index) == null or inv.slot_at(inv.selected_index).is_empty():
		return
	var on: bool = inv.toggle_mark(inv.selected_index)
	Audio.play_se(&"cursol" if on else &"41c")
	_refresh()


## `mTG_TABLE_MONEY`, hand empty: clicking the wallet opens the denomination picker
## (only amounts you can currently afford), matching `mTG_select_tag_decide_money`.
## Hand full: dropping a money-bag item here deposits it (mirrors `mHD_open_sack`) —
## this port's "Use" verb already deposits bags too, so this is a second, faithful path
## to the same result rather than the only way in.
func _on_wallet_gui(event: InputEvent) -> void:
	if not _click_event(event):
		return
	get_viewport().set_input_as_handled()
	_open_wallet_popup()


func _open_wallet_popup() -> void:
	if not _open or _tag_mode:
		return
	var inv: Inventory = Game.inventory
	if inv.hand_index >= 0:
		_deposit_hand_bag()
		return
	var denoms: Array[int] = inv.withdrawable_denominations()
	if denoms.is_empty():
		return
	_tag_choices = PackedStringArray()
	## `mTG_money_sack1..4`: the amounts you can take out, then Quit.
	for amount: int in denoms:
		_tag_choices.append("%d" % amount)
	_tag_choices.append("Quit")
	_tag_index = 0
	_wallet_tag_mode = true
	_tag_mode = true
	Audio.play_se(&"41c")
	_refresh()


func _deposit_hand_bag() -> void:
	var inv: Inventory = Game.inventory
	var slot: InventorySlot = inv.slot_at(inv.hand_index)
	if slot == null or slot.is_empty():
		return
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data == null or data.bell_value <= 0:
		return ## only money bags deposit here
	var hand_idx: int = inv.hand_index
	inv.clear_hand()
	inv.remove_from_slot(hand_idx, 1)
	inv.add_bells(data.bell_value)
	Audio.play_se(&"52")
	Game.post_notice("Deposited %d Bells" % data.bell_value)
	_refresh()
	_update_hand_cursor(true)


func _run_wallet_tag(tag: String) -> void:
	_wallet_tag_mode = false
	_tag_mode = false
	var amount: int = tag.to_int()
	if amount > 0:
		if Game.inventory.withdraw_to_hand(amount):
			Audio.play_se(&"52")
			Game.post_notice("Withdrew %d Bells" % amount)
		else:
			Game.post_notice("Pockets are full")
	_refresh()
	_update_hand_cursor(true)


## Test-only: no in-game callers; kept for tests.
func _open_background_slot() -> void:
	if not _open or _tag_mode:
		return
	if Game.inventory.background_id == &"":
		Game.post_notice("No background set")
		return
	_tag_choices = PackedStringArray(["Remove"])
	_tag_index = 0
	_background_tag_mode = true
	_tag_mode = true
	Audio.play_se(&"41c")
	_refresh()


func _run_background_tag(tag: String) -> void:
	_background_tag_mode = false
	_tag_mode = false
	if tag == "Remove":
		Game.inventory.set_background(&"")
		_refresh_background()
		Game.post_notice("Background cleared")
	_refresh()


## Left click only: fingers arrive here too, as the mouse clicks
## `emulate_mouse_from_touch` makes, so also taking the touch fired twice.
func _click_event(event: InputEvent) -> bool:
	return (
		event is InputEventMouseButton and (event as InputEventMouseButton).pressed
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	)


func _activate_cursor() -> void:
	if _focus_gyroid:
		_activate_gyroid_cursor()
		return
	if _focus_player:
		_activate_player_cursor()
		return
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
	_tag_choices = inv.tags_for_slot(idx, uses_mobile_layout())
	if _tag_choices.is_empty():
		return
	_tag_mode = true
	_tag_index = 0
	Audio.play_se(&"41c")
	_refresh()


## `mTG_TABLE_PLAYER`, hand empty: pressing A on the player doll offers to take off
## whatever's equipped — the swap-in direction (hand full) is `_equip_hand_on_player`.
## Reuses the ordinary "Unequip" tag/case (`Inventory.unequip`, `_run_tag`), which doesn't
## care which slot the popup was opened from.
func _activate_player_cursor() -> void:
	var inv: Inventory = Game.inventory
	if inv.hand_index >= 0:
		_equip_hand_on_player()
		return
	if inv.equipment_id == &"":
		return
	## `mTG_select_tag_decide_player`: the equipped tool offers `mTG_TYPE_CATCH_ITEM`.
	_tag_choices = PackedStringArray(["Grab", "Quit"])
	_tag_index = 0
	_tag_mode = true
	Audio.play_se(&"41c")
	_refresh()


## `mHD_open_end_proc_item_type3`: dropping a held tool/clothing item onto the player doll
## equips/wears it. This port's equip is a reference (the item stays in its pocket slot,
## `Inventory.equip_slot`), so "dropping" here just runs that and clears the hand rather
## than physically moving the item.
func _equip_hand_on_player() -> void:
	var inv: Inventory = Game.inventory
	var hand_idx: int = inv.hand_index
	var slot: InventorySlot = inv.slot_at(hand_idx)
	if slot == null or slot.is_empty():
		inv.clear_hand()
		return
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data == null:
		return
	if data.equippable:
		inv.clear_hand()
		if inv.equip_slot(hand_idx):
			Game.post_notice("Equipped %s" % data.display_name)
	elif data.category == ItemData.Category.CLOTH:
		inv.clear_hand()
		if Game.wear_cloth_from_slot(hand_idx):
			Game.post_notice("Wearing %s" % data.display_name)
	elif data.usable and data.use_verb == "Eat":
		## `mIV_ANIM_EAT`: food dropped on the player picture is eaten (EAT1 in the portrait,
		## the bite on the clip's frame 17).
		inv.clear_hand()
		_set_portrait_anim(PortraitAnim.EAT)
		get_tree().create_timer(17.0 / DecompTime.FRAME_HZ).timeout.connect(func() -> void: Audio.play_se(&"eat"))
		var eaten: String = inv.use_slot(hand_idx)
		if eaten != "":
			Game.post_notice(eaten)
	else:
		return
	_refresh()
	_update_hand_cursor(true)


func _activate_mail_cursor() -> void:
	var inv: Inventory = Game.inventory
	var idx: int = inv.selected_mail_index
	var mail: MailData = inv.mail_at(idx)
	_tag_choices = PackedStringArray()
	## An empty letter slot offers nothing (`mTG_select_tag_decide_mail`); letters are written
	## from stationery ("Write Letter").
	if mail == null or mail.is_empty():
		return
	if mail.is_received():
		## `mTG_def_rmail`: Read, Grab, Throw Away, Quit (Grab needs a hand for letters, which
		## this port does not have, so it is left out).
		_tag_choices.append("Read")
		if mail.has_enclosure():
			_tag_choices.append("Take")
	else:
		## `mTG_present_proc` (`mTG_catch_item_from_table`) - one verb, both directions:
		## a held item attaches as the gift; with an empty hand and a gift already
		## attached, the same verb takes it back.
		if inv.hand_index >= 0 and mail.present_item_id == &"":
			_tag_choices.append("Present")
		elif inv.hand_index < 0 and mail.present_item_id != &"":
			_tag_choices.append("Present")
	_tag_choices.append("Throw Away")
	_tag_choices.append("Quit")
	_tag_mode = true
	_tag_index = 0
	_refresh()


func _run_tag(tag: String) -> void:
	if _gyroid_tag_mode:
		_run_gyroid_tag(tag)
		return
	if _wallet_tag_mode:
		_run_wallet_tag(tag)
		return
	if _background_tag_mode:
		_run_background_tag(tag)
		return
	if _focus_mail:
		_run_mail_tag(tag)
		return
	var inv: Inventory = Game.inventory
	var idx: int = inv.selected_index
	match tag:
		"Quit":
			_cancel_tag_mode()
			return
		"Grab":
			_grab_selected()
			return
		"Write Letter":
			## `mTG_write_proc`: out of the pockets and into the letter paper picker.
			close()
			_open_write_letter()
			return
		"Put on Wall", "Spread on Floor":
			var slot: InventorySlot = inv.slot_at(idx)
			if slot != null and not slot.is_empty():
				FurnitureEditing.apply_cover(ItemCatalog.get_item(slot.item.item_id))
			close()
		"Drop":
			## Your own room puts furniture down in the room (`mTG_room_put_proc`); anywhere
			## else the item lands on the ground (`mTG_field_put_proc`).
			var drop_slot: InventorySlot = inv.slot_at(idx)
			var drop_data: ItemData = ItemCatalog.get_item(drop_slot.item.item_id) if drop_slot != null and not drop_slot.is_empty() else null
			if Game.is_decorating() and drop_data is FurnitureData:
				var placer := Player.find(get_tree())
				if placer != null:
					FurnitureEditing.place_held(placer)
				close()
			else:
				_drop_selected()
		"Drop All":
			_drop_all_marked()
		## Touch shortcuts for the drop-on-the-player-picture gestures (`tags_for_slot`).
		"Set Background":
			var cloth_slot: InventorySlot = inv.slot_at(idx)
			if cloth_slot != null and not cloth_slot.is_empty():
				inv.set_background(cloth_slot.item.item_id)
				_refresh_background()
				Game.post_notice("Pockets backdrop changed")
		"Equip":
			if inv.equip_slot(idx):
				var data: ItemData = ItemCatalog.get_item(inv.equipment_id)
				if data != null:
					Game.post_notice("Equipped %s" % data.display_name)
		"Unequip":
			var equipped: ItemData = ItemCatalog.get_item(inv.equipment_id)
			inv.unequip()
			if equipped != null:
				Game.post_notice("Put away %s" % equipped.display_name)
		"Wear":
			if Game.wear_cloth_from_slot(idx):
				var worn: ItemData = ItemCatalog.get_item(Game.resident.cloth_id)
				if worn != null:
					Game.post_notice("Wearing %s" % worn.display_name)
				if Game.first_job.cloth_job_finished():
					Game.set_interact_prompt("Talk to Tom Nook")
				close()
		"Eat":
			_set_portrait_anim(PortraitAnim.EAT)
			get_tree().create_timer(17.0 / DecompTime.FRAME_HZ).timeout.connect(func() -> void: Audio.play_se(&"eat"))
			var eat_msg: String = inv.use_slot(idx)
			if eat_msg != "":
				Game.post_notice(eat_msg)
		"Give":
			if Game.pocket_requests.donation_pending:
				## Blathers is waiting (`mTG_tag_hand_over_curator`): book the outcome and let his
				## dialogue respond.
				var gift: InventorySlot = inv.slot_at(idx)
				if gift != null and not gift.is_empty():
					Game.pocket_requests.take_donation(gift.item.item_id)
				close()
				return
			if Game.pocket_requests.handover_pending:
				## A villager's quest — the talk plays the hand-over.
				Game.pocket_requests.take_handover(idx)
				close()
				return
			## Intro down payment — Nook's director plays the hand-over and books it.
			## The opening tap's Close is ignored for one press; handing the bag over
			## must still put the pockets away.
			Game.intro.payment_made()
			_ignore_close_once = false
			close()
		"Put Away":
			## A drawer or music player is waiting — hand the pick back to it.
			var putin_slot: InventorySlot = inv.slot_at(idx)
			if putin_slot != null and not putin_slot.is_empty():
				Game.pocket_requests.take_putin(putin_slot.item.item_id)
			close()
		"Sell":
			Game.pocket_requests.take_sell([idx] as Array[int])
			close()
		"Sell All":
			var picked: Array[int] = inv.marked_indices()
			inv.clear_marks()
			Game.pocket_requests.take_sell(picked)
			close()
		"Open":
			var slot: InventorySlot = inv.slot_at(idx)
			if slot == null or slot.is_empty():
				pass
			elif slot.item.condition == InventoryItem.Condition.PRESENT:
				slot.item.condition = InventoryItem.Condition.NORMAL
				## `mTG_present_open_proc`.
				Audio.play_se(&"436")
				inv.changed.emit()
				Game.post_notice("Opened present")
			else:
				## Money bags (`ITM_MONEY_START`) also use "Open" as their verb
				## (`mHD_open_sack`) — only wrapped presents get the unwrap above.
				var msg: String = inv.use_slot(idx)
				if msg != "":
					Game.post_notice(msg)
		"Release":
			## `mTG_release_proc`: out of the pockets, then the player lets it go.
			var rel_slot: InventorySlot = inv.slot_at(idx)
			if rel_slot == null or rel_slot.is_empty():
				return
			var rel_data: ItemData = ItemCatalog.get_item(rel_slot.item.item_id)
			var rel_water: Variant = inv.release_water
			var rel_player: Player = Player.find(get_tree())
			inv.remove_from_slot(idx, 1)
			close()
			if rel_player != null:
				rel_player.sequences.release_from_pocket(rel_data, rel_water)
		"Bury":
			## `mTG_TYPE_FIELD_DEFAULT_BURY`: put it in the hole and scoop it shut.
			var bury_ctx: InteractionContext = _field_context()
			var bury_cell: Vector2i = ToolUse.facing_cell(bury_ctx)
			var bury_slot: InventorySlot = inv.slot_at(idx)
			if bury_slot == null or bury_slot.is_empty():
				return
			var buried_id: StringName = bury_slot.item.item_id
			var buried: ItemData = ItemCatalog.get_item(buried_id)
			inv.remove_from_slot(idx, 1)
			close()
			if BuriedUse.bury(bury_ctx, bury_cell, buried_id):
				Audio.play_se(&"scoop_umeru")
				Game.post_notice("Buried %s." % (buried.display_name if buried != null else "it"))
			elif buried != null:
				inv.add(buried, 1)
				Game.post_notice("Can't bury it here.")
		"Plant":
			## `mTG_plant_proc`: shovel+hole → putin scoop; else throw-put on the facing unit.
			var taken: Dictionary = PlantGrowth.take_plant_from_slot(_field_context(), idx)
			if not bool(taken.get("ok", false)):
				var fail: String = str(taken.get("msg", ""))
				if fail != "":
					Game.post_notice(fail)
			else:
				close()
				var player := Player.find(get_tree())
				if player != null:
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
				if Game.first_job.plant_job_finished(Game.inventory):
					Game.first_job.mark_plant_finished()
					Game.set_interact_prompt("Talk to Tom Nook")
		_:
			var msg: String = inv.use_slot(idx)
			if msg != "":
				Game.post_notice(msg)
	_tag_mode = false
	_refresh()


## "Quit": back out of the verb window to the slot (the B button does the same).
func _cancel_tag_mode() -> void:
	_gyroid_tag_mode = false
	_tag_mode = false
	_pending_mail_discard = -1
	_wallet_tag_mode = false
	_background_tag_mode = false
	_refresh()


## "Grab" (`mTG_catch_proc`): the item goes into the hand. On the player picture it takes the
## equipped tool off its hook and into the hand.
func _grab_selected() -> void:
	var inv: Inventory = Game.inventory
	if _focus_player:
		var slot_index: int = inv.equipped_slot_index()
		if slot_index >= 0:
			inv.unequip()
			inv.pick_hand(slot_index)
		else:
			inv.unequip()
	else:
		inv.pick_hand(inv.selected_index)
	_play_hand_clip("hnd_catch", false)
	get_tree().create_timer(0.35).timeout.connect(func() -> void: _play_hand_clip("hnd_side", true))
	_cancel_tag_mode()
	_update_hand_cursor(true)


func _run_mail_tag(tag: String) -> void:
	var inv: Inventory = Game.inventory
	var idx: int = inv.selected_mail_index
	## `mTG_dump_mail` (Yes/No): the second tap confirms or cancels the pending discard,
	## reusing the same verb popup rather than a separate dialog widget.
	if _pending_mail_discard >= 0:
		var discard_idx: int = _pending_mail_discard
		_pending_mail_discard = -1
		if tag == "Yes":
			inv.remove_mail(discard_idx)
			## `mTG_dump_mail_proc`.
			Audio.play_se(&"435")
			Game.post_notice("Discarded letter")
		_tag_mode = false
		_refresh()
		return
	match tag:
		"Quit":
			_cancel_tag_mode()
			return
		"Read":
			_read_letter(inv.mail_at(idx))
		"Take":
			_take_letter_enclosure(idx)
		"Present":
			_present_on_mail(idx)
		"Throw Away":
			_pending_mail_discard = idx
			## `mTG_dump_mail`: Yes / Quit.
			_tag_choices = PackedStringArray(["Yes", "Quit"])
			_tag_index = 0
			_refresh()
			return
		_:
			pass
	_tag_mode = false
	_refresh()


## `mTG_open_board_init(..., mSM_BD_OPEN_READ, ...)` — the letter's actual stationery
## art with header/body/footer, not a text toast (`m_board_ovl.c`).
func _read_letter(mail: MailData) -> void:
	if mail == null or mail.is_empty():
		return
	var reader: LetterReaderOverlay = LetterReaderOverlay.find(get_tree())
	if reader == null:
		Game.post_notice(mail.body if mail.body.strip_edges() != "" else mail.header)
		return
	reader.open(mail)


func _take_letter_enclosure(idx: int) -> void:
	var inv: Inventory = Game.inventory
	var mail: MailData = inv.mail_at(idx)
	if mail == null or not mail.has_enclosure():
		return
	var item: ItemData = ItemCatalog.get_item(mail.present_item_id)
	if item == null:
		Game.post_notice("The enclosure is missing.")
		return
	var count: int = maxi(1, mail.present_count)
	if not inv.has_space_for(item, count):
		Game.post_notice("Your pockets are full.")
		return
	inv.add(item, count)
	mail.present_item_id = &""
	mail.present_count = 1
	mail.mark_read()
	inv.mail_changed.emit()
	Game.post_notice("You took the %s." % item.display_name)


## `mTG_present_proc`/`mTG_catch_item_from_table` (`m_tag_ovl.c:4672-4685`) — one verb,
## both directions, same "drop hand contents onto a special slot" shape already used
## for the equip-on-player and background-slot drops: a held item leaves pockets and
## becomes the letter's gift; with an empty hand and a gift already attached, it comes
## back out into an empty pocket slot instead.
func _present_on_mail(idx: int) -> void:
	var inv: Inventory = Game.inventory
	var mail: MailData = inv.mail_at(idx)
	if mail == null:
		return
	if mail.present_item_id == &"" and inv.hand_index >= 0:
		var removed: InventoryItem = inv.remove_from_slot(inv.hand_index, 1)
		inv.clear_hand()
		if removed.is_empty():
			return
		mail.present_item_id = removed.item_id
		inv.mail_changed.emit()
		var data: ItemData = ItemCatalog.get_item(removed.item_id)
		Game.post_notice("Attached %s to the letter." % (data.display_name if data != null else String(removed.item_id)))
	elif mail.present_item_id != &"" and inv.hand_index < 0:
		var data: ItemData = ItemCatalog.get_item(mail.present_item_id)
		if data == null:
			mail.present_item_id = &""
			inv.mail_changed.emit()
			return
		if not inv.has_space_for(data, 1):
			Game.post_notice("Your pockets are full.")
			return
		inv.add(data, 1)
		mail.present_item_id = &""
		inv.mail_changed.emit()
		Game.post_notice("Took back %s." % data.display_name)


## `mTG_write_proc` → `mSM_OVL_BOARD` on the stationery, with the address book over it
## (`m_board_ovl.c` / `m_address_ovl.c`). With no stationery items in the port, the
## paper is picked first.
func _open_write_letter() -> void:
	var picker: LetterPaperPickerOverlay = LetterPaperPickerOverlay.find(get_tree())
	if picker == null:
		return
	picker.open()


func _drop_selected() -> void:
	var inv: Inventory = Game.inventory
	var removed: InventoryItem = inv.drop_slot(inv.selected_index, 1)
	if removed.is_empty():
		return
	var data: ItemData = ItemCatalog.get_item(removed.item_id)
	if data == null:
		return
	close()
	## `aSIGN_set_white_sign`: a signboard stands up where it is put.
	if data.id == SignboardUse.ITEM_ID:
		var sign_ctx: InteractionContext = _field_context()
		if Game.current_room_id != &"" or not SignboardUse.place(sign_ctx.world, ToolUse.facing_cell(sign_ctx)):
			inv.add(data, removed.count, removed.condition)
			Game.post_notice("Can't put it here")
			return
		Audio.play_se(&"item_horidashi")
		return
	if not _spawn_pickup(data, 0.0, removed.condition == InventoryItem.Condition.PRESENT):
		inv.add(data, removed.count, removed.condition)
		Game.post_notice("Can't drop here")
		return
	## `mTG_common_throw_put_field`: it lands on the unit with `NA_SE_2A`.
	var dropper := Player.find(get_tree())
	Audio.play_se(&"2a", dropper if dropper != null else self)
	Game.post_notice("Dropped %s" % data.display_name)


## `mTG_TYPE_TAG_PUT_ALL` ("Drop All"): pull every marked slot out first (so a full-count
## stack doesn't half-drop if a later slot turns out undroppable), then spawn one pickup
## per item with a little lateral spread so they don't land in a single pile.
func _drop_all_marked() -> void:
	var inv: Inventory = Game.inventory
	var indices: Array[int] = inv.marked_indices()
	if indices.is_empty():
		return
	var removed: Array[InventoryItem] = []
	for idx: int in indices:
		var slot: InventorySlot = inv.slot_at(idx)
		var count: int = slot.item.count if slot != null and not slot.is_empty() else 1
		var taken: InventoryItem = inv.drop_slot(idx, count)
		if not taken.is_empty():
			removed.append(taken)
	inv.clear_marks()
	close()
	var dropped: int = 0
	for i: int in removed.size():
		var item: InventoryItem = removed[i]
		var data: ItemData = ItemCatalog.get_item(item.item_id)
		if data == null:
			continue
		if _spawn_pickup(data, 0.0, item.condition == InventoryItem.Condition.PRESENT):
			dropped += 1
		else:
			inv.add(data, item.count, item.condition)
	if dropped > 0:
		Game.post_notice("Dropped %d item(s)" % dropped)
	else:
		Game.post_notice("Can't drop here")


## Lay the item on the unit in front, or the nearest free one (`FieldItems`), dropped from the
## player's hands. `_lateral_offset` is unused: each item finds its own unit.
func _spawn_pickup(item: ItemData, _lateral_offset: float = 0.0, wrapped: bool = false) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var player := Player.find(tree)
	var world := World.find(tree)
	if world == null and player != null and Game.interior_session != null:
		return _put_down_indoors(player, item, wrapped)
	if player == null or world == null or not (world.grid is WorldGrid):
		return false
	var grid: WorldGrid = world.grid
	var ctx: InteractionContext = _field_context()
	var front: Vector2i = ToolUse.facing_cell(ctx)
	var cell: Vector2i = FieldItems.drop_cell(grid, front, front - grid.world_to_cell(player.global_position))
	if cell.x < 0:
		return false
	var pickup: ItemPickup = FieldItems.put(world, cell, item.id, wrapped)
	if pickup == null:
		return false
	var land: Vector3 = pickup.global_position
	var start: Vector3 = player.global_position + Vector3(0.0, 50.0 * FieldCatalog.GX_TO_METERS, 0.0)
	pickup.begin_fall(start, land, 0.55)
	return true


## In your own house the item goes on the floor in front of you, or on the table there
## (`RoomItems`); other rooms hold nothing put down.
func _put_down_indoors(player: Player, item: ItemData, wrapped: bool) -> bool:
	var session: IndoorSession = Game.interior_session
	var facing: WorldGrid.Facing = WorldGrid.facing_from_player_yaw(player.facing_yaw())
	var front: Vector2i = session.grid.step(session.grid.world_to_cell(player.global_position), facing)
	var entry: FurniturePlacement = RoomItems.drop(session, front, item, wrapped)
	if entry == null:
		return false
	var host: Interior = Interior.find(get_tree())
	if host != null:
		host.spawn_placement(entry)
		if item is FurnitureData:
			var node := host.furniture_node(entry.id) as Node3D
			LeafFlight.fly(host, player, node.global_position if node != null else player.global_position, item)
	return true


## `mSM_IV_OPEN_NORMAL`: on the field, look for water ahead of the player for a fish.
func _find_release_water() -> void:
	var inv: Inventory = Game.inventory
	var ctx: InteractionContext = _field_context()
	var world: World = ctx.world as World
	var player: Player = ctx.actor as Player
	inv.release_outdoors = world != null and player != null
	inv.release_water = null
	if not inv.release_outdoors:
		return
	var layout: WorldData = world.layout
	var grid: WorldGrid = world.grid
	var found: Variant = CreatureRelease.search_water(func(at: Vector3) -> bool:
		var attr: int = FieldCollision.unit_attr_at(layout, grid, at)
		return attr >= 0 and FieldCatalog.is_water_attr(attr),
		player.global_position, player.facing_yaw())
	if found != null:
		var water: Vector3 = found as Vector3
		water.y = world.fish.surface_at(water)
		inv.release_water = water


func _field_context() -> InteractionContext:
	var ctx := InteractionContext.new()
	ctx.inventory = Game.inventory
	var tree := get_tree()
	if tree != null:
		ctx.actor = Player.find(tree)
		ctx.world = World.find(tree)
	return ctx


func _refresh() -> void:
	var inv: Inventory = Game.inventory
	_refresh_mobile_layout()
	## GC `mIV_SetLineStrings` draws land/player names in lowercase on the sen bars.
	if _player_name != null:
		_player_name.text = Game.resident.player_name.to_lower()
	if _town_name != null:
		_town_name.text = Game.town.town_name.to_lower()
	_wallet.text = _format_bells(inv.wallet)
	var eq: ItemData = ItemCatalog.get_item(inv.equipment_id)
	_equip.text = "Held: %s" % (eq.display_name if eq != null else "—")
	if _portrait_frame != null:
		## Selection cue for the player doll, same idea as the item-slot selected style.
		_portrait_frame.modulate = Color(1.35, 1.3, 1.0) if _focus_player else Color.WHITE
	_sync_portrait_equipment()
	_refresh_items(inv)
	_refresh_mail(inv)
	_refresh_gyroid()
	if _side_tab != SideTab.POCKETS and not _page_moving:
		_collect_page(_side_tab).populate(Game.species_log)
	if _tag_mode and _side_tab == SideTab.POCKETS and not _tag_choices.is_empty():
		_show_tag_popup()
	else:
		_hide_tag_popup()
	_refresh_name_tag(inv)
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
		var selected: bool = (not _focus_mail) and (not _focus_gyroid) and i == inv.selected_index
		var in_hand: bool = i == inv.hand_index
		var marked: bool = inv.is_marked(i)
		var style: StyleBox = style_item_selected if selected else (style_item_marked if marked else style_item)
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
		var style: StyleBox = style_mail_selected if selected else style_mail
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
			## Opened mail (`RECV_READ`/`RECV_PRESENT_READ`) shows the slit-open
			## envelope art instead of the sealed one (`m_mail` read flag).
			var read: bool = mail.font in [
				MailData.LetterFont.RECV_READ, MailData.LetterFont.RECV_PRESENT_READ
			]
			var letter_tex: Texture2D
			if read:
				letter_tex = (
					_tex_letter_open_present
					if has_present and _tex_letter_open_present != null
					else _tex_letter_open
				)
			if letter_tex == null:
				letter_tex = (
					_tex_letter_present if has_present and _tex_letter_present != null else _tex_letter
				)
			_set_slot_picture(btn, letter_tex)
			btn.modulate = Color(1, 1, 1, 1)
		btn.disabled = false


## --- house gyroid table (`m_haniwa_ovl`) -------------------------------------------------

const GYROID_COLS := 2
const GYROID_ROWS := 2
const GYROID_INTERRUPT_SEC := 120.0 / DecompTime.TICK_HZ


func _set_gyroid_visible(on: bool) -> void:
	_gyroid_root.visible = on
	for btn: Button in _mail_buttons:
		btn.visible = not on
	if _letters_label != null:
		_letters_label.visible = not on and _side_tab == SideTab.POCKETS


func _on_gyroid_pressed(slot: int) -> void:
	if not _open or _gyroid_house == null:
		return
	_focus_gyroid = true
	_focus_mail = false
	_gyroid_sel = slot
	_activate_gyroid_cursor()


func _gyroid_navigate(event: InputEvent) -> void:
	var col: int = _gyroid_sel % GYROID_COLS
	@warning_ignore("integer_division")
	var row: int = _gyroid_sel / GYROID_COLS
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		if col == 0:
			## Back onto the pockets' right edge, same row.
			_focus_gyroid = false
			Game.inventory.select(row * Inventory.COLUMNS + (Inventory.COLUMNS - 1))
		else:
			_gyroid_sel -= 1
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		if col < GYROID_COLS - 1:
			_gyroid_sel += 1
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		if row > 0:
			_gyroid_sel -= GYROID_COLS
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		if row < GYROID_ROWS - 1:
			_gyroid_sel += GYROID_COLS
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_activate_gyroid_cursor()
		get_viewport().set_input_as_handled()
		return
	else:
		return
	Audio.play_se(&"cursol")
	_refresh()
	_update_hand_cursor(true)
	get_viewport().set_input_as_handled()


## `mTG_select_tag_decide_haniwa` + the hand dropping a pocket item on the table.
func _activate_gyroid_cursor() -> void:
	var house: House = _gyroid_house
	if house == null:
		return
	var inv: Inventory = Game.inventory
	var empty: bool = GyroidStore.is_empty_slot(house, _gyroid_sel)
	_tag_choices = PackedStringArray()
	_gyroid_put_pocket = -1
	if _gyroid_owner:
		if inv.hand_index >= 0:
			if not empty:
				Audio.play_se(&"3")
				return
			## `mTG_haniwa_put_item`.
			_gyroid_put_pocket = inv.hand_index
			_tag_choices = PackedStringArray(["Free", "Set price", "Display only"])
		elif not empty:
			## `mTG_haniwa_item`.
			_tag_choices = PackedStringArray(["Grab", "Free", "Set price", "Display only", "Quit"])
	elif not empty and int(GyroidStore.item_at(house, _gyroid_sel)["exchange"]) != GyroidStore.Exchange.DISPLAY:
		## `mTG_haniwa_get_item`.
		_tag_choices = PackedStringArray(["Take it", "Quit"])
	if _tag_choices.is_empty():
		return
	_gyroid_tag_mode = true
	_tag_mode = true
	_tag_index = 0
	Audio.play_se(&"41c")
	_refresh()


func _run_gyroid_tag(tag: String) -> void:
	var house: House = _gyroid_house
	var inv: Inventory = Game.inventory
	_gyroid_tag_mode = false
	_tag_mode = false
	match tag:
		"Free":
			_gyroid_set_terms(GyroidStore.Exchange.FREE, 0)
		"Display only":
			_gyroid_set_terms(GyroidStore.Exchange.DISPLAY, 0)
		"Set price":
			## `mTG_priceset_proc`: starts from the item's current price.
			_price_mode = true
			_price_digit = 4
			_price = int(GyroidStore.item_at(house, _gyroid_sel)["price"]) if _gyroid_put_pocket < 0 else 0
			Audio.play_se(&"33")
		"Grab":
			if GyroidStore.take_back(house, _gyroid_sel, inv):
				Audio.play_se(&"60")
			else:
				_gyroid_say(GyroidStore.MSG_NO_ROOM)
				Audio.play_se(&"3")
		"Take it":
			var paid: bool = int(GyroidStore.item_at(house, _gyroid_sel)["price"]) > 0
			match GyroidStore.buy(house, _gyroid_sel, inv):
				&"ok":
					_gyroid_say(GyroidStore.MSG_THANKS)
					## `NA_SE_5F` for a gift, the till for a sale.
					Audio.play_se(&"register" if paid else &"5f")
				&"no_room":
					_gyroid_say(GyroidStore.MSG_NO_ROOM)
					Audio.play_se(&"3")
				&"no_money":
					_gyroid_say(GyroidStore.MSG_CANT_AFFORD)
					Audio.play_se(&"3")
	_refresh()
	_update_hand_cursor(true)


## `mTG_set_trade_cond`: put the held pocket item in on these terms, or re-term an item.
func _gyroid_set_terms(exchange: GyroidStore.Exchange, price: int) -> void:
	var house: House = _gyroid_house
	var inv: Inventory = Game.inventory
	if _gyroid_put_pocket >= 0:
		if not GyroidStore.entrust(house, _gyroid_sel, inv, _gyroid_put_pocket, exchange, price):
			return
		_play_hand_clip("hnd_sasu", true)
	else:
		GyroidStore.set_terms(house, _gyroid_sel, exchange, price)
	_gyroid_put_pocket = -1
	Audio.play_se(&"33")
	_gyroid_say(GyroidStore.MSG_GOT_IT)


## `mTG_mv_priceSet`: left/right pick a digit, up/down step it, A sets (0 = free), B backs out.
func _handle_price_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		_price_mode = false
		_gyroid_put_pocket = -1
		Audio.play_se(&"3")
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_price_mode = false
		if _price == 0:
			_gyroid_set_terms(GyroidStore.Exchange.FREE, 0)
		else:
			_gyroid_set_terms(GyroidStore.Exchange.SALE, _price)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		var up: int = GyroidStore.step_price(_price, _price_digit, 1)
		if up != _price:
			Audio.play_se(&"426")
		_price = up
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		var down: int = GyroidStore.step_price(_price, _price_digit, -1)
		if down != _price:
			Audio.play_se(&"426")
		_price = down
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		if _price_digit > 0:
			_price_digit -= 1
			Audio.play_se(&"cursol")
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		if _price_digit < GyroidStore.PRICE_STEPS.size() - 1:
			_price_digit += 1
			Audio.play_se(&"cursol")
	else:
		return
	_refresh()


func _gyroid_say(text: String) -> void:
	_gyroid_interrupt = text
	_gyroid_interrupt_left = GYROID_INTERRUPT_SEC


func _process(delta: float) -> void:
	_step_tags(delta)
	if _gyroid_interrupt_left > 0.0:
		_gyroid_interrupt_left -= delta
		if _gyroid_interrupt_left <= 0.0:
			_gyroid_interrupt = ""
			_refresh_gyroid()


## Price as five digits with the edited one bracketed, e.g. `0 1 [2] 0 0 Bells`.
func _price_text() -> String:
	var digits: String = "%05d" % _price
	var parts: PackedStringArray = PackedStringArray()
	for i: int in digits.length():
		parts.append("[%s]" % digits[i] if i == _price_digit else digits[i])
	return " ".join(parts) + " Bells"


func _refresh_gyroid() -> void:
	if _gyroid_house == null:
		return
	var house: House = _gyroid_house
	for i: int in _gyroid_buttons.size():
		var btn: Button = _gyroid_buttons[i]
		var selected: bool = _focus_gyroid and i == _gyroid_sel
		var style: StyleBox = style_item_selected if selected else style_item
		for key: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(key, style)
		var rec: Dictionary = GyroidStore.item_at(house, i)
		var id: StringName = StringName(rec.get("item", &""))
		btn.text = ""
		if id == &"":
			_set_slot_picture(btn, null)
			btn.modulate = Color.WHITE
			continue
		var data: ItemData = ItemCatalog.get_item(id)
		var icon: Texture2D = InventoryChrome.icon_for_item(data, int(rec.get("cond", 0)) as InventoryItem.Condition)
		_set_slot_picture(btn, icon)
		if icon == null and data != null:
			btn.text = data.display_name.substr(0, mini(5, data.display_name.length()))
		btn.modulate = Color.WHITE
	## `mHW_make_message`: interrupt line, else what the cursor / tag is on.
	var line: String = _gyroid_interrupt
	if line == "":
		if _price_mode:
			line = GyroidStore.MSG_HOW_MUCH + "\n" + _price_text()
		elif _gyroid_tag_mode:
			line = GyroidStore.MSG_CHOOSE_ONE
		else:
			line = GyroidStore.status_line(house, _gyroid_sel if _focus_gyroid else -1, _gyroid_owner)
	_gyroid_status.text = line

extends Control

## The real bottom-right field HUD clock — `banti` in ac-decomp
## (`src/game/m_banti.c` + `src/data/model/clk_win.c`). Not a menu overlay:
## the real game draws this every frame while outdoors, gated by
## `mFI_FIELDTYPE_FG` + not-first-intro + `banti.alpha > 0.01`.
##
## Fade: `banti_calc_disp_alpha_rate` ramps alpha toward 1 only when
## `mPlib_Get_address_able_display() == mPlayer_ADDRESSABLE_TRUE` (player
## idle — not moving, not talking, no menu open) and toward 0 otherwise.
## Reproduced here as: player velocity ~0, not busy, no overlay open.
##
## Every badge (date, weekday, time digit, am/pm, the blinking `:` dot) is a
## single self-contained real ROM texture — circle, hairline, and glyph
## baked together, `clk_win_*` — extracted + HD via ACHD + tinted with the
## real PRIM/ENV pairs by `tools/asset_pipeline/clock_ui.py`. Month and day
## are each ONE badge (`clk_win_suuji1..31`, decomp indexes day-of-month
## 1-31 directly), not split into separate digit circles; hour/minute each
## split into two single-digit badges (`clk_win_jikan0..9` + a blank for the
## hidden leading hour zero), matching `banti_draw_hiduke`/`banti_draw_jikan`.
##
## Not reproduced: `banti_chk_disp_left`, which slides the whole widget to
## the opposite corner when it would overlap the player's on-screen position.

const _TEX_DIR := "res://assets/generated/ui/clock/"

const _DATE_DIAMETER := 46.0
const _AMPM_DIAMETER := 34.0
const _TIME_DIAMETER := 26.0
const _ROW_SPACING := 4.0
const _BADGE_SPACING := 2.0

const _FADE_IN_SPEED := 1.6
const _FADE_OUT_SPEED := 3.2
const _IDLE_VELOCITY_EPS := 0.05

const _MENU_GROUPS := ["dialogue_ui", "shop_ui", "inventory_ui", "map_ui", "debug_console_ui"]

var _month_tex: TextureRect
var _day_tex: TextureRect
var _weekday_tex: TextureRect
var _hour_tens_tex: TextureRect
var _hour_ones_tex: TextureRect
var _minute_tens_tex: TextureRect
var _minute_ones_tex: TextureRect
var _ampm_tex: TextureRect
var _dot_nodes: Array[TextureRect] = []

var _alpha: float = 0.0
var _blink_elapsed: float = 0.0
var _blink_on: bool = true


func _ready() -> void:
	modulate.a = 0.0
	_build()
	Clock.time_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	_update_blink(delta)
	_update_fade(delta)


func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_theme_constant_override("separation", int(_ROW_SPACING))
	add_child(vbox)

	var date_row := HBoxContainer.new()
	date_row.alignment = BoxContainer.ALIGNMENT_END
	date_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	date_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_row.add_theme_constant_override("separation", int(_BADGE_SPACING))
	vbox.add_child(date_row)

	var time_row := HBoxContainer.new()
	time_row.alignment = BoxContainer.ALIGNMENT_END
	time_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_row.add_theme_constant_override("separation", int(_BADGE_SPACING))
	vbox.add_child(time_row)

	_month_tex = _badge(_DATE_DIAMETER)
	date_row.add_child(_month_tex)
	date_row.add_child(_dot(_DATE_DIAMETER * 0.16))
	_day_tex = _badge(_DATE_DIAMETER)
	date_row.add_child(_day_tex)
	date_row.add_child(_gap(6.0))
	_weekday_tex = _badge(_DATE_DIAMETER)
	date_row.add_child(_weekday_tex)

	_hour_tens_tex = _badge(_TIME_DIAMETER)
	time_row.add_child(_hour_tens_tex)
	_hour_ones_tex = _badge(_TIME_DIAMETER)
	time_row.add_child(_hour_ones_tex)
	time_row.add_child(_dot(_TIME_DIAMETER * 0.3))
	_minute_tens_tex = _badge(_TIME_DIAMETER)
	time_row.add_child(_minute_tens_tex)
	_minute_ones_tex = _badge(_TIME_DIAMETER)
	time_row.add_child(_minute_ones_tex)
	time_row.add_child(_gap(6.0))
	_ampm_tex = _badge(_AMPM_DIAMETER)
	time_row.add_child(_ampm_tex)


func _badge(diameter: float) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(diameter, diameter)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _dot(diameter: float) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(diameter, diameter)
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := TextureRect.new()
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(t)
	t.texture = load(_TEX_DIR + "dot.png")
	_dot_nodes.append(t)
	return wrap


func _gap(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 1.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _refresh() -> void:
	_month_tex.texture = load(_TEX_DIR + "date_%d.png" % Clock.month)
	_day_tex.texture = load(_TEX_DIR + "date_%d.png" % Clock.day)
	_weekday_tex.texture = load(_TEX_DIR + "weekday_%d.png" % Clock.weekday())

	var hour12: int = Clock.hour % 12
	if hour12 == 0:
		hour12 = 12
	var hour_tens: int = hour12 / 10
	var hour_ones: int = hour12 % 10
	var minute_tens: int = Clock.minute / 10
	var minute_ones: int = Clock.minute % 10

	## Only the hour's leading zero is hidden (`banti_draw_jikan_sub`'s
	## `hide_zero` is TRUE only for `hour_upper_anim`).
	_hour_tens_tex.texture = load(_TEX_DIR + "time_blank.png") if hour_tens == 0 else load(_TEX_DIR + "time_%d.png" % hour_tens)
	_hour_ones_tex.texture = load(_TEX_DIR + "time_%d.png" % hour_ones)
	_minute_tens_tex.texture = load(_TEX_DIR + "time_%d.png" % minute_tens)
	_minute_ones_tex.texture = load(_TEX_DIR + "time_%d.png" % minute_ones)
	_ampm_tex.texture = load(_TEX_DIR + ("am.png" if Clock.hour < 12 else "pm.png"))


func _update_blink(delta: float) -> void:
	_blink_elapsed += delta
	if _blink_elapsed >= 1.0:
		_blink_elapsed = 0.0
		_blink_on = not _blink_on
	for dot: TextureRect in _dot_nodes:
		dot.visible = _blink_on


func _update_fade(delta: float) -> void:
	var idle: bool = _player_is_idle() and not _any_menu_open()
	var target: float = 1.0 if idle else 0.0
	var speed: float = _FADE_IN_SPEED if idle else _FADE_OUT_SPEED
	_alpha = move_toward(_alpha, target, speed * delta)
	modulate.a = _alpha


func _player_is_idle() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	var player: Node = tree.get_first_node_in_group("player")
	if player == null:
		return false
	if player.has_method("is_busy") and bool(player.call("is_busy")):
		return false
	if player is CharacterBody3D:
		return (player as CharacterBody3D).velocity.length() < _IDLE_VELOCITY_EPS
	return true


func _any_menu_open() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	for group: String in _MENU_GROUPS:
		var ui: Node = tree.get_first_node_in_group(group)
		if ui != null and ui.has_method("is_open") and bool(ui.call("is_open")):
			return true
	return false

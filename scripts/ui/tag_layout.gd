class_name TagLayout
extends RefCounted

## Where the pockets' name plate and verb window sit and how big they are
## (`m_tag_ovl.c` `mTG_set_tag_win_scale_p`, `mTG_init_tag_data_item_win_sub_mail_item`,
## `mTG_init_tag_data_select_win_after_item` / `_only`). Everything is in screen units about the
## screen centre with y up, the way the ROM works them out; the overlay turns that into pixels.
##
## One `Tag` is a window: `base` is where it hangs from (the slot centre for the name plate),
## `body_ofs` / `body_scale` place and stretch the window model from there, `text_ofs` is where
## its text starts, and `arrow_dir` is 0 (none), 1 (arrow on the left edge, body to the right)
## or 2 (the other way round).

const WIN_ITEM := 0
const WIN_SELECT2 := 2

const ITEM_WINDOW_WIDTH := 122.5
const SELECT_WINDOW_WIDTH := 122.5
const SELECT_WINDOW_HEIGHT := 129.5
## Names appear this many game frames after the cursor settles (`mTG_get_item_name_wait_time`).
const NAME_WAIT_FRAMES := 20
const TEXT_LINE_HEIGHT := 16.0
const TEXT_SCALE := 0.875
## Fixed screen edges (`mTG_check_edge_*`).
const RIGHT_EDGE := 146.0
const SELECT_RIGHT_LIMIT := 134.0
const SELECT_FOOT_LIMIT := -120.0
const SELECT_TOP_LIMIT := 120.0


class Tag:
	extends RefCounted
	var base := Vector2.ZERO
	var body_ofs := Vector2.ZERO
	var body_scale := Vector2.ONE
	var text_ofs := Vector2.ZERO
	var share := Vector2.ZERO  ## `_04`: how far into the window's size range the text reaches.
	var model_scale: float = 1.0  ## `_34`
	var arrow_dir: int = 0
	var row: int = 0  ## The pockets row the tag hangs from (`tag_row`).


## `tag_win_data_pix[]`: [min scale, anchor, `_34`, `_14`, `_18`, text start, text growth].
static func _win_data(win_type: int) -> Dictionary:
	if win_type == WIN_ITEM:
		return {
			"min": Vector2(0.2972973, 0.8125),
			"anchor": Vector2(-64.75, 14.0),
			"scale": 0.875,
			"from": 21.0,
			"span": 84.0,
			"text": Vector2(8.75, -4.375),
			"text_grow": Vector2(4.375, -2.625),
			"arrow_ofs": Vector2(-3.5, -3.5),
			"arrow_grow": Vector2(-7.0, 3.5),
		}
	return {
		"min": Vector2(0.5714286, 0.43243244),
		"anchor": Vector2(-61.25, 64.75),
		"scale": 0.875,
		"from": 31.5,
		"span": 42.0,
		"text": Vector2(22.75, -14.875),
		"text_grow": Vector2(5.25, -15.75),
		"arrow_ofs": Vector2(6.125, 15.75),
		"arrow_grow": Vector2(0.875, 26.25),
	}


## `mTG_set_tag_win_scale_p`: size and text/body offsets for text `x` wide and `y` tall
## (`y == 0`: a single line, the height follows the width).
static func set_win_scale(tag: Tag, win_type: int, x: float, y: float) -> void:
	var d: Dictionary = _win_data(win_type)
	tag.share.x = (x - float(d["from"])) / float(d["span"])
	if y != 0.0:
		tag.share.y = (y - 28.0) / 42.0
	else:
		tag.share.y = tag.share.x
	tag.model_scale = float(d["scale"])
	var minimum: Vector2 = d["min"]
	var anchor: Vector2 = d["anchor"]
	var text: Vector2 = d["text"]
	var text_grow: Vector2 = d["text_grow"]
	var arrow_ofs: Vector2 = d["arrow_ofs"]
	var arrow_grow: Vector2 = d["arrow_grow"]
	tag.body_scale = Vector2(
		minimum.x + tag.share.x * (1.0 - minimum.x), minimum.y + tag.share.y * (1.0 - minimum.y)
	)
	tag.text_ofs = Vector2(
		text.x + text_grow.x * tag.share.x + anchor.x * tag.body_scale.x,
		text.y + text_grow.y * tag.share.y + anchor.y * tag.body_scale.y,
	)
	tag.body_ofs = Vector2(
		(arrow_ofs.x + arrow_grow.x * tag.share.x) - anchor.x * tag.body_scale.x,
		(arrow_ofs.y + arrow_grow.y * tag.share.y) - anchor.y * tag.body_scale.y,
	)


## The name plate for the pockets slot centred at `slot` on `row` (`win_sub_mail_item` for an
## ordinary item: win type ITEM, text scaled 0.875). `name_width` is the ROM font's width of
## the name at its native size.
static func item_tag(slot: Vector2, row: int, name_width: float) -> Tag:
	var tag := Tag.new()
	tag.base = slot
	tag.row = row
	set_win_scale(tag, WIN_ITEM, name_width * TEXT_SCALE, 0.0)
	if _fits_right_item(tag):
		tag.arrow_dir = 1
	else:
		tag.body_ofs.x *= -1.0
		tag.arrow_dir = 2
	return tag


static func _fits_right_item(tag: Tag) -> bool:
	return tag.base.x + tag.body_ofs.x + tag.body_scale.x * 64.75 <= RIGHT_EDGE


## `mTG_check_edge_right_select`: how far the window's right edge is inside the screen
## (`<= 0` means it fits).
static func right_overhang(tag: Tag) -> float:
	var margin: float = tag.body_scale.x * SELECT_WINDOW_WIDTH * 0.5
	return (tag.base.x + tag.body_ofs.x + margin) - SELECT_RIGHT_LIMIT


## `mTG_calc_right_edge_select`.
static func right_edge(tag: Tag) -> float:
	return tag.base.x + tag.body_ofs.x + tag.body_scale.x * SELECT_WINDOW_WIDTH * 0.5


## `mTG_check_edge_foot_select`: true while the window still clears the bottom of the screen.
static func clears_foot(tag: Tag) -> bool:
	var margin: float = (tag.body_scale.y * SELECT_WINDOW_HEIGHT) * 0.5
	return ((tag.base.y + tag.body_ofs.y) - margin) - 3.0 >= SELECT_FOOT_LIMIT


## The verb window that opens off the name plate (`select_win_after_item`). `words` is the
## number of verbs, `widest` the widest verb at the ROM font's native size.
static func verb_tag(item: Tag, words: int, widest: float) -> Tag:
	var tag := Tag.new()
	## `mTG_chg_tag_func2`: the window starts where the name plate's text starts. The plate's own
	## y offset is left out of the y term: reference frames of the original (slots in rows 0
	## and 1, left and right columns) only agree with the ROM's placement that way.
	tag.base = Vector2(
		item.base.x + (item.body_ofs.x + item.text_ofs.x - 3.5),
		item.base.y + ((item.text_ofs.y - float(item.row) * TEXT_LINE_HEIGHT) - 8.0) * TEXT_SCALE,
	)
	tag.row = 0
	if item.arrow_dir == 0:
		return _verb_tag_only(tag, words, widest)
	set_win_scale(tag, WIN_SELECT2, widest * TEXT_SCALE, float(words) * TEXT_LINE_HEIGHT * TEXT_SCALE)

	var left_flag: bool = item.body_ofs.x < 0.0
	## [down_min[0], down_min[1], down_ofs[0], down_ofs[1], up_min[0], up_min[1], up_ofs[0], up_ofs[1]]
	var down_min0 := Vector2(27.125, 1.750)
	var down_min1 := Vector2(54.250, 1.750)
	var down_ofs0 := Vector2(27.125, -1.750)
	var down_ofs1 := Vector2(54.250, -1.750)
	var up_min0 := Vector2(-29.750, 6.125)
	var up_min1 := Vector2(-28.875, 8.750)
	var up_ofs0 := Vector2(-29.750, -6.125)
	var up_ofs1 := Vector2(-28.875, -8.750)
	var scale_x := 129.5
	var scale_y := 28.0

	tag.base.y += down_min0.y + (item.body_ofs.y - item.body_scale.y * scale_y * 0.5) + item.share.y * down_min1.y
	tag.body_ofs.y = (up_min0.y + tag.share.y * up_min1.y) - tag.body_scale.y * SELECT_WINDOW_HEIGHT * 0.5
	tag.base.x += item.body_ofs.x - item.body_scale.x * scale_x * 0.5
	tag.body_ofs.x = tag.body_scale.x * SELECT_WINDOW_WIDTH * 0.5

	var below: bool = clears_foot(tag)
	if below and words == 2 and item.row == 1:
		below = false

	var down0: Vector2 = down_min0 if below else down_ofs0
	var down1: Vector2 = down_min1 if below else down_ofs1
	var up0: Vector2 = up_min0 if below else up_ofs0
	var up1: Vector2 = up_min1 if below else up_ofs1
	if below:
		tag.base.x += down0.x + item.share.x * down1.x
		tag.body_ofs.x += up0.x + tag.share.x * up1.x
	else:
		tag.base.y = (
			item.base.y + item.body_ofs.y + item.body_scale.y * scale_y * 0.5
			+ down_ofs0.y + item.share.y * down_ofs1.y
		)
		tag.body_ofs.y = (tag.body_scale.y * SELECT_WINDOW_HEIGHT * 0.5) + (up_ofs0.y + tag.share.y * up_ofs1.y)
		var top: float = tag.base.y + tag.body_ofs.y + tag.body_scale.y * SELECT_WINDOW_HEIGHT * 0.5
		if top > SELECT_TOP_LIMIT:
			tag.base.y -= top - SELECT_TOP_LIMIT
		tag.base.x += down_ofs0.x + item.share.x * down_ofs1.x
		tag.body_ofs.x += up_ofs0.x + tag.share.x * up_ofs1.x

	var dist_right: float = right_edge(tag)
	var step := 0
	if dist_right >= 131.0:
		step = 2 if dist_right >= 167.0 else 1
	if step == 2 or left_flag:
		tag.base.x = (
			(item.base.x + item.body_ofs.x + item.body_scale.x * scale_x * 0.5)
			- (down0.x + item.share.x * down1.x)
		)
		tag.body_ofs.x = -(tag.body_scale.x * SELECT_WINDOW_WIDTH * 0.5) - (up0.x + tag.share.x * up1.x)
		var xofs: float = (tag.base.x + tag.body_ofs.x - tag.body_scale.x * SELECT_WINDOW_WIDTH * 0.5) - -134.0
		if xofs < 0.0:
			tag.body_ofs.x -= xofs
	elif step == 1:
		tag.base.x -= dist_right - 131.0
	tag.arrow_dir = 0
	return tag


## `select_win_only`: the verb window alone (no name plate to hang from).
static func _verb_tag_only(tag: Tag, words: int, widest: float) -> Tag:
	var arrow_min: Array[Vector2] = [
		Vector2(6.125, 15.75), Vector2(-4.375, 15.75), Vector2(4.375, -15.75), Vector2(-6.125, -15.75)
	]
	var arrow_dis: Array[Vector2] = [
		Vector2(0.875, 26.25), Vector2(0.875, 26.25), Vector2(-0.875, -26.25), Vector2(-0.875, -26.25)
	]
	set_win_scale(tag, WIN_SELECT2, widest * TEXT_SCALE, float(words) * TEXT_LINE_HEIGHT * TEXT_SCALE)
	var edge_right: bool = right_overhang(tag) <= 0.0
	var edge_foot: bool = clears_foot(tag)
	var idx: int
	var dir := Vector2.ONE
	if edge_right:
		tag.arrow_dir = 1
		dir.x = 1.0
		if edge_foot:
			idx = 0
			dir.y = -1.0
		else:
			idx = 2
			dir.y = 1.0
	else:
		tag.arrow_dir = 2
		dir.x = -1.0
		if edge_foot:
			idx = 1
			dir.y = -1.0
		else:
			idx = 3
			dir.y = 1.0
	tag.body_ofs.x = arrow_min[idx].x + arrow_dis[idx].x * tag.share.x + tag.body_scale.x * 61.25 * dir.x
	tag.body_ofs.y = arrow_min[idx].y + arrow_dis[idx].y * tag.share.y + (tag.body_scale.y * 64.75 - 6.0) * dir.y
	return tag

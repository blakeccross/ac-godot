class_name GroundItemLabel
extends RefCounted

## The name that pops up when you stop on something lying on the ground
## (`m_watch_my_step` / `Player_actor_Get_itemNo_forWindow`).
##
## The search is the pickup one (`Player_actor_Search_putin_item`): a signboard 35 GX
## ahead, otherwise whatever item is within 15 GX of a point 20 GX ahead, otherwise 10.
## Weeds are found and then dropped, so standing on one names nothing. Furniture counts
## only outdoors (`NAME_TYPE_FTR` is refused off the field). The first intro is already
## clear once play reaches the field (`mEv_UnSetFirstIntro` as the first job starts).

const GX := FieldCatalog.GX_TO_METERS
## `Player_actor_Get_PickupHandPosition` distances, and the 15 GX reach / height.
const SIGN_AHEAD := 35.0 * GX
const ITEM_AHEAD := 20.0 * GX
const NEAR_AHEAD := 10.0 * GX
const REACH := 15.0 * GX
## The window sits on a point 30 GX over the player's feet (three quarters of a unit).
const HEAD := 30.0 * GX
## `add_calc` fraction `1 - sqrt(0.5)`: half the gap every two ticks.
const FADE_HALF_LIFE := 2.0 * DecompTime.TICK_SEC
const OPEN_MAX := 0.25 * DecompTime.TICK_HZ
const OPEN_MIN := 0.15 * DecompTime.TICK_HZ
const CLOSE_MAX := 0.1 * DecompTime.TICK_HZ
const CLOSE_MIN := 0.05 * DecompTime.TICK_HZ
## The second close `add_calc` (max step 0.005).
const CLOSE_CREEP := 0.005 * DecompTime.TICK_HZ
## Modes 1 and 2 hold two frames each before the body (`watch_my_step_move`).
const LEAD_IN := 4.0 * DecompTime.FRAME_SEC
## Font ortho is 320×240. The window origin is 40 across and 42 up from the head
## (`watch_my_step_move`), flipped by `trans_x` / `trans_y`.
const NUDGE_X := 40.0
const NUDGE_Y := 42.0
## `mFont_SetLineStrings` scale, and the width term `stringWidth * 0.875 - 17.5` over 122.5.
const GLYPH_SCALE := 0.875
const WIDTH_BIAS := 17.5
const SCALE_SPAN := 122.5
const CELL_H := 16.0
## Body quad after the name scale: `160 * (0.25 + 0.75 scale)` by `30 * (0.7666… + 0.2333… scale)`.
const BODY_W0 := 40.0
const BODY_W1 := 120.0
const BODY_H0 := 23.0
const BODY_H1 := 7.0
## Glyph top-left, from the body's top-left: `10 + (1 - scale)` across, `5 + 3 scale` down.
const TEXT_X := 11.0
const TEXT_Y := 5.0
const TEXT_Y_SCALE := 3.0
## Tail pieces in screen pixels (the 16× matrix cancels the font ortho). `w2` then `w1`,
## y down, so a positive `trans_y` hangs the tail toward the player.
const JOINT_OFS := Vector2(-1.0, 20.0)
const JOINT_SIZE := Vector2(24.0, 12.0)
const TIP_OFS := Vector2(-13.0, 30.0)
const TIP_SIZE := Vector2(16.0, 8.0)


class Spot extends RefCounted:
	var id: StringName = &""
	var position: Vector3 = Vector3.ZERO
	var label: String = ""
	var signboard: bool = false
	var weed: bool = false
	var furniture: bool = false


class Reveal extends RefCounted:
	enum Phase { HIDDEN, OPENING, SHOWN, CLOSING }

	var phase: Phase = Phase.HIDDEN
	var label: String = ""
	var opacity: float = 0.0
	var _lead: float = 0.0


	## `next_label` empty, or `held_back` (indoor camera morph still above 20), closes it.
	func advance(delta: float, next_label: String, held_back: bool) -> void:
		var want := next_label != "" and not held_back
		var just_opened := false
		if phase == Phase.HIDDEN:
			if not want:
				return
			label = next_label
			opacity = 0.0
			_lead = LEAD_IN
			phase = Phase.OPENING
		if phase == Phase.OPENING:
			## Modes 1–2 run out even if you step off during them.
			_lead -= delta
			if _lead <= 0.0:
				just_opened = true
				phase = Phase.SHOWN if want else Phase.CLOSING
				if want:
					label = next_label
		if phase == Phase.SHOWN and not just_opened:
			if want:
				label = next_label
				opacity = Motion.approach(opacity, 1.0, FADE_HALF_LIFE, OPEN_MAX, OPEN_MIN, delta)
			else:
				phase = Phase.CLOSING
		if phase == Phase.CLOSING:
			opacity = Motion.approach(opacity, 0.0, FADE_HALF_LIFE, CLOSE_MAX, CLOSE_MIN, delta)
			opacity = Motion.approach(opacity, 0.0, FADE_HALF_LIFE, CLOSE_CREEP, CLOSE_CREEP, delta)
			if opacity < 0.01:
				opacity = 0.0
				label = ""
				phase = Phase.HIDDEN


	## Glyphs fade in once the body is past half open (`opacity - 0.5`, doubled).
	func text_alpha() -> float:
		if phase == Phase.OPENING:
			return 0.0
		return clampf((opacity - 0.5) * 2.0, 0.0, 1.0)


static func make(
	id: StringName,
	position: Vector3,
	label: String,
	signboard: bool = false,
	weed: bool = false,
	furniture: bool = false,
) -> Spot:
	var spot := Spot.new()
	spot.id = id
	spot.position = position
	spot.label = label
	spot.signboard = signboard
	spot.weed = weed
	spot.furniture = furniture
	return spot


## The name to show, or "" when the pickup search misses, hits a weed, or hits furniture
## somewhere it isn't named (`allow_furniture` is the outdoor field).
static func label_for(
	origin: Vector3, yaw: float, grid: WorldGrid, spots: Array, allow_furniture: bool
) -> String:
	if grid == null:
		return ""
	var by_id: Dictionary = {}
	for entry: Variant in spots:
		var spot := entry as Spot
		if spot == null or spot.id == &"":
			continue
		by_id[spot.id] = spot
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var probes: Array[Dictionary] = [
		{"ahead": SIGN_AHEAD, "signs": true},
		{"ahead": ITEM_AHEAD, "signs": false},
		{"ahead": NEAR_AHEAD, "signs": false},
	]
	for probe: Dictionary in probes:
		var at := origin + forward * float(probe["ahead"])
		var hit := _probe_hit(at, origin.y, grid, by_id, bool(probe["signs"]))
		if hit == null:
			continue
		## A weed ends the search (`Get_itemNo_forWindow` drops grass). Furniture off the
		## field is not a hit at all (`CheckItem` breaks out of `NAME_TYPE_FTR`).
		if hit.weed:
			return ""
		if hit.furniture and not allow_furniture:
			continue
		if hit.label.is_empty():
			continue
		return hit.label
	return ""


## `trans_x` / `trans_y` from a 320×240 screen point (origin top-left) and the facing yaw.
static func flip(screen_x: float, screen_y: float, yaw: float) -> Vector2:
	var trans_x := 1.0
	if screen_x > 200.0 or (screen_x > 120.0 and yaw >= 0.0):
		trans_x = -1.0
	var trans_y := -1.0 if screen_y < 68.0 else 1.0
	return Vector2(trans_x, trans_y)


## Same flip, from a viewport pixel and the viewport size.
static func flip_for(screen: Vector2, viewport: Vector2, yaw: float) -> Vector2:
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return Vector2.ONE
	return flip(screen.x / viewport.x * 320.0, screen.y / viewport.y * 240.0, yaw)


## Pixels per 320×240 unit. The font ortho is square (`mFont_CulcOrthoMatrix`, ±160×120),
## so 40 across and 42 up stay in that proportion on a widescreen viewport.
static func units(viewport: Vector2) -> float:
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return 1.0
	return minf(viewport.x / 320.0, viewport.y / 240.0)


## `mFont_GetStringWidth` (cut advances, 16px cell) → `scale = (width * 0.875 - 17.5) / 122.5`.
static func name_scale(cell_width: float) -> float:
	return maxf(cell_width * GLYPH_SCALE - WIDTH_BIAS, 0.0) / SCALE_SPAN


## Body size in 320×240 pixels: `(40 + scale * 120)` by `(23 + scale * 7)`.
static func body_size(scale: float) -> Vector2:
	return Vector2(BODY_W0 + scale * BODY_W1, BODY_H0 + scale * BODY_H1)


## The drawn window (`watch_my_step_draw`): origin, body, glyph top-left, and the two tail pieces.
class Frame extends RefCounted:
	var origin: Vector2 = Vector2.ZERO
	var body_position: Vector2 = Vector2.ZERO
	var body_size: Vector2 = Vector2.ZERO
	var text_position: Vector2 = Vector2.ZERO
	var font_px: int = 14
	var joint_position: Vector2 = Vector2.ZERO
	var joint_size: Vector2 = Vector2.ZERO
	var tip_position: Vector2 = Vector2.ZERO
	var tip_size: Vector2 = Vector2.ZERO
	var scale: float = 0.0


## `player_px` is the unprojected head. `side` is `flip`. `cell_width` is the cut
## string width at the 16px cell. Positions are viewport pixels, top-left, y down.
static func frame_at(player_px: Vector2, side: Vector2, viewport: Vector2, cell_width: float) -> Frame:
	var k := units(viewport)
	var scale := name_scale(cell_width)
	var body := body_size(scale) * k
	## `pos = screen - (nudge + half screen)`; the model origin lands back at screen + nudge.
	var origin := player_px + Vector2(side.x * NUDGE_X, -side.y * NUDGE_Y) * k
	var frame := Frame.new()
	frame.scale = scale
	frame.origin = origin
	frame.body_size = body
	frame.body_position = origin - body * 0.5
	## Glyphs: `10 + origin.x - half width + (1 - scale)`, and the matching top inset.
	frame.text_position = frame.body_position + Vector2(TEXT_X - scale, TEXT_Y + TEXT_Y_SCALE * scale) * k
	frame.font_px = maxi(1, int(round(CELL_H * GLYPH_SCALE * k)))
	frame.joint_size = JOINT_SIZE * k
	frame.joint_position = origin + Vector2(side.x * JOINT_OFS.x, side.y * JOINT_OFS.y) * k - frame.joint_size * 0.5
	frame.tip_size = TIP_SIZE * k
	frame.tip_position = origin + Vector2(side.x * TIP_OFS.x, side.y * TIP_OFS.y) * k - frame.tip_size * 0.5
	return frame


static func _probe_hit(
	probe: Vector3, player_y: float, grid: WorldGrid, by_id: Dictionary, signboard_only: bool
) -> Spot:
	var id: StringName = grid.occupant_at(grid.world_to_cell(probe))
	if id == &"" or not by_id.has(id):
		return null
	var spot: Spot = by_id[id]
	if signboard_only and not spot.signboard:
		return null
	var flat := Vector2(spot.position.x - probe.x, spot.position.z - probe.z)
	if flat.length() > REACH or absf(spot.position.y - player_y) > REACH:
		return null
	return spot

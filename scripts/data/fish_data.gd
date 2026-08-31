class_name FishData
extends ItemData

## Catchable fish. Months are 1–12. Hours are the original's four time-of-day slots
## rather than a free window, because that is the only resolution the spawn tables have.

## `aGYO_SIZE_*`. Drives the shadow's scale and every per-size table in `FishSize`.
enum SizeClass { XXS, XS, S, M, L, XL, XXL, WHALE }

## `aSOG_TIME_*`. `aSOG_gyoei_time_no` buckets the clock into these four and indexes the
## month's spawn table with it, so a fish is in or out of a whole slot at a time.
enum TimeSlot { NIGHT, MORNING, DAY, EVENING }

const SLOT_HOURS := {
	TimeSlot.NIGHT: Vector2i(21, 4),
	TimeSlot.MORNING: Vector2i(4, 9),
	TimeSlot.DAY: Vector2i(9, 16),
	TimeSlot.EVENING: Vector2i(16, 21),
}

## Empty means every month. Otherwise the 1–12 months this fish appears in.
@export var months: PackedInt32Array = PackedInt32Array()
## `TimeSlot` values. Empty means all four. Piranha and the dawn/dusk trout hold
## non-adjacent slots, which is why this is a set and not a start/end pair.
@export var time_slots: PackedInt32Array = PackedInt32Array()
## `WaterBodies.Kind` values, from the `r_month` / `s_month` / `p_month` split. Empty
## means any water. The finer `aSOG_SPAWN_AREA_*` sub-areas (pool, waterfall, river
## mouth, offing) are not modelled, so a river fish can bite anywhere in a river.
@export var waters: PackedInt32Array = PackedInt32Array()
## The coelacanth is spliced into the sea table only while it rains
## (`aSOG_add_kaseki_range_data`). There is no weather system yet, so this shuts it out.
@export var needs_rain: bool = false
@export var size_class: SizeClass = SizeClass.S
## Relative pick weight among the fish available at this month and slot. The original
## carries a separate weight per month, half-month and slot; this is the highest of them.
@export var rarity_weight: int = 10
## `gyoei_type[].search_area`, 0–4: how far and how wide a cone this fish notices a bobber
## in. Low is fussy (a large char only looks 3° off its nose), high is eager.
@export_range(0, 4) var search_area: int = 2
## `gyoei_type[].bite_time`, 0–4: how long it holds the hook once it commits, which is the
## window you get to reel. Low is a snatch, 4 is a lazy 1.5s.
@export_range(0, 4) var bite_time: int = 3
## `Player_actor_Get_sakana_msg_num`: the catch report, `0x1327 + type` up to type 0x20 and
## `0x2FA9 + type` past it. One per species, pun included; the rare three run to two pages.
@export var catch_msg: int = 0
## The `act_f*` display lists, minus the `_a` / `_b` pose suffix. `aGYO_actor_draw_fish`
## only ever reaches those two, so `_c` is not converted.
@export var model_base: String = ""
## `aGYO_anime_ptn`: 1 fast (8-frame cadence), 2 slow (16-frame), 0 never flaps.
@export var model_flap: int = 0
## `aGYO_hosei_y`: per-species Y nudge the draw applies before the model, in GX.
@export var model_lift: float = 0.0


func model_pose(pose: StringName) -> String:
	if model_base.is_empty():
		return ""
	return "%s_%s.glb" % [model_base, pose]


func _init() -> void:
	category = Category.FISH


## `aSOG_gyoei_time_no`: hour thresholds 3 / 8 / 15 / 20, with the tail wrapping to night.
static func slot_for_hour(p_hour: int) -> TimeSlot:
	var h: int = posmod(p_hour, 24)
	if h <= 3:
		return TimeSlot.NIGHT
	if h <= 8:
		return TimeSlot.MORNING
	if h <= 15:
		return TimeSlot.DAY
	if h <= 20:
		return TimeSlot.EVENING
	return TimeSlot.NIGHT


func in_water(kind: int) -> bool:
	return waters.is_empty() or kind in waters


func is_available(p_month: int, p_hour: int) -> bool:
	if needs_rain:
		return false
	if not months.is_empty() and not (p_month in months):
		return false
	return time_slots.is_empty() or int(slot_for_hour(p_hour)) in time_slots


func is_available_now() -> bool:
	return is_available(Clock.month, Clock.hour)

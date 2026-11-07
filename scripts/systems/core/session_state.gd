class_name SessionState
extends RefCounted

## Small flags that last one play session and are never saved, each read by the one feature
## named in its comment. `Game` makes a new one for a new town; `reset_load` runs on every load.

## A paid-off loan or the end of Nook's chores, waiting for the next door (`Game.PAYMENT_*`).
var complete_payment: StringName = &""
## The last board check wrote no seasonal notice, so a villager may bury treasure.
var treasure_due: bool = false
## `Save_Get(insect_term)` / `insect_term_transition_offset`: the 0-based month the insect
## spawn table is heading into and how many days (0-5) before its 1st the cross-month blend
## starts (`aSOI_ins_chk_term_info`).
var insect_term_month: int = 0
var insect_term_offset: int = 0
## `mFI_GetDigStatus`'s `old_pos`: where the golden shovel last dug.
var golden_last_dig: Vector2i = Vector2i(-1, -1)
## `unk_nook_present_count`: presents Nook has handed over for codes this session.
var nook_code_gifts: int = 0
## `Common.money_power` / `goods_power`: the house's feng shui (`FengShui`), recomputed on
## the way out to the field.
var money_power: int = 0
var goods_power: int = 0

## A show owns the music (`mBGMPsComp_make_ps_demo`): the field keeps its hands off.
var show_bgm: StringName = &""
## Where each event's actors stand today (`mEv_reserve_common_place`), `"id:index" → {…}`, so
## leaving a building finds a visitor where it was. Forgotten when the day changes.
var event_places: Dictionary = {}
var event_places_day: String = ""
## Tortimer by the river has had his first word with the player (`aESC`).
var bridge_tortimer_talked: bool = false
## `Common_Get(axe_damage)`: wear on the held axe (`AxeWear`).
var axe_damage: int = 0
## The money rock being hit (`MoneyRock`): its id, the hits so far and when the run ends.
var money_rock_id: StringName = &""
var money_rock_hits: int = 0
var money_rock_ends_msec: int = 0
## The quest manager's memory (`VillagerTalkManager`): `last_strings` (last word picked per
## topic, 255 = none), the last island chat line, and per errand whether the next villager
## hands the item back (1) or passes it on (2), 0 = not decided (`errand_next`).
var talk_last_strings := PackedInt32Array([255, 255, 255, 255, 255, 255, 255])
var talk_last_island_chat: int = 0
var errand_next := PackedByteArray([0, 0, 0, 0, 0])
## Villagers out walking, `id → true`, held to `VillagerWalk.walker_cap`.
var walkers: Dictionary = {}
## The villager allowed to open an umbrella next, and when the window opens (`VillagerOutdoor`).
var umbrella_holder: Object = null
var umbrella_ready_at: float = 0.0

# Started afresh on every load (`reset_load`).

## `mMsr_FirstClearMushroom` has run for this play session.
var mushrooms_session_cleared: bool = false
## Shells still to wash up: twenty when a session starts (`mFI_SetFirstSetShell`).
var shells_owed: int = ShellUse.FIRST_NUM
var shell_minute_counted: bool = false
## `Common.snowman_msg_id` (`mSN_decide_msg`): rolled each play session.
var snowman_msg_id: int = 0
## `goki_shocked_flag`: the first roach of a session startles the player, once.
var roach_shocked: bool = false
## `Sunburn`: seconds in the sun towards the next rank, and a rank change waiting for the
## player to go indoors.
var sun_time: float = 0.0
var sunburn_rankup_pending: bool = false
var sunburn_rankdown_pending: bool = false


func _init() -> void:
	reset_load()


func reset_load() -> void:
	mushrooms_session_cleared = false
	shells_owed = ShellUse.FIRST_NUM
	shell_minute_counted = false
	snowman_msg_id = randi_range(0, 2)
	roach_shocked = false
	sun_time = 0.0
	sunburn_rankup_pending = false
	sunburn_rankdown_pending = false

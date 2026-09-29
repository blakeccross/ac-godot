class_name GulliverTalk
extends BankTalk

## Gulliver washed up on the beach (`ac_ev_dozaemon_move.c_inc`).
##
## - Asleep: 35% he stirs (0x23F8) and gets up once the window closes; otherwise he mumbles
##   (0x23F9–0x23FD) and sleeps on.
## - Up: he speaks first (0x23FE–0x2403, sets `WAKEUP`), then his gift: pockets full →
##   0x2408; else 0x2404 and one of his far-off keepsakes (`mSP_LISTTYPE_JONASON`) → 0x2406.
## - Wandering: gift still owed → 0x2409 (still full) or 0x2405 + gift → 0x2407; after the
##   gift 0x240A–0x240F.

enum Mode { ASLEEP, WOKEN, WANDER }

const MSG_STIR := 0x23F8
const MSG_MUMBLE := 0x23F9
const MSG_WAKE := 0x23FE
const MSG_GIFT := 0x2404
const MSG_GIFT_LATE := 0x2405
const MSG_BYE_FIRST := 0x2406
const MSG_BYE_LATE := 0x2407
const MSG_FULL := 0x2408
const MSG_FULL_LATE := 0x2409
const MSG_CHAT := 0x240A
## `aEDZ_set_norm_talk_info`: 35% to wake him.
const WAKE_CHANCE := 0.35

var mode: Mode = Mode.ASLEEP
## `mEv_dozaemon_c.flags`: `{"wakeup", "gave_first", "give"}`.
var area: Dictionary = {}
var inventory: Inventory
var rng: RandomNumberGenerator
## Set when the talk made him stand up.
var wakes: bool = false
var gift: StringName = &""


func _init(p_mode: Mode, p_area: Dictionary, p_inventory: Inventory, p_rng: RandomNumberGenerator = null) -> void:
	mode = p_mode
	area = p_area
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


func start_msg() -> int:
	match mode:
		Mode.ASLEEP:
			if rng.randf() < WAKE_CHANCE:
				wakes = true
				return MSG_STIR
			return MSG_MUMBLE + rng.randi_range(0, 4)
		Mode.WOKEN:
			area["wakeup"] = true
			return MSG_WAKE + rng.randi_range(0, 5)
	## `aEDZ_set_wander_talk_info`.
	if not bool(area.get("give", false)):
		return _offer(true)
	return MSG_CHAT + rng.randi_range(0, 5)


func next_step() -> Dictionary:
	match current_msg:
		MSG_GIFT, MSG_GIFT_LATE:
			return _hand_over()
	if current_msg >= MSG_WAKE and current_msg < MSG_WAKE + 6:
		return msg(_offer(false))
	return {}


## `aEDZ_to_ageru` / `aEDZ_to_ageru2`.
func _offer(late: bool) -> int:
	if inventory == null or not inventory.has_space(1):
		return MSG_FULL_LATE if late else MSG_FULL
	area["gave_first"] = not late
	return MSG_GIFT_LATE if late else MSG_GIFT


## `aEDZ_ageru`: the keepsake goes straight into the pockets, then changes hands.
func _hand_over() -> Dictionary:
	gift = FtrCatalog.pick("jonason", rng)
	var item: ItemData = ItemCatalog.get_item(gift)
	if item != null and inventory != null:
		inventory.add(item, 1)
	area["give"] = true
	if Game != null and Game.events != null:
		Game.events.dozaemon_completed = true
	var bye: int = MSG_BYE_FIRST if bool(area.get("gave_first", false)) else MSG_BYE_LATE
	if gift == &"":
		return msg(bye)
	return {"anim": {"give": gift}, "msg": bye}

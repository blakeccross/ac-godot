class_name VillagerGreeting
extends RefCounted

## Two villagers meeting outdoors (`aNPC_greeting_area_check`, `ac_npc_act_greeting.c_inc`).
##
## Pairing: every frame the NPC control actor pairs up villagers within 80 GX of each other
## (and 40 GX in height) that are free — no partner, not just after a greeting (10 s), not
## hidden, not angry / sad / sleepy. The first of the pair to start the greeting rolls one
## reaction from `react_rate_table` (A is the one the player is closer to) — moods and
## opinions of each other, catchphrases passed on or reset, shirts and umbrellas (the Able
## Sisters trend lives here) — then both turn, close in, bow by looks and, if their clothes
## changed, change on the spot.

const PAIR_RANGE := 80.0 * FieldCatalog.GX_TO_METERS
const PAIR_HEIGHT := 40.0 * FieldCatalog.GX_TO_METERS
## `aNPC_act_greeting_turn`: stand still when this close.
const APPROACH_NEAR := 50.0 * FieldCatalog.GX_TO_METERS
## `demo_move_timer = 80` frames.
const APPROACH_SECONDS := 80.0 / DecompTime.TICK_HZ
## `palActorIgnoreTimer = 10 * FRAMES_PER_SECOND` after a greeting.
const IGNORE_SECONDS := 10.0
## `aNPC_get_greeting_step` → `aNPC_ACTION_TYPE_GREETING0..3` → `AISATU1..4`, by looks
## (normal, peppy, lazy, jock, cranky, snooty).
const GREETING_CLIPS: Array[String] = [
	"npc_1_aisatu2", "npc_1_aisatu1", "npc_1_aisatu2", "npc_1_aisatu1", "npc_1_aisatu3", "npc_1_aisatu4",
]
const CHANGE_CLIP := "npc_1_get_change1"

## `aNPC_set_feel_sub`: feel, minutes, opinion change.
const FEEL_ROLL: Array = [[2, 1, -8], [3, 1, -4], [0, 0, 0]]
## `mNpc_FEEL_HAPPY` / `SAD` / `ANGRY` as `VillagerState.set_feel` codes.
const FEEL_HAPPY := 1
const FEEL_ANGRY := 2
const FEEL_SAD := 3


## `aNPC_check_cond_to_greeting`.
static func can_greet(state: VillagerState) -> bool:
	if state == null:
		return true
	return state.mood != VillagerState.Mood.ANGRY and state.mood != VillagerState.Mood.SAD \
		and state.mood != VillagerState.Mood.SLEEPY


## `aNPC_greeting_area_check`: `villagers` are the free ones, in actor order; returns pairs.
static func pair_up(villagers: Array) -> Array:
	var pairs: Array = []
	var taken: Dictionary = {}
	for i: int in villagers.size():
		var a: Node3D = villagers[i]
		if taken.has(a):
			continue
		for j: int in range(i + 1, villagers.size()):
			var b: Node3D = villagers[j]
			if taken.has(b):
				continue
			var d: Vector3 = b.global_position - a.global_position
			if absf(d.y) >= PAIR_HEIGHT:
				continue
			if Vector2(d.x, d.z).length() < PAIR_RANGE:
				pairs.append([a, b])
				taken[a] = true
				taken[b] = true
				break
	return pairs


## `aNPC_decide_AB_Actor`: A is the one with more friendship toward the player.
static func order(x: VillagerState, y: VillagerState, rng: RandomNumberGenerator) -> Array:
	var fx: int = x.friendship if x != null else 0
	var fy: int = y.friendship if y != null else 0
	if fx == fy:
		return [x, y] if rng.randf() < 0.5 else [y, x]
	return [x, y] if fx > fy else [y, x]


## `aNPC_chk_same_cloth` as shipped: any two Able designs count as the same (the design index
## check was lost).
static func same_cloth(a: VillagerState, a_data: VillagerData, b: VillagerState, b_data: VillagerData) -> bool:
	if a.cloth_design >= 0 or b.cloth_design >= 0:
		return a.cloth_design >= 0 and b.cloth_design >= 0
	return VillagerTalkManager.worn_cloth(a_data, a) == VillagerTalkManager.worn_cloth(b_data, b)


## `aNPC_act_greeting_reaction`. `x` / `y` are {"state", "data", "slot"}; `around` is the
## `aroundNpcInfoList`: residents one acre away, met, not these two, friendliest first, each
## {"state", "data", "loaded"}. Returns the reaction applied, or -1.
static func react(
	x: Dictionary, y: Dictionary, around: Array, residents: TownResidents, rng: RandomNumberGenerator
) -> int:
	var xs: VillagerState = x["state"]
	var ys: VillagerState = y["state"]
	var count: int = NeedleworkTrend.REACT_RATES.size()
	if (xs != null and xs.wearing_present_cloth) or (ys != null and ys.wearing_present_cloth):
		## Wearing the player's present: no shirt swaps (`react = COPY_CLOTH`).
		count = NeedleworkTrend.React.COPY_CLOTH
	var rnd: float = rng.randf()
	var picked: int = -1
	for i: int in count:
		rnd -= NeedleworkTrend.REACT_RATES[i]
		if rnd < 0.0:
			picked = i
			break
	if picked < 0:
		return -1
	var ab: Array = order(xs, ys, rng)
	var a: Dictionary = x if ab[0] == xs else y
	var b: Dictionary = y if a == x else x
	_apply(picked, a, b, around, residents, rng)
	return picked


static func _apply(
	kind: int, a: Dictionary, b: Dictionary, around: Array, residents: TownResidents, rng: RandomNumberGenerator
) -> void:
	var as_: VillagerState = a["state"]
	var bs: VillagerState = b["state"]
	match kind:
		NeedleworkTrend.React.SET_FEEL:
			for pair: Array in [[a, b], [b, a]]:
				var roll: Array = FEEL_ROLL[rng.randi_range(0, FEEL_ROLL.size() - 1)]
				_relation(residents, pair[0], pair[1], int(roll[2]))
				(pair[0]["state"] as VillagerState).set_feel(int(roll[0]), int(roll[1]))
		NeedleworkTrend.React.COPY_END_WORDS:
			if _sex(a) == _sex(b):
				var words: String = VillagerTalk.catchphrase_of(a["data"], as_)
				if VillagerTalk.catchphrase_of(b["data"], bs) != words:
					bs.catchphrase = words
				else:
					for o: Dictionary in around:
						if VillagerTalk.catchphrase_of(o["data"], o["state"]) != words:
							(o["state"] as VillagerState).catchphrase = words
							break
			_both_happy(a, b, residents)
		NeedleworkTrend.React.RESET_END_WORDS:
			## `mNpc_ResetWordEnding`.
			bs.catchphrase = ""
			_relation(residents, a, b, -8)
			as_.set_feel(FEEL_ANGRY, 1)
		NeedleworkTrend.React.CHG_SP_UMB:
			as_.umbrella_design = NeedleworkTrend._another_design(as_.umbrella_design, rng)
		NeedleworkTrend.React.COPY_CLOTH:
			if not same_cloth(bs, b["data"], as_, a["data"]):
				bs.cloth_design = as_.cloth_design
				bs.cloth_id = as_.cloth_id
			else:
				for o: Dictionary in around:
					var os: VillagerState = o["state"]
					if not same_cloth(os, o["data"], as_, a["data"]) and not bool(o.get("loaded", false)):
						os.cloth_design = as_.cloth_design
						os.cloth_id = as_.cloth_id
						break
			_both_happy(a, b, residents)
		NeedleworkTrend.React.SET_CLOTH:
			## `mSP_SelectRandomItem_New(mSP_KIND_CLOTH)` other than what they had on.
			var have: StringName = VillagerTalkManager.worn_cloth(a["data"], as_)
			var pool: Array[StringName] = []
			for id: StringName in ShopGoods.category_pool(ItemData.Category.CLOTH):
				if id != have:
					pool.append(id)
			if not pool.is_empty():
				as_.cloth_id = pool[rng.randi_range(0, pool.size() - 1)]
			as_.cloth_design = -1
			_relation(residents, a, b, -4)
			as_.set_feel(FEEL_SAD, 1)
		NeedleworkTrend.React.CHG_SP_CLOTH:
			as_.cloth_design = NeedleworkTrend._another_design(as_.cloth_design, rng)
			_relation(residents, a, b, 8)
			as_.set_feel(FEEL_HAPPY, 1)
		NeedleworkTrend.React.RESET_CLOTH_AND_UMB:
			as_.cloth_design = -1
			as_.cloth_id = &""
			as_.umbrella_design = -1
			_relation(residents, a, b, -4)
			as_.set_feel(FEEL_SAD, 1)


static func _both_happy(a: Dictionary, b: Dictionary, residents: TownResidents) -> void:
	_relation(residents, a, b, 8)
	(a["state"] as VillagerState).set_feel(FEEL_HAPPY, 1)
	_relation(residents, b, a, 8)
	(b["state"] as VillagerState).set_feel(FEEL_HAPPY, 1)


## `aNPC_set_relation`: 0–255.
static func _relation(residents: TownResidents, from: Dictionary, to: Dictionary, add: int) -> void:
	if residents == null or add == 0:
		return
	var f: int = int(from.get("slot", -1))
	var t: int = int(to.get("slot", -1))
	if f < 0 or t < 0:
		return
	residents.set_relation(f, t, clampi(residents.relation(f, t) + add, 0, 255))


static func _sex(v: Dictionary) -> int:
	var data: VillagerData = v["data"]
	var looks: int = int(data.personality.looks) if data != null and data.personality != null else 0
	return TownResidents.looks_sex(looks)


## `aNPC_sort_aroundNpcInfoList`: a selection sort that only fills every other slot.
static func sort_around(list: Array) -> void:
	var i: int = 0
	while i < list.size():
		var best: int = i
		for j: int in range(i, list.size()):
			if int(list[j]["friendship"]) > int(list[best]["friendship"]):
				best = j
		var tmp: Variant = list[i]
		list[i] = list[best]
		list[best] = tmp
		i += 2

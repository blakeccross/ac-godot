class_name NeedleworkTrend
extends RefCounted

## Who in town is wearing an Able Sisters design — the data behind Mabel's
## "Any suggestions?" report and what trading a display away undoes.
##
## Decomp: a villager wears a shop shirt when `Animal_c.cloth == RSV_CLOTH`, with
## `cloth_original_id` 0-3 naming the mannequin; a shop umbrella when `umbrella_id` is
## `ITM_MY_ORG_UMBRELLA0..3` (stands 4-7). They pick these up from each other in
## `aNPC_act_greeting_reaction` (`ac_npc_act_greeting.c_inc`): when two villagers greet,
## one reaction is rolled from `react_rate_table`. `aNNW_trend_check_*` counts wearers,
## `aNNW_trend_delete_*` puts wearers back in their default clothes when the design on
## that display is replaced.
##
## Live greetings run in `VillagerGreeting`; `daily_greetings` is the old once-a-day
## stand-in, kept for tests. Wear lives on
## `VillagerState.cloth_design` / `umbrella_design` (-1 = not wearing one, else 0-3).

enum React {
	SET_FEEL, COPY_END_WORDS, RESET_END_WORDS, CHG_SP_UMB,
	COPY_CLOTH, SET_CLOTH, CHG_SP_CLOTH, RESET_CLOTH_AND_UMB,
}

## `react_rate_table`, in `React` order. The rest of the unit (0.2) is "no reaction".
const REACT_RATES: Array[float] = [0.2, 0.1, 0.1, 0.1, 0.1, 0.05, 0.1, 0.05]
const DESIGNS := 4  ## mNW_CLOTH_DESIGN_NUM / mNW_UMBRELLA_DESIGN_NUM
const MAX_CATCHUP_DAYS := 7


## Town residents' states (the `Save_Get(animals)` scan in `aNNW_trend_check_*`).
static func town_states() -> Array[VillagerState]:
	var out: Array[VillagerState] = []
	if Game == null or Game.villagers == null:
		return out
	for id: StringName in FirstJob.resident_ids():
		out.append(Game.villagers.get_or_create(id))
	return out


## `aNNW_trend_check_cloth` (shop 0-3) / `aNNW_trend_check_umbrella` (shop 4-7).
static func count(states: Array, shop_idx: int) -> int:
	var n := 0
	var design: int = shop_idx & 3
	var umbrella: bool = (shop_idx & 7) >= DESIGNS
	for s: VillagerState in states:
		if s == null:
			continue
		if (s.umbrella_design if umbrella else s.cloth_design) == design:
			n += 1
	return n


## `aNNW_set_trend_cloth_message` / `_umbrella_message`: a random slot to start with,
## replaced by any strictly more-worn one. Returns `[shop_idx, count]`.
static func top(states: Array, is_umbrella: bool, rng: RandomNumberGenerator) -> Array:
	var base: int = DESIGNS if is_umbrella else 0
	var best_idx: int = base + rng.randi_range(0, DESIGNS - 1)
	var best: int = 0
	for i in DESIGNS:
		var c: int = count(states, base + i)
		if c > best:
			best = c
			best_idx = base + i
	return [best_idx, best]


## `aNNW_trend_delete_cloth` / `_umbrella` (`mNpc_SetDefAnimalCloth` / `Umbrella`).
## Returns how many villagers changed back.
static func delete(states: Array, shop_idx: int) -> int:
	var n := 0
	var design: int = shop_idx & 3
	var umbrella: bool = (shop_idx & 7) >= DESIGNS
	for s: VillagerState in states:
		if s == null:
			continue
		if umbrella and s.umbrella_design == design:
			s.umbrella_design = -1
			n += 1
		elif not umbrella and s.cloth_design == design:
			s.cloth_design = -1
			n += 1
	return n


## Pick a reaction the way `aNPC_act_greeting_reaction` walks `react_rate_table`;
## -1 when the roll falls past the table.
static func roll_reaction(rng: RandomNumberGenerator) -> int:
	var rnd: float = rng.randf()
	for i in REACT_RATES.size():
		rnd -= REACT_RATES[i]
		if rnd < 0.0:
			return i
	return -1


## `aNPC_decide_AB_Actor`: A is the one the player is closer to; ties are a coin flip.
static func order_pair(x: VillagerState, y: VillagerState, rng: RandomNumberGenerator) -> Array:
	if x.friendship == y.friendship:
		return [x, y] if rng.randf() < 0.5 else [y, x]
	return [x, y] if x.friendship > y.friendship else [y, x]


## Apply one greeting reaction between A and B. `others` are the rest of the town, for
## `aNPC_copy_cloth`'s "pass it on to a neighbour" branch.
static func apply_reaction(react: int, a: VillagerState, b: VillagerState, others: Array,
		rng: RandomNumberGenerator) -> void:
	match react:
		React.CHG_SP_UMB:
			a.umbrella_design = _another_design(a.umbrella_design, rng)
		React.COPY_CLOTH:
			if b.cloth_design != a.cloth_design:
				b.cloth_design = a.cloth_design
			elif a.cloth_design >= 0:
				for o: VillagerState in others:
					if o != null and o != a and o != b and o.cloth_design != a.cloth_design:
						o.cloth_design = a.cloth_design
						break
		React.SET_CLOTH:
			a.cloth_design = -1  ## a new shop shirt from `mSP_SelectRandomItem_New`
		React.CHG_SP_CLOTH:
			a.cloth_design = _another_design(a.cloth_design, rng)
		React.RESET_CLOTH_AND_UMB:
			a.cloth_design = -1
			a.umbrella_design = -1


## One greeting between two villagers. Returns the reaction applied (or -1).
static func greet(x: VillagerState, y: VillagerState, others: Array, rng: RandomNumberGenerator) -> int:
	var react: int = roll_reaction(rng)
	if react < 0:
		return -1
	var ab: Array = order_pair(x, y, rng)
	apply_reaction(react, ab[0], ab[1], others, rng)
	return react


## Stand-in for a day of villagers greeting each other: every resident greets one
## random neighbour. Runs once per renewed day (capped).
static func daily_greetings(states: Array, rng: RandomNumberGenerator, days: int = 1) -> void:
	if states.size() < 2:
		return
	for _d in clampi(days, 1, MAX_CATCHUP_DAYS):
		for i in states.size():
			var j: int = rng.randi_range(0, states.size() - 2)
			if j >= i:
				j += 1
			greet(states[i], states[j], states, rng)


static func _another_design(current: int, rng: RandomNumberGenerator) -> int:
	var pick: int = rng.randi_range(0, DESIGNS - 1)
	if current >= 0:
		while pick == current:
			pick = rng.randi_range(0, DESIGNS - 1)
	return pick

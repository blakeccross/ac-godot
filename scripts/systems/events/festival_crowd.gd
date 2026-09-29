class_name FestivalCrowd
extends RefCounted

## Villagers who turn out for a festival (`mEv_EVENT_*` with `joint_npcs` in
## `m_event_map_npc_data.c_inc`): which actor family each map slot uses, what it does and
## what it says. The field copy of the villager is hidden while they are out
## (`mNpc_SetEventNpc` / `mNpc_GetSameEventNpc`).
##
## Talk is always `msg_base[looks] (+ slot * 3) + RANDOM(n)`; the bases are the actors'
## `set_talk_info` tables, in `mNpc_LOOKS_*` order (normal, peppy, lazy, jock, cranky, snooty,
## same as `VillagerPersonality.Looks`).

## Behaviour of a family (`think` procs):
## - `WANDER`: walks a short way from the spot, pauses, sometimes cheers (`aHN0_think_main_proc`).
## - `CYCLE`: stays put and loops through `clips` at random (`aHN1_setupAction`, `aHM0_…`).
enum Mode { WANDER, CYCLE }

## Family key → data:
## - `msg`: six bases by looks; `rand`: RANDOM(n); `step`: added per slot (× slot index);
## - `slot_from`: the actor id the slot index counts from (`npc_id - SP_NPC_EV_X_1`);
## - `mode`, `clips` (weights by entry count), `walk` (wander clip), `radius` (cells);
## - `alt`: another six bases used while `alt_event` is on (`mEv_EVENT_METEOR_SHOWER`).
const FAMILIES: Dictionary = {
	## `ac_hanabi_npc0`: wanders with a fan (`walk_ki1`, `utiwa_wait1`), cheering now and then.
	&"hanabi0": {
		"msg": [5711, 5726, 5696, 5741, 5756, 5771], "rand": 3, "step": 0,
		"mode": Mode.WANDER, "walk": "npc_1_walk_ki1", "clips": ["npc_1_utiwa_wait1", "npc_1_banzai1"],
		"radius": 2,
	},
	## `ac_hanabi_npc1`: stands and fans, claps and cheers (`aHN1_setupAction`).
	&"hanabi1": {
		"msg": [5714, 5729, 5699, 5744, 5759, 5774], "rand": 3, "step": 3, "slot_from": 1,
		"mode": Mode.CYCLE, "clips": ["npc_1_utiwa_wait1", "npc_1_utiwa_wait1", "npc_1_clap1", "npc_1_banzai1"],
	},
	## `ac_hanami_npc0`: sits on the mat, claps and drinks (odd slots hold a tumbler).
	&"hanami0": {
		"msg": [6445, 6460, 6430, 6475, 6490, 6505], "rand": 3, "step": 3,
		"mode": Mode.CYCLE, "clips": ["npc_1_sitdown_wait1", "npc_1_sitdown_wait1", "npc_1_sitdown_clap1", "npc_1_sitdown_drink1"],
	},
	## `ac_hanami_npc1`: dances around the mats.
	&"hanami1": {
		"msg": [6457, 6472, 6442, 6487, 6502, 6517], "rand": 3, "step": 0,
		"mode": Mode.WANDER, "walk": "npc_1_dance1", "clips": ["npc_1_dance1"], "radius": 2,
	},
	## `ac_tukimi_npc1`: moon viewing (or the meteor shower), eyeing the dumplings.
	&"tukimi1": {
		"msg": [0x1EB0, 0x1EBF, 0x1EA1, 0x1ECE, 0x1EDD, 0x1EEC], "rand": 3, "step": 3,
		"alt": [0x3F46, 0x3F55, 0x3F37, 0x3F64, 0x3F73, 0x3F82], "alt_event": &"meteor_shower",
		"mode": Mode.CYCLE, "clips": ["npc_1_wait1", "npc_1_wait1", "npc_1_kuisinbo1"],
	},
	## `ac_countdown_npc0/1`: party poppers ready (`term` 0 before the last minute).
	&"countdown": {
		"msg": [7528, 7549, 7507, 7570, 7591, 7612], "rand": 3, "step": 0,
		"mode": Mode.CYCLE, "clips": ["npc_1_cracker_wait1"],
	},
	## `ac_turi_npc0` (`aTR0_set_talk_info`): rod out by the pond.
	&"turi": {
		"msg": [0x1F0A, 0x1F19, 0x1EFB, 0x1F28, 0x1F37, 0x1F46], "rand": 3, "step": 3,
		"mode": Mode.CYCLE, "clips": ["npc_1_turi_wait1"],
	},
	## `ac_taisou_npc0`: the radio routine; slot 0 is Copper, 1–4 villagers
	## (`msg_base[event_type][looks] + RANDOM(2) + type * 3`).
	&"taisou": {
		"msg": [0x1A3C, 0x1A4B, 0x1A2D, 0x1A5A, 0x1A69, 0x1A78], "rand": 2, "step": 3,
		"alt": [0x1A96, 0x1AA5, 0x1A87, 0x1AB4, 0x1AC3, 0x1AD2], "alt_event": &"sports_fair_aerobics",
		"mode": Mode.CYCLE, "sequence": true,
		"clips": ["npc_1_taisou1", "npc_1_taisou2", "npc_1_taisou3_a", "npc_1_taisou3_b", "npc_1_taisou4_a",
			"npc_1_taisou4_b", "npc_1_taisou5_a", "npc_1_taisou5_b", "npc_1_taisou6_a", "npc_1_taisou6_b", "npc_1_taisou7"],
	},
	## `ac_tamaire_npc0/1`: ball toss (`base_msg + RANDOM(3)` between rounds).
	&"tamaire": {
		"msg": [7781, 7793, 7769, 7805, 7817, 7829], "rand": 3, "step": 0,
		"mode": Mode.CYCLE, "clips": ["npc_1_tamahiroi1", "npc_1_tamanage1", "npc_1_wait1"],
	},
	## `ac_tokyoso_npc0/1`: foot race runners at the line.
	&"tokyoso": {
		"msg": [6621, 6637, 6605, 6653, 6669, 6685], "rand": 2, "step": 0,
		"mode": Mode.CYCLE, "clips": ["npc_1_youi1", "npc_1_warmup1", "npc_1_wait1"],
	},
	## `ac_tunahiki_npc0/1`: tug-of-war (`base_msg + RANDOM(3)`).
	&"tunahiki": {
		"msg": [6532, 6544, 6520, 6556, 6568, 6580], "rand": 3, "step": 0,
		"mode": Mode.CYCLE, "clips": ["npc_1_tunahiki_yuri1", "npc_1_tunahiki_aiko1", "npc_1_tunahiki_furi1"],
	},
	## `ac_hatumode_npc0`: queueing at the shrine (`base_msg + 15 + RANDOM(3)` while waiting).
	&"hatumode": {
		"msg": [7679 + 15, 7697 + 15, 7661 + 15, 7715 + 15, 7733 + 15, 7751 + 15], "rand": 3, "step": 0,
		"mode": Mode.CYCLE, "clips": ["npc_1_wait1", "npc_1_wait1", "npc_1_omairi1"],
	},
	## `ac_harvest_npc0`: seated at the tables (`msg_base[looks] + id * 3 + RANDOM(3)`).
	&"harvest0": {
		"msg": [15512, 15543, 15419, 15450, 15481, 15574], "rand": 3, "step": 3,
		"mode": Mode.CYCLE, "clips": ["npc_1_sitdown_wait1", "npc_1_sitdown_wait1", "npc_1_sitdown_clap1"],
	},
	## `ac_harvest_npc1`: standing guest.
	&"harvest1": {
		"msg": [0x3CA4, 0x3CC3, 0x3C47, 0x3C66, 0x3C85, 0x3CE2], "rand": 3, "step": 0,
		"mode": Mode.CYCLE, "clips": ["npc_1_wait1", "npc_1_wait1", "npc_1_clap1"],
	},
	## `ac_groundhog_npc0`: listening to the speech (`now_term` 0 before it starts).
	&"groundhog": {
		"msg": [15698, 15729, 15605, 15636, 15667, 15760], "rand": 3, "step": 0,
		"mode": Mode.CYCLE, "clips": ["npc_1_wait1", "npc_1_wait1", "npc_1_clap1"],
	},
}

## `SP_NPC_EV_*` map actor → `[family, slot]` (the `ac_npc_ctrl` profile table).
const ACTORS: Dictionary = {
	"SP_NPC_EV_HANABI_0": [&"hanabi0", 0], "SP_NPC_EV_HANABI_1": [&"hanabi1", 1],
	"SP_NPC_EV_HANABI_2": [&"hanabi1", 2], "SP_NPC_EV_HANABI_3": [&"hanabi1", 3],
	"SP_NPC_EV_HANABI_4": [&"hanabi1", 4],
	"SP_NPC_EV_HANAMI_0": [&"hanami0", 0], "SP_NPC_EV_HANAMI_1": [&"hanami0", 1],
	"SP_NPC_EV_HANAMI_2": [&"hanami0", 2], "SP_NPC_EV_HANAMI_3": [&"hanami0", 3],
	"SP_NPC_EV_HANAMI_4": [&"hanami1", 4],
	"SP_NPC_EV_TUKIMI_0": [&"tukimi1", 0], "SP_NPC_EV_TUKIMI_1": [&"tukimi1", 1],
	"SP_NPC_EV_TUKIMI_2": [&"tukimi1", 2], "SP_NPC_EV_TUKIMI_3": [&"tukimi1", 3],
	"SP_NPC_EV_TUKIMI_4": [&"tukimi1", 4],
	"SP_NPC_EV_COUNTDOWN_0": [&"countdown", 0], "SP_NPC_EV_COUNTDOWN_1": [&"countdown", 1],
	"SP_NPC_EV_COUNTDOWN_2": [&"countdown", 2], "SP_NPC_EV_COUNTDOWN_3": [&"countdown", 3],
	"SP_NPC_EV_COUNTDOWN_4": [&"countdown", 4],
	"SP_NPC_EV_TURI_0": [&"turi", 0], "SP_NPC_EV_TURI_1": [&"turi", 1], "SP_NPC_EV_TURI_2": [&"turi", 2],
	"SP_NPC_EV_TURI_3": [&"turi", 3], "SP_NPC_EV_TURI_4": [&"turi", 4],
	"SP_NPC_EV_TAISOU_1": [&"taisou", 1], "SP_NPC_EV_TAISOU_2": [&"taisou", 2],
	"SP_NPC_EV_TAISOU_3": [&"taisou", 3], "SP_NPC_EV_TAISOU_4": [&"taisou", 4],
	"SP_NPC_EV_TAMAIRE_0": [&"tamaire", 0], "SP_NPC_EV_TAMAIRE_1": [&"tamaire", 1],
	"SP_NPC_EV_TAMAIRE_2": [&"tamaire", 2], "SP_NPC_EV_TAMAIRE_3": [&"tamaire", 3],
	"SP_NPC_EV_TAMAIRE_4": [&"tamaire", 4],
	"SP_NPC_EV_TOKYOSO_0": [&"tokyoso", 0], "SP_NPC_EV_TOKYOSO_1": [&"tokyoso", 1],
	"SP_NPC_EV_TOKYOSO_2": [&"tokyoso", 2], "SP_NPC_EV_TOKYOSO_3": [&"tokyoso", 3],
	"SP_NPC_EV_TOKYOSO_4": [&"tokyoso", 4],
	"SP_NPC_EV_TUNAHIKI_0": [&"tunahiki", 0], "SP_NPC_EV_TUNAHIKI_1": [&"tunahiki", 1],
	"SP_NPC_EV_TUNAHIKI_2": [&"tunahiki", 2], "SP_NPC_EV_TUNAHIKI_3": [&"tunahiki", 3],
	"SP_NPC_EV_TUNAHIKI_4": [&"tunahiki", 4],
	"SP_NPC_EV_HATUMODE_0": [&"hatumode", 0], "SP_NPC_EV_HATUMODE_1": [&"hatumode", 1],
	"SP_NPC_EV_HATUMODE_2": [&"hatumode", 2], "SP_NPC_EV_HATUMODE_3": [&"hatumode", 3],
	"SP_NPC_EV_HATUMODE_4": [&"hatumode", 4],
	"SP_NPC_EV_HARVEST_0": [&"harvest0", 0], "SP_NPC_EV_HARVEST_1": [&"harvest0", 1],
	"SP_NPC_EV_HARVEST_2": [&"harvest0", 2], "SP_NPC_EV_HARVEST_3": [&"harvest0", 3],
	"SP_NPC_EV_HARVEST_4": [&"harvest1", 4],
	"SP_NPC_EV_GROUNDHOG_0": [&"groundhog", 0], "SP_NPC_EV_GROUNDHOG_1": [&"groundhog", 1],
	"SP_NPC_EV_GROUNDHOG_2": [&"groundhog", 2], "SP_NPC_EV_GROUNDHOG_3": [&"groundhog", 3],
}

## Festival props (`STRUCTURE_START + n` in the map) → model and footprint in cells.
const PROPS: Dictionary = {
	"FIREWORKS_STALL0": ["obj_e_yatai_l", Vector2i(3, 2)],
	"FIREWORKS_STALL1": ["obj_e_yatai_r", Vector2i(3, 2)],
	"SAKURA_TABLE0": ["obj_e_hanami_a", Vector2i(2, 2)],
	"SAKURA_TABLE1": ["obj_e_hanami_b", Vector2i(2, 2)],
	"AEROBICS_RADIO": ["obj_e_radio", Vector2i(1, 1)],
	"NEWYEAR_COUNTDOWN0": ["obj_e_count01", Vector2i(2, 1)],
	"NEWYEAR_COUNTDOWN1": ["obj_e_count02_cl", Vector2i(2, 1)],
	"SPORTSFAIR_BASKET_RED": ["obj_e_kago_r", Vector2i(1, 1)],
	"SPORTSFAIR_BASKET_WHITE": ["obj_e_kago_w", Vector2i(1, 1)],
	"FISHCHECK_STAND0": ["obj_e_turi_l", Vector2i(2, 1)],
	"FISHCHECK_STAND1": ["obj_e_turi_r", Vector2i(2, 1)],
	"GHOG": ["obj_e_ghog", Vector2i(1, 1)],
	"HTABLE0": ["obj_e_hfes_a", Vector2i(2, 2)],
	"HTABLE1": ["obj_e_hfes_b", Vector2i(2, 2)],
	"HTABLE2": ["obj_e_hfes_c", Vector2i(2, 2)],
}


static func family_of(actor: String) -> StringName:
	var entry: Array = ACTORS.get(actor, [])
	return entry[0] if not entry.is_empty() else &""


static func slot_of(actor: String) -> int:
	var entry: Array = ACTORS.get(actor, [])
	return int(entry[1]) if not entry.is_empty() else 0


## `set_talk_info`: the message for a villager of `looks` in `slot`.
static func talk_msg(family: StringName, looks: int, slot: int, rng: RandomNumberGenerator, alt: bool = false) -> int:
	var data: Dictionary = FAMILIES.get(family, {})
	if data.is_empty():
		return -1
	var bases: Array = data["alt"] if alt and data.has("alt") else data["msg"]
	var base: int = int(bases[clampi(looks, 0, bases.size() - 1)])
	var step: int = int(data.get("step", 0)) * (slot - int(data.get("slot_from", 0)))
	var n: int = maxi(1, int(data.get("rand", 1)))
	return base + step + (rng.randi_range(0, n - 1) if rng != null else 0)


## `mEvMN_GetNpcIdxRandom`: residents the player knows come first, the rest fill in; the
## draw is fixed for the day so a reload shows the same faces.
static func pick_villagers(residents: Array[StringName], count: int, seed_text: String, known: Callable = Callable()) -> Array[StringName]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_text.hash()
	var first: Array[StringName] = []
	var rest: Array[StringName] = []
	for id: StringName in residents:
		if known.is_valid() and bool(known.call(id)):
			first.append(id)
		else:
			rest.append(id)
	_shuffle(first, rng)
	_shuffle(rest, rng)
	var out: Array[StringName] = []
	for id: StringName in first + rest:
		if out.size() >= count:
			break
		out.append(id)
	return out


static func _shuffle(list: Array[StringName], rng: RandomNumberGenerator) -> void:
	for i: int in range(list.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: StringName = list[i]
		list[i] = list[j]
		list[j] = tmp

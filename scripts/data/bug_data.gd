class_name BugData
extends ItemData

## Catchable bug. Months are 1–12. Hours use the original's six insect terms
## (`aSOI_TERM0`–`aSOI_TERM5`), not a free window, because that is the only
## resolution the spawn tables have.

## `aINS_PROGRAM_*` from `ac_insect_h.h`, in decomp order. Drives movement AI: each
## value selects a `BugProgram` subclass under `scripts/systems/bugs/`.
enum Program {
	CHOU,		## butterflies (`ac_ins_chou.c`)
	BATTA,		## locusts / crickets / grasshopper (`ac_ins_batta.c`)
	TONBO,		## dragonflies (`ac_ins_tonbo.c`)
	TENTOU,		## ladybugs / mantis / snail (`ac_ins_tentou.c`)
	HOTARU,		## firefly (`ac_ins_hotaru.c`)
	SEMI,		## cicadas / bee (`ac_ins_semi.c`)
	KABUTO,		## beetles (`ac_ins_kabuto.c`)
	GOKI,		## cockroach (`ac_ins_goki.c`)
	HITODAMA,	## spirit / Wisp (`ac_ins_hitodama.c`)
	AMENBO,		## pond skater (`ac_ins_amenbo.c`)
	KA,			## mosquito (`ac_ins_ka.c`)
	DANGO,		## pill bug / ant (`ac_ins_dango.c`)
	KERA,		## mole cricket (`ac_ins_kera.c`)
	MINO,		## bagworm / spider (`ac_ins_mino.c`)
}

## `aINS_program_type[]` (`ac_insect_data.c_inc`): the program each `type_index`
## (`aINS_INSECT_TYPE_*`, 0..39, then SPIRIT=40) runs. This table is authoritative —
## `program` authored on a `.tres` is overwritten from it on load.
const PROGRAM_FOR_TYPE: Array[int] = [
	Program.CHOU, Program.CHOU, Program.CHOU, Program.CHOU,          ## 0-3   butterflies
	Program.SEMI, Program.SEMI, Program.SEMI, Program.SEMI, Program.SEMI,  ## 4-8  cicadas + bee
	Program.TONBO, Program.TONBO, Program.TONBO, Program.TONBO,      ## 9-12  dragonflies
	Program.BATTA, Program.BATTA, Program.BATTA, Program.BATTA, Program.BATTA, Program.BATTA,  ## 13-18 locusts/crickets
	Program.KABUTO, Program.KABUTO, Program.KABUTO, Program.KABUTO, Program.KABUTO,  ## 19-23 beetles
	Program.TENTOU, Program.TENTOU, Program.TENTOU,                  ## 24-26 ladybug, spotted, mantis
	Program.HOTARU,                                                  ## 27    firefly
	Program.GOKI,                                                    ## 28    cockroach
	Program.KABUTO, Program.KABUTO, Program.KABUTO,                  ## 29-31 saw/mountain/giant beetle
	Program.TENTOU,                                                  ## 32    snail
	Program.KERA,                                                    ## 33    mole cricket
	Program.AMENBO,                                                  ## 34    pond skater
	Program.MINO,                                                    ## 35    bagworm
	Program.DANGO,                                                   ## 36    pill bug
	Program.MINO,                                                    ## 37    spider
	Program.DANGO,                                                   ## 38    ant
	Program.KA,                                                      ## 39    mosquito
	Program.HITODAMA,                                                ## 40    spirit (aINS_INSECT_TYPE_SPIRIT)
]


static func program_for_type(type_idx: int) -> Program:
	if type_idx < 0 or type_idx >= PROGRAM_FOR_TYPE.size():
		return Program.CHOU
	return PROGRAM_FOR_TYPE[type_idx] as Program

## `aSOI_SPAWN_AREA_*`. Where this species can appear.
enum Habitat {
	FLOWER,
	TREE,
	RAIN_FLOWER,
	FLYING,
	GROUND,
	BUSH,
	NEAR_WATER,
	WATER,
	ROCK,
	UNDERGROUND,
}

## `aSOI_TERM0`–`aSOI_TERM5`. Hour buckets from `ac_set_ovl_insect.h`.
enum TimeTerm { T0, T1, T2, T3, T4, T5 }

const TERM_HOURS := {
	TimeTerm.T0: Vector2i(23, 4),
	TimeTerm.T1: Vector2i(4, 8),
	TimeTerm.T2: Vector2i(8, 16),
	TimeTerm.T3: Vector2i(16, 17),
	TimeTerm.T4: Vector2i(17, 19),
	TimeTerm.T5: Vector2i(19, 23),
}

## Decomp type index (`aINS_INSECT_TYPE_*`). Used for catch messages and spawn tables.
@export var type_index: int = 0
## Empty means every month.
@export var months: PackedInt32Array = PackedInt32Array()
## `TimeTerm` values. Empty means all six.
@export var time_terms: PackedInt32Array = PackedInt32Array()
## `Habitat` values. Empty means any habitat.
@export var habitats: PackedInt32Array = PackedInt32Array()
## Snail and similar: only while it rains (`aSOI_SPAWN_AREA_RAINING_ON_FLOWER`).
@export var needs_rain: bool = false
## Relative pick weight among bugs available at this month/term/habitat.
@export var rarity_weight: int = 10
## `Player_actor_Get_mushi_msg_num`: `0xA2C + type` below type 0x20, else `0x2FA1 + type`.
@export var catch_msg: int = 0
## Display list base under `assets/generated/creatures/bug/`. Pose suffix `_a` / `_b`.
@export var model_base: String = ""
## Wing-flap cadence: 1 fast, 2 slow, 0 still.
@export var model_flap: int = 0
## Y nudge before draw, in GX.
@export var model_lift: float = 0.0
## Movement program. Authored value is a fallback — `BugCatalog` overwrites it from
## `PROGRAM_FOR_TYPE[type_index]` (the decomp `aINS_program_type[]` table) on load.
@export var program: Program = Program.CHOU

## Pose A/B cadence for field and held insects (30 Hz hold table).
const POSE_FLAP_HZ := 30.0
const POSE_FLAP_FAST: Array[int] = [0, 0, 0, 0, 1, 1, 0, 0]
const POSE_FLAP_SLOW: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0]


func model_pose(pose: StringName) -> String:
	if model_base.is_empty():
		return ""
	return "%s_%s.glb" % [model_base, pose]


static func pose_pattern(flap: int) -> Array[int]:
	match flap:
		1:
			return POSE_FLAP_FAST.duplicate()
		2:
			return POSE_FLAP_SLOW.duplicate()
		_:
			return [0]


func _init() -> void:
	category = Category.BUG


## `aSOI_insect_time_no` / `aSOI_hour_to_term`: 11PM–3:59AM T0, 4–7 T1, 8–3PM T2,
## 4PM T3, 5–6PM T4, 7–10PM T5.
static func term_for_hour(p_hour: int) -> TimeTerm:
	var h: int = posmod(p_hour, 24)
	if h <= 3 or h >= 23:
		return TimeTerm.T0
	if h <= 7:
		return TimeTerm.T1
	if h <= 15:
		return TimeTerm.T2
	if h <= 16:
		return TimeTerm.T3
	if h <= 18:
		return TimeTerm.T4
	return TimeTerm.T5


## `aSOI_SPAWN_AREA_*` from `ac_set_ovl_insect.h` → actor habitat after placement.
static func habitat_from_spawn_area(spawn_area: int, prefer_flower: bool = true) -> Habitat:
	match spawn_area:
		0:
			return Habitat.TREE
		1:
			return Habitat.FLOWER
		2:
			return Habitat.RAIN_FLOWER
		3:
			return Habitat.FLYING
		4:
			return Habitat.GROUND
		5:
			return Habitat.BUSH
		6:
			return Habitat.NEAR_WATER
		7:
			return Habitat.WATER
		8:
			return Habitat.ROCK
		9:
			return Habitat.UNDERGROUND
		12:
			return Habitat.FLOWER if prefer_flower else Habitat.FLYING
		_:
			return Habitat.FLYING


static func catch_msg_for_type(type_idx: int) -> int:
	if type_idx < 0x20:
		return 0xA2C + type_idx
	return 0x2FA1 + type_idx


func in_habitat(kind: int) -> bool:
	return habitats.is_empty() or kind in habitats


func is_available(p_month: int, p_hour: int) -> bool:
	if needs_rain:
		return false
	if not months.is_empty() and not (p_month in months):
		return false
	return time_terms.is_empty() or int(term_for_hour(p_hour)) in time_terms


func is_available_now() -> bool:
	return is_available(Clock.month, Clock.hour)
